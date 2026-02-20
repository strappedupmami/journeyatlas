import SwiftUI

struct ProactiveFeedCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            List {
                if session.feedItems.isEmpty {
                    Text("No proactive items yet. Connect API + auth to unlock full feed.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.feedItems) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.headline)
                            Text(item.summary).font(.subheadline)
                            Text("Why now: \(item.whyNow)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Priority: \(item.priority)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Proactive Feed")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") { Task { await session.refreshFeed() } }
                }
            }
        }
    }
}
