import SwiftUI
import WebKit

// MARK: - Navigation Enum
enum DashboardSection: String, CaseIterable, Identifiable {
    case command, aiChat, aiGuide, survey, concierge, code, workspaces
    case execution, memory, mobility, world, nature, access, plans, output, visualization, operations, rnd

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .command: return "Home"
        case .aiChat: return "AI Chat"
        case .aiGuide: return "AI Guide"
        case .survey: return "Survey"
        case .concierge: return "Concierge"
        case .code: return "Code"
        case .workspaces: return "Workspaces"
        case .execution: return "Execution"
        case .memory: return "Memory"
        case .mobility: return "Travel"
        case .world: return "World Monitor"
        case .nature: return "Nature Monitor"
        case .access: return "Access"
        case .plans: return "Plans"
        case .output: return "Runtime"
        case .visualization: return "Visualization"
        case .operations: return "Operations"
        case .rnd: return "R&D"
        }
    }

    var icon: String {
        switch self {
        case .command: return "sparkles.square.filled.on.square"
        case .aiChat: return "message.badge.waveform"
        case .aiGuide: return "book.closed"
        case .survey: return "point.3.connected.trianglepath.dotted"
        case .concierge: return "message.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .workspaces: return "folder"
        case .execution: return "bolt.heart"
        case .memory: return "brain.head.profile"
        case .mobility: return "airplane"
        case .world: return "globe.europe.africa.fill"
        case .nature: return "leaf.fill"
        case .access: return "person.badge.key"
        case .plans: return "creditcard"
        case .output: return "terminal"
        case .visualization: return "cube.transparent"
        case .operations: return "command.circle"
        case .rnd: return "cpu"
        }
    }
}

// MARK: - Root Dashboard
struct RootDashboardView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var selectedSection: DashboardSection? = .command

    var body: some View {
        let visibleSections = DashboardSection.allCases.filter {
            $0 != .execution
                && $0 != .concierge
                && $0 != .workspaces
                && $0 != .rnd
                && ($0 != .output || session.canViewRuntimeDiagnostics)
        }
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Text("BLACKHAVEN")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.primary.opacity(0.88))
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .background(Color.clear)

                List(visibleSections, selection: $selectedSection) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.icon)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                }
                .listStyle(.sidebar)
                .environment(\.defaultMinListRowHeight, 32)
            }
            .navigationTitle("")
            .navigationSplitViewColumnWidth(min: 180, ideal: 204, max: 220)
        } detail: {
            // Main Content Area
            ZStack {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

                switch selectedSection {
                case .command:
                    CommandCenterCard()
                case .aiChat:
                    AIChatCard(initialMode: .chat)
                case .aiGuide:
                    AIGuideCard()
                case .survey:
                    AdaptiveSurveyCard()
                case .concierge:
                    AIChatCard(initialMode: .chat)
                case .code:
                    CodingWorkspaceCard()
                case .workspaces:
                    AIChatCard(initialMode: .projects)
                case .execution:
                    CommandCenterCard()
                case .memory:
                    NotesCard()
                case .mobility:
                    MobilityOpsCard()
                case .world:
                    WorldMonitorCard()
                case .nature:
                    NatureMonitorCard()
                case .access:
                    AppleSignInCard()
                case .plans:
                    SubscriptionCard()
                case .output:
                    SystemOutputCard()
                case .visualization:
                    VisualizationStudioCard()
                case .operations:
                    OperationsWarRoomCard()
                case .rnd:
                    AIChatCard(initialMode: .rnd)
                case .none:
                    VStack {
                        Image(systemName: "square.dashed")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)
                        Text("Select a module")
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: session.localAISetupHandoffNonce) { _, _ in
            selectedSection = session.surveyAnswerCount == 0 ? .survey : .command
        }
        .onAppear {
            session.consumePendingGUIValidationLaunchRequestIfNeeded()
        }
        .onChange(of: session.guiValidationRequestedSectionRawValue) { _, rawValue in
            guard let rawValue, let target = DashboardSection(rawValue: rawValue) else { return }
            selectedSection = target
        }
        .onChange(of: session.canViewRuntimeDiagnostics) { _, canView in
            if !canView && selectedSection == .output {
                selectedSection = .command
            }
        }
        .sheet(isPresented: $session.showRemoteTransferTutorial) {
            RemoteTransferTutorialSheet {
                selectedSection = .command
                session.dismissRemoteTransferTutorial()
            }
        }
        .overlay(alignment: .topTrailing) {
            if session.guiValidationIsRunning || !session.guiValidationLogs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.guiValidationIsRunning ? "GUI Validation Running" : "GUI Validation")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AtlasTheme.textPrimary)
                    if !session.guiValidationCurrentStep.isEmpty {
                        Text(session.guiValidationCurrentStep)
                            .font(.caption)
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }
                    ForEach(session.guiValidationLogs.prefix(6), id: \.self) { line in
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(AtlasTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(12)
                .frame(width: 320, alignment: .leading)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AtlasTheme.border, lineWidth: 1)
                )
                .padding(.top, 16)
                .padding(.trailing, 16)
            }
        }
    }
}

private struct AIChatCard: View {
    enum Mode: String, CaseIterable, Identifiable {
        case chat
        case projects
        case rnd

        var id: String { rawValue }

        var title: String {
            switch self {
            case .chat: return "Chat"
            case .projects: return "Projects"
            case .rnd: return "R&D Studio"
            }
        }
    }

