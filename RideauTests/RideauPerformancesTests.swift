import Testing
import Foundation
@testable import CORE

private final class RideauTestsBundleMarker {}

private func loadFixtureResponse() throws -> RideauEventsResponse {
    let bundle = Bundle(for: RideauTestsBundleMarker.self)
    let url = bundle.url(forResource: "public-embed.example", withExtension: "json")!
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(RideauEventsResponse.self, from: data)
}

private func fixtureEvent(slug: String) throws -> RideauEvent {
    let response = try loadFixtureResponse()
    return try #require(response.events.first { $0.slug == slug })
}

// MARK: - Avkodning

@Suite("Avkodning av public-embed-svaret")
struct RideauDecodingTests {
    @Test("Hela fixturen avkodas utan fel, fem event + server_time")
    func decodesFixture() throws {
        let response = try loadFixtureResponse()
        #expect(response.events.count == 5)
        #expect(response.serverTime == "2026-10-10T12:00:00.000Z")
    }

    @Test("Okänt sales_state mappas till .unknown")
    func unknownSalesStateMapsToUnknown() throws {
        let json = """
        {"slug":"x","title":"X","starts_at":"2027-01-01T00:00:00Z","purchase_url":"https://x","sales_state":"paused","free_ticket_names":[]}
        """.data(using: .utf8)!
        let event = try JSONDecoder().decode(RideauEvent.self, from: json)
        #expect(event.salesState == .unknown)
    }

    @Test("Saknade valfria fält avkodas utan fel (decodeIfPresent)")
    func missingOptionalFieldsDecodeCleanly() throws {
        let json = """
        {"slug":"minimal","title":"Minimal","starts_at":"2027-01-01T00:00:00Z","purchase_url":"https://x","sales_state":"open"}
        """.data(using: .utf8)!
        let event = try JSONDecoder().decode(RideauEvent.self, from: json)
        #expect(event.venue == nil)
        #expect(event.fromPriceOre == nil)
        #expect(event.toPriceOre == nil)
        #expect(event.toPriceOreKeyPresent == false)
        #expect(event.freeTicketNames.isEmpty)
        #expect(event.posterUrl == nil)
    }

    @Test("to_price_ore: null särskiljs från att nyckeln saknas helt")
    func explicitNullToPriceOreIsDistinctFromMissingKey() throws {
        let event = try fixtureEvent(slug: "ny-produktion-utan-biljetter")
        #expect(event.toPriceOreKeyPresent == true)
        #expect(event.toPriceOre == nil)
    }
}

// MARK: - Datumformat (Europe/Stockholm)

@Suite("Datumformat i Europe/Stockholm")
struct RideauDateFormattingTests {
    @Test("Visningstext byggs i Stockholms tidszon, inte UTC")
    func displayTextUsesStockholmTime() {
        // 2027-05-10T17:00:00Z är sommartid i Stockholm => 19:00 lokalt.
        let text = RideauDateFormatting.displayText(for: "2027-05-10T17:00:00Z")
        #expect(text?.contains("kl. 19:00") == true)
    }

    @Test("Vintertidens start (25 okt) hanteras korrekt över DST-gränsen")
    func handlesDaylightSavingTransition() {
        // Före övergången (01:00 UTC): Stockholm är fortfarande CEST (+2).
        let beforeTransition = RideauDateFormatting.displayText(for: "2026-10-24T22:00:00Z")
        #expect(beforeTransition?.contains("kl. 00:00") == true)

        // Efter övergången: Stockholm är CET (+1).
        let afterTransition = RideauDateFormatting.displayText(for: "2026-10-25T10:00:00Z")
        #expect(afterTransition?.contains("kl. 11:00") == true)
    }

    @Test("Talad datumtext är fullt utskriven")
    func spokenTextIsFullyWritten() {
        let text = RideauDateFormatting.spokenText(for: "2027-05-10T17:00:00Z")
        #expect(text?.contains("klockan 19") == true)
    }
}

