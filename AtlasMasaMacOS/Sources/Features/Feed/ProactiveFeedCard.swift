import SwiftUI

struct ProactiveFeedCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "Execution Loop",
            subtitle: "Daily, mid-term, and long-term orchestration with executive-grade clarity"
        ) {
            AtlasPanel(heading: "Plan source", caption: "Tier-aware pipeline: local reasoning first, cloud reasoning when upgraded") {
                Text("Active tier: \(session.selectedTier.title)")
                    .foregroundStyle(AtlasTheme.textPrimary)
                Text(session.selectedTier.subtitle)
                    .foregroundStyle(AtlasTheme.textSecondary)

                Button("Refresh execution feed") {
                    Task { await session.refreshFeed() }
                }
                .buttonStyle(AtlasPrimaryButtonStyle())
            }

            AtlasPanel(heading: "Proactive outputs", caption: "What to execute now and why") {
                if session.feedItems.isEmpty {
                    Text("No items yet. Complete survey and check-in, then refresh feed.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(session.feedItems) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.system(size: 18, weight: .semibold, design: .serif))
                                .foregroundStyle(AtlasTheme.textPrimary)
                            Text(item.summary)
                                .foregroundStyle(AtlasTheme.textSecondary)
                            Text("Why now: \(item.whyNow)")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.accentWarm)
                            Text("Priority: \(item.priority)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                        )
                    }
                }
            }

            AtlasPanel(heading: "Product feedback path", caption: "If friction is detected, offer anonymized report routing") {
                Toggle("Enable feedback offer on negative signal", isOn: $session.feedbackOfferEnabled)
                    .tint(AtlasTheme.accent)
                    .foregroundStyle(AtlasTheme.textPrimary)

                TextField("Optional feedback draft", text: $session.pendingFeedback, axis: .vertical)
                    .lineLimit(2 ... 5)
                    .atlasFieldStyle()

                Button("Send anonymized report") {
                    session.submitAnonymizedFeedback()
                }
                .buttonStyle(AtlasSecondaryButtonStyle())
            }
        }
    }
}
