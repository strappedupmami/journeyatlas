import SwiftUI

struct SubscriptionCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "Plans + Billing",
            subtitle: "Start with local-only trial, then upgrade to cloud reasoning when ROI is clear"
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
                    Text("3-month free trial logic: local reasoning + cloud storage.")
                        .foregroundStyle(AtlasTheme.accentWarm)
                } else {
                    Text("Tier 2 requires Stripe + Apple Pay capable checkout on web and app entitlement sync.")
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
                    Text("• Tier 1: free trial, local reasoning, cloud storage only")
                    Text("• Tier 2: cloud reasoning + premium orchestration")
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
