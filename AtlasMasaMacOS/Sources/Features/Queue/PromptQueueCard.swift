import SwiftUI

struct PromptQueueCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "Prompt Queue",
            subtitle: "Queue prompts and run local reasoning in managed background passes"
        ) {
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
