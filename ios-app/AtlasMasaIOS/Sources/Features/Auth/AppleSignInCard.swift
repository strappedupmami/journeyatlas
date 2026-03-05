import SwiftUI

struct AppleSignInCard: View {
    @EnvironmentObject private var session: SessionStore
    @State private var inferenceProviderID = "gemini"
    @State private var inferenceModel = ""
    @State private var inferenceEndpoint = ""
    @State private var inferenceAPIKeyDraft = ""
    @State private var inferenceSnapshot: SessionStore.InferenceSettingsSnapshot?
    @State private var firstNameDraft = ""
    @State private var middleNameDraft = ""
    @State private var lastNameDraft = ""
    @State private var usernameDraft = ""

    var body: some View {
        AtlasScreen(
            title: "Account",
            subtitle: "Combined sign-up/sign-in with Apple, Google, and Passwordless (more secure)"
        ) {
            AtlasPanel(
                heading: "Secure account (sign up / sign in)",
                caption: "One combined flow. Choose your preferred secure method."
            ) {
                Button {
                    session.startNativeAppleSignIn()
                } label: {
                    HStack(spacing: 10) {
                        Text("")
                            .font(.system(size: 18, weight: .semibold, design: .default))
                        Text(session.isAppleSignInInProgress ? "Connecting to Apple…" : "Sign in with Apple")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(AtlasSecondaryButtonStyle())
                .disabled(session.isAppleSignInInProgress)

                HStack(spacing: 10) {
                    GoogleSignInButton(
                        title: session.isGoogleSignInInProgress ? "Connecting to Google…" : "Sign in with Google"
                    ) {
                        session.startGoogleSignIn()
                    }
                    .disabled(
                        session.isPasskeyInProgress
                            || session.isAppleSignInInProgress
                            || session.isGoogleSignInInProgress
                    )

                    Button(session.isPasskeyInProgress ? "Passwordless: Working…" : "Passwordless (more secure) Sign in") {
                        session.signInWithPasswordless()
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())
                    .disabled(
                        session.isPasskeyInProgress
                            || session.isAppleSignInInProgress
                            || session.isGoogleSignInInProgress
                    )
                }

                Button(session.isPasskeyInProgress ? "Creating account…" : "Passwordless (more secure) Sign up") {
                    session.signUpWithPasswordless()
                }
                .buttonStyle(AtlasSecondaryButtonStyle())
                .disabled(
                    session.isPasskeyInProgress
                        || session.isAppleSignInInProgress
                        || session.isGoogleSignInInProgress
                )

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

            AtlasPanel(
                heading: "Profile identity",
                caption: "Editable once signed in"
            ) {
                TextField("First name", text: $firstNameDraft)
                    .atlasFieldStyle()
                    .disabled(!session.isSignedIn)

                TextField("Middle name", text: $middleNameDraft)
                    .atlasFieldStyle()
                    .disabled(!session.isSignedIn)

                TextField("Last name", text: $lastNameDraft)
                    .atlasFieldStyle()
                    .disabled(!session.isSignedIn)

                TextField("Username (letters, numbers, ., _, -)", text: $usernameDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .atlasFieldStyle()
                    .disabled(!session.isSignedIn)

                HStack(spacing: 10) {
                    Button("Save profile identity") {
                        session.saveAccountIdentity(
                            firstName: firstNameDraft,
                            middleName: middleNameDraft,
                            lastName: lastNameDraft,
                            username: usernameDraft
                        )
                        loadAccountIdentityDraft()
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())
                    .disabled(!session.isSignedIn)

                    Button("Reset") {
                        loadAccountIdentityDraft()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                }

                Text(session.isSignedIn ? "Displayed account name updates everywhere in the app after saving." : "Sign in to edit account identity.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.textSecondary)
            }

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
                heading: "Model runtime",
                caption: "Configure model keys and runtime routes used by queue + podcast pipeline"
            ) {
                Picker("Model provider", selection: $inferenceProviderID) {
                    ForEach(session.inferenceProviderOptions()) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .pickerStyle(.segmented)

                if let option = session.inferenceProviderOptions().first(where: { $0.id == inferenceProviderID }) {
                    Text(option.subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.textSecondary)
                }

                TextField("Model target (locked by provider)", text: $inferenceModel)
                    .atlasFieldStyle()
                    .disabled(true)

                Text("OpenAI-Compatible is locked to gpt-5.2. Gemini is locked to gemini-3-flash-preview for reasoning plus gemini-2.5-pro-preview-tts for podcast audio.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.textSecondary)

                if inferenceProviderID == "openai_compatible" {
                    TextField("Endpoint URL", text: $inferenceEndpoint)
                        .atlasFieldStyle()
                }

                SecureField("API key (leave blank to keep current key)", text: $inferenceAPIKeyDraft)
                    .atlasFieldStyle()

                if let snapshot = inferenceSnapshot, snapshot.apiKeyStored {
                    Text("Stored API key: \(snapshot.apiKeyHint ?? "saved in Keychain")")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.accentWarm)
                }

                HStack(spacing: 10) {
                    Button("Save runtime config") {
                        session.saveInferenceSettings(
                            providerID: inferenceProviderID,
                            model: inferenceModel,
                            endpoint: inferenceEndpoint,
                            newAPIKey: inferenceAPIKeyDraft
                        )
                        inferenceAPIKeyDraft = ""
                        loadInferenceSnapshot()
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())

                    Button("Clear API key") {
                        session.clearInferenceAPIKey()
                        loadInferenceSnapshot()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                }

                Text(inferenceSnapshot?.statusLine ?? "Inference runtime status unavailable.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.textSecondary)
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
        }
        .onAppear {
            loadInferenceSnapshot()
            loadAccountIdentityDraft()
        }
        .onChange(of: session.isSignedIn) { _, _ in
            loadAccountIdentityDraft()
        }
        .onChange(of: session.accountLabel) { _, _ in
            if session.isSignedIn {
                loadAccountIdentityDraft()
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

    private func loadInferenceSnapshot() {
        let snapshot = session.inferenceSettingsSnapshot()
        inferenceSnapshot = snapshot
        inferenceProviderID = snapshot.providerID
        inferenceModel = snapshot.model
        inferenceEndpoint = snapshot.endpoint
    }

    private func loadAccountIdentityDraft() {
        firstNameDraft = session.accountFirstName
        middleNameDraft = session.accountMiddleName
        lastNameDraft = session.accountLastName
        usernameDraft = session.accountUsername
    }
}

private struct GoogleSignInButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                    Text("G")
                        .font(.system(size: 14, weight: .bold, design: .default))
                        .foregroundStyle(Color.black)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sign in with Google")
    }
}
