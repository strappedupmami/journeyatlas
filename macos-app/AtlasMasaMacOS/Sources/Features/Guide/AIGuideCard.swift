import AppKit
import SwiftUI

// MARK: - Internal Navigation
enum AIGuideTab: String, CaseIterable, Identifiable {
    case overview = "System Overview"
    case growth = "Growth OS & Experiments"
    case learning = "Adaptive Learning & Mentorship"
    var id: String { self.rawValue }
}

struct AIGuideCard: View {
    @EnvironmentObject private var session: SessionStore
    @State private var selectedTab: AIGuideTab = .overview

    // MARK: - State Properties (Growth OS)
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

    // MARK: - State Properties (Experiments)
    @State private var experimentHypothesis = ""
    @State private var experimentMetric = ""
    @State private var experimentTarget = ""
    @State private var experimentDurationDays = 14
    @State private var experiments: [BusinessExperiment] = []

    // MARK: - State Properties (Learning & Mentor)
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
    @State private var learningLessonCard = GuidedLearningLessonCard.empty
    @State private var geminiDesignCard = ""

    // MARK: - Constants
    private static let businessExperimentStorageKey = "atlas.ios.business.experiments.v1"
    private static let primaryChannels = ["YouTube", "Newsletter", "LinkedIn", "TikTok", "X/Twitter", "Podcast", "Community"]
    private static let secondaryChannels = ["Newsletter", "Blog/SEO", "DM/Outbound", "Partnerships", "Webinars", "Affiliate", "Community"]

