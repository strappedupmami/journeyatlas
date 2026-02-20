import SwiftUI

struct NotesCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        List {
            Section("Capture") {
                TextField("Title", text: $session.pendingNoteTitle)
                TextField("What happened / what matters?", text: $session.pendingNoteContent, axis: .vertical)
                    .lineLimit(4...10)

                Button("Save Note") {
                    Task { await session.saveNote() }
                }
            }

            Section("History") {
                if session.notes.isEmpty {
                    Text("No synced notes yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title).font(.headline)
                            Text(note.content).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Notes + Memory")
        .toolbar {
            ToolbarItem {
                Button("Reload") { Task { await session.loadNotes() } }
            }
        }
    }
}
