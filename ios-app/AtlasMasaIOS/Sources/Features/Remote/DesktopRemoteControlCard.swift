import SwiftUI

struct DesktopRemoteControlCard: View {
    @EnvironmentObject private var remote: DesktopRemoteControlStore

    var body: some View {
        AtlasScreen(
            title: "Desktop Remote",
            subtitle: "Use BlackHaven on desktop for Qwen and GPT-5.4 from your phone"
        ) {
            AtlasPanel(heading: "Connection", caption: "Pair with the desktop app on the same network") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Desktop URL", text: $remote.baseURLText)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Pairing token", text: $remote.tokenText)
                        .textFieldStyle(.roundedBorder)

                    Text(remote.desktopName)
                        .font(.headline)
                        .foregroundStyle(AtlasTheme.textPrimary)
                    Text(remote.connectionStatus)
                        .font(.footnote)
                        .foregroundStyle(AtlasTheme.textSecondary)
                    Text("Runtime: \(remote.runtimeSummary) · local model: \(remote.localModel) · queue: \(remote.queueDepth)")
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textSecondary)

                    Button(remote.isBusy ? "Refreshing…" : "Refresh desktop status") {
                        Task { await remote.refreshStatus() }
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                    .disabled(remote.isBusy)
                }
            }

            AtlasPanel(heading: "Dispatch", caption: "Choose Qwen or GPT-5.4, then send work to desktop") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Target", selection: $remote.selectedTarget) {
                        ForEach(DesktopRemoteControlStore.DispatchTarget.allCases) { target in
                            Text(target.title).tag(target)
                        }
                    }
                    .pickerStyle(.segmented)

                    if remote.selectedTarget == .cloudGPT54 {
                        Picker("Coding route", selection: $remote.selectedRoute) {
                            ForEach(DesktopRemoteControlStore.CodingRoute.allCases) { route in
                                Text(route.title).tag(route)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    TextEditor(text: $remote.draftPrompt)
                        .frame(minHeight: 160)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.22))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AtlasTheme.border, lineWidth: 1)
                        )

                    Button(remote.isBusy ? "Sending…" : "Send to desktop") {
                        Task { await remote.sendPrompt() }
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())
                    .disabled(remote.isBusy)

                    Text(remote.lastAction)
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textSecondary)
                }
            }
        }
    }
}
