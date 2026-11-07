import XCTest
@testable import MindFriendApp

final class CompanionSyncTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var directory: URL!
    private var store: SharedDataStore!

    override func setUpWithError() throws {
        suite = "CompanionSyncTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        store = SharedDataStore(userDefaults: defaults, actionDirectory: directory)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    private func calendar(_ zone: String = "America/New_York") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testSnapshotIsAtomicAndBoundToAccountAndLocalDate() throws {
        let a = UUID(), b = UUID()
        let now = date("2026-11-01T04:30:00Z")
        store.reset(to: a)
        var snapshot = WidgetSnapshot(ownerID: a, localDate: "2026-11-01", updatedAt: now)
        snapshot.todayMood = "good"
        snapshot.todayMoodScore = 4
        snapshot.currentStreak = 9
        XCTAssertTrue(try store.publish(snapshot))
        XCTAssertEqual(store.snapshot(at: now, calendar: calendar())?.currentStreak, 9)
        XCTAssertNil(store.snapshot(at: date("2026-11-02T05:01:00Z"), calendar: calendar()))
        store.reset(to: b)
        XCTAssertNil(store.snapshot(at: now, calendar: calendar()))
        XCTAssertFalse(try store.publish(snapshot), "A late old-account response must not publish")
        store.reset(to: nil)
        XCTAssertNil(store.activeOwnerID)
    }

    func testPendingActionSurvivesProcessRestartAndAccountSwitchWithOriginalIdentity() throws {
        let a = UUID(), b = UUID()
        let now = date("2026-11-01T04:30:00Z")
        store.reset(to: a)
        XCTAssertTrue(try store.publish(WidgetSnapshot(ownerID: a, localDate: "2026-11-01")))
        let action = try store.queueMood(score: 2, now: now, calendar: calendar())
        XCTAssertEqual(action.localDate, "2026-11-01")
        XCTAssertEqual(action.timeZoneID, "America/New_York")
        XCTAssertEqual(action.observedAt, now)
        let restored = SharedDataStore(userDefaults: UserDefaults(suiteName: suite), actionDirectory: directory)
        XCTAssertEqual(try restored.pendingActions(for: a), [action])
        restored.reset(to: b)
        XCTAssertEqual(try restored.pendingActions(for: a), [action])
        XCTAssertTrue(try restored.pendingActions(for: b).isEmpty)
        XCTAssertNil(restored.snapshot(at: now, calendar: calendar()))
        XCTAssertThrowsError(try restored.queueMood(score: 4, now: now, calendar: calendar()))
    }

    func testAcknowledgmentRemovesOnlyMatchingOwnerAndEvent() throws {
        let owner = UUID()
        let first = CompanionAction(ownerID: owner, kind: .mood, moodScore: 2)
        let second = CompanionAction(ownerID: owner, kind: .mood, moodScore: 4)
        try store.storePending(first)
        try store.storePending(second)
        try store.acknowledge(CompanionActionReceipt(eventID: first.id, ownerID: UUID(), status: .applied))
        XCTAssertEqual(try store.pendingActions(for: owner).count, 2)
        try store.acknowledge(CompanionActionReceipt(eventID: first.id, ownerID: owner, status: .preservedNewer))
        XCTAssertEqual(try store.pendingActions(for: owner), [second])
        try store.acknowledge(CompanionActionReceipt(eventID: first.id, ownerID: owner, status: .preservedNewer))
        XCTAssertEqual(try store.pendingActions(for: owner), [second])
    }

    func testIndependentWritersDoNotOverwritePendingActionsAndConflictsAreRejected() throws {
        let owner = UUID()
        let other = SharedDataStore(userDefaults: UserDefaults(suiteName: suite), actionDirectory: directory)
        let actions = (0..<20).map { CompanionAction(ownerID: owner, kind: .mood, moodScore: $0 % 5 + 1) }
        for (index, action) in actions.enumerated() { try (index.isMultiple(of: 2) ? store! : other).storePending(action) }
        try store.storePending(actions[0])
        XCTAssertEqual(Set(try store.pendingActions(for: owner).map(\.id)), Set(actions.map(\.id)))
        let changed = CompanionAction(id: actions[0].id, ownerID: owner, kind: .mood, moodScore: 5)
        XCTAssertThrowsError(try other.storePending(changed))
        try store.acknowledge(CompanionActionReceipt(eventID: actions[0].id, ownerID: owner, status: .applied))
        XCTAssertEqual(try other.pendingActions(for: owner).count, 19)
    }

    func testQueueRejectsMissingIdentityInvalidPayloadAndOldQuest() throws {
        let now = date("2026-11-01T04:30:00Z")
        XCTAssertThrowsError(try store.queueMood(score: 2, now: now, calendar: calendar()))
        let owner = UUID(), quest = UUID()
        store.reset(to: owner)
        var snapshot = WidgetSnapshot(ownerID: owner, localDate: "2026-11-01")
        snapshot.dailyQuest = WidgetDailyQuest(id: quest.uuidString, title: "Quest", description: "Test", category: "mindfulness", xpReward: 0, isCompleted: false, assignedDate: now)
        try store.publish(snapshot)
        XCTAssertThrowsError(try store.queueMood(score: 99, now: now, calendar: calendar()))
        XCTAssertThrowsError(try store.queueQuest(questID: UUID().uuidString, now: now, calendar: calendar()))
        let action = try store.queueQuest(questID: quest.uuidString, now: now, calendar: calendar())
        XCTAssertEqual(action.questID, quest)
        XCTAssertEqual(action.localDate, "2026-11-01")
        XCTAssertThrowsError(try store.queueQuest(questID: quest.uuidString, now: date("2026-11-02T05:01:00Z"), calendar: calendar()))
        XCTAssertEqual(try store.pendingActions(for: owner), [action])
    }

    func testOriginalLocalDatesAcrossDSTAndTokyo() throws {
        let owner = UUID()
        for (stamp, zone, day) in [
            ("2026-03-08T06:59:00Z", "America/New_York", "2026-03-08"),
            ("2026-03-08T07:01:00Z", "America/New_York", "2026-03-08"),
            ("2026-11-01T05:30:00Z", "America/New_York", "2026-11-01"),
            ("2026-11-01T06:30:00Z", "America/New_York", "2026-11-01"),
            ("2026-11-01T15:01:00Z", "Asia/Tokyo", "2026-11-02")
        ] {
            let action = CompanionAction(ownerID: owner, kind: .mood, observedAt: date(stamp), calendar: calendar(zone), moodScore: 3)
            try store.storePending(action)
            XCTAssertEqual(action.localDate, day)
            XCTAssertEqual(try JSONDecoder().decode(CompanionAction.self, from: JSONEncoder().encode(action)), action)
        }
    }
}