    // MARK: - Main Body
    var body: some View {
        AtlasScreen(
            title: "Atlas Core",
            subtitle: "System capabilities, business growth loops, and adaptive mentor configuration"
        ) {
            VStack(alignment: .leading, spacing: 24) {
                // High-End macOS Segmented Control for Sub-navigation
                Picker("Section", selection: $selectedTab) {
                    ForEach(AIGuideTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 600)

                Divider()

                // Content Routing
                switch selectedTab {
                case .overview:
                    overviewSection
                case .growth:
                    growthOSSection
                case .learning:
                    learningSection
                }
            }
        }
        .onAppear {
            initializeData()
        }
        .onChange(of: session.pendingAdaptiveBusinessQuestion?.id) { _, _ in
            syncAdaptiveQuestionDraft(with: session.pendingAdaptiveBusinessQuestion)
        }
    }

    // MARK: - Tab 1: System Overview
    private var overviewSection: some View {
        HStack(alignment: .top, spacing: 24) {
            // Left Column: The "Why" and "How"
            VStack(spacing: 20) {
                AtlasPanel(heading: "System Mission", caption: "Why Atlas was built") {
                    Text("Atlas is built to help people operate with more financial stability, healthier cognitive performance, and stronger execution under real-world pressure. The system focuses on daily function, long-term wealth mobility, and practical resilience.")
                        .font(.subheadline)
                        .foregroundStyle(AtlasTheme.textSecondary)
                }

                AtlasPanel(heading: "Operational Pipeline", caption: "How Atlas works in-app") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Intake: Adaptive survey, notes, prompts, and check-ins.", systemImage: "1.circle.fill")
                        Label("Synthesis: Model inference identifies blockers and priorities.", systemImage: "2.circle.fill")
                        Label("Execution: Daily/mid/long actions, workspace plans, and queue outputs.", systemImage: "3.circle.fill")
                        Label("Iteration: Behavior data updates recommendations and learning packages.", systemImage: "4.circle.fill")
                    }
                    .font(.subheadline)
                    .foregroundStyle(AtlasTheme.textSecondary)
                }

                AtlasPanel(heading: "Professional Boundaries", caption: "Safe usage guidelines") {
                    Text("Atlas provides structured decision support, not guaranteed outcomes or licensed professional advice. Validate high-stakes medical, legal, and regulated financial decisions with qualified professionals.")
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.accentWarm)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            // Right Column: Footprint and Capabilities
            VStack(spacing: 20) {
                AtlasPanel(heading: "Live Data Footprint", caption: "What is currently available to the planning engine") {
                    Form {
                        LabeledContent("Survey Answers", value: "\(session.survey?.progress.answered ?? 0)")
                        LabeledContent("Notes Stored", value: "\(session.notes.count)")
                        LabeledContent("Workspace Sessions", value: "\(session.workspaceSessions.count)")
                        LabeledContent("Memory Records", value: "\(session.workspaceMemoryRecords.count)")
                        LabeledContent("Queued Prompts", value: "\(session.promptQueue.count)")
                        LabeledContent("Execution Actions", value: "\(session.executionActions.count)")
                    }
                    .formStyle(.grouped)
                }

                AtlasPanel(heading: "Personalization Engine", caption: "Memory and privacy behavior") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Personalization uses your own inputs. If memory collection is disabled, Atlas relies only on lighter session context.")
                            .font(.subheadline)
                            .foregroundStyle(AtlasTheme.textSecondary)

                        HStack {
                            AtlasPill(title: session.memoryCollectionEnabled ? "Memory: Active" : "Memory: Disabled")
                            AtlasPill(title: "Tier: \(session.selectedTier.title)")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    // MARK: - Tab 2: Growth OS & Experiments
    private var growthOSSection: some View {
        HStack(alignment: .top, spacing: 24) {
            // Left Column: Business Metrics
            VStack(spacing: 20) {
                AtlasPanel(heading: "Growth OS Dashboard", caption: "North-star metrics and execution loops") {
                    HStack(spacing: 12) {
                        MetricCard(title: "Readiness", value: "\(growthReadinessScore)%")
                        MetricCard(title: "Running Exp.", value: "\(runningExperimentsCount)")
                        MetricCard(title: "Win Rate", value: "\(experimentWinRatePercent)%")
                    }

                    Form {
                        Section("North-Star Strategy") {
                            TextField("Metric (e.g., Active Learners)", text: $northStarMetric)
                            TextField("Weekly Target (e.g., +8%)", text: $northStarTarget)
                        }
                    }

                    HStack {
                        Button("Generate Brief") { runBusinessMentorPrompt(growthBriefPrompt()) }
                            .buttonStyle(AtlasPrimaryButtonStyle())
                            .disabled(isRunningBusinessMentor)
                        Button("Queue in Chat") { queuePromptInConcierge(growthBriefPrompt()) }
                            .buttonStyle(AtlasSecondaryButtonStyle())
                    }
                }

                AtlasPanel(heading: "Retention & Revenue", caption: "Protect recurring value") {
                    Form {
                        TextField("Active Users", text: $activeUsersInput)
                        TextField("Retained Users", text: $retainedUsersInput)
                        TextField("MRR (USD)", text: $monthlyRevenueInput)
                        TextField("Expansion Rev (USD)", text: $expansionRevenueInput)
                        TextField("Churn Rate % (Override)", text: $churnRateInput)
                    }

                    HStack(spacing: 12) {
                        MetricCard(title: "Retention", value: "\(retentionRatePercent)%")
                        MetricCard(title: "Net Rev (NRR)", value: "\(netRevenueRetentionPercent)%")
                        AtlasPill(title: retentionHealthLabel)
                    }
                    .padding(.vertical, 8)

                    HStack {
                        Button("Generate Plan") { runBusinessMentorPrompt(retentionPlanPrompt()) }
                            .buttonStyle(AtlasPrimaryButtonStyle())
                            .disabled(isRunningBusinessMentor)
                    }
                }

                AtlasPanel(heading: "Platform Leverage", caption: "Design compounding distribution loops") {
                    Form {
                        Picker("Primary Channel", selection: $platformPrimaryChannel) {
                            ForEach(Self.primaryChannels, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Secondary Channel", selection: $platformSecondaryChannel) {
                            ForEach(Self.secondaryChannels, id: \.self) { Text($0).tag($0) }
                        }
                        TextField("Core Asset", text: $platformCoreAsset)
                        TextField("Loop Design", text: $platformLoopDesign)
                    }
                    Button("Generate Platform Plan") { runBusinessMentorPrompt(platformLeveragePrompt()) }
                        .buttonStyle(AtlasPrimaryButtonStyle())
                        .disabled(isRunningBusinessMentor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            // Right Column: Experiment Engine
            VStack(spacing: 20) {
                AtlasPanel(heading: "Experiment Engine", caption: "High-velocity test loop") {
                    Form {
                        TextField("Hypothesis", text: $experimentHypothesis, axis: .vertical).lineLimit(2 ... 4)
                        TextField("Primary Metric", text: $experimentMetric)
                        TextField("Success Target", text: $experimentTarget)
                        Stepper("Duration: \(experimentDurationDays) days", value: $experimentDurationDays, in: 3 ... 45)
                    }

                    HStack {
                        Button("Create Experiment") { createExperiment() }
                            .buttonStyle(AtlasPrimaryButtonStyle())
                        Button("Review Portfolio") { runBusinessMentorPrompt(experimentPortfolioPrompt()) }
                            .buttonStyle(AtlasSecondaryButtonStyle())
                            .disabled(isRunningBusinessMentor || experiments.isEmpty)
                    }

                    Divider().padding(.vertical, 8)

                    if experiments.isEmpty {
                        ContentUnavailableView("No Experiments", systemImage: "flask", description: Text("Add an experiment with a clear hypothesis and success target."))
                            .frame(height: 200)
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(experiments) { experiment in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(experiment.hypothesis)
                                                .font(.headline)
                                            Spacer()
                                            AtlasPill(title: experiment.status.displayName)
                                        }
                                        Text("Metric: **\(experiment.metric)** · Target: **\(experiment.target)**")
                                            .font(.caption)
                                            .foregroundStyle(AtlasTheme.textSecondary)

                                        HStack {
                                            if experiment.status == .running {
                                                Button("Mark Won") { updateExperiment(experiment.id, status: .won) }
                                                    .buttonStyle(.bordered)
                                                    .controlSize(.small)
                                                Button("Mark Lost") { updateExperiment(experiment.id, status: .lost) }
                                                    .buttonStyle(.bordered)
                                                    .controlSize(.small)
                                            }
                                            Spacer()
                                            Button("Ask Mentor") { runBusinessMentorPrompt(experimentReviewPrompt(for: experiment)) }
                                                .buttonStyle(.borderedProminent)
                                                .controlSize(.small)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AtlasTheme.border, lineWidth: 1))
                                }
                            }
                        }
                        .frame(maxHeight: 600)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    // MARK: - Tab 3: Learning & Mentorship
    private var learningSection: some View {
        HStack(alignment: .top, spacing: 24) {
            // Left Column: Adaptive Questionnaire
            VStack(spacing: 20) {
                AtlasPanel(heading: "Continuous Adaptive Questionnaire", caption: "Ollama gathers business context via memory") {
                    Form {
                        Toggle("Enable Continuous Questions", isOn: $adaptiveQuestionEngineEnabled)
                        Toggle("Enable Background Autopilot", isOn: $adaptiveBusinessAutopilotEnabled)
                    }
                    .toggleStyle(.switch)

                    HStack {
                        Button("Save Settings") {
                            session.saveAdaptiveBusinessRuntimeSettings(questionEngineEnabled: adaptiveQuestionEngineEnabled, businessAutopilotEnabled: adaptiveBusinessAutopilotEnabled)
                            businessRuntimeStatus = session.adaptiveBusinessRuntimeStatusLine
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())

                        Button("Force Generate Next") { session.requestNextAdaptiveBusinessQuestionNow() }
                            .buttonStyle(AtlasSecondaryButtonStyle())
                    }

                    Divider().padding(.vertical, 8)

                    if let question = session.pendingAdaptiveBusinessQuestion {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(question.prompt)
                                .font(.headline)

                            ForEach(question.options, id: \.self) { option in
                                let isSelected = adaptiveSelectedOptions.contains(option)
                                Button(action: {
                                    if isSelected {
                                        adaptiveSelectedOptions.remove(option)
                                    } else {
                                        adaptiveSelectedOptions.insert(option)
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(isSelected ? AtlasTheme.accentWarm : AtlasTheme.textSecondary)
                                        Text(option)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .padding(8)
                                .background(isSelected ? AtlasTheme.accentWarm.opacity(0.1) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }

                            TextField("Extra context (optional)", text: $adaptiveFreeformResponse, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2 ... 4)

                            Button("Submit Response") {
                                session.answerAdaptiveBusinessQuestion(questionID: question.id, selectedOptions: Array(adaptiveSelectedOptions), freeformText: adaptiveFreeformResponse)
                                businessRuntimeStatus = session.adaptiveBusinessRuntimeStatusLine
                                adaptiveSelectedOptions.removeAll()
                                adaptiveFreeformResponse = ""
                            }
                            .buttonStyle(AtlasPrimaryButtonStyle())
                        }
                    } else {
                        ContentUnavailableView("No Pending Questions", systemImage: "tray", description: Text("Atlas will generate the next context question automatically."))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            // Right Column: Guided Learning & Output
            VStack(spacing: 20) {
                AtlasPanel(heading: "Guided Learning Backend", caption: "Kiwix + Ollama Integration") {
                    if !session.isPrimarySurveyComplete {
                        Text("Finish the initialization survey first to unlock guided learning.")
                            .foregroundStyle(AtlasTheme.textSecondary)
                    } else if !session.guidedLearningActivated {
                        Button("Activate Guided Learning") {
                            session.activateGuidedLearningAfterSurvey()
                            learningRuntimeStatus = "Activated."
                        }
                        .buttonStyle(AtlasPrimaryButtonStyle())
                    } else {
                        Form {
                            Section("Local Server Configuration") {
                                TextField("Kiwix Base URL", text: $kiwixBaseURL)
                                TextField("Ollama Endpoint", text: $ollamaEndpoint)
                                TextField("Ollama Model", text: $ollamaModel)
                            }
                        }

                        Button("Save Configuration") {
                            session.saveGuidedLearningSettings(kiwixBaseURL: kiwixBaseURL, ollamaEndpoint: ollamaEndpoint, ollamaModel: ollamaModel)
                            learningRuntimeStatus = "Settings saved."
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())

                        Divider().padding(.vertical, 8)

                        TextField("What do you want to learn?", text: $learningPrompt, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3 ... 5)

                        Button(isRunningLearning ? "Generating..." : "Generate Learning Path") {
                            Task {
                                isRunningLearning = true
                                let result = await session.requestGuidedLearningResponse(
                                    for: duolingoFormattedLearningPrompt(for: learningPrompt)
                                )
                                await MainActor.run {
                                    let parsedCard = buildLearningLessonCard(from: result.answer, query: learningPrompt)
                                    learningAnswer = result.answer
                                    learningGrounding = result.groundingSummary
                                    learningSourceURL = result.kiwixSourceURL
                                    learningRuntimeStatus = result.runtimeStatus
                                    learningLessonCard = parsedCard
                                    geminiDesignCard = buildGeminiDesignCard(
                                        from: parsedCard,
                                        sourceURL: result.kiwixSourceURL,
                                        userQuery: learningPrompt,
                                        rawAnswer: result.answer
                                    )
                                    isRunningLearning = false
                                }
                            }
                        }
                        .buttonStyle(AtlasPrimaryButtonStyle())
                        .disabled(isRunningLearning || learningPrompt.isEmpty)
                    }
                }

                if learningLessonCard.hasContent {
                    AtlasPanel(heading: "Duolingo-Style Learning Section", caption: "Comprehensive, visually minimal lesson card") {
                        duolingoLearningCardView
                    }
                }

                if !geminiDesignCard.isEmpty {
                    AtlasPanel(heading: "Gemini 3.1 Pro Design Card", caption: "Copy this handoff to iterate visual design") {
                        VStack(alignment: .leading, spacing: 10) {
                            ScrollView {
                                Text(geminiDesignCard)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(AtlasTheme.textSecondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 240)

                            HStack {
                                Button("Copy Gemini Card") {
                                    copyToClipboard(geminiDesignCard)
                                    learningRuntimeStatus = "Gemini design card copied to clipboard."
                                }
                                .buttonStyle(AtlasSecondaryButtonStyle())
                                Spacer()
                            }
                        }
                    }
                }

                if !businessRuntimeStatus.isEmpty || !learningRuntimeStatus.isEmpty || !learningGrounding.isEmpty || !businessMentorAnswer.isEmpty {
                    AtlasPanel(heading: "Runtime Output", caption: "Status, grounding, and mentor logs") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                if !learningRuntimeStatus.isEmpty {
                                    Text("> \(learningRuntimeStatus)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                if !learningGrounding.isEmpty {
                                    Text(learningGrounding)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !businessRuntimeStatus.isEmpty {
                                    Text("> \(businessRuntimeStatus)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                if !businessMentorAnswer.isEmpty {
                                    Text(businessMentorAnswer)
                                        .font(.body)
                                        .textSelection(.enabled)
                                }
                                if !businessMentorGrounding.isEmpty {
                                    Text(businessMentorGrounding)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let learningSourceURL, !learningSourceURL.isEmpty {
                                    Text("Learning source: \(learningSourceURL)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                if let businessMentorSourceURL, !businessMentorSourceURL.isEmpty {
                                    Text("Mentor source: \(businessMentorSourceURL)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 240)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    // MARK: - Helper UI Components
    private struct MetricCard: View {
        let title: String
        let value: String
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(AtlasTheme.textSecondary)
                Text(value).font(.title3.weight(.bold)).foregroundStyle(AtlasTheme.textPrimary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AtlasTheme.border, lineWidth: 1))
        }
    }

    private var duolingoLearningCardView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(learningLessonCard.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text(learningLessonCard.keyInsight)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.86))
            }

            HStack(spacing: 8) {
                learningStatPill(title: "\(learningLessonCard.estimatedMinutes)m")
                learningStatPill(title: learningLessonCard.difficulty)
                learningStatPill(title: "\(learningLessonCard.xpReward) XP")
            }

            if !learningLessonCard.sourceGuide.isEmpty {
                Text(learningLessonCard.sourceGuide)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.76))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Learning Path")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.88))

                ForEach(Array(learningLessonCard.pathSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(AtlasTheme.accent)
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        Text("\(index + 1). \(step)")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.16))

            VStack(alignment: .leading, spacing: 6) {
                Text("Practice Drill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
                Text(learningLessonCard.practiceDrill)
                    .font(.caption)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Quick Check")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
                Text(learningLessonCard.quizQuestion)
                    .font(.caption)
                    .foregroundStyle(.white)

                ForEach(learningLessonCard.quizOptions, id: \.self) { option in
                    Text(option)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                if !learningLessonCard.quizCorrectOption.isEmpty {
                    Text("Correct: \(learningLessonCard.quizCorrectOption)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AtlasTheme.accent)
                }
                if !learningLessonCard.quizWhy.isEmpty {
                    Text(learningLessonCard.quizWhy)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }

            Divider().overlay(Color.white.opacity(0.16))

            VStack(alignment: .leading, spacing: 5) {
                Text("Reflection")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
                Text(learningLessonCard.reflectionCheckpoint)
                    .font(.caption)
                    .foregroundStyle(.white)
                Text("Next: \(learningLessonCard.nextAction)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AtlasTheme.accent)
                Text(learningLessonCard.motivation)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.74))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AtlasTheme.pureBlack.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AtlasTheme.accentWarm, lineWidth: 1)
        )
    }

    private func learningStatPill(title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.94))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
    }

    private struct GuidedLearningLessonCard: Hashable {
        var title: String
        var estimatedMinutes: String
        var difficulty: String
        var xpReward: String
        var sourceGuide: String
        var keyInsight: String
        var pathSteps: [String]
        var practiceDrill: String
        var quizQuestion: String
        var quizOptions: [String]
        var quizCorrectOption: String
        var quizWhy: String
        var reflectionCheckpoint: String
        var nextAction: String
        var motivation: String

        var hasContent: Bool {
            !title.isEmpty || !keyInsight.isEmpty || !practiceDrill.isEmpty
        }

        static let empty = GuidedLearningLessonCard(
            title: "",
            estimatedMinutes: "12",
            difficulty: "Medium",
            xpReward: "50",
            sourceGuide: "",
            keyInsight: "",
            pathSteps: [],
            practiceDrill: "",
            quizQuestion: "",
            quizOptions: [],
            quizCorrectOption: "",
            quizWhy: "",
            reflectionCheckpoint: "",
            nextAction: "",
            motivation: ""
        )
    }

    // MARK: - Logic & Calculations
    private func initializeData() {
        let settings = session.guidedLearningSettingsSnapshot()
        kiwixBaseURL = settings.kiwixBaseURL
        ollamaEndpoint = settings.ollamaEndpoint
        ollamaModel = settings.ollamaModel
        adaptiveQuestionEngineEnabled = session.adaptiveBusinessQuestionEngineEnabled
        adaptiveBusinessAutopilotEnabled = session.businessAutopilotEnabled
        syncAdaptiveQuestionDraft(with: session.pendingAdaptiveBusinessQuestion)
        loadBusinessExperiments()
        primeBusinessFields()
        learningRuntimeStatus = session.isGuidedLearningRuntimeActive ? "Guided learning is active." : "Guided learning is locked."
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

    private func duolingoFormattedLearningPrompt(for query: String) -> String {
        """
        \(query)

        FORMAT REQUIREMENTS
        Return concise markdown using these exact headers and labels:
        # Lesson Title
        ## Session Stats
        Estimated Minutes: <integer>
        Difficulty: <Easy|Medium|Hard>
        XP Reward: <integer>
        ## Source Guide
        ## Key Insight
        ## Learning Path
        (exactly 4 numbered steps)
        ## Practice Drill
        ## Quick Check
        Question: <text>
        Option A: <text>
        Option B: <text>
        Option C: <text>
        Correct Option: <A|B|C>
        Why: <one line>
        ## Reflection Checkpoint
        ## Next Action
        ## Motivation

        Keep it practical, execution-oriented, and brief.
        """
    }

    private func buildLearningLessonCard(from answer: String, query: String) -> GuidedLearningLessonCard {
        let cleanAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAnswer.isEmpty else { return .empty }

        var card = GuidedLearningLessonCard.empty
        card.title = markdownH1(in: cleanAnswer) ?? "Learning Sprint: \(normalizeInlineText(query))"

        let stats = markdownSection("Session Stats", in: cleanAnswer)
        card.estimatedMinutes = extractField("Estimated Minutes", in: stats) ?? "12"
        card.difficulty = extractField("Difficulty", in: stats) ?? "Medium"
        card.xpReward = extractField("XP Reward", in: stats) ?? "50"

        card.sourceGuide = markdownSection("Source Guide", in: cleanAnswer)
        card.keyInsight = markdownSection("Key Insight", in: cleanAnswer)

        let learningPathSection = markdownSection("Learning Path", in: cleanAnswer)
        card.pathSteps = markdownListItems(from: learningPathSection)
        if card.pathSteps.isEmpty {
            card.pathSteps = compactLines(from: learningPathSection, limit: 4)
        }
        if card.pathSteps.isEmpty {
            card.pathSteps = [
                "Frame the idea in one sentence.",
                "Apply it to a concrete business/workflow example.",
                "Test your understanding with one checkpoint.",
                "Execute one measurable next action."
            ]
        }

        card.practiceDrill = markdownSection("Practice Drill", in: cleanAnswer)
        let quickCheck = markdownSection("Quick Check", in: cleanAnswer)
        card.quizQuestion = extractField("Question", in: quickCheck) ?? "What is the most important action from this lesson?"
        card.quizOptions = [
            extractField("Option A", in: quickCheck),
            extractField("Option B", in: quickCheck),
            extractField("Option C", in: quickCheck),
        ]
        .compactMap { $0 }
        if card.quizOptions.isEmpty {
            card.quizOptions = markdownListItems(from: quickCheck)
        }
        card.quizCorrectOption = extractField("Correct Option", in: quickCheck) ?? ""
        card.quizWhy = extractField("Why", in: quickCheck) ?? ""

        card.reflectionCheckpoint = markdownSection("Reflection Checkpoint", in: cleanAnswer)
        card.nextAction = markdownSection("Next Action", in: cleanAnswer)
        card.motivation = markdownSection("Motivation", in: cleanAnswer)

        if card.keyInsight.isEmpty {
            card.keyInsight = "This lesson is grounded in your Kiwix source context and tailored to your current goals."
        }
        if card.practiceDrill.isEmpty {
            card.practiceDrill = "Run one 15-minute drill using today’s concept and log your result."
        }
        if card.reflectionCheckpoint.isEmpty {
            card.reflectionCheckpoint = "What clicked? What still feels fuzzy? What action will make this real today?"
        }
        if card.nextAction.isEmpty {
            card.nextAction = "Block 15 minutes and execute step 1 from the path."
        }
        if card.motivation.isEmpty {
            card.motivation = "Small consistent wins beat occasional perfect sessions."
        }

        return card
    }

    private func buildGeminiDesignCard(
        from card: GuidedLearningLessonCard,
        sourceURL: String?,
        userQuery: String,
        rawAnswer: String
    ) -> String {
        """
        You are Gemini 3.1 Pro. Design a Duolingo-style, visually minimal learning card for a macOS app.

        Product context:
        - Input stack: Kiwix (grounding snippets) + Ollama (personalized synthesis)
        - Visual direction: premium minimal, pure black base, dark red accents, high readability
        - Goal: comprehensive learning flow without visual clutter

        Content payload (exact):
        - User Query: \(normalizeInlineText(userQuery))
        - Lesson Title: \(normalizeInlineText(card.title))
        - Session Stats: \(normalizeInlineText(card.estimatedMinutes)) min | \(normalizeInlineText(card.difficulty)) | \(normalizeInlineText(card.xpReward)) XP
        - Source Guide: \(normalizeInlineText(card.sourceGuide))
        - Key Insight: \(normalizeInlineText(card.keyInsight))
        - Learning Path:
          1. \(normalizeInlineText(pathStep(at: 0, from: card.pathSteps)))
          2. \(normalizeInlineText(pathStep(at: 1, from: card.pathSteps)))
          3. \(normalizeInlineText(pathStep(at: 2, from: card.pathSteps)))
          4. \(normalizeInlineText(pathStep(at: 3, from: card.pathSteps)))
        - Practice Drill: \(normalizeInlineText(card.practiceDrill))
        - Quick Check Question: \(normalizeInlineText(card.quizQuestion))
        - Quick Check Options: \(normalizeInlineText(card.quizOptions.joined(separator: " | ")))
        - Correct Option: \(normalizeInlineText(card.quizCorrectOption))
        - Reflection Checkpoint: \(normalizeInlineText(card.reflectionCheckpoint))
        - Next Action: \(normalizeInlineText(card.nextAction))
        - Motivation: \(normalizeInlineText(card.motivation))
        - Grounded Source URL: \(normalizeInlineText(sourceURL ?? "none"))

        Design requirements:
        - Output 1: component hierarchy and spacing system
        - Output 2: typography scale and font recommendations
        - Output 3: black/red color tokens with contrast-safe values
        - Output 4: interaction states (idle, hover, selected, completed)
        - Output 5: SwiftUI-ready style tokens + sample layout pseudocode
        - Keep it visually minimal but information-complete

        Raw model output for reference:
        \(rawAnswer.prefix(1800))
        """
    }

    private func copyToClipboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func markdownH1(in text: String) -> String? {
        text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.hasPrefix("# ") })
            .map { normalizeInlineText(String($0.dropFirst(2))) }
    }

    private func markdownSection(_ title: String, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: title)
        let pattern = "(?ms)^##\\s+\(escaped)\\s*$\\n(.*?)(?=^##\\s+|\\z)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let nsRange = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              let sectionRange = Range(match.range(at: 1), in: text)
        else {
            return ""
        }
        return text[sectionRange].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func markdownListItems(from text: String) -> [String] {
        text
            .split(separator: "\n")
            .compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                let pattern = #"^(?:[-*]\s+|\d+\.\s+)(.+)$"#
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
                let nsRange = NSRange(line.startIndex ..< line.endIndex, in: line)
                guard let match = regex.firstMatch(in: line, options: [], range: nsRange),
                      let valueRange = Range(match.range(at: 1), in: line)
                else {
                    return nil
                }
                return normalizeInlineText(String(line[valueRange]))
            }
    }

    private func compactLines(from text: String, limit: Int) -> [String] {
        text
            .split(separator: "\n")
            .map { normalizeInlineText(String($0)) }
            .filter { !$0.isEmpty }
            .prefix(limit)
            .map { $0 }
    }

    private func extractField(_ fieldName: String, in block: String) -> String? {
        block
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { line -> String? in
                let lowerLine = line.lowercased()
                let lowerField = fieldName.lowercased()
                guard lowerLine.hasPrefix("\(lowerField):") else { return nil }
                let value = line.dropFirst(fieldName.count + 1)
                return normalizeInlineText(String(value))
            }
            .first
    }

    private func normalizeInlineText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pathStep(at index: Int, from steps: [String]) -> String {
        guard steps.indices.contains(index) else { return "" }
        return steps[index]
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