    @State private var selectedMode: Mode

    init(initialMode: Mode = .chat) {
        _selectedMode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI Chat")
                        .font(.title2.weight(.bold))
                    Text("Unified local-first chat surface for concierge work, project threads, and agentic R&D execution.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("AI Chat Mode", selection: $selectedMode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.regularMaterial)

            Divider()

            Group {
                switch selectedMode {
                case .chat:
                    PromptQueueCard()
                case .projects:
                    WorkspacesCard()
                case .rnd:
                    RAndDStudioCard()
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct RAndDStudioCard: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showSimpleSummary = false
    @State private var refreshToken = UUID()

    private let productTypeOptions = [
        ("mechanical_vehicle", "Mechanical Vehicle"),
        ("vehicle_part", "Vehicle Part"),
        ("mechanical_product", "Mechanical Product"),
        ("electronic_product", "Electronic Product"),
        ("pcb_assembly", "PCB / KiCad Assembly"),
        ("general_product", "General Product"),
        ("auto", "Auto Detect"),
    ]
    private let documentTypeOptions = [
        ("manufacturing_build_guide", "Manufacturing Build Guide"),
        ("module_assembly_guide", "Module Assembly Guide"),
        ("service_manual", "Service Manual"),
        ("repair_guide", "Repair Guide"),
        ("qa_inspection_checklist", "QA / Inspection Checklist"),
        ("public_project_story", "Public Project Story"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("R&D Studio")
                        .font(.largeTitle.weight(.bold))
                    Text("Local-first mechanical design orchestration with staged approvals, research context, package review, and read-only assembly scenes.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                AtlasPanel(heading: "Prompt Intake", caption: "Detailed product or vehicle request plus local research/planning context") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Atlas will use your prompt, account memory/history, internal retrieval, academic research results, and an optional local planning note before drafting a technical plan.")
                            .foregroundStyle(AtlasTheme.textSecondary)

                        Picker("Product Type", selection: $session.rAndDSelectedProductType) {
                            ForEach(productTypeOptions, id: \.0) { option in
                                Text(option.1).tag(option.0)
                            }
                        }

                        TextEditor(text: $session.rAndDPromptDraft)
                            .frame(minHeight: 160)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AtlasTheme.cardStrong)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AtlasTheme.border, lineWidth: 1)
                            )

                        HStack(spacing: 12) {
                            Button(session.rAndDIsWorking ? "Planning..." : "Draft Technical Plan") {
                                Task { await session.createRAndDJob() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(session.rAndDIsWorking)

                            Text(session.rAndDStatusLine)
                                .font(.footnote)
                                .foregroundStyle(AtlasTheme.textSecondary)
                        }
                    }
                }

                AtlasPanel(heading: "Jobs", caption: "Recent R&D jobs in this desktop session") {
                    if session.rAndDJobs.isEmpty {
                        Text("No R&D jobs yet. Start by drafting a technical plan from a detailed prompt.")
                            .foregroundStyle(AtlasTheme.textSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(session.rAndDJobs) { job in
                                Button {
                                    session.selectedRAndDJobID = job.jobID
                                    Task { await session.refreshRAndDSelectedJobDetails() }
                                } label: {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(job.productType.replacingOccurrences(of: "_", with: " ").capitalized)
                                                .font(.headline)
                                                .foregroundStyle(AtlasTheme.textPrimary)
                                            Text("\(job.currentStage.rawValue) · \(job.progressPercent)% complete · \(job.eta.estimatedRemainingMinutes)m remaining")
                                                .font(.caption)
                                                .foregroundStyle(AtlasTheme.textSecondary)
                                            Text(job.designDomain.replacingOccurrences(of: "_", with: " "))
                                                .font(.caption2)
                                                .foregroundStyle(AtlasTheme.textSecondary)
                                        }
                                        Spacer()
                                        if session.selectedRAndDJobID == job.jobID {
                                            Text("Selected")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(AtlasTheme.accentWarm)
                                        }
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(AtlasTheme.cardStrong)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let job = session.selectedRAndDJob {
                    AtlasPanel(heading: "Plan Review", caption: "Technical plan, simpler summary, and approval controls") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Show simple-language summary", isOn: $showSimpleSummary)
                                .toggleStyle(.switch)

                            Text(showSimpleSummary ? (job.latestPlan?.simpleSummary ?? "No simple summary yet.") : (job.latestPlan?.userExplanation ?? "No technical plan yet."))
                                .foregroundStyle(AtlasTheme.textSecondary)

                            if let latestPlan = job.latestPlan, !latestPlan.blockingIssues.isEmpty {
                                Text("Blocking issues: \(latestPlan.blockingIssues.joined(separator: " | "))")
                                    .foregroundStyle(.red.opacity(0.85))
                            }

                            TextEditor(text: $session.rAndDPlanRevisionDraft)
                                .frame(minHeight: 100)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(AtlasTheme.cardStrong)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(AtlasTheme.border, lineWidth: 1)
                                )

                            HStack(spacing: 12) {
                                Button("Revise Plan") {
                                    Task { await session.reviseSelectedRAndDPlan() }
                                }
                                .buttonStyle(.bordered)

                                Button("Approve Plan") {
                                    Task { await session.approveSelectedRAndDPlan() }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }

                    AtlasPanel(heading: "Execution Dashboard", caption: "Stage status, live ETA, artifacts, and change controls") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Current stage: \(job.currentStage.rawValue)")
                                .font(.headline)
                            Text("Design domain: \(job.designDomain.replacingOccurrences(of: "_", with: " ")) · Progress: \(job.progressPercent)%")
                                .foregroundStyle(AtlasTheme.textSecondary)
                            Text("ETA: \(job.eta.estimatedRemainingMinutes)m remaining · bottleneck: \(job.eta.currentBottleneck) · confidence: \(job.eta.confidenceLabel)")
                                .foregroundStyle(AtlasTheme.textSecondary)
                            Text(job.autoRunEnabled ? "Background execution is running." : (job.waitingOnUser ? "Waiting for your input." : "Execution idle."))
                                .foregroundStyle(job.autoRunEnabled ? AtlasTheme.accentWarm : AtlasTheme.textSecondary)
                            Text(job.latestValidationSummary)
                                .foregroundStyle(AtlasTheme.textSecondary)

                            HStack(spacing: 16) {
                                Text("Queued: \(job.partCounts.queued)")
                                Text("Blocked: \(job.partCounts.blocked)")
                                Text("Completed: \(job.partCounts.completed)")
                            }
                            .font(.caption)
                            .foregroundStyle(AtlasTheme.textSecondary)

                            HStack(spacing: 12) {
                                Button(job.waitingOnUser ? "Resume Execution" : "Resume Execution") {
                                    Task { await session.approveSelectedRAndDStage() }
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Pause After Current Stage") {
                                    Task { await session.pauseSelectedRAndDExecution() }
                                }
                                .buttonStyle(.bordered)

                                Button("Refresh") {
                                    Task { await session.refreshRAndDSelectedJobDetails() }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    AtlasPanel(heading: "Model Routing", caption: "How the macOS app should use local and frontier models for this job") {
                        VStack(alignment: .leading, spacing: 10) {
                            routingRows(title: "Local-only", items: job.routingSummary.localOnlyTasks)
                            routingRows(title: "Gemini escalations", items: job.routingSummary.geminiEscalatedTasks)
                            routingRows(title: "GPT escalations", items: job.routingSummary.gptEscalatedTasks)
                            routingRows(title: "CAD / simulation executors", items: job.routingSummary.executorTasks)
                        }
                    }

                    AtlasPanel(heading: "Governance", caption: "Requirements, decisions, reviews, reports, approvals, and baselines") {
                        if let governance = session.rAndDGovernance {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Readiness: \(governance.summary.readinessStatus) · Requirements: \(governance.summary.requirementCount) · Decisions: \(governance.summary.decisionCount) · Evidence: \(governance.summary.evidenceCount)")
                                    .foregroundStyle(AtlasTheme.textSecondary)
                                Text("Reports: \(governance.summary.reportCount) · Approvals: \(governance.summary.approvalCount) · Unresolved: \(governance.summary.unresolvedItemCount)")
                                    .foregroundStyle(AtlasTheme.textSecondary)

                                HStack(spacing: 12) {
                                    Button("Generate Compliance Packet") {
                                        Task { await session.generateSelectedRAndDComplianceReport() }
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("Record Review") {
                                        Task { await session.recordSelectedRAndDReview(status: "in_review") }
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Approve + Baseline") {
                                        Task { await session.recordSelectedRAndDApproval(createBaseline: true) }
                                    }
                                    .buttonStyle(.bordered)
                                }

                                TextField("Report title (optional)", text: $session.rAndDReportTitleDraft)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Review note", text: $session.rAndDReviewNoteDraft)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Approval comment", text: $session.rAndDApprovalCommentDraft)
                                    .textFieldStyle(.roundedBorder)
                                HStack(spacing: 12) {
                                    TextField("Reviewer name", text: $session.rAndDApprovalReviewerName)
                                        .textFieldStyle(.roundedBorder)
                                    TextField("Reviewer role", text: $session.rAndDApprovalReviewerRole)
                                        .textFieldStyle(.roundedBorder)
                                }

                                governanceList(title: "Requirements", items: governance.requirements.prefix(4).map { "\($0.requirementID) · \($0.status) · \($0.description)" })
                                governanceList(title: "Decisions", items: governance.decisions.prefix(3).map { "\($0.decisionID) · \($0.status) · \($0.title)" })
                                governanceList(title: "Reports", items: governance.reports.prefix(3).map { "\($0.reportID) · \($0.status) · \($0.title)" })
                                governanceList(title: "Approvals", items: governance.approvals.prefix(3).map { "\($0.approvalID) · \($0.authorityKind) · \($0.approvalState)" })
                                governanceList(title: "Baselines", items: governance.baselines.prefix(2).map { "\($0.baselineID) · \($0.status) · \($0.snapshotHash.prefix(12))" })
                            }
                        } else {
                            Text("Governance state will load with the selected job.")
                                .foregroundStyle(AtlasTheme.textSecondary)
                        }
                    }

                    AtlasPanel(heading: "Documentation", caption: "Generate manufacturing, service, repair, QA, and project-story PDFs from structured R&D state") {
                        VStack(alignment: .leading, spacing: 12) {
                            if let doctrine = session.rAndDDoctrine {
                                Text("Doctrine profile: \(doctrine.profile.title)")
                                    .font(.headline)
                                if !session.rAndDMajorDoctrineFailures.isEmpty {
                                    Text("Major doctrine blockers: \(session.rAndDMajorDoctrineFailures.map(\.doctrineArea).joined(separator: ", "))")
                                        .foregroundStyle(.red.opacity(0.85))
                                } else {
                                    Text("No major doctrine blockers. Public and private documentation can be generated.")
                                        .foregroundStyle(.green.opacity(0.85))
                                }
                            } else {
                                Text("Doctrine checks load with the selected job and gate private release documentation.")
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }

                            Picker("Document Type", selection: $session.rAndDSelectedDocumentType) {
                                ForEach(documentTypeOptions, id: \.0) { option in
                                    Text(option.1).tag(option.0)
                                }
                            }

                            Picker("Audience Mode", selection: $session.rAndDDocumentAudienceMode) {
                                Text("Private").tag("private")
                                Text("Public").tag("public")
                            }

                            HStack(spacing: 12) {
                                TextField("Document title", text: $session.rAndDDocumentTitleDraft)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Platform name", text: $session.rAndDDocumentPlatformNameDraft)
                                    .textFieldStyle(.roundedBorder)
                            }
                            HStack(spacing: 12) {
                                TextField("Revision", text: $session.rAndDDocumentRevisionDraft)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Author", text: $session.rAndDDocumentAuthorDraft)
                                    .textFieldStyle(.roundedBorder)
                            }
                            TextField("Purpose", text: $session.rAndDDocumentPurposeDraft)
                                .textFieldStyle(.roundedBorder)
                            TextField("Target audience", text: $session.rAndDDocumentTargetAudienceDraft)
                                .textFieldStyle(.roundedBorder)

                            HStack(spacing: 12) {
                                Button("Generate Document") {
                                    Task { await session.generateSelectedRAndDDocument() }
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Generate Core Bundle") {
                                    Task { await session.generateSelectedRAndDDocumentBundle() }
                                }
                                .buttonStyle(.bordered)

                                Button("Export Selected PDF") {
                                    Task { await session.exportSelectedRAndDDocumentToPDF() }
                                }
                                .buttonStyle(.bordered)

                                Button("Export Core Bundle") {
                                    Task { await session.exportCurrentRAndDBundleToPDFs() }
                                }
                                .buttonStyle(.bordered)
                            }

                            Text(session.rAndDDocumentPreviewStatus)
                                .font(.footnote)
                                .foregroundStyle(AtlasTheme.textSecondary)
                            if let drift = session.rAndDSelectedDocumentRevisionDriftMessage {
                                Text("Revision drift: \(drift)")
                                    .font(.caption)
                                    .foregroundStyle(.orange.opacity(0.9))
                            }

                            if !session.rAndDLastExportPath.isEmpty {
                                Text("Last export: \(session.rAndDLastExportPath)")
                                    .font(.caption)
                                    .foregroundStyle(AtlasTheme.textSecondary)
                                    .textSelection(.enabled)
                            }
                            if !session.rAndDBundleExportStatus.isEmpty {
                                Text(session.rAndDBundleExportStatus)
                                    .font(.caption)
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                            if !session.rAndDLastExportError.isEmpty {
                                Text("Last export error: \(session.rAndDLastExportError)")
                                    .font(.caption)
                                    .foregroundStyle(.red.opacity(0.85))
                            }

                            if !session.rAndDDocuments.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Generated Documents")
                                        .font(.headline)
                                    ForEach(session.rAndDDocuments.prefix(6)) { document in
                                        Button {
                                            session.selectRAndDDocument(document.documentID)
                                        } label: {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(document.title)
                                                        .font(.subheadline.weight(.semibold))
                                                        .foregroundStyle(AtlasTheme.textPrimary)
                                                    Text("\(document.documentType.replacingOccurrences(of: "_", with: " ")) · \(document.revisionLabel) · \(document.audienceMode)")
                                                        .font(.caption)
                                                        .foregroundStyle(AtlasTheme.textSecondary)
                                                }
                                                Spacer()
                                                if session.selectedRAndDDocumentID == document.documentID {
                                                    Text("Previewing")
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(AtlasTheme.accentWarm)
                                                }
                                            }
                                            .padding(10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill(AtlasTheme.cardStrong)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if !session.rAndDDocumentationBundles.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Bundles")
                                        .font(.headline)
                                    ForEach(session.rAndDDocumentationBundles.prefix(3)) { bundle in
                                        Text("\(bundle.title) · \(bundle.revisionLabel) · \(bundle.documentIDs.count) docs")
                                            .font(.caption)
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                    }
                                }
                            }

                            if !session.rAndDDocumentPreviewHTML.isEmpty {
                                RAndDDocumentPreviewWebView(html: session.rAndDDocumentPreviewHTML)
                                    .frame(minHeight: 540)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(AtlasTheme.border, lineWidth: 1)
                                    )
                            } else {
                                Text("Preview will appear here after generation or selection.")
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                        }
                    }

                    AtlasPanel(heading: "Traceability", caption: "Requirement to decision to evidence to report to approval links") {
                        if session.rAndDTraceabilityRows.isEmpty {
                            Text("Traceability rows will appear once the job has requirements and evidence.")
                                .foregroundStyle(AtlasTheme.textSecondary)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(session.rAndDTraceabilityRows.prefix(5)) { row in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(row.requirementID) · \(row.title)")
                                            .font(.headline)
                                        Text("Decisions: \(row.decisionIDs.joined(separator: ", "))")
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                        Text("Evidence: \(row.evidenceIDs.joined(separator: ", "))")
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                        Text("Reports: \(row.reportIDs.joined(separator: ", "))")
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                        if !row.unresolvedItems.isEmpty {
                                            Text("Open: \(row.unresolvedItems.joined(separator: " | "))")
                                                .foregroundStyle(.red.opacity(0.85))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    AtlasPanel(heading: "Change Requests", caption: "Part-level fixes or orchestration-level redesigns") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Target part ID for part-level fix (optional)", text: $session.rAndDTargetPartID)
                                .textFieldStyle(.roundedBorder)
                            TextEditor(text: $session.rAndDChangeRequestDraft)
                                .frame(minHeight: 90)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(AtlasTheme.cardStrong)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(AtlasTheme.border, lineWidth: 1)
                                )
                            HStack(spacing: 12) {
                                Button("Request Part Fix") {
                                    Task { await session.submitSelectedRAndDChangeRequest(scope: "part") }
                                }
                                .buttonStyle(.bordered)
                                Button("Request System Redesign") {
                                    Task { await session.submitSelectedRAndDChangeRequest(scope: "orchestration") }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    AtlasPanel(heading: "Artifacts & Inspection", caption: "What to open, what to inspect, and how to ask for changes") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Button(session.rAndDLocalExecutionIsRunning ? "Running Local CAD..." : "Run Local CAD Artifacts") {
                                    Task { await session.rerunSelectedRAndDLocalCADExecution() }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(session.rAndDLocalExecutionIsRunning)

                                Text(session.rAndDLocalExecutionStatusLine)
                                    .font(.caption)
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                            if !session.rAndDWorkspaceRootPath.isEmpty {
                                Text("Local workspace: \(session.rAndDWorkspaceRootPath)")
                                    .font(.caption)
                                    .foregroundStyle(AtlasTheme.textSecondary)
                                    .textSelection(.enabled)
                            }
                            if !session.rAndDInspectionGuide.isEmpty {
                                Text(session.rAndDInspectionGuide)
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                            ForEach(session.rAndDArtifacts.prefix(8)) { artifact in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(artifact.title) · \(artifact.format.uppercased())")
                                        .font(.headline)
                                    Text(artifact.content)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                        .lineLimit(6)
                                }
                                .padding(.vertical, 2)
                            }
                            if !session.rAndDLocalExecutionRecords.isEmpty {
                                Divider()
                                ForEach(session.rAndDLocalExecutionRecords.prefix(4)) { record in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(record.tool) · \(record.status)")
                                            .font(.headline)
                                        Text(record.detail)
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                        if !record.outputPaths.isEmpty {
                                            Text(record.outputPaths.joined(separator: "\n"))
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(AtlasTheme.textSecondary)
                                                .textSelection(.enabled)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }

                    AtlasPanel(heading: "Assembly Review", caption: "Stage assemblies, exploded-view manifests, and grouped package outputs") {
                        let assemblyArtifacts = session.rAndDLocalWorkspaceAssets.filter {
                            [
                                "assembly_stage_package",
                                "exploded_view_manifest",
                                "assembly_package",
                                "review_scene_package",
                                "assembly_stage_review_scene"
                            ].contains($0.artifactType)
                        }
                        if assemblyArtifacts.isEmpty {
                            Text("Assembly-stage packages and exploded-view manifests will appear here as execution reaches package assembly.")
                                .foregroundStyle(AtlasTheme.textSecondary)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("This is a read-only native review surface. BlackHaven materializes USD-style scene assets, assembly-stage packages, and exploded manifests here, while source-of-truth CAD stays in FreeCAD.")
                                    .foregroundStyle(AtlasTheme.textSecondary)
                                ForEach(assemblyArtifacts.prefix(8)) { artifact in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(artifact.title) · \(artifact.artifactType)")
                                            .font(.headline)
                                        Text(artifact.localPath)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                            .textSelection(.enabled)
                                        Text(artifact.preview)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                            .lineLimit(8)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(32)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: session.selectedRAndDJobID ?? refreshToken.uuidString) {
            while !Task.isCancelled {
                guard let job = session.selectedRAndDJob, job.autoRunEnabled || !job.waitingOnUser else {
                    break
                }
                try? await Task.sleep(for: .seconds(3))
                await session.refreshRAndDSelectedJobDetails()
            }
        }
    }
}

@ViewBuilder
private func routingRows(title: String, items: [String]) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.headline)
        if items.isEmpty {
            Text("No items recorded for this lane yet.")
                .foregroundStyle(AtlasTheme.textSecondary)
        } else {
            ForEach(items, id: \.self) { item in
                Text("- \(item)")
                    .foregroundStyle(AtlasTheme.textSecondary)
            }
        }
    }
}

@ViewBuilder
private func governanceList(title: String, items: [String]) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.headline)
        if items.isEmpty {
            Text("No items yet.")
                .foregroundStyle(AtlasTheme.textSecondary)
        } else {
            ForEach(items, id: \.self) { item in
                Text("- \(item)")
                    .foregroundStyle(AtlasTheme.textSecondary)
            }
        }
    }
}

private struct OperationsWarRoomCard: View {
    private let modules = [
        ("Engineering Bay", "Use the desktop for review-heavy engineering work: large model inspection, simulation launch points, and revision-aware change requests."),
        ("Swarm Canvas", "Show agent status, queues, dependencies, and failure hotspots in one place so orchestration does not disappear into logs."),
        ("Fleet Command", "Surface vehicle telemetry anomalies, maintenance risks, and customer-impacting hardware issues before they become support fires."),
        ("Factory Timeline", "Treat build sequencing as a live scheduling problem with dependency awareness, not a static spreadsheet."),
        ("Token & Cashflow Matrix", "Keep model spend, routing efficiency, and revenue impact visible enough to approve optimization changes with confidence.")
    ]

    private let readinessRows = [
        "Choose the real source of truth for agent state, fleet signals, factory events, and cost metrics.",
        "Define what the Mac can approve directly and what only escalates or drafts.",
        "Back each panel with live data before describing the war room as an operational product.",
        "Keep auditability and operator accountability visible whenever automation takes action."
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Operations War Room")
                        .font(.largeTitle.weight(.bold))
                    Text("Desktop oversight for agent orchestration, fleet awareness, factory timing, and cost-control decisions.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                AtlasPanel(heading: "Current Product Boundary", caption: "What this module is for and what it is not") {
                    Text("Atlas macOS should become the high-context workstation for operating the system, not a marketing claim that every workflow is already autonomous. The right role is oversight, diagnosis, approval, and intervention on top of automation.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                }

                AtlasPanel(heading: "Core Modules", caption: "The control surfaces this PDF is pointing toward") {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(modules, id: \.0) { module in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(module.0)
                                    .font(.headline)
                                    .foregroundStyle(AtlasTheme.textPrimary)
                                Text(module.1)
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                        }
                    }
                }

                AtlasPanel(heading: "Readiness Gates", caption: "What still needs to happen before this is a real operator desk") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(readinessRows, id: \.self) { row in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(AtlasTheme.accentWarm)
                                Text(row)
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                        }
                    }
                }
            }
            .padding(32)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct VisualizationStudioCard: View {
    private let stackRows = [
        ("Native First", "The current repo has a macOS desktop shell, but not yet a production 3D renderer. The right upgrade path is native Apple Silicon visualization instead of a heavy browser viewer."),
        ("Scene Format", "Use hierarchical USD or USDZ exports from the CAD pipeline so the app can keep part relationships intact for exploded views, review, and selective swaps."),
        ("Rendering Layer", "RealityKit or Metal should own rendering, playback, and scene interaction. The CAD source of truth stays outside the viewer."),
        ("Interactive Review", "The useful workflow is pause, inspect, comment, request a change, and pull an updated component or scene revision back into the same session.")
    ]

    private let readinessRows = [
        "Pick the first supported workflow: exploded review, cinematic walkthrough, or pause-and-comment scene editing.",
        "Define minimum Apple Silicon targets so the end-user experience is honest about memory and performance.",
        "Choose USD or USDZ export rules and keep revision IDs attached to every scene package.",
        "Treat this as a review cockpit, not as the legal or engineering source of truth."
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Visualization Studio")
                        .font(.largeTitle.weight(.bold))
                    Text("Native Apple Silicon review cockpit for large assemblies, exploded views, and live scene iteration.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                AtlasPanel(heading: "Current Product Boundary", caption: "What exists now versus what this module is preparing for") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Today, the macOS app is a desktop control surface. It does not yet ship a full RealityKit or Metal assembly viewer. This module makes the roadmap explicit without pretending the renderer is already complete.")
                            .foregroundStyle(AtlasTheme.textSecondary)

                        ForEach(stackRows, id: \.0) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.0)
                                    .font(.headline)
                                    .foregroundStyle(AtlasTheme.textPrimary)
                                Text(row.1)
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                        }
                    }
                }

                AtlasPanel(heading: "Readiness Gates", caption: "What still needs to happen before this becomes a real end-user feature") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(readinessRows, id: \.self) { row in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(AtlasTheme.accentWarm)
                                Text(row)
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                        }
                    }
                }
            }
            .padding(32)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct RemoteTransferTutorialSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.10, blue: 0.18), Color(red: 0.08, green: 0.16, blue: 0.27)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("Your desktop is the local home base")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("BlackHaven is built so a phone can hand work and files back to the desktop you already own while that machine stays on and plugged in, even when internet service is degraded or unavailable.")
                    .font(.title3)
                    .foregroundStyle(Color.white.opacity(0.92))

                tutorialLine("1. Pair your phone to this Mac with the Desktop Remote URL and pairing token in Command.")
                tutorialLine("2. Keep the destination on your own machine whenever your local network is available, including internet-down situations.")
                tutorialLine("3. Run energy-intensive local AI on infrastructure you control, including the grid, home solar, portable panels, batteries, or small wind.")
                tutorialLine("4. Use BlackHaven as an emergency prepping and management tool that stays useful when internet access drops but local power and local networking remain available.")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Why this matters")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Local-first design lets you control the energy source, keep sensitive work closer to home, and sustain heavy long-term AI workloads with backup power plus renewable generation. That makes BlackHaven more useful for resilience planning, outage response, and continuity operations.")
                        .foregroundStyle(Color.white.opacity(0.82))
                }
                .padding(16)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggested power strategy")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("We recommend pairing renewable energy generation with home backup power so this Mac can stay available for local AI and emergency coordination. Founder recommendation: EcoFlow Delta Pro 3.")
                        .foregroundStyle(Color.white.opacity(0.82))
                }
                .padding(16)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 12) {
                    Button("Open Home") {
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)

                    Text("You’ll find the pairing URL and token in Desktop Remote Control on Home.")
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .presentationDetents([.large])
    }

    private func tutorialLine(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(.leading, 2)
    }
}

// MARK: - World Monitor Card
struct WorldMonitorCard: View {
    private static let endpointStorageKey = "atlas.macos.worldmonitor.endpoint"
    private static let hostedEndpoint = "https://worldmonitor.app"
    private static let localEndpoint = "http://127.0.0.1:5173"
    static let natureSources: [NatureSignalSource] = [
        NatureSignalSource(
            title: "IUCN Red List",
            detail: "Threat status index for species and conservation categories.",
            kind: "Web",
            urlString: "https://www.iucnredlist.org/"
        ),
        NatureSignalSource(
            title: "IUCN Red List API",
            detail: "Programmatic species and category access. API key/token required.",
            kind: "API",
            urlString: "https://api.iucnredlist.org/"
        ),
        NatureSignalSource(
            title: "GBIF",
            detail: "Global biodiversity occurrence records and taxonomy references.",
            kind: "Web",
            urlString: "https://www.gbif.org/"
        ),
        NatureSignalSource(
            title: "GBIF API",
            detail: "Open species occurrence API for biodiversity monitoring workflows.",
            kind: "API",
            urlString: "https://api.gbif.org/v1/"
        ),
        NatureSignalSource(
            title: "Protected Planet (WDPA)",
            detail: "Protected area coverage and conservation boundary datasets.",
            kind: "Web",
            urlString: "https://www.protectedplanet.net/en"
        ),
        NatureSignalSource(
            title: "Global Forest Watch",
            detail: "Tree cover loss and forest pressure indicators.",
            kind: "Web",
            urlString: "https://www.globalforestwatch.org/"
        ),
        NatureSignalSource(
            title: "NASA FIRMS",
            detail: "Active fire and thermal anomaly monitoring.",
            kind: "Web",
            urlString: "https://firms.modaps.eosdis.nasa.gov/"
        ),
        NatureSignalSource(
            title: "NOAA Climate at a Glance",
            detail: "Climate trend indicators and regional anomalies.",
            kind: "Indicator",
            urlString: "https://www.ncei.noaa.gov/access/monitoring/climate-at-a-glance/"
        ),
        NatureSignalSource(
            title: "Copernicus Climate Bulletins",
            detail: "Global monthly climate bulletins and key planetary indicators.",
            kind: "Indicator",
            urlString: "https://climate.copernicus.eu/climate-bulletins"
        )
    ]
    private static let charitySources: [NatureSignalSource] = [
        NatureSignalSource(
            title: "Charity Navigator",
            detail: "Charity profiles, ratings, and accountability context.",
            kind: "Web",
            urlString: "https://www.charitynavigator.org/"
        ),
        NatureSignalSource(
            title: "Charity Navigator Data API",
            detail: "Developer access for organization/rating data (requires approved credentials).",
            kind: "API",
            urlString: "https://developer.charitynavigator.org/"
        ),
        NatureSignalSource(
            title: "Charity Navigator GraphQL API",
            detail: "Official GraphQL product channel for partner data integrations.",
            kind: "API",
            urlString: "https://www.charitynavigator.org/products-and-services/graphql-api/"
        ),
        NatureSignalSource(
            title: "CN Ratings Methodology",
            detail: "How impact/accountability dimensions are scored.",
            kind: "Method",
            urlString: "https://www.charitynavigator.org/about-us/our-methodology/ratings/"
        ),
        NatureSignalSource(
            title: "IRS EO Search",
            detail: "Federal tax-exempt lookup and filing validation.",
            kind: "Reg",
            urlString: "https://apps.irs.gov/app/eos/"
        ),
        NatureSignalSource(
            title: "ProPublica Nonprofit Explorer",
            detail: "Form 990 history, compensation, and financial trend review.",
            kind: "Data",
            urlString: "https://projects.propublica.org/nonprofits/"
        ),
        NatureSignalSource(
            title: "Candid / GuideStar",
            detail: "Program descriptions, transparency seals, and nonprofit profiles.",
            kind: "Data",
            urlString: "https://www.guidestar.org/"
        ),
        NatureSignalSource(
            title: "GiveWell Top Charities",
            detail: "Evidence-driven charity effectiveness benchmarks.",
            kind: "Impact",
            urlString: "https://www.givewell.org/charities/top-charities"
        )
    ]

