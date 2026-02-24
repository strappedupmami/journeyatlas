import SwiftUI

struct WorkspacesCard: View {
    @EnvironmentObject private var session: SessionStore
    @FocusState private var queuePromptFocused: Bool

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
                heading: workspaceStudio.heading,
                caption: workspaceStudio.caption
            ) {
                let studio = workspaceStudio

                Text(studio.positioning)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.textSecondary)

                HStack(spacing: 10) {
                    AtlasPill(title: "CONF \(studio.confidencePercent)%")
                    AtlasPill(title: "\(studio.signalCount) lane signals")
                    AtlasPill(title: "\(studio.notebookCount) notebooks")
                    AtlasPill(title: "Queue \(activeQueueDepth)")
                }

                Text("Model lane brief")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AtlasTheme.textPrimary)
                Text(session.workspaceModelBrief)
                    .foregroundStyle(AtlasTheme.textSecondary)

                if let plan = session.workspacePlans.first(where: { $0.lane == session.activeWorkspaceLane }) {
                    Text("Lane objective: \(plan.objective)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.textSecondary)
                    Text("Current target: \(plan.nextActionNow)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.textPrimary)
                }

                ForEach(studio.modules) { module in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(module.title, systemImage: module.symbolName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AtlasTheme.textPrimary)
                        Text(module.purpose)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AtlasTheme.textSecondary)
                        Text("Deliverable: \(module.deliverable)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AtlasTheme.accentWarm)

                        Button("Run \(module.title)") {
                            session.launchWorkspaceStudioModule(
                                moduleTitle: module.title,
                                moduleInstruction: module.instruction
                            )
                        }
                        .buttonStyle(AtlasPrimaryButtonStyle())
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.2))
                    )
                }

                HStack(spacing: 10) {
                    Button("Queue lane executive brief") {
                        session.launchWorkspaceStudioModule(
                            moduleTitle: "Executive Lane Brief",
                            moduleInstruction: studio.executiveBriefInstruction
                        )
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())

                    Button("New lane notebook") {
                        session.createWorkspaceSession(for: session.activeWorkspaceLane)
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
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
                                    .font(.system(size: 18, weight: .semibold, design: .default))
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

            AtlasPanel(
                heading: "Workspace queue",
                caption: "Queue is now an internal workspace tool for local reasoning passes"
            ) {
                TextField("Write a prompt for local reasoning", text: $session.pendingPrompt, axis: .vertical)
                    .lineLimit(3 ... 8)
                    .atlasFieldStyle()
                    .focused($queuePromptFocused)

                HStack {
                    Button("Add to queue") {
                        queuePromptFocused = false
                        session.enqueuePrompt()
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())

                    Button("Run worker") {
                        queuePromptFocused = false
                        session.startPromptQueueWorker()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())

                    Button("Clear") {
                        queuePromptFocused = false
                        session.clearPromptQueue()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                }

                if session.promptQueue.isEmpty {
                    Text("No queued prompts yet.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(session.promptQueue) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.prompt)
                                    .font(.system(size: 16, weight: .semibold, design: .default))
                                    .foregroundStyle(AtlasTheme.textPrimary)
                                Spacer()
                                Text(item.status.rawValue.uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(AtlasTheme.accentWarm)
                            }

                            if let output = item.output {
                                Text("Summary: \(output.summary)")
                                    .foregroundStyle(AtlasTheme.textSecondary)
                                Text("Next action: \(output.nextAction)")
                                    .foregroundStyle(AtlasTheme.textPrimary)
                            }

                            if let error = item.errorMessage {
                                Text(error)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                        )
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    queuePromptFocused = false
                }
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

    private var activeQueueDepth: Int {
        session.promptQueue.filter { $0.status == .queued || $0.status == .running }.count
    }

    private var workspaceStudio: WorkspaceStudioSnapshot {
        let lane = session.activeWorkspaceLane
        let lanePlan = session.workspacePlans.first(where: { $0.lane == lane })
        let signalCount = session.workspaceMemoryRecords.filter { $0.lane == lane || $0.lane == nil }.count
        let notebookCount = session.sessions(for: lane).count
        let confidencePercent = Int(((lanePlan?.confidence ?? 0.58) * 100).rounded())

        switch lane {
        case .emergencyCommand:
            return WorkspaceStudioSnapshot(
                heading: "Emergency Command Studio",
                caption: "Incident-grade controls for triage, escalation, and continuity",
                positioning: "Operate with disciplined incident command: stabilize first, route communication, then recover service continuity.",
                confidencePercent: confidencePercent,
                signalCount: signalCount,
                notebookCount: notebookCount,
                executiveBriefInstruction: "Create an emergency command brief for the next 24 hours with triage priorities, escalation thresholds, continuity actions, and a handoff summary.",
                modules: [
                    WorkspaceStudioModule(
                        symbolName: "cross.case.fill",
                        title: "Incident Triage Board",
                        purpose: "Convert active signals into severity tiers and first response actions.",
                        deliverable: "Severity board with owners, immediate actions, and containment goals.",
                        instruction: "Build an incident triage board from active workspace signals. Include severity levels, first 30-minute actions, owners, and escalation thresholds."
                    ),
                    WorkspaceStudioModule(
                        symbolName: "person.3.sequence.fill",
                        title: "Escalation Chain Mapper",
                        purpose: "Define who gets informed, when, and through which channel under pressure.",
                        deliverable: "Escalation chain by trigger, role, and communication channel.",
                        instruction: "Map an escalation chain for this situation. Provide trigger conditions, role assignments, communication channels, and fallback routing if a role is unavailable."
                    ),
                    WorkspaceStudioModule(
                        symbolName: "waveform.path.ecg",
                        title: "Continuity Recovery Plan",
                        purpose: "Protect mission-critical operations while services degrade or fail.",
                        deliverable: "24-hour continuity protocol with restoration checkpoints.",
                        instruction: "Design a 24-hour continuity and recovery protocol with critical services, fallback paths, timeline checkpoints, and recovery validation steps."
                    )
                ]
            )

        case .wealthOperations:
            return WorkspaceStudioSnapshot(
                heading: "Wealth Operations Studio",
                caption: "Cashflow, pricing, and compounding controls for predictable growth",
                positioning: "Treat wealth as an operating system: drive direct revenue, defend margin, and compound gains through disciplined review loops.",
                confidencePercent: confidencePercent,
                signalCount: signalCount,
                notebookCount: notebookCount,
                executiveBriefInstruction: "Create a one-week wealth operations brief with direct revenue actions, pricing tests, risk controls, and daily performance metrics.",
                modules: [
                    WorkspaceStudioModule(
                        symbolName: "dollarsign.circle.fill",
                        title: "Revenue Sprint Planner",
                        purpose: "Turn high-level goals into direct money actions for the next 7 days.",
                        deliverable: "Day-by-day revenue sprint with measurable outputs.",
                        instruction: "Create a 7-day revenue sprint plan with one direct money action per day, expected output, and a daily review metric."
                    ),
                    WorkspaceStudioModule(
                        symbolName: "chart.line.uptrend.xyaxis",
                        title: "Pricing and Offer Lab",
                        purpose: "Improve offer clarity, price points, and close probability.",
                        deliverable: "Pricing test matrix with hypotheses and next experiment.",
                        instruction: "Design a pricing and offer test matrix with 3 experiments, hypothesis for each, expected conversion effect, and decision rules."
                    ),
                    WorkspaceStudioModule(
                        symbolName: "shield.lefthalf.filled",
                        title: "Cashflow Defense Grid",
                        purpose: "Protect runway and reduce downside when volatility hits.",
                        deliverable: "Cashflow defense checklist with trigger-based actions.",
                        instruction: "Build a cashflow defense grid with spend controls, reserve rules, downside triggers, and fallback decisions for the next 30 days."
                    )
                ]
            )

        case .mobilityOps:
            return WorkspaceStudioSnapshot(
                heading: "Mobility Operations Studio",
                caption: "Route reliability, legal safety, and vehicle continuity controls",
                positioning: "Run mobility like mission-critical infrastructure: route safely, pre-wire backups, and eliminate avoidable downtime.",
                confidencePercent: confidencePercent,
                signalCount: signalCount,
                notebookCount: notebookCount,
                executiveBriefInstruction: "Create a mobility operations brief with legal route planning, fatigue safeguards, service backups, and continuity checkpoints.",
                modules: [
                    WorkspaceStudioModule(
                        symbolName: "map.fill",
                        title: "Route and Compliance Planner",
                        purpose: "Choose resilient routes with legal and overnight constraints baked in.",
                        deliverable: "Primary and backup routes with legal-safe checkpoints.",
                        instruction: "Generate a route and compliance plan with primary/backup routes, legal constraints, stop strategy, and decision triggers for rerouting."
                    ),
                    WorkspaceStudioModule(
                        symbolName: "car.side.fill",
                        title: "Vehicle Continuity Checklist",
                        purpose: "Reduce field failures with preflight and maintenance rhythm.",
                        deliverable: "Preflight and service checklist linked to route intensity.",
                        instruction: "Create a vehicle continuity checklist with preflight checks, maintenance cadence, parts/supplies list, and escalation path for failures."
                    ),
                    WorkspaceStudioModule(
                        symbolName: "exclamationmark.triangle.fill",
                        title: "Fatigue and Safety Gate",
                        purpose: "Protect operator judgment quality during long operational days.",
                        deliverable: "Fatigue thresholds with stop/continue rules and fallback options.",
                        instruction: "Build a fatigue and safety gate protocol with thresholds, stop-or-continue decision rules, recovery windows, and fallback actions."
                    )
                ]
            )

        case .deepWork:
            return WorkspaceStudioSnapshot(
                heading: "Cognitive Performance Studio",
                caption: "Deep work, cognition, and recovery systems for elite output",
                positioning: "Protect thinking quality with biological stability, focus architecture, and reflection loops that improve decisions over time.",
                confidencePercent: confidencePercent,
                signalCount: signalCount,
                notebookCount: notebookCount,
                executiveBriefInstruction: "Create a cognitive performance brief for today with deep-work blocks, cognitive load controls, recovery windows, and decision-quality checks.",
                modules: [
                    WorkspaceStudioModule(
                        symbolName: "brain.head.profile",
                        title: "Focus Block Composer",
                        purpose: "Structure high-value work blocks around current energy and blockers.",
                        deliverable: "Time-block plan with one protected deep-work sprint.",
                        instruction: "Compose a focus block schedule for today using my current energy and blockers. Include one protected deep-work sprint and pre/post block rituals."
                    ),
                    WorkspaceStudioModule(
                        symbolName: "timer",
                        title: "Cognitive Load Audit",
                        purpose: "Identify overload sources and remove friction before execution.",
                        deliverable: "Load audit with removal actions and attention safeguards.",
                        instruction: "Run a cognitive load audit. Identify the top overload sources, what to remove/defer, and attention safeguards to maintain decision quality."
                    ),
                    WorkspaceStudioModule(
                        symbolName: "book.closed.fill",
                        title: "Decision Reflection Loop",
                        purpose: "Capture lessons from recent decisions to improve future execution.",
                        deliverable: "Reflection template with one improvement experiment.",
                        instruction: "Generate a decision reflection loop for today with prompts, one key lesson, and one experiment to improve tomorrow's execution quality."
                    )
                ]
            )

        case .innovation:
            return WorkspaceStudioSnapshot(
                heading: "Innovation Systems Studio",
                caption: "Hypothesis, prototyping, and validation controls for fast safe shipping",
                positioning: "Ship innovation as a system: explicit hypotheses, constrained prototypes, and rapid validation with reliability gates.",
                confidencePercent: confidencePercent,
                signalCount: signalCount,
                notebookCount: notebookCount,
                executiveBriefInstruction: "Create an innovation systems brief with hypothesis prioritization, bounded prototyping, validation milestones, and reliability gates.",
                modules: [
                    WorkspaceStudioModule(
                        symbolName: "atom",
                        title: "Hypothesis Stack Builder",
                        purpose: "Rank what to test first based on leverage and evidence strength.",
                        deliverable: "Ranked hypothesis stack with confidence and test scope.",
                        instruction: "Build a ranked hypothesis stack for current innovation goals. Include confidence, impact potential, and smallest safe test for each hypothesis."
                    ),
                    WorkspaceStudioModule(
                        symbolName: "shippingbox.fill",
                        title: "Prototype Gate Runner",
                        purpose: "Move from concept to bounded prototype without uncontrolled risk.",
                        deliverable: "Prototype plan with scope, constraints, and safety gates.",
                        instruction: "Design a prototype gate plan from concept to first prototype. Include scope boundaries, reliability gates, and criteria to proceed or pause."
                    ),
                    WorkspaceStudioModule(
                        symbolName: "checklist.checked",
                        title: "Validation and Launch Matrix",
                        purpose: "Convert prototype outputs into launch-quality evidence.",
                        deliverable: "Validation matrix with metrics, thresholds, and launch decision.",
                        instruction: "Generate a validation and launch matrix with key metrics, pass/fail thresholds, field validation steps, and launch decision criteria."
                    )
                ]
            )
        }
    }
}

private struct WorkspaceStudioSnapshot {
    let heading: String
    let caption: String
    let positioning: String
    let confidencePercent: Int
    let signalCount: Int
    let notebookCount: Int
    let executiveBriefInstruction: String
    let modules: [WorkspaceStudioModule]
}

private struct WorkspaceStudioModule: Identifiable {
    let symbolName: String
    let title: String
    let purpose: String
    let deliverable: String
    let instruction: String

    var id: String { title }
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
