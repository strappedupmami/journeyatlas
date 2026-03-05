import SwiftUI

struct SubscriptionCard: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        AtlasScreen(
            title: "Plans + Billing",
            subtitle: "Cloud AI is locked until billing is active. No guest usage and no unpaid debt mode."
        ) {
            AtlasPanel(heading: "Active plan", caption: "Cloud access follows billing state") {
                Picker("Plan", selection: $session.selectedTier) {
                    ForEach(AccountTier.allCases) { tier in
                        Text(tier.title).tag(tier)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: session.selectedTier) { _, tier in
                    session.setTier(tier)
                }

                Text(session.selectedTier.subtitle)
                    .foregroundStyle(AtlasTheme.textSecondary)

                if session.selectedTier == .localTrial {
                    Text("Status: Locked until payment method is active.")
                        .foregroundStyle(AtlasTheme.accentWarm)
                } else {
                    Text("Status: Cloud AI unlocked for this account.")
                        .foregroundStyle(AtlasTheme.accentWarm)
                }
            }

            AtlasPanel(heading: "Payment method", caption: "Choose how to activate billing") {
                Button("In-App Purchase / Apple Pay (Recommended)") {
                    session.startInAppPurchaseFlow()
                }
                .buttonStyle(AtlasPrimaryButtonStyle())
                .disabled(!session.isSignedIn)

                Button("Manual card setup (Stripe)") {
                    Task {
                        await session.startManualCardSetup { url in
                            openURL(url)
                        }
                    }
                }
                .buttonStyle(AtlasSecondaryButtonStyle())
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .disabled(!session.isSignedIn)

                Button("Refresh billing status") {
                    Task { await session.refreshBillingStatus() }
                }
                .buttonStyle(AtlasSecondaryButtonStyle())
                .disabled(!session.isSignedIn)

                Text(session.billingStatusMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(session.billingAccessEnabled ? .green : AtlasTheme.textSecondary)
            }

            AtlasPanel(heading: "Billing capability", caption: "Read from API health when available") {
                if let caps = session.health?.capabilities {
                    capability("Apple OAuth", ok: caps.appleOAuth)
                    capability("Google OAuth", ok: caps.googleOAuth)
                    capability("Passkey", ok: caps.passkey)
                    capability("Billing", ok: caps.billing)
                } else {
                    Text("Health not loaded yet.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                }

                Button("Refresh API capabilities") {
                    Task { await session.refreshHealth() }
                }
                .buttonStyle(AtlasSecondaryButtonStyle())
            }

            AtlasPanel(heading: "Revenue path", caption: "Economic model alignment") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("• No unpaid usage: cloud compute is blocked until billing is active")
                    Text("• Billing model: charge user payment method, not app owner debt")
                    Text("• Mobility: van rental as parallel revenue stream")
                    Text("• Team/business: fleet pricing with SLA")
                }
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AtlasTheme.textSecondary)
            }
        }
    }

    private func capability(_ title: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? .green : .orange)
            Text("\(title): \(ok ? "ready" : "pending")")
                .foregroundStyle(AtlasTheme.textPrimary)
            Spacer()
        }
    }
}