// MARK: - Nedräkning

@Suite("Nedräkning mot sales_open_at")
struct RideauCountdownTests {
    @Test("Nedräkning i minuter sista timmen")
    func countdownUnderAnHour() {
        let now = Date()
        let opensAt = now.addingTimeInterval(192) // 3 min 12 s
        let text = RideauCountdown.text(salesOpenAt: opensAt, now: now, clockSkew: 0)
        #expect(text == "om 3 min 12 s")
    }

    @Test("Nedräkning i dagar och timmar")
    func countdownOverADay() {
        let now = Date()
        let opensAt = now.addingTimeInterval(2 * 86400 + 4 * 3600)
        let text = RideauCountdown.text(salesOpenAt: opensAt, now: now, clockSkew: 0)
        #expect(text == "om 2 d 4 h")
    }

    @Test("Klockskillnad på enheten (+5 min) korrigeras")
    func clockSkewDeviceAhead() {
        let trueNow = Date()
        let deviceNow = trueNow.addingTimeInterval(300) // enheten går 5 min före
        let opensAt = trueNow.addingTimeInterval(60) // servern: 1 minut kvar i verklig tid
        // Utan korrigering (opensAt - deviceNow = -240 s) skulle knappen visas för tidigt.
        let text = RideauCountdown.text(salesOpenAt: opensAt, now: deviceNow, clockSkew: -300)
        #expect(text == "om 1 min 0 s")
    }

    @Test("Klockskillnad på enheten (-5 min) korrigeras")
    func clockSkewDeviceBehind() {
        let now = Date()
        let opensAt = now.addingTimeInterval(-60) // redan öppet enligt servern
        // Enheten går 5 min efter => utan korrigering skulle den tro att tid kvarstår.
        let text = RideauCountdown.text(salesOpenAt: opensAt, now: now, clockSkew: 300)
        #expect(text == "")
    }
}

// MARK: - sales_state → text/knapp

@Suite("sales_state-mappning")
struct RideauStatusTests {
    @Test("upcoming visar 'Visa föreställning'")
    func upcomingButton() {
        #expect(RideauStatus.buttonTitle(for: .upcoming) == "Visa föreställning")
        #expect(RideauStatus.statusText(for: .upcoming) == nil)
    }

    @Test("open visar 'Köp biljetter'")
    func openButton() {
        #expect(RideauStatus.buttonTitle(for: .open) == "Köp biljetter")
    }

    @Test("sold_out visar 'Slutsålt' utan knapp")
    func soldOutHasNoButton() {
        #expect(RideauStatus.buttonTitle(for: .soldOut) == nil)
        #expect(RideauStatus.statusText(for: .soldOut) == "Slutsålt")
    }

    @Test("unknown visas neutralt utan knapp")
    func unknownHasNoButton() {
        #expect(RideauStatus.buttonTitle(for: .unknown) == nil)
        #expect(RideauStatus.statusText(for: .unknown) == nil)
    }
}

// MARK: - priceText

@Suite("priceText")
struct RideauPricingTests {
    @Test("Intervall med gratistyp: lägsta blir 0 trots att from_price_ore är satt")
    func intervalWithFreeTicketType() throws {
        let event = try fixtureEvent(slug: "test-slapp")
        #expect(RideauPricing.priceText(for: event) == "0–295 kr")
    }

    @Test("Intervall utan gratistyper")
    func intervalWithoutFreeTickets() throws {
        let event = try fixtureEvent(slug: "varshow-2027")
        #expect(RideauPricing.priceText(for: event) == "150–250 kr")
    }

    @Test("Lägsta = högsta visar ett enda pris")
    func sameHighAndLow() throws {
        let event = try fixtureEvent(slug: "hostshow-2026")
        #expect(RideauPricing.priceText(for: event) == "200 kr")
    }

