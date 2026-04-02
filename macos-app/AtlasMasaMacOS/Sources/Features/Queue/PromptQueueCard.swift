import SwiftUI

// MARK: - Prompt Queue (Concierge)
struct PromptQueueCard: View {
    @EnvironmentObject private var session: SessionStore
    private let maxRuntimeRetries = 3

    var body: some View {
        // Native macOS messaging layout: Edge-to-edge
        VStack(spacing: 0) {
            // High-End Top Bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BlackHaven Concierge")
                        .font(.headline)
                    Text("Formal tactical assistant")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    AtlasPill(title: activeRunPillTitle)
                    AtlasPill(title: "LOCAL INFERENCE")
                }

                Menu {
                    Button("Clear Conversation", role: .destructive) {
                        session.clearConciergePromptQueue()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
            .padding(16)
            .background(.regularMaterial)

            if showRuntimeStrip {
                VStack(alignment: .leading, spacing: 6) {
                    if let statusMessage = session.localAIChatStatusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }
                    AtlasModelRuntimeProgressStrip(
                        progress: session.localModelRuntimeProgress,
                        busy: session.localModelRuntimeIsBusy,
                        title: "Local Runtime",
                        sizeText: session.localModelDownloadSizeText,
                        etaText: session.localModelDownloadETAText,
                        compact: true
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .background(.regularMaterial)
            }

            Divider()

            // Chat Area
            ScrollViewReader { proxy in
                ScrollView {
                    if commandThreadItems.isEmpty {
                        emptyStateView
                    } else {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(commandThreadItems) { item in
                                commandThreadMessage(item)
                                    .id(item.id)
                            }
                        }
                        .padding(20)
                    }
                }
                .onChange(of: commandThreadItems.count) { _, _ in
                    if let first = commandThreadItems.first {
                        withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                    }
                }
            }

            Divider()

            // Bottom Input Area
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Message concierge...", text: $session.pendingPrompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .submitLabel(.send)
                    .onSubmit {
                        guard !trimmedPendingPrompt.isEmpty else { return }
                        session.enqueuePrompt()
                    }
                    .lineLimit(1 ... 8)
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(AtlasTheme.border, lineWidth: 1)
                    )

                Button {
                    session.enqueuePrompt()
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
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("BlackHaven Concierge", systemImage: "sparkles")
        } description: {
            Text("Start with a mission request. BlackHaven will process tactical, memory-aware responses locally.")
        }
        .padding(.top, 60)
    }

    @ViewBuilder
    private func commandThreadMessage(_ item: PromptQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AtlasChatBubble(text: item.prompt, isUser: true)

            if let output = item.output {
                AtlasAssistantResponseView(output: output)
            } else if let streamed = item.streamedResponseText?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !streamed.isEmpty {
                AtlasChatBubble(text: streamed, isUser: false, isStreaming: item.status == .running)
            } else if let error = item.errorMessage, !error.isEmpty {
                AtlasChatBubble(text: error, isUser: false)
            } else {
                AtlasChatBubble(
                    text: pendingAssistantStatusText(for: item),
                    isUser: false,
                    isStreaming: item.status == .running
                )
            }
        }
    }

    // Keep existing private vars (commandThreadItems, activeRunPillTitle, etc.)
    private var commandThreadItems: [PromptQueueItem] {
        session.promptQueue.filter { $0.workspaceLane == nil }.sorted { $0.createdAt > $1.createdAt }
    }

