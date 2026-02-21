import Foundation

enum APIError: Error, LocalizedError {
    case invalidResponse
    case insecureTransport
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .insecureTransport:
            return "Blocked insecure API transport. Use HTTPS (HTTP only allowed on localhost)."
        case let .server(status, message):
            return "Server error (\(status)): \(message)"
        }
    }
}

struct APIClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = AppEnvironment.apiBaseURL, session: URLSession = APIClient.makeSecureSession()) {
        self.baseURL = baseURL
        self.session = session
    }

    func health() async throws -> HealthResponse {
        try await get(path: "/health")
    }

    func startAppleOAuth(returnTo: String) async throws -> OAuthStartResponse {
        let escaped = returnTo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "/"
        return try await get(path: "/v1/auth/apple/start?return_to=\(escaped)")
    }

    func surveyNext() async throws -> SurveyNextResponse {
        try await get(path: "/v1/survey/next")
    }

    func submitSurveyAnswer(questionID: String, answer: String) async throws -> SurveyNextResponse {
        try await post(path: "/v1/survey/answer", body: SurveyAnswerPayload(userID: nil, questionID: questionID, answer: answer))
    }

    func feedProactive() async throws -> ProactiveFeedResponse {
        try await get(path: "/v1/feed/proactive")
    }

    func notesList() async throws -> NotesListResponse {
        try await get(path: "/v1/notes")
    }

    func upsertNote(title: String, content: String) async throws {
        _ = try await postRaw(path: "/v1/notes/upsert", body: NoteUpsertPayload(userID: nil, title: title, content: content))
    }

    func exchangeNativeApple(identityToken: String, authorizationCode: String?, locale: String) async throws {
        // Scaffold endpoint for native Sign in with Apple exchange.
        _ = try await postRaw(path: "/v1/auth/apple/native", body: NativeAppleExchangePayload(identityToken: identityToken, authorizationCode: authorizationCode, locale: locale))
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        let request = try request(path: path, method: "GET")
        let (data, response) = try await session.data(for: request)
        return try decode(T.self, data: data, response: response)
    }

    private func post<T: Decodable, Body: Encodable>(path: String, body: Body) async throws -> T {
        let request = try request(path: path, method: "POST", body: body)
        let (data, response) = try await session.data(for: request)
        return try decode(T.self, data: data, response: response)
    }

    private func postRaw<Body: Encodable>(path: String, body: Body) async throws -> Data {
        let request = try request(path: path, method: "POST", body: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode, message: String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        return data
    }

    private func request<Body: Encodable>(path: String, method: String, body: Body? = nil) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidResponse
        }
        guard Self.isSecureTransport(url: url) else {
            throw APIError.insecureTransport
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode, message: String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private static func makeSecureSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        if #available(iOS 13.0, macOS 10.15, *) {
            config.tlsMinimumSupportedProtocolVersion = .TLSv12
        }
        return URLSession(configuration: config)
    }

    private static func isSecureTransport(url: URL) -> Bool {
        let scheme = (url.scheme ?? "").lowercased()
        if scheme == "https" {
            return true
        }
        if scheme == "http" {
            let host = (url.host ?? "").lowercased()
            return host == "localhost" || host == "127.0.0.1"
        }
        return false
    }
}
