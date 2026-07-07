import Foundation
import Combine

@MainActor
final class FormsService: ObservableObject {
    @Published var submissions: [FormSubmission] = []
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let supabaseURL = "https://vuokkdtyhmhkvfizsnwm.supabase.co"
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ1b2trZHR5aG1oa3ZmaXpzbndtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MjEzMDAsImV4cCI6MjA5ODM5NzMwMH0.n4LdnB4n_J3zqgzo6wLg3oZsdQtZobLoC-VA4X-S9qw"
    private var pollingTask: Task<Void, Never>?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func fetchForms() async throws -> [FormSummary] {
        try await request(
            path: "/rest/v1/forms",
            queryItems: [
                URLQueryItem(name: "select", value: "id,title,slug,status,enable_checkin"),
                URLQueryItem(name: "order", value: "title.asc")
            ]
        )
    }

    func fetchPublishedForms() async throws -> [FormSummary] {
        try await request(
            path: "/rest/v1/forms",
            queryItems: [
                URLQueryItem(name: "select", value: "id,title,slug,status,enable_checkin"),
                URLQueryItem(name: "status", value: "eq.published")
            ]
        )
    }

    func setFormCheckInEnabled(formId: String, enabled: Bool) async throws {
        let data = try encoder.encode(["enable_checkin": enabled])
        _ = try await requestData(
            path: "/rest/v1/forms",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(formId)")],
            method: "PATCH",
            body: data,
            additionalHeaders: [
                "Content-Type": "application/json",
                "Prefer": "return=minimal"
            ]
        )
    }

    func createForm(title: String, slug: String, status: String, enableCheckin: Bool) async throws -> FormSummary {
        let payload = FormSettingsUpdate(
            title: title,
            slug: slug,
            status: status,
            enableCheckin: enableCheckin
        )
        let created: [FormSummary] = try await request(
            path: "/rest/v1/forms",
            queryItems: [URLQueryItem(name: "select", value: "id,title,slug,status,enable_checkin")],
            method: "POST",
            body: try encoder.encode(payload),
            additionalHeaders: [
                "Content-Type": "application/json",
                "Prefer": "return=representation"
            ]
        )
        guard let form = created.first else { throw URLError(.badServerResponse) }
        return form
    }

    func updateFormSettings(form: FormSummary) async throws {
        let payload = FormSettingsUpdate(
            title: form.title,
            slug: form.slug,
            status: form.status,
            enableCheckin: form.enableCheckin
        )
        _ = try await requestData(
            path: "/rest/v1/forms",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(form.id)")],
            method: "PATCH",
            body: try encoder.encode(payload),
            additionalHeaders: [
                "Content-Type": "application/json",
                "Prefer": "return=minimal"
            ]
        )
    }

    func deleteForm(formId: String) async throws {
        _ = try await requestData(
            path: "/rest/v1/forms",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(formId)")],
            method: "DELETE",
            additionalHeaders: ["Prefer": "return=minimal"]
        )
    }

