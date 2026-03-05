import Foundation

enum APIError: Error, LocalizedError {
    case invalidResponse
    case invalidPath
    case insecureTransport
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .invalidPath:
            return "Blocked unsafe API path."
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
    private let slowLoadReporter: SlowLoadReporter

    init(
        baseURL: URL = AppEnvironment.apiBaseURL,
        session: URLSession = APIClient.makeSecureSession(),
        slowLoadReporter: SlowLoadReporter = SlowLoadReporter(source: "ios-app")
    ) {
        self.baseURL = baseURL
        self.session = session
        self.slowLoadReporter = slowLoadReporter
    }

    func health() async throws -> HealthResponse {
        try await get(path: "/health")
    }

    func startAppleOAuth(returnTo: String) async throws -> OAuthStartResponse {
        let escaped = returnTo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "/"
        return try await get(path: "/v1/auth/apple/start?return_to=\(escaped)")
    }

    func startGoogleOAuth(returnTo: String) async throws -> OAuthStartResponse {
        let escaped = returnTo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "/"
        return try await get(path: "/v1/auth/google/start?return_to=\(escaped)")
    }

    func authMe() async throws -> AuthMeResponse {
        try await get(path: "/v1/auth/me")
    }

    func logout() async throws {
        _ = try await postRaw(path: "/v1/auth/logout", body: EmptyPayload())
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

    func submitExecutionCheckin(payload: ExecutionCheckinPayload) async throws -> ExecutionCheckinResponse {
        try await post(path: "/v1/execution/checkin", body: payload)
    }

    func toggleExecutionTask(taskID: String, completed: Bool, collapsed: Bool? = nil) async throws -> ProactiveFeedResponse {
        let payload = ExecutionTaskTogglePayload(userID: nil, taskID: taskID, completed: completed, collapsed: collapsed)
        let response: ExecutionTaskMutationResponse = try await post(path: "/v1/execution/task/toggle", body: payload)
        return response.feed
    }

    func respondExecutionTask(
        taskID: String,
        completedParts: String?,
        incompleteParts: String?,
        note: String?,
        completed: Bool? = nil,
        collapsed: Bool? = nil
    ) async throws -> ProactiveFeedResponse {
        let payload = ExecutionTaskRespondPayload(
            userID: nil,
            taskID: taskID,
            completedParts: completedParts,
            incompleteParts: incompleteParts,
            note: note,
            completed: completed,
            collapsed: collapsed
        )
        let response: ExecutionTaskMutationResponse = try await post(path: "/v1/execution/task/respond", body: payload)
        return response.feed
    }

    func notesList() async throws -> NotesListResponse {
        try await get(path: "/v1/notes")
    }

    func chat(
        sessionID: String?,
        text: String,
        locale: String?,
        preferredFormat: String?,
        responseDepth: String?,
        responseTone: String?,
        includeProactive: Bool?
    ) async throws -> ConciergeChatResponse {
        try await post(
            path: "/v1/chat",
            body: ChatRequestPayload(
                sessionID: sessionID,
                text: text,
                locale: locale,
                userID: nil,
                preferredFormat: preferredFormat,
                responseDepth: responseDepth,
                responseTone: responseTone,
                includeProactive: includeProactive
            )
        )
    }

    func createBillingCheckoutSession() async throws -> BillingCheckoutSessionResponse {
        try await post(path: "/v1/billing/create_checkout_session", body: EmptyPayload())
    }

    func upsertNote(title: String, content: String) async throws {
        _ = try await postRaw(path: "/v1/notes/upsert", body: NoteUpsertPayload(userID: nil, title: title, content: content))
    }

    func submitFeedback(
        category: String,
        severity: String,
        message: String,
        tags: [String],
        source: String
    ) async throws {
        _ = try await postRaw(
            path: "/v1/feedback/submit",
            body: FeedbackSubmitPayload(
                userID: nil,
                category: category,
                severity: severity,
                message: message,
                tags: tags,
                targetEmployee: "product_team",
                source: source
            )
        )
    }

    func exchangeNativeApple(
        identityToken: String,
        authorizationCode: String?,
        email: String?,
        displayName: String?,
        locale: String
    ) async throws {
        _ = try await postRaw(
            path: "/v1/auth/apple/native",
            body: NativeAppleExchangePayload(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                email: email,
                displayName: displayName,
                locale: locale
            )
        )
    }

    func passkeyRegisterStart(displayName: String, locale: String) async throws -> PasskeyStartEnvelope {
        let data = try await postRaw(
            path: "/v1/auth/passkey/register/start",
            body: PasskeyRegistrationStartPayload(
                email: nil,
                displayName: displayName,
                locale: locale
            )
        )
        return try decodePasskeyStartEnvelope(data: data)
    }

    func passkeyRegisterFinish(payload: PasskeyRegistrationFinishPayload) async throws {
        _ = try await postRaw(path: "/v1/auth/passkey/register/finish", body: payload)
    }

    func passkeyLoginStart() async throws -> PasskeyStartEnvelope {
        let data = try await postRaw(
            path: "/v1/auth/passkey/login/start",
            body: PasskeyLoginStartPayload(email: nil)
        )
        return try decodePasskeyStartEnvelope(data: data)
    }

    func passkeyLoginFinish(payload: PasskeyLoginFinishPayload) async throws -> AuthLoginResponse {
        try await post(path: "/v1/auth/passkey/login/finish", body: payload)
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        let request = try request(path: path, method: "GET")
        let (data, response) = try await performDataRequest(request: request, path: path, method: "GET")
        return try decode(T.self, data: data, response: response)
    }

    private func post<T: Decodable, Body: Encodable>(path: String, body: Body) async throws -> T {
        let request = try request(path: path, method: "POST", body: body)
        let (data, response) = try await performDataRequest(request: request, path: path, method: "POST")
        return try decode(T.self, data: data, response: response)
    }

    private func postRaw<Body: Encodable>(path: String, body: Body) async throws -> Data {
        let request = try request(path: path, method: "POST", body: body)
        let (data, response) = try await performDataRequest(request: request, path: path, method: "POST")
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode, message: String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        return data
    }

    private func performDataRequest(request: URLRequest, path: String, method: String) async throws -> (Data, URLResponse) {
        let startedAt = Date()
        do {
            let (data, response) = try await session.data(for: request)
            slowLoadReporter.reportIfNeeded(
                apiBaseURL: baseURL,
                method: method,
                path: path,
                response: response,
                startedAt: startedAt,
                errorDescription: nil
            )
            return (data, response)
        } catch {
            slowLoadReporter.reportIfNeeded(
                apiBaseURL: baseURL,
                method: method,
                path: path,
                response: nil,
                startedAt: startedAt,
                errorDescription: String(describing: error)
            )
            throw error
        }
    }

    private func request(path: String, method: String) throws -> URLRequest {
        try baseRequest(path: path, method: method, bodyData: nil)
    }

    private func request<Body: Encodable>(path: String, method: String, body: Body) throws -> URLRequest {
        let encoded = try JSONEncoder().encode(body)
        return try baseRequest(path: path, method: method, bodyData: encoded)
    }

    private func baseRequest(path: String, method: String, bodyData: Data?) throws -> URLRequest {
        guard !path.contains("://"), !path.starts(with: "//") else {
            throw APIError.invalidPath
        }
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidResponse
        }
        if let expectedHost = baseURL.host?.lowercased(),
           let actualHost = url.host?.lowercased(),
           expectedHost != actualHost
        {
            throw APIError.invalidPath
        }
        guard Self.isSecureTransport(url: url) else {
            throw APIError.insecureTransport
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("AtlasMasaMobile/1.0", forHTTPHeaderField: "X-Client")
        request.setValue(Self.originHeaderValue(for: baseURL), forHTTPHeaderField: "Origin")
        request.timeoutInterval = 20
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
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

    private func decodePasskeyStartEnvelope(data: Data) throws -> PasskeyStartEnvelope {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        guard let requestID = object["request_id"] as? String,
              !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw APIError.invalidResponse
        }
        guard let options = object["options"] as? [String: Any] else {
            throw APIError.invalidResponse
        }
        return PasskeyStartEnvelope(requestID: requestID, options: options)
    }

    private static func makeSecureSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
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

    private static func originHeaderValue(for baseURL: URL) -> String {
        let host = (baseURL.host ?? "").lowercased()
        if host == "localhost" || host == "127.0.0.1" {
            let scheme = (baseURL.scheme ?? "").lowercased() == "https" ? "https" : "http"
            if let port = baseURL.port {
                return "\(scheme)://\(host):\(port)"
            }
            return "\(scheme)://\(host):5500"
        }
        return "https://atlasmasa.com"
    }
}

struct PasskeyStartEnvelope: @unchecked Sendable {
    let requestID: String
    let options: [String: Any]
}

struct SlowLoadReporter {
    private let source: String
    private let thresholdMs: Int
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let iso8601 = ISO8601DateFormatter()

