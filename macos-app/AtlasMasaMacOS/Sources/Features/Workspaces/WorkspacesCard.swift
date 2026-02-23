import SwiftUI

struct WorkspacesCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "Research Workspaces",
            subtitle: "Operational lanes for emergency command, wealth, mobility, cognition, and innovation"
        ) {
            AtlasPanel(
                heading: "Session notebooks",
                caption: "NotebookLM-style sessions per workspace, with shared intelligence across all workspaces"
            ) {
                Picker("Workspace lane", selection: Binding(
                    get: { session.activeWorkspaceLane },
                    set: { session.setActiveWorkspaceLane($0) }
                )) {
                    ForEach(WorkspaceLane.allCases) { lane in
                        Text(lane.title).tag(lane)
                    }
                }
                .pickerStyle(.menu)
                .atlasFieldStyle()

                HStack(spacing: 10) {
                    Button("New notebook session") {
                        session.createWorkspaceSession(for: session.activeWorkspaceLane)
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())

                    Text("\(session.sessions(for: session.activeWorkspaceLane).count) sessions")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.accentWarm)
                }

                if session.sessions(for: session.activeWorkspaceLane).isEmpty {
                    Text("No sessions yet in this workspace.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(session.sessions(for: session.activeWorkspaceLane)) { notebook in
                        Button {
                            session.activateWorkspaceSession(notebook.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(notebook.title)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    Spacer()
                                    if session.activeSessionID(for: notebook.lane) == notebook.id {
                                        AtlasPill(title: "ACTIVE")
                                    }
                                }
                                Text(notebook.summary)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black.opacity(0.2))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            AtlasPanel(
                heading: "Workspace orchestration",
                caption: "Built from your survey, memory, check-ins, and research-ranked execution streams"
            ) {
                if session.workspacePlans.isEmpty {
                    Text("No workspace plans yet. Complete deep survey + check-in and add at least one note.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(session.workspacePlans) { workspace in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(workspace.title)
                                    .font(.system(size: 18, weight: .semibold, design: .serif))
                                    .foregroundStyle(AtlasTheme.textPrimary)
                                Spacer()
                                Text("CONF \(Int(workspace.confidence * 100))%")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(AtlasTheme.accentWarm)
                            }

                            Text(workspace.objective)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)

                            Text("Next action now: \(workspace.nextActionNow)")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(AtlasTheme.textPrimary)

                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(workspace.protocolChecklist, id: \.self) { step in
                                    Text("• \(step)")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                }
                            }

                            Text("Evidence: \(workspace.evidenceSummary)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)

                            if !workspace.sharedMemorySignals.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Shared memory signals")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    ForEach(workspace.sharedMemorySignals, id: \.self) { signal in
                                        Text("• \(signal)")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                    }
                                }
                            }

                            if !workspace.crossWorkspaceSignals.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Cross-workspace carryover")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    ForEach(workspace.crossWorkspaceSignals, id: \.self) { signal in
                                        Text("• \(signal)")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                    }
                                }
                            }

                            Text("Memory records linked: \(workspace.memoryRecordCount)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(AtlasTheme.accentWarm)

                            ForEach(workspace.citations) { citation in
                                Link(destination: URL(string: citation.sourceURL) ?? URL(string: "https://atlasmasa.com")!) {
                                    Text("Source: \(citation.title) (\(citation.year))")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(AtlasTheme.accent)
                                }
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                        )
                    }
                }
            }

            AtlasPanel(
                heading: "Collective wealth + impact network",
                caption: "Use collected signals to form high-trust collaboration squads for wealth-building and real-world problem solving"
            ) {
                let collaboration = collaborationSnapshot

                Text(collaboration.mission)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.textSecondary)

                HStack(spacing: 10) {
                    AtlasPill(title: session.isSignedIn ? "Account-linked" : "Guest-local")
                    AtlasPill(title: "\(collaboration.tags.count) active signals")
                    AtlasPill(title: "\(collaboration.matches.count) collaborator matches")
                }

                if collaboration.matches.isEmpty {
                    Text("Add one note or complete more deep survey questions to unlock stronger collaboration matching.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(collaboration.matches) { match in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(match.title)
                                    .font(.system(size: 15, weight: .semibold, design: .default))
                                    .foregroundStyle(AtlasTheme.textPrimary)
                                Spacer()
                                Text("FIT \(match.fitScore)%")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(AtlasTheme.accentWarm)
                            }

                            Text(match.whyMatch)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)

                            Text("First sprint: \(match.firstSprint)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(AtlasTheme.textPrimary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                        )
                    }
                }

                Text("Priority world-problem squads")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AtlasTheme.textPrimary)

                ForEach(collaboration.squads) { squad in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(squad.problem)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AtlasTheme.textPrimary)
                        Text(squad.squadMove)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }
                }

                Button("Generate collaboration brief") {
                    let topMatch = collaboration.matches.first?.title ?? "Cross-functional operator"
                    session.appendOutput("Collaboration brief ready: mission='\(collaboration.mission)' | top match='\(topMatch)' | squads=\(collaboration.squads.count).")
                }
                .buttonStyle(AtlasSecondaryButtonStyle())
            }
        }
    }

    private var collaborationSnapshot: CollaborationSnapshot {
        let baseText = [
            session.dailyPriority,
            session.midTermGoal,
            session.longTermVision,
            session.checkInBlockers,
            session.workspaceMode,
            session.notes.prefix(12).map(\.content).joined(separator: " "),
            session.workspacePlans.prefix(8).map(\.objective).joined(separator: " "),
            session.memoryInsights.prefix(12).map(\.value).joined(separator: " ")
        ]
            .joined(separator: " ")
            .lowercased()

        let tagRules: [(String, [String])] = [
            ("revenue", ["revenue", "cash", "income", "sales", "client", "לקוחות", "הכנסה"]),
            ("mobility", ["mobility", "vehicle", "transport", "fleet", "van", "רכב", "תחבורה"]),
            ("operations", ["ops", "operations", "workflow", "execution", "תפעול", "ביצוע"]),
            ("health", ["health", "recovery", "sleep", "fatigue", "בריאות", "עייפות"]),
            ("resilience", ["resilience", "risk", "emergency", "backup", "חירום", "גיבוי"]),
            ("product", ["product", "build", "ship", "prototype", "מוצר", "פיתוח"]),
            ("capital", ["capital", "finance", "invest", "budget", "הון", "השקעה"]),
            ("community", ["community", "partner", "team", "collab", "שיתוף", "קהילה"])
        ]

        let tags = Set(
            tagRules.compactMap { tag, needles in
                needles.contains(where: { baseText.contains($0) }) ? tag : nil
            }
        )

        let mission = session.longTermVision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Build a collaborative wealth-and-impact mission using your next 90-day priorities."
            : session.longTermVision

        let archetypes: [CollaborationArchetype] = [
            .init(
                title: "Revenue Growth Operator",
                requiredTags: ["revenue", "operations"],
                whyMatch: "Turns execution into predictable weekly cashflow and customer growth.",
                firstSprint: "Define one offer, one channel, and one weekly revenue metric."
            ),
            .init(
                title: "Mobility Infrastructure Builder",
                requiredTags: ["mobility", "operations", "product"],
                whyMatch: "Designs durable transport systems and converts field friction into scalable products.",
                firstSprint: "Map the top 3 mobility bottlenecks and ship one measurable fix."
            ),
            .init(
                title: "Capital + Finance Strategist",
                requiredTags: ["capital", "revenue"],
                whyMatch: "Builds allocation discipline so growth compounds instead of leaking.",
                firstSprint: "Create a 3-bucket capital plan: runway, growth, and reserves."
            ),
            .init(
                title: "Resilience & Safety Lead",
                requiredTags: ["resilience", "health", "operations"],
                whyMatch: "Hardens systems under stress so teams can execute in volatile conditions.",
                firstSprint: "Install one continuity protocol for crises, fatigue, and operational failures."
            ),
            .init(
                title: "Community Partnership Architect",
                requiredTags: ["community", "revenue", "mobility"],
                whyMatch: "Builds collaboration loops with aligned operators to accelerate impact.",
                firstSprint: "Recruit 3 partner organizations and launch one shared pilot."
            )
        ]

        let matches = archetypes
            .map { archetype in
                let overlap = archetype.requiredTags.filter { tags.contains($0) }.count
                let density = tags.isEmpty ? 0.0 : Double(overlap) / Double(archetype.requiredTags.count)
                let fitScore = max(35, Int((density * 100).rounded()))
                return CollaborationMatch(
                    title: archetype.title,
                    fitScore: fitScore,
                    whyMatch: archetype.whyMatch,
                    firstSprint: archetype.firstSprint
                )
            }
            .sorted { lhs, rhs in
                if lhs.fitScore == rhs.fitScore { return lhs.title < rhs.title }
                return lhs.fitScore > rhs.fitScore
            }
            .prefix(3)
            .map { $0 }

        let squads: [CollaborationSquad] = [
            .init(
                problem: "Affordable mobility access",
                squadMove: "Combine operators, finance, and product builders to reduce cost-per-km for workers and families."
            ),
            .init(
                problem: "Emergency readiness for road-based lives",
                squadMove: "Coordinate resilience protocols, health safeguards, and backup logistics to prevent catastrophic downtime."
            ),
            .init(
                problem: "Small-operator wealth mobility",
                squadMove: "Create collaborative playbooks that move individuals from survival mode to compounding ownership."
            )
        ]

        return CollaborationSnapshot(
            mission: mission,
            tags: tags.sorted(),
            matches: matches,
            squads: squads
        )
    }
}

private struct CollaborationArchetype {
    let title: String
    let requiredTags: [String]
    let whyMatch: String
    let firstSprint: String
}

private struct CollaborationMatch: Identifiable {
    let id = UUID().uuidString
    let title: String
    let fitScore: Int
    let whyMatch: String
    let firstSprint: String
}

private struct CollaborationSquad: Identifiable {
    let id = UUID().uuidString
    let problem: String
    let squadMove: String
}

private struct CollaborationSnapshot {
    let mission: String
    let tags: [String]
    let matches: [CollaborationMatch]
    let squads: [CollaborationSquad]
}
