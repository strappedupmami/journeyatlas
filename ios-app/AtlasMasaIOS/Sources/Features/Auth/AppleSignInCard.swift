import AuthenticationServices
import SwiftUI

struct AppleSignInCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "Account",
            subtitle: "Combined sign-up/sign-in with Apple, Google, and Passwordless (more secure)"
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

            AtlasPanel(
                heading: "How account state drives personalization",
                caption: "Why this is the entry gate for long-term memory and execution plans"
            ) {
                Text("Atlas uses secure account identity to persist your personalization graph across sessions and devices. The AI uses your signed-in data (survey, notes, queue outputs, and workspace sessions) to produce tailored execution plans.")
                    .foregroundStyle(AtlasTheme.textSecondary)
                Text("No legacy passwords are used: provider auth + passkeys + secure sessions.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.accentWarm)
            }

            AtlasPanel(
                heading: "Secure account (sign up / sign in)",
                caption: "One combined flow. Choose your preferred secure method."
            ) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await session.handleAppleAuthorization(result: result) }
                }
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 10) {
                    Button("Continue with Google") {
                        session.signInWithGooglePlaceholder()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())

                    Button("Passwordless (more secure) Sign in") {
                        session.signInWithPasswordless()
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())
                }

                Button("Passwordless (more secure) Sign up") {
                    session.signUpWithPasswordless()
                }
                .buttonStyle(AtlasSecondaryButtonStyle())

                Text(session.accountStatusMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.textSecondary)

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
