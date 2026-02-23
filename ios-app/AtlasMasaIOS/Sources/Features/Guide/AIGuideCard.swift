import SwiftUI

struct AIGuideCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "Atlas AI Guide",
            subtitle: "Why it exists, how it works, and how personalization/training are applied"
        ) {
            AtlasPanel(
                heading: "Why Atlas was built",
                caption: "Mission and intended outcome"
            ) {
                Text("Atlas is built to help people operate with more financial stability, healthier cognitive performance, and stronger execution under real-world pressure. The system focuses on daily function, long-term wealth mobility, and practical resilience for modern work/travel lifestyles.")
                    .foregroundStyle(AtlasTheme.textSecondary)
            }

            AtlasPanel(
                heading: "What the AI is trained for",
                caption: "Core domains Atlas is optimized to solve"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("• Economic execution: income growth paths, career/business decision support, and blocker removal")
                    Text("• Brain-performance aware planning: sleep/focus/stress-aware protocols for consistent output")
                    Text("• Work/travel operations: practical planning, continuity thinking, and high-friction environment execution")
                    Text("• Adaptive coaching: convert user data into actionable daily, mid-term, and long-horizon plans")
                }
                .foregroundStyle(AtlasTheme.textSecondary)
            }

            AtlasPanel(
                heading: "How Atlas works in-app",
                caption: "Operational pipeline"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1) Intake: adaptive survey, notes, prompts, workspace sessions, and check-ins.")
                    Text("2) Synthesis: local reasoning + decision rules identify blockers and priorities.")
                    Text("3) Execution design: daily/mid/long actions, workspace plans, and queue outputs.")
                    Text("4) Iteration: new behavior data updates recommendations and learning packages.")
                }
                .foregroundStyle(AtlasTheme.textSecondary)
            }

            AtlasPanel(
                heading: "How your personalization works",
                caption: "Memory and privacy behavior"
            ) {
                Text("Personalization uses your own inputs (survey answers, notes, check-ins, workspace sessions, and queue outputs). If memory collection is disabled, Atlas will avoid long-term memory accumulation and rely on lighter session context.")
                    .foregroundStyle(AtlasTheme.textSecondary)

                HStack(spacing: 10) {
                    AtlasPill(title: session.memoryCollectionEnabled ? "Memory ON" : "Memory OFF")
                    AtlasPill(title: session.selectedTier.title)
                }
            }

            AtlasPanel(
                heading: "Live account data footprint",
                caption: "What is actively available to the planning engine right now"
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Survey answers captured: \(session.survey?.progress.answered ?? 0)")
                    Text("Notes stored: \(session.notes.count)")
                    Text("Workspace sessions: \(session.workspaceSessions.count)")
                    Text("Memory records: \(session.workspaceMemoryRecords.count)")
                    Text("Queued prompts: \(session.promptQueue.count)")
                    Text("Execution actions in plan: \(session.executionActions.count)")
                }
                .foregroundStyle(AtlasTheme.textSecondary)
            }

            AtlasPanel(
                heading: "Professional boundaries",
                caption: "How to use Atlas safely"
            ) {
                Text("Atlas provides structured decision support, not guaranteed outcomes or licensed professional advice. Treat outputs as an execution copilot: validate high-stakes medical, legal, and regulated financial decisions with qualified professionals.")
                    .foregroundStyle(AtlasTheme.textSecondary)
            }
        }
    }
}
