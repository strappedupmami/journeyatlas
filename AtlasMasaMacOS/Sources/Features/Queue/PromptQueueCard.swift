import SwiftUI

struct PromptQueueCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        List {
            Section("Queue prompts") {
                TextField("Type a prompt to queue", text: $session.pendingPrompt, axis: .vertical)
                    .lineLimit(2 ... 6)
                HStack {
                    Button("Add to queue") {
                        session.enqueuePrompt()
                    }
                    Button("Run local worker") {
                        session.startPromptQueueWorker()
                    }
                    .buttonStyle(.bordered)
                }
                Button("Clear queue", role: .destructive) {
                    session.clearPromptQueue()
                }
            }

            Section("Queued items") {
                if session.promptQueue.isEmpty {
                    Text("No queued prompts yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.promptQueue) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.prompt)
                                .font(.headline)
                            Text("Status: \(item.status.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let output = item.output {
                                Text("Summary: \(output.summary)")
                                    .font(.subheadline)
                                Text("Next action: \(output.nextAction)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Prompt Queue")
    }
}
