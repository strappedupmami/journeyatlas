import XCTest
@testable import AtlasMasaMacOS

final class AtlasMasaMacOSTests: XCTestCase {
    private func offlineClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 0.01
        config.timeoutIntervalForResource = 0.01
        config.waitsForConnectivity = false
        return APIClient(
            baseURL: URL(string: "https://example.invalid")!,
            session: URLSession(configuration: config)
        )
    }

    @MainActor
    private func testStore() -> SessionStore {
        SessionStore(api: offlineClient(), launchBehavior: .testing)
    }

    private func sampleRAndDJob() -> RAndDJobResponse {
        RAndDJobResponse(
            jobID: "job-1",
            productType: "mechanical_vehicle",
            designDomain: "mechanical_cad",
            currentStage: .reviewHandoff,
            waitingOnUser: true,
            autoRunEnabled: false,
            pausedAfterCurrentStage: false,
            acceptedPlanVersion: 2,
            latestPlan: RAndDPlan(
                version: 2,
                generatedAt: "2026-04-01T00:00:00Z",
                goals: ["Ship a serviceable trailer platform"],
                constraints: ["Low tool count", "Affordable architecture"],
                risks: ["Service access drift"],
                assumptions: ["Use common hardware", "Avoid proprietary repair tooling"],
                requiredResearchDomains: ["manufacturing", "service"],
                proposedParts: ["Frame", "Utility module"],
                executionStages: [],
                userExplanation: "Detailed plan",
                simpleSummary: "Simple summary",
                citations: [],
                executable: true,
                blockingIssues: []
            ),
            eta: RAndDEta(
                estimatedTotalMinutes: 120,
                estimatedRemainingMinutes: 15,
                currentStageEstimatedMinutes: 10,
                confidenceLabel: "medium",
                currentBottleneck: "review",
                slippageReason: "none"
            ),
            partCounts: RAndDPartCounts(queued: 0, running: 0, blocked: 0, completed: 2),
            riskFlags: ["human review required"],
            latestValidationSummary: "Validation ready",
            latestArtifacts: [],
            routingSummary: RAndDRoutingSummary(localOnlyTasks: [], geminiEscalatedTasks: [], gptEscalatedTasks: [], executorTasks: []),
            governanceSummary: RAndDGovernanceSummary(
                requirementCount: 1,
                decisionCount: 1,
                evidenceCount: 1,
                reportCount: 0,
                approvalCount: 0,
                unresolvedItemCount: 1,
                readinessStatus: "needs_review"
            ),
            progressPercent: 84
        )
    }

    func testScaffoldBootstraps() {
        XCTAssertTrue(true)
    }

    func testResolvedLaunchBehaviorTreatsXCTestAsTesting() {
        let behavior = SessionStore.resolvedLaunchBehavior(
            environment: ["XCTestConfigurationFilePath": "/tmp/session.xctestconfiguration"]
        )

        XCTAssertEqual(behavior, .testing)
    }

    func testNormalizeCADExecutablePathResolvesAppBundles() {
        XCTAssertEqual(
            SessionStore.normalizeCADExecutablePath("/Applications/FreeCAD.app"),
            "/Applications/FreeCAD.app/Contents/MacOS/FreeCAD"
        )
        XCTAssertEqual(
            SessionStore.normalizeCADExecutablePath("~/Applications/KiCad.app"),
            ("~/Applications/KiCad.app" as NSString)
                .expandingTildeInPath + "/Contents/MacOS/kicad-cli"
        )
    }

    func testDeriveFreeCADPathsFindsCompanionCmdFromAppBundle() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlas-freecad-\(UUID().uuidString)", isDirectory: true)
        let freeCADApp = tempRoot.appendingPathComponent("FreeCAD.app", isDirectory: true)
        let macOSDir = freeCADApp.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let binDir = freeCADApp.appendingPathComponent("Contents/Resources/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        let freeCADURL = macOSDir.appendingPathComponent("FreeCAD")
        let freeCADCmdURL = binDir.appendingPathComponent("FreeCADCmd")
        FileManager.default.createFile(atPath: freeCADURL.path, contents: Data())
        FileManager.default.createFile(atPath: freeCADCmdURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: freeCADURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: freeCADCmdURL.path)

        let derivedFromApp = SessionStore.deriveFreeCADPaths(from: freeCADApp.path)
        XCTAssertEqual(derivedFromApp.freeCAD, freeCADURL.path)
        XCTAssertEqual(derivedFromApp.freeCADCmd, freeCADCmdURL.path)

        let derivedFromCmd = SessionStore.deriveFreeCADPaths(from: freeCADCmdURL.path)
        XCTAssertEqual(derivedFromCmd.freeCAD, freeCADURL.path)
        XCTAssertEqual(derivedFromCmd.freeCADCmd, freeCADCmdURL.path)
    }

    func testLocalCADExecutableArtifactSelectionRequiresPythonCADSource() {
        XCTAssertTrue(SessionStore.isLocalCADExecutableArtifact(artifactType: "cad_source", format: "py"))
        XCTAssertFalse(SessionStore.isLocalCADExecutableArtifact(artifactType: "blueprint_package", format: "md"))
        XCTAssertFalse(SessionStore.isLocalCADExecutableArtifact(artifactType: "cad_source", format: "fcstd"))
    }

    @MainActor
    func testNextLayerArtifactsGenerateFromManualState() {
        let store = testStore()
        store.deleteLocalMemory()
        store.dailyPriority = "Ship the desktop-first release."
        store.midTermGoal = "Harden BlackHaven for real end users."
        store.checkInMood = "Overloaded"
        store.checkInEnergy = 2
        store.checkInBlockers = "Need to verify onboarding, installer readiness, and one blocker at a time."

        store.applyDailyCheckIn()

        XCTAssertNotNil(store.operatorStateSnapshot)
        XCTAssertEqual(store.operatorStateSnapshot?.mode, .lowEnergyMode)
        XCTAssertNotNil(store.currentSupportRecommendation)
        XCTAssertNotNil(store.currentActivitySuggestion)
        XCTAssertNotNil(store.currentItineraryPlan)
        XCTAssertNotNil(store.activeChecklistPlan)
        XCTAssertFalse(store.activeChecklistPlan?.steps.isEmpty ?? true)
    }

    @MainActor
    func testOfflineRAndDDocumentFallbackBuildsPreviewableRecord() {
        let store = testStore()
        store.deleteLocalMemory()
        let job = sampleRAndDJob()
        store.rAndDJobs = [job]
        store.selectedRAndDJobID = job.jobID
        store.rAndDArtifacts = [
            RAndDArtifact(
                artifactID: "artifact-1",
                partID: nil,
                artifactType: "assembly_package",
                title: "Assembly package",
                format: "md",
                content: "Assembly content",
                createdAt: "2026-04-01T00:00:00Z"
            )
        ]
        store.rAndDDoctrine = RAndDDoctrineResponse(
            jobID: job.jobID,
            profile: RAndDDoctrineProfile(
                profileID: "profile-1",
                title: "BlackHaven Vehicle Doctrine",
                principles: ["manufacturability", "serviceability"],
                updatedAt: "2026-04-01T00:00:00Z"
            ),
            checks: [
                RAndDDoctrineCheck(
                    checkID: "check-1",
                    doctrineArea: "manufacturability",
                    severity: "warning",
                    passed: false,
                    explanation: "Too much complexity",
                    suggestedFix: "Simplify the join strategy",
                    linkedModuleIDs: [],
                    linkedArtifactIDs: [],
                    linkedDecisionIDs: [],
                    gating: false,
                    updatedAt: "2026-04-01T00:00:00Z"
                )
            ],
            moduleDefinitions: [],
            toolRequirements: [
                RAndDToolRequirement(toolID: "tool-1", name: "Socket set", category: "mechanical", reason: "Common fasteners", commonality: "common")
            ],
            bomItems: [
                RAndDBomItem(bomID: "bom-1", name: "Common structural stock", quantity: "1 set", notes: "Use stocked sections", moduleID: nil)
            ],
            assemblySteps: [],
            serviceAccessPoints: [],
            inspectionChecklistItems: [],
            revisionHistory: []
        )

        let document = store.buildOfflineFallbackRAndDDocument()

        XCTAssertNotNil(document)
        XCTAssertEqual(store.selectedRAndDDocument?.documentType, "manufacturing_build_guide")
        XCTAssertFalse(store.rAndDDocumentPreviewHTML.isEmpty)
        XCTAssertTrue(store.rAndDDocumentPreviewHTML.contains("BlackHaven R&amp;D"))
    }

    @MainActor
    func testMajorDoctrineFailuresAreDetectedForReleaseGating() {
        let store = testStore()
        store.rAndDDoctrine = RAndDDoctrineResponse(
            jobID: "job-1",
            profile: RAndDDoctrineProfile(profileID: "profile-1", title: "Doctrine", principles: [], updatedAt: "2026-04-01T00:00:00Z"),
            checks: [
                RAndDDoctrineCheck(
                    checkID: "major-1",
                    doctrineArea: "service_access",
                    severity: "major",
                    passed: false,
                    explanation: "Requires teardown",
                    suggestedFix: "Move service points to removable panel",
                    linkedModuleIDs: [],
                    linkedArtifactIDs: [],
                    linkedDecisionIDs: [],
                    gating: true,
                    updatedAt: "2026-04-01T00:00:00Z"
                ),
                RAndDDoctrineCheck(
                    checkID: "info-1",
                    doctrineArea: "accessible_documentation",
                    severity: "info",
                    passed: true,
                    explanation: "Plain language",
                    suggestedFix: "",
                    linkedModuleIDs: [],
                    linkedArtifactIDs: [],
                    linkedDecisionIDs: [],
                    gating: false,
                    updatedAt: "2026-04-01T00:00:00Z"
                )
            ],
            moduleDefinitions: [],
            toolRequirements: [],
            bomItems: [],
            assemblySteps: [],
            serviceAccessPoints: [],
            inspectionChecklistItems: [],
            revisionHistory: []
        )

        XCTAssertEqual(store.rAndDMajorDoctrineFailures.count, 1)
        XCTAssertEqual(store.rAndDMajorDoctrineFailures.first?.doctrineArea, "service_access")
    }

    @MainActor
    func testSelectedDocumentRevisionDriftIsSurfaced() {
        let store = testStore()
        let job = sampleRAndDJob()
        store.rAndDJobs = [job]
        store.selectedRAndDJobID = job.jobID
        store.rAndDDoctrine = RAndDDoctrineResponse(
            jobID: job.jobID,
            profile: RAndDDoctrineProfile(profileID: "profile-1", title: "Doctrine", principles: [], updatedAt: "2026-04-01T00:00:00Z"),
            checks: [],
            moduleDefinitions: [],
            toolRequirements: [],
            bomItems: [],
            assemblySteps: [],
            serviceAccessPoints: [],
            inspectionChecklistItems: [],
            revisionHistory: [
                RAndDRevisionRecord(revisionID: "rev-1", label: "R3-P2", sourcePlanVersion: 2, reason: "updated", createdAt: "2026-04-01T00:00:00Z")
            ]
        )
        store.rAndDDocuments = [
            RAndDDocumentRecord(
                documentID: "doc-1",
                documentType: "service_manual",
                audienceMode: "private",
                title: "Service Manual",
                projectName: "BlackHaven R&D",
                platformName: "Trailer",
                revisionLabel: "R1-P1",
                sourceJobID: job.jobID,
                sourcePlanVersion: 1,
                artifactIDs: [],
                moduleIDs: [],
                purpose: "Purpose",
                targetAudience: "Audience",
                author: "Author",
                assumptions: [],
                safetyNotes: [],
                toolsRequired: [],
                materialsRequired: [],
                bomSummary: [],
                sections: [],
                manufacturabilityNotes: [],
                affordabilityNotes: [],
                repairabilityNotes: [],
                serviceabilityNotes: [],
                publicBenefitRationale: "Benefit",
                exports: [],
                createdAt: "2026-04-01T00:00:00Z",
                updatedAt: "2026-04-01T00:00:00Z"
            )
        ]
        store.selectedRAndDDocumentID = "doc-1"

        XCTAssertNotNil(store.rAndDSelectedDocumentRevisionDriftMessage)
        XCTAssertTrue(store.rAndDSelectedDocumentRevisionDriftMessage?.contains("source plan v1 is behind current accepted plan v2") == true)
    }

    @MainActor
    func testWorkspaceMemoryCarriesAcrossLanes() {
        let store = testStore()
        store.deleteLocalMemory()
        store.dailyPriority = "Close two enterprise partnerships this week."
        store.midTermGoal = "Harden emergency command workflows."
        store.longTermVision = "Scale Atlas travel design infrastructure."
        store.checkInMood = "Focused"
        store.checkInEnergy = 4
        store.checkInWentToGymToday = true
        store.checkInMadeMoneyToday = true
        store.checkInMoneySignalNote = "Closed one client call today."
        store.workspaceMode = "Travel and enterprise operations"
        store.notes = [
            UserNote(noteID: "n1", title: "Emergency prep", content: "Build crisis and triage command checklist."),
            UserNote(noteID: "n2", title: "Revenue sprint", content: "Run pricing + outreach + close flow."),
            UserNote(noteID: "n3", title: "Innovation loop", content: "Prototype systems architecture for mobility.")
        ]

        store.applyDailyCheckIn()

        XCTAssertFalse(store.workspaceMemoryRecords.isEmpty)
        XCTAssertFalse(store.workspacePlans.isEmpty)
        XCTAssertTrue(store.workspacePlans.contains { !$0.sharedMemorySignals.isEmpty })
        XCTAssertTrue(store.workspacePlans.contains { !$0.crossWorkspaceSignals.isEmpty })
        XCTAssertTrue(store.workspacePlans.allSatisfy { $0.memoryRecordCount > 0 })
    }

    @MainActor
    func testWorkspaceMemoryUpsertsCoreSignals() {
        let store = testStore()
        store.deleteLocalMemory()
        store.dailyPriority = "First value"
        store.applyDailyCheckIn()
        store.dailyPriority = "Second value"
        store.applyDailyCheckIn()

        let dailyPriorityRecords = store.workspaceMemoryRecords.filter { record in
            if record.key != "daily_priority" { return false }
            if record.source != .checkin { return false }
            return record.lane == nil
        }
        XCTAssertEqual(dailyPriorityRecords.count, 1)
        XCTAssertEqual(dailyPriorityRecords.first?.value, "Second value")
    }

    @MainActor
    func testKnowledgeFilesBecomeSharedWorkspaceMemory() throws {
        let store = testStore()
        store.deleteLocalMemory()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlas-knowledge-\(UUID().uuidString).txt")
        let content = """
        BlackHaven project memory should persist strategy context across all workspace lanes.
        Revenue playbook: run daily outbound, strengthen offer clarity, and enforce weekly close cadence.
        """
        try content.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        store.importKnowledgeFiles(urls: [tempURL])

        XCTAssertEqual(store.knowledgeFiles.count, 1)
        let documentRecords = store.workspaceMemoryRecords.filter { $0.source == .document }
        XCTAssertFalse(documentRecords.isEmpty)
        XCTAssertTrue(documentRecords.allSatisfy { $0.lane == nil && $0.sessionID == nil })
    }

    @MainActor
    func testKnowledgeRetrievalPrefersPromptRelevantChunks() throws {
        let store = testStore()
        store.deleteLocalMemory()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlas-semantic-\(UUID().uuidString).txt")
        let content = """
        Recirculating showers for vans require a particulate filter, UV sterilization stage, and a compact heat exchanger so water can be reused safely.
        The plumbing loop should include a service access panel and clear maintenance intervals for filter swaps.

        Israeli business regulation updates can affect VAT handling, company reporting, compliance filings, and employer obligations in 2026.
        """
        try content.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        store.importKnowledgeFiles(urls: [tempURL])

        let digest = store.knowledgeRetrievalDigest(
            for: "What filtration and UV stages do I need for a recirculating shower in a van build?",
            surface: .workspace,
            workspaceLane: .mobileLivingInfrastructure,
            maxLength: 900
        )

        XCTAssertTrue(digest.localizedCaseInsensitiveContains("filter") || digest.localizedCaseInsensitiveContains("filtration"), digest)
        XCTAssertTrue(digest.localizedCaseInsensitiveContains("uv"), digest)
        XCTAssertFalse(digest.localizedCaseInsensitiveContains("vat handling"), digest)
    }

    @MainActor
    func testKnowledgeRetrievalStaysWithinBudgetAndUsesIndexWhenPromptArrives() throws {
        let store = testStore()
        store.deleteLocalMemory()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlas-semantic-budget-\(UUID().uuidString).txt")
        let repeated = Array(repeating: "Lightweight RV insulation can use aerogel blankets, polyiso, cork, and careful thermal-break design.", count: 50)
            .joined(separator: "\n")
        try repeated.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        store.importKnowledgeFiles(urls: [tempURL])

        let digest = store.knowledgeRetrievalDigest(
            for: "Best lightweight insulation choices for an electric RV build",
            surface: .workspace,
            workspaceLane: .mobileLivingInfrastructure,
            maxLength: 420
        )

        XCTAssertLessThanOrEqual(digest.count, 420)
        XCTAssertTrue(digest.localizedCaseInsensitiveContains("retrieved evidence"))
        XCTAssertTrue(digest.localizedCaseInsensitiveContains("insulation"))
    }

    @MainActor
    func testWorkspaceSessionsSeedAndCarryAcrossLanes() async {
        let store = testStore()
        store.deleteLocalMemory()
        XCTAssertGreaterThanOrEqual(store.workspaceSessions.count, WorkspaceLane.allCases.count)

        store.setActiveWorkspaceLane(.innovation)
        store.createWorkspaceSession(for: .innovation, title: "Innovation Lab Notebook")

        let activeInnovation = store.activeSessionID(for: .innovation)
        XCTAssertNotNil(activeInnovation)

        store.pendingNoteTitle = "Prototype sprint"
        store.pendingNoteContent = "Ship hypothesis to validation loop."
        await store.saveNote()
        store.applyDailyCheckIn()

        let innovationRecords = store.workspaceMemoryRecords.filter { record in
            record.lane == .innovation
        }
        XCTAssertTrue(innovationRecords.contains(where: { $0.sessionID == activeInnovation }))

        let crossLaneRecords = store.workspaceMemoryRecords.filter { record in
            record.lane == .mobilityOps || record.lane == .wealthOperations || record.lane == .deepWork
        }
        XCTAssertFalse(crossLaneRecords.isEmpty)
    }

    @MainActor
    func testMemoryVaultKeepsStableNoteTimestampsAcrossSyncs() {
        let store = testStore()
        store.deleteLocalMemory()
        let createdAt = Date(timeIntervalSince1970: 1_715_000_000)
        store.notes = [
            UserNote(
                noteID: "stable-note",
                title: "Stable chronology",
                content: "Do not rewrite this note timestamp on every vault sync.",
                createdAt: createdAt
            )
        ]

        store.debugSyncMemoryVault(reason: "first_sync")
        let first = store.debugMemoryVaultSnapshot().rawRecords.first { $0.id == "note:stable-note" }

        store.debugSyncMemoryVault(reason: "second_sync")
        let second = store.debugMemoryVaultSnapshot().rawRecords.first { $0.id == "note:stable-note" }

        XCTAssertEqual(first?.createdAt, createdAt)
        XCTAssertEqual(second?.createdAt, createdAt)
    }

    @MainActor
    func testQueueMutationByIDIsSafeWhenItemDisappears() {
        let store = testStore()
        store.deleteLocalMemory()
        let id = "queued-item"
        store.promptQueue = [
            PromptQueueItem(
                id: id,
                prompt: "Test queue item",
                status: .queued,
                createdAt: Date()
            )
        ]

        let firstMutation = store.updatePromptQueueItem(id: id) { item in
            item.status = .running
            item.checkpointNote = "Working"
        }
        XCTAssertTrue(firstMutation)
        XCTAssertEqual(store.promptQueue.first?.status, .running)

        store.promptQueue = []

        let secondMutation = store.updatePromptQueueItem(id: id) { item in
            item.status = .done
        }
        XCTAssertFalse(secondMutation)
    }

    @MainActor
    func testAdditionalSurveyPassAvoidsRepeatedQuestionIDs() async {
        let store = testStore()
        store.deleteLocalMemory()
        var askedIDs = Set<String>()

        for _ in 0 ..< 40 {
            await store.loadSurvey()
            guard let question = store.survey?.question else { break }
            askedIDs.insert(question.id)
            if let firstChoice = question.choices.first {
                await store.answerSurvey(firstChoice)
            }
        }

        await store.startAdditionalSurveyPass()

        var newlyAsked: [String] = []
        for _ in 0 ..< 3 {
            guard let question = store.survey?.question else { break }
            XCTAssertFalse(askedIDs.contains(question.id))
            newlyAsked.append(question.id)
            askedIDs.insert(question.id)
            if let firstChoice = question.choices.first {
                await store.answerSurvey(firstChoice)
            }
        }

        XCTAssertFalse(newlyAsked.isEmpty)
        XCTAssertTrue(newlyAsked.allSatisfy { $0.hasPrefix("adaptive_depth_") })
    }

    @MainActor
    func testWealthRouteQuestionsDriveWealthExecutionLane() async {
        let store = testStore()
        store.deleteLocalMemory()
        var askedIDs = Set<String>()

        for _ in 0 ..< 90 {
            await store.loadSurvey()
            guard let question = store.survey?.question else { break }
            askedIDs.insert(question.id)

            let choice: SurveyChoice
            switch question.id {
            case "primary_goal":
                choice = question.choices.first(where: { $0.value == "wealth" }) ?? question.choices.first!
            case "wealth_vehicle":
                choice = question.choices.first(where: { $0.value == "hybrid" }) ?? question.choices.first!
            case "industry_focus":
                choice = question.choices.first(where: { $0.value == "software_ai" }) ?? question.choices.first!
            case "business_model_focus":
                choice = question.choices.first(where: { $0.value == "saas" }) ?? question.choices.first!
            default:
                choice = question.choices.first!
            }
            await store.answerSurvey(choice)
        }

        XCTAssertTrue(askedIDs.contains("wealth_vehicle"))
        XCTAssertTrue(askedIDs.contains("industry_focus"))
        XCTAssertTrue(askedIDs.contains("high_paying_job_track"))
        XCTAssertTrue(askedIDs.contains("business_model_focus"))
        XCTAssertTrue(askedIDs.contains("compounding_plan"))
        XCTAssertTrue(askedIDs.contains("income_gap_primary"))
        XCTAssertTrue(askedIDs.contains("brain_sleep_quality"))
        XCTAssertTrue(askedIDs.contains("brain_focus_stability"))
        XCTAssertTrue(askedIDs.contains("brain_stress_regulation"))
        XCTAssertTrue(askedIDs.contains("decision_protocol"))
        XCTAssertTrue(askedIDs.contains("weekly_revenue_reps"))
        XCTAssertTrue(askedIDs.contains("behavioral_money_leak"))
        XCTAssertTrue(askedIDs.contains("capital_allocation_discipline"))
        XCTAssertTrue(askedIDs.contains("employment_state"))
        XCTAssertTrue(askedIDs.contains("business_state"))
        XCTAssertTrue(askedIDs.contains("growth_priority"))
        XCTAssertTrue(askedIDs.contains("promotion_horizon"))
        XCTAssertTrue(askedIDs.contains("customer_growth_focus"))

        store.dailyPriority = "Ship one high leverage move today."
        store.applyDailyCheckIn()

        XCTAssertTrue(store.executionActions.contains(where: { $0.source == "wealth-route" }))
        XCTAssertTrue(store.executionActions.contains(where: { $0.source == "wealth-brain-diagnostic" }))
        XCTAssertTrue(store.executionActions.contains(where: { $0.source == "wealth-compounding" }))
        XCTAssertTrue(store.executionActions.contains(where: { $0.source == "wealth-corpus-ladder" }))
        XCTAssertTrue(store.executionActions.contains(where: { $0.source == "wealth-corpus-promotion" || $0.source == "wealth-corpus-business" }))
        XCTAssertTrue(store.tailoredOffers.contains(where: { $0.id == "offer-wealth-neuro-diagnostic" }))
        XCTAssertTrue(store.tailoredOffers.contains(where: { $0.id == "offer-income-ladder-ai_software" }))
    }

    @MainActor
    func testJobRadarBuildsOpportunitiesAndBlockerPlan() async {
        let store = testStore()
        store.deleteLocalMemory()

        for _ in 0 ..< 120 {
            await store.loadSurvey()
            guard let question = store.survey?.question else { break }

            let choice: SurveyChoice
            switch question.id {
            case "primary_goal":
                choice = question.choices.first(where: { $0.value == "wealth" }) ?? question.choices.first!
            case "wealth_vehicle":
                choice = question.choices.first(where: { $0.value == "job_ladder" }) ?? question.choices.first!
            case "industry_focus":
                choice = question.choices.first(where: { $0.value == "software_ai" }) ?? question.choices.first!
            case "high_paying_job_track":
                choice = question.choices.first(where: { $0.value == "engineering" }) ?? question.choices.first!
            case "job_radar_interest":
                choice = question.choices.first(where: { $0.value == "no" }) ?? question.choices.first!
            case "job_radar_blocker":
                choice = question.choices.first(where: { $0.value == "skills_gap" }) ?? question.choices.first!
            case "job_radar_support_mode":
                choice = question.choices.first(where: { $0.value == "portfolio_plan" }) ?? question.choices.first!
            default:
                choice = question.choices.first!
            }

            await store.answerSurvey(choice)
        }

        store.applyDailyCheckIn()

        XCTAssertFalse(store.jobMarketOpportunities.isEmpty)
        XCTAssertTrue(store.executionActions.contains(where: { $0.source == "job-radar" }))
        XCTAssertTrue(store.executionActions.contains(where: { $0.source == "job-blocker" }))
        XCTAssertTrue(store.tailoredOffers.contains(where: { $0.id == "offer-global-job-market-radar" }))
    }

    @MainActor
    func testCareerRouteChoosesPromotionOrCustomerGrowth() async {
        let employeeStore = testStore()
        employeeStore.deleteLocalMemory()

        for _ in 0 ..< 130 {
            await employeeStore.loadSurvey()
            guard let question = employeeStore.survey?.question else { break }
            let choice: SurveyChoice
            switch question.id {
            case "primary_goal":
                choice = question.choices.first(where: { $0.value == "wealth" }) ?? question.choices.first!
            case "employment_state":
                choice = question.choices.first(where: { $0.value == "employed_full_time" }) ?? question.choices.first!
            case "business_state":
                choice = question.choices.first(where: { $0.value == "no_business" }) ?? question.choices.first!
            case "growth_priority":
                choice = question.choices.first(where: { $0.value == "climb_job_ladder" }) ?? question.choices.first!
            case "promotion_horizon":
                choice = question.choices.first(where: { $0.value == "senior_to_staff" }) ?? question.choices.first!
            case "customer_growth_focus":
                choice = question.choices.first(where: { $0.value == "not_applicable" }) ?? question.choices.first!
            default:
                choice = question.choices.first!
            }
            await employeeStore.answerSurvey(choice)
        }

        employeeStore.applyDailyCheckIn()
        XCTAssertTrue(employeeStore.executionActions.contains(where: { $0.source == "career-fit" }))
        XCTAssertTrue(employeeStore.executionActions.contains(where: { $0.source == "promotion-sprint" }))
        XCTAssertTrue(employeeStore.tailoredOffers.contains(where: { $0.id == "offer-promotion-accelerator" }))

        let businessStore = testStore()
        businessStore.deleteLocalMemory()

        for _ in 0 ..< 130 {
            await businessStore.loadSurvey()
            guard let question = businessStore.survey?.question else { break }
            let choice: SurveyChoice
            switch question.id {
            case "primary_goal":
                choice = question.choices.first(where: { $0.value == "wealth" }) ?? question.choices.first!
            case "employment_state":
                choice = question.choices.first(where: { $0.value == "between_roles" }) ?? question.choices.first!
            case "business_state":
                choice = question.choices.first(where: { $0.value == "recurring_revenue" }) ?? question.choices.first!
            case "growth_priority":
                choice = question.choices.first(where: { $0.value == "grow_business_customer_base" }) ?? question.choices.first!
            case "promotion_horizon":
                choice = question.choices.first(where: { $0.value == "not_applicable" }) ?? question.choices.first!
            case "customer_growth_focus":
                choice = question.choices.first(where: { $0.value == "lead_generation" }) ?? question.choices.first!
            default:
                choice = question.choices.first!
            }
            await businessStore.answerSurvey(choice)
        }

        businessStore.applyDailyCheckIn()
        XCTAssertTrue(businessStore.executionActions.contains(where: { $0.source == "career-fit" }))
        XCTAssertTrue(businessStore.executionActions.contains(where: { $0.source == "customer-growth-sprint" }))
        XCTAssertTrue(businessStore.executionActions.contains(where: { $0.source == "wealth-corpus-business" }))
        XCTAssertTrue(businessStore.tailoredOffers.contains(where: { $0.id == "offer-customer-growth-engine" }))
        XCTAssertTrue(businessStore.tailoredOffers.contains(where: { $0.id == "offer-business-playbook-ai_software" }))
    }

    @MainActor
    func testRealEstateIndustryCorpusAppearsInExecutionAndOffers() async {
        let store = testStore()
        store.deleteLocalMemory()

        for _ in 0 ..< 130 {
            await store.loadSurvey()
            guard let question = store.survey?.question else { break }
            let choice: SurveyChoice
            switch question.id {
            case "primary_goal":
                choice = question.choices.first(where: { $0.value == "wealth" }) ?? question.choices.first!
            case "wealth_vehicle":
                choice = question.choices.first(where: { $0.value == "business_builder" }) ?? question.choices.first!
            case "industry_focus":
                choice = question.choices.first(where: { $0.value == "real_estate" }) ?? question.choices.first!
            case "business_model_focus":
                choice = question.choices.first(where: { $0.value == "local_service" }) ?? question.choices.first!
            case "growth_priority":
                choice = question.choices.first(where: { $0.value == "grow_business_customer_base" }) ?? question.choices.first!
            case "customer_growth_focus":
                choice = question.choices.first(where: { $0.value == "lead_generation" }) ?? question.choices.first!
            default:
                choice = question.choices.first!
            }
            await store.answerSurvey(choice)
        }

        store.applyDailyCheckIn()
        XCTAssertTrue(store.executionActions.contains(where: {
            $0.source == "wealth-corpus-ladder" && $0.title.contains("Real Estate")
        }))
        XCTAssertTrue(store.executionActions.contains(where: {
            $0.source == "wealth-corpus-business" && $0.title.contains("Real Estate")
        }))
        XCTAssertTrue(store.tailoredOffers.contains(where: { $0.id == "offer-income-ladder-real_estate" }))
        XCTAssertTrue(store.tailoredOffers.contains(where: { $0.id == "offer-business-playbook-real_estate" }))
    }

    @MainActor
    func testCodingWorkspaceScanOpenSaveAndPromptMemory() throws {
        let store = testStore()
        store.deleteLocalMemory()

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("atlas-coding-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let mainFile = root.appendingPathComponent("main.swift")
        try """
        import Foundation
        print("hello")
        """
            .write(to: mainFile, atomically: true, encoding: .utf8)

        store.setCodingWorkspaceRootPath(root.path)
        store.rescanCodingWorkspace()
        XCTAssertTrue(store.codingWorkspaceFiles.contains(mainFile.path))

        store.openCodingFile(mainFile.path)
        XCTAssertTrue(store.codingEditorText.contains("hello"))

        store.setCodingEditorText("import Foundation\nprint(\"updated\")\n")
        XCTAssertTrue(store.codingEditorIsDirty)
        store.saveCodingFile()
        XCTAssertFalse(store.codingEditorIsDirty)

        let disk = try String(contentsOf: mainFile, encoding: .utf8)
        XCTAssertTrue(disk.contains("updated"))

        store.codingPromptDraft = "How should I validate this quick script?"
        store.submitCodingPrompt()
        XCTAssertGreaterThanOrEqual(store.codingMessages.count, 2)
        XCTAssertFalse(store.codingMemoryRecords.isEmpty)
    }

    @MainActor
    func testCodingWorkspaceSlashGrepFindsFileContent() throws {
        let store = testStore()
        store.deleteLocalMemory()

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("atlas-coding-grep-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let file = root.appendingPathComponent("script.sh")
        try "echo local_agent_ready\n".write(to: file, atomically: true, encoding: .utf8)

        store.setCodingWorkspaceRootPath(root.path)
        store.rescanCodingWorkspace()
        store.codingPromptDraft = "/grep local_agent_ready"
        store.submitCodingPrompt()

        let hasMatch = store.codingMessages.contains { message in
            message.content.contains("script.sh")
                && message.content.lowercased().contains("local_agent_ready")
        }
        XCTAssertTrue(hasMatch)
    }
}
