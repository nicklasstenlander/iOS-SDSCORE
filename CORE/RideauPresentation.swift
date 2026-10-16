import Foundation

nonisolated enum RideauPricing {
    static func priceText(for event: RideauEvent) -> String? {
        let hasFreeTickets = !event.freeTicketNames.isEmpty

        if event.toPriceOreKeyPresent {
            guard let to = event.toPriceOre else {
                return hasFreeTickets ? "Gratis" : nil
            }
            if to == 0 { return "Gratis" }
            let low = hasFreeTickets ? 0 : event.fromPriceOre
            guard let low else { return formatKr(to) }
            return low == to ? formatKr(low) : "\(amount(low))–\(amount(to)) kr"
        }

        if let from = event.fromPriceOre {
            return "Från \(formatKr(from))"
        }
        return hasFreeTickets ? "Gratis" : nil
    }

    /// Bara i fallback-läget (äldre server utan `to_price_ore`) — en rad per
    /// gratis biljettyp, t.ex. "Barn 0-3 år: gratis".
    static func freeTicketFallbackLines(for event: RideauEvent) -> [String]? {
        guard !event.toPriceOreKeyPresent,
              event.fromPriceOre != nil,
              !event.freeTicketNames.isEmpty else {
            return nil
        }
        return event.freeTicketNames.map { "\($0): gratis" }
    }

    static func spokenPriceText(for event: RideauEvent) -> String? {
        let hasFreeTickets = !event.freeTicketNames.isEmpty

        if event.toPriceOreKeyPresent {
            guard let to = event.toPriceOre else {
                return hasFreeTickets ? "Gratis" : nil
            }
            if to == 0 { return "Gratis" }
            let low = hasFreeTickets ? 0 : event.fromPriceOre
            guard let low else { return "\(amount(to)) kronor" }
            return low == to ? "\(amount(low)) kronor" : "\(amount(low)) till \(amount(to)) kronor"
        }

        if let from = event.fromPriceOre {
            return "från \(amount(from)) kronor"
        }
        return hasFreeTickets ? "Gratis" : nil
    }

    private static func amount(_ ore: Int) -> Int { ore / 100 }
    private static func formatKr(_ ore: Int) -> String { "\(amount(ore)) kr" }
}

nonisolated enum RideauDateFormatting {
    private static let weekdayNames = ["Sön", "Mån", "Tis", "Ons", "Tor", "Fre", "Lör"]
    private static let monthNames = [
        "jan", "feb", "mar", "apr", "maj", "jun",
        "jul", "aug", "sep", "okt", "nov", "dec"
    ]
    private static let fullWeekdayNames = [
        "söndag", "måndag", "tisdag", "onsdag", "torsdag", "fredag", "lördag"
    ]
    private static let fullMonthNames = [
        "januari", "februari", "mars", "april", "maj", "juni",
        "juli", "augusti", "september", "oktober", "november", "december"
    ]

    /// "Lör 5 dec kl. 13:00" — alltid Europe/Stockholm, oavsett enhetens tidszon.
    static func displayText(for isoString: String) -> String? {
        guard let date = RideauISO8601.parse(isoString) else { return nil }
        let c = ScheduleService.stockholmCalendar.dateComponents(
            [.weekday, .day, .month, .hour, .minute], from: date
        )
        guard let weekday = c.weekday, let day = c.day, let month = c.month,
              let hour = c.hour, let minute = c.minute else { return nil }
        return String(
            format: "%@ %d %@ kl. %02d:%02d",
            weekdayNames[weekday - 1], day, monthNames[month - 1], hour, minute
        )
    }

    /// "lördag 5 december klockan 13" — för VoiceOver.
    static func spokenText(for isoString: String) -> String? {
        guard let date = RideauISO8601.parse(isoString) else { return nil }
        let c = ScheduleService.stockholmCalendar.dateComponents(
            [.weekday, .day, .month, .hour], from: date
        )
        guard let weekday = c.weekday, let day = c.day, let month = c.month,
              let hour = c.hour else { return nil }
        return "\(fullWeekdayNames[weekday - 1]) \(day) \(fullMonthNames[month - 1]) klockan \(hour)"
    }
}

nonisolated enum RideauCountdown {
    /// "om 2 d 4 h" / "om 3 min 12 s" sista timmen. `clockSkew` är server
    /// minus enhet, så en enhet som går fel åt något håll räknas rätt.
    static func text(salesOpenAt: Date, now: Date, clockSkew: TimeInterval) -> String {
        let adjustedNow = now.addingTimeInterval(clockSkew)
        let remaining = salesOpenAt.timeIntervalSince(adjustedNow)
        guard remaining > 0 else { return "" }

        if remaining < 3600 {
            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60
            return "om \(minutes) min \(seconds) s"
        }

        let totalHours = Int(remaining) / 3600
        let days = totalHours / 24
        let hours = totalHours % 24
        return days > 0 ? "om \(days) d \(hours) h" : "om \(hours) h"
    }
}

nonisolated enum RideauStatus {
    static func buttonTitle(for state: RideauSalesState) -> String? {
        switch state {
        case .upcoming: "Visa föreställning"
        case .open: "Köp biljetter"
        case .soldOut, .unknown: nil
        }
    }

    static func statusText(for state: RideauSalesState) -> String? {
        switch state {
        case .soldOut: "Slutsålt"
        case .upcoming, .open, .unknown: nil
        }
    }
}
