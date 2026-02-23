import SwiftUI

struct SubscriptionCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "Plans + Billing",
            subtitle: "Every account starts with a 2-month free trial, then Pro continues at ₪20/month."
        ) {
            AtlasPanel(heading: "Active plan", caption: "Switch between local-first and cloud reasoning modes") {
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
                    Text("Trial pricing: free for 60 days, then choose Pro at ₪20/month.")
                        .foregroundStyle(AtlasTheme.accentWarm)
                } else {
                    Text("Pro pricing: ₪20/month after the 2-month trial window.")
                        .foregroundStyle(AtlasTheme.accentWarm)
                }
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
                    Text("• Free trial: 2 months for every new account")
                    Text("• Paid plan: ₪20/month after trial")
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
