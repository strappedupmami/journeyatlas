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
        slowLoadReporter: SlowLoadReporter = SlowLoadReporter(source: "macos-app")
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
        includeProactive: Bool?,
        codeAgentRoute: String? = nil,
        preferredCloudModel: String? = nil,
        cloudFallbackModel: String? = nil
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
                includeProactive: includeProactive,
                codeAgentRoute: codeAgentRoute,
                preferredCloudModel: preferredCloudModel,
                cloudFallbackModel: cloudFallbackModel
            )
        )
    }

    func upsertNote(title: String, content: String) async throws {
        _ = try await postRaw(path: "/v1/notes/upsert", body: NoteUpsertPayload(userID: nil, title: title, content: content))
    }

    func exchangeNativeApple(identityToken: String, authorizationCode: String?, locale: String) async throws {
        // Scaffold endpoint for native Sign in with Apple exchange.
        _ = try await postRaw(path: "/v1/auth/apple/native", body: NativeAppleExchangePayload(identityToken: identityToken, authorizationCode: authorizationCode, locale: locale))
    }

    func createRAndDJob(payload: RAndDJobCreatePayload) async throws -> RAndDJobResponse {
        try await post(path: "/v1/rnd/jobs", body: payload)
    }

    func rAndDJob(jobID: String) async throws -> RAndDJobResponse {
        try await get(path: "/v1/rnd/jobs/\(jobID)")
    }

    func reviseRAndDPlan(jobID: String, revisionPrompt: String) async throws -> RAndDJobResponse {
        try await post(
            path: "/v1/rnd/jobs/\(jobID)/plan/revise",
            body: RAndDPlanRevisePayload(revisionPrompt: revisionPrompt)
        )
    }

    func approveRAndDPlan(jobID: String) async throws -> RAndDJobResponse {
        try await post(path: "/v1/rnd/jobs/\(jobID)/plan/approve", body: EmptyPayload())
    }

    func approveRAndDStage(jobID: String, note: String?) async throws -> RAndDJobResponse {
        try await post(
            path: "/v1/rnd/jobs/\(jobID)/stage/approve",
            body: RAndDStageApprovePayload(note: note)
        )
    }

    func pauseRAndDExecution(jobID: String, pauseAfterCurrentStage: Bool = true) async throws -> RAndDJobResponse {
        try await post(
            path: "/v1/rnd/jobs/\(jobID)/pause",
            body: RAndDPausePayload(pauseAfterCurrentStage: pauseAfterCurrentStage)
        )
    }

    func submitRAndDChangeRequest(
        jobID: String,
        scope: String?,
        targetPartID: String?,
        request: String
    ) async throws -> RAndDJobResponse {
        try await post(
            path: "/v1/rnd/jobs/\(jobID)/change_request",
            body: RAndDChangeRequestPayload(scope: scope, targetPartID: targetPartID, request: request)
        )
    }

    func rAndDArtifacts(jobID: String) async throws -> RAndDArtifactsResponse {
        try await get(path: "/v1/rnd/jobs/\(jobID)/artifacts")
    }

    func rAndDTimeline(jobID: String) async throws -> RAndDTimelineResponse {
        try await get(path: "/v1/rnd/jobs/\(jobID)/timeline")
    }

    func rAndDGovernance(jobID: String) async throws -> RAndDGovernanceResponse {
        try await get(path: "/v1/rnd/jobs/\(jobID)/governance")
    }

    func rAndDTraceability(jobID: String) async throws -> RAndDTraceabilityResponse {
        try await get(path: "/v1/rnd/jobs/\(jobID)/traceability")
    }

    func rAndDDoctrine(jobID: String) async throws -> RAndDDoctrineResponse {
        try await get(path: "/v1/rnd/jobs/\(jobID)/doctrine")
    }

    func rAndDDocuments(jobID: String) async throws -> RAndDDocumentsResponse {
        try await get(path: "/v1/rnd/jobs/\(jobID)/documents")
    }

    func recordRAndDReview(
        jobID: String,
        title: String?,
        status: String?,
        note: String?
    ) async throws -> RAndDJobResponse {
        try await post(
            path: "/v1/rnd/jobs/\(jobID)/reviews/record",
            body: RAndDReviewRecordPayload(
                title: title,
                status: status,
                note: note,
                requirementIDs: nil,
                decisionIDs: nil,
                evidenceIDs: nil
            )
        )
    }

    func generateRAndDReport(
        jobID: String,
        title: String?,
        reportType: String?
    ) async throws -> RAndDJobResponse {
        try await post(
            path: "/v1/rnd/jobs/\(jobID)/reports/generate",
            body: RAndDReportGeneratePayload(title: title, reportType: reportType)
        )
    }

    func generateRAndDDocument(
        jobID: String,
        payload: RAndDDocumentGeneratePayload
    ) async throws -> RAndDJobResponse {
        try await post(path: "/v1/rnd/jobs/\(jobID)/documents/generate", body: payload)
    }

    func generateRAndDDocumentBundle(
        jobID: String,
        payload: RAndDDocumentBundleGeneratePayload
    ) async throws -> RAndDJobResponse {
        try await post(path: "/v1/rnd/jobs/\(jobID)/documents/bundle/generate", body: payload)
    }

    func recordRAndDApproval(
        jobID: String,
        payload: RAndDApprovalRecordPayload
    ) async throws -> RAndDJobResponse {
        try await post(path: "/v1/rnd/jobs/\(jobID)/approvals/record", body: payload)
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
            userAgent: "AtlasMasaDesktop/1.0",
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
