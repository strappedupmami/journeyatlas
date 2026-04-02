import SwiftUI

struct CommandCenterCard: View {
    @EnvironmentObject private var session: SessionStore
    @FocusState private var conciergePromptFocused: Bool

    var body: some View {
        AtlasScreen(
            title: "BlackHaven Home",
            subtitle: "Home brief, execution planning, and orchestration controls"
        ) {
            AtlasPanel(
                heading: "Safety + rehabilitation guardrails",
                caption: "Safety checks for risky patterns"
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
                heading: "Model Inference Brief",
                caption: "Current home synthesis"
            ) {
                if !session.isModelAutofillUnlocked {
                    Text("AI home brief unlock: \(session.modelAutofillMinimumSurveyAnswers) survey answers (\(session.modelAutofillSurveyAnswersRemaining) remaining).")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.accentWarm)
                }
                ResponseFeedbackCard(
                    source: "ios_concierge_command_brief",
                    prompt: conciergePromptSnapshot,
                    response: session.commandModelBrief
                )
            }

            AtlasPanel(
                heading: "Home Prompt Studio",
                caption: "Text-first queue controls for home operations"
            ) {
                Text("Write a prompt for BlackHaven AI")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AtlasTheme.textPrimary)

                TextField("Type your message", text: $session.pendingPrompt, axis: .vertical)
                    .lineLimit(3 ... 8)
                    .atlasFieldStyle()
                    .focused($conciergePromptFocused)

                Picker("Output type", selection: $session.pendingPromptOutputType) {
                    ForEach(PromptOutputType.allCases) { outputType in
                        Text(outputType.title).tag(outputType)
                    }
                }
                .pickerStyle(.segmented)

                if session.pendingPromptOutputType == .quiz {
                    Picker("Quiz difficulty", selection: $session.pendingPromptQuizDifficulty) {
                        ForEach(QuizDifficulty.allCases) { difficulty in
                            Text(difficulty.title).tag(difficulty)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack(spacing: 10) {
                    Button("Send") {
                        conciergePromptFocused = false
                        session.enqueuePrompt()
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())

                    Button("Clear") {
                        conciergePromptFocused = false
                        session.clearConciergePromptQueue()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                }

                if recentConciergeItems.isEmpty {
                    Text("No home prompts yet. Send one to generate a standard reply, podcast, or rehearsal quiz.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(recentConciergeItems) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            AtlasChatBubble(text: item.prompt, isUser: true)

                            if let output = item.output {
                                AtlasChatBubble(text: queueFeedbackResponseText(output), isUser: false)
                                HStack(spacing: 8) {
                                    let outputType = output.outputType ?? item.outputType ?? .standard
                                    AtlasPill(title: outputType.title)
                                    if outputType == .quiz,
                                       let difficulty = output.quizDifficulty ?? item.quizDifficulty
                                    {
                                        AtlasPill(title: difficulty.title.uppercased())
                                    }
                                    AtlasPill(title: item.status.rawValue.uppercased())
                                }
                                ResponseFeedbackCard(
                                    source: "ios_concierge_prompt",
                                    prompt: item.prompt,
                                    response: queueFeedbackResponseText(output)
                                )
                            } else if let error = item.errorMessage {
                                AtlasChatBubble(text: "Error: \(error)", isUser: false)
                            } else {
                                let outputType = item.outputType ?? .standard
                                let descriptor = outputType == .quiz
                                    ? "\(outputType.title.lowercased()) (\((item.quizDifficulty ?? .medium).title.lowercased()))"
                                    : outputType.title.lowercased()
                                AtlasChatBubble(
                                    text: "\(item.status.rawValue.capitalized)... generating \(descriptor) output.",
                                    isUser: false
                                )
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                        )
                    }
                }
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
                caption: "Branching intake is now part of Home and powers long-term personalization quality"
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

            AtlasPanel(
                heading: "Travel Itinerary Window",
                caption: "Your saved itinerary is visible directly on Home"
            ) {
                if session.activeTravelItineraryLocations.isEmpty {
                    Text("No saved itinerary yet. Add locations in Travel Maps + Itinerary and they will appear here.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(session.activeTravelItinerary.title)
                            .font(.system(size: 16, weight: .semibold, design: .default))
                            .foregroundStyle(AtlasTheme.textPrimary)

                        ForEach(Array(session.activeTravelItineraryLocations.enumerated()), id: \.element.id) { index, location in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(AtlasTheme.accentWarm)
                                    .frame(width: 24, alignment: .leading)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(location.name)
                                        .font(.system(size: 14, weight: .semibold, design: .default))
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    Text(location.googleMapsQuery)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                    if !location.notes.isEmpty {
                                        Text(location.notes)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                            .lineLimit(2)
                                    }
                                }
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    conciergePromptFocused = false
                }
            }
        }
    }

    private var conciergePromptSnapshot: String {
        let parts = [
            session.dailyPriority,
            session.midTermGoal,
            session.longTermVision,
            session.checkInMood,
            session.checkInBlockers,
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: "\n")
    }

    private var recentConciergeItems: [PromptQueueItem] {
        Array(session.promptQueue.filter { $0.workspaceLane == nil }.suffix(6))
    }

    private func queueFeedbackResponseText(_ output: LocalReasoningOutput) -> String {
        var lines = [
            "Type: \((output.outputType ?? .standard).title)",
            (output.outputType == .quiz || output.quizDifficulty != nil)
                ? "Difficulty: \((output.quizDifficulty ?? .medium).title)"
                : nil,
            "Summary: \(output.summary)",
            "Next action: \(output.nextAction)",
        ].compactMap { $0 }
        let body = (output.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            lines.append("")
            lines.append(body)
        }
        return lines.joined(separator: "\n")
    }
}
