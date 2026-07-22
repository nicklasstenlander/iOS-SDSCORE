import Foundation
import Combine

struct ContentCard: Codable, Identifiable {
    let id: String
    let type: String
    let title: String
    let body: String?
    let imageUrl: String?
    let linkUrl: String?
    let linkLabel: String?
    let startsAt: String
    let expiresAt: String?
    let published: Bool
    let sortOrder: Int
    let sendPush: Bool?
    let pushSentAt: String?
    let showOnWeb: Bool
    let showOnApp: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, title, body, published
        case imageUrl = "image_url"
        case linkUrl = "link_url"
        case linkLabel = "link_label"
        case startsAt = "starts_at"
        case expiresAt = "expires_at"
        case sortOrder = "sort_order"
        case sendPush = "send_push"
        case pushSentAt = "push_sent_at"
        case showOnWeb = "show_on_web"
        case showOnApp = "show_on_app"
    }
}

struct ContentCardDraft {
    var type: String = "news"
    var title: String = ""
    var body: String = ""
    var imageUrl: String = ""
    var linkUrl: String = ""
    var linkLabel: String = ""
    var startsAt: Date = Date()
    var expiresAt: Date? = nil
    var published: Bool = false
    var sortOrder: Int = 0
    var sendPush: Bool = false
    var showOnWeb: Bool = true
    var showOnApp: Bool = true
}

@MainActor
final class ContentCardsService: ObservableObject {
    @Published var cards: [ContentCard] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let supabaseURL = "https://vuokkdtyhmhkvfizsnwm.supabase.co"
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ1b2trZHR5aG1oa3ZmaXpzbndtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MjEzMDAsImV4cCI6MjA5ODM5NzMwMH0.n4LdnB4n_J3zqgzo6wLg3oZsdQtZobLoC-VA4X-S9qw"

    // MARK: - Public (anon) — används av HomeView, rör inte

    func loadCards() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let now = ISO8601DateFormatter().string(from: Date())
        guard var components = URLComponents(string: "\(supabaseURL)/rest/v1/content_cards") else {
            errorMessage = "Kunde inte skapa adress för nyheter."
            return
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "published", value: "eq.true"),
            URLQueryItem(name: "show_on_app", value: "eq.true"),
            URLQueryItem(name: "starts_at", value: "lte.\(now)"),
            URLQueryItem(name: "or", value: "(expires_at.is.null,expires_at.gte.\(now))"),
            URLQueryItem(name: "order", value: "sort_order.asc")
        ]

        guard let url = components.url else {
            errorMessage = "Kunde inte skapa adress för nyheter."
            return
        }

        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                errorMessage = "Kunde inte hämta nyheter."
                return
            }
            cards = try JSONDecoder().decode([ContentCard].self, from: data)
        } catch {
            errorMessage = "Kunde inte hämta nyheter. \(error.localizedDescription)"
        }
    }

    // MARK: - Admin — kräver autentiserad användare

    func fetchAllCards() async throws -> [ContentCard] {
        let data = try await adminRequestData(
            path: "/rest/v1/content_cards",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "sort_order.asc")
            ]
        )
        return try JSONDecoder().decode([ContentCard].self, from: data)
    }

    func createCard(_ draft: ContentCardDraft) async throws -> ContentCard {
        let data = try await adminRequestData(
            path: "/rest/v1/content_cards",
            queryItems: [URLQueryItem(name: "select", value: "*")],
            method: "POST",
            body: try cardPayloadData(from: draft),
            additionalHeaders: [
                "Content-Type": "application/json",
                "Prefer": "return=representation"
            ]
        )
        let created = try JSONDecoder().decode([ContentCard].self, from: data)
        guard let card = created.first else { throw URLError(.badServerResponse) }
        return card
    }

    func updateCard(id: String, _ draft: ContentCardDraft) async throws {
        _ = try await adminRequestData(
            path: "/rest/v1/content_cards",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id)")],
            method: "PATCH",
            body: try cardPayloadData(from: draft),
            additionalHeaders: [
                "Content-Type": "application/json",
                "Prefer": "return=minimal"
            ]
        )
    }

    func deleteCard(id: String) async throws {
        _ = try await adminRequestData(
            path: "/rest/v1/content_cards",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id)")],
            method: "DELETE",
            additionalHeaders: ["Prefer": "return=minimal"]
        )
    }

    // MARK: - Private helpers

    private func cardPayloadData(from draft: ContentCardDraft) throws -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var dict: [String: Any] = [
            "type": draft.type,
            "title": draft.title,
            "published": draft.published,
            "sort_order": draft.sortOrder,
            "starts_at": iso.string(from: draft.startsAt),
            "send_push": draft.sendPush,
            "show_on_web": draft.showOnWeb,
            "show_on_app": draft.showOnApp
        ]

        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        dict["body"] = body.isEmpty ? NSNull() : body

        let imageUrl = draft.imageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        dict["image_url"] = imageUrl.isEmpty ? NSNull() : imageUrl

        let linkUrl = draft.linkUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        dict["link_url"] = linkUrl.isEmpty ? NSNull() : linkUrl

        let linkLabel = draft.linkLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        dict["link_label"] = linkLabel.isEmpty ? NSNull() : linkLabel

        if let expiresAt = draft.expiresAt {
            dict["expires_at"] = iso.string(from: expiresAt)
        } else {
            dict["expires_at"] = NSNull()
        }

        return try JSONSerialization.data(withJSONObject: dict)
    }

    private func adminRequestData(
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
}
