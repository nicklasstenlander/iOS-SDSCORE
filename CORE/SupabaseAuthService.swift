import Foundation
import Combine

/// Minimal Supabase Auth-klient via REST, utan externa beroenden.
/// Använder samma projekt som CORE-webbappen (sds-dashboard).
@MainActor
final class SupabaseAuthService: ObservableObject {
    static let shared = SupabaseAuthService()

    // Samma värden som i CORE-webbappens .env (VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY).
    // Anon-nyckeln är publik och avsedd att bäddas in i klienter, precis som i webappen.
    private let supabaseURL = "https://vuokkdtyhmhkvfizsnwm.supabase.co"
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ1b2trZHR5aG1oa3ZmaXpzbndtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MjEzMDAsImV4cCI6MjA5ODM5NzMwMH0.n4LdnB4n_J3zqgzo6wLg3oZsdQtZobLoC-VA4X-S9qw"

    @Published var isAuthenticated = false
    @Published var isLoading = true
    @Published var profile: UserProfile?
    @Published var errorMessage: String?

    private var accessToken: String?
    private var refreshTask: Task<String, Error>?
    private let refreshThreshold: TimeInterval = 5 * 60
    private let tokenKey = "sds_core_access_token"
    private let refreshKey = "sds_core_refresh_token"
    private let userIdKey = "sds_core_user_id"
    private let expiresAtKey = "sds_core_expires_at"

    init() {
        Task { await restoreSession() }
    }

    // MARK: - Inloggning

    func signIn(email: String, password: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=password") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["email": email, "password": password])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }

            if http.statusCode == 200 {
                let decoded = try JSONDecoder().decode(AuthTokenResponse.self, from: data)
                storeSession(decoded)
                isAuthenticated = true
                await loadProfile(userId: decoded.user.id)
            } else {
                let err = try? JSONDecoder().decode(AuthErrorResponse.self, from: data)
                errorMessage = err?.errorDescription ?? err?.msg ?? "Fel e-post eller lösenord."
            }
        } catch {
            errorMessage = "Kunde inte ansluta. Kontrollera din internetanslutning."
        }
    }

    func signOut() {
        refreshTask?.cancel()
        refreshTask = nil
        accessToken = nil
        profile = nil
        isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: refreshKey)
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: expiresAtKey)
    }

    // MARK: - Sessionsåterställning

    private func restoreSession() async {
        defer { isLoading = false }

        guard let token = UserDefaults.standard.string(forKey: tokenKey) else { return }
        accessToken = token

        do {
            let validToken = try await validAccessToken()
            if let userId = UserDefaults.standard.string(forKey: userIdKey) ?? userIdFromJWT(validToken) {
                UserDefaults.standard.set(userId, forKey: userIdKey)
                isAuthenticated = true
                await loadProfile(userId: userId)
            } else {
                signOut()
            }
        } catch {
            signOut()
        }
    }

    // MARK: - Hämta profil (user_profiles-tabellen)

    private func loadProfile(userId: String) async {
        do {
            let data = try await authenticatedProfileData(userId: userId)
            profile = try? JSONDecoder().decode(UserProfile.self, from: data)
        } catch AuthSessionError.unauthorized {
            signOut()
        } catch {
            // Profilen är icke-kritisk, men sessionsfel hanteras separat ovan.
        }
    }

    func validAccessToken() async throws -> String {
        if let token = accessToken ?? UserDefaults.standard.string(forKey: tokenKey),
           !shouldRefreshToken() {
            accessToken = token
            return token
        }

        return try await refreshAccessToken()
    }

    private func authenticatedProfileData(userId: String) async throws -> Data {
        do {
            let token = try await validAccessToken()
            return try await profileData(userId: userId, token: token)
        } catch AuthSessionError.unauthorized {
            _ = try await refreshAccessToken()
            let retryToken = try await validAccessToken()
            return try await profileData(userId: userId, token: retryToken)
        }
    }

    private func profileData(userId: String, token: String) async throws -> Data {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/user_profiles?select=*&id=eq.\(userId)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.pgrst.object+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode == 401 {
            throw AuthSessionError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return data
    }

    private func refreshAccessToken() async throws -> String {
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task { try await performRefresh() }
        refreshTask = task

        do {
            let token = try await task.value
            refreshTask = nil
            return token
        } catch {
            refreshTask = nil
            signOut()
            throw error
        }
    }

    private func performRefresh() async throws -> String {
        guard let refreshToken = UserDefaults.standard.string(forKey: refreshKey),
              let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=refresh_token") else {
            throw AuthSessionError.missingRefreshToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard http.statusCode == 200 else {
            throw AuthSessionError.refreshFailed
        }

        let decoded = try JSONDecoder().decode(AuthTokenResponse.self, from: data)
        storeSession(decoded)
        return decoded.accessToken
    }

    private func storeSession(_ response: AuthTokenResponse) {
        // TODO: flytta till Keychain före bredare distribution.
        let expiresAt = response.expiresAt.map(Date.init(timeIntervalSince1970:))
            ?? Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600))

        accessToken = response.accessToken
        UserDefaults.standard.set(response.accessToken, forKey: tokenKey)
        UserDefaults.standard.set(response.refreshToken, forKey: refreshKey)
        UserDefaults.standard.set(response.user.id, forKey: userIdKey)
        UserDefaults.standard.set(expiresAt.timeIntervalSince1970, forKey: expiresAtKey)
    }

    private func shouldRefreshToken(date: Date = Date()) -> Bool {
        let storedExpiry = UserDefaults.standard.object(forKey: expiresAtKey) as? Double
        let expiresAt = storedExpiry.map { Date(timeIntervalSince1970: $0) }
            ?? accessToken.flatMap(jwtExpirationDate)
            ?? UserDefaults.standard.string(forKey: tokenKey).flatMap(jwtExpirationDate)

        guard let expiresAt else { return true }
        return expiresAt.timeIntervalSince(date) <= refreshThreshold
    }

    private func userIdFromJWT(_ token: String) -> String? {
        jwtPayload(token)?["sub"] as? String
    }

    private func jwtExpirationDate(_ token: String) -> Date? {
        guard let exp = jwtPayload(token)?["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    private func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = payload.count % 4
        if padding > 0 {
            payload.append(String(repeating: "=", count: 4 - padding))
        }

        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: - Svarsmodeller

private struct AuthTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int?
    let expiresAt: TimeInterval?
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }

    struct AuthUser: Codable {
        let id: String
    }
}

private struct AuthErrorResponse: Codable {
    let msg: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case msg
        case errorDescription = "error_description"
    }
}

private enum AuthSessionError: Error {
    case missingRefreshToken
    case refreshFailed
    case unauthorized
}

// MARK: - Rollbaserade rättigheter

extension SupabaseAuthService {
    var isAdmin: Bool {
        profile?.role == "admin"
    }

    var canSeeFinancials: Bool {
        profile?.role == "admin"
    }
}
