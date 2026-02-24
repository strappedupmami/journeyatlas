import SwiftUI

struct PromptQueueCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "Prompt Queue",
            subtitle: "Queue prompts and run local reasoning in managed background passes"
        ) {
            AtlasPanel(heading: "How queued reasoning works", caption: "Local processing model + purpose") {
                Text("Queued prompts are processed by Atlas local reasoning workers to produce execution-focused outputs. The queue is part of the app's practical mission: keep users moving forward on money, health, and operations under real constraints.")
                    .foregroundStyle(AtlasTheme.textSecondary)
                Text("Open AI Guide for full details on training domains, system limits, and personalization behavior.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.accentWarm)
            }

            AtlasPanel(heading: "Queue controls", caption: "Designed for on-the-go execution under limited attention") {
                TextField("Write a prompt for local reasoning", text: $session.pendingPrompt, axis: .vertical)
                    .lineLimit(3 ... 8)
                    .atlasFieldStyle()

                HStack {
                    Button("Add to queue") {
                        session.enqueuePrompt()
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())

                    Button("Run worker") {
                        session.startPromptQueueWorker()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())

                    Button("Clear") {
                        session.clearPromptQueue()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                }
            }

            AtlasPanel(heading: "Queued jobs", caption: "Local-only reasoning outputs with next-action recommendations") {
                if session.promptQueue.isEmpty {
                    Text("No queued prompts yet.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(session.promptQueue) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.prompt)
                                    .font(.system(size: 16, weight: .semibold, design: .serif))
                                    .foregroundStyle(AtlasTheme.textPrimary)
                                Spacer()
                                Text(item.status.rawValue.uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(AtlasTheme.accentWarm)
                            }

                            if let output = item.output {
                                Text("Summary: \(output.summary)")
                                    .foregroundStyle(AtlasTheme.textSecondary)
                                Text("Next action: \(output.nextAction)")
                                    .foregroundStyle(AtlasTheme.textPrimary)
                            }

                            if let error = item.errorMessage {
                                Text(error)
                                    .foregroundStyle(.orange)
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
}

struct CodingWorkspaceCard: View {
    @EnvironmentObject private var session: SessionStore
    @State private var workspacePathDraft = ""
    @State private var fileFilter = ""

    var body: some View {
        AtlasScreen(
            title: "Coding Workspace",
            subtitle: "Codex-style local workspace: files, prompts, commands, and persistent on-device memory"
        ) {
            AtlasPanel(
                heading: "Workspace root",
                caption: "Set project path, index files locally, and keep context on this device"
            ) {
                HStack(spacing: 10) {
                    TextField("/Users/.../project", text: $workspacePathDraft)
                        .atlasFieldStyle()

                    Button("Set") {
                        session.setCodingWorkspaceRootPath(workspacePathDraft)
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())

                    Button("Scan") {
                        session.setCodingWorkspaceRootPath(workspacePathDraft)
                        session.rescanCodingWorkspace()
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())
                }

                HStack(spacing: 8) {
                    AtlasPill(title: "\(session.codingWorkspaceFiles.count) files")
                    AtlasPill(title: "\(session.codingMessages.count) messages")
                    AtlasPill(title: "\(session.codingMemoryRecords.count) memory records")
                }

                if !session.codingWorkspaceRootPath.isEmpty {
                    Text("Active root: \(session.codingWorkspaceRootPath)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.textSecondary)
                }

                Text("Model inference is default and always-on for local coding responses.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.accentWarm)
            }

            AtlasPanel(
                heading: "Navigator and editor",
                caption: "Browse indexed files and edit the active file directly"
            ) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Filter files", text: $fileFilter)
                            .atlasFieldStyle()

                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                if filteredFiles.isEmpty {
                                    Text("No files found. Scan workspace or adjust filter.")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                } else {
                                    ForEach(filteredFiles, id: \.self) { filePath in
                                        Button {
                                            session.openCodingFile(filePath)
                                        } label: {
                                            CodingFileRow(
                                                title: session.codingRelativePath(filePath),
                                                isSelected: session.codingSelectedFilePath == filePath
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .frame(minWidth: 280, maxWidth: 360)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(session.codingSelectedFilePath.map(session.codingRelativePath) ?? "No file open")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(AtlasTheme.textPrimary)
                            if session.codingEditorIsDirty {
                                AtlasPill(title: "UNSAVED")
                            }
                            Spacer()
                        }

                        TextEditor(
                            text: Binding(
                                get: { session.codingEditorText },
                                set: { session.setCodingEditorText($0) }
                            )
                        )
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .padding(10)
                        .frame(minHeight: 360)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.22))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AtlasTheme.border, lineWidth: 1)
                        )

                        HStack(spacing: 10) {
                            Button("Save file") {
                                session.saveCodingFile()
                            }
                            .buttonStyle(AtlasPrimaryButtonStyle())

                            Button("Reload file") {
                                if let path = session.codingSelectedFilePath {
                                    session.openCodingFile(path)
                                }
                            }
                            .buttonStyle(AtlasSecondaryButtonStyle())

                            Button("Remember snapshot") {
                                session.rememberCurrentCodingFile()
                            }
                            .buttonStyle(AtlasSecondaryButtonStyle())
                        }
                    }
                }
                .frame(minHeight: 420)
            }

            AtlasPanel(
                heading: "Local agent and terminal",
                caption: "Send prompts to local reasoning and run shell commands in the workspace root"
            ) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                if session.codingMessages.isEmpty {
                                    Text("No coding conversation yet. Try: /help or ask for a code plan.")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                } else {
                                    ForEach(Array(session.codingMessages.suffix(60).reversed())) { message in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(roleLabel(message.role))
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .foregroundStyle(roleColor(message.role))
                                            Text(message.content)
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                                .foregroundStyle(AtlasTheme.textPrimary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.black.opacity(0.2))
                                        )
                                    }
                                }
                            }
                        }

                        TextField("Ask local coding agent (or /help)", text: $session.codingPromptDraft, axis: .vertical)
                            .lineLimit(2 ... 7)
                            .atlasFieldStyle()

                        HStack(spacing: 10) {
                            Button(session.codingIsGeneratingReply ? "Thinking..." : "Send local prompt") {
                                session.submitCodingPrompt()
                            }
                            .buttonStyle(AtlasPrimaryButtonStyle())
                            .disabled(session.codingIsGeneratingReply)

                            Button("Clear chat memory") {
                                session.clearCodingMemory()
                            }
                            .buttonStyle(AtlasSecondaryButtonStyle())
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Shell command", text: $session.codingCommandDraft)
                            .atlasFieldStyle()

                        HStack(spacing: 10) {
                            Button(session.codingIsRunningCommand ? "Running..." : "Run command") {
                                session.runCodingCommand()
                            }
                            .buttonStyle(AtlasPrimaryButtonStyle())
                            .disabled(session.codingIsRunningCommand)

                            Button("Clear output") {
                                session.codingCommandOutput = ""
                            }
                            .buttonStyle(AtlasSecondaryButtonStyle())
                        }

                        ScrollView {
                            Text(session.codingCommandOutput.isEmpty ? "No command output yet." : session.codingCommandOutput)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(AtlasTheme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .frame(minHeight: 220)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.22))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AtlasTheme.border, lineWidth: 1)
                        )
                    }
                    .frame(minWidth: 320, maxWidth: 420)
                }
                .frame(minHeight: 380)
            }

            AtlasPanel(
                heading: "Memory bank",
                caption: "Append-only local coding memory (limited by your device storage and RAM)"
            ) {
                Text(session.codingMemoryUsageEstimate())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.accentWarm)

                if session.codingMemoryRecords.isEmpty {
                    Text("No coding memory records yet.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(Array(session.codingMemoryRecords.suffix(12).reversed())) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.summary)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(AtlasTheme.textPrimary)
                            Text(record.detail)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)
                                .lineLimit(3)
                            if let path = record.relatedFilePath {
                                Text(session.codingRelativePath(path))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(AtlasTheme.accentWarm)
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
        .onAppear {
            if workspacePathDraft.isEmpty {
                workspacePathDraft = session.codingWorkspaceRootPath
            }
        }
    }

    private var filteredFiles: [String] {
        let query = fileFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return session.codingWorkspaceFiles }
        return session.codingWorkspaceFiles.filter { filePath in
            session.codingRelativePath(filePath).lowercased().contains(query)
        }
    }

    private func roleLabel(_ role: CodingMessageRole) -> String {
        switch role {
        case .user: return "YOU"
        case .assistant: return "LOCAL AGENT"
        case .system: return "SYSTEM"
        case .command: return "COMMAND"
        }
    }

    private func roleColor(_ role: CodingMessageRole) -> Color {
        switch role {
        case .user: return AtlasTheme.accentWarm
        case .assistant: return AtlasTheme.accent
        case .system: return AtlasTheme.textSecondary
        case .command: return Color.green.opacity(0.9)
        }
    }
}

private struct CodingFileRow: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(AtlasTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AtlasTheme.cardStrong : Color.black.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? AtlasTheme.accentWarm : AtlasTheme.border, lineWidth: 1)
            )
    }
}
