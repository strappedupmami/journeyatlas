import AuthenticationServices
import SwiftUI

struct AppleSignInCard: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section("System Capability") {
                if let health = session.health {
                    Label(health.capabilities.appleOAuth ? "Apple OAuth available" : "Apple OAuth unavailable", systemImage: health.capabilities.appleOAuth ? "checkmark.seal.fill" : "xmark.seal")
                        .foregroundStyle(health.capabilities.appleOAuth ? .green : .orange)
                } else {
                    Label("Health pending", systemImage: "hourglass")
                }
            }

            Section("Sign in with Apple") {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await session.handleAppleAuthorization(result: result) }
                }
                .frame(height: 42)

                Button("Start Apple Web OAuth") {
                    Task {
                        await session.beginAppleWebSignIn { url in
                            openURL(url)
                        }
                    }
                }
            }

            Section("What is implemented") {
                Text("Native credential capture is scaffolded. Backend token exchange endpoint can be finalized once API hosting is live.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Atlas Auth")
        .toolbar {
            ToolbarItem {
                Button("Refresh") { Task { await session.refreshHealth() } }
            }
        }
    }
}
