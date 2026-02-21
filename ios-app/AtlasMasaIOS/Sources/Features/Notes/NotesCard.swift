import SwiftUI

struct NotesCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "Notes + Memory",
            subtitle: "Long-term personalization memory for life/work/mobility decisions"
        ) {
            AtlasPanel(heading: "Capture note", caption: "High-signal context from your real day") {
                TextField("Note title", text: $session.pendingNoteTitle)
                    .atlasFieldStyle()
                TextField("What happened, what matters, what must be acted on?", text: $session.pendingNoteContent, axis: .vertical)
                    .lineLimit(4 ... 10)
                    .atlasFieldStyle()

                HStack {
                    Button("Save note") {
                        Task { await session.saveNote() }
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())

                    Button("Reload from API") {
                        Task { await session.loadNotes() }
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                }
            }

            AtlasPanel(heading: "Memory insights", caption: "Derived profile signals currently active") {
                if session.memoryInsights.isEmpty {
                    Text("No memory insights yet.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(session.memoryInsights) { insight in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(insight.label)
                                .font(.system(size: 15, weight: .semibold, design: .serif))
                                .foregroundStyle(AtlasTheme.textPrimary)
                            Text(insight.value)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                        )
                    }
                }

                Text("Memory footprint: \(session.memoryUsageEstimate())")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.accentWarm)

                Button("Delete local memory") {
                    session.deleteLocalMemory()
                }
                .buttonStyle(AtlasSecondaryButtonStyle())
            }

            AtlasPanel(heading: "Recent notes", caption: "Last captured context") {
                if session.notes.isEmpty {
                    Text("No notes yet.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(session.notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title)
                                .font(.system(size: 16, weight: .semibold, design: .serif))
                                .foregroundStyle(AtlasTheme.textPrimary)
                            Text(note.content)
                                .foregroundStyle(AtlasTheme.textSecondary)
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
