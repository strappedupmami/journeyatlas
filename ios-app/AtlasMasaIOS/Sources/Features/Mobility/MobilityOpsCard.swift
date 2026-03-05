import SwiftUI

struct MobilityOpsCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "Mobility + Van Rental",
            subtitle: "Mobility profile and rental intent"
        ) {
            AtlasPanel(
                heading: "Rental intent",
                caption: "Set the fields used by routing and planning"
            ) {
                Toggle("I need van rental support", isOn: $session.vanRentalNeeded)
                    .tint(AtlasTheme.accent)
                    .foregroundStyle(AtlasTheme.textPrimary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Primary region")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AtlasTheme.textPrimary)
                    TextField("Enter region", text: $session.travelRegion)
                        .atlasFieldStyle()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Annual distance (km)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AtlasTheme.textPrimary)
                    TextField("Enter yearly distance", text: $session.annualDistanceKM)
                        .keyboardType(.numberPad)
                        .atlasFieldStyle()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Work mode")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AtlasTheme.textPrimary)
                    TextField("Enter work mode", text: $session.workspaceMode)
                        .atlasFieldStyle()
                }

                Button("Apply mobility profile") {
                    session.applyDailyCheckIn()
                    session.appendOutput("Mobility profile updated for rental and planning alignment.")
                }
                .buttonStyle(AtlasPrimaryButtonStyle())
            }
        }
    }
}
