import Foundation

@MainActor
final class DesktopRemoteControlStore: ObservableObject {
    enum DispatchTarget: String, CaseIterable, Identifiable {
        case localQwen = "local_qwen"
        case cloudGPT54 = "cloud_gpt5_4"

        var id: String { rawValue }
        var title: String {
            switch self {
            case .localQwen: return "Qwen"
            case .cloudGPT54: return "GPT-5.4"
            }
        }
    }

    enum CodingRoute: String, CaseIterable, Identifiable {
        case auto
        case frontendDesign = "frontend_design"
        case backendOps = "backend_ops"

        var id: String { rawValue }
        var title: String {
            switch self {
            case .auto: return "Auto"
            case .frontendDesign: return "Frontend"
            case .backendOps: return "Backend"
            }
        }
    }

    @Published var baseURLText: String
    @Published var tokenText: String
    @Published var draftPrompt = ""
    @Published var selectedTarget: DispatchTarget
    @Published var selectedRoute: CodingRoute
    @Published var connectionStatus = "Enter the desktop URL and pairing token from BlackHaven."
    @Published var desktopName = "No desktop connected"
    @Published var runtimeSummary = "Status pending"
    @Published var localModel = "qwen2.5:7b"
    @Published var queueDepth = 0
    @Published var lastAction = "No remote actions yet."
    @Published var isBusy = false

    private let defaults = UserDefaults.standard
    private let baseURLKey = "atlas.remote.desktop.base_url"
    private let tokenKey = "atlas.remote.desktop.token"
    private let targetKey = "atlas.remote.desktop.target"
    private let routeKey = "atlas.remote.desktop.route"

    init() {
        baseURLText = defaults.string(forKey: baseURLKey) ?? "http://127.0.0.1:8765"
        tokenText = defaults.string(forKey: tokenKey) ?? ""
        selectedTarget = DispatchTarget(rawValue: defaults.string(forKey: targetKey) ?? "") ?? .localQwen
        selectedRoute = CodingRoute(rawValue: defaults.string(forKey: routeKey) ?? "") ?? .auto
    }

    func refreshStatus() async {
        guard let request = buildRequest(path: "/api/remote/status", method: "GET") else {
            connectionStatus = "Desktop URL is invalid. Use http://<desktop-ip>:8765 or https://..."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                connectionStatus = "Desktop response was invalid."
                return
            }
            guard http.statusCode == 200 else {
                connectionStatus = "Desktop rejected the request (\(http.statusCode)). Check the pairing token."
                return
            }

            let status = try JSONDecoder().decode(RemoteDesktopStatusResponse.self, from: data)
            desktopName = "\(status.appName) on \(status.deviceName)"
            runtimeSummary = status.runtimeStatus
            localModel = status.localModel
            queueDepth = status.queueDepth
            lastAction = status.lastAction
            connectionStatus = status.runtimeDetail
            persist()
        } catch {
            connectionStatus = "Could not reach desktop remote control: \(error.localizedDescription)"
        }
    }

    func sendPrompt() async {
        let cleaned = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            connectionStatus = "Write a prompt before sending it to the desktop."
            return
        }
        guard let request = buildDispatchRequest(prompt: cleaned) else {
            connectionStatus = "Desktop URL is invalid. Use http://<desktop-ip>:8765 or https://..."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                connectionStatus = "Desktop response was invalid."
                return
            }
            let dispatch = try JSONDecoder().decode(RemoteDesktopDispatchResponse.self, from: data)
            connectionStatus = dispatch.message
            lastAction = dispatch.message
            queueDepth = dispatch.queueDepth
            if http.statusCode == 200 {
                draftPrompt = ""
            }
            persist()
        } catch {
            connectionStatus = "Could not send prompt to desktop: \(error.localizedDescription)"
        }
    }

    private func buildDispatchRequest(prompt: String) -> URLRequest? {
        guard var request = buildRequest(path: "/api/remote/dispatch", method: "POST") else {
            return nil
        }
        let payload = RemoteDesktopDispatchRequest(
            prompt: prompt,
            target: selectedTarget.rawValue,
            route: selectedTarget == .cloudGPT54 ? selectedRoute.rawValue : nil
        )
        request.httpBody = try? JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func buildRequest(path: String, method: String) -> URLRequest? {
        guard let base = normalizedBaseURL() else { return nil }
        let url = base.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        if !tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(tokenText.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func normalizedBaseURL() -> URL? {
        let trimmed = baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased()
        else {
            return nil
        }

        if scheme == "https" {
            return url
        }

        guard scheme == "http", Self.isPrivateNetworkHost(host) else {
            return nil
        }
        return url
    }

    private static func isPrivateNetworkHost(_ host: String) -> Bool {
        host == "localhost"
            || host == "127.0.0.1"
            || host.hasPrefix("10.")
            || host.hasPrefix("192.168.")
            || host.hasPrefix("172.16.")
            || host.hasPrefix("172.17.")
            || host.hasPrefix("172.18.")
            || host.hasPrefix("172.19.")
            || host.hasPrefix("172.20.")
            || host.hasPrefix("172.21.")
            || host.hasPrefix("172.22.")
            || host.hasPrefix("172.23.")
            || host.hasPrefix("172.24.")
            || host.hasPrefix("172.25.")
            || host.hasPrefix("172.26.")
            || host.hasPrefix("172.27.")
            || host.hasPrefix("172.28.")
            || host.hasPrefix("172.29.")
            || host.hasPrefix("172.30.")
            || host.hasPrefix("172.31.")
    }

    private func persist() {
        defaults.set(baseURLText, forKey: baseURLKey)
        defaults.set(tokenText, forKey: tokenKey)
        defaults.set(selectedTarget.rawValue, forKey: targetKey)
        defaults.set(selectedRoute.rawValue, forKey: routeKey)
    }
}

private struct RemoteDesktopStatusResponse: Decodable {
    let appName: String
    let deviceName: String
    let runtimeStatus: String
    let runtimeDetail: String
    let localModel: String
    let queueDepth: Int
    let lastAction: String

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case deviceName = "device_name"
        case runtimeStatus = "runtime_status"
        case runtimeDetail = "runtime_detail"
        case localModel = "local_model"
        case queueDepth = "queue_depth"
        case lastAction = "last_action"
    }
}

private struct RemoteDesktopDispatchRequest: Encodable {
    let prompt: String
    let target: String
    let route: String?
}

private struct RemoteDesktopDispatchResponse: Decodable {
    let message: String
    let queueDepth: Int

    enum CodingKeys: String, CodingKey {
        case message
        case queueDepth = "queue_depth"
    }
}
