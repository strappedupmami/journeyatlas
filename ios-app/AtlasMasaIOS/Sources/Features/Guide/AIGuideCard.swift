import SwiftUI

struct AIGuideCard: View {
    @EnvironmentObject private var session: SessionStore
    @State private var northStarMetric = ""
    @State private var northStarTarget = ""
    @State private var activeUsersInput = ""
    @State private var retainedUsersInput = ""
    @State private var monthlyRevenueInput = ""
    @State private var expansionRevenueInput = ""
    @State private var churnRateInput = ""
    @State private var platformPrimaryChannel = "YouTube"
    @State private var platformSecondaryChannel = "Newsletter"
    @State private var platformCoreAsset = ""
    @State private var platformLoopDesign = ""
    @State private var experimentHypothesis = ""
    @State private var experimentMetric = ""
    @State private var experimentTarget = ""
    @State private var experimentDurationDays = 14
    @State private var experiments: [BusinessExperiment] = []
    @State private var businessMentorQuestion = ""
    @State private var businessMentorAnswer = ""
    @State private var businessMentorGrounding = ""
    @State private var businessMentorSourceURL: String?
    @State private var businessRuntimeStatus = ""
    @State private var isRunningBusinessMentor = false
    @State private var adaptiveQuestionEngineEnabled = true
    @State private var adaptiveBusinessAutopilotEnabled = true
    @State private var adaptiveSelectedOptions: Set<String> = []
    @State private var adaptiveFreeformResponse = ""
    @State private var adaptiveQuestionID: String?

    @State private var kiwixBaseURL = ""
    @State private var ollamaEndpoint = ""
    @State private var ollamaModel = ""
    @State private var learningPrompt = ""
    @State private var learningAnswer = ""
    @State private var learningGrounding = ""
    @State private var learningSourceURL: String?
    @State private var learningRuntimeStatus = ""
    @State private var isRunningLearning = false
    private static let businessExperimentStorageKey = "atlas.ios.business.experiments.v1"
    private static let primaryChannels = [
        "YouTube",
        "Newsletter",
        "LinkedIn",
        "TikTok",
        "X/Twitter",
        "Podcast",
        "Community"
    ]
    private static let secondaryChannels = [
        "Newsletter",
        "Blog/SEO",
        "DM/Outbound",
        "Partnerships",
        "Webinars",
        "Affiliate",
        "Community"
    ]