    func fetchFormFields(formId: String) async throws -> [FormField] {
        try await request(
            path: "/rest/v1/form_fields",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "form_id", value: "eq.\(formId)"),
                URLQueryItem(name: "order", value: "sort_order.asc")
            ]
        )
    }

    func fetchFormOptions(formId: String) async throws -> [FormOption] {
        try await request(
            path: "/rest/v1/form_options",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "form_id", value: "eq.\(formId)"),
                URLQueryItem(name: "order", value: "sort_order.asc")
            ]
        )
    }

    func fetchOptions(formId: String) async throws -> [FormOption] {
        try await fetchFormOptions(formId: formId)
    }

    func replaceFieldsAndOptions(formId: String, fields: [FormFieldDraft]) async throws {
        _ = try await requestData(
            path: "/rest/v1/form_fields",
            queryItems: [URLQueryItem(name: "form_id", value: "eq.\(formId)")],
            method: "DELETE",
            additionalHeaders: ["Prefer": "return=minimal"]
        )

        guard !fields.isEmpty else { return }

        let fieldPayloads = fields.enumerated().map { index, draft in
            FormFieldInsert(
                formId: formId,
                key: normalizedKey(draft.key, fallback: "field_\(index + 1)"),
                type: draft.type.rawValue,
                label: cleaned(draft.label, fallback: "Fält \(index + 1)"),
                helpText: optionalCleaned(draft.helpText),
                required: draft.required,
                sortOrder: index
            )
        }

        let insertedFields: [FormField] = try await request(
            path: "/rest/v1/form_fields",
            queryItems: [],
            method: "POST",
            body: try encoder.encode(fieldPayloads),
            additionalHeaders: [
                "Content-Type": "application/json",
                "Prefer": "return=representation"
            ]
        )

        let fieldIdByLocalId = Dictionary(uniqueKeysWithValues: zip(fields.map(\.localId), insertedFields.map(\.id)))
        let optionPayloads = fields.flatMap { draft -> [FormOptionInsert] in
            guard let fieldId = fieldIdByLocalId[draft.localId], draft.type.usesOptions else { return [] }
            return draft.options.enumerated().map { optionIndex, option in
                FormOptionInsert(
                    formId: formId,
                    fieldId: fieldId,
                    key: normalizedKey(option.key, fallback: "option_\(optionIndex + 1)"),
                    label: cleaned(option.label, fallback: "Alternativ \(optionIndex + 1)"),
                    description: optionalCleaned(option.description),
                    dayTime: draft.type == .courseChoice ? optionalCleaned(option.dayTime) : nil,
                    location: draft.type == .courseChoice ? optionalCleaned(option.location) : nil,
                    level: draft.type == .courseChoice ? optionalCleaned(option.level) : nil,
                    capacity: draft.type == .courseChoice ? Int(option.capacity.trimmingCharacters(in: .whitespacesAndNewlines)) : nil,
                    active: option.active,
                    sortOrder: optionIndex
                )
            }
        }

        guard !optionPayloads.isEmpty else { return }
        _ = try await requestData(
            path: "/rest/v1/form_options",
            queryItems: [],
            method: "POST",
            body: try encoder.encode(optionPayloads),
            additionalHeaders: [
                "Content-Type": "application/json",
                "Prefer": "return=minimal"
            ]
        )
    }

    func fetchSubmissions(formId: String) async throws -> [FormSubmission] {
        try await request(
            path: "/rest/v1/form_submissions",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "form_id", value: "eq.\(formId)"),
                URLQueryItem(name: "order", value: "submitted_at.desc")
            ]
        )
    }

    func setCheckedIn(submissionId: String, checkedIn: Bool, by: String) async throws {
        let timestamp = checkedIn ? ISO8601DateFormatter().string(from: Date()) : nil
        let checkedInBy = checkedIn ? by : nil
        let body: [String: Any] = [
            "checked_in_at": timestamp as Any? ?? NSNull(),
            "checked_in_by": checkedInBy as Any? ?? NSNull()
        ]
        let data = try JSONSerialization.data(withJSONObject: body)

        _ = try await requestData(
            path: "/rest/v1/form_submissions",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(submissionId)")],
            method: "PATCH",
            body: data,
            additionalHeaders: [
                "Content-Type": "application/json",
                "Prefer": "return=minimal"
            ]
        )
    }

    func startPolling(formId: String, interval: TimeInterval = 4) {
        stopPolling()
        pollingTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.refreshSubmissions(formId: formId)

                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    return
                }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refreshSubmissions(formId: String) async {
        do {
            submissions = try await fetchSubmissions(formId: formId)
            errorMessage = nil
        } catch {
            errorMessage = "Kunde inte hämta formulärsvar."
        }
    }

    func updateCheckInOptimistically(submissionId: String, checkedIn: Bool, by: String) async {
        guard let index = submissions.firstIndex(where: { $0.id == submissionId }) else { return }
        let previous = submissions[index]
        submissions[index].checkedInAt = checkedIn ? ISO8601DateFormatter().string(from: Date()) : nil
        submissions[index].checkedInBy = checkedIn ? by : nil

        do {
            try await setCheckedIn(submissionId: submissionId, checkedIn: checkedIn, by: by)
            errorMessage = nil
        } catch {
            if let rollbackIndex = submissions.firstIndex(where: { $0.id == submissionId }) {
                submissions[rollbackIndex] = previous
            }
            errorMessage = "Kunde inte spara avprickningen. Försök igen."
        }
    }

    private func request<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem],
        method: String = "GET",
        body: Data? = nil,
        additionalHeaders: [String: String] = [:]
    ) async throws -> T {
        let data = try await requestData(
            path: path,
            queryItems: queryItems,
            method: method,
            body: body,
            additionalHeaders: additionalHeaders
        )
        return try decoder.decode(T.self, from: data)
    }

    private func requestData(
        path: String,
        queryItems: [URLQueryItem],
        method: String = "GET",
        body: Data? = nil,
        additionalHeaders: [String: String] = [:]
    ) async throws -> Data {
        guard var components = URLComponents(string: supabaseURL + path) else {
            throw URLError(.badURL)
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let token = try await SupabaseAuthService.shared.validAccessToken()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        additionalHeaders.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return data
    }

    private func cleaned(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func optionalCleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedKey(_ value: String, fallback: String) -> String {
        let source = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : value
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let scalars = source.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let key = String(scalars)
            .split(separator: "_")
            .joined(separator: "_")
        return key.isEmpty ? fallback : key
    }
}

private struct FormSettingsUpdate: Encodable {
    let title: String
    let slug: String?
    let status: String
    let enableCheckin: Bool

    enum CodingKeys: String, CodingKey {
        case title, slug, status
        case enableCheckin = "enable_checkin"
    }
}

private struct FormFieldInsert: Encodable {
    let formId: String
    let key: String
    let type: String
    let label: String
    let helpText: String?
    let required: Bool
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case key, type, label, required
        case formId = "form_id"
        case helpText = "help_text"
        case sortOrder = "sort_order"
    }
}

private struct FormOptionInsert: Encodable {
    let formId: String
    let fieldId: String
    let key: String
    let label: String
    let description: String?
    let dayTime: String?
    let location: String?
    let level: String?
    let capacity: Int?
    let active: Bool
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case key, label, description, location, level, capacity, active
        case formId = "form_id"
        case fieldId = "field_id"
        case dayTime = "day_time"
        case sortOrder = "sort_order"
    }
}
