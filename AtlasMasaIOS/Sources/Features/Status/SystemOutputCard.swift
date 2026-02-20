import SwiftUI

struct SystemOutputCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            List(session.systemOutput, id: \.self) { line in
                Text(line)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
            .navigationTitle("System Output")
        }
    }
}
