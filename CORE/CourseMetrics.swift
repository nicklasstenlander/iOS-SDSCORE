import Foundation

struct CourseMetrics {
    var registered = 0
    var accepted = 0
    var revenue: Double = 0
    var price: Double?

    nonisolated init(registered: Int = 0, accepted: Int = 0, revenue: Double = 0, price: Double? = nil) {
        self.registered = registered
        self.accepted = accepted
        self.revenue = revenue
        self.price = price
    }
}

struct ParticipantCourseChange: Hashable {
    let previousCourseNames: [String]

    var badgeText: String {
        "Bytt från \(previousCourseNames.joined(separator: ", "))"
    }
}

enum CourseMetricsEngine {
    nonisolated static func isPerformance(event: Event?) -> Bool {
        guard let event else { return false }

        if isPerformanceName(event.grouping?.primaryEventGroup?.name) {
            return true
        }

        if isPerformanceName(event.category?.name) {
            return true
        }

        return containsPerformanceKeyword(event.code) || containsPerformanceKeyword(event.name)
    }

    nonisolated static func isPerformance(booking: Booking) -> Bool {
        if isPerformanceName(booking.event?.category?.name) {
            return true
        }

        return containsPerformanceKeyword(booking.event?.code) || containsPerformanceKeyword(booking.event?.name)
    }

    nonisolated static func isPerformance(booking: Booking, eventLookup: [String: Event]) -> Bool {
        if let event = fullEvent(for: booking, eventLookup: eventLookup),
           isPerformance(event: event) {
            return true
        }

        return isPerformance(booking: booking)
    }

    nonisolated static func isStatisticalBooking(_ booking: Booking) -> Bool {
        !isPerformance(booking: booking)
    }

    nonisolated static func isStatisticalBooking(_ booking: Booking, eventLookup: [String: Event]) -> Bool {
        !isPerformance(booking: booking, eventLookup: eventLookup)
    }

    nonisolated static func isStatisticalEvent(_ event: Event) -> Bool {
        !isPerformance(event: event)
    }

    nonisolated static func bookingEventId(_ booking: Booking) -> String {
        booking.event?.id.map(String.init) ?? ""
    }

    nonisolated static func eventId(_ event: Event) -> String {
        String(event.id)
    }

    nonisolated static func isAcceptedBooking(_ booking: Booking) -> Bool {
        booking.status?.code?.uppercased() == "ACCEPTED"
    }

    nonisolated static func countBookingsByParticipant(_ bookings: [Booking]) -> [String: Int] {
        let statisticalBookings = bookings.filter { isStatisticalBooking($0) }
        let canonicalKeyOf = canonicalParticipantKeys(for: statisticalBookings)
        var countByCanonicalKey: [String: Int] = [:]

        for booking in statisticalBookings {
            guard let canonicalKey = canonicalParticipantKey(for: booking, lookup: canonicalKeyOf) else { continue }
            countByCanonicalKey[canonicalKey, default: 0] += 1
        }

        var countByParticipant: [String: Int] = [:]
        for booking in statisticalBookings {
            guard let participantKey = participantIdentifier(for: booking),
                  let canonicalKey = canonicalParticipantKey(for: booking, lookup: canonicalKeyOf) else {
                continue
            }
            countByParticipant[participantKey] = countByCanonicalKey[canonicalKey] ?? 0
        }

        return countByParticipant
    }

    nonisolated static func countBookingsByParticipant(_ bookings: [Booking], eventLookup: [String: Event]) -> [String: Int] {
        countBookingsByParticipant(bookings.filter { isStatisticalBooking($0, eventLookup: eventLookup) })
    }

    nonisolated static func isNewStudentBooking(_ booking: Booking, countByParticipant: [String: Int]) -> Bool {
        guard isStatisticalBooking(booking) else { return false }
        guard let participantKey = participantIdentifier(for: booking) else { return false }
        return countByParticipant[participantKey] == 1
    }

