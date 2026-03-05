import SwiftUI

struct SubscriptionCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "Prepaid Credits",
            subtitle: "Desktop AI and memory run on-device by default. Cloud usage is pay-as-you-go via prepaid credits."
        ) {
            AtlasPanel(heading: "Access state", caption: "No premium plan toggle. Credits control cloud access.") {
                Text(session.prepaidCreditsActive
                    ? "Status: Prepaid credits active for exact cloud usage."
                    : "Status: No prepaid credits active. On-device AI remains available."
                )
                .foregroundStyle(AtlasTheme.accentWarm)

                Text("Cloud code and reasoning features activate only when prepaid credits are available.")
                    .foregroundStyle(AtlasTheme.textSecondary)
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
                    Text("• Core desktop AI stays on-device with local persistence")
                    Text("• Cloud models are pay-as-you-go with prepaid credits only")
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
                .foregroundStyle(ok ? .green : AtlasTheme.accent)
            Text("\(title): \(ok ? "ready" : "pending")")
                .foregroundStyle(AtlasTheme.textPrimary)
            Spacer()
        }
    }
}
