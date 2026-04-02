import SwiftUI

struct SystemOutputCard: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showLogs = false

    var body: some View {
        if !session.canViewRuntimeDiagnostics {
            AtlasScreen(
                title: "Runtime Health",
                subtitle: "Owner-only diagnostics"
            ) {
                AtlasPanel(heading: "Unavailable", caption: "Runtime diagnostics are limited to the BlackHaven Owner account") {
                    Text("This area is reserved for owner-level runtime diagnostics and setup traces.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                }
            }
        } else {
        AtlasScreen(
            title: "Runtime Health",
            subtitle: "Local AI readiness, setup actions, and secondary operational traces"
        ) {
            AtlasPanel(heading: session.runtimeHealthHeadline, caption: "BlackHaven-managed local AI setup and runtime readiness") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(session.localModelRuntimeStatus)
                            .font(.headline)
                            .foregroundStyle(session.localModelRuntimeReady ? Color.green : AtlasTheme.textPrimary)
                        Spacer()
                        Text(session.localModelRuntimeReady ? "Ready" : (session.localModelRuntimeIsBusy ? "In Progress" : "Pending"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }

                    Text(session.localModelRuntimeDetail)
                        .font(.footnote)
                        .foregroundStyle(AtlasTheme.textSecondary)

                    Text("Detected hardware: \(session.localAIHardwareSummary)")
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textSecondary)

                    Text(session.localReasoningDepthStatus)
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textSecondary)

                    Text(session.runtimeEndpointReachabilityLine)
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textSecondary)

                    if !session.selectedLocalAIInstallOptions.isEmpty {
                        Text("Selected models: \(session.selectedLocalAIInstallSummary)")
                            .font(.caption)
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }

                    if session.shouldShowLocalRuntimeProgressUI {
                        AtlasModelRuntimeProgressStrip(
                            progress: session.localModelRuntimeProgress,
                            busy: session.localModelRuntimeIsBusy,
                            title: "Model Download",
                            sizeText: session.localModelDownloadSizeText,
                            etaText: session.localModelDownloadETAText,
                            compact: false
                        )
                    }

                    HStack(spacing: 10) {
                        Button(session.localAIPrimaryActionTitle) {
                            if session.localAISetupCompleted {
                                session.retryLocalAISetup()
                            } else {
                                session.installSelectedLocalAIModels()
                            }
                        }
                        .buttonStyle(AtlasPrimaryButtonStyle())

                        Button("Show Setup Options") {
                            session.revealLocalAISetupAgain()
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                    }
                }
            }

            AtlasPanel(heading: "CAD / EDA Tools", caption: "FreeCAD, CalculiX, and KiCad setup, path detection, and executable health checks") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(session.cadToolsStatusLine)
                            .font(.headline)
                            .foregroundStyle(session.cadToolsHealthy ? Color.green : AtlasTheme.textPrimary)
                        Spacer()
                        Text(session.cadToolsHealthy ? "Ready" : (session.cadToolsConfigured ? "Configured" : "Setup Needed"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }

                    Text(session.freeCADHealthLine)
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textSecondary)
                    Text(session.freeCADCmdHealthLine)
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textSecondary)
                    Text(session.kiCadCLIHealthLine)
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textSecondary)
                    Text(session.calculiXHealthLine)
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textSecondary)

                    HStack(spacing: 10) {
                        Button("Open Setup Wizard") {
                            session.revealCADToolsSetupWizard()
                        }
                        .buttonStyle(AtlasPrimaryButtonStyle())

                        Button("Auto Detect") {
                            Task { await session.autoDetectCADTools() }
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())

                        Button("Run Health Check") {
                            Task { await session.runCADToolsHealthCheck() }
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Official downloads")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AtlasTheme.textPrimary)
                        ForEach(session.cadToolDownloads) { tool in
                            VStack(alignment: .leading, spacing: 2) {
                                Link(tool.title, destination: URL(string: tool.url)!)
                                    .font(.footnote.weight(.semibold))
                                Text(tool.detail)
                                    .font(.caption)
                                    .foregroundStyle(AtlasTheme.textSecondary)
                                Text(tool.url)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(AtlasTheme.textSecondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }

            AtlasPanel(heading: "Runtime log", caption: "Secondary diagnostics, hidden by default") {
                DisclosureGroup(isExpanded: $showLogs) {
                    VStack(alignment: .leading, spacing: 8) {
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
                } label: {
                    Text(showLogs ? "Hide runtime log" : "Show runtime log")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .sheet(isPresented: $session.showCADToolsSetupWizard) {
            CADToolsSetupWizardSheet()
                .environmentObject(session)
        }
        }
    }

}

struct CADToolsSetupWizardSheet: View {
    @EnvironmentObject private var session: SessionStore
    @State private var freeCADPath = ""
    @State private var freeCADCmdPath = ""
    @State private var kiCadCLIPath = ""
    @State private var calculiXPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("CAD Tools Setup")
                .font(.largeTitle.weight(.bold))
            Text("Set the executable paths BlackHaven should use for FreeCAD, CalculiX, and KiCad-backed R&D jobs. Official app installs are recommended; BlackHaven will call the tools externally rather than bundle them.")
                .foregroundStyle(.secondary)

            Group {
                Text("FreeCAD executable")
                    .font(.headline)
                TextField("/Applications/FreeCAD.app/Contents/MacOS/FreeCAD", text: $freeCADPath)
                    .textFieldStyle(.roundedBorder)

                Text("FreeCADCmd executable")
                    .font(.headline)
                TextField("/Applications/FreeCAD.app/Contents/Resources/bin/FreeCADCmd", text: $freeCADCmdPath)
                    .textFieldStyle(.roundedBorder)

                Text("KiCad CLI executable")
                    .font(.headline)
                TextField("/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli", text: $kiCadCLIPath)
                    .textFieldStyle(.roundedBorder)

                Text("CalculiX / ccx executable")
                    .font(.headline)
                TextField("/opt/homebrew/bin/ccx", text: $calculiXPath)
                    .textFieldStyle(.roundedBorder)
            }

            Text("Tip: you can paste either the executable path directly or, for FreeCAD/KiCad apps, the `.app` bundle path and let BlackHaven normalize it.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Downloads")
                    .font(.headline)
                ForEach(session.cadToolDownloads) { tool in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Link(tool.title, destination: URL(string: tool.url)!)
                                .font(.subheadline.weight(.semibold))
                            Text(tool.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(tool.url)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Auto Detect") {
                    Task {
                        await session.autoDetectCADTools()
                        let snapshot = session.cadToolsSettingsSnapshot()
                        freeCADPath = snapshot.freeCADPath
                        freeCADCmdPath = snapshot.freeCADCmdPath
                        kiCadCLIPath = snapshot.kiCadCLIPath
                        calculiXPath = snapshot.calculiXPath
                    }
                }
                .buttonStyle(AtlasSecondaryButtonStyle())

                Button("Save Paths") {
                    session.saveCADToolsSettings(
                        freeCADPath: freeCADPath,
                        freeCADCmdPath: freeCADCmdPath,
                        kiCadCLIPath: kiCadCLIPath,
                        calculiXPath: calculiXPath
                    )
                }
                .buttonStyle(AtlasSecondaryButtonStyle())

                Button("Save + Health Check") {
                    session.saveCADToolsSettings(
                        freeCADPath: freeCADPath,
                        freeCADCmdPath: freeCADCmdPath,
                        kiCadCLIPath: kiCadCLIPath,
                        calculiXPath: calculiXPath
                    )
                    Task { await session.runCADToolsHealthCheck() }
                }
                .buttonStyle(AtlasPrimaryButtonStyle())
            }

            HStack {
                Spacer()
                Button("Close") {
                    session.dismissCADToolsSetupWizard()
                }
            }
        }
        .padding(28)
        .frame(minWidth: 700, minHeight: 360)
        .onAppear {
            let snapshot = session.cadToolsSettingsSnapshot()
            freeCADPath = snapshot.freeCADPath
            freeCADCmdPath = snapshot.freeCADCmdPath
            kiCadCLIPath = snapshot.kiCadCLIPath
            calculiXPath = snapshot.calculiXPath
        }
    }
}