    nonisolated static func courseChangesByParticipant(bookings: [Booking], currentPeriodCode: String?) -> [String: ParticipantCourseChange] {
        guard let currentPeriodCode,
              let previousPeriodCode = previousPeriodCode(for: currentPeriodCode) else {
            return [:]
        }

        let statisticalBookings = bookings.filter { isStatisticalBooking($0) }
        let canonicalKeyOf = canonicalParticipantKeys(for: statisticalBookings)
        var currentCoursesByParticipant: [String: Set<String>] = [:]
        var previousCoursesByParticipant: [String: [(normalized: String, original: String)]] = [:]

        for booking in statisticalBookings {
            guard let canonicalKey = canonicalParticipantKey(for: booking, lookup: canonicalKeyOf),
                  let periodCode = periodCode(for: booking),
                  let courseName = booking.event?.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !courseName.isEmpty else {
                continue
            }

            let normalizedName = normalizedCourseName(courseName)
            guard !normalizedName.isEmpty else { continue }

            if periodCode == currentPeriodCode {
                currentCoursesByParticipant[canonicalKey, default: []].insert(normalizedName)
            } else if periodCode == previousPeriodCode {
                previousCoursesByParticipant[canonicalKey, default: []].append((normalizedName, courseName))
            }
        }

        var changesByCanonicalKey: [String: ParticipantCourseChange] = [:]
        for (canonicalKey, currentCourses) in currentCoursesByParticipant {
            guard let previousCourses = previousCoursesByParticipant[canonicalKey], !previousCourses.isEmpty else {
                continue
            }

            let previousNormalizedNames = Set(previousCourses.map(\.normalized))
            guard currentCourses.isDisjoint(with: previousNormalizedNames) else { continue }

            let originalNames = uniqueOriginalCourseNames(previousCourses)
            guard !originalNames.isEmpty else { continue }
            changesByCanonicalKey[canonicalKey] = ParticipantCourseChange(previousCourseNames: originalNames)
        }

        var result: [String: ParticipantCourseChange] = [:]
        for booking in statisticalBookings {
            guard let participantKey = participantIdentifier(for: booking),
                  let canonicalKey = canonicalParticipantKey(for: booking, lookup: canonicalKeyOf),
                  let change = changesByCanonicalKey[canonicalKey] else {
                continue
            }
            result[participantKey] = change
        }

        return result
    }

    nonisolated static func courseChangesByParticipant(
        bookings: [Booking],
        currentPeriodCode: String?,
        eventLookup: [String: Event]
    ) -> [String: ParticipantCourseChange] {
        courseChangesByParticipant(
            bookings: bookings.filter { isStatisticalBooking($0, eventLookup: eventLookup) },
            currentPeriodCode: currentPeriodCode
        )
    }

    nonisolated static func courseChange(for booking: Booking, changesByParticipant: [String: ParticipantCourseChange]) -> ParticipantCourseChange? {
        guard isStatisticalBooking(booking) else { return nil }
        guard let participantKey = participantIdentifier(for: booking) else { return nil }
        return changesByParticipant[participantKey]
    }

    nonisolated static func canonicalParticipantKeys(for bookings: [Booking]) -> [String: String] {
        var canonicalKeyOf: [String: String] = [:]
        var keyByNameAndBirth: [String: String] = [:]

        for booking in bookings {
            guard let key = participantIdentifier(for: booking), canonicalKeyOf[key] == nil else { continue }

            guard let identity = nameAndBirthIdentity(for: booking) else {
                canonicalKeyOf[key] = key
                continue
            }

            if let existingKey = keyByNameAndBirth[identity] {
                canonicalKeyOf[key] = existingKey
            } else {
                keyByNameAndBirth[identity] = key
                canonicalKeyOf[key] = key
            }
        }

        return canonicalKeyOf
    }

    nonisolated static func bookingTicketQuantity(_ booking: Booking) -> Int {
        if let structuredQuantity = ticketQuantityFromFormResponses(booking) {
            return structuredQuantity
        }

        return ticketQuantityFromSummary(booking.regFormResponse?.textSummary) ?? 1
    }

