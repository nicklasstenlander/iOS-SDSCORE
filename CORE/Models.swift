import Foundation

// MARK: - Bokningar (från sds-cogwork-proxy Worker)

struct BookingsResponse: Codable {
    let bookings: [Booking]
    let search: SearchInfo?
    let cachedAt: String?
}

struct SearchInfo: Codable {
    let numRowsFound: Int?
    let shown: SearchShown?
    let limits: SearchLimits?
}

struct SearchShown: Codable {
    let numRowsShown: Int?
    let firstShownRowNum: Int?
    let lastShownRowNum: Int?
}

struct SearchLimits: Codable {
    let maxRows: Int?
    let maxRowsDefault: Int?
    let maxRowsAllowed: Int?
}

struct Booking: Codable, Identifiable {
    let id: Int
    let key: String
    let created: String
    let reference: String?
    let event: BookingEvent?
    let participant: Participant?
    let payment: Payment?
    let status: BookingStatus?

    struct BookingEvent: Codable {
        let key: String?
        let id: Int?
        let code: String?
        let name: String?
        let startDateTime: String?
        let startDate: String?
        let startTime: String?
        let category: EventCategory?
        let pricing: EventPricing?
        let grouping: BookingEventGrouping?

        struct BookingEventGrouping: Codable {
            let eventBlock: EventBlock?
        }
    }

    struct Participant: Codable {
        let id: Int?
        let key: String?
        let name: String?
        let firstName: String?
        let lastName: String?
        let dateOfBirth: String?
    }

    struct Payment: Codable {
        let paid: Bool?
        let amountPaid: Double?
        let priceAgreed: Double?
        let currency: String?
        let paymentDue: String?
    }

    struct BookingStatus: Codable {
        let code: String?
        let name: String?
    }

    let regFormResponse: BookingFormResponse?
    let formResponses: [BookingFormResponse]?
    let comment: String?
    let finStatus: String?

    /// Grov klassificering av betalstatus för badge-visning.
    var paymentLabel: (text: String, isPaid: Bool) {
        guard let payment else { return ("Okänd", false) }
        if payment.paid == true {
            let amount = payment.amountPaid.map { "\(Int($0)) \(payment.currency ?? "SEK")" } ?? ""
            return ("Betald · \(amount)", true)
        } else {
            let due = payment.paymentDue.map { " · förfaller \($0)" } ?? ""
            return ("Obetald\(due)", false)
        }
    }

    var formattedPrice: String {
        guard let price = payment?.priceAgreed else { return "–" }
        return "\(Int(price)) \(payment?.currency ?? "SEK")"
    }
}

struct EventCategory: Codable, Hashable {
    let id: Int?
    let name: String?
}

struct EventGroup: Codable, Hashable {
    let key: String?
    let id: FlexibleID?
    let name: String?
}

struct EventBlock: Codable, Hashable {
    let key: String?
    let id: FlexibleID?
    let name: String?
}

struct EventPricing: Codable, Hashable {
    let currency: String?
    let basePriceInclVat: Double?
}

struct BookingFormQuestion: Codable, Hashable {
    let questionId: Int?
    let questionType: String?
    let questionTitle: String?
    let htmlIdForQuestion: String?
    let answers: [String: FlexibleValue]?
}

struct BookingFormResponse: Codable, Hashable {
    let createdDateTime: String?
    let textSummary: String?
    let htmlSummary: String?
    let answeredQuestions: [BookingFormQuestion]?
}

enum FlexibleID: Codable, Hashable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }

    var stringValue: String {
        switch self {
        case .int(let value): String(value)
        case .string(let value): value
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let value): value
        case .string(let value): Int(value)
        }
    }
}

enum FlexibleValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let numberValue = try? container.decode(Double.self) {
            self = .number(numberValue)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String {
        switch self {
        case .string(let value): value
        case .number(let value): value.formatted()
        case .bool(let value): value ? "true" : "false"
        case .null: ""
        }
    }
}

// MARK: - Aggregerat "allt"-svar (type=all)

struct AllDataResponse: Codable {
    let bookings: BookingsWrapper
    let events: EventsWrapper?
    let cachedAt: String?

    struct BookingsWrapper: Codable {
        let bookings: [Booking]
        let search: SearchInfo?
    }

    struct EventsWrapper: Codable {
        let events: [Event]
        let search: SearchInfo?
    }
}

struct Event: Codable, Identifiable {
    let id: Int
    let key: String?
    let name: String?
    let created: String?
    let code: String?
    let category: EventCategory?
    let place: String?
    let pricing: EventPricing?
    let registration: EventRegistration?
    let schedule: EventSchedule?
    let statistics: EventStatistics?
    let grouping: EventGrouping?
    let requirements: EventRequirements?
    let instructorsName: String?
}

struct EventRegistration: Codable, Hashable {
    let status: String?
    let statusName: String?
    let statusText: String?
    let showing: Bool?
    let open: Bool?
}

struct EventSchedule: Codable, Hashable {
    let dayAndTimeInfo: String?
    let start: EventSchedulePoint?
    let end: EventSchedulePoint?
    let numberOfPlannedOccasions: Int?
    let numberOfScheduledOccasions: Int?
    let occasions: [EventOccasion]?
}

struct EventSchedulePoint: Codable, Hashable {
    let date: String?
    let time: String?
    let dayOfWeek: String?
}

struct EventOccasion: Codable, Hashable {
    let length: Int?
    let startDateTime: String?
    let startDayOfWeek: String?
    let endDateTime: String?
}

