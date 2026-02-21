import SwiftUI

struct RootDashboardView: View {
    var body: some View {
        TabView {
            CommandCenterCard()
                .tabItem { Label("Command", systemImage: "sparkles.square.filled.on.square") }

            AdaptiveSurveyCard()
                .tabItem { Label("Survey", systemImage: "point.3.connected.trianglepath.dotted") }

            PromptQueueCard()
                .tabItem { Label("Queue", systemImage: "tray.full") }

            ProactiveFeedCard()
                .tabItem { Label("Execution", systemImage: "bolt.heart") }

            NotesCard()
                .tabItem { Label("Memory", systemImage: "brain.head.profile") }

            MobilityOpsCard()
                .tabItem { Label("Mobility", systemImage: "car.side") }

            AppleSignInCard()
                .tabItem { Label("Access", systemImage: "person.badge.key") }

            SubscriptionCard()
                .tabItem { Label("Plans", systemImage: "creditcard") }

            SystemOutputCard()
                .tabItem { Label("Output", systemImage: "terminal") }
        }
        .tint(AtlasTheme.accentWarm)
    }
}
