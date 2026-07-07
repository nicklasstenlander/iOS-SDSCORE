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

enum FormFieldType: String, Codable, CaseIterable, Identifiable {
    case shortText = "short_text"
    case longText = "long_text"
    case email
    case phone
    case date
    case checkboxes
    case radio
    case select
    case courseChoice = "course_choice"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortText: "Kort text"
        case .longText: "Lång text"
        case .email: "E-post"
        case .phone: "Telefon"
        case .date: "Datum"
        case .checkboxes: "Kryssrutor"
        case .radio: "Radioknappar"
        case .select: "Lista"
        case .courseChoice: "Kursval"
        }
    }

    var usesOptions: Bool {
        switch self {
        case .checkboxes, .radio, .select, .courseChoice: true
        default: false
        }
    }
}

struct FormField: Codable, Identifiable {
    let id: String
    let formId: String
    let key: String
    let type: FormFieldType
    let label: String
    let helpText: String?
    let required: Bool
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, key, type, label, required
        case formId = "form_id"
        case helpText = "help_text"
        case sortOrder = "sort_order"
    }
}

struct FormOption: Codable, Identifiable {
    let id: String
    let formId: String?
    let fieldId: String
    let key: String
    let label: String
    let description: String?
    let dayTime: String?
    let location: String?
    let level: String?
    let capacity: Int?
    let active: Bool
    let sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case id, key, label, description, location, level, capacity, active
        case formId = "form_id"
        case fieldId = "field_id"
        case dayTime = "day_time"
        case sortOrder = "sort_order"
    }

    init(
        id: String,
        formId: String? = nil,
        fieldId: String,
        key: String,
        label: String,
        description: String? = nil,
        dayTime: String? = nil,
        location: String? = nil,
        level: String? = nil,
        capacity: Int? = nil,
        active: Bool = true,
        sortOrder: Int? = nil
    ) {
        self.id = id
        self.formId = formId
        self.fieldId = fieldId
        self.key = key
        self.label = label
        self.description = description
        self.dayTime = dayTime
        self.location = location
        self.level = level
        self.capacity = capacity
        self.active = active
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        formId = try container.decodeIfPresent(String.self, forKey: .formId)
        fieldId = try container.decode(String.self, forKey: .fieldId)
        key = try container.decode(String.self, forKey: .key)
        label = try container.decode(String.self, forKey: .label)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        dayTime = try container.decodeIfPresent(String.self, forKey: .dayTime)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        level = try container.decodeIfPresent(String.self, forKey: .level)
        capacity = try container.decodeIfPresent(Int.self, forKey: .capacity)
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
    }
}

struct FormOptionDraft: Identifiable, Hashable {
    var localId = UUID()
    var key: String
    var label: String
    var description: String
    var dayTime: String
    var location: String
    var level: String
    var capacity: String
    var active: Bool
    var sortOrder: Int

    init(
        localId: UUID = UUID(),
        key: String = "",
        label: String = "Nytt alternativ",
        description: String = "",
        dayTime: String = "",
        location: String = "",
        level: String = "",
        capacity: String = "",
        active: Bool = true,
        sortOrder: Int = 0
    ) {
        self.localId = localId
        self.key = key
        self.label = label
        self.description = description
        self.dayTime = dayTime
        self.location = location
        self.level = level
        self.capacity = capacity
        self.active = active
        self.sortOrder = sortOrder
    }

    var id: UUID { localId }
}

struct FormFieldDraft: Identifiable, Hashable {
    var localId = UUID()
    var key: String
    var type: FormFieldType
    var label: String
    var helpText: String
    var required: Bool
    var sortOrder: Int
    var options: [FormOptionDraft]

    init(
        localId: UUID = UUID(),
        key: String = "",
        type: FormFieldType = .shortText,
        label: String = "Nytt fält",
        helpText: String = "",
        required: Bool = false,
        sortOrder: Int = 0,
        options: [FormOptionDraft] = []
    ) {
        self.localId = localId
        self.key = key
        self.type = type
        self.label = label
        self.helpText = helpText
        self.required = required
        self.sortOrder = sortOrder
        self.options = options
    }

    var id: UUID { localId }
}

struct FormSummary: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var slug: String?
    var status: String
    var enableCheckin: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, slug, status
        case enableCheckin = "enable_checkin"
    }

    init(id: String, title: String, slug: String? = nil, status: String, enableCheckin: Bool = false) {
        self.id = id
        self.title = title
        self.slug = slug
        self.status = status
        self.enableCheckin = enableCheckin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        status = try container.decode(String.self, forKey: .status)
        enableCheckin = try container.decodeIfPresent(Bool.self, forKey: .enableCheckin) ?? false
    }
}
