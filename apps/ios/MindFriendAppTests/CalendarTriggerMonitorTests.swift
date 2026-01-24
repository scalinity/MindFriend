//  CalendarTriggerMonitorTests.swift
//  MindFriendAppTests
//
//  Tests for CalendarTriggerMonitor: event classification, scanning, permissions

import XCTest
import EventKit
@testable import MindFriendApp

@MainActor
final class CalendarTriggerMonitorTests: XCTestCase {
    var monitor: CalendarTriggerMonitor!
    var mockSupabase: MockSupabaseClient!

    override func setUp() async throws {
        mockSupabase = MockSupabaseClient()
        monitor = CalendarTriggerMonitor(supabase: mockSupabase)
    }

    override func tearDown() async throws {
        monitor.stopPeriodicScanning()
        monitor = nil
        mockSupabase = nil
    }

    // MARK: - Event Classification Tests

    func testClassifyMeetingEvent() throws {
        let event = MockEKEvent()
        event.title = "Team Meeting with Client"
        event.startDate = Date().addingTimeInterval(60 * 60) // 1 hour from now
        event.endDate = event.startDate.addingTimeInterval(30 * 60) // 30 min duration

        let classified = monitor.classifyEvent(event)

        XCTAssertEqual(classified.classification, .meeting)
        XCTAssertEqual(classified.stressScore, EventClassification.meeting.defaultStressScore)
        XCTAssertFalse(classified.needsArmor)
    }

    func testClassifyDeadlineEvent() throws {
        let event = MockEKEvent()
        event.title = "Project Deadline - Submit Report"
        event.startDate = Date().addingTimeInterval(2 * 60 * 60)
        event.endDate = event.startDate.addingTimeInterval(60 * 60)

        let classified = monitor.classifyEvent(event)

        XCTAssertEqual(classified.classification, .deadline)
        XCTAssertEqual(classified.stressScore, EventClassification.deadline.defaultStressScore)
    }

    func testClassifyTravelEvent() throws {
        let event = MockEKEvent()
        event.title = "Flight to San Francisco"
        event.startDate = Date().addingTimeInterval(4 * 60 * 60)
        event.endDate = event.startDate.addingTimeInterval(3 * 60 * 60)

        let classified = monitor.classifyEvent(event)

        XCTAssertEqual(classified.classification, .travel)
        XCTAssertEqual(classified.stressScore, EventClassification.travel.defaultStressScore)
    }

    func testClassifyMedicalEvent() throws {
        let event = MockEKEvent()
        event.title = "Doctor Appointment - Annual Checkup"
        event.startDate = Date().addingTimeInterval(24 * 60 * 60)
        event.endDate = event.startDate.addingTimeInterval(45 * 60)

        let classified = monitor.classifyEvent(event)

        XCTAssertEqual(classified.classification, .medical)
        XCTAssertEqual(classified.stressScore, EventClassification.medical.defaultStressScore)
    }

    func testShortEventIncreasesStress() throws {
        let event = MockEKEvent()
        event.title = "Quick Standup"
        event.startDate = Date().addingTimeInterval(60 * 60)
        event.endDate = event.startDate.addingTimeInterval(15 * 60) // 15 min duration
        event.isAllDay = false

        let classified = monitor.classifyEvent(event)

        // Short events should have +0.2 stress adjustment
        XCTAssertGreaterThan(classified.stressScore, EventClassification.meeting.defaultStressScore)
    }

    func testNeedsArmorMaxStress() throws {
        let event = MockEKEvent()
        event.title = "Regular Meeting"
        event.eventIdentifier = "test-event-123"
        event.startDate = Date().addingTimeInterval(60 * 60)
        event.endDate = event.startDate.addingTimeInterval(60 * 60)

        // TODO: Mock calendar config with needsArmor set
        // For now, just verify the logic exists
        let classified = monitor.classifyEvent(event)

        XCTAssertFalse(classified.needsArmor) // Will be true once mocking is complete
    }

    // MARK: - Stress Score Tests

    func testWarrantsIntervention() throws {
        let event = MockEKEvent()
        event.title = "Important Presentation"
        event.startDate = Date().addingTimeInterval(60 * 60)
        event.endDate = event.startDate.addingTimeInterval(60 * 60)

        let classified = monitor.classifyEvent(event)

        // Meeting events have 0.7 stress by default
        XCTAssertTrue(classified.warrantsIntervention(threshold: 0.7))
        XCTAssertTrue(classified.warrantsIntervention(threshold: 0.6))
        XCTAssertFalse(classified.warrantsIntervention(threshold: 0.8))
    }

    // MARK: - Configuration Tests

    func testDefaultConfiguration() async throws {
        let config = try await monitor.getTriggerConfig()

        XCTAssertEqual(config.leadTimeMinutes, 45)
        XCTAssertEqual(config.minStressScore, 0.7)
        XCTAssertTrue(config.enabledCalendarIds.isEmpty)
        XCTAssertTrue(config.needsArmorEventIds.isEmpty)
    }

    func testUpdateConfiguration() async throws {
        var config = CalendarTriggerConfig.default
        config.enabledCalendarIds = ["calendar-1", "calendar-2"]
        config.leadTimeMinutes = 60
        config.minStressScore = 0.8

        try await monitor.updateTriggerConfig(config)

        let loaded = try await monitor.getTriggerConfig()
        XCTAssertEqual(loaded.enabledCalendarIds, ["calendar-1", "calendar-2"])
        XCTAssertEqual(loaded.leadTimeMinutes, 60)
        XCTAssertEqual(loaded.minStressScore, 0.8)
    }

    // MARK: - Permissions Tests

    func testHasCalendarPermissionWhenDenied() {
        // Note: This will always return false in test environment
        // unless calendar permission is actually granted
        let hasPermission = monitor.hasCalendarPermission()

        // In test environment, this should be false
        XCTAssertFalse(hasPermission)
    }
}

// MARK: - Mock Objects

class MockEKEvent: EKEvent {
    private var _title: String?
    private var _startDate: Date?
    private var _endDate: Date?
    private var _eventIdentifier: String = UUID().uuidString
    private var _isAllDay: Bool = false
    private var _notes: String?
    private var _mockAttendees: [EKParticipant] = []
    private var _mockCalendar: EKCalendar?

    override var title: String? {
        get { _title }
        set { _title = newValue }
    }

    override var startDate: Date! {
        get { _startDate ?? Date() }
        set { _startDate = newValue }
    }

    override var endDate: Date! {
        get { _endDate ?? Date() }
        set { _endDate = newValue }
    }

    override var eventIdentifier: String {
        get { _eventIdentifier }
    }

    override var isAllDay: Bool {
        get { _isAllDay }
        set { _isAllDay = newValue }
    }

    override var notes: String? {
        get { _notes }
        set { _notes = newValue }
    }

    override var attendees: [EKParticipant]? {
        get { _mockAttendees.isEmpty ? nil : _mockAttendees }
    }

    override var calendar: EKCalendar {
        get {
            if let calendar = _mockCalendar {
                return calendar
            }
            let eventStore = EKEventStore()
            let calendar = EKCalendar(for: .event, eventStore: eventStore)
            _mockCalendar = calendar
            return calendar
        }
    }
}
