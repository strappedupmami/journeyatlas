import XCTest
@testable import AtlasMasaIOS

final class AtlasMasaIOSTests: XCTestCase {
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

    func testScaffoldBootstraps() {
        XCTAssertTrue(true)
    }

    @MainActor
    func testWorkspaceMemoryCarriesAcrossLanes() {
        let store = SessionStore(api: offlineClient())
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
        let store = SessionStore(api: offlineClient())
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
    func testWorkspaceSessionsSeedAndCarryAcrossLanes() async {
        let store = SessionStore(api: offlineClient())
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
    func testAdditionalSurveyPassAvoidsRepeatedQuestionIDs() async {
        let store = SessionStore(api: offlineClient())
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
        let store = SessionStore(api: offlineClient())
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

        store.dailyPriority = "Ship one high leverage move today."
        store.applyDailyCheckIn()

        XCTAssertTrue(store.executionActions.contains(where: { $0.source == "wealth-route" }))
        XCTAssertTrue(store.executionActions.contains(where: { $0.source == "wealth-compounding" }))
    }

    @MainActor
    func testJobRadarBuildsOpportunitiesAndBlockerPlan() async {
        let store = SessionStore(api: offlineClient())
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
}
