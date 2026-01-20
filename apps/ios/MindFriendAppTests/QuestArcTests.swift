//
//  QuestArcTests.swift
//  MindFriendAppTests
//
//  Tests for Quest Arc models and computed properties
//

import XCTest
@testable import MindFriendApp

final class QuestArcTests: XCTestCase {

    // MARK: - UserQuestArc Progress Tests

    func testProgressPercentage_atStart() {
        let userArc = createUserArc(currentDay: 0, durationDays: 14)
        XCTAssertEqual(userArc.progressPercentage, 0.0, accuracy: 0.001)
    }

    func testProgressPercentage_midway() {
        let userArc = createUserArc(currentDay: 7, durationDays: 14)
        XCTAssertEqual(userArc.progressPercentage, 0.5, accuracy: 0.001)
    }

    func testProgressPercentage_complete() {
        let userArc = createUserArc(currentDay: 14, durationDays: 14)
        XCTAssertEqual(userArc.progressPercentage, 1.0, accuracy: 0.001)
    }

    func testProgressPercentage_overComplete() {
        // Should cap at 1.0
        let userArc = createUserArc(currentDay: 20, durationDays: 14)
        XCTAssertEqual(userArc.progressPercentage, 1.0, accuracy: 0.001)
    }

    // MARK: - Milestone Tests

    func testCompletedMilestones_none() {
        let userArc = createUserArc(currentDay: 2, durationDays: 14, milestones: [3, 7, 14])
        XCTAssertEqual(userArc.completedMilestones, [])
    }

    func testCompletedMilestones_first() {
        let userArc = createUserArc(currentDay: 3, durationDays: 14, milestones: [3, 7, 14])
        XCTAssertEqual(userArc.completedMilestones, [3])
    }

    func testCompletedMilestones_partial() {
        let userArc = createUserArc(currentDay: 8, durationDays: 14, milestones: [3, 7, 14])
        XCTAssertEqual(userArc.completedMilestones, [3, 7])
    }

    func testCompletedMilestones_all() {
        let userArc = createUserArc(currentDay: 14, durationDays: 14, milestones: [3, 7, 14])
        XCTAssertEqual(userArc.completedMilestones, [3, 7, 14])
    }

    func testNextMilestoneDay_beforeFirst() {
        let userArc = createUserArc(currentDay: 1, durationDays: 14, milestones: [3, 7, 14])
        XCTAssertEqual(userArc.nextMilestoneDay, 3)
    }

    func testNextMilestoneDay_betweenMilestones() {
        let userArc = createUserArc(currentDay: 5, durationDays: 14, milestones: [3, 7, 14])
        XCTAssertEqual(userArc.nextMilestoneDay, 7)
    }

    func testNextMilestoneDay_afterAll() {
        let userArc = createUserArc(currentDay: 14, durationDays: 14, milestones: [3, 7, 14])
        XCTAssertNil(userArc.nextMilestoneDay)
    }

    func testIsMilestoneDay_onMilestone() {
        let userArc = createUserArc(currentDay: 7, durationDays: 14, milestones: [3, 7, 14])
        XCTAssertTrue(userArc.isMilestoneDay)
    }

    func testIsMilestoneDay_notOnMilestone() {
        let userArc = createUserArc(currentDay: 6, durationDays: 14, milestones: [3, 7, 14])
        XCTAssertFalse(userArc.isMilestoneDay)
    }

    // MARK: - Completion Tests

    func testIsCompleted_notYet() {
        let userArc = createUserArc(currentDay: 13, durationDays: 14)
        XCTAssertFalse(userArc.isCompleted)
    }

    func testIsCompleted_exactlyDone() {
        let userArc = createUserArc(currentDay: 14, durationDays: 14)
        XCTAssertTrue(userArc.isCompleted)
    }

    func testIsCompleted_overDone() {
        let userArc = createUserArc(currentDay: 15, durationDays: 14)
        XCTAssertTrue(userArc.isCompleted)
    }

    // MARK: - Pause Expiration Tests

    func testPausedExpiresAt_notPaused() {
        let userArc = createUserArc(currentDay: 5, durationDays: 14, pausedAt: nil)
        XCTAssertNil(userArc.pausedExpiresAt)
    }

    func testPausedExpiresAt_paused() {
        let pausedDate = Date()
        let userArc = createUserArc(currentDay: 5, durationDays: 14, pausedAt: pausedDate)

        guard let expiresAt = userArc.pausedExpiresAt else {
            XCTFail("Expected expiration date")
            return
        }

        // Should be 30 days after paused date
        let calendar = Calendar.current
        let dayDiff = calendar.dateComponents([.day], from: pausedDate, to: expiresAt).day
        XCTAssertEqual(dayDiff, 30)
    }

    // MARK: - Helpers

    private func createUserArc(
        currentDay: Int,
        durationDays: Int,
        milestones: [Int] = [3, 7, 14],
        pausedAt: Date? = nil
    ) -> UserQuestArc {
        UserQuestArc(
            id: UUID(),
            userId: UUID(),
            arcId: UUID(),
            status: pausedAt != nil ? "paused" : "active",
            currentDay: currentDay,
            snapshotDurationDays: durationDays,
            snapshotMilestoneDays: milestones,
            startedAt: Date(),
            pausedAt: pausedAt,
            completedAt: nil,
            abandonedAt: nil,
            questArc: nil
        )
    }
}

// MARK: - QuestArc Model Tests

final class QuestArcModelTests: XCTestCase {

    func testQuestArc_init() {
        let arc = QuestArc(
            id: UUID(),
            title: "Test Arc",
            description: "A test arc",
            category: "stress",
            durationDays: 14,
            milestoneDays: [3, 7, 14],
            isPremium: false,
            isActive: true,
            createdAt: Date()
        )

        XCTAssertEqual(arc.title, "Test Arc")
        XCTAssertEqual(arc.category, "stress")
        XCTAssertEqual(arc.durationDays, 14)
        XCTAssertEqual(arc.milestoneDays.count, 3)
        XCTAssertFalse(arc.isPremium)
    }
}
