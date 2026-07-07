import Foundation
import Combine

struct TelavoxCall: Decodable, Identifiable {
    enum Direction: String, Decodable, CaseIterable {
        case incoming
        case outgoing
        case missed
    }

    let datetime: String
    let dateTimeISO: String?
    let duration: Int
    let number: String
    let callId: String?
    let numberE164: String?
    let recordingId: String?
    var direction: Direction = .incoming

    var id: String {
        callId ?? "\(direction.rawValue)-\(datetime)-\(number)"
    }

    var startDate: Date? {
        guard let dateTimeISO else { return nil }
        return TelavoxCall.isoFormatter.date(from: dateTimeISO)
    }

    enum CodingKeys: String, CodingKey {
        case datetime
        case dateTimeISO
        case legacyDatetimeISO = "datetimeISO"
        case duration
        case number
        case callId
        case numberE164
        case recordingId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        datetime = try container.decode(String.self, forKey: .datetime)
        dateTimeISO = try container.decodeIfPresent(String.self, forKey: .dateTimeISO)
            ?? container.decodeIfPresent(String.self, forKey: .legacyDatetimeISO)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        number = try container.decode(String.self, forKey: .number)
        callId = try container.decodeIfPresent(String.self, forKey: .callId)
        numberE164 = try container.decodeIfPresent(String.self, forKey: .numberE164)
        recordingId = try container.decodeIfPresent(String.self, forKey: .recordingId)
    }

    init(
        datetime: String,
        dateTimeISO: String?,
        duration: Int,
        number: String,
        callId: String?,
        numberE164: String?,
        recordingId: String?,
        direction: Direction
    ) {
        self.datetime = datetime
        self.dateTimeISO = dateTimeISO
        self.duration = duration
        self.number = number
        self.callId = callId
        self.numberE164 = numberE164
        self.recordingId = recordingId
        self.direction = direction
    }

    func withDirection(_ direction: Direction) -> TelavoxCall {
        TelavoxCall(
            datetime: datetime,
            dateTimeISO: dateTimeISO,
            duration: duration,
            number: number,
            callId: callId,
            numberE164: numberE164,
            recordingId: recordingId,
            direction: direction
        )
    }

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }()
}

struct TelavoxCallsResponse: Decodable {
    let incoming: [TelavoxCall]
    let outgoing: [TelavoxCall]
    let missed: [TelavoxCall]
}

struct ParticipantCallInfo: Hashable {
    let name: String
    let courses: [String]
}

enum SDSPhoneNumbers {
    static let groupSender = "0850278989"

    static func lookupKey(_ number: String) -> String {
        var normalized = number.filter(\.isNumber)
        if normalized.hasPrefix("46") {
            normalized.removeFirst(2)
            normalized = "0" + normalized
        }
        return normalized
    }

    static func e164Digits(_ number: String) -> Int64? {
        var digits = number.filter(\.isNumber)
        if digits.hasPrefix("00") {
            digits.removeFirst(2)
        }
        if digits.hasPrefix("0") {
            digits.removeFirst()
            digits = "46" + digits
        }
        guard digits.hasPrefix("46"), digits.count >= 10 else { return nil }
        return Int64(digits)
    }

    static func participantLookup(for bookings: [Booking]) -> [String: ParticipantCallInfo] {
        var participantByPhone: [String: Booking] = [:]
        var participantKeyByPhone: [String: String] = [:]

        for booking in bookings {
            let phones = participantPhoneNumbers(in: booking)
            for phone in phones {
                let key = lookupKey(phone)
                guard !key.isEmpty, participantByPhone[key] == nil else { continue }
                participantByPhone[key] = booking
                if let participantKey = booking.participant?.key, !participantKey.isEmpty {
                    participantKeyByPhone[key] = participantKey
                }
            }
        }

        var result: [String: ParticipantCallInfo] = [:]
        for (phone, booking) in participantByPhone {
            let participantKey = participantKeyByPhone[phone]
            let courses = bookings
                .filter { participantKey != nil && $0.participant?.key == participantKey }
                .compactMap { $0.event?.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let uniqueCourses = Array(NSOrderedSet(array: courses)) as? [String] ?? courses
            let name = booking.participant?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            result[phone] = ParticipantCallInfo(name: name, courses: uniqueCourses)
        }
        return result
    }

    static func participantPhoneNumbers(in booking: Booking) -> [String] {
        var numbers = booking.participant?.telephoneNumbers?.compactMap(\.telephoneNumber) ?? []
        let formResponses = [booking.regFormResponse].compactMap { $0 } + (booking.formResponses ?? [])
        for response in formResponses {
            for question in response.answeredQuestions ?? [] {
                let title = question.questionTitle?.lowercased() ?? ""
                guard title.contains("telefon") || title.contains("mobil") else { continue }
                numbers.append(contentsOf: question.answers?.values.map(\.stringValue) ?? [])
            }
        }
        return numbers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

@MainActor
final class TelavoxService: ObservableObject {
    private let baseURL = "https://sds-cogwork-proxy.nicklas-stenlander.workers.dev"

    @Published var calls: [TelavoxCall] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadCalls(daysBack: Int = 7) async {
        let calendar = Calendar(identifier: .gregorian)
        let toDate = Date()
        let fromDate = calendar.date(byAdding: .day, value: -max(daysBack, 0), to: toDate) ?? toDate
        await loadCalls(fromDate: fromDate, toDate: toDate)
    }

    func loadCalls(on date: Date) async {
        await loadCalls(fromDate: date, toDate: date)
    }

    func loadCalls(fromDate: Date, toDate: Date) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: TelavoxCallsResponse = try await get(path: "calls", queryItems: [
                URLQueryItem(name: "fromDate", value: Self.dayFormatter.string(from: fromDate)),
                URLQueryItem(name: "toDate", value: Self.dayFormatter.string(from: toDate))
            ])
            calls = response.missed.map { $0.withDirection(.missed) }
                + response.incoming.map { $0.withDirection(.incoming) }
                + response.outgoing.map { $0.withDirection(.outgoing) }
        } catch {
            errorMessage = "Kunde inte hämta samtal från Telavox."
        }
    }

    func dial(number: String) async -> Bool {
        do {
            let _: EmptyTelavoxResponse = try await get(path: "dial", queryItems: [
                URLQueryItem(name: "number", value: number)
            ])
            return true
        } catch {
            errorMessage = "Kunde inte starta samtalet."
            return false
        }
    }

    func sendSMS(number: String, message: String, sender: String) async -> Bool {
        do {
            let _: EmptyTelavoxResponse = try await get(path: "sms", queryItems: [
                URLQueryItem(name: "number", value: number),
                URLQueryItem(name: "message", value: message),
                URLQueryItem(name: "sender", value: sender)
            ])
            return true
        } catch {
            errorMessage = "Kunde inte skicka SMS."
            return false
        }
    }

    private func get<T: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> T {
        var components = URLComponents(string: "\(baseURL)/telavox/\(path)")
        components?.queryItems = queryItems
        guard let url = components?.url else { throw URLError(.badURL) }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if T.self == EmptyTelavoxResponse.self || data.isEmpty {
            return EmptyTelavoxResponse() as! T
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct EmptyTelavoxResponse: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}
