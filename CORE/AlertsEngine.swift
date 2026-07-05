import Foundation

enum AlertType: Hashable {
    case duplicate
    case pending
}

struct BookingAlert: Identifiable {
    let booking: Booking
    let type: AlertType
    let count: Int

    var id: String {
        "\(booking.key)-\(type)"
    }
}

struct AlertsResult {
    let alerts: [BookingAlert]
    let duplicateCount: Int
    let pendingCount: Int
}

enum AlertsEngine {
    private static let excludedDuplicateGroupIds: Set<Int> = [18358]
    private static let pendingStatusCodes: Set<String> = ["NEW"]

    static func buildAlerts(allBookings: [Booking], duplicateBookings: [Booking] = [], events: [Event] = []) -> AlertsResult {
        var seen = Set<String>()
        var result: [BookingAlert] = []
        let excludedEventIds = Set(events.compactMap { event -> Int? in
            guard let groupId = event.grouping?.primaryEventGroup?.id?.intValue,
                  excludedDuplicateGroupIds.contains(groupId) else { return nil }
            return event.id
        })

        let grouped = Dictionary(grouping: duplicateBookings) { booking in
            let participantKey = booking.participant?.key ?? booking.participant?.id.map(String.init) ?? ""
            let eventId = booking.event?.id.map(String.init) ?? ""
            return "\(participantKey)::\(eventId)"
        }

        var seenParticipants = Set<String>()
        for groupBookings in grouped.values where groupBookings.count > 1 {
            guard let first = groupBookings.first else { continue }
            let code = first.event?.code?.lowercased() ?? ""
            if code.contains("forestallning") || first.event?.id.map({ excludedEventIds.contains($0) }) == true {
                continue
            }

            let participantKey = first.participant?.key ?? first.participant?.id.map(String.init) ?? ""
            guard !participantKey.isEmpty, !seenParticipants.contains(participantKey), !seen.contains(first.key) else {
                continue
            }

            seenParticipants.insert(participantKey)
            seen.insert(first.key)
            result.append(BookingAlert(booking: first, type: .duplicate, count: groupBookings.count))
        }

        for booking in allBookings {
            let code = booking.status?.code?.uppercased() ?? ""
            if pendingStatusCodes.contains(code), !seen.contains(booking.key) {
                seen.insert(booking.key)
                result.append(BookingAlert(booking: booking, type: .pending, count: 1))
            }
        }

        return AlertsResult(
            alerts: result,
            duplicateCount: result.filter { $0.type == .duplicate }.count,
            pendingCount: result.filter { $0.type == .pending }.count
        )
    }
}
