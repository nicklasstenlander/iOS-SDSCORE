import Testing
import Foundation
@testable import CORE

@Suite("Periods: sortering och kodtolkning")
struct PeriodsSortingTests {
    @Test("sortPeriodCodes sorterar nyast först, HT före VT inom samma år")
    func sortPeriodCodesOrdersNewestFirstWithHTBeforeVT() {
        let input = ["VT26", "HT26", "VT27", "HT25"]
        let sorted = Periods.sortPeriodCodes(input)
        #expect(sorted == ["VT27", "HT26", "VT26", "HT25"])
    }

    @Test("blockNameToCode hanterar formen '<Höst/Vår>terminen <år>'")
    func blockNameToCodeHandlesTerminenSuffix() {
        #expect(Periods.blockNameToCode("Vårterminen 2027") == "VT27")
        #expect(Periods.blockNameToCode("Höstterminen 2026") == "HT26")
        #expect(Periods.blockNameToCode("Sommarkurser") == "Sommarkurser")
    }
}

@Suite("Periods: union och deduplicering av terminer")
struct PeriodsMergeTests {
    @Test("mergedPeriods dedupliceras på eventBlockId/codePrefix, fast lista vinner, icke-terminer utesluts")
    func mergedPeriodsDedupesAndSorts() {
        let dynamicBlocks: [(name: String, eventBlockId: String, code: String?)] = [
            (name: "Höstterminen 2026", eventBlockId: "19459", code: "HT26"), // dubblett av fast HT26
            (name: "Vårterminen 2028", eventBlockId: "99999", code: nil), // ny, okänd termin
            (name: "Sommarkurser", eventBlockId: "11111", code: nil) // inte en termin
        ]

        let merged = Periods.mergedPeriods(fixed: Periods.available, dynamicBlocks: dynamicBlocks)

        #expect(merged.first == Periods.all)
        #expect(merged.filter { $0.eventBlockId == "19459" }.count == 1)
        #expect(merged.first { $0.eventBlockId == "19459" } == Periods.fall2026)
        #expect(!merged.contains { $0.eventBlockId == "11111" })
        #expect(merged.contains { $0.codePrefix == "VT28" && $0.eventBlockId == "99999" })
        // "Alla terminer" ligger först, sedan nyast-först — VT28 (2028) är nyast.
        #expect(merged.dropFirst().first?.codePrefix == "VT28")
    }
}

@Suite("Periods: bokningar matchas mot rätt termin via eventlistan")
struct PeriodsBookingMatchTests {
    private static let knownEventBlockIds: Set<String> = ["17665", "18402", "19459", "20430"]

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("En bokning vars kurs ligger i HT26-blocket men har VT26-kod hamnar i HT26, inte VT26")
    func bookingWithMismatchedCodeMatchesActualTermFromEventList() throws {
        // Motsvarar VT26-DANCECAMP_SOMMAR_26_COPY (Sommarläger v.33): koden pekar på VT26, men den
        // fullständiga eventlistan (type=all) visar att CogWork har lagt kursen i HT26-blocket.
        // Bokningens egen nästlade event.grouping saknar det här fältet — därför måste uppslagningen
        // komma från den fullständiga eventlistan, inte från booking.event direkt.
        let event = try decode(Event.self, """
        {
            "id": 500,
            "code": "VT26-DANCECAMP_SOMMAR_26_COPY",
            "name": "Sommarläger v.33",
            "grouping": {
                "eventBlock": { "id": 19459, "name": "Höstterminen 2026" }
            }
        }
        """)

        let booking = try decode(Booking.self, """
        {
            "id": 1,
            "key": "booking-1",
            "created": "2026-05-01T10:00:00Z",
            "event": { "id": 500, "code": "VT26-DANCECAMP_SOMMAR_26_COPY" }
        }
        """)

        let lookup = Periods.eventBlockIdLookup(events: [event], knownEventBlockIds: Self.knownEventBlockIds)
        #expect(lookup["500"] == "19459")

        #expect(Periods.matches(booking, period: Periods.fall2026, eventBlockIdLookup: lookup) == true)
        #expect(Periods.matches(booking, period: Periods.spring2026, eventBlockIdLookup: lookup) == false)
    }

