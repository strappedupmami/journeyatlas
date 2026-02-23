import SwiftUI

struct RootDashboardView: View {
    private enum Tab: Hashable {
        case concierge
        case execution
        case workspaces
        case mobility
        case more
    }

    @State private var selectedTab: Tab = .concierge

    var body: some View {
        TabView(selection: $selectedTab) {
            CommandCenterCard()
                .tag(Tab.concierge)
                .tabItem { Label("Concierge", systemImage: "message.fill") }

            ProactiveFeedCard()
                .tag(Tab.execution)
                .tabItem { Label("Execution", systemImage: "dollarsign.circle") }

            WorkspacesCard()
                .tag(Tab.workspaces)
                .tabItem { Label("Workspaces", systemImage: "wrench.and.screwdriver") }

            MobilityOpsCard()
                .tag(Tab.mobility)
                .tabItem { Label("Mobility", systemImage: "car.side.fill") }

            MoreMenuCard()
                .tag(Tab.more)
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .tint(AtlasTheme.accentWarm)
    }
}

private struct MoreMenuCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            AtlasScreen(
                title: "More",
                subtitle: "Account, memory, guide, and billing controls"
            ) {
                AtlasPanel(
                    heading: "Profile photo",
                    caption: "Shown above your menu options"
                ) {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AtlasTheme.accent, AtlasTheme.accentWarm],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)
                            .overlay(
                                Text(profileInitials)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.white)
                            )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.accountLabel)
                                .font(.system(size: 18, weight: .semibold, design: .default))
                                .foregroundStyle(AtlasTheme.textPrimary)
                            Text(session.isSignedIn ? "Signed in" : "Guest mode")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)
                        }
                        Spacer()
                    }
                }

                AtlasPanel(
                    heading: "Options",
                    caption: "Open any section from here"
                ) {
                    NavigationLink {
                        AppleSignInCard()
                    } label: {
                        MoreRow(icon: "person.badge.key", title: "Account", subtitle: "Security and sign-in methods")
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        NotesCard()
                    } label: {
                        MoreRow(icon: "brain.head.profile", title: "Memory", subtitle: "Long-term personalization signals")
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AIGuideCard()
                    } label: {
                        MoreRow(icon: "book.closed", title: "AI Guide", subtitle: "How Atlas works and privacy behavior")
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SubscriptionCard()
                    } label: {
                        MoreRow(icon: "creditcard", title: "Plans", subtitle: "Free trial and paid subscription")
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SystemOutputCard()
                    } label: {
                        MoreRow(icon: "terminal", title: "System Output", subtitle: "Operational status and traces")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var profileInitials: String {
        let trimmed = session.accountLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "A" }
        let parts = trimmed.split(separator: " ")
        if parts.count >= 2 {
            let first = parts.first?.first.map(String.init) ?? ""
            let second = parts.dropFirst().first?.first.map(String.init) ?? ""
            let initials = (first + second).uppercased()
            return initials.isEmpty ? "A" : initials
        }
        let first = trimmed.prefix(1).uppercased()
        return first.isEmpty ? "A" : String(first)
    }
}

private struct MoreRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AtlasTheme.accentWarm)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(AtlasTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.textSecondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AtlasTheme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AtlasTheme.cardStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AtlasTheme.border, lineWidth: 1)
        )
    }
}
