import SwiftUI

struct CommandCenterCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "Atlas/אטלס Life OS",
            subtitle: "Swift-native command center for daily, mid-term, and long-horizon execution"
        ) {
            AtlasPanel(
                heading: "Account status",
                caption: "Passwordless, provider auth, and secure session state"
            ) {
                HStack(spacing: 10) {
                    AtlasPill(title: session.isSignedIn ? "Signed in" : "Guest")
                    AtlasPill(title: session.selectedTier.title)
                }

                Text("Operator: \(session.accountLabel)")
                    .foregroundStyle(AtlasTheme.textSecondary)

                if session.selectedTier == .localTrial {
                    Text("Local-first mode: execution runs on device and persists across restarts.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.accentWarm)
                }
            }

            AtlasPanel(
                heading: "Safety + rehabilitation guardrails",
                caption: "Atlas actively de-escalates suspicious patterns and redirects toward safe, pro-social progress"
            ) {
                HStack(spacing: 10) {
                    AtlasPill(title: session.safetyModeActive ? "Intervention active" : "Monitoring")
                    AtlasPill(title: "Risk score: \(session.safetyRiskScore)")
                }

                Text(session.safetyInterventionSummary)
                    .foregroundStyle(AtlasTheme.textSecondary)

                if session.safetyModeActive {
                    Text("High-risk content is blocked from operational queueing. You can continue with de-escalation and constructive planning.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.accentWarm)

                    Button("Acknowledge guidance") {
                        session.acknowledgeSafetyGuidance()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                }
            }

            AtlasPanel(
                heading: "AI transparency (quick)",
                caption: "Why Atlas exists and how this plan is generated"
            ) {
                Text("Atlas is built for financial mobility, healthier cognitive execution, and resilient travel/work operations. This command plan is generated from your check-in + survey + notes + workspace memory, then prioritized into immediate, mid-term, and long-horizon actions.")
                    .foregroundStyle(AtlasTheme.textSecondary)
                Text("Open the AI Guide tab for full training, workflow, and privacy details.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.accentWarm)
            }

            AtlasPanel(
                heading: "Daily execution check-in",
                caption: "Set your core horizon signals so the orchestration loop can prioritize correctly"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Daily priority", text: $session.dailyPriority)
                        .atlasFieldStyle()
                    TextField("Mid-term objective (this quarter)", text: $session.midTermGoal)
                        .atlasFieldStyle()
                    TextField("Long-term mission (12-36 months)", text: $session.longTermVision)
                        .atlasFieldStyle()
                    TextField("Current blockers", text: $session.checkInBlockers)
                        .atlasFieldStyle()

                    Stepper("Energy: \(session.checkInEnergy)/5", value: $session.checkInEnergy, in: 1 ... 5)
                        .foregroundStyle(AtlasTheme.textPrimary)
                    TextField("Mood", text: $session.checkInMood)
                        .atlasFieldStyle()
                    Toggle("Went to the gym / training today", isOn: $session.checkInWentToGymToday)
                        .tint(AtlasTheme.accent)
                        .foregroundStyle(AtlasTheme.textPrimary)
                    Toggle("Made money progress today", isOn: $session.checkInMadeMoneyToday)
                        .tint(AtlasTheme.accent)
                        .foregroundStyle(AtlasTheme.textPrimary)
                    TextField("Money progress note (optional)", text: $session.checkInMoneySignalNote)
                        .atlasFieldStyle()

                    Button("Apply check-in and refresh execution plan") {
                        session.applyDailyCheckIn()
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())
                }
            }

            AtlasPanel(
                heading: "Execution plan",
                caption: "What to do now, what to progress this week, and what to protect long-term"
            ) {
                if session.executionActions.isEmpty {
                    Text("Run your check-in to generate action priorities.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(session.executionActions) { action in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(action.title)
                                    .font(.system(size: 16, weight: .semibold, design: .serif))
                                    .foregroundStyle(AtlasTheme.textPrimary)
                                Spacer()
                                Text(action.horizon)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(AtlasTheme.accentWarm)
                            }
                            Text(action.details)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                        )
                    }
                }
            }
        }
    }
}
