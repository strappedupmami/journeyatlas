import SwiftUI

struct ProactiveFeedCard: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.openURL) private var openURL

    @State private var selectedOpportunityID: String?
    @State private var planSourcePresented = false
    @State private var workspaceLanesPresented = false
    @State private var streamChatsPresented = false
    @State private var completedDraftByTask: [String: String] = [:]
    @State private var incompleteDraftByTask: [String: String] = [:]
    @State private var noteDraftByTask: [String: String] = [:]

    var body: some View {
        ZStack {
            AtlasTheme.backgroundGradient
                .ignoresSafeArea()
            AtlasTheme.glowGradient
                .ignoresSafeArea()
            AtlasTheme.ambientGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    executionStreamPanel
                    proactiveOutputsPanel
                    if session.isJobRadarReady {
                        jobRadarPanel
                    } else {
                        surveyUnlockPanel
                    }
                    tailoredOffersPanel
                    researchPanel
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
        }
        .safeAreaInset(edge: .top) {
            executionHeader
        }
        .sheet(isPresented: $planSourcePresented) {
            NavigationStack {
                PlanSourceCard()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                planSourcePresented = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $workspaceLanesPresented) {
            workspaceLanesSheet
        }
        .sheet(isPresented: $streamChatsPresented) {
            streamChatsSheet
        }
        .onAppear {
            if selectedOpportunityID == nil {
                selectedOpportunityID = session.jobMarketOpportunities.first?.id
            }
        }
        .onChange(of: session.jobMarketOpportunities.map(\.id)) { _, ids in
            if ids.contains(selectedOpportunityID ?? "") { return }
            selectedOpportunityID = ids.first
        }
    }

    private var executionHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Execution Loop")
                    .font(AtlasTheme.brandDisplayFont(size: 27))
                    .tracking(0.4)
                    .foregroundStyle(AtlasTheme.textPrimary)
                Text(laneLabel(selectedLane))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.textSecondary)
            }

            Spacer()

            AtlasPill(title: session.inferenceSettingsSnapshot().model.uppercased())

            Menu {
                Button("Plan source") {
                    planSourcePresented = true
                }
                Button("Workspace lanes") {
                    workspaceLanesPresented = true
                }
                Button("Projects & chats") {
                    streamChatsPresented = true
                }
                Button("Refresh execution feed") {
                    Task { await session.refreshFeed() }
                }

                Divider()

                ForEach(WorkspaceLane.allCases) { lane in
                    Button {
                        session.executionSelectedLane = lane
                        session.setActiveWorkspaceLane(lane)
                    } label: {
                        if lane == selectedLane {
                            Label(laneLabel(lane), systemImage: "checkmark")
                        } else {
                            Text(laneLabel(lane))
                        }
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AtlasTheme.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(AtlasTheme.cardStrong)
                    )
                    .overlay(
                        Circle()
                            .stroke(AtlasTheme.border, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 11)
        .padding(.bottom, 9)
        .background(
            ZStack {
                AtlasTheme.chromeSurface
                AtlasTheme.chromeGradient
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AtlasTheme.chromeEdge)
                    .frame(height: 1)
            }
            .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
        )
    }

    private var executionStreamPanel: some View {
        AtlasPanel(
            heading: "Lane-matched stream",
            caption: "Execution output aligned to selected workspace lane"
        ) {
            HStack(spacing: 8) {
                AtlasPill(title: laneLabel(selectedLane).uppercased())
                AtlasPill(title: "\(laneActions.count) ACTIONS")
                AtlasPill(title: "\(laneFeed.count) OUTPUTS")
            }

            if let lanePlan {
                Text(lanePlan.nextActionNow)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.textPrimary)
                Text(lanePlan.objective)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.textSecondary)
            }

            if let firstAction = laneActions.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick execution quiz")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AtlasTheme.accentWarm)
                    Text("What should Atlas do next for this lane?")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.textSecondary)

                    HStack(spacing: 8) {
                        Button("Coach me") {
                            queueLanePrompt("Coach me through this lane action: \(firstAction.details)", outputType: .quiz)
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())

                        Button("Queue in chat") {
                            queueLanePrompt("Run this lane action as tactical output: \(firstAction.details)", outputType: .standard)
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                    }
                }
            }
        }
    }

    private var proactiveOutputsPanel: some View {
        AtlasPanel(heading: "Execution checklists", caption: "Check/uncheck tasks, collapse completed cards, and send done/not-done updates") {
            if checklistItems.isEmpty {
                Text("No execution items yet. Refresh feed or complete more survey depth.")
                    .foregroundStyle(AtlasTheme.textSecondary)
            } else {
                ForEach(checklistItems) { item in
                    let state = item.checklistState
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                let next = !(state?.completed ?? false)
                                Task { await session.updateExecutionTaskChecklist(taskID: item.id, completed: next, collapsed: next) }
                            } label: {
                                Image(systemName: (state?.completed ?? false) ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle((state?.completed ?? false) ? AtlasTheme.accentWarm : AtlasTheme.textSecondary)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.system(size: 16, weight: .semibold, design: .default))
                                    .foregroundStyle(AtlasTheme.textPrimary)
                                    .strikethrough(state?.completed ?? false, color: AtlasTheme.textSecondary)
                                Text("Priority: \(item.priority)")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                            Spacer()

                            if state?.completed == true {
                                Button((state?.collapsed ?? false) ? "Expand" : "Collapse") {
                                    Task {
                                        await session.updateExecutionTaskChecklist(
                                            taskID: item.id,
                                            completed: true,
                                            collapsed: !(state?.collapsed ?? false)
                                        )
                                    }
                                }
                                .buttonStyle(AtlasSecondaryButtonStyle())
                            }
                        }

                        if state?.collapsed != true {
                            Text(item.summary)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)
                            Text("Why now: \(item.whyNow)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AtlasTheme.accentWarm)

                            if let latest = state?.latestResponse {
                                Text("Latest update: \(renderLatestResponse(latest))")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                TextField("What did you complete?", text: completedBinding(for: item.id), axis: .vertical)
                                    .lineLimit(1 ... 3)
                                    .atlasFieldStyle()
                                TextField("What is still not done?", text: incompleteBinding(for: item.id), axis: .vertical)
                                    .lineLimit(1 ... 3)
                                    .atlasFieldStyle()
                                TextField("Optional note for AI adjustment", text: noteBinding(for: item.id), axis: .vertical)
                                    .lineLimit(1 ... 3)
                                    .atlasFieldStyle()

                                HStack(spacing: 8) {
                                    Button("Send task update") {
                                        submitTaskUpdate(for: item, markCompleted: state?.completed)
                                    }
                                    .buttonStyle(AtlasSecondaryButtonStyle())

                                    Button("Done + adjust") {
                                        submitTaskUpdate(for: item, markCompleted: true)
                                    }
                                    .buttonStyle(AtlasPrimaryButtonStyle())
                                }
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

    private var jobRadarPanel: some View {
        AtlasPanel(
            heading: "Global job market radar",
            caption: "Interactive role routing tied to memory and survey signals"
        ) {
            if session.jobMarketOpportunities.isEmpty {
                Text("No opportunities yet. Refresh survey/check-in signals and try again.")
                    .foregroundStyle(AtlasTheme.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(session.jobMarketOpportunities.prefix(6)) { opportunity in
                            Button(opportunity.title) {
                                selectedOpportunityID = opportunity.id
                            }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(opportunity.id == selectedOpportunityID ? AtlasTheme.cardStrong : Color.black.opacity(0.2))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(opportunity.id == selectedOpportunityID ? AtlasTheme.accentWarm : AtlasTheme.border, lineWidth: 1)
                            )
                            .foregroundStyle(AtlasTheme.textPrimary)
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let selectedOpportunity {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectedOpportunity.title)
                            .font(.system(size: 18, weight: .semibold, design: .default))
                            .foregroundStyle(AtlasTheme.textPrimary)
                        Text("\(selectedOpportunity.location) · \(selectedOpportunity.salaryBandUSD)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(AtlasTheme.accentWarm)

                        Text(session.jobNarrative(for: selectedOpportunity))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AtlasTheme.textSecondary)

                        radarChecklist(
                            title: "How to become technically capable",
                            items: selectedOpportunity.capabilityPath
                        )
                        radarChecklist(
                            title: "Why this role now",
                            items: selectedOpportunity.whyHighlights + selectedOpportunity.benefitsHighlights
                        )

                        HStack(spacing: 8) {
                            ForEach(selectedOpportunity.links) { link in
                                Button(link.platform.label) {
                                    guard let url = URL(string: link.url) else { return }
                                    openURL(url)
                                }
                                .buttonStyle(AtlasSecondaryButtonStyle())
                            }
                        }

                        HStack(spacing: 8) {
                            Button("Quiz me") {
                                queueLanePrompt(
                                    "Create a concise interview prep quiz for \(selectedOpportunity.title) focused on technical capability gaps.",
                                    outputType: .quiz
                                )
                            }
                            .buttonStyle(AtlasSecondaryButtonStyle())

                            Button("Open in concierge") {
                                queueConciergeStarterForOpportunity(selectedOpportunity)
                            }
                            .buttonStyle(AtlasPrimaryButtonStyle())
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.2))
                    )
                }
            }
        }
    }

    private var surveyUnlockPanel: some View {
        AtlasPanel(
            heading: "Career calibration",
            caption: "Finish survey to unlock memory-personalized job radar"
        ) {
            Text("Radar unlock progress: \(session.surveyCompletionPercent)%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AtlasTheme.accentWarm)
            Text("Complete the primary survey first, then Atlas will preload job opportunities into concierge and workspace chats.")
                .foregroundStyle(AtlasTheme.textSecondary)
            Button("Continue survey") {
                session.openSurveyTabRequested = true
            }
            .buttonStyle(AtlasPrimaryButtonStyle())
        }
    }

    private func radarChecklist(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AtlasTheme.textPrimary)
            ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { index, item in
                Text("\(index + 1). \(item)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.textSecondary)
            }
        }
    }

    private var tailoredOffersPanel: some View {
        AtlasPanel(heading: "Tailored offers", caption: "Memory-aware recommendations in concise cards") {
            if session.tailoredOffers.isEmpty {
                Text("Complete survey/check-in to unlock tailored offers.")
                    .foregroundStyle(AtlasTheme.textSecondary)
            } else {
                ForEach(session.tailoredOffers.prefix(3)) { offer in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(offer.title)
                            .font(.system(size: 15, weight: .semibold, design: .default))
                            .foregroundStyle(AtlasTheme.textPrimary)
                        Text(offer.summary)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AtlasTheme.textSecondary)
                        Text("Next: \(offer.callToAction)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AtlasTheme.accentWarm)
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

    private var researchPanel: some View {
        AtlasPanel(heading: "Research streams", caption: "Evidence-grounded lane recommendations") {
            if laneResearchStreams.isEmpty {
                Text("No lane-matched research stream yet.")
                    .foregroundStyle(AtlasTheme.textSecondary)
            } else {
                ForEach(laneResearchStreams.prefix(3)) { stream in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(stream.title)
                            .font(.system(size: 15, weight: .semibold, design: .default))
                            .foregroundStyle(AtlasTheme.textPrimary)
                        Text(stream.executionRecommendation)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AtlasTheme.textSecondary)
                        Text("CONF \(Int(stream.confidence * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(AtlasTheme.accentWarm)
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

    private var workspaceLanesSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Workspace lanes")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(AtlasTheme.textPrimary)
                        Spacer()
                        Button("Done") {
                            workspaceLanesPresented = false
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                    }

                    ForEach(session.workspacePlans) { plan in
                        Button {
                            session.executionSelectedLane = plan.lane
                            session.setActiveWorkspaceLane(plan.lane)
                            workspaceLanesPresented = false
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(plan.title)
                                        .font(.system(size: 16, weight: .semibold, design: .default))
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    Spacer()
                                    Text("\(Int(plan.confidence * 100))%")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(AtlasTheme.accentWarm)
                                }
                                Text(plan.nextActionNow)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black.opacity(0.2))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(AtlasTheme.backgroundGradient.ignoresSafeArea())
        }
    }

    private var streamChatsSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Projects & chats")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AtlasTheme.textPrimary)
                    Spacer()
                    Button("Done") {
                        streamChatsPresented = false
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                }

                Button("New chat") {
                    session.createWorkspaceSession(for: selectedLane)
                }
                .buttonStyle(AtlasPrimaryButtonStyle())

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(session.sessions(for: selectedLane)) { notebook in
                            Button {
                                session.activateWorkspaceSession(notebook.id)
                                streamChatsPresented = false
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(notebook.title)
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(AtlasTheme.textPrimary)
                                        Spacer()
                                        if notebook.id == session.activeSessionID(for: selectedLane) {
                                            AtlasPill(title: "ACTIVE")
                                        }
                                    }
                                    Text(notebook.summary)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.black.opacity(0.2))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(AtlasTheme.backgroundGradient.ignoresSafeArea())
        }
    }

    private var selectedLane: WorkspaceLane {
        session.executionSelectedLane
    }

    private var lanePlan: WorkspacePlan? {
        session.workspacePlans.first(where: { $0.lane == selectedLane })
    }

    private var laneActions: [ExecutionAction] {
        session.executionActions(for: selectedLane)
    }

    private var laneFeed: [FeedItem] {
        session.feedItems(for: selectedLane)
    }

    private var checklistItems: [FeedItem] {
        session.feedItems
    }

    private var laneResearchStreams: [ResearchExecutionStream] {
        session.researchStreams.filter { laneForDomain($0.domain) == selectedLane }
    }

    private func completedBinding(for taskID: String) -> Binding<String> {
        Binding(
            get: { completedDraftByTask[taskID] ?? "" },
            set: { completedDraftByTask[taskID] = $0 }
        )
    }

    private func incompleteBinding(for taskID: String) -> Binding<String> {
        Binding(
            get: { incompleteDraftByTask[taskID] ?? "" },
            set: { incompleteDraftByTask[taskID] = $0 }
        )
    }

    private func noteBinding(for taskID: String) -> Binding<String> {
        Binding(
            get: { noteDraftByTask[taskID] ?? "" },
            set: { noteDraftByTask[taskID] = $0 }
        )
    }

    private func renderLatestResponse(_ response: FeedItemTaskResponse) -> String {
        var parts: [String] = []
        if let done = response.completedParts, !done.isEmpty {
            parts.append("done: \(done)")
        }
        if let pending = response.incompleteParts, !pending.isEmpty {
            parts.append("pending: \(pending)")
        }
        if let note = response.note, !note.isEmpty {
            parts.append("note: \(note)")
        }
        return parts.isEmpty ? "No details" : parts.joined(separator: " | ")
    }

    private func submitTaskUpdate(for item: FeedItem, markCompleted: Bool?) {
        let done = completedDraftByTask[item.id]
        let pending = incompleteDraftByTask[item.id]
        let note = noteDraftByTask[item.id]
        Task {
            await session.submitExecutionTaskResponse(
                taskID: item.id,
                completedParts: done,
                incompleteParts: pending,
                note: note,
                completed: markCompleted,
                collapsed: markCompleted == true ? true : nil
            )
        }
        completedDraftByTask[item.id] = ""
        incompleteDraftByTask[item.id] = ""
        noteDraftByTask[item.id] = ""
    }

    private var selectedOpportunity: JobOpportunity? {
        guard let selectedOpportunityID else {
            return session.jobMarketOpportunities.first
        }
        return session.jobMarketOpportunities.first(where: { $0.id == selectedOpportunityID })
            ?? session.jobMarketOpportunities.first
    }

    private func laneForDomain(_ domain: String) -> WorkspaceLane {
        switch domain {
        case "emergency-response", "emergency-preparedness", "emergency-management", "crisis-management", "crisis-planning", "incident-command":
            return .emergencyCommand
        case "wealth":
            return .wealthOperations
        case "travel", "mobility", "operations", "safety", "resilience":
            return .mobilityOps
        case "technology-innovation", "systems-innovation", "digital-innovation", "physical-innovation", "innovation":
            return .innovation
        default:
            return .deepWork
        }
    }

    private func laneLabel(_ lane: WorkspaceLane) -> String {
        switch lane {
        case .emergencyCommand:
            return "Emergency"
        case .wealthOperations:
            return "Wealth"
        case .mobilityOps:
            return "Mobility"
        case .deepWork:
            return "Cognitive"
        case .innovation:
            return "Innovation"
        }
    }

    private func queueLanePrompt(_ prompt: String, outputType: PromptOutputType) {
        session.pendingPrompt = prompt
        if selectedLane == session.activeWorkspaceLane {
            session.enqueueWorkspacePrompt(outputType: outputType)
        } else {
            session.enqueuePrompt(outputType: outputType)
        }
    }

    private func queueConciergeStarterForOpportunity(_ opportunity: JobOpportunity) {
        session.pendingPrompt = "Create a concise plan for pursuing \(opportunity.title) in \(opportunity.location). Focus on technical capability path, why this role fits my profile, and first 7 execution steps."
        session.enqueuePrompt(outputType: .standard)
    }
}

struct PlanSourceCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "Plan source",
            subtitle: "Tier-aware orchestration and model routing"
        ) {
            AtlasPanel(heading: "Source graph", caption: "What powers your plans") {
                Text("Active tier: \(session.selectedTier.title)")
                    .foregroundStyle(AtlasTheme.textPrimary)
                Text(session.selectedTier.subtitle)
                    .foregroundStyle(AtlasTheme.textSecondary)
                Text("Data graph: \(session.workspaceSessions.count) chats · \(session.workspaceMemoryRecords.count) memory records · \(session.surveyAnswerCount) survey answers")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.accentWarm)
                Text("Inference status: \(session.feedInferenceStatus)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.textSecondary)
            }

            AtlasPanel(heading: "Model route", caption: "Gemini-first runtime") {
                let snapshot = session.inferenceSettingsSnapshot()
                Text("Provider: \(snapshot.providerID.uppercased())")
                    .foregroundStyle(AtlasTheme.textPrimary)
                Text("Model: \(snapshot.model)")
                    .foregroundStyle(AtlasTheme.textPrimary)
                Text(snapshot.statusLine)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.textSecondary)
            }

            AtlasPanel(heading: "Calibration", caption: "Survey and memory depth") {
                Text("Survey completion: \(session.surveyCompletionPercent)%")
                    .foregroundStyle(AtlasTheme.textPrimary)
                Text(session.isPrimarySurveyComplete ? "Primary survey completed." : "Primary survey still in progress.")
                    .foregroundStyle(session.isPrimarySurveyComplete ? AtlasTheme.accentWarm : AtlasTheme.textSecondary)
                if !session.isModelAutofillUnlocked {
                    Text("AI autofill unlock: \(session.modelAutofillMinimumSurveyAnswers) survey answers (\(session.modelAutofillSurveyAnswersRemaining) remaining).")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.accentWarm)
                }
            }
        }
    }
}
