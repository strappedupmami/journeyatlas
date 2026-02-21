import SwiftUI

struct RootDashboardView: View {
    var body: some View {
        TabView {
            AppleSignInCard()
                .tabItem { Label("Auth", systemImage: "person.badge.key") }

            AdaptiveSurveyCard()
                .tabItem { Label("Survey", systemImage: "list.bullet.clipboard") }

            ProactiveFeedCard()
                .tabItem { Label("Feed", systemImage: "bolt.heart") }

            NotesCard()
                .tabItem { Label("Notes", systemImage: "square.and.pencil") }

            PromptQueueCard()
                .tabItem { Label("Queue", systemImage: "tray.full") }

            SubscriptionCard()
                .tabItem { Label("Billing", systemImage: "creditcard") }

            SystemOutputCard()
                .tabItem { Label("Output", systemImage: "terminal") }
        }
    }
}