    @EnvironmentObject private var session: SessionStore
    @State private var endpointURL = URL(string: Self.hostedEndpoint)!
    @State private var endpointDraft = Self.hostedEndpoint
    @State private var endpointStatusLine = "World Monitor hosted endpoint active."

    var body: some View {
        AtlasScreen(
            title: "World Monitor",
            subtitle: "Live dashboard endpoint controls, charity intelligence sources, and embedded monitoring."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                AtlasPanel(heading: "World Monitor", caption: "Live dashboard endpoint controls.") {
                    VStack(alignment: .leading, spacing: 9) {
                        TextField("World Monitor URL", text: $endpointDraft)
                            .atlasFieldStyle()
                        HStack(spacing: 8) {
                            Button("Load URL") {
                                applyEndpoint(endpointDraft)
                            }
                            Button("Use Hosted") {
                                applyEndpoint(Self.hostedEndpoint)
                            }
                            Button("Use Local Dev") {
                                applyEndpoint(Self.localEndpoint)
                            }
                        }
                        Text(endpointStatusLine)
                            .font(.footnote)
                            .foregroundStyle(AtlasTheme.textSecondary)
                        Text("Local dev tip: run npm install and npm run dev in /Users/avrohom/Downloads/BlackHaven/worldmonitor-main.")
                            .font(.caption)
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }
                }

                AtlasPanel(heading: "Charity Impact Monitor", caption: "Track progress, gaps, and funding need using Charity Navigator and nonprofit transparency sources.") {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Recommended scorecard dimensions:")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AtlasTheme.textPrimary)
                        Text("Impact progress trend · Where outcomes are lacking · Funding gap (needed vs secured) · Charity Navigator accountability signal.")
                            .font(.caption)
                            .foregroundStyle(AtlasTheme.textSecondary)
                        Divider()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Self.charitySources) { source in
                                    HStack(alignment: .top, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(source.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(AtlasTheme.textPrimary)
                                            Text(source.detail)
                                                .font(.caption)
                                                .foregroundStyle(AtlasTheme.textSecondary)
                                        }
                                        Spacer(minLength: 8)
                                        if let url = URL(string: source.urlString) {
                                            Link(source.kind, destination: url)
                                                .font(.caption.weight(.semibold))
                                        }
                                    }
                                    if source.id != Self.charitySources.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 220)
                    }
                }