    nonisolated static func buildCourseMetrics(bookings: [Booking]) -> [String: CourseMetrics] {
        var metrics: [String: CourseMetrics] = [:]
        var priceCounts: [String: [Int: Int]] = [:]

        for booking in bookings where isStatisticalBooking(booking) {
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

    nonisolated static func metrics(for event: Event, in metrics: [String: CourseMetrics], fallbackToEventStatistics: Bool = true) -> CourseMetrics {
        guard isStatisticalEvent(event) else { return CourseMetrics() }
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

    private nonisolated static func ticketQuantityFromFormResponses(_ booking: Booking) -> Int? {
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

    private nonisolated static func ticketQuantityFromSummary(_ summary: String?) -> Int? {
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

    private nonisolated static func isTicketQuantityQuestion(_ title: String?) -> Bool {
        let normalized = title?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !normalized.isEmpty else { return false }
        if normalized.contains("biljett") { return true }
        return normalized.range(of: #"^antal\s+(barn|vuxen|vuxna|ungdom|ungdomar|student|studenter|senior|seniorer|pensionär|pensionärer)\b"#, options: .regularExpression) != nil
    }

    private nonisolated static func parseQuantityAnswer(_ answer: FlexibleValue) -> Int {
        switch answer {
        case .number(let value):
            return value.isFinite && value > 0 ? Int(value) : 0
        default:
            let text = answer.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = text.prefix { $0.isNumber }
            return Int(prefix) ?? 0
        }
    }

    private nonisolated static func isPerformanceName(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "föreställningar"
    }

    private nonisolated static func containsPerformanceKeyword(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("föreställning") || normalized.contains("forestallning")
    }

    private nonisolated static func fullEvent(for booking: Booking, eventLookup: [String: Event]) -> Event? {
        [booking.event?.id.map(String.init), booking.event?.key]
            .compactMap { $0 }
            .compactMap { eventLookup[$0] }
            .first
    }

    private nonisolated static func canonicalParticipantKey(for booking: Booking, lookup: [String: String]) -> String? {
        guard let key = participantIdentifier(for: booking) else { return nil }
        return lookup[key] ?? key
    }

    private nonisolated static func participantIdentifier(for booking: Booking) -> String? {
        if let key = booking.participant?.key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }

        return nameAndBirthIdentity(for: booking).map { "nameDob:\($0)" }
    }

    private nonisolated static func nameAndBirthIdentity(for booking: Booking) -> String? {
        guard let rawName = booking.participant?.name,
              let rawDateOfBirth = booking.participant?.dateOfBirth else {
            return nil
        }

        let name = rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let dateOfBirth = rawDateOfBirth.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !dateOfBirth.isEmpty else {
            return nil
        }

        return "\(collapsedWhitespace(name))|\(dateOfBirth)"
    }

    private nonisolated static func periodCode(for booking: Booking) -> String? {
        let eventCode = booking.event?.code?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if let eventCode, eventCode.range(of: #"^(HT|VT)\d{2}"#, options: .regularExpression) != nil {
            return String(eventCode.prefix(4))
        }

        let eventBlockName = booking.event?.grouping?.eventBlock?.name
        if let eventBlockName {
            let blockCode = Periods.blockNameToCode(eventBlockName).uppercased()
            if Periods.isPeriodCode(blockCode) {
                return blockCode
            }
        }

        for dateValue in [booking.event?.startDateTime, booking.event?.startDate, booking.created] {
            let code = Periods.dateToPeriodCode(dateValue)
            if !code.isEmpty { return code }
        }

        return nil
    }

    private nonisolated static func previousPeriodCode(for code: String) -> String? {
        guard Periods.isPeriodCode(code) else { return nil }
        let term = String(code.prefix(2))
        guard let year = Int(code.suffix(2)) else { return nil }

        if term == "HT" {
            return String(format: "VT%02d", year)
        }

        return String(format: "HT%02d", (year + 99) % 100)
    }

    private nonisolated static func normalizedCourseName(_ value: String) -> String {
        collapsedWhitespace(value.trimmingCharacters(in: .whitespacesAndNewlines)).lowercased()
    }

    private nonisolated static func collapsedWhitespace(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        var lastWasSpace = false
        for char in value {
            if char.isWhitespace {
                if !lastWasSpace { result.append(" ") }
                lastWasSpace = true
            } else {
                result.append(char)
                lastWasSpace = false
            }
        }
        return result
    }

    private nonisolated static func uniqueOriginalCourseNames(_ values: [(normalized: String, original: String)]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values {
            guard !seen.contains(value.normalized) else { continue }
            seen.insert(value.normalized)
            result.append(value.original)
        }

        return result
    }
}
