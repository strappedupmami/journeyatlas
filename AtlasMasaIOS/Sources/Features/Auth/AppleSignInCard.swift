import AuthenticationServices
import SwiftUI

struct AppleSignInCard: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        AtlasScreen(
            title: "Account Access",
            subtitle: "Traditional provider auth plus passwordless flows, no legacy passwords"
        ) {
            AtlasPanel(heading: "Provider status", caption: "Live capability check from Rust API when available") {
                if let health = session.health {
                    capabilityRow("Apple", available: health.capabilities.appleOAuth)
                    capabilityRow("Google", available: health.capabilities.googleOAuth)
                    capabilityRow("Passkey", available: health.capabilities.passkey)
                    capabilityRow("Billing", available: health.capabilities.billing)
                } else {
                    Text("Health check pending. Refresh to verify provider readiness.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                }

                Button("Refresh provider status") {
                    Task { await session.refreshHealth() }
                }
                .buttonStyle(AtlasSecondaryButtonStyle())
            }

            AtlasPanel(heading: "Sign up", caption: "Create secure account using provider auth or passwordless") {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await session.handleAppleAuthorization(result: result) }
                }
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack {
                    Button("Sign up with Google") {
                        session.signInWithGooglePlaceholder()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())

                    Button("Passwordless sign up") {
                        session.signUpWithPasswordless()
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())
                }

                Button("Start Apple OAuth in browser") {
                    Task {
                        await session.beginAppleWebSignIn { url in
                            openURL(url)
                        }
                    }
                }
                .buttonStyle(AtlasSecondaryButtonStyle())
            }

            AtlasPanel(heading: "Sign in", caption: "Use secure provider session or passwordless entry") {
                HStack {
                    Button("Sign in with Google") {
                        session.signInWithGooglePlaceholder()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())

                    Button("Passwordless sign in") {
                        session.signInWithPasswordless()
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())
                }

                if session.isSignedIn {
                    HStack {
                        Text("Active account: \(session.accountLabel)")
                            .foregroundStyle(AtlasTheme.textSecondary)
                        Spacer()
                        Button("Sign out") {
                            session.signOut()
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                    }
                }
            }
        }
    }

    private func capabilityRow(_ title: String, available: Bool) -> some View {
        HStack {
            Image(systemName: available ? "checkmark.seal.fill" : "xmark.seal")
                .foregroundStyle(available ? .green : .orange)
            Text("\(title): \(available ? "available" : "pending")")
                .foregroundStyle(AtlasTheme.textPrimary)
            Spacer()
        }
    }
}