    @Test("Inget pris när eventet saknar biljettyper helt")
    func noTicketTypesShowsNoPrice() throws {
        let event = try fixtureEvent(slug: "ny-produktion-utan-biljetter")
        #expect(RideauPricing.priceText(for: event) == nil)
    }

    @Test("Bara gratistyper (to_price_ore = 0) visar 'Gratis'")
    func allFreeShowsGratis() throws {
        let event = try fixtureEvent(slug: "oppet-hus-gratis")
        #expect(RideauPricing.priceText(for: event) == "Gratis")
    }

    @Test("Fallback utan to_price_ore visar 'Från X kr' plus en gratisrad per typ")
    func legacyFallbackWithoutToPriceOre() {
        let event = RideauEvent(
            slug: "legacy",
            title: "Legacy",
            startsAt: "2027-01-01T00:00:00Z",
            purchaseUrl: "https://x",
            salesState: .open,
            fromPriceOre: 15000,
            toPriceOreKeyPresent: false,
            freeTicketNames: ["Barn 0-3 år"]
        )
        #expect(RideauPricing.priceText(for: event) == "Från 150 kr")
        #expect(RideauPricing.freeTicketFallbackLines(for: event) == ["Barn 0-3 år: gratis"])
    }
}

// MARK: - Flikens synlighetsregel

@Suite("Flikens synlighetsregel")
struct RideauVisibilityTests {
    @Test("Dold tills minst ett event har hämtats")
    @MainActor
    func hiddenUntilEventsExist() {
        let service = RideauEventsService()
        #expect(service.isVisible == false)

        service.events = [
            RideauEvent(
                slug: "x", title: "X", startsAt: "2027-01-01T00:00:00Z",
                purchaseUrl: "https://x", salesState: .open
            )
        ]
        #expect(service.isVisible == true)
    }
}

// MARK: - app_destination-parsning

@Suite("HomeCardDestination.parse")
struct HomeCardDestinationTests {
    @Test("forestallningar leder till Föreställningar-fliken")
    func performancesDestination() {
        #expect(HomeCardDestination.parse("forestallningar") == .performances)
    }

    @Test("event:<slug> leder till en specifik föreställning")
    func specificPerformanceDestination() {
        #expect(HomeCardDestination.parse("event:around-the-world") == .performanceSlug("around-the-world"))
    }

    @Test("Befintliga värden fortsätter fungera")
    func existingDestinationsStillWork() {
        #expect(HomeCardDestination.parse("kurser") == .courses)
        #expect(HomeCardDestination.parse("schema") == .schedule)
        #expect(HomeCardDestination.parse("course:42") == .course(42))
        #expect(HomeCardDestination.parse(nil) == .none)
        #expect(HomeCardDestination.parse("") == .none)
    }
}

// MARK: - Konfiguration (RIDEAU_API_BASE)

@Suite("RideauConfig")
struct RideauConfigTests {
    @Test("Reservvärde används när Info.plist-värdet är tomt")
    func fallsBackWhenValueIsEmpty() {
        let base = RideauConfig.apiBase(infoDictionary: ["RideauAPIBase": ""])
        #expect(URL(string: base)?.scheme == "https")
    }

    @Test("Reservvärde används när nyckeln saknas helt")
    func fallsBackWhenKeyIsMissing() {
        let base = RideauConfig.apiBase(infoDictionary: [:])
        #expect(URL(string: base)?.scheme == "https")
        let organizer = RideauConfig.organizer(infoDictionary: [:])
        #expect(organizer.isEmpty == false)
    }

    @Test("RideauAPIBase i den byggda appens Info.plist är en giltig https-URL")
    func apiBaseInBuiltAppIsValidHTTPSURL() {
        let base = RideauConfig.apiBase(infoDictionary: Bundle.main.infoDictionary)
        #expect(URL(string: base)?.scheme == "https")
    }
}
