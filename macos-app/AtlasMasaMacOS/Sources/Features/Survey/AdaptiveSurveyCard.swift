import SwiftUI

struct AdaptiveSurveyCard: View {
    @EnvironmentObject private var session: SessionStore

    // Smooth transitions for when the question changes
    @Namespace private var surveyAnimation
    @State private var activeMultiQuestionID: String?
    @State private var multiSelections: Set<String> = []

    var body: some View {
        AtlasScreen(
            title: "Adaptive Deep Survey",
            subtitle: "Calibrating your long-term operational profile"
        ) {
            HStack(alignment: .top, spacing: 32) {
                // MARK: - LEFT COLUMN: Status & Context
                VStack(spacing: 24) {
                    surveyStatusPanel

                    if let hints = session.survey?.profileHints, !hints.isEmpty {
                        profileHintsPanel(hints: hints)
                    }

                    explanationPanel
                }
                .frame(width: 320) // Fixed width for the sidebar

                // MARK: - RIGHT COLUMN: The Stage (Hinge-Style Focus)
                VStack {
                    Spacer(minLength: 40)

                    if let survey = session.survey {
                        if let question = survey.question {
                            // Active Question Card
                            Group {
                                if question.kind == "multi_choice" {
                                    multiChoiceQuestionCard(for: question)
                                } else {
                                    questionCard(for: question)
                                }
                            }
                                .transition(AnyTransition.asymmetric(
                                    insertion: AnyTransition.opacity.combined(with: AnyTransition.move(edge: .trailing)),
                                    removal: AnyTransition.opacity.combined(with: AnyTransition.move(edge: .leading))
                                ))
                        } else {
                            // Completion State
                            completionCard
                                .transition(AnyTransition.opacity.combined(with: AnyTransition.scale))
                        }
                    } else {
                        // Loading State
                        ProgressView("Synthesizing survey data...")
                            .controlSize(.large)
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: session.survey?.question?.title)
            }
        }
    }

    // MARK: - Subviews: The Stage (Right Column)

    @ViewBuilder
    private func questionCard(for question: SurveyQuestion) -> some View {
        VStack(spacing: 32) {
            // Typography hierarchy similar to high-end editorial/dating apps
            VStack(spacing: 12) {
                Text(question.title)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(AtlasTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let description = question.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)

            // Large, tactile choice buttons
            VStack(spacing: 12) {
                ForEach(question.choices) { choice in
                    Button {
                        Task { await session.answerSurvey(choice) }
                    } label: {
                        Text(choice.label)
                            .font(.system(size: 16, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 20)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AtlasTheme.border, lineWidth: 1)
                            )
                            // Subtle hover effect applied via standard button styling
                    }
                    .buttonStyle(.plain) // Use plain so we can style the label entirely
                    // Custom hover/press scaling for that premium feel
                    .pressAndHoverEffect()
                }
            }
        }
        .padding(40)
        // A beautiful frosted glass card for the question
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .frame(maxWidth: 600)
    }

    @ViewBuilder
    private func multiChoiceQuestionCard(for question: SurveyQuestion) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Text(question.title)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(AtlasTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let description = question.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)

            VStack(spacing: 10) {
                ForEach(question.choices) { choice in
                    Button {
                        toggleMultiSelection(choice.value)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: multiSelections.contains(choice.value) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(multiSelections.contains(choice.value) ? AtlasTheme.accentWarm : AtlasTheme.textSecondary)
                            Text(choice.label)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AtlasTheme.textPrimary)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AtlasTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .pressAndHoverEffect()
                }
            }

            HStack {
                Spacer()
                Button("Continue") {
                    let selected = question.choices.filter { multiSelections.contains($0.value) }
                    Task {
                        await session.answerSurveyMulti(questionID: question.id, selectedChoices: selected)
                    }
                }
                .buttonStyle(AtlasPrimaryButtonStyle())
                .disabled(multiSelections.isEmpty)
            }
        }
        .padding(40)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .frame(maxWidth: 600)
        .onAppear {
            resetMultiSelectionIfNeeded(questionID: question.id)
        }
        .onChange(of: question.id) { _, newID in
            resetMultiSelectionIfNeeded(questionID: newID)
        }
    }

    private func resetMultiSelectionIfNeeded(questionID: String) {
        guard activeMultiQuestionID != questionID else { return }
        activeMultiQuestionID = questionID
        multiSelections = []
    }

    private func toggleMultiSelection(_ value: String) {
        if value == "not_sure" {
            if multiSelections.contains("not_sure") {
                multiSelections.remove("not_sure")
            } else {
                multiSelections = ["not_sure"]
            }
            return
        }
        if multiSelections.contains(value) {
            multiSelections.remove(value)
        } else {
            multiSelections.insert(value)
            multiSelections.remove("not_sure")
        }
    }

    private var completionCard: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(AtlasTheme.accentWarm)

            VStack(spacing: 8) {
                Text("Profile Synthesized")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(AtlasTheme.textPrimary)

                Text("Atlas now has the depth required for proactive orchestration. You can start another pass at any time to add new data.")
                    .font(.system(size: 15))
                    .foregroundStyle(AtlasTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if session.isGuidedLearningRuntimeActive {
                Text("Guided learning is active. Open AI Guide for personalized learning.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AtlasTheme.textSecondary)
                    .padding(.top, 8)
            } else {
                Button("Initialize Atlas Workspace") {
                    session.activateGuidedLearningAfterSurvey()
                }
                .buttonStyle(AtlasPrimaryButtonStyle())
                .padding(.top, 16)
            }
        }
        .padding(40)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(maxWidth: 500)
    }

    // MARK: - Subviews: Sidebar (Left Column)

    private var surveyStatusPanel: some View {
        AtlasPanel(heading: "Survey Progress", caption: "Unlocking orchestration depth") {
            if let survey = session.survey {
                VStack(alignment: .leading, spacing: 16) {
                    // Custom compact progress indicator
                    VStack(alignment: .trailing, spacing: 8) {
                        ProgressView(value: Double(survey.progress.percent), total: 100)
                            .tint(AtlasTheme.accentWarm)

                        Text("\(survey.progress.answered)/\(survey.progress.total) Answered · \(survey.progress.percent)%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }

                    if session.surveyAdditionalPassesCompleted > 0 {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Additional passes: \(session.surveyAdditionalPassesCompleted)")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AtlasTheme.accent)
                    }

                    Divider()

                    VStack(spacing: 10) {
                        Button("Reload Survey") {
                            Task { await session.loadSurvey() }
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                        .frame(maxWidth: .infinity)

                        Button(session.isAdditionalSurveyPassActive ? "Additional Pass Active" : "Start Additional Pass") {
                            Task { await session.startAdditionalSurveyPass() }
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                        .frame(maxWidth: .infinity)
                        .disabled(session.isAdditionalSurveyPassActive)
                    }
                }
            } else {
                Text("Connecting to engine...")
                    .font(.caption)
                    .foregroundStyle(AtlasTheme.textSecondary)
            }
        }
    }

    private func profileHintsPanel(hints: [String]) -> some View {
        AtlasPanel(heading: "Live Profile Hints", caption: "Derived from current depth") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(hints, id: \.self) { hint in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(AtlasTheme.textSecondary.opacity(0.5))
                            .frame(width: 4, height: 4)
                            .padding(.top, 6)

                        Text(hint)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }
                }
            }
        }
    }

    private var explanationPanel: some View {
        AtlasPanel(heading: "System Training", caption: "Why we ask this") {
            Text("The survey trains your personal operating profile: economic blockers, brain-performance conditions, transport constraints, and what you want next. Atlas uses this to generate professional-grade, personalized action streams instead of generic advice.")
                .font(.system(size: 13))
                .foregroundStyle(AtlasTheme.textSecondary)
        }
    }
}

// MARK: - View Modifier for Tactile Button Feel
extension View {
    /// Adds a subtle scale and opacity effect when a button is pressed,
    /// giving it a high-end, tactile application feel.
    func pressAndHoverEffect() -> some View {
        self.modifier(PressAndHoverModifier())
    }
}

private struct PressAndHoverModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
            // Standard macOS Button style handles the click-scaling nicely,
            // but the hover state adds that extra premium touch.
            .opacity(isHovered ? 0.85 : 1.0)
            .scaleEffect(isHovered ? 1.01 : 1.0)
    }
}
