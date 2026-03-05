import SwiftUI

struct MobilityOpsCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // High-End Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mobility & Operations")
                        .font(.largeTitle.weight(.bold))
                    Text("Capture operational intent and execution profile for van rentals")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                // Two-Column Desktop Architecture
                HStack(alignment: .top, spacing: 32) {
                    // MARK: - LEFT COLUMN: The Input Form
                    VStack(spacing: 24) {
                        AtlasPanel(heading: "Rental Intent", caption: "Sync mission details with your execution system") {
                            // Native macOS Form alignment
                            Form {
                                Section {
                                    Toggle("I need van rental support", isOn: $session.vanRentalNeeded)
                                        .toggleStyle(.switch)
                                }

                                Divider().padding(.vertical, 8)

                                Section {
                                    TextField("Primary Region", text: $session.travelRegion)
                                    TextField("Annual Distance (km)", text: $session.annualDistanceKM)
                                    TextField("Work Mode", text: $session.workspaceMode)
                                }
                            }
                            .controlSize(.regular)
                            .textFieldStyle(.roundedBorder)

                            HStack {
                                Spacer()
                                Button("Apply Mobility Profile") {
                                    session.applyDailyCheckIn()
                                    session.appendOutput("Mobility profile updated for rental and planning alignment.")
                                }
                                .buttonStyle(AtlasPrimaryButtonStyle())
                                .padding(.top, 16)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    // MARK: - RIGHT COLUMN: System Impact Information
                    VStack(spacing: 24) {
                        AtlasPanel(heading: "System Impact", caption: "How your profile influences reasoning") {
                            VStack(alignment: .leading, spacing: 20) {
                                InfoRow(
                                    icon: "map.fill",
                                    title: "Daily Execution",
                                    description: "Default plans inherit your regional constraints and mobility limitations automatically."
                                )

                                InfoRow(
                                    icon: "car.circle.fill",
                                    title: "Prompt Queue",
                                    description: "Background reasoning outputs actively factor in your specified annual driving load."
                                )

                                InfoRow(
                                    icon: "cloud.fill",
                                    title: "Cloud Upgrades",
                                    description: "Tier 2 routing uses these fields for deeper, high-fidelity optimization when enabled."
                                )
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(32)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Native Helper Component
private struct InfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(AtlasTheme.accentWarm)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AtlasTheme.textPrimary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(AtlasTheme.textSecondary)
                    .lineSpacing(2)
            }
        }
    }
}