    var body: some View {
        AtlasScreen(
            title: "Atlas AI Guide",
            subtitle: "Why it exists, how it works, and how personalization/training are applied"
        ) {
            AtlasPanel(
                heading: "Why Atlas was built",
                caption: "Mission and intended outcome"
            ) {
                Text("Atlas is built to help people operate with more financial stability, healthier cognitive performance, and stronger execution under real-world pressure. The system focuses on daily function, long-term wealth mobility, and practical resilience for modern work/travel lifestyles.")
                    .foregroundStyle(AtlasTheme.textSecondary)
            }

            AtlasPanel(
                heading: "What the AI is trained for",
                caption: "Core domains Atlas is optimized to solve"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("• Economic execution: income growth paths, career/business decision support, and blocker removal")
                    Text("• Brain-performance aware planning: sleep/focus/stress-aware protocols for consistent output")
                    Text("• Work/travel operations: practical planning, continuity thinking, and high-friction environment execution")
                    Text("• Adaptive coaching: convert user data into actionable daily, mid-term, and long-horizon plans")
                }
                .foregroundStyle(AtlasTheme.textSecondary)
            }

            AtlasPanel(
                heading: "How Atlas works in-app",
                caption: "Operational pipeline"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1) Intake: adaptive survey, notes, prompts, workspace sessions, and check-ins.")
                    Text("2) Synthesis: model inference + decision rules identify blockers and priorities.")
                    Text("3) Execution design: daily/mid/long actions, workspace plans, and queue outputs.")
                    Text("4) Iteration: new behavior data updates recommendations and learning packages.")
                }
                .foregroundStyle(AtlasTheme.textSecondary)
            }

            AtlasPanel(
                heading: "How your personalization works",
                caption: "Memory and privacy behavior"
            ) {
                Text("Personalization uses your own inputs (survey answers, notes, check-ins, workspace sessions, and queue outputs). If memory collection is disabled, Atlas will avoid long-term memory accumulation and rely on lighter session context.")
                    .foregroundStyle(AtlasTheme.textSecondary)

                HStack(spacing: 10) {
                    AtlasPill(title: session.memoryCollectionEnabled ? "Memory ON" : "Memory OFF")
                    AtlasPill(title: session.selectedTier.title)
                }
            }

            AtlasPanel(
                heading: "Live account data footprint",
                caption: "What is actively available to the planning engine right now"
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Survey answers captured: \(session.survey?.progress.answered ?? 0)")
                    Text("Notes stored: \(session.notes.count)")
                    Text("Workspace sessions: \(session.workspaceSessions.count)")
                    Text("Memory records: \(session.workspaceMemoryRecords.count)")
                    Text("Queued prompts: \(session.promptQueue.count)")
                    Text("Execution actions in plan: \(session.executionActions.count)")
                }
                .foregroundStyle(AtlasTheme.textSecondary)
            }

            AtlasPanel(
                heading: "Professional boundaries",
                caption: "How to use Atlas safely"
            ) {
                Text("Atlas provides structured decision support, not guaranteed outcomes or licensed professional advice. Treat outputs as an execution copilot: validate high-stakes medical, legal, and regulated financial decisions with qualified professionals.")
                    .foregroundStyle(AtlasTheme.textSecondary)
            }

            AtlasPanel(
                heading: "Business Growth OS Dashboard",
                caption: "North-star metrics and compounding loops inspired by how scaled companies operate"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        AtlasPill(title: "READINESS \(growthReadinessScore)%")
                        AtlasPill(title: "RUNNING EXP \(runningExperimentsCount)")
                        AtlasPill(title: "WIN RATE \(experimentWinRatePercent)%")
                    }

                    Text("Track one north-star metric, run disciplined weekly experiments, and protect retention while adding distribution channels.")
                        .foregroundStyle(AtlasTheme.textSecondary)

                    TextField("North-star metric (for example: weekly active learners)", text: $northStarMetric)
                        .textFieldStyle(.roundedBorder)
                    TextField("Weekly target (for example: +8%)", text: $northStarTarget)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        Button("Generate Weekly Growth Brief") {
                            runBusinessMentorPrompt(growthBriefPrompt())
                        }
                        .buttonStyle(AtlasPrimaryButtonStyle())
                        .disabled(isRunningBusinessMentor)

                        Button("Queue Growth Brief in Chat") {
                            queuePromptInConcierge(growthBriefPrompt())
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                    }
                }
            }

            AtlasPanel(
                heading: "Experiment Engine",
                caption: "Build a high-velocity test loop with clear hypotheses and success thresholds"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Hypothesis", text: $experimentHypothesis, axis: .vertical)
                        .lineLimit(2 ... 5)
                        .textFieldStyle(.roundedBorder)
                    TextField("Primary metric", text: $experimentMetric)
                        .textFieldStyle(.roundedBorder)
                    TextField("Success target", text: $experimentTarget)
                        .textFieldStyle(.roundedBorder)
                    Stepper("Experiment window: \(experimentDurationDays) days", value: $experimentDurationDays, in: 3 ... 45)
                        .foregroundStyle(AtlasTheme.textSecondary)

                    HStack(spacing: 8) {
                        Button("Create Experiment") {
                            createExperiment()
                        }
                        .buttonStyle(AtlasPrimaryButtonStyle())

                        Button("Mentor: Review Portfolio") {
                            runBusinessMentorPrompt(experimentPortfolioPrompt())
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                        .disabled(isRunningBusinessMentor || experiments.isEmpty)
                    }

                    if experiments.isEmpty {
                        Text("No experiments yet. Add one with a measurable metric and target.")
                            .foregroundStyle(AtlasTheme.textSecondary)
                    } else {
                        ForEach(experiments.prefix(8)) { experiment in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(experiment.hypothesis)
                                        .font(.system(size: 14, weight: .semibold, design: .default))
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    Spacer()
                                    Text(experiment.status.displayName)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(AtlasTheme.accentWarm)
                                }
                                Text("Metric: \(experiment.metric) · Target: \(experiment.target)")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AtlasTheme.textSecondary)
                                Text("Window: \(experiment.windowDays)d · Created \(experiment.createdAtLabel)")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(AtlasTheme.textSecondary)
                                HStack(spacing: 8) {
                                    Button("Mark Won") {
                                        updateExperiment(experiment.id, status: .won)
                                    }
                                    .buttonStyle(AtlasSecondaryButtonStyle())

                                    Button("Mark Lost") {
                                        updateExperiment(experiment.id, status: .lost)
                                    }
                                    .buttonStyle(AtlasSecondaryButtonStyle())

                                    Button("Ask Mentor") {
                                        runBusinessMentorPrompt(experimentReviewPrompt(for: experiment))
                                    }
                                    .buttonStyle(AtlasSecondaryButtonStyle())
                                    .disabled(isRunningBusinessMentor)
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

            AtlasPanel(
                heading: "Retention + Revenue Module",
                caption: "Protect recurring value while scaling growth"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Active users (period)", text: $activeUsersInput)
                        .textFieldStyle(.roundedBorder)
                    TextField("Retained users (period)", text: $retainedUsersInput)
                        .textFieldStyle(.roundedBorder)
                    TextField("Monthly recurring revenue (USD)", text: $monthlyRevenueInput)
                        .textFieldStyle(.roundedBorder)
                    TextField("Expansion revenue (USD)", text: $expansionRevenueInput)
                        .textFieldStyle(.roundedBorder)
                    TextField("Churn rate % (optional override)", text: $churnRateInput)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        AtlasPill(title: "RETENTION \(retentionRatePercent)%")
                        AtlasPill(title: "NET REV \(netRevenueRetentionPercent)%")
                        AtlasPill(title: retentionHealthLabel)
                    }

                    HStack(spacing: 8) {
                        Button("Generate Retention Plan") {
                            runBusinessMentorPrompt(retentionPlanPrompt())
                        }
                        .buttonStyle(AtlasPrimaryButtonStyle())
                        .disabled(isRunningBusinessMentor)

                        Button("Queue Revenue Plan in Chat") {
                            queuePromptInConcierge(retentionPlanPrompt())
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                    }
                }
            }

            AtlasPanel(
                heading: "Platform Leverage Planner",
                caption: "Design distribution loops that compound over time"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Primary channel", selection: $platformPrimaryChannel) {
                        ForEach(Self.primaryChannels, id: \.self) { channel in
                            Text(channel).tag(channel)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Secondary channel", selection: $platformSecondaryChannel) {
                        ForEach(Self.secondaryChannels, id: \.self) { channel in
                            Text(channel).tag(channel)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("Core asset (newsletter, template, course, toolkit)", text: $platformCoreAsset)
                        .textFieldStyle(.roundedBorder)
                    TextField("Loop design (capture -> nurture -> convert -> retain)", text: $platformLoopDesign, axis: .vertical)
                        .lineLimit(2 ... 5)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        Button("Generate Platform Plan") {
                            runBusinessMentorPrompt(platformLeveragePrompt())
                        }
                        .buttonStyle(AtlasPrimaryButtonStyle())
                        .disabled(isRunningBusinessMentor)

                        Button("Queue Platform Plan in Chat") {
                            queuePromptInConcierge(platformLeveragePrompt())
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                    }
                }
            }

            AtlasPanel(
                heading: "Continuous Adaptive Questionnaire",
                caption: "Ollama keeps asking business-growth questions from memory with multi-select + freeform responses"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Answered: \(session.answeredAdaptiveBusinessQuestionCount) · Pending: \(session.adaptiveBusinessQuestions.filter { $0.response == nil }.count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.textSecondary)

                    Toggle("Enable continuous adaptive questions", isOn: $adaptiveQuestionEngineEnabled)
                        .tint(AtlasTheme.accentWarm)
                    Toggle("Enable background business autopilot", isOn: $adaptiveBusinessAutopilotEnabled)
                        .tint(AtlasTheme.accentWarm)

                    HStack(spacing: 8) {
                        Button("Save Runtime Settings") {
                            session.saveAdaptiveBusinessRuntimeSettings(
                                questionEngineEnabled: adaptiveQuestionEngineEnabled,
                                businessAutopilotEnabled: adaptiveBusinessAutopilotEnabled
                            )
                            businessRuntimeStatus = session.adaptiveBusinessRuntimeStatusLine
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())

                        Button("Generate Question Now") {
                            session.requestNextAdaptiveBusinessQuestionNow()
                        }
                        .buttonStyle(AtlasPrimaryButtonStyle())
                    }

                    if let question = session.pendingAdaptiveBusinessQuestion {
                        Text(question.prompt)
                            .font(.system(size: 14, weight: .semibold, design: .default))
                            .foregroundStyle(AtlasTheme.textPrimary)

                        ForEach(question.options, id: \.self) { option in
                            let selected = adaptiveSelectedOptions.contains(option)
                            Button(selected ? "✓ \(option)" : option) {
                                if selected {
                                    adaptiveSelectedOptions.remove(option)
                                } else {
                                    adaptiveSelectedOptions.insert(option)
                                }
                            }
                            .buttonStyle(AtlasSecondaryButtonStyle())
                        }

                        TextField("Add extra context (optional)", text: $adaptiveFreeformResponse, axis: .vertical)
                            .lineLimit(2 ... 5)
                            .textFieldStyle(.roundedBorder)

                        Button("Submit Response to Memory") {
                            session.answerAdaptiveBusinessQuestion(
                                questionID: question.id,
                                selectedOptions: Array(adaptiveSelectedOptions),
                                freeformText: adaptiveFreeformResponse
                            )
                            businessRuntimeStatus = session.adaptiveBusinessRuntimeStatusLine
                            adaptiveSelectedOptions.removeAll()
                            adaptiveFreeformResponse = ""
                        }
                        .buttonStyle(AtlasPrimaryButtonStyle())
                    } else {
                        Text("No pending adaptive question right now. Keep runtime enabled and Atlas will generate the next one.")
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }

                    Text(session.adaptiveBusinessRuntimeStatusLine)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.textSecondary)
                }
            }

            AtlasPanel(
                heading: "Kiwix + Ollama Guided Learning",
                caption: "Business mentor runtime activates only after survey completion and explicit confirmation"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Survey completion: \(session.surveyCompletionPercent)%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.textSecondary)

                    if !session.isPrimarySurveyComplete {
                        Text("Finish the initialization survey first. Once it is complete, you can activate guided learning here.")
                            .foregroundStyle(AtlasTheme.textSecondary)
                    } else if !session.guidedLearningActivated {
                        Text("Survey is complete. Activate guided learning when you're ready to start using the app.")
                            .foregroundStyle(AtlasTheme.textSecondary)
                        Button("I'm done with initialization and want to start using Atlas") {
                            session.activateGuidedLearningAfterSurvey()
                            learningRuntimeStatus = "Guided learning activated."
                        }
                        .buttonStyle(AtlasPrimaryButtonStyle())
                    } else {
                        Text("Guided learning is active. Kiwix provides grounded offline context, and Ollama personalizes the learning flow.")
                            .foregroundStyle(AtlasTheme.textSecondary)

                        TextField("Kiwix base URL", text: $kiwixBaseURL)
                            .textFieldStyle(.roundedBorder)
                        TextField("Ollama /v1/chat/completions URL", text: $ollamaEndpoint)
                            .textFieldStyle(.roundedBorder)
                        TextField("Ollama model", text: $ollamaModel)
                            .textFieldStyle(.roundedBorder)

                        Button("Save Kiwix + Ollama Settings") {
                            session.saveGuidedLearningSettings(
                                kiwixBaseURL: kiwixBaseURL,
                                ollamaEndpoint: ollamaEndpoint,
                                ollamaModel: ollamaModel
                            )
                            learningRuntimeStatus = "Guided learning settings saved."
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())

                        TextField("What do you want to learn right now?", text: $learningPrompt, axis: .vertical)
                            .lineLimit(3 ... 7)
                            .textFieldStyle(.roundedBorder)

                        Button(isRunningLearning ? "Generating..." : "Generate Personalized Learning Path") {
                            let prompt = learningPrompt
                            guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            isRunningLearning = true
                            Task {
                                let result = await session.requestGuidedLearningResponse(for: prompt)
                                await MainActor.run {
                                    learningAnswer = result.answer
                                    learningGrounding = result.groundingSummary
                                    learningSourceURL = result.kiwixSourceURL
                                    learningRuntimeStatus = result.runtimeStatus
                                    isRunningLearning = false
                                }
                            }
                        }
                        .buttonStyle(AtlasPrimaryButtonStyle())
                        .disabled(isRunningLearning)
                    }

                    Divider()
                        .overlay(AtlasTheme.border)

                    TextField("Ask a business-growth question for mentor mode", text: $businessMentorQuestion, axis: .vertical)
                        .lineLimit(2 ... 6)
                        .textFieldStyle(.roundedBorder)

                    Button(isRunningBusinessMentor ? "Mentor responding..." : "Ask Business Mentor") {
                        let prompt = businessMentorQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !prompt.isEmpty else { return }
                        runBusinessMentorPrompt(
                            """
                            You are my business mentor.
                            Use grounded context to answer with:
                            1) The highest-leverage move now
                            2) Why it matters economically
                            3) Exact 7-day execution sequence
                            4) A clear success metric

                            QUESTION:
                            \(prompt)
                            """
                        )
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())
                    .disabled(isRunningBusinessMentor)

                    if !learningRuntimeStatus.isEmpty {
                        Text(learningRuntimeStatus)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }

                    if !learningGrounding.isEmpty {
                        Text(learningGrounding)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }

                    if let learningSourceURL, !learningSourceURL.isEmpty {
                        Text("Kiwix source: \(learningSourceURL)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }

                    if !learningAnswer.isEmpty {
                        Text(learningAnswer)
                            .foregroundStyle(AtlasTheme.textSecondary)
                            .textSelection(.enabled)
                    }

                    if !businessRuntimeStatus.isEmpty {
                        Text(businessRuntimeStatus)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }

                    if !businessMentorGrounding.isEmpty {
                        Text(businessMentorGrounding)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }

                    if let businessMentorSourceURL, !businessMentorSourceURL.isEmpty {
                        Text("Business mentor source: \(businessMentorSourceURL)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }

                    if !businessMentorAnswer.isEmpty {
                        Text(businessMentorAnswer)
                            .foregroundStyle(AtlasTheme.textSecondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .onAppear {
                let settings = session.guidedLearningSettingsSnapshot()
                kiwixBaseURL = settings.kiwixBaseURL
                ollamaEndpoint = settings.ollamaEndpoint
                ollamaModel = settings.ollamaModel
                adaptiveQuestionEngineEnabled = session.adaptiveBusinessQuestionEngineEnabled
                adaptiveBusinessAutopilotEnabled = session.businessAutopilotEnabled
                syncAdaptiveQuestionDraft(with: session.pendingAdaptiveBusinessQuestion)
                loadBusinessExperiments()
                primeBusinessFields()
                learningRuntimeStatus = session.isGuidedLearningRuntimeActive
                    ? "Guided learning is active."
                    : "Guided learning is locked until post-survey activation."
            }
            .onChange(of: session.pendingAdaptiveBusinessQuestion?.id) { _, _ in
                syncAdaptiveQuestionDraft(with: session.pendingAdaptiveBusinessQuestion)
            }
        }
    }

    private var runningExperimentsCount: Int {
        experiments.filter { $0.status == .running }.count
    }

    private var completedExperimentsCount: Int {
        experiments.filter { $0.status == .won || $0.status == .lost }.count
    }

    private var experimentWinRatePercent: Int {
        let completed = completedExperimentsCount
        guard completed > 0 else { return 0 }
        let wins = experiments.filter { $0.status == .won }.count
        return Int((Double(wins) / Double(completed) * 100).rounded())
    }

    private var retentionRatePercent: Int {
        let active = numericValue(from: activeUsersInput)
        let retained = numericValue(from: retainedUsersInput)
        guard active > 0 else { return 0 }
        return Int(((retained / active) * 100).rounded())
    }

    private var netRevenueRetentionPercent: Int {
        let revenue = numericValue(from: monthlyRevenueInput)
        guard revenue > 0 else { return 0 }
        let expansion = numericValue(from: expansionRevenueInput)
        let churnOverride = numericValue(from: churnRateInput)
        let churn = churnOverride > 0 ? churnOverride : Double(max(0, 100 - retentionRatePercent))
        let nrr = ((revenue - (revenue * churn / 100) + expansion) / revenue) * 100
        return max(0, Int(nrr.rounded()))
    }

    private var growthReadinessScore: Int {
        var score = min(25, session.surveyCompletionPercent / 4)
        if session.guidedLearningActivated {
            score += 15
        }
        score += min(20, runningExperimentsCount * 5)
        score += min(20, experimentWinRatePercent / 5)
        score += min(20, retentionRatePercent / 5)
        return min(100, max(0, score))
    }

    private var retentionHealthLabel: String {
        if netRevenueRetentionPercent >= 110 {
            return "STRONG"
        }
        if netRevenueRetentionPercent >= 100 {
            return "STABLE"
        }
        return "AT RISK"
    }

    private func numericValue(from text: String) -> Double {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        return Double(normalized) ?? 0
    }

    private func queuePromptInConcierge(_ prompt: String) {
        session.pendingPrompt = prompt
#if os(iOS)
        session.enqueuePrompt(outputType: .standard)
#else
        session.enqueuePrompt()
#endif
        businessRuntimeStatus = "Prompt queued in chat."
    }

    private func runBusinessMentorPrompt(_ prompt: String) {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }
        isRunningBusinessMentor = true
        Task {
            let response = await session.requestGuidedLearningResponse(for: cleanPrompt)
            await MainActor.run {
                businessMentorAnswer = response.answer
                businessMentorGrounding = response.groundingSummary
                businessMentorSourceURL = response.kiwixSourceURL
                businessRuntimeStatus = response.runtimeStatus
                isRunningBusinessMentor = false
            }
        }
    }

    private func growthBriefPrompt() -> String {
        """
        Build a weekly growth operating brief using principles used by large scaled businesses:
        - customer obsession and value delivery
        - fast experimentation with clear metrics
        - retention and expansion discipline
        - compounding distribution loops

        Context:
        - North-star metric: \(northStarMetric.isEmpty ? "not set" : northStarMetric)
        - Weekly target: \(northStarTarget.isEmpty ? "not set" : northStarTarget)
        - Running experiments: \(runningExperimentsCount)
        - Experiment win rate: \(experimentWinRatePercent)%
        - Retention rate: \(retentionRatePercent)%
        - Net revenue retention: \(netRevenueRetentionPercent)%
        - Survey completion: \(session.surveyCompletionPercent)%

        Return:
        1) Biggest bottleneck now
        2) Three prioritized moves for next 7 days
        3) One metric dashboard spec
        4) One risk and mitigation
        """
    }

    private func retentionPlanPrompt() -> String {
        """
        Build a retention + revenue protection plan.
        Inputs:
        - Active users: \(activeUsersInput.isEmpty ? "not set" : activeUsersInput)
        - Retained users: \(retainedUsersInput.isEmpty ? "not set" : retainedUsersInput)
        - Retention rate: \(retentionRatePercent)%
        - MRR: \(monthlyRevenueInput.isEmpty ? "not set" : monthlyRevenueInput)
        - Expansion revenue: \(expansionRevenueInput.isEmpty ? "not set" : expansionRevenueInput)
        - NRR: \(netRevenueRetentionPercent)%

        Return:
        1) Segment-specific churn diagnosis
        2) Onboarding fix sequence
        3) Expansion offer design
        4) 14-day KPI checkpoints
        """
    }

    private func platformLeveragePrompt() -> String {
        """
        Build a platform leverage plan with compounding distribution.
        Inputs:
        - Primary channel: \(platformPrimaryChannel)
        - Secondary channel: \(platformSecondaryChannel)
        - Core asset: \(platformCoreAsset.isEmpty ? "not set" : platformCoreAsset)
        - Loop design: \(platformLoopDesign.isEmpty ? "not set" : platformLoopDesign)

        Return:
        1) Channel strategy for next 30 days
        2) Content/asset cadence
        3) Conversion path to paid value
        4) Retention loop and flywheel metric
        """
    }

    private func experimentPortfolioPrompt() -> String {
        let summary = experiments.prefix(8).map { experiment in
            "- \(experiment.hypothesis) | metric: \(experiment.metric) | target: \(experiment.target) | status: \(experiment.status.displayName)"
        }.joined(separator: "\n")
        return """
        Review this experiment portfolio and recommend what to stop, scale, or redesign:
        \(summary)

        Return:
        1) Top 2 experiments to scale
        2) 1 experiment to kill
        3) Redesign suggestion for weakest experiment
        4) Portfolio-level metric architecture
        """
    }

    private func experimentReviewPrompt(for experiment: BusinessExperiment) -> String {
        """
        Review this experiment and provide a decision memo.
        - Hypothesis: \(experiment.hypothesis)
        - Metric: \(experiment.metric)
        - Target: \(experiment.target)
        - Status: \(experiment.status.displayName)
        - Window: \(experiment.windowDays) days

        Return:
        1) Is the hypothesis strong?
        2) What evidence is missing?
        3) How to improve test design?
        4) Keep, pivot, or stop decision
        """
    }

    private func createExperiment() {
        let hypothesis = experimentHypothesis.trimmingCharacters(in: .whitespacesAndNewlines)
        let metric = experimentMetric.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = experimentTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hypothesis.isEmpty, !metric.isEmpty, !target.isEmpty else {
            businessRuntimeStatus = "Add hypothesis, metric, and target to create an experiment."
            return
        }

        let experiment = BusinessExperiment(
            id: UUID().uuidString,
            hypothesis: hypothesis,
            metric: metric,
            target: target,
            windowDays: experimentDurationDays,
            status: .running,
            createdAtUTC: Date()
        )
        experiments.insert(experiment, at: 0)
        saveBusinessExperiments()
        experimentHypothesis = ""
        experimentMetric = ""
        experimentTarget = ""
        businessRuntimeStatus = "Experiment added."
    }

    private func updateExperiment(_ id: String, status: BusinessExperiment.Status) {
        guard let index = experiments.firstIndex(where: { $0.id == id }) else { return }
        experiments[index].status = status
        saveBusinessExperiments()
        businessRuntimeStatus = "Experiment updated: \(status.displayName)."
    }

    private func loadBusinessExperiments() {
        guard let data = UserDefaults.standard.data(forKey: Self.businessExperimentStorageKey) else { return }
        if let decoded = try? JSONDecoder().decode([BusinessExperiment].self, from: data) {
            experiments = decoded
        }
    }

    private func saveBusinessExperiments() {
        if let data = try? JSONEncoder().encode(experiments) {
            UserDefaults.standard.set(data, forKey: Self.businessExperimentStorageKey)
        }
    }

    private func primeBusinessFields() {
        if northStarMetric.isEmpty {
            northStarMetric = "Weekly active learners"
        }
        if northStarTarget.isEmpty {
            northStarTarget = "+8% WoW"
        }
        if platformCoreAsset.isEmpty {
            platformCoreAsset = "Practical learning playbooks"
        }
        if platformLoopDesign.isEmpty {
            platformLoopDesign = "content -> opt-in -> guided lesson -> activation -> retention"
        }
        if businessRuntimeStatus.isEmpty {
            businessRuntimeStatus = session.isGuidedLearningRuntimeActive
                ? "Business mentor runtime is active."
                : "Business mentor runtime is locked until post-survey activation."
        }
    }

    private func syncAdaptiveQuestionDraft(with question: SessionStore.AdaptiveBusinessQuestion?) {
        guard let question else {
            adaptiveQuestionID = nil
            adaptiveSelectedOptions.removeAll()
            adaptiveFreeformResponse = ""
            return
        }
        guard adaptiveQuestionID != question.id else { return }
        adaptiveQuestionID = question.id
        adaptiveSelectedOptions = Set(question.response?.selectedOptions ?? [])
        adaptiveFreeformResponse = question.response?.freeformText ?? ""
    }
}

private struct BusinessExperiment: Codable, Identifiable, Hashable {
    enum Status: String, Codable, CaseIterable {
        case running
        case won
        case lost

        var displayName: String {
            switch self {
            case .running:
                return "RUNNING"
            case .won:
                return "WON"
            case .lost:
                return "LOST"
            }
        }
    }

    let id: String
    var hypothesis: String
    var metric: String
    var target: String
    var windowDays: Int
    var status: Status
    var createdAtUTC: Date

    var createdAtLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        return formatter.string(from: createdAtUTC)
    }
}
