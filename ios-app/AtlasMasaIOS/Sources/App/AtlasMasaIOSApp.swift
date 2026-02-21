import SwiftUI

@main
struct AtlasMasaIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootDashboardView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .task {
                    await session.bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active || phase == .background {
                        session.startPromptQueueWorker()
                    }
                }
        }
    }
}
