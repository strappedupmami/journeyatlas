import XCTest
@testable import AtlasMasaIOS

final class AtlasMasaIOSTests: XCTestCase {
    func testScaffoldBootstraps() {
        XCTAssertTrue(true)
    }

    @MainActor
    func testWorkspaceMemoryCarriesAcrossLanes() {
        let store = SessionStore(api: APIClient(baseURL: URL(string: "https://example.invalid")!))
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
        let store = SessionStore(api: APIClient(baseURL: URL(string: "https://example.invalid")!))
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
}
