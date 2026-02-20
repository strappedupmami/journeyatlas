import Foundation

enum AppEnvironment {
    static let apiBaseKey = "atlas.api.base"

    static var apiBaseURL: URL {
        if let custom = UserDefaults.standard.string(forKey: apiBaseKey),
           let url = URL(string: custom.trimmingCharacters(in: .whitespacesAndNewlines)),
           !custom.isEmpty {
            return url
        }
        return URL(string: "https://api.atlasmasa.com")!
    }
}
