import SwiftUI

struct RootDashboardView: View {
    var body: some View {
        TabView {
            CommandCenterCard()
                .tabItem { Label("Command", systemImage: "sparkles.square.filled.on.square") }

            ProactiveFeedCard()
                .tabItem { Label("Execution", systemImage: "dollarsign.circle") }

            WorkspacesCard()
                .tabItem { Label("Workspaces", systemImage: "wrench.and.screwdriver") }

            MobilityOpsCard()
                .tabItem { Label("Mobility", systemImage: "car.side.fill") }

            // Keep Account first in the tab overflow ("More") menu.
            AppleSignInCard()
                .tabItem { Label("Account", systemImage: "person.badge.key") }

            AIGuideCard()
                .tabItem { Label("AI Guide", systemImage: "book.closed") }

            NotesCard()
                .tabItem { Label("Memory", systemImage: "brain.head.profile") }

            SubscriptionCard()
                .tabItem { Label("Plans", systemImage: "creditcard") }
        }
        .tint(AtlasTheme.accentWarm)
    }
}