    init(source: String, thresholdMs: Int = 4500, session: URLSession? = nil) {
        self.source = source
        self.thresholdMs = max(thresholdMs, 1)
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 8
            self.session = URLSession(configuration: config)
        }
    }

    func reportIfNeeded(
        apiBaseURL: URL,
        method: String,
        path: String,
        response: URLResponse?,
        startedAt: Date,
        errorDescription: String?
    ) {
        let durationMs = max(Int(Date().timeIntervalSince(startedAt) * 1000), 0)
        guard durationMs >= thresholdMs else {
            return
        }
        guard let endpoint = endpointURL(for: apiBaseURL) else {
            return
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        let payload = SlowLoadEventPayload(
            kind: "network-request",
            source: source,
            url: absoluteURLString(for: apiBaseURL, path: path),
            referrer: "",
            userAgent: "AtlasMasaMobile/1.0",
            timestamp: iso8601.string(from: Date()),
            thresholdMs: thresholdMs,
            metrics: [
                "requestDurationMs": durationMs,
                "httpStatus": statusCode
            ],
            connection: nil,
            error: cleanedError(errorDescription),
            method: method
        )

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 8
            request.httpBody = try encoder.encode(payload)
            session.dataTask(with: request).resume()
        } catch {
            // Silent failure by design.
        }
    }

