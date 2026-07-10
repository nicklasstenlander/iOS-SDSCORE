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
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, type, title, body
        case imageUrl = "image_url"
        case linkUrl = "link_url"
        case linkLabel = "link_label"
        case startsAt = "starts_at"
        case expiresAt = "expires_at"
        case sortOrder = "sort_order"
    }
}

@MainActor
final class ContentCardsService: ObservableObject {
    @Published var cards: [ContentCard] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let supabaseURL = "https://vuokkdtyhmhkvfizsnwm.supabase.co"
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ1b2trZHR5aG1oa3ZmaXpzbndtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MjEzMDAsImV4cCI6MjA5ODM5NzMwMH0.n4LdnB4n_J3zqgzo6wLg3oZsdQtZobLoC-VA4X-S9qw"

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
}
