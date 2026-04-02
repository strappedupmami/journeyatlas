import SwiftUI

struct NotesCard: View {
    @EnvironmentObject private var session: SessionStore

    // UI State for native macOS layout
    @State private var selectedNoteID: String?
    @State private var showInsightsInspector = false

    var body: some View {
        NavigationSplitView {
            // MARK: - LEFT PANE: Notes History Sidebar
            notesSidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 350)
        } detail: {
            // MARK: - MAIN PANE: Editor / Viewer
            mainEditorContent
        }
        // MARK: - RIGHT PANE: Memory Insights Inspector
        .inspector(isPresented: $showInsightsInspector) {
            insightsInspector
                .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
        }
    }

    // MARK: - Left Pane: Sidebar
    private var notesSidebar: some View {
        VStack(spacing: 0) {
            // Sidebar Header
            HStack {
                Text("MEMORY BANK")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await session.loadNotes() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Reload notes from API")
            }
            .padding(16)
            .background(.regularMaterial)

            Divider()

            // Notes List
            List(selection: $selectedNoteID) {
                // "New Note" Draft Option
                Section {
                    Text("Draft: New Note")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AtlasTheme.accentWarm)
                        .padding(.vertical, 4)
                        .tag(String?.none) // Selects nil to show the composer
                }

                // Historical Notes
                Section("RECENT NOTES") {
                    if session.notes.isEmpty {
                        Text("No notes yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.notes) { note in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.title)
                                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                                    .lineLimit(1)
                                Text(note.content)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 4)
                            .tag(String?(note.id))
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            // Footer Action
            VStack {
                Button {
                    selectedNoteID = nil // Switch to draft mode
                } label: {
                    Label("Compose Note", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AtlasPrimaryButtonStyle())
                .padding(16)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    // MARK: - Main Pane: Note Editor / Viewer
    private var mainEditorContent: some View {
        VStack(spacing: 0) {
            // High-End Top Toolbar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedNoteID == nil ? "New Note" : "Past Note")
                        .font(.headline)
                    Text(selectedNoteID == nil ? "High-signal context capture" : "Historical context")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // System Status & Inspector Toggle
                HStack(spacing: 16) {
                    Toggle("Memory Active", isOn: Binding(
                        get: { session.memoryCollectionEnabled },
                        set: { session.setMemoryCollectionEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Button {
                        showInsightsInspector.toggle()
                    } label: {
                        Image(systemName: "brain.head.profile")
                            .font(.title3)
                            .foregroundStyle(showInsightsInspector ? AtlasTheme.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Memory Insights")
                }
            }
            .padding(16)
            .background(.regularMaterial)

            Divider()

            // Edge-to-Edge Canvas Area
            if let selectedNoteID = selectedNoteID, let note = session.notes.first(where: { $0.id == selectedNoteID }) {
                // Read-Only View for Past Notes
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(note.title)
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .foregroundStyle(AtlasTheme.textPrimary)

                        Text(note.content)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(AtlasTheme.textSecondary)
                            .lineSpacing(6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(32)
                }
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                // Active Composer for New Notes
                VStack(spacing: 0) {
                    TextField("Note title", text: $session.pendingNoteTitle)
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 32)
                        .padding(.top, 32)
                        .padding(.bottom, 16)

                    TextEditor(text: $session.pendingNoteContent)
                        .font(.system(size: 15, weight: .regular))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 28) // Slight offset due to TextEditor native padding

                    HStack {
                        Spacer()
                        Button("Save Note") {
                            Task {
                                await session.saveNote()
                                // Optionally clear selection to stay on the newly created empty draft
                                selectedNoteID = nil
                            }
                        }
                        .buttonStyle(AtlasPrimaryButtonStyle())
                        .disabled(!session.memoryCollectionEnabled || session.pendingNoteTitle.isEmpty)
                        .padding(20)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    // MARK: - Right Pane: Memory Insights Inspector
    private var insightsInspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Memory Insights")
                    .font(.headline)
                Spacer()
                Button {
                    showInsightsInspector = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Footprint & Controls
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SYSTEM FOOTPRINT")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        Text(session.memoryUsageEstimate())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AtlasTheme.accentWarm)

                        Text(session.memoryVaultStatusLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(session.memoryVaultPolicyLine)
                            .font(.caption)
                            .foregroundStyle(AtlasTheme.accentWarm)

                        TextField("Recall local raw memory", text: $session.memoryVaultRecallQuery)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 10) {
                            Button("Compact Further") {
                                session.compactMemoryVault()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Deep Archive") {
                                session.deepArchiveMemoryVault()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Recall Raw Memory") {
                                session.recallMemoryVault()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        if !session.memoryVaultRecallResults.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(session.memoryVaultRecallResults) { hit in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(hit.summary)
                                            .font(.caption.weight(.semibold))
                                        Text("\(hit.sourceLabel) · \(hit.timestamp) · \(hit.matchReason)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AtlasTheme.border, lineWidth: 1))
                                }
                            }
                        }

                        Button("Delete Local Memory", role: .destructive) {
                            session.deleteLocalMemory()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 4)
                    }

                    Divider()

                    // Derived Signals
                    VStack(alignment: .leading, spacing: 12) {
                        Text("DERIVED SIGNALS")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        if session.memoryInsights.isEmpty {
                            Text("No memory insights yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(session.memoryInsights) { insight in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(insight.label)
                                        .font(.system(.subheadline, design: .serif).weight(.semibold))
                                    Text(insight.value)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AtlasTheme.border, lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(.regularMaterial)
    }
}
