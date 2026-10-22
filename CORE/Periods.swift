import Foundation

struct Period: Hashable, Identifiable, Sendable {
    let displayName: String
    let eventBlockId: String?
    let codePrefix: String?

    nonisolated var id: String {
        codePrefix ?? "alla"
    }

    nonisolated static func == (lhs: Period, rhs: Period) -> Bool {
        lhs.displayName == rhs.displayName
            && lhs.eventBlockId == rhs.eventBlockId
            && lhs.codePrefix == rhs.codePrefix
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(displayName)
        hasher.combine(eventBlockId)
        hasher.combine(codePrefix)
    }
}

enum Periods {
    nonisolated static let all = Period(displayName: "Alla terminer", eventBlockId: nil, codePrefix: nil)
    nonisolated static let spring2026 = Period(displayName: "Vårterminen 2026", eventBlockId: "18402", codePrefix: "VT26")
    nonisolated static let fall2026 = Period(displayName: "Höstterminen 2026", eventBlockId: "19459", codePrefix: "HT26")
    nonisolated static let fall2025 = Period(displayName: "Höstterminen 2025", eventBlockId: "17665", codePrefix: "HT25")
    nonisolated static let spring2027 = Period(displayName: "Vårterminen 2027", eventBlockId: "20430", codePrefix: "VT27")
    nonisolated static let available = [all, spring2027, fall2026, spring2026, fall2025]

    nonisolated static let eventBlockIdsByCode: [String: String] = [
        "HT25": "17665",
        "VT26": "18402",
        "HT26": "19459",
        "VT27": "20430"
    ]

    nonisolated static func defaultPeriod(date: Date = Date(), in periods: [Period] = available) -> Period {
        let code = defaultPeriodCode(date: date)
        return periods.first { $0.codePrefix == code } ?? all
    }

    private nonisolated static func defaultPeriodCode(date: Date) -> String {
        let year = Calendar.current.component(.year, from: date) % 100
        let month = Calendar.current.component(.month, from: date)
        let term = month < 7 ? "VT" : "HT"
        return String(format: "%@%02d", term, year)
    }

    nonisolated static func matches(_ event: Event, period: Period) -> Bool {
        guard period != all else { return true }

        let eventBlockId = event.grouping?.eventBlock?.id?.stringValue
        if let selectedId = period.eventBlockId, let eventBlockId, eventBlockId == selectedId {
            return true
        }

        guard let codePrefix = period.codePrefix else { return false }

        return matchesPeriodCode(codePrefix, values: [
            event.code,
            event.schedule?.start?.date,
            event.grouping?.eventBlock?.name,
        ])
    }

    /// Matchar en bokning mot en period via `eventBlockIdLookup` (kurs-id/-nyckel -> termins eventBlockId),
    /// uppslagen från den fullständiga eventlistan (type=all). Bokningens egen `event.grouping.eventBlock`
    /// skickas aldrig av CogWork i /bookings-svaret, så den går inte att lita på här. Kodprefix/datum
    /// används bara som reservlösning när bokningens kurs saknas i eventlistan.
    nonisolated static func matches(_ booking: Booking, period: Period, eventBlockIdLookup: [String: String]) -> Bool {
        guard period != all else { return true }

        let bookingKeys = [booking.event?.id.map(String.init), booking.event?.key].compactMap { $0 }
        if let resolvedEventBlockId = bookingKeys.compactMap({ eventBlockIdLookup[$0] }).first {
            return period.eventBlockId != nil && resolvedEventBlockId == period.eventBlockId
        }

        guard let codePrefix = period.codePrefix else { return false }
        let eventCode = booking.event?.code?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return eventCode?.hasPrefix(codePrefix.uppercased()) == true
    }

    /// Bygger en uppslagning kurs-id/-nyckel -> termins eventBlockId utifrån den fullständiga eventlistan.
    /// Använder i första hand grouping.eventBlock.id, annars det id i additionalEventGroups som är en känd
    /// termin (jämfört som strängar, eftersom eventBlock.id är ett tal men additionalEventGroups[].id en sträng).
    nonisolated static func eventBlockIdLookup(events: [Event], knownEventBlockIds: Set<String>) -> [String: String] {
        var lookup: [String: String] = [:]
        for event in events {
            guard let blockId = resolvedEventBlockId(for: event, knownEventBlockIds: knownEventBlockIds) else { continue }
            lookup[String(event.id)] = blockId
            if let key = event.key, !key.isEmpty {
                lookup[key] = blockId
            }
        }
        return lookup
    }

    private nonisolated static func resolvedEventBlockId(for event: Event, knownEventBlockIds: Set<String>) -> String? {
        if let blockId = event.grouping?.eventBlock?.id?.stringValue {
            return blockId
        }
        return event.grouping?.additionalEventGroups?.first { group in
            guard let id = group.id?.stringValue else { return false }
            return knownEventBlockIds.contains(id)
        }?.id?.stringValue
    }

