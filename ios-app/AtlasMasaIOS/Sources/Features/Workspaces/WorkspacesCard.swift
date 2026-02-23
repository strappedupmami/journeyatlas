import SwiftUI

struct WorkspacesCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "Research Workspaces",
            subtitle: "Operational lanes for emergency command, wealth, mobility, cognition, and innovation"
        ) {
            AtlasPanel(
                heading: "Session notebooks",
                caption: "NotebookLM-style sessions per workspace, with shared intelligence across all workspaces"
            ) {
                Picker("Workspace lane", selection: Binding(
                    get: { session.activeWorkspaceLane },
                    set: { session.setActiveWorkspaceLane($0) }
                )) {
                    ForEach(WorkspaceLane.allCases) { lane in
                        Text(lane.title).tag(lane)
                    }
                }
                .pickerStyle(.menu)
                .atlasFieldStyle()

                HStack(spacing: 10) {
                    Button("New notebook session") {
                        session.createWorkspaceSession(for: session.activeWorkspaceLane)
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())

                    Text("\(session.sessions(for: session.activeWorkspaceLane).count) sessions")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.accentWarm)
                }

                if session.sessions(for: session.activeWorkspaceLane).isEmpty {
                    Text("No sessions yet in this workspace.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(session.sessions(for: session.activeWorkspaceLane)) { notebook in
                        Button {
                            session.activateWorkspaceSession(notebook.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(notebook.title)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    Spacer()
                                    if session.activeSessionID(for: notebook.lane) == notebook.id {
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
            }

            AtlasPanel(
                heading: "Workspace orchestration",
                caption: "Built from your survey, memory, check-ins, and research-ranked execution streams"
            ) {
                if session.workspacePlans.isEmpty {
                    Text("No workspace plans yet. Complete deep survey + check-in and add at least one note.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(session.workspacePlans) { workspace in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(workspace.title)
                                    .font(.system(size: 18, weight: .semibold, design: .default))
                                    .foregroundStyle(AtlasTheme.textPrimary)
                                Spacer()
                                Text("CONF \(Int(workspace.confidence * 100))%")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(AtlasTheme.accentWarm)
                            }

                            Text(workspace.objective)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)

                            Text("Next action now: \(workspace.nextActionNow)")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(AtlasTheme.textPrimary)

                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(workspace.protocolChecklist, id: \.self) { step in
                                    Text("• \(step)")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                }
                            }

                            Text("Evidence: \(workspace.evidenceSummary)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)

                            if !workspace.sharedMemorySignals.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Shared memory signals")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    ForEach(workspace.sharedMemorySignals, id: \.self) { signal in
                                        Text("• \(signal)")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                    }
                                }
                            }

                            if !workspace.crossWorkspaceSignals.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Cross-workspace carryover")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    ForEach(workspace.crossWorkspaceSignals, id: \.self) { signal in
                                        Text("• \(signal)")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                    }
                                }
                            }

                            Text("Memory records linked: \(workspace.memoryRecordCount)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(AtlasTheme.accentWarm)

                            ForEach(workspace.citations) { citation in
                                Link(destination: URL(string: citation.sourceURL) ?? URL(string: "https://atlasmasa.com")!) {
                                    Text("Source: \(citation.title) (\(citation.year))")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(AtlasTheme.accent)
                                }
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

            AtlasPanel(
                heading: "Workspace queue",
                caption: "Queue is now an internal workspace tool for local reasoning passes"
            ) {
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

                if session.promptQueue.isEmpty {
                    Text("No queued prompts yet.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(session.promptQueue) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.prompt)
                                    .font(.system(size: 16, weight: .semibold, design: .default))
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