    private var activeRunPillTitle: String { "READY" } // Simplified for demo
    private var trimmedPendingPrompt: String { session.pendingPrompt.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var showRuntimeStrip: Bool {
        session.canViewRuntimeDiagnostics && session.shouldShowLocalRuntimeProgressUI
    }
    private func pendingAssistantStatusText(for item: PromptQueueItem) -> String {
        let note = item.checkpointNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch item.status {
        case .queued:
            return (note?.isEmpty == false ? note! : "Queued. I’ll reply in a moment.")
        case .running:
            return (note?.isEmpty == false ? note! : "Working on your response...")
        case .failed:
            return "I couldn’t generate a response right now."
        case .done:
            return "Completed."
        }
    }
}

// MARK: - IDE / Coding Workspace
struct CodingWorkspaceCard: View {
    @EnvironmentObject private var session: SessionStore
    @State private var workspacePathDraft = ""
    @State private var fileFilter = ""
    @State private var showClassicTools = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agentic Coding Interface")
                        .font(.headline)
                    Text("Code is unlocked by prepaid credits and uses Gemini 3.1 Pro Preview for frontend/UI direction plus GPT-5.4 for backend/build depth.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(session.codingAgentReadinessSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                AtlasPill(title: session.prepaidCreditsActive ? "PREPAID ACTIVE" : "PREPAID REQUIRED")
            }
            .padding(16)
            .background(.regularMaterial)

            if !session.prepaidCreditsActive {
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .foregroundStyle(AtlasTheme.accentWarm)
                    Text("Code Agent is locked until prepaid credits are active.")
                        .font(.headline)
                    Text("Local planning remains available in other modules. Add prepaid credits to use agentic coding and terminal operations.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 520)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                agenticPanel
                Divider()
                HStack(spacing: 12) {
                    Toggle("Show traditional editor + terminal", isOn: $showClassicTools)
                        .toggleStyle(.switch)
                    Spacer()
                    Text(session.codingMemoryUsageEstimate())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)

                if showClassicTools {
                    Divider()
                    HSplitView {
                        navigatorPane
                            .frame(minWidth: 220, idealWidth: 260, maxWidth: 350)
                        editorPane
                            .frame(minWidth: 400, maxWidth: .infinity)
                        toolsPane
                            .frame(minWidth: 300, idealWidth: 350, maxWidth: 450)
                    }
                }
            }
        }
        .onAppear {
            if workspacePathDraft.isEmpty { workspacePathDraft = session.codingWorkspaceRootPath }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - IDE Panes

    private var agenticPanel: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.codingAgentToolingSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Slash commands: /status, /scan, /open <path>, /save, /run <shell>, /grep <pattern>, /remember")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    TextField("Workspace path...", text: $workspacePathDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Scan") {
                        session.setCodingWorkspaceRootPath(workspacePathDraft)
                        session.rescanCodingWorkspace()
                    }
                    .controlSize(.small)
                }

