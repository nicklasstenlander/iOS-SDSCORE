import Foundation
import Combine

nonisolated enum RideauConfig {
    static let fallbackAPIBase = "https://oyqgxnmwojjjpoubdlfa.supabase.co/functions/v1"
    static let fallbackOrganizer = "sds"

    /// Reservvärde används om Info.plist-nyckeln saknas eller är tom (t.ex. en
    /// build utan `Secrets.xcconfig`) — fliken ska aldrig döljas på grund av
    /// ett konfigurationsproblem.
    static func apiBase(infoDictionary: [String: Any]?) -> String {
        let value = (infoDictionary?["RideauAPIBase"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallbackAPIBase : value
    }

    static func organizer(infoDictionary: [String: Any]?) -> String {
        let value = (infoDictionary?["RideauOrganizer"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallbackOrganizer : value
    }
}

@MainActor
final class RideauEventsService: ObservableObject {
    @Published var events: [RideauEvent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Server-klocka minus enhetens klocka, satt vid varje lyckad hämtning.
    @Published private(set) var clockSkew: TimeInterval = 0

    private var lastFetch: Date?
    private let cacheLifetime: TimeInterval = 300

    /// Flikens enda synlighetsregel: dold tills minst ett event hämtats.
    var isVisible: Bool { !events.isEmpty }

    private var baseURL: String {
        RideauConfig.apiBase(infoDictionary: Bundle.main.infoDictionary)
    }

    private var organizer: String {
        RideauConfig.organizer(infoDictionary: Bundle.main.infoDictionary)
    }

    func loadIfNeeded(force: Bool = false) async {
        if !force,
           let last = lastFetch,
           Date().timeIntervalSince(last) < cacheLifetime,
           !events.isEmpty {
            return
        }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard var components = URLComponents(string: "\(baseURL)/public-embed") else {
            errorMessage = "Kunde inte hämta föreställningar. Dra nedåt för att försöka igen."
            return
        }
        components.queryItems = [URLQueryItem(name: "organizer", value: organizer)]

        guard let url = components.url else {
            errorMessage = "Kunde inte hämta föreställningar. Dra nedåt för att försöka igen."
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                errorMessage = "Kunde inte hämta föreställningar. Dra nedåt för att försöka igen."
                return
            }
            let decoded = try JSONDecoder().decode(RideauEventsResponse.self, from: data)
            events = decoded.events
            if let serverDate = RideauISO8601.parse(decoded.serverTime) {
                clockSkew = serverDate.timeIntervalSince(Date())
            }
            lastFetch = Date()
        } catch is CancellationError {
            // Task avbruten av SwiftUI-livscykeln — inte ett användarfel
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession avbruten av task-livscykeln — inte ett användarfel
        } catch {
            errorMessage = "Kunde inte hämta föreställningar. Dra nedåt för att försöka igen."
        }
    }
}
