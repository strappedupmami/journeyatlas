import SwiftUI

// MARK: - Navigation Enums
enum FeedTab: String, CaseIterable, Identifiable {
    case execution = "Execution & Tasks"
    case radar = "Market Radar & Intelligence"
    case learning = "Learning & System"
    var id: String { self.rawValue }
}

struct ProactiveFeedCard: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.openURL) private var openURL

    // UI State
    @State private var selectedTab: FeedTab = .execution
    @State private var selectedTaskID: String?

    // Original State
    @State private var completedDraftByTask: [String: String] = [:]
    @State private var incompleteDraftByTask: [String: String] = [:]
    @State private var noteDraftByTask: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            // High-End Top Toolbar & Status
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Execution Loop")
                            .font(.headline)
                        Text("Daily orchestration and mid-term intelligence")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 8) {
                            AtlasPill(title: session.selectedTier.title.uppercased())
                            AtlasPill(title: session.feedInferenceStatus)
                        }
                        Text("\(session.workspaceSessions.count) Notebooks · \(session.workspaceMemoryRecords.count) Memory Records")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Picker("Section", selection: $selectedTab) {
                        ForEach(FeedTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 500)

                    Spacer()

                    Button(action: {
                        Task { await session.refreshFeed() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh Feed")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(16)
            .background(.regularMaterial)

            Divider()

            // Main Content Routing
            ZStack {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

                switch selectedTab {
                case .execution:
                    executionTab
                case .radar:
                    radarTab
                case .learning:
                    learningTab
                }
            }
        }
    }

    // MARK: - Tab 1: Execution (Split View)
    private var executionTab: some View {
        HSplitView {
            // Left Pane: Workspaces & Tasks
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Workspaces Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ACTIVE WORKSPACES").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        if session.workspacePlans.isEmpty {
                            Text("No workspace lanes active.").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            ForEach(session.workspacePlans.prefix(3)) { workspace in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(workspace.title).font(.system(.subheadline, design: .serif).weight(.semibold))
                                        Text(workspace.nextActionNow).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(Int(workspace.confidence * 100))%").font(.caption.weight(.bold)).foregroundStyle(AtlasTheme.accentWarm)
                                }
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AtlasTheme.border, lineWidth: 1))
                            }
                        }
                    }

                    // Checklist Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("EXECUTION CHECKLIST").font(.caption.weight(.bold)).foregroundStyle(.secondary)

                        if session.feedItems.isEmpty {
                            Text("No items pending.").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            ForEach(session.feedItems) { item in
                                let state = item.checklistState
                                let isSelected = selectedTaskID == item.id

                                HStack(alignment: .top, spacing: 10) {
                                    Button {
                                        let next = !(state?.completed ?? false)
                                        Task { await session.updateExecutionTaskChecklist(taskID: item.id, completed: next, collapsed: next) }
                                    } label: {
                                        Image(systemName: (state?.completed ?? false) ? "checkmark.square.fill" : "square")
                                            .foregroundStyle((state?.completed ?? false) ? AtlasTheme.accentWarm : .secondary)
                                            .font(.title3)
                                    }
                                    .buttonStyle(.plain)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.subheadline.weight(.medium))
                                            .strikethrough(state?.completed ?? false, color: .secondary)
                                        if !isSelected {
                                            Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(isSelected ? AtlasTheme.accentWarm.opacity(0.1) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedTaskID = item.id
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .frame(minWidth: 300, idealWidth: 350, maxWidth: 450)

            // Right Pane: Task Inspector
            VStack {
                if let selectedTaskID = selectedTaskID, let item = session.feedItems.first(where: { $0.id == selectedTaskID }) {
                    taskInspector(for: item)
                } else {
                    ContentUnavailableView("No Task Selected", systemImage: "checklist", description: Text("Select a task from the execution list to view details and submit updates."))
                }
            }
            .frame(minWidth: 350, maxWidth: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    // Task Detail Inspector
    @ViewBuilder
    private func taskInspector(for item: FeedItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("TASK DETAILS").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Text(item.title).font(.system(size: 26, weight: .semibold, design: .serif))
                HStack {
                    AtlasPill(title: "Priority: \(item.priority)")
                    if let state = item.checklistState, state.completed {
                        AtlasPill(title: "COMPLETED")
                    }
                }
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Context
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Context").font(.headline)
                        Text(item.summary).font(.subheadline).foregroundStyle(.secondary)

                        Text("Why Now:").font(.subheadline.weight(.bold)).padding(.top, 4)
                        Text(item.whyNow).font(.subheadline).foregroundStyle(AtlasTheme.accentWarm)
                    }

                    Divider()

                    // Update Form
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Submit Update").font(.headline)

                        if let latest = item.checklistState?.latestResponse {
                            Text("Latest Update: \(renderLatestResponse(latest))")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(8)
                                .background(Color(nsColor: .windowBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        Form {
                            Section {
                                TextField("What did you complete?", text: completedBinding(for: item.id), axis: .vertical).lineLimit(2 ... 4)
                                TextField("What is still not done?", text: incompleteBinding(for: item.id), axis: .vertical).lineLimit(2 ... 4)
                                TextField("Note for AI adjustment", text: noteBinding(for: item.id), axis: .vertical).lineLimit(2 ... 4)
                            }
                        }
                        .formStyle(.grouped)
                        .scrollDisabled(true) // Form handles its own layout here

                        HStack(spacing: 12) {
                            Button("Send Update") { submitTaskUpdate(for: item, markCompleted: item.checklistState?.completed) }
                                .buttonStyle(AtlasSecondaryButtonStyle())
                            Spacer()
                            Button("Mark Done + Adjust") { submitTaskUpdate(for: item, markCompleted: true) }
                                .buttonStyle(AtlasPrimaryButtonStyle())
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: - Tab 2: Radar (Grid View)
    private var radarTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Job Radar
                VStack(alignment: .leading, spacing: 16) {
                    Text("GLOBAL JOB MARKET RADAR").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    if session.jobMarketOpportunities.isEmpty {
                        Text("Complete wealth/job survey signals to unlock routing.").foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)], spacing: 16) {
                            ForEach(session.jobMarketOpportunities.prefix(6)) { opportunity in
                                radarCard {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(opportunity.title).font(.system(size: 17, weight: .semibold, design: .serif))
                                        Text("\(opportunity.location) · \(opportunity.salaryBandUSD)").font(.subheadline.weight(.semibold)).foregroundStyle(AtlasTheme.accentWarm)
                                        Text("Track: \(humanizedOpportunityField(opportunity.track))").font(.caption).foregroundStyle(.secondary)
                                        Text(opportunity.remoteFriendly ? "Remote-compatible" : "On-site/hybrid").font(.caption).foregroundStyle(.secondary)

                                        HStack {
                                            ForEach(opportunity.links) { link in
                                                Button(link.platform.label) {
                                                    if let url = URL(string: link.url) { openURL(url) }
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                            }
                        }
                    }
                }

                // Research Streams
                VStack(alignment: .leading, spacing: 16) {
                    Text("RESEARCH-BACKED STREAMS").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    if session.researchStreams.isEmpty {
                        Text("Add notes/check-ins to unlock evidence-matched recommendations.").foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 350, maximum: 500), spacing: 16)], spacing: 16) {
                            ForEach(session.researchStreams) { stream in
                                radarCard {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(stream.title).font(.system(size: 17, weight: .semibold, design: .serif))
                                            Spacer()
                                            AtlasPill(title: "CONF \(Int(stream.confidence * 100))%")
                                        }
                                        Text("Action:").font(.caption.weight(.bold)).padding(.top, 4)
                                        Text(stream.executionRecommendation).font(.subheadline)
                                        Text("Evidence:").font(.caption.weight(.bold)).padding(.top, 4)
                                        Text(stream.whyItWorks).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - Tab 3: Learning & System
    private var learningTab: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 24) {
                // Learning Package
                VStack(alignment: .leading, spacing: 20) {
                    Text("ADAPTIVE LEARNING").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    if let learning = session.learningPackage {
                        AtlasPanel(heading: "Podcast Brief: \(learning.podcastTitle)", caption: "Version \(learning.version)") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(learning.podcastSummary).font(.subheadline).foregroundStyle(.secondary)
                                Divider()
                                ForEach(learning.podcastSegments) { segment in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(segment.title).font(.subheadline.weight(.semibold)).foregroundStyle(AtlasTheme.accentWarm)
                                        ForEach(segment.talkingPoints, id: \.self) { point in
                                            Text("• \(point)").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    } else {
                        AtlasPanel(heading: "Learning Mode", caption: nil) {
                            Text("Complete deeper survey/check-ins to unlock learning outputs.").foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // Feedback & Tailored Offers
                VStack(alignment: .leading, spacing: 20) {
                    Text("SYSTEM & OFFERS").font(.caption.weight(.bold)).foregroundStyle(.secondary)

                    AtlasPanel(heading: "Feedback Routing", caption: "Report friction anonymously") {
                        Form {
                            Toggle("Enable feedback offer on negative signal", isOn: $session.feedbackOfferEnabled)
                            TextField("Optional feedback draft", text: $session.pendingFeedback, axis: .vertical).lineLimit(3 ... 5)
                        }
                        .formStyle(.grouped)
                        Button("Send Report") { session.submitAnonymizedFeedback() }
                            .buttonStyle(AtlasSecondaryButtonStyle())
                    }

                    if !session.tailoredOffers.isEmpty {
                        AtlasPanel(heading: "Tailored Offers", caption: "Matched to your profile") {
                            VStack(spacing: 12) {
                                ForEach(session.tailoredOffers) { offer in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(offer.title).font(.subheadline.weight(.semibold))
                                            Spacer()
                                            AtlasPill(title: offer.type.rawValue.uppercased())
                                        }
                                        Text(offer.summary).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
    }

    // MARK: - Helpers & Subviews
    private func radarCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AtlasTheme.border, lineWidth: 1))
    }

    // Keeping original logic functions perfectly intact
    private func humanizedOpportunityField(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines).capitalized
    }

    private func completedBinding(for taskID: String) -> Binding<String> {
        Binding(get: { completedDraftByTask[taskID] ?? "" }, set: { completedDraftByTask[taskID] = $0 })
    }

    private func incompleteBinding(for taskID: String) -> Binding<String> {
        Binding(get: { incompleteDraftByTask[taskID] ?? "" }, set: { incompleteDraftByTask[taskID] = $0 })
    }

    private func noteBinding(for taskID: String) -> Binding<String> {
        Binding(get: { noteDraftByTask[taskID] ?? "" }, set: { noteDraftByTask[taskID] = $0 })
    }

    private func renderLatestResponse(_ response: FeedItemTaskResponse) -> String {
        var parts: [String] = []
        if let done = response.completedParts, !done.isEmpty { parts.append("done: \(done)") }
        if let pending = response.incompleteParts, !pending.isEmpty { parts.append("pending: \(pending)") }
        if let note = response.note, !note.isEmpty { parts.append("note: \(note)") }
        return parts.isEmpty ? "No details" : parts.joined(separator: " | ")
    }

    private func submitTaskUpdate(for item: FeedItem, markCompleted: Bool?) {
        let done = completedDraftByTask[item.id]
        let pending = incompleteDraftByTask[item.id]
        let note = noteDraftByTask[item.id]
        Task {
            await session.submitExecutionTaskResponse(taskID: item.id, completedParts: done, incompleteParts: pending, note: note, completed: markCompleted, collapsed: markCompleted == true ? true : nil)
        }
        completedDraftByTask[item.id] = ""
        incompleteDraftByTask[item.id] = ""
        noteDraftByTask[item.id] = ""
    }
}
