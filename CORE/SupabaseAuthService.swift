import Foundation
import Combine

/// Minimal Supabase Auth-klient via REST, utan externa beroenden.
/// Använder samma projekt som CORE-webbappen (sds-dashboard).
@MainActor
final class SupabaseAuthService: ObservableObject {
    // Samma värden som i CORE-webbappens .env (VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY).
    // Anon-nyckeln är publik och avsedd att bäddas in i klienter, precis som i webappen.
    private let supabaseURL = "https://vuokkdtyhmhkvfizsnwm.supabase.co"
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ1b2trZHR5aG1oa3ZmaXpzbndtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MjEzMDAsImV4cCI6MjA5ODM5NzMwMH0.n4LdnB4n_J3zqgzo6wLg3oZsdQtZobLoC-VA4X-S9qw"

    @Published var isAuthenticated = false
    @Published var isLoading = true
    @Published var profile: UserProfile?
    @Published var errorMessage: String?

    private var accessToken: String?
    private let tokenKey = "sds_core_access_token"
    private let refreshKey = "sds_core_refresh_token"
    private let userIdKey = "sds_core_user_id"

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
                accessToken = decoded.accessToken
                UserDefaults.standard.set(decoded.accessToken, forKey: tokenKey)
                UserDefaults.standard.set(decoded.refreshToken, forKey: refreshKey)
                UserDefaults.standard.set(decoded.user.id, forKey: userIdKey)
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
        accessToken = nil
        profile = nil
        isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: refreshKey)
        UserDefaults.standard.removeObject(forKey: userIdKey)
    }

    // MARK: - Sessionsåterställning (enkel, förnyar inte token — för första testversionen räcker det)

    private func restoreSession() async {
        if let token = UserDefaults.standard.string(forKey: tokenKey) {
            accessToken = token
            isAuthenticated = true
            if let userId = UserDefaults.standard.string(forKey: userIdKey) ?? userIdFromJWT(token) {
                UserDefaults.standard.set(userId, forKey: userIdKey)
                await loadProfile(userId: userId)
            }
            // OBS: i denna första testversion görs ingen refresh-token-förnyelse.
            // Om token gått ut loggas man ut nästa gång ett anrop misslyckas (401).
        }
        isLoading = false
    }

    // MARK: - Hämta profil (user_profiles-tabellen)

    private func loadProfile(userId: String) async {
        guard let token = accessToken,
              let url = URL(string: "\(supabaseURL)/rest/v1/user_profiles?select=*&id=eq.\(userId)") else { return }

        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.pgrst.object+json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            profile = try? JSONDecoder().decode(UserProfile.self, from: data)
        } catch {
            // Icke-kritiskt för första testversionen — appen fungerar utan profilnamn.
        }
    }

    private func userIdFromJWT(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = payload.count % 4
        if padding > 0 {
            payload.append(String(repeating: "=", count: 4 - padding))
        }

        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = object["sub"] as? String else {
            return nil
        }

        return subject
    }
}

// MARK: - Svarsmodeller

private struct AuthTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
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
