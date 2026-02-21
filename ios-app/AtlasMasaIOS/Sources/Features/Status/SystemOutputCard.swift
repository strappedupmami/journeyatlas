import SwiftUI

struct SystemOutputCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "System Output",
            subtitle: "Operational trace for auth, survey, queue worker, memory, and orchestration events"
        ) {
            AtlasPanel(heading: "Runtime log", caption: "Most recent events appear first") {
                if session.systemOutput.isEmpty {
                    Text("No logs yet.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(session.systemOutput, id: \.self) { line in
                        Text(line)
                            .font(.footnote.monospaced())
                            .foregroundStyle(AtlasTheme.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.black.opacity(0.22))
                            )
                    }
                }
            }
        }
    }
}
