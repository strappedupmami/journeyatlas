import SwiftUI

struct AdaptiveSurveyCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "Adaptive Deep Survey",
            subtitle: "20-30 minute branching intake to calibrate long-term personalization"
        ) {
            AtlasPanel(heading: "Survey progress", caption: "Complete full depth to unlock strongest proactive orchestration") {
                if let survey = session.survey {
                    ProgressView(value: Double(survey.progress.percent), total: 100)
                        .tint(AtlasTheme.accent)
                    Text("\(survey.progress.answered)/\(survey.progress.total) answered · \(survey.progress.percent)%")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.textSecondary)
                    Text("Additional passes completed: \(session.surveyAdditionalPassesCompleted)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.accentWarm)
                } else {
                    Text("Loading survey...")
                        .foregroundStyle(AtlasTheme.textSecondary)
                }

                Button("Reload survey") {
                    Task { await session.loadSurvey() }
                }
                .buttonStyle(AtlasSecondaryButtonStyle())

                Button(session.isAdditionalSurveyPassActive ? "Additional pass in progress" : "Start additional pass (new questions only)") {
                    Task { await session.startAdditionalSurveyPass() }
                }
                .buttonStyle(AtlasSecondaryButtonStyle())
                .disabled(session.isAdditionalSurveyPassActive)
            }

            AtlasPanel(heading: "Why Atlas asks these questions", caption: "Training and personalization alignment") {
                Text("The survey trains your personal operating profile: economic blockers, brain-performance conditions, execution habits, and mobility/work constraints. Atlas uses this to generate professional-grade, personalized action streams instead of generic advice.")
                    .foregroundStyle(AtlasTheme.textSecondary)
                Text("You can retake additional passes at any time; Atlas will add new depth without repeating answered questions.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.accentWarm)
            }

            AtlasPanel(heading: "Current branch", caption: "Every answer changes what comes next") {
                if let survey = session.survey {
                    if let question = survey.question {
                        Text(question.title)
                            .font(.system(size: 18, weight: .semibold, design: .default))
                            .foregroundStyle(AtlasTheme.textPrimary)

                        if let description = question.description, !description.isEmpty {
                            Text(description)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)
                        }

                        ForEach(question.choices) { choice in
                            Button(choice.label) {
                                Task { await session.answerSurvey(choice) }
                            }
                            .buttonStyle(AtlasSecondaryButtonStyle())
                        }
                    } else {
                        Text("Survey complete. Proactive engine now uses full profile depth. Start another pass any time to add new data without repeating previous questions.")
                            .foregroundStyle(AtlasTheme.accentWarm)
                    }
                } else {
                    Text("Survey unavailable.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                }
            }

            if let hints = session.survey?.profileHints, !hints.isEmpty {
                AtlasPanel(heading: "Profile hints", caption: "Derived from current survey depth") {
                    ForEach(hints, id: \.self) { hint in
                        Text("• \(hint)")
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }
                }
            }
        }
    }
}
