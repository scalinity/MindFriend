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
    private var center: InterventionNotificationCenterFixture!

    override func setUp() async throws {
        center = InterventionNotificationCenterFixture()
        manager = InterventionNotificationManager(notificationCenter: center)
    }

    override func tearDown() async throws {
        manager = nil
        center = nil
    }

    // MARK: - Test Helpers

    private func makeMicroMomentTemplate(
        id: String = "11111111-1111-4111-8111-111111111111",
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
        center.status = .notDetermined
        let hasPermission = await manager.hasNotificationPermission()
        XCTAssertFalse(hasPermission)
    }

    func testHasNotificationPermissionWhenAuthorized() async {
        center.status = .authorized
        let hasPermission = await manager.hasNotificationPermission()
        XCTAssertTrue(hasPermission)
    }

    func testRequestPermissionUsesAlertSoundAndBadgeAndPreservesDenial() async {
        center.permissionGranted = false
        let granted = await manager.requestNotificationPermission()
        XCTAssertFalse(granted)
        XCTAssertEqual(center.requestedOptions, [.alert, .sound, .badge])
    }

    // MARK: - Notification Content Tests

    func testDeliverInterventionCreatesNotificationWithCorrectContent() async throws {
        let intervention = makeMicroMomentTemplate()
        let context = "You have a meeting in 45 minutes"
        let deliveryId = UUID()

        try await manager.deliverIntervention(intervention, context: context, deliveryId: deliveryId)
        let request = try XCTUnwrap(center.added.first)
        XCTAssertEqual(request.identifier, deliveryId.uuidString)
        XCTAssertNil(request.trigger)
        XCTAssertEqual(request.content.title, "🌬️ Calm Breath")
        XCTAssertEqual(request.content.body, "You have a meeting in 45 minutes (1 min)")
        XCTAssertEqual(request.content.categoryIdentifier, "INTERVENTION")
        XCTAssertEqual(request.content.threadIdentifier, "interventions")
        let link = try XCTUnwrap(InterventionDeepLink.parse(from: request.content.userInfo))
        XCTAssertEqual(link.deliveryId, deliveryId)
        XCTAssertEqual(link.interventionId, UUID(uuidString: intervention.id))
        XCTAssertEqual(link.action, .open)
    }

    func testScheduleInterventionForFuture() async throws {
        let intervention = makeMicroMomentTemplate(
            id: "22222222-2222-4222-8222-222222222222",
            name: "Grounding Exercise",
            type: .grounding,
            title: "5-4-3-2-1 technique",
            durationSeconds: 120
        )

        let scheduledDate = Date().addingTimeInterval(60 * 60) // 1 hour from now
        let deliveryId = UUID()

        try await manager.scheduleIntervention(
            intervention, at: scheduledDate, context: "Prepare for upcoming event", deliveryId: deliveryId
        )
        let request = try XCTUnwrap(center.added.first)
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 3600, accuracy: 2)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(request.identifier, deliveryId.uuidString)
        XCTAssertEqual(request.content.body, "Prepare for upcoming event (2 min)")
        XCTAssertEqual(InterventionDeepLink.parse(from: request.content.userInfo)?.interventionId,
                       UUID(uuidString: intervention.id))
    }

    func testSchedulingFailurePropagatesWithoutRecordingDelivery() async {
        center.addError = InterventionNotificationCenterFixture.Failure.rejected
        do {
            try await manager.deliverIntervention(makeMicroMomentTemplate(), context: "", deliveryId: UUID())
            XCTFail("Expected the injected scheduling failure")
        } catch {
            XCTAssertEqual(error as? InterventionNotificationCenterFixture.Failure, .rejected)
        }
        XCTAssertTrue(center.added.isEmpty)
        XCTAssertNil(center.badgeCount)
    }

    func testInvalidInterventionIDDoesNotCreateAValidDeepLink() async throws {
        try await manager.deliverIntervention(makeMicroMomentTemplate(id: "invalid"), context: "", deliveryId: UUID())
        let request = try XCTUnwrap(center.added.first)
        XCTAssertNil(InterventionDeepLink.parse(from: request.content.userInfo))
        XCTAssertEqual(request.content.userInfo["error"] as? String, "invalid_intervention_id")
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
        center.pending = [pendingRequest("one", category: "INTERVENTION"),
                          pendingRequest("two", category: "INTERVENTION"),
                          pendingRequest("other", category: "MEDICATION")]
        await manager.updateBadgeCount()
        XCTAssertEqual(center.badgeCount, 2)
    }

    func testCancelPendingInterventions() async {
        center.pending = [pendingRequest("intervention", category: "INTERVENTION"),
                          pendingRequest("other", category: "MEDICATION")]
        await manager.cancelPendingInterventions()

        let pendingCount = await manager.getPendingCount()
        XCTAssertEqual(pendingCount, 0)
        XCTAssertEqual(center.pending.map(\.identifier), ["other"])
        XCTAssertEqual(center.removed, ["intervention"])
        XCTAssertEqual(center.badgeCount, 0)
    }

    private func pendingRequest(_ id: String, category: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = category
        return UNNotificationRequest(identifier: id, content: content,
                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false))
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

@MainActor
private final class InterventionNotificationCenterFixture: InterventionNotificationCenter {
    enum Failure: Error { case rejected }
    var status: UNAuthorizationStatus = .authorized
    var permissionGranted = true
    var requestedOptions: UNAuthorizationOptions?
    var addError: Error?
    var added: [UNNotificationRequest] = []
    var pending: [UNNotificationRequest] = []
    var removed: [String] = []
    var badgeCount: Int?
    var categories: Set<UNNotificationCategory> = []

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestedOptions = options
        return permissionGranted
    }
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func add(_ request: UNNotificationRequest) async throws {
        if let addError { throw addError }
        added.append(request)
        if request.trigger != nil { pending.append(request) }
    }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { pending }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removed += identifiers
        pending.removeAll { identifiers.contains($0.identifier) }
    }
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) { self.categories = categories }
    func setBadgeCount(_ newBadgeCount: Int) async throws { badgeCount = newBadgeCount }
}
