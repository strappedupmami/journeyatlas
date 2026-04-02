import SwiftUI

@main
struct AtlasMasaIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = SessionStore()
    @StateObject private var remote = DesktopRemoteControlStore()

    var body: some Scene {
        WindowGroup {
            RootDashboardView()
                .environmentObject(session)
                .environmentObject(remote)
                .preferredColorScheme(.dark)
                .task {
                    await session.bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active || phase == .background {
                        session.startPromptQueueWorker()
                        session.startAgenticBusinessRuntime()
                    }
                    if phase == .active {
                        Task {
                            await session.handleAppBecameActive()
                        }
                    }
                }
        }
    }
}
