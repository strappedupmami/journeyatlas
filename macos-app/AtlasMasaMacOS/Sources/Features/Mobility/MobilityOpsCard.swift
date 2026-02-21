import SwiftUI

struct MobilityOpsCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "Mobility + Van Rental",
            subtitle: "Website sells the rental; app captures operational intent and execution profile"
        ) {
            AtlasPanel(
                heading: "Rental intent",
                caption: "Provide mission details and keep them synced with your execution system"
            ) {
                Toggle("I need van rental support", isOn: $session.vanRentalNeeded)
                    .tint(AtlasTheme.accent)
                    .foregroundStyle(AtlasTheme.textPrimary)

                TextField("Primary region", text: $session.travelRegion)
                    .atlasFieldStyle()
                TextField("Annual distance (km)", text: $session.annualDistanceKM)
                    .atlasFieldStyle()
                TextField("Work mode", text: $session.workspaceMode)
                    .atlasFieldStyle()

                Button("Apply mobility profile") {
                    session.applyDailyCheckIn()
                    session.appendOutput("Mobility profile updated for rental and planning alignment.")
                }
                .buttonStyle(AtlasPrimaryButtonStyle())
            }

            AtlasPanel(
                heading: "What this feeds",
                caption: "Your mobility profile directly influences local reasoning and proactive planning"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("• Daily execution plan gets mobility constraints by default")
                    Text("• Prompt queue outputs inherit your annual driving load")
                    Text("• Tier 2 cloud upgrade (when enabled) can use these fields for deeper routing")
                }
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AtlasTheme.textSecondary)
            }
        }
    }
}
