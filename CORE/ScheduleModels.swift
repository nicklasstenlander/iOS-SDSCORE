import Foundation

struct ScheduleEvent: Codable, Identifiable, Equatable {
    let eventId: String
    let eventCwId: String
    let name: String
    let time: String
    let dayStr: String
    let instructors: String
    let place: String
    let showing: Bool
    // participants intentionally omitted — field contains personnummer (PII)

    var id: String { eventId }
}