    /// Slår samman den fasta terminslistan med terminer från workerns `?type=terms`. CogWork slutar lista
    /// kurser från avslutade terminer, och workern lär sig nya terminer automatiskt — unionen säkerställer
    /// att båda källornas terminer finns kvar. Dedupliceras på eventBlockId och codePrefix; vid krock vinner
    /// den fasta listan.
    nonisolated static func mergedPeriods(
        fixed: [Period],
        dynamicBlocks: [(name: String, eventBlockId: String, code: String?)]
    ) -> [Period] {
        var seenEventBlockIds = Set<String>()
        var seenCodePrefixes = Set<String>()
        var merged: [Period] = []

        func add(_ period: Period) {
            if let id = period.eventBlockId, seenEventBlockIds.contains(id) { return }
            if let code = period.codePrefix, seenCodePrefixes.contains(code) { return }
            if let id = period.eventBlockId { seenEventBlockIds.insert(id) }
            if let code = period.codePrefix { seenCodePrefixes.insert(code) }
            merged.append(period)
        }

        for period in fixed where period != all {
            add(period)
        }

        for block in dynamicBlocks {
            guard !block.eventBlockId.isEmpty else { continue }

            let code: String
            if let providedCode = block.code?.uppercased(), isPeriodCode(providedCode) {
                code = providedCode
            } else {
                code = blockNameToCode(block.name).uppercased()
            }
            guard isPeriodCode(code) else { continue }

            add(Period(displayName: blockNameToFullLabel(block.name), eventBlockId: block.eventBlockId, codePrefix: code))
        }

        let order = sortPeriodCodes(merged.compactMap(\.codePrefix))
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let sorted = merged.sorted { lhs, rhs in
            guard let left = lhs.codePrefix.flatMap({ rank[$0] }),
                  let right = rhs.codePrefix.flatMap({ rank[$0] }) else { return false }
            return left < right
        }

        return [all] + sorted
    }

    nonisolated static func defaultEventBlockId(date: Date = Date()) -> String {
        let year = Calendar.current.component(.year, from: date) % 100
        let month = Calendar.current.component(.month, from: date)
        let term = month < 7 ? "VT" : "HT"
        return eventBlockIdsByCode[String(format: "%@%02d", term, year)] ?? ""
    }

    nonisolated static func defaultFullPeriodLabel(date: Date = Date()) -> String {
        let year = Calendar.current.component(.year, from: date)
        let month = Calendar.current.component(.month, from: date)
        return month < 7 ? "Vårterminen \(year)" : "Höstterminen \(year)"
    }

    nonisolated static func blockNameToCode(_ name: String) -> String {
        if let year = firstYear(in: name, prefixes: ["Höst", "höst"]) {
            return "HT\(String(year.suffix(2)))"
        }

        if let year = firstYear(in: name, prefixes: ["Vår", "vår"]) {
            return "VT\(String(year.suffix(2)))"
        }

        return name
    }

    nonisolated static func blockNameToFullLabel(_ name: String) -> String {
        if let year = firstYear(in: name, prefixes: ["Höst", "höst"]) {
            return "Höstterminen \(year)"
        }

        if let year = firstYear(in: name, prefixes: ["Vår", "vår"]) {
            return "Vårterminen \(year)"
        }

        return name
    }

    nonisolated static func codeToLabel(_ code: String) -> String {
        guard code.count == 4 else { return code }
        let term = String(code.prefix(2))
        let year = String(code.suffix(2))
        guard term == "HT" || term == "VT", Int(year) != nil else { return code }
        return "\(term) 20\(year)"
    }

    nonisolated static func isPeriodCode(_ value: String) -> Bool {
        value.range(of: #"^(HT|VT)\d{2}$"#, options: .regularExpression) != nil
    }

    nonisolated static func dateToPeriodCode(_ date: String?) -> String {
        guard let date, date.count >= 7 else { return "" }
        let year = String(date.prefix(4))
        let monthText = String(date.dropFirst(5).prefix(2))
        guard year.range(of: #"^\d{4}$"#, options: .regularExpression) != nil,
              let month = Int(monthText) else { return "" }
        return "\(month >= 7 ? "HT" : "VT")\(year.suffix(2))"
    }

    nonisolated static func matchesPeriodCode(_ code: String, values: [String?]) -> Bool {
        let normalizedCode = code.uppercased()
        return values.contains { value in
            guard let value else { return false }
            let normalizedValue = value.uppercased()
            return normalizedValue.contains(normalizedCode) || dateToPeriodCode(value) == normalizedCode
        }
    }

    nonisolated static func sortPeriodCodes(_ codes: [String]) -> [String] {
        codes.sorted { lhs, rhs in
            guard let left = parsePeriod(lhs), let right = parsePeriod(rhs) else { return lhs > rhs }
            if left.year != right.year { return left.year > right.year }
            return termRank(left.term) > termRank(right.term)
        }
    }

    // HT (höst) ligger senare på året än VT (vår), så vid "nyast först" inom samma år ska HT före VT.
    private nonisolated static func termRank(_ term: String) -> Int {
        term == "HT" ? 1 : 0
    }

    private nonisolated static func parsePeriod(_ code: String) -> (term: String, year: Int)? {
        guard isPeriodCode(code) else { return nil }
        let term = String(code.prefix(2))
        let year = Int(code.suffix(2)) ?? 0
        return (term, year)
    }

    private nonisolated static func firstYear(in value: String, prefixes: [String]) -> String? {
        for prefix in prefixes {
            let pattern = #"\#(prefix)(en|terminen)?\s+(\d{4})"#
            if let range = value.range(of: pattern, options: .regularExpression) {
                let match = String(value[range])
                return match.split(separator: " ").last.map(String.init)
            }
        }

        return nil
    }
}