struct EventStatistics: Codable, Hashable {
    let instructors: Int?
    let staff: Int?
    let accepted: Int?
}

struct EventGrouping: Codable, Hashable {
    let eventBlock: EventBlock?
    let primaryEventGroup: EventGroup?
    let additionalEventGroups: [EventGroup]?
}

struct EventRequirements: Codable, Hashable {
    let minAge: Int?
    let maxAge: Int?
    let maxParticipants: Int?
}

struct EventsResponse: Codable {
    let search: SearchInfo?
    let events: [Event]
}

struct CogWorkUser: Codable, Identifiable {
    let id: Int
    let key: String?
    let name: String?
    let firstName: String?
    let lastName: String?
    let dateOfBirth: String?
    let thumb: UserThumb?
    let addresses: [UserAddress]?
    let emails: [UserEmail]?
    let telephoneNumbers: [UserTelephoneNumber]?
    let isMember: Bool?
    let membershipNumber: String?

    enum CodingKeys: String, CodingKey {
        case id
        case key
        case name
        case firstName
        case lastName
        case dateOfBirth
        case thumb
        case addresses
        case emails
        case telephoneNumbers
        case isMember
        case membershipNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = container.decodeFlexibleStringIfPresent(forKey: .key)
        name = container.decodeFlexibleStringIfPresent(forKey: .name)
        firstName = container.decodeFlexibleStringIfPresent(forKey: .firstName)
        lastName = container.decodeFlexibleStringIfPresent(forKey: .lastName)
        dateOfBirth = container.decodeFlexibleStringIfPresent(forKey: .dateOfBirth)
        thumb = try container.decodeIfPresent(UserThumb.self, forKey: .thumb)
        addresses = try container.decodeIfPresent([UserAddress].self, forKey: .addresses)
        emails = try container.decodeIfPresent([UserEmail].self, forKey: .emails)
        telephoneNumbers = try container.decodeIfPresent([UserTelephoneNumber].self, forKey: .telephoneNumbers)
        isMember = container.decodeFlexibleBoolIfPresent(forKey: .isMember)
        membershipNumber = container.decodeFlexibleStringIfPresent(forKey: .membershipNumber)

        if let numericId = container.decodeFlexibleIntIfPresent(forKey: .id) {
            id = numericId
        } else {
            id = -Self.fallbackID(from: [key, name, firstName, lastName].compactMap { $0 }.joined(separator: "|"))
        }
    }

    private static func fallbackID(from value: String) -> Int {
        let source = value.isEmpty ? UUID().uuidString : value
        let raw = source.unicodeScalars.reduce(UInt64(5381)) { hash, scalar in
            ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return Int(raw % UInt64(Int.max))
    }
}

struct UserThumb: Codable, Hashable {
    let url: String?
    let width: Int?

    enum CodingKeys: String, CodingKey {
        case url
        case width
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = container.decodeFlexibleStringIfPresent(forKey: .url)
        width = container.decodeFlexibleIntIfPresent(forKey: .width)
    }
}

struct UserAddress: Codable, Hashable {
    let careOf: String?
    let streetAddress: String?
    let postalCode: String?
    let city: String?
    let country: String?

    enum CodingKeys: String, CodingKey {
        case careOf
        case streetAddress
        case postalCode
        case city
        case country
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        careOf = container.decodeFlexibleStringIfPresent(forKey: .careOf)
        streetAddress = container.decodeFlexibleStringIfPresent(forKey: .streetAddress)
        postalCode = container.decodeFlexibleStringIfPresent(forKey: .postalCode)
        city = container.decodeFlexibleStringIfPresent(forKey: .city)
        country = container.decodeFlexibleStringIfPresent(forKey: .country)
    }
}

struct UserEmail: Codable, Hashable {
    let email: String?

    enum CodingKeys: String, CodingKey {
        case email
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = container.decodeFlexibleStringIfPresent(forKey: .email)
    }
}

struct UserTelephoneNumber: Codable, Hashable {
    let telephoneNumber: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case telephoneNumber
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        telephoneNumber = container.decodeFlexibleStringIfPresent(forKey: .telephoneNumber)
        type = container.decodeFlexibleStringIfPresent(forKey: .type)
    }
}

struct UsersResponse: Decodable {
    let search: SearchInfo?
    let users: [CogWorkUser]

    enum CodingKeys: String, CodingKey {
        case search
        case users
        case user
    }

    init(from decoder: Decoder) throws {
        if let array = try? [CogWorkUser](from: decoder) {
            search = nil
            users = array
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        search = try container.decodeIfPresent(SearchInfo.self, forKey: .search)

        if let users = try container.decodeIfPresent([CogWorkUser].self, forKey: .users) {
            self.users = users
        } else if let user = try container.decodeIfPresent(CogWorkUser.self, forKey: .user) {
            users = [user]
        } else {
            users = []
        }
    }
}

// MARK: - Supabase-profil

struct UserProfile: Codable {
    let id: String
    let fullName: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case role
    }

    var firstName: String {
        fullName.split(separator: " ").first.map(String.init) ?? fullName
    }
}

extension KeyedDecodingContainer {
    func decodeFlexibleStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value.rounded() == value ? String(Int(value)) : String(value)
        }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        return nil
    }

    func decodeFlexibleIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    func decodeFlexibleBoolIfPresent(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "yes", "ja", "1"].contains(normalized) { return true }
            if ["false", "no", "nej", "0"].contains(normalized) { return false }
        }
        return nil
    }
}
