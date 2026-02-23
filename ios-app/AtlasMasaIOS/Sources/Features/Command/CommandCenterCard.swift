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
                heading: "AI transparency (quick)",
                caption: "Why Atlas exists and how this plan is generated"
            ) {
                Text("Atlas is built for financial mobility, healthier cognitive execution, and resilient travel/work operations. This command plan is generated from your check-in + survey + notes + workspace memory, then prioritized into immediate, mid-term, and long-horizon actions.")
                    .foregroundStyle(AtlasTheme.textSecondary)
                Text("Open AI Guide from the More menu for full training, workflow, and privacy details.")
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
                heading: "Adaptive deep survey",
                caption: "Branching intake is now part of Command and powers long-term personalization quality"
            ) {
                if let survey = session.survey {
                    ProgressView(value: Double(survey.progress.percent), total: 100)
                        .tint(AtlasTheme.accent)
                    Text("\(survey.progress.answered)/\(survey.progress.total) answered · \(survey.progress.percent)%")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.textSecondary)

                    if let question = survey.question {
                        Text(question.title)
                            .font(.system(size: 17, weight: .semibold, design: .default))
                            .foregroundStyle(AtlasTheme.textPrimary)

                        if let description = question.description, !description.isEmpty {
                            Text(description)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)
                        }

                        ForEach(question.choices) { choice in
                            Button(choice.label) {
                                Task { await session.answerSurvey(choice) }
                            }
                            .buttonStyle(AtlasSecondaryButtonStyle())
                        }
                    } else {
                        Text("Survey complete. Start an additional pass whenever you want more depth.")
                            .foregroundStyle(AtlasTheme.accentWarm)
                    }
                } else {
                    Text("Survey loading...")
                        .foregroundStyle(AtlasTheme.textSecondary)
                }

                HStack {
                    Button("Reload survey") {
                        Task { await session.loadSurvey() }
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())

                    Button(session.isAdditionalSurveyPassActive ? "Additional pass in progress" : "Start additional pass") {
                        Task { await session.startAdditionalSurveyPass() }
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                    .disabled(session.isAdditionalSurveyPassActive)
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
                                    .font(.system(size: 16, weight: .semibold, design: .default))
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
