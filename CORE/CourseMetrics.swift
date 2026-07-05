import Foundation

struct CourseMetrics {
    var registered = 0
    var accepted = 0
    var revenue: Double = 0
    var price: Double?
}

enum CourseMetricsEngine {
    static func bookingEventId(_ booking: Booking) -> String {
        booking.event?.id.map(String.init) ?? ""
    }

    static func eventId(_ event: Event) -> String {
        String(event.id)
    }

    static func isAcceptedBooking(_ booking: Booking) -> Bool {
        booking.status?.code?.uppercased() == "ACCEPTED"
    }

    static func countBookingsByParticipant(_ bookings: [Booking]) -> [String: Int] {
        var canonicalKeyOf: [String: String] = [:]
        var keyByNameAndBirth: [String: String] = [:]

        for booking in bookings {
            guard let key = booking.participant?.key, canonicalKeyOf[key] == nil else { continue }

            let name = booking.participant?.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let dateOfBirth = booking.participant?.dateOfBirth
            guard let name, !name.isEmpty, let dateOfBirth else {
                canonicalKeyOf[key] = key
                continue
            }

            let identity = "\(name)|\(dateOfBirth)"
            if let existingKey = keyByNameAndBirth[identity] {
                canonicalKeyOf[key] = existingKey
            } else {
                keyByNameAndBirth[identity] = key
                canonicalKeyOf[key] = key
            }
        }

        var countByCanonicalKey: [String: Int] = [:]
        for booking in bookings {
            guard let key = booking.participant?.key else { continue }
            let canonicalKey = canonicalKeyOf[key] ?? key
            countByCanonicalKey[canonicalKey, default: 0] += 1
        }

        var countByParticipant: [String: Int] = [:]
        for (key, canonicalKey) in canonicalKeyOf {
            countByParticipant[key] = countByCanonicalKey[canonicalKey] ?? 0
        }

        return countByParticipant
    }

    static func isNewStudentBooking(_ booking: Booking, countByParticipant: [String: Int]) -> Bool {
        guard let key = booking.participant?.key else { return false }
        return countByParticipant[key] == 1
    }

    static func bookingTicketQuantity(_ booking: Booking) -> Int {
        if let structuredQuantity = ticketQuantityFromFormResponses(booking) {
            return structuredQuantity
        }

        return ticketQuantityFromSummary(booking.regFormResponse?.textSummary) ?? 1
    }

    static func buildCourseMetrics(bookings: [Booking]) -> [String: CourseMetrics] {
        var metrics: [String: CourseMetrics] = [:]
        var priceCounts: [String: [Int: Int]] = [:]

        for booking in bookings {
            let id = bookingEventId(booking)
            guard !id.isEmpty else { continue }

            let quantity = bookingTicketQuantity(booking)
            var current = metrics[id] ?? CourseMetrics()
            current.registered += quantity

            if let price = booking.payment?.priceAgreed {
                let unitPrice = quantity > 0 ? Int((price / Double(quantity)).rounded()) : Int(price)
                priceCounts[id, default: [:]][unitPrice, default: 0] += quantity
            }

            if isAcceptedBooking(booking) {
                current.accepted += quantity
                current.revenue += booking.payment?.priceAgreed ?? 0
            }

            metrics[id] = current
        }

        for (id, counts) in priceCounts {
            guard var current = metrics[id],
                  let mostCommonPrice = counts.sorted(by: { $0.value == $1.value ? $0.key > $1.key : $0.value > $1.value }).first?.key else {
                continue
            }
            current.price = Double(mostCommonPrice)
            metrics[id] = current
        }

        return metrics
    }

    static func metrics(for event: Event, in metrics: [String: CourseMetrics], fallbackToEventStatistics: Bool = true) -> CourseMetrics {
        if let fromBookings = metrics[eventId(event)] { return fromBookings }
        guard fallbackToEventStatistics else { return CourseMetrics() }

        let accepted = event.statistics?.accepted ?? 0
        let price = event.pricing?.basePriceInclVat
        return CourseMetrics(
            registered: accepted,
            accepted: accepted,
            revenue: Double(accepted) * (price ?? 0),
            price: price
        )
    }

    private static func ticketQuantityFromFormResponses(_ booking: Booking) -> Int? {
        let responses = booking.formResponses ?? []
        for response in responses.reversed() {
            var total = 0
            var foundTicketQuestion = false

            for question in response.answeredQuestions ?? [] {
                guard isTicketQuantityQuestion(question.questionTitle) else { continue }
                foundTicketQuestion = true
                let answers = question.answers ?? [:]
                for answer in answers.values {
                    total += parseQuantityAnswer(answer)
                }
            }

            if foundTicketQuestion { return total > 0 ? total : nil }
        }

        return nil
    }

    private static func ticketQuantityFromSummary(_ summary: String?) -> Int? {
        guard let summary else { return nil }

        let lines = summary.components(separatedBy: .newlines)
        var total = 0
        var foundTicketLine = false
        var currentLineIsTicketQuantity = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if isTicketQuantityQuestion(trimmed) {
                currentLineIsTicketQuantity = true
                continue
            }

            if currentLineIsTicketQuantity {
                total += parseQuantityAnswer(.string(trimmed.replacingOccurrences(of: #"^-\s*"#, with: "", options: .regularExpression)))
                foundTicketLine = true
                currentLineIsTicketQuantity = false
            }
        }

        return foundTicketLine && total > 0 ? total : nil
    }

    private static func isTicketQuantityQuestion(_ title: String?) -> Bool {
        let normalized = title?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !normalized.isEmpty else { return false }
        if normalized.contains("biljett") { return true }
        return normalized.range(of: #"^antal\s+(barn|vuxen|vuxna|ungdom|ungdomar|student|studenter|senior|seniorer|pensionär|pensionärer)\b"#, options: .regularExpression) != nil
    }

    private static func parseQuantityAnswer(_ answer: FlexibleValue) -> Int {
        switch answer {
        case .number(let value):
            return value.isFinite && value > 0 ? Int(value) : 0
        default:
            let text = answer.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = text.prefix { $0.isNumber }
            return Int(prefix) ?? 0
        }
    }
}