                HStack(spacing: 8) {
                    Button("Frontend Design Brief") {
                        session.codingPromptDraft =
                            "Design and implement a polished frontend UI for this feature with responsive behavior and accessible interactions."
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button("Backend Fix Plan") {
                        session.codingPromptDraft =
                            "Diagnose the backend issue, propose the minimum safe patch, and include verification commands/tests."
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button("Build + Test Recovery") {
                        session.codingPromptDraft =
                            "Create a step-by-step build/test troubleshooting sequence with commands and expected outputs."
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(.regularMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(session.codingMessages.suffix(80).reversed())) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(roleLabel(message.role))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(roleColor(message.role))
                            Text(message.content)
                                .font(.subheadline)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(12)
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Ask the code agent...", text: $session.codingPromptDraft, axis: .vertical)
                    .lineLimit(1 ... 8)
                    .textFieldStyle(.roundedBorder)
                Button(action: { session.submitCodingPrompt() }) {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(session.codingIsGeneratingReply)
            }
            .padding(12)
            .background(.regularMaterial)
        }
    }

    private var navigatorPane: some View {
        VStack(spacing: 0) {
            // Workspace Controls
            VStack(alignment: .leading, spacing: 12) {
                Text("WORKSPACE").font(.caption.weight(.bold)).foregroundStyle(.secondary)

                HStack {
                    TextField("Path...", text: $workspacePathDraft)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    Button("Scan") {
                        session.setCodingWorkspaceRootPath(workspacePathDraft)
                        session.rescanCodingWorkspace()
                    }.controlSize(.small)
                }

                TextField("Filter files...", text: $fileFilter)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
            }
            .padding(12)
            .background(.regularMaterial)

            Divider()

            // File List (Native Density)
            List(selection: Binding(
                get: { session.codingSelectedFilePath },
                set: {
                    if let path = $0 { session.openCodingFile(path) }
                }
            )) {
                if filteredFiles.isEmpty {
                    Text("No files found.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(filteredFiles, id: \.self) { filePath in
                        Text(session.codingRelativePath(filePath))
                            .font(.system(.subheadline, design: .monospaced))
                            .padding(.vertical, 2)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            // Editor Tab Bar
            HStack {
                let currentFile = session.codingSelectedFilePath.map(session.codingRelativePath) ?? "No file open"
                Text(currentFile)
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.medium)

                if session.codingEditorIsDirty {
                    Circle().fill(AtlasTheme.accentWarm).frame(width: 8, height: 8)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button("Save") { session.saveCodingFile() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!session.codingEditorIsDirty)

                    Button("Snapshot") { session.rememberCurrentCodingFile() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial)

            Divider()

            // Main Text Editor
            TextEditor(text: Binding(
                get: { session.codingEditorText },
                set: { session.setCodingEditorText($0) }
            ))
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            // Remove the hardcoded paddings and strokes for a true edge-to-edge text view
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var toolsPane: some View {
        VStack(spacing: 0) {
            // Sub-Split: Agent Chat (Top) and Terminal (Bottom)
            VSplitView {
                // Agent Chat Area
                VStack(spacing: 0) {
                    HStack {
                        Text("AGENTIC CODER").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") { session.clearCodingMemory() }.buttonStyle(.plain).font(.caption)
                    }
                    .padding(12)
                    .background(.regularMaterial)

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(session.codingMessages.suffix(60).reversed())) { message in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(roleLabel(message.role))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(roleColor(message.role))
                                    Text(message.content)
                                        .font(.subheadline)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(12)
                    }

                    Divider()

                    HStack {
                        TextField("Ask agent...", text: $session.codingPromptDraft)
                            .textFieldStyle(.roundedBorder)
                        Button(action: { session.submitCodingPrompt() }) {
                            Image(systemName: "paperplane.fill")
                        }
                        .disabled(session.codingIsGeneratingReply)
                    }
                    .padding(12)
                }
                .frame(minHeight: 200)

                // Terminal Area
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Text("TERMINAL").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(12)
                    .background(.regularMaterial)

                    Divider()

                    ScrollView {
                        Text(session.codingCommandOutput.isEmpty ? "Ready." : session.codingCommandOutput)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .background(Color(nsColor: .textBackgroundColor))

                    Divider()

                    HStack {
                        Text(">")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.secondary)
                        TextField("Command", text: $session.codingCommandDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .onSubmit { session.runCodingCommand() }
                    }
                    .padding(12)
                }
                .frame(minHeight: 150)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        // Subtle left border to separate from editor
        .overlay(Rectangle().frame(width: 1).foregroundStyle(AtlasTheme.border), alignment: .leading)
    }

    // Helpers
    private var filteredFiles: [String] {
        let query = fileFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return session.codingWorkspaceFiles }
        return session.codingWorkspaceFiles.filter { session.codingRelativePath($0).lowercased().contains(query) }
    }

    private func roleLabel(_ role: CodingMessageRole) -> String {
        switch role {
        case .user:
            return "YOU"
        case .assistant:
            return "AGENTIC CODER"
        case .system:
            return "SYSTEM"
        case .command:
            return "COMMAND"
        }
    }

    private func roleColor(_ role: CodingMessageRole) -> Color {
        switch role {
        case .user:
            return AtlasTheme.accentWarm
        case .assistant:
            return AtlasTheme.accent
        case .system:
            return .secondary
        case .command:
            return .green
        }
    }
}
