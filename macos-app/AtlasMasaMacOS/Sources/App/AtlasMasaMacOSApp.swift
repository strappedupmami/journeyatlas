import AppKit
import SwiftUI

final class AtlasAppDelegate: NSObject, NSApplicationDelegate {
    private var didForceFullscreen = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        enforceImmersiveWindowMode()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        enforceImmersiveWindowMode()
    }

    private func enforceImmersiveWindowMode(retryCount: Int = 0) {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else {
            guard retryCount < 12 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.enforceImmersiveWindowMode(retryCount: retryCount + 1)
            }
            return
        }

        window.collectionBehavior.insert(.fullScreenPrimary)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact

        guard !didForceFullscreen else { return }
        guard !window.styleMask.contains(.fullScreen) else { return }
        didForceFullscreen = true
        DispatchQueue.main.async {
            window.toggleFullScreen(nil)
        }
    }
}

@main
struct AtlasMasaMacOSApp: App {
    @NSApplicationDelegateAdaptor(AtlasAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
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
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Workspace Session") {
                    session.createWorkspaceSession(for: session.activeWorkspaceLane)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

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

                Button("Clear Session Memory") {
                    session.deleteLocalMemory()
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
    }
}
