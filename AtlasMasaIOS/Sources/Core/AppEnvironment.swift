import Foundation

enum AppEnvironment {
    static let apiBaseKey = "atlas.api.base"
    private static let productionHosts: Set<String> = [
        "api.atlasmasa.com",
        "journeyatlas-production.up.railway.app",
    ]

    private static func isAllowedLocalHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1"
    }

    private static func isAllowedProductionHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return productionHosts.contains(host)
    }

    private static func isSecureAPIURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        if scheme == "https" {
#if DEBUG
            return true
#else
            return isAllowedProductionHost(url.host)
#endif
        }
        if scheme == "http", isAllowedLocalHost(url.host) {
#if DEBUG
            return true
#else
            return false
#endif
        }
        return false
    }

    static var apiBaseURL: URL {
#if DEBUG
        if let custom = UserDefaults.standard.string(forKey: apiBaseKey) {
            let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed),
               !trimmed.isEmpty,
               isSecureAPIURL(url)
            {
                return url
            }
        }
#endif

        let fallback = URL(string: "https://api.atlasmasa.com")!
        if isSecureAPIURL(fallback) {
            return fallback
        }
        return URL(string: "https://journeyatlas-production.up.railway.app")!
    }
}
