import SwiftUI

struct RootDashboardView: View {
    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink("Auth") { AppleSignInCard() }
                NavigationLink("Adaptive Survey") { AdaptiveSurveyCard() }
                NavigationLink("Proactive Feed") { ProactiveFeedCard() }
                NavigationLink("Notes") { NotesCard() }
                NavigationLink("Prompt Queue") { PromptQueueCard() }
                NavigationLink("Subscription") { SubscriptionCard() }
                NavigationLink("System Output") { SystemOutputCard() }
            }
            .navigationTitle("Atlas Masa")
        } detail: {
            AppleSignInCard()
        }
        .frame(minWidth: 960, minHeight: 620)
    }
}