    private func cleanedError(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return String(value.prefix(200))
    }

    private func absoluteURLString(for apiBaseURL: URL, path: String) -> String {
        URL(string: path, relativeTo: apiBaseURL)?.absoluteString ?? path
    }

    private func endpointURL(for apiBaseURL: URL) -> URL? {
        let host = (apiBaseURL.host ?? "").lowercased()
        let scheme = (apiBaseURL.scheme ?? "https").lowercased()
        if host == "localhost" || host == "127.0.0.1" {
            return URL(string: "\(scheme)://\(host):3000/api/ops/slow-load")
        }
        return URL(string: "https://atlasmasa.com/api/ops/slow-load")
    }
}

private struct SlowLoadEventPayload: Encodable {
    let kind: String
    let source: String
    let url: String
    let referrer: String
    let userAgent: String
    let timestamp: String
    let thresholdMs: Int
    let metrics: [String: Int]
    let connection: SlowLoadConnectionPayload?
    let error: String?
    let method: String
}

private struct SlowLoadConnectionPayload: Encodable {
    let effectiveType: String?
    let downlinkMbps: Int?
    let rttMs: Int?
    let saveData: Bool?
}

private struct EmptyPayload: Encodable {}

private struct FeedbackSubmitPayload: Encodable {
    let userID: String?
    let category: String
    let severity: String
    let message: String
    let tags: [String]
    let targetEmployee: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case category
        case severity
        case message
        case tags
        case targetEmployee = "target_employee"
        case source
    }
}
