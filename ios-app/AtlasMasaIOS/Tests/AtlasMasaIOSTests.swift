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
        XCTAssertEqual(store.workspaceSessions.count, WorkspaceLane.allCases.count)

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
}
