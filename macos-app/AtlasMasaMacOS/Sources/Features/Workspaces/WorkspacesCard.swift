import SwiftUI
import UniformTypeIdentifiers

struct WorkspacesCard: View {
    @EnvironmentObject private var session: SessionStore
    @FocusState private var composerFocused: Bool

    // Toggle for the right-hand metadata panel (Standard macOS pattern)
    @State private var showInspector = false
    @State private var showKnowledgeFileImporter = false

    private let maxRuntimeRetries = 3

    var body: some View {
        // Native macOS Layout: Sidebar + Main Detail View
        NavigationSplitView {
            // MARK: - LEFT PANE: Sidebar (Projects & Sessions)
            sidebarContent
                .navigationTitle("Workspaces")
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 350)
        } detail: {
            // MARK: - MAIN PANE: Active Chat Thread
            chatDetailContent
        }
        // MARK: - RIGHT PANE: Workspace Guide Inspector
        .inspector(isPresented: $showInspector) {
            inspectorContent
                .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
        }
    }

    // MARK: - Sidebar (Left Pane)
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Project Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("WORKSPACE").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Picker("Project", selection: Binding(
                    get: { session.activeWorkspaceLane },
                    set: { session.setActiveWorkspaceLane($0) }
                )) {
                    ForEach(WorkspaceLane.allCases) { lane in
                        Text(compactLaneTitle(lane)).tag(lane)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .padding(16)
            .background(.regularMaterial)

            Divider()

            // Chat Sessions List
            List(selection: Binding(
                get: { session.activeSessionID(for: session.activeWorkspaceLane) },
                set: {
                    if let id = $0 { session.activateWorkspaceSession(id) }
                }
            )) {
                Section("CHATS (\(laneSessions.count))") {
                    if laneSessions.isEmpty {
                        Text("No chats yet.").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        ForEach(laneSessions) { chat in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chat.title)
                                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                                    .lineLimit(1)
                                Text(sessionGuidePreview(for: chat))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 4)
                            .tag(chat.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            // Footer Controls
            VStack(spacing: 12) {
                // Quick suggestions for new chats
                if !laneNameSuggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(laneNameSuggestions, id: \.self) { suggestion in
                                Button(suggestion) {
                                    session.createWorkspaceSession(for: session.activeWorkspaceLane, title: suggestion)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                Button(action: { session.createWorkspaceSession(for: session.activeWorkspaceLane) }) {
                    Label("New Chat", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AtlasPrimaryButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Chat Detail (Main Pane)
    private var chatDetailContent: some View {
        VStack(spacing: 0) {
            // High-End Top Toolbar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeProjectTitle)
                        .font(.headline)
                    Text(activeChatTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                AtlasPill(title: activeRunPillTitle)

                Button {
                    showKnowledgeFileImporter = true
                } label: {
                    Label("Load Files", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Import PDFs and text files into shared workspace memory")

                Button(action: { showInspector.toggle() }) {
                    Image(systemName: "sidebar.trailing")
                        .font(.title3)
                        .foregroundStyle(showInspector ? AtlasTheme.accent : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
                .help("Toggle Workspace Guide")
            }
            .padding(16)
            .background(.regularMaterial)

            Divider()

            // Edge-to-Edge Chat Area
            ScrollViewReader { proxy in
                ScrollView {
                    if workspaceThreadItems.isEmpty {
                        emptyStateView
                    } else {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(workspaceThreadItems) { item in
                                workspaceThreadMessage(item)
                                    .id(item.id)
                            }
                        }
                        .padding(24)
                    }
                }
                .onChange(of: workspaceThreadItems.count) { _, _ in
                    if let last = workspaceThreadItems.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Native Bottom Input Area
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Message \(activeProjectTitle) workspace...", text: $session.pendingPrompt)
                    .textFieldStyle(.plain)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        sendWorkspacePrompt()
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(AtlasTheme.border, lineWidth: 1)
                    )

                Button {
                    sendWorkspacePrompt()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(trimmedPendingPrompt.isEmpty ? .secondary : AtlasTheme.accent)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedPendingPrompt.isEmpty)
            }
            .padding(16)
            .background(.regularMaterial)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .fileImporter(
            isPresented: $showKnowledgeFileImporter,
            allowedContentTypes: [.pdf, .plainText, .utf8PlainText, .text, .json, .commaSeparatedText],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                session.importKnowledgeFiles(urls: urls)
            case let .failure(error):
                session.appendOutput("Knowledge file picker failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Inspector (Right Pane)
    private var inspectorContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Workspace Guide")
                    .font(.headline)
                Spacer()
                Button(action: { showInspector = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let lanePlan = session.workspacePlans.first(where: { $0.lane == session.activeWorkspaceLane }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ACTIVE OBJECTIVE")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(lanePlan.objective)
                                .font(.subheadline)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("CURRENT TARGET")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(lanePlan.nextActionNow)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AtlasTheme.accentWarm)
                        }
                    } else {
                        Text("No active objective set for this workspace yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("KNOWLEDGE FILES")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                showKnowledgeFileImporter = true
                            } label: {
                                Label("Load", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }

                        if session.knowledgeFiles.isEmpty {
                            Text("Load PDFs or text docs once. Their content becomes shared memory across all workspace lanes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(session.knowledgeFiles.prefix(8)) { file in
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(file.fileName)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                        Text("\(file.chunkCount) context chunks · \(byteCountLabel(file.byteCount))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Text(file.preview)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        session.removeKnowledgeFile(file.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove from shared memory")
                                }
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    Divider()

                    Button("Clear Active Chat", role: .destructive) {
                        session.clearWorkspacePromptQueue()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(16)
            }
        }
        .background(.regularMaterial)
    }

    // MARK: - Subviews & Helpers

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(activeProjectTitle.uppercased(), systemImage: "folder.fill")
        } description: {
            Text("Awaiting first AI response. Start a message in this project chat and Atlas will generate responses directly in-thread.")
        }
        .padding(.top, 60)
    }

    @ViewBuilder
    private func workspaceThreadMessage(_ item: PromptQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AtlasChatBubble(text: item.prompt, isUser: true)

            if let output = item.output {
                AtlasChatBubble(text: assistantMessageText(for: output), isUser: false)
            } else if let error = item.errorMessage, !error.isEmpty {
                AtlasChatBubble(text: "Runtime notice: \(error)", isUser: false)
            } else {
                AtlasChatBubble(text: pendingAssistantStatusText(for: item), isUser: false)
            }
        }
    }

    // Original computed properties maintained perfectly
    private var workspaceThreadItems: [PromptQueueItem] {
        let lane = session.activeWorkspaceLane
        let activeSession = session.activeSessionID(for: lane)
        return session.promptQueue
            .filter { $0.workspaceLane == lane && ($0.workspaceSessionID == nil || $0.workspaceSessionID == activeSession) }
            .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
    }

    private var laneSessions: [WorkspaceNotebookSession] {
        session.sessions(for: session.activeWorkspaceLane)
    }

    private var laneNameSuggestions: [String] {
        session.workspaceNameSuggestions(for: session.activeWorkspaceLane, limit: 3)
    }

    private var activeChatID: String? {
        session.activeSessionID(for: session.activeWorkspaceLane)
    }

    private var activeChatTitle: String {
        laneSessions.first(where: { $0.id == activeChatID })?.title ?? "Primary chat"
    }

    private var activeProjectTitle: String {
        compactLaneTitle(session.activeWorkspaceLane)
    }

    private var activeRunPillTitle: String {
        let active = workspaceThreadItems.filter { $0.status == .running || $0.status == .queued }.count
        return active == 0 ? "READY" : "\(active) ACTIVE"
    }

    private var trimmedPendingPrompt: String {
        session.pendingPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendWorkspacePrompt() {
        guard !trimmedPendingPrompt.isEmpty else { return }
        composerFocused = false
        session.enqueueWorkspacePrompt()
    }

    private func assistantMessageText(for output: LocalReasoningOutput) -> String {
        "\(output.summary)\n\nNext action: \(output.nextAction)"
    }

    private func pendingAssistantStatusText(for item: PromptQueueItem) -> String {
        "Preparing your response..."
    }

    private func compactLaneTitle(_ lane: WorkspaceLane) -> String {
        switch lane {
        case .emergencyCommand:
            return "Emergency"
        case .wealthOperations:
            return "Wealth"
        case .mobilityOps:
            return "Travel"
        case .deepWork:
            return "Deep Work"
        case .innovation:
            return "Innovation"
        }
    }

    private func sessionGuidePreview(for sessionNotebook: WorkspaceNotebookSession) -> String {
        let trimmed = sessionNotebook.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "fresh session notebook." || trimmed.lowercased().hasPrefix("primary notebook for ") {
            return "Awaiting first AI response."
        }
        return String(trimmed.replacingOccurrences(of: "\n", with: " ").prefix(130))
    }

    private func byteCountLabel(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, bytes)), countStyle: .file)
    }
}
