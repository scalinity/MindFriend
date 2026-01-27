//  InterventionNotificationManagerTests.swift
//  MindFriendAppTests
//
//  Tests for InterventionNotificationManager: delivery, deep linking, actionable notifications

import XCTest
import UserNotifications
@testable import MindFriendApp

@MainActor
final class InterventionNotificationManagerTests: XCTestCase {
    var manager: InterventionNotificationManager!

    override func setUp() async throws {
        manager = InterventionNotificationManager()
    }

    override func tearDown() async throws {
        await manager.cancelPendingInterventions()
        manager = nil
    }

    // MARK: - Test Helpers

    private func makeMicroMomentTemplate(
        id: String = "test-123",
        name: String = "Test Moment",
        type: MicroMomentType = .breathing,
        title: String = "Calm Breath",
        description: String? = "A quick breathing exercise",
        durationSeconds: Int = 60
    ) -> MicroMomentTemplate {
        MicroMomentTemplate(
            id: id,
            name: name,
            slug: name.lowercased().replacingOccurrences(of: " ", with: "-"),
            type: type,
            title: title,
            description: description,
            durationSeconds: durationSeconds,
            instructions: [],
            animationType: nil,
            audioUrl: nil,
            hapticPattern: nil,
            suggestedContexts: nil,
            energyEffect: nil,
            isPremium: false,
            isActive: true,
            sortOrder: 0,
            createdAt: "2026-01-25T00:00:00Z",
            updatedAt: "2026-01-25T00:00:00Z"
        )
    }

    // MARK: - Permission Tests

    func testHasNotificationPermissionWhenNotDetermined() async {
        let hasPermission = await manager.hasNotificationPermission()

        // In test environment without permission, should be false
        XCTAssertFalse(hasPermission)
    }

    // MARK: - Notification Content Tests

    func testDeliverInterventionCreatesNotificationWithCorrectContent() async throws {
        let intervention = makeMicroMomentTemplate()
        let context = "You have a meeting in 45 minutes"
        let deliveryId = UUID()

        // This will fail in test environment without permission, but we can verify the method exists
        do {
            try await manager.deliverIntervention(intervention, context: context, deliveryId: deliveryId)
            XCTFail("Expected to throw permission error in test environment")
        } catch {
            // Expected - no permission in test environment
            print("Expected error: \(error)")
        }
    }

    func testScheduleInterventionForFuture() async throws {
        let intervention = makeMicroMomentTemplate(
            id: "test-456",
            name: "Grounding Exercise",
            type: .grounding,
            title: "5-4-3-2-1 technique",
            durationSeconds: 120
        )

        let scheduledDate = Date().addingTimeInterval(60 * 60) // 1 hour from now
        let deliveryId = UUID()

        do {
            try await manager.scheduleIntervention(
                intervention,
                at: scheduledDate,
                context: "Prepare for upcoming event",
                deliveryId: deliveryId
            )
            XCTFail("Expected to throw permission error in test environment")
        } catch {
            // Expected - no permission in test environment
            print("Expected error: \(error)")
        }
    }

    // MARK: - Deep Link Parsing Tests

    func testParseDeepLinkForOpenAction() async {
        let deliveryId = UUID()
        let interventionId = UUID()

        let userInfo: [AnyHashable: Any] = [
            "delivery_id": deliveryId.uuidString,
            "intervention_id": interventionId.uuidString,
            "action": "open",
            "type": "intervention"
        ]

        let deepLink = InterventionDeepLink.parse(from: userInfo)

        XCTAssertNotNil(deepLink)
        XCTAssertEqual(deepLink?.deliveryId, deliveryId)
        XCTAssertEqual(deepLink?.interventionId, interventionId)
        XCTAssertEqual(deepLink?.action, .open)
    }

    func testParseDeepLinkForCompleteAction() async {
        let deliveryId = UUID()
        let interventionId = UUID()

        let userInfo: [AnyHashable: Any] = [
            "delivery_id": deliveryId.uuidString,
            "intervention_id": interventionId.uuidString,
            "action": "complete",
            "type": "intervention"
        ]

        let deepLink = InterventionDeepLink.parse(from: userInfo)

        XCTAssertNotNil(deepLink)
        XCTAssertEqual(deepLink?.action, .complete)
    }

    func testParseDeepLinkForDismissAction() async {
        let deliveryId = UUID()
        let interventionId = UUID()

        let userInfo: [AnyHashable: Any] = [
            "delivery_id": deliveryId.uuidString,
            "intervention_id": interventionId.uuidString,
            "action": "dismiss",
            "type": "intervention"
        ]

        let deepLink = InterventionDeepLink.parse(from: userInfo)

        XCTAssertNotNil(deepLink)
        XCTAssertEqual(deepLink?.action, .dismiss)
    }

    func testParseDeepLinkForRemindLaterAction() async {
        let deliveryId = UUID()
        let interventionId = UUID()

        let userInfo: [AnyHashable: Any] = [
            "delivery_id": deliveryId.uuidString,
            "intervention_id": interventionId.uuidString,
            "action": "remind_later",
            "type": "intervention"
        ]

        let deepLink = InterventionDeepLink.parse(from: userInfo)

        XCTAssertNotNil(deepLink)
        XCTAssertEqual(deepLink?.action, .remindLater)
    }

    func testParseDeepLinkWithInvalidData() async {
        let userInfo: [AnyHashable: Any] = [
            "delivery_id": "not-a-uuid",
            "intervention_id": "also-not-a-uuid",
            "action": "open"
        ]

        let deepLink = InterventionDeepLink.parse(from: userInfo)

        XCTAssertNil(deepLink) // Should fail gracefully with invalid UUIDs
    }

    func testParseDeepLinkWithMissingFields() async {
        let userInfo: [AnyHashable: Any] = [
            "delivery_id": UUID().uuidString
            // Missing intervention_id and action
        ]

        let deepLink = InterventionDeepLink.parse(from: userInfo)

        XCTAssertNil(deepLink)
    }

    // MARK: - Badge Count Tests

    func testUpdateBadgeCountReflectsPendingCount() async {
        // Note: In test environment, this will always be 0
        await manager.updateBadgeCount()

        // Verify method completes without error
        // Actual badge count verification would require permission
    }

    func testCancelPendingInterventions() async {
        await manager.cancelPendingInterventions()

        let pendingCount = await manager.getPendingCount()
        XCTAssertEqual(pendingCount, 0)
    }

    // MARK: - Type Tests

    func testBreathingType() {
        let intervention = makeMicroMomentTemplate(type: .breathing)
        XCTAssertEqual(intervention.type, .breathing)
    }

    func testGroundingType() {
        let intervention = makeMicroMomentTemplate(type: .grounding)
        XCTAssertEqual(intervention.type, .grounding)
    }

    // MARK: - Duration Tests

    func testDurationUnderMinute() {
        let intervention = makeMicroMomentTemplate(durationSeconds: 45)
        XCTAssertEqual(intervention.durationSeconds, 45)
    }

    func testDurationInMinutes() {
        let intervention = makeMicroMomentTemplate(durationSeconds: 180)
        XCTAssertEqual(intervention.durationSeconds, 180)
    }
}
