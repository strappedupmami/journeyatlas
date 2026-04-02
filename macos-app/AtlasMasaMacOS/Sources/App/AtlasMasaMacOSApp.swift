import AppKit
import SwiftUI

final class AtlasAppDelegate: NSObject, NSApplicationDelegate {
    private var didApplyPreferredWindowSizing = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SessionStore.captureLaunchTriggeredGUIValidationRequestIfNeeded()
        configurePreferredWindowPresentation()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        configurePreferredWindowPresentation()
    }

    private func configurePreferredWindowPresentation(retryCount: Int = 0) {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else {
            guard retryCount < 12 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.configurePreferredWindowPresentation(retryCount: retryCount + 1)
            }
            return
        }

        window.collectionBehavior.insert(.fullScreenPrimary)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact

        guard !didApplyPreferredWindowSizing else { return }
        didApplyPreferredWindowSizing = true

        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let targetFrame: NSRect
        if let visibleFrame {
            let width = min(max(1280, visibleFrame.width * 0.9), visibleFrame.width)
            let height = min(max(820, visibleFrame.height * 0.9), visibleFrame.height)
            targetFrame = NSRect(
                x: visibleFrame.midX - (width / 2),
                y: visibleFrame.midY - (height / 2),
                width: width,
                height: height
            )
        } else {
            targetFrame = NSRect(x: 80, y: 80, width: 1440, height: 900)
        }

        window.setFrame(targetFrame, display: true)
        window.center()
    }
}

@main
struct AtlasMasaMacOSApp: App {
    @NSApplicationDelegateAdaptor(AtlasAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup(id: "main-dashboard") {
            RootDashboardView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1000, minHeight: 650)
                .task {
                    await session.bootstrap()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhase(newPhase)
                }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1200, height: 800)

        WindowGroup("World Monitor", id: "world-monitor") {
            WorldMonitorCard()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1000, minHeight: 650)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1160, height: 780)

        WindowGroup("Nature Monitor", id: "nature-monitor") {
            NatureMonitorCard()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1000, minHeight: 650)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1160, height: 780)

        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Workspace Session") {
                    session.createWorkspaceSession(for: session.activeWorkspaceLane)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Monitors") {
                Button("Open World Monitor Window") {
                    openWindow(id: "world-monitor")
                }
                .keyboardShortcut("1", modifiers: [.command, .shift])

                Button("Open Nature Monitor Window") {
                    openWindow(id: "nature-monitor")
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])
            }

#if DEBUG
            CommandMenu("Validation") {
                Button("Run GUI Validation Suite") {
                    session.requestGUIValidationSuite(triggerSource: "validation menu")
                }
                .keyboardShortcut("y", modifiers: [.command, .shift])

                Button("Arm GUI Validation For Next Launch") {
                    session.armGUIValidationSuiteForNextLaunch()
                }

                Button("Clear GUI Validation Log") {
                    session.guiValidationCurrentStep = ""
                    session.guiValidationLastTriggerSource = ""
                    session.guiValidationLogs = []
                }
            }
#endif

            if session.canViewRuntimeDiagnostics {
                CommandMenu("Runtime") {
                    Button("Restart Agentic Workers") {
                        session.startPromptQueueWorker()
                        session.startAgenticBusinessRuntime()
                    }
                    .keyboardShortcut("r", modifiers: [.command, .shift])

                    Button("Refresh Health Check") {
                        Task { await session.refreshHealth() }
                    }

                    Divider()

                    Button("Run GUI Validation Suite Now") {
                        session.requestGUIValidationSuite(triggerSource: "runtime menu")
                    }

                    Button("Arm GUI Validation For Next Launch") {
                        session.armGUIValidationSuiteForNextLaunch()
                    }

                    Divider()

                    Button("Clear Session Memory") {
                        session.deleteLocalMemory()
                    }
                }
            }
        }

        Settings {
            AtlasSettingsView()
                .environmentObject(session)
        }
        .defaultSize(width: 520, height: 320)
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        guard session.allowsAutomaticRuntimeWork else { return }
        switch phase {
        case .active, .background:
            session.startPromptQueueWorker()
            session.startAgenticBusinessRuntime()
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}

private struct AtlasSettingsView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        TabView {
            Form {
                Section("Memory") {
                    Toggle(
                        "Enable Local Memory Persistence",
                        isOn: Binding(
                            get: { session.memoryCollectionEnabled },
                            set: { session.setMemoryCollectionEnabled($0) }
                        )
                    )
                    Text(session.memoryUsageEstimate())
                        .foregroundStyle(.secondary)
                }

                Section("Adaptive Runtime") {
                    Toggle(
                        "Adaptive Question Engine",
                        isOn: Binding(
                            get: { session.adaptiveBusinessQuestionEngineEnabled },
                            set: { enabled in
                                session.saveAdaptiveBusinessRuntimeSettings(
                                    questionEngineEnabled: enabled,
                                    businessAutopilotEnabled: session.businessAutopilotEnabled
                                )
                            }
                        )
                    )
                    Toggle(
                        "Business Autopilot",
                        isOn: Binding(
                            get: { session.businessAutopilotEnabled },
                            set: { enabled in
                                session.saveAdaptiveBusinessRuntimeSettings(
                                    questionEngineEnabled: session.adaptiveBusinessQuestionEngineEnabled,
                                    businessAutopilotEnabled: enabled
                                )
                            }
                        )
                    )
                    Text(session.adaptiveBusinessRuntimeStatusLine)
                        .foregroundStyle(.secondary)
                }

                Section("Workspace Modules") {
                    Toggle(
                        "Show MLI Studio",
                        isOn: Binding(
                            get: { session.mliStudioVisible },
                            set: { session.setMLIStudioVisible($0) }
                        )
                    )
                    Text("MLI Studio covers vanlife, RV systems, and mobile living infrastructure planning.")
                        .foregroundStyle(.secondary)
                }

                Section("CAD Tools") {
                    Text(session.cadToolsStatusLine)
                        .foregroundStyle(.secondary)
                    Text(session.freeCADHealthLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(session.freeCADCmdHealthLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(session.kiCadCLIHealthLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(session.calculiXHealthLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Open Setup Wizard") {
                            session.revealCADToolsSetupWizard()
                        }
                        Button("Auto Detect") {
                            Task { await session.autoDetectCADTools() }
                        }
                        Button("Run Health Check") {
                            Task { await session.runCADToolsHealthCheck() }
                        }
                    }

                    ForEach(session.cadToolDownloads) { tool in
                        VStack(alignment: .leading, spacing: 2) {
                            Link(tool.title, destination: URL(string: tool.url)!)
                            Text(tool.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(20)
            .tabItem {
                Label("Runtime", systemImage: "gearshape")
            }

            Form {
                Section("Workers") {
                    Button("Restart Agentic Workers") {
                        session.startPromptQueueWorker()
                        session.startAgenticBusinessRuntime()
                    }
                    Button("Request Adaptive Question Now") {
                        session.requestNextAdaptiveBusinessQuestionNow()
                    }
                }

                Section("Safety") {
                    Button("Clear Session Memory") {
                        session.deleteLocalMemory()
                    }
                    .foregroundStyle(.red)
                }
            }
            .padding(20)
            .tabItem {
                Label("Diagnostics", systemImage: "wrench.and.screwdriver")
            }
        }
        .sheet(isPresented: $session.showCADToolsSetupWizard) {
            CADToolsSetupWizardSheet()
                .environmentObject(session)
        }
    }
}
