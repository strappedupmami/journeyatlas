import AuthenticationServices
import SwiftUI

// MARK: - Auth Mode Enum
private enum AuthMode: String, CaseIterable, Identifiable {
    case signIn = "Sign In"
    case signUp = "Create Account"
    var id: String { self.rawValue }
}

struct AppleSignInCard: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.openURL) private var openURL

    // UI State
    @State private var authMode: AuthMode = .signIn

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // High-End Top Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Account Access")
                        .font(.largeTitle.weight(.bold))
                    Text("Secure, passwordless identity for cross-device personalization")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                // Two-Column Desktop Layout
                HStack(alignment: .top, spacing: 32) {
                    // MARK: - LEFT COLUMN: Active Auth Box
                    VStack(spacing: 0) {
                        if session.isSignedIn {
                            activeProfileCard
                        } else {
                            authenticationCard
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    // MARK: - RIGHT COLUMN: System Status & Info
                    VStack(spacing: 24) {
                        providerStatusCard
                        securityExplainerCard
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(32)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if session.health == nil {
                Task { await session.refreshHealth() }
            }
        }
    }

    // MARK: - Auth Views (Left Column)

    private var authenticationCard: some View {
        AtlasPanel(heading: authMode.rawValue, caption: "Use a secure provider or passwordless entry") {
            VStack(spacing: 20) {
                // Segmented Control for Mode Switching
                Picker("Mode", selection: $authMode) {
                    ForEach(AuthMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 8)

                // Primary Apple Auth (Native Button)
                SignInWithAppleButton(authMode == .signIn ? .signIn : .signUp) { request in
                    request.requestedScopes = [.fullName, .email]
                    session.appendOutput("Starting native Apple sign-in...")
                } onCompletion: { result in
                    Task {
                        await session.handleAppleAuthorization(result: result)
                        if case let .failure(error) = result, shouldAutoFallbackToWeb(error) {
                            await session.beginAppleWebSignIn { url in openURL(url) }
                        }
                    }
                }
                .frame(height: 44)
                .signInWithAppleButtonStyle(.whiteOutline) // Mac-appropriate styling

                HStack {
                    VStack { Divider() }
                    Text("OR").font(.caption).foregroundStyle(.secondary)
                    VStack { Divider() }
                }
                .padding(.vertical, 8)

                // Unified Secondary Actions
                VStack(spacing: 12) {
                    Button(action: {
                        Task { await session.beginGoogleWebSignIn { url in openURL(url) } }
                    }) {
                        Label("Continue with Google", systemImage: "g.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                    .controlSize(.large)

                    Button(action: {
                        if authMode == .signIn {
                            session.signInWithPasswordless()
                        } else {
                            session.signUpWithPasswordless()
                        }
                    }) {
                        Label(authMode == .signIn ? "Passwordless Sign In" : "Passwordless Sign Up", systemImage: "key.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())
                    .controlSize(.large)
                }

                Button("Start Apple OAuth in browser") {
                    Task { await session.beginAppleWebSignIn { url in openURL(url) } }
                }
                .buttonStyle(.link)
                .font(.caption)
                .padding(.top, 8)
            }
        }
    }

    private var activeProfileCard: some View {
        AtlasPanel(heading: "Active Session", caption: "You are currently authenticated") {
            VStack(alignment: .center, spacing: 16) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 64))
                    .foregroundStyle(AtlasTheme.accentWarm)
                    .padding(.top, 16)

                VStack(spacing: 4) {
                    Text("Operator Identity")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(session.accountLabel)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                }

                Divider().padding(.vertical, 8)

                Button("Sign Out", role: .destructive) {
                    session.signOut()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Info Views (Right Column)

    private var providerStatusCard: some View {
        AtlasPanel(heading: "Provider Status", caption: "Live capability check from API") {
            VStack(alignment: .leading, spacing: 16) {
                if let health = session.health {
                    VStack(spacing: 12) {
                        capabilityRow("Apple OAuth", available: health.capabilities.appleOAuth)
                        capabilityRow("Google OAuth", available: health.capabilities.googleOAuth)
                        capabilityRow("Passkey", available: health.capabilities.passkey)
                        capabilityRow("Billing", available: health.capabilities.billing)
                    }
                } else {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Verifying provider readiness...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Refresh Status") {
                        Task { await session.refreshHealth() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var securityExplainerCard: some View {
        AtlasPanel(heading: "Data & Personalization", caption: "Why account state matters") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.title2)
                        .foregroundStyle(AtlasTheme.accentWarm)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Secure Identity")
                            .font(.subheadline.weight(.semibold))
                        Text("No legacy passwords are used. Atlas strictly utilizes provider auth, passkeys, and secure sessions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundStyle(AtlasTheme.accentWarm)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Personalization Graph")
                            .font(.subheadline.weight(.semibold))
                        Text("Your signed-in data (surveys, notes, queue outputs, and workspace sessions) is persisted to produce tailored execution plans.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func capabilityRow(_ title: String, available: Bool) -> some View {
        HStack {
            Image(systemName: available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(available ? .green : AtlasTheme.accent)
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(available ? "Operational" : "Pending")
                .font(.caption.weight(.bold).monospaced())
                .foregroundStyle(available ? Color.secondary : AtlasTheme.accentWarm)
        }
    }

    private func shouldAutoFallbackToWeb(_ error: Error) -> Bool {
        guard let authError = error as? ASAuthorizationError else {
            return true
        }
        return authError.code != .canceled
    }
}
