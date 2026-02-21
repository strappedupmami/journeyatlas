import SwiftUI

@main
struct AtlasMasaIOSApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootDashboardView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .task {
                    await session.bootstrap()
                }
        }
    }
}
