import Foundation
import Combine

@MainActor
final class CogWorkService: ObservableObject {
    private let baseURL = "https://sds-cogwork-proxy.nicklas-stenlander.workers.dev"
    private let publicBaseURL = "https://dans.se/api/public"

    @Published var bookings: [Booking] = []
    @Published var events: [Event] = []
    @Published var users: [CogWorkUser] = []
    @Published var selectedUserBookings: [Booking] = []
    @Published var isLoading = false
    @Published var isLoadingEvents = false
    @Published var isLoadingUsers = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    var cogWorkPassword: String {
        get {
            let stored = UserDefaults.standard.string(forKey: "sds_core_cogwork_password") ?? ""
            if !stored.isEmpty { return stored }
            return Bundle.main.object(forInfoDictionaryKey: "CogWorkSharedPassword") as? String ?? ""
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "sds_core_cogwork_password")
        }
    }

    /// Hämtar alla bokningar (aggregerat över terminer via Workerns cache).
    func loadBookings() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(baseURL)/?type=bookings") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                errorMessage = "Kunde inte hämta anmälningar (serverfel)."
                return
            }
            let decoded = try JSONDecoder().decode(BookingsResponse.self, from: data)
            bookings = decoded.bookings
            lastUpdated = Date()
        } catch {
            errorMessage = "Kunde inte hämta anmälningar. \(error.localizedDescription)"
        }
    }

    func loadAllData(eventBlockId: String? = nil) async {
        isLoading = true
        isLoadingEvents = true
        errorMessage = nil
        defer {
            isLoading = false
            isLoadingEvents = false
        }

        do {
            var queryItems = [URLQueryItem(name: "type", value: "all")]
            if let eventBlockId, !eventBlockId.isEmpty {
                queryItems.append(URLQueryItem(name: "eventBlockId", value: eventBlockId))
            }
            let data = try await proxyData(queryItems: queryItems)
            let decoded = try JSONDecoder().decode(AllDataResponse.self, from: data)
            bookings = decoded.bookings.bookings
            events = decoded.events?.events ?? []
            lastUpdated = Date()
        } catch {
            errorMessage = "Kunde inte hämta översiktsdata. \(error.localizedDescription)"
        }
    }

    func loadEvents(eventBlockId: String? = nil) async {
        isLoadingEvents = true
        errorMessage = nil
        defer { isLoadingEvents = false }

        do {
            if hasCogWorkPassword {
                let response: EventsResponse = try await publicAPI(path: "events", extra: eventBlockId.map { ["eventBlockId": $0] } ?? [:])
                events = response.events
            } else {
                var queryItems = [URLQueryItem(name: "type", value: "all")]
                if let eventBlockId, !eventBlockId.isEmpty {
                    queryItems.append(URLQueryItem(name: "eventBlockId", value: eventBlockId))
                }
                let data = try await proxyData(queryItems: queryItems)
                let decoded = try JSONDecoder().decode(AllDataResponse.self, from: data)
                events = decoded.events?.events ?? []
            }
        } catch {
            errorMessage = "Kunde inte hämta kurser. \(error.localizedDescription)"
        }
    }

    func searchUsers(query: String) async {
        guard hasCogWorkPassword else {
            errorMessage = "CogWork-lösenord krävs för kundsökning."
            return
        }

        isLoadingUsers = true
        errorMessage = nil
        defer { isLoadingUsers = false }

        do {
            let response: UsersResponse = try await publicAPI(path: "users", extra: [
                "textSearch": query,
                "maxRows": "50"
            ])
            users = response.users
        } catch {
            errorMessage = "Kunde inte söka kunder. \(Self.readableDecodingError(error))"
        }
    }

    func loadUser(named name: String) async -> CogWorkUser? {
        guard hasCogWorkPassword else {
            errorMessage = "CogWork-lösenord krävs för kunduppgifter."
            return nil
        }

        isLoadingUsers = true
        errorMessage = nil
        defer { isLoadingUsers = false }

        do {
            let response: UsersResponse = try await publicAPI(path: "users", extra: [
                "name": name
            ])
            return response.users.first
        } catch {
            errorMessage = "Kunde inte hämta kund. \(error.localizedDescription)"
            return nil
        }
    }

    func loadBookings(forUserId userId: Int) async {
        guard hasCogWorkPassword else {
            errorMessage = "CogWork-lösenord krävs för deltagarens bokningar."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: BookingsResponse = try await publicAPI(path: "bookings", extra: [
                "userId": String(userId)
            ])
            selectedUserBookings = response.bookings
        } catch {
            errorMessage = "Kunde inte hämta deltagarens bokningar. \(error.localizedDescription)"
        }
    }

    func verifyCogWorkPassword(_ password: String) async -> Bool {
        do {
            let _: EventsResponse = try await publicAPI(path: "events", password: password, extra: [
                "maxRows": "1"
            ])
            cogWorkPassword = password
            return true
        } catch {
            return false
        }
    }

    /// Tvingar Workern att rensa cache och hämta färskt från CogWork ("Från CogWork"-knappen).
    func forceRefreshFromCogWork() async {
        guard let purgeURL = URL(string: "\(baseURL)/purge") else { return }
        isLoading = true
        defer { isLoading = false }
        _ = try? await URLSession.shared.data(from: purgeURL)
        await loadBookings()
    }

    // MARK: - Härledda värden för Översikt

    var totalCount: Int { bookings.count }

    var paidCount: Int { bookings.filter { $0.payment?.paid == true }.count }

    var unpaidCount: Int { bookings.filter { $0.payment?.paid == false }.count }

    private var hasCogWorkPassword: Bool {
        !cogWorkPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func proxyData(queryItems: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(string: baseURL + "/")
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func publicAPI<T: Decodable>(
        path: String,
        password: String? = nil,
        extra: [String: String] = [:]
    ) async throws -> T {
        var components = URLComponents(string: "\(publicBaseURL)/\(path)/")
        var queryItems = [
            URLQueryItem(name: "org", value: "sollentunadans"),
            URLQueryItem(name: "verbose", value: "1"),
            URLQueryItem(name: "maxRows", value: "1000")
        ]

        let passwordValue = password ?? cogWorkPassword
        if !passwordValue.isEmpty {
            queryItems.append(URLQueryItem(name: "pw", value: passwordValue))
        }

        for (key, value) in extra where !value.isEmpty {
            queryItems.removeAll { $0.name == key }
            queryItems.append(URLQueryItem(name: key, value: value))
        }

        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.userAuthenticationRequired)
        }

        if let apiError = try? JSONDecoder().decode(CogWorkErrorResponse.self, from: data),
           let firstError = apiError.firstError {
            throw CogWorkAPIError.message(firstError)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

private extension CogWorkService {
    static func readableDecodingError(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }

        switch decodingError {
        case .keyNotFound(let key, let context):
            return "Saknar fält \(path(context.codingPath + [key]))."
        case .typeMismatch(_, let context):
            return "Fel datatyp vid \(path(context.codingPath)). \(context.debugDescription)"
        case .valueNotFound(_, let context):
            return "Saknar värde vid \(path(context.codingPath))."
        case .dataCorrupted(let context):
            return "Ogiltig data vid \(path(context.codingPath)). \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    static func path(_ codingPath: [CodingKey]) -> String {
        let value = codingPath.map(\.stringValue).joined(separator: ".")
        return value.isEmpty ? "rot" : value
    }
}

private struct CogWorkErrorResponse: Decodable {
    let firstError: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let strings = try? container.decodeIfPresent([String].self, forKey: .errors) {
            firstError = strings.first
        } else if let objects = try? container.decodeIfPresent([CogWorkErrorObject].self, forKey: .errors) {
            firstError = objects.first?.msg
        } else {
            firstError = nil
        }
    }

    enum CodingKeys: String, CodingKey { case errors }
}

private struct CogWorkErrorObject: Decodable {
    let msg: String?
}

private enum CogWorkAPIError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        }
    }
}
