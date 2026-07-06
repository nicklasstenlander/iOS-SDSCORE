import Foundation

struct FormSubmission: Codable, Identifiable {
    let id: String
    let formId: String
    let submittedAt: String
    let respondentName: String?
    let respondentEmail: String?
    let respondentPhone: String?
    let answers: [String: AnyCodableValue]
    let selectedOptionKeys: [String]
    var checkedInAt: String?
    var checkedInBy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case formId = "form_id"
        case submittedAt = "submitted_at"
        case respondentName = "respondent_name"
        case respondentEmail = "respondent_email"
        case respondentPhone = "respondent_phone"
        case answers
        case selectedOptionKeys = "selected_option_keys"
        case checkedInAt = "checked_in_at"
        case checkedInBy = "checked_in_by"
    }

    var isCheckedIn: Bool { checkedInAt != nil }
}

enum AnyCodableValue: Codable {
    case string(String)
    case array([String])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let a = try? container.decode([String].self) { self = .array(a); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }

    var displayString: String {
        switch self {
        case .string(let s): return s
        case .array(let a): return a.joined(separator: ", ")
        case .null: return "–"
        }
    }
}

struct FormOption: Codable, Identifiable {
    let id: String
    let fieldId: String
    let key: String
    let label: String

    enum CodingKeys: String, CodingKey {
        case id, key, label
        case fieldId = "field_id"
    }
}

struct FormSummary: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let status: String
    var enableCheckin: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, status
        case enableCheckin = "enable_checkin"
    }

    init(id: String, title: String, status: String, enableCheckin: Bool = false) {
        self.id = id
        self.title = title
        self.status = status
        self.enableCheckin = enableCheckin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decode(String.self, forKey: .status)
        enableCheckin = try container.decodeIfPresent(Bool.self, forKey: .enableCheckin) ?? false
    }
}
