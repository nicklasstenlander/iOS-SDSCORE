import Foundation

/// Fel som visas för användaren vid anrop mot sds-cogwork-proxy.
enum APIClientError: LocalizedError {
    case unauthorized
    case forbidden
    case server(Int)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Sessionen har gått ut. Logga in igen."
        case .forbidden:
            return "Saknar behörighet för detta."
        case .server(let code):
            return "Serverfel (\(code))."
        case .transport(let error):
            return error.localizedDescription
        }
    }
}

/// Gemensam klient för anrop mot workern (sds-cogwork-proxy). Sätter alltid
/// Authorization: Bearer <Supabase access token>. Vid 401 förnyas token en gång
/// och anropet görs om; misslyckas det loggas användaren ut.
enum APIClient {
    static func data(for request: URLRequest) async throws -> Data {
        let auth = SupabaseAuthService.shared
        let token: String
        do {
            token = try await auth.validAccessToken()
        } catch {
            throw APIClientError.unauthorized
        }

        let (firstData, firstResponse) = try await perform(request, token: token)
        guard let firstHTTP = firstResponse as? HTTPURLResponse else {
            throw APIClientError.transport(URLError(.badServerResponse))
        }

        guard firstHTTP.statusCode == 401 else {
            return try validated(firstData, firstHTTP)
        }

        guard let refreshedToken = try? await auth.refreshAccessToken() else {
            await auth.signOut()
            throw APIClientError.unauthorized
        }

        let (retryData, retryResponse) = try await perform(request, token: refreshedToken)
        guard let retryHTTP = retryResponse as? HTTPURLResponse else {
            throw APIClientError.transport(URLError(.badServerResponse))
        }

        if retryHTTP.statusCode == 401 {
            await auth.signOut()
            throw APIClientError.unauthorized
        }

        return try validated(retryData, retryHTTP)
    }

    static func json<T: Decodable>(_ type: T.Type, for request: URLRequest) async throws -> T {
        let data = try await data(for: request)
        return try JSONDecoder().decode(type, from: data)
    }

    static func request(
        url: URL,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        jsonBody: [String: Any]? = nil
    ) throws -> URLRequest {
        var finalURL = url
        if let queryItems, !queryItems.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = queryItems
            guard let composed = components?.url else { throw URLError(.badURL) }
            finalURL = composed
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = method

        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }

        return request
    }

    private static func perform(_ request: URLRequest, token: String) async throws -> (Data, URLResponse) {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await URLSession.shared.data(for: request)
    }

    private static func validated(_ data: Data, _ http: HTTPURLResponse) throws -> Data {
        switch http.statusCode {
        case 200..<300:
            return data
        case 403:
            throw APIClientError.forbidden
        default:
            throw APIClientError.server(http.statusCode)
        }
    }
}
