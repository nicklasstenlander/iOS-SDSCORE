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

    func fetchForms() async throws -> [FormSummary] {
        try await request(
            path: "/rest/v1/forms",
            queryItems: [
                URLQueryItem(name: "select", value: "id,title,status,enable_checkin"),
                URLQueryItem(name: "order", value: "title.asc")
            ]
        )
    }

    func fetchPublishedForms() async throws -> [FormSummary] {
        try await request(
            path: "/rest/v1/forms",
            queryItems: [
                URLQueryItem(name: "select", value: "id,title,status,enable_checkin"),
                URLQueryItem(name: "status", value: "eq.published")
            ]
        )
    }

    func setFormCheckInEnabled(formId: String, enabled: Bool) async throws {
        let data = try JSONEncoder().encode(["enable_checkin": enabled])
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

    func fetchOptions(formId: String) async throws -> [FormOption] {
        try await request(
            path: "/rest/v1/form_options",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "form_id", value: "eq.\(formId)")
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
        components.queryItems = queryItems

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
}