                AtlasPanel(heading: "Live Dashboard", caption: "Embedded worldmonitor.app or local endpoint.") {
                    WorldMonitorWebView(url: endpointURL)
                        .frame(minHeight: 280)
                }
            }
        }
        .onAppear {
            restoreEndpoint()
        }
    }

    // MARK: Logic
    private func restoreEndpoint() {
        let saved = UserDefaults.standard.string(forKey: Self.endpointStorageKey) ?? Self.hostedEndpoint
        applyEndpoint(saved, persist: false)
    }

    private func applyEndpoint(_ raw: String, persist: Bool = true) {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            endpointURL = URL(string: Self.hostedEndpoint)!
            endpointDraft = Self.hostedEndpoint
            endpointStatusLine = "World Monitor hosted endpoint active."
            return
        }

        if !normalized.contains("://") {
            normalized = "https://\(normalized)"
        }

        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            endpointURL = URL(string: Self.hostedEndpoint)!
            endpointDraft = Self.hostedEndpoint
            endpointStatusLine = "Invalid endpoint; switched back to hosted World Monitor."
            if persist {
                UserDefaults.standard.set(Self.hostedEndpoint, forKey: Self.endpointStorageKey)
            }
            return
        }

        endpointURL = url
        endpointDraft = normalized
        let host = url.host?.lowercased() ?? ""
        if host == "127.0.0.1" || host == "localhost" {
            endpointStatusLine = "World Monitor local dev endpoint active."
        } else {
            endpointStatusLine = "World Monitor endpoint active: \(url.absoluteString)"
        }
        if persist {
            UserDefaults.standard.set(normalized, forKey: Self.endpointStorageKey)
        }
    }
}