    @Test("Saknas eventBlock helt tas det kända termins-id:t ur additionalEventGroups (Danskalas-fallet)")
    func eventMissingEventBlockFallsBackToAdditionalEventGroups() throws {
        // Danskalas (260274) saknar grouping.eventBlock men har VT26 i additionalEventGroups.
        let event = try decode(Event.self, """
        {
            "id": 260274,
            "code": "DANSKALAS",
            "grouping": {
                "additionalEventGroups": [ { "id": "18402", "name": "Vårterminen 2026" } ]
            }
        }
        """)

        let lookup = Periods.eventBlockIdLookup(events: [event], knownEventBlockIds: Self.knownEventBlockIds)
        #expect(lookup["260274"] == "18402")
    }

    @Test("Saknas kursen i eventlistan faller matchningen tillbaka på kodprefix")
    func bookingMissingFromEventListFallsBackToCodePrefix() throws {
        let booking = try decode(Booking.self, """
        {
            "id": 2,
            "key": "booking-2",
            "created": "2026-05-01T10:00:00Z",
            "event": { "id": 999, "code": "VT26-OKAND_KURS" }
        }
        """)

        let lookup = Periods.eventBlockIdLookup(events: [], knownEventBlockIds: Self.knownEventBlockIds)

        #expect(Periods.matches(booking, period: Periods.spring2026, eventBlockIdLookup: lookup) == true)
        #expect(Periods.matches(booking, period: Periods.fall2026, eventBlockIdLookup: lookup) == false)
    }
}

@Suite("Periods: publik katalog visar nästa termin när anmälan öppnar")
struct PeriodsPublicCatalogTests {
    private func event(_ id: Int, block: Int, name: String, start: String, open: Bool) throws -> Event {
        let json = """
        {"id": \(id), "registration": {"open": \(open), "showing": true},
         "schedule": {"start": {"date": "\(start)"}},
         "grouping": {"eventBlock": {"id": \(block), "name": "\(name)"}}}
        """
        return try JSONDecoder().decode(Event.self, from: Data(json.utf8))
    }

    @Test("bara innevarande termin: inget val, den terminen visas")
    func onlyCurrentTerm() throws {
        let events = [try event(1, block: 19459, name: "Höstterminen 2026", start: "2026-08-31", open: true)]
        #expect(Periods.publicTerms(events: events).map(\.id) == ["19459"])
        #expect(Periods.defaultPublicTermID(events: events) == "19459")
    }

    @Test("VT27 öppen för anmälan (16 nov): VT27 är förvald, HT26 finns kvar som val, äldst först")
    func upcomingTermOpenIsDefault() throws {
        let events = [
            try event(1, block: 20430, name: "Vårterminen 2027", start: "2027-01-11", open: true),
            try event(2, block: 19459, name: "Höstterminen 2026", start: "2026-08-31", open: false),
            try event(3, block: 19459, name: "Höstterminen 2026", start: "2026-09-01", open: true),
        ]
        #expect(Periods.publicTerms(events: events).map(\.name) == ["Höstterminen 2026", "Vårterminen 2027"])
        #expect(Periods.defaultPublicTermID(events: events) == "20430")
    }

    @Test("VT27 synlig men anmälan stängd: innevarande termin med öppen anmälan förvald")
    func upcomingTermNotYetOpen() throws {
        let events = [
            try event(1, block: 20430, name: "Vårterminen 2027", start: "2027-01-11", open: false),
            try event(2, block: 19459, name: "Höstterminen 2026", start: "2026-08-31", open: true),
        ]
        #expect(Periods.defaultPublicTermID(events: events) == "19459")
    }

    @Test("ingen öppen anmälan alls: senaste terminen")
    func noOpenRegistration() throws {
        let events = [
            try event(1, block: 20430, name: "Vårterminen 2027", start: "2027-01-11", open: false),
            try event(2, block: 19459, name: "Höstterminen 2026", start: "2026-08-31", open: false),
        ]
        #expect(Periods.defaultPublicTermID(events: events) == "20430")
    }
}
