import SwiftUI

struct CommandCenterCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "BlackHaven Home",
            subtitle: "Swift-native home dashboard for daily, mid-term, and long-horizon execution"
        ) {
            if session.shouldShowLocalAISetupExperience {
                localAISetupPanel
            } else {
                HStack(alignment: .top, spacing: 24) {
                    VStack(spacing: 24) {
                        onboardingPanel
                        accountAndSafetyPanel
                        checkInPanel
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(spacing: 24) {
                        remoteControlPanel
                        stateAwareExecutionPanel
                        travelItineraryPanel
                        executionStreamWindowPanel
                        checklistActivityPanel
                        executionPlanPanel
                        inferenceBriefPanel
                        transparencyPanel
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
    }
    
    // MARK: - Subviews

    private var onboardingPanel: some View {
        AtlasPanel(heading: "Welcome To BlackHaven", caption: "Start here before execution stream unlock") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Welcome to BlackHaven. To get started on wealth building and life improvement, complete the adaptive deep survey powered by local AI (Qwen 2.5 / DeepSeek R1).")
                    .font(.subheadline)
                    .foregroundStyle(AtlasTheme.textSecondary)

                HStack(spacing: 8) {
                    AtlasPill(title: session.runtimeHealthHeadline.uppercased())
                    if let primaryModel = session.selectedLocalAIInstallOptions.first?.modelName {
                        AtlasPill(title: primaryModel)
                    }
                }

                Text(session.localModelRuntimeDetail)
                    .font(.caption)
                    .foregroundStyle(AtlasTheme.textSecondary)

                Text("Survey progress: \(session.surveyAnswerCount)/\(session.surveyAnswersRequiredForExecution)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AtlasTheme.textPrimary)

                if session.isExecutionStreamUnlocked {
                    Text("Execution stream unlocked.")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Answer \(session.surveyAnswersRemainingForExecution) more questions to unlock execution stream.")
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.accentWarm)
                }
            }
        }
    }

    private var localAISetupPanel: some View {
        AtlasPanel(heading: "BlackHaven Is Preparing Local AI", caption: "First-launch setup for a real end-user experience") {
            VStack(alignment: .leading, spacing: 18) {
                Text("BlackHaven will install and prepare local AI directly in the app. No Terminal, no manual model commands, and no confusing runtime logs.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AtlasTheme.textPrimary)

                Text("Detected hardware: \(session.localAIHardwareSummary)")
                    .font(.subheadline)
                    .foregroundStyle(AtlasTheme.textSecondary)

                if session.shouldShowLocalRuntimeProgressUI {
                    AtlasModelRuntimeProgressStrip(
                        progress: session.localModelRuntimeProgress,
                        busy: session.localModelRuntimeIsBusy,
                        title: session.runtimeHealthHeadline,
                        sizeText: session.localModelDownloadSizeText,
                        etaText: session.localModelDownloadETAText,
                        compact: false
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose local models to install")
                        .font(.headline)
                        .foregroundStyle(AtlasTheme.textPrimary)

                    ForEach(session.localAIInstallOptions) { option in
                        Button {
                            session.toggleLocalAIInstallOption(option.id)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: session.selectedLocalAIInstallOptionIDs.contains(option.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(option.recommended ? AtlasTheme.accentWarm : AtlasTheme.textSecondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(option.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AtlasTheme.textPrimary)
                                        if option.recommended {
                                            AtlasPill(title: "RECOMMENDED")
                                        }
                                    }
                                    Text(option.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                    Text("\(option.modelName) · \(option.approximateSizeLabel)")
                                        .font(.caption2)
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(session.selectedLocalAIInstallOptionIDs.contains(option.id) ? AtlasTheme.accentWarm : AtlasTheme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Text(session.selectedLocalAIInstallSummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AtlasTheme.textPrimary)
                }

                Text(session.localModelRuntimeDetail)
                    .font(.footnote)
                    .foregroundStyle(AtlasTheme.textSecondary)

                HStack(spacing: 10) {
                    Button(session.localAIPrimaryActionTitle) {
                        session.installSelectedLocalAIModels()
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())

                    Button("Check Existing Runtime") {
                        session.retryLocalAISetup()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())

                    Button("Set Up Later") {
                        session.deferLocalAISetup()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                }

                if session.canViewRuntimeDiagnostics {
                    Text(session.runtimeEndpointReachabilityLine)
                        .font(.caption2)
                        .foregroundStyle(AtlasTheme.textSecondary)
                }
            }
        }
    }
    
    private var accountAndSafetyPanel: some View {
        AtlasPanel(heading: "System Status", caption: "Authentication and active guardrails") {
            VStack(alignment: .leading, spacing: 16) {
                // Account Info
                HStack {
                    AtlasPill(title: session.isSignedIn ? "Signed In" : "Guest")
                    AtlasPill(title: session.selectedTier.title)
                    Spacer()
                    Text(session.accountLabel)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(AtlasTheme.textSecondary)
                }
                
                if session.selectedTier == .localTrial {
                    Text("Local-first mode active. Execution runs on-device.")
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.accentWarm)
                }
                
                Divider()
                
                // Safety Guardrails
                HStack {
                    Label("Guardrails", systemImage: session.safetyModeActive ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                        .foregroundStyle(session.safetyModeActive ? AtlasTheme.accent : .green)
                    Spacer()
                    Text("Risk Score: \(session.safetyRiskScore)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AtlasTheme.textSecondary)
                }
                
                if !session.safetyInterventionSummary.isEmpty {
                    Text(session.safetyInterventionSummary)
                        .font(.subheadline)
                        .foregroundStyle(AtlasTheme.textSecondary)
                }
                
                if session.safetyModeActive {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("High-risk content is blocked from operational queueing. Proceed with constructive planning.")
                            .font(.caption)
                            .foregroundStyle(AtlasTheme.accentWarm)
                        
                        Button("Acknowledge Guidance") {
                            session.acknowledgeSafetyGuidance()
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                    }
                    .padding(12)
                    .background(AtlasTheme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var remoteControlPanel: some View {
        AtlasPanel(heading: "Desktop Remote Control", caption: "Pair iPhone or Android to make this Mac your local-first remote desktop") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Keep this Mac on and plugged in so your phone can route work, file handoff, and long-running AI tasks into your own machine instead of a cloud relay.")
                    .font(.subheadline)
                    .foregroundStyle(AtlasTheme.textPrimary)
                Text("Designed for privacy, resilience, emergency prep, and energy control. Pair BlackHaven with home backup power plus renewable generation so local AI stays available during outages and internet-down conditions. Founder recommendation: EcoFlow Delta Pro 3.")
                    .font(.caption)
                    .foregroundStyle(AtlasTheme.textSecondary)
                Text(session.remoteControlStatus)
                    .font(.subheadline)
                    .foregroundStyle(AtlasTheme.textSecondary)
                Text(session.remoteControlURL)
                    .font(.caption.monospaced())
                    .foregroundStyle(AtlasTheme.textPrimary)
                Text("Pairing token: \(session.remoteControlToken)")
                    .font(.caption.monospaced())
                    .foregroundStyle(AtlasTheme.textPrimary)
                    .textSelection(.enabled)
                Text(session.remoteControlLastAction)
                    .font(.caption)
                    .foregroundStyle(AtlasTheme.textSecondary)
            }
        }
    }
    
    private var checkInPanel: some View {
        AtlasPanel(heading: "Daily Execution Check-in", caption: "Set core signals for the orchestration loop") {
            // Native macOS Form automatically aligns labels and inputs beautifully
            Form {
                Section {
                    TextField("Daily Priority", text: $session.dailyPriority)
                    TextField("Mid-term Objective", text: $session.midTermGoal)
                    TextField("Long-term Mission", text: $session.longTermVision)
                    TextField("Current Blockers", text: $session.checkInBlockers)
                }
                
                Divider().padding(.vertical, 8)
                
                Section {
                    Stepper(value: $session.checkInEnergy, in: 1...5) {
                        Text("Energy Level: \(session.checkInEnergy)/5")
                    }
                    TextField("Mood", text: $session.checkInMood)
                    
                    Toggle("Completed Physical Training", isOn: $session.checkInWentToGymToday)
                    Toggle("Made Financial Progress", isOn: $session.checkInMadeMoneyToday)
                    
                    if session.checkInMadeMoneyToday {
                        TextField("Progress Notes", text: $session.checkInMoneySignalNote)
                    }
                }
            }
            // Forces standard control sizing rather than inheriting anything strange
            .controlSize(.regular)
            .textFieldStyle(.roundedBorder)
            .toggleStyle(.switch)
            
            HStack {
                Spacer()
                Button("Generate Execution Plan") {
                    session.applyDailyCheckIn()
                }
                .buttonStyle(AtlasPrimaryButtonStyle())
                .padding(.top, 8)
            }
        }
    }
    
    private var executionPlanPanel: some View {
        AtlasPanel(heading: "Execution Plan", caption: "Prioritized operational horizons") {
            if session.executionActions.isEmpty {
                // High-end native empty state
                ContentUnavailableView(
                    "No Plan Generated",
                    systemImage: "checklist",
                    description: Text("Run your daily check-in to generate prioritized action horizons.")
                )
                .frame(minHeight: 200)
            } else {
                VStack(spacing: 12) {
                    ForEach(session.executionActions) { action in
                        HStack(alignment: .top, spacing: 12) {
                            // A subtle indicator dot
                            Circle()
                                .fill(AtlasTheme.accentWarm)
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(action.title)
                                        .font(.headline)
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    Spacer()
                                    AtlasPill(title: action.horizon)
                                }
                                Text(action.details)
                                    .font(.subheadline)
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AtlasTheme.border, lineWidth: 0.5)
                        )
                    }
                }
            }
        }
    }

    private var executionStreamWindowPanel: some View {
        AtlasPanel(heading: "Execution Stream Window", caption: "Integrated stream now lives on Home") {
            if !session.isExecutionStreamUnlocked {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Execution stream is locked until the adaptive survey reaches \(session.surveyAnswersRequiredForExecution) answers.")
                        .font(.subheadline)
                        .foregroundStyle(AtlasTheme.textSecondary)
                    Text("Remaining: \(session.surveyAnswersRemainingForExecution)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AtlasTheme.accentWarm)
                }
            } else if session.feedItems.isEmpty {
                Text("No live stream items yet. Complete check-in and refresh feed.")
                    .font(.subheadline)
                    .foregroundStyle(AtlasTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(session.feedItems.prefix(5)) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AtlasTheme.textPrimary)
                            Text(item.summary)
                                .font(.caption)
                                .foregroundStyle(AtlasTheme.textSecondary)
                            Text("Why now: \(item.whyNow)")
                                .font(.caption2)
                                .foregroundStyle(AtlasTheme.textSecondary)
                        }
                        if item.id != session.feedItems.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var travelItineraryPanel: some View {
        AtlasPanel(heading: "Travel Itinerary Window", caption: "Your saved itinerary is visible directly on Home") {
            if session.activeTravelItineraryLocations.isEmpty {
                Text("No saved itinerary yet. Add locations in Travel Maps & Itinerary and they will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(AtlasTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(session.activeTravelItineraryDraft.title)
                        .font(.headline)
                        .foregroundStyle(AtlasTheme.textPrimary)

                    ForEach(Array(session.activeTravelItineraryLocations.enumerated()), id: \.element.id) { index, location in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AtlasTheme.accentWarm)
                                .frame(width: 26, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(location.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AtlasTheme.textPrimary)
                                Text(location.googleMapsQuery)
                                    .font(.caption)
                                    .foregroundStyle(AtlasTheme.textSecondary)
                                if !location.notes.isEmpty {
                                    Text(location.notes)
                                        .font(.caption)
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        if index != session.activeTravelItineraryLocations.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var stateAwareExecutionPanel: some View {
        AtlasPanel(heading: "State-Aware Execution", caption: "Manual-state routing, support guidance, and continuity-first planning") {
            VStack(alignment: .leading, spacing: 12) {
                if let snapshot = session.operatorStateSnapshot {
                    HStack {
                        AtlasPill(title: snapshot.mode.title.uppercased())
                        AtlasPill(title: "Energy \(snapshot.energyLevel)/5")
                        Spacer()
                        Button("Refresh Routing") {
                            session.refreshNextLayerExperience()
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                    }

                    Text(snapshot.summary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AtlasTheme.textPrimary)

                    Text("Next action: \(snapshot.nextAction)")
                        .font(.subheadline)
                        .foregroundStyle(AtlasTheme.textSecondary)

                    Text(snapshot.rationale)
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textSecondary)

                    if let blocker = snapshot.blockerSummary {
                        Text("Current blocker: \(blocker)")
                            .font(.caption)
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }
                } else {
                    Text("Run a check-in to build a state-aware execution snapshot.")
                        .font(.subheadline)
                        .foregroundStyle(AtlasTheme.textSecondary)
                }

                if let support = session.currentSupportRecommendation {
                    Divider()
                    Text(support.title)
                        .font(.headline)
                        .foregroundStyle(AtlasTheme.textPrimary)
                    Text(support.summary)
                        .font(.subheadline)
                        .foregroundStyle(AtlasTheme.textSecondary)
                    if let prompt = support.bodyDoublingPrompt {
                        Text(prompt)
                            .font(.caption)
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }
                }
            }
        }
    }

    private var checklistActivityPanel: some View {
        AtlasPanel(heading: "Checklist + Activity Hub", caption: "Interactive checklist, activity suggestion, and itinerary generation") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Button("Generate Checklist") {
                        session.generateChecklistFromCurrentContext()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())

                    Button("Activity Suggestion") {
                        session.generateActivitySuggestion()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())

                    Button("Generate Itinerary") {
                        session.generateItineraryPlan()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                }

                if let activity = session.currentActivitySuggestion {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activity.title)
                            .font(.headline)
                        Text("\(activity.durationLabel) · \(activity.summary)")
                            .font(.subheadline)
                            .foregroundStyle(AtlasTheme.textSecondary)
                        Text(activity.reason)
                            .font(.caption)
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }
                }

                if let itinerary = session.currentItineraryPlan {
                    Divider()
                    Text(itinerary.title)
                        .font(.headline)
                    ForEach(itinerary.steps) { step in
                        HStack(alignment: .top, spacing: 10) {
                            Text(step.timeLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AtlasTheme.accentWarm)
                                .frame(width: 70, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(step.summary)
                                    .font(.caption)
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                        }
                    }
                }

                if let checklist = session.activeChecklistPlan {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(checklist.title)
                                .font(.headline)
                            Text(checklist.summary)
                                .font(.caption)
                                .foregroundStyle(AtlasTheme.textSecondary)
                        }
                        Spacer()
                        Text("\(Int(checklist.completionRatio * 100))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AtlasTheme.accentWarm)
                    }

                    ForEach(checklist.steps) { step in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 10) {
                                Button {
                                    session.toggleChecklistStep(step.id)
                                } label: {
                                    Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(step.isCompleted ? .green : AtlasTheme.textSecondary)
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.title)
                                        .font(.subheadline.weight(.semibold))
                                        .strikethrough(step.isCompleted, color: .secondary)
                                    Text(step.rationale)
                                        .font(.caption)
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                    Text(step.instructions)
                                        .font(.caption)
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    if !step.externalLinks.isEmpty {
                                        Text("Links: \(step.externalLinks.joined(separator: " · "))")
                                            .font(.caption2)
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                            .textSelection(.enabled)
                                    }
                                    if !step.fileReferences.isEmpty {
                                        Text("Files: \(step.fileReferences.joined(separator: " · "))")
                                            .font(.caption2)
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                            .textSelection(.enabled)
                                    }
                                }
                            }

                            TextField(
                                "Optional notes",
                                text: Binding(
                                    get: { step.notes ?? "" },
                                    set: { session.updateChecklistStepNotes(step.id, notes: $0) }
                                ),
                                axis: .vertical
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }
    
    private var inferenceBriefPanel: some View {
        AtlasPanel(heading: "Model Inference Brief", caption: "Always-on local synthesis") {
            Text(session.commandModelBrief)
                .font(.system(.subheadline, design: .monospaced)) // Monospaced gives it a "terminal/brief" feel
                .foregroundStyle(AtlasTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var transparencyPanel: some View {
        AtlasPanel(heading: "AI Transparency", caption: "Why BlackHaven exists") {
            VStack(alignment: .leading, spacing: 12) {
                Text("BlackHaven is built for financial mobility, healthier cognitive execution, and resilient operations. This command plan is synthesized from your check-ins, surveys, notes, and workspace memory.")
                    .font(.subheadline)
                    .foregroundStyle(AtlasTheme.textSecondary)
                
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(AtlasTheme.accentWarm)
                    Text("See the AI Guide tab for full training and privacy details.")
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textPrimary)
                }
            }
        }
    }
}