struct NatureMonitorCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AtlasPanel(heading: "Nature Signal Stack v2", caption: "Live top-5 signals + risk score + alert thresholds.") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("Risk: \(session.natureRiskScore)/100 (\(session.natureRiskBand))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AtlasTheme.textPrimary)
                        Button("Refresh now") {
                            Task { await session.refreshNatureSignalStackNow(sendNotifications: true) }
                        }
                    }
                    Text("Alert thresholds: elevated >= \(session.natureElevatedThreshold), critical >= \(session.natureCriticalThreshold)")
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textSecondary)
                    Text(session.natureAlertSummary)
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textSecondary)

                    if session.natureSignalTiles.isEmpty {
                        Text("No live tiles yet. Tap refresh to fetch current nature signals.")
                            .font(.caption)
                            .foregroundStyle(AtlasTheme.textSecondary)
                    } else {
                        ForEach(session.natureSignalTiles) { tile in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tile.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    Text(tile.metric)
                                        .font(.caption)
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(tile.trend)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                    Text(tile.severity)
                                        .font(.caption2)
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                }
                            }
                            if tile.id != session.natureSignalTiles.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }

            AtlasPanel(heading: "Critical Indicators", caption: "IUCN Red List + high-value wildlife/environment indicators and APIs.") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(WorldMonitorCard.natureSources) { source in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    Text(source.detail)
                                        .font(.caption)
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                }
                                Spacer(minLength: 8)
                                if let url = URL(string: source.urlString) {
                                    Link(source.kind, destination: url)
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            if source.id != WorldMonitorCard.natureSources.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(18)
    }
}

private struct RAndDDocumentPreviewWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}

struct NatureSignalSource: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let kind: String
    let urlString: String
}

// MARK: - WebView Representable
private struct WorldMonitorWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if #available(macOS 13.0, *) {
            config.defaultWebpagePreferences.preferredContentMode = .desktop
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.enclosingScrollView?.hasVerticalScroller = true
        webView.enclosingScrollView?.hasHorizontalScroller = true
        webView.enclosingScrollView?.drawsBackground = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}
