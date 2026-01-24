import XCTest
@testable import MindFriendApp

/// Tests for InterventionService
/// Focus: PHI sanitization before network transmission
final class InterventionServiceTests: XCTestCase {

    // MARK: - TriggerContext Sanitization Tests

    func testSanitizeBiometrics_RemovesRawHeartRate() {
        // Given: Context with raw heart rate value (PHI)
        let context = TriggerContext(
            biometrics: TriggerContext.Biometrics(
                heartRate: 120.0,  // Raw PHI value
                hrv: nil
            ),
            timeOfDay: "morning",
            recentMood: 7,
            upcomingEvents: nil,
            timingConfidence: 0.85
        )

        // When: Sanitizing context
        let sanitized = context.sanitized()

        // Then: Raw HR value removed, category/flags preserved
        XCTAssertNotNil(sanitized.biometrics)
        XCTAssertEqual(sanitized.biometrics?.hasElevatedHR, true, "Should flag elevated HR")
        XCTAssertEqual(sanitized.biometrics?.hrCategory, "elevated", "Should categorize as 'elevated'")
        XCTAssertNil(sanitized.biometrics?.hasLowHRV, "Should be nil when no HRV data")
        XCTAssertNil(sanitized.biometrics?.hrvCategory, "Should be nil when no HRV data")

        // Non-PHI fields preserved
        XCTAssertEqual(sanitized.timeOfDay, "morning")
        XCTAssertEqual(sanitized.recentMood, 7)
        XCTAssertEqual(sanitized.timingConfidence, 0.85)
    }

    func testSanitizeBiometrics_RemovesRawHRV() {
        // Given: Context with raw HRV value (PHI)
        let context = TriggerContext(
            biometrics: TriggerContext.Biometrics(
                heartRate: nil,
                hrv: 25.0  // Raw PHI value (very low)
            ),
            timeOfDay: "afternoon",
            recentMood: nil,
            upcomingEvents: nil,
            timingConfidence: nil
        )

        // When: Sanitizing context
        let sanitized = context.sanitized()

        // Then: Raw HRV value removed, category/flags preserved
        XCTAssertNotNil(sanitized.biometrics)
        XCTAssertEqual(sanitized.biometrics?.hasLowHRV, true, "Should flag low HRV")
        XCTAssertEqual(sanitized.biometrics?.hrvCategory, "very_low", "Should categorize as 'very_low'")
        XCTAssertNil(sanitized.biometrics?.hasElevatedHR, "Should be nil when no HR data")
        XCTAssertNil(sanitized.biometrics?.hrCategory, "Should be nil when no HR data")
    }

    func testSanitizeBiometrics_CategorizesBothMetrics() {
        // Given: Context with both HR and HRV (PHI)
        let context = TriggerContext(
            biometrics: TriggerContext.Biometrics(
                heartRate: 75.0,  // Normal
                hrv: 60.0         // Normal
            ),
            timeOfDay: "evening",
            recentMood: nil,
            upcomingEvents: nil,
            timingConfidence: nil
        )

        // When: Sanitizing context
        let sanitized = context.sanitized()

        // Then: Both metrics categorized correctly
        XCTAssertNotNil(sanitized.biometrics)
        XCTAssertEqual(sanitized.biometrics?.hasElevatedHR, false, "75 bpm is normal")
        XCTAssertEqual(sanitized.biometrics?.hrCategory, "normal")
        XCTAssertEqual(sanitized.biometrics?.hasLowHRV, false, "60ms is normal")
        XCTAssertEqual(sanitized.biometrics?.hrvCategory, "normal")
    }

    func testSanitizeBiometrics_HeartRateCategories() {
        let testCases: [(hr: Double, expectedCategory: String, expectedElevated: Bool)] = [
            (50.0, "low", false),           // Low HR
            (60.0, "normal", false),        // Lower bound normal
            (100.0, "normal", false),       // Upper bound normal
            (101.0, "elevated", true),      // Just elevated
            (120.0, "elevated", true),      // Elevated
            (121.0, "very_high", true),     // Very high
            (150.0, "very_high", true)      // Very high
        ]

        for testCase in testCases {
            let context = TriggerContext(
                biometrics: TriggerContext.Biometrics(heartRate: testCase.hr, hrv: nil),
                timeOfDay: nil,
                recentMood: nil,
                upcomingEvents: nil,
                timingConfidence: nil
            )

            let sanitized = context.sanitized()

            XCTAssertEqual(
                sanitized.biometrics?.hrCategory,
                testCase.expectedCategory,
                "HR \(testCase.hr) should be '\(testCase.expectedCategory)'"
            )
            XCTAssertEqual(
                sanitized.biometrics?.hasElevatedHR,
                testCase.expectedElevated,
                "HR \(testCase.hr) elevated flag should be \(testCase.expectedElevated)"
            )
        }
    }

    func testSanitizeBiometrics_HRVCategories() {
        let testCases: [(hrv: Double, expectedCategory: String, expectedLow: Bool)] = [
            (15.0, "very_low", true),       // Very low HRV (< 20, < 30)
            (25.0, "low", true),            // Low HRV (< 30, 20-50)
            (30.0, "low", false),           // Low HRV (not < 30, 20-50)
            (50.0, "low", false),           // Low HRV (upper bound, 20-50)
            (51.0, "normal", false),        // Normal HRV (50-100)
            (100.0, "normal", false),       // Normal HRV (upper bound)
            (101.0, "high", false),         // High HRV (> 100)
            (120.0, "high", false)          // High HRV
        ]

        for testCase in testCases {
            let context = TriggerContext(
                biometrics: TriggerContext.Biometrics(heartRate: nil, hrv: testCase.hrv),
                timeOfDay: nil,
                recentMood: nil,
                upcomingEvents: nil,
                timingConfidence: nil
            )

            let sanitized = context.sanitized()

            XCTAssertEqual(
                sanitized.biometrics?.hrvCategory,
                testCase.expectedCategory,
                "HRV \(testCase.hrv) should be '\(testCase.expectedCategory)'"
            )
            XCTAssertEqual(
                sanitized.biometrics?.hasLowHRV,
                testCase.expectedLow,
                "HRV \(testCase.hrv) low flag should be \(testCase.expectedLow)"
            )
        }
    }

    func testSanitizeBiometrics_NilWhenNoBiometrics() {
        // Given: Context without biometric data
        let context = TriggerContext(
            biometrics: nil,
            timeOfDay: "morning",
            recentMood: 5,
            upcomingEvents: nil,
            timingConfidence: 0.7
        )

        // When: Sanitizing context
        let sanitized = context.sanitized()

        // Then: Biometrics should be nil
        XCTAssertNil(sanitized.biometrics, "Should be nil when no biometric data")

        // Other fields preserved
        XCTAssertEqual(sanitized.timeOfDay, "morning")
        XCTAssertEqual(sanitized.recentMood, 5)
        XCTAssertEqual(sanitized.timingConfidence, 0.7)
    }

    func testSanitizeEvents_NilWhenNoEvents() {
        // Given: Context without events
        let context = TriggerContext(
            biometrics: TriggerContext.Biometrics(heartRate: 70.0, hrv: 50.0),
            timeOfDay: "afternoon",
            recentMood: 6,
            upcomingEvents: nil,
            timingConfidence: 0.8
        )

        // When: Sanitizing context
        let sanitized = context.sanitized()

        // Then: Events should be nil
        XCTAssertNil(sanitized.upcomingEvents, "Should be nil when no events")
    }

    // MARK: - Calendar Event Sanitization Tests

    func testSanitizeEvents_RemovesEventTitles() {
        // Given: Context with calendar events containing titles (PII)
        let event1StartDate = ISO8601DateFormatter().date(from: "2026-01-24T14:00:00Z")!
        let event1EndDate = ISO8601DateFormatter().date(from: "2026-01-24T15:00:00Z")!
        let event2StartDate = ISO8601DateFormatter().date(from: "2026-01-24T10:00:00Z")!
        let event2EndDate = ISO8601DateFormatter().date(from: "2026-01-24T11:00:00Z")!

        let context = TriggerContext(
            biometrics: nil,
            timeOfDay: "morning",
            recentMood: nil,
            upcomingEvents: [
                ClassifiedEvent(
                    id: "event-1",
                    title: "Therapy Appointment",  // PII - must be removed
                    startDate: event1StartDate,
                    endDate: event1EndDate,
                    classification: .medical,
                    stressScore: 0.6,
                    isAllDay: false,
                    needsArmor: true,
                    calendarId: "calendar-1"
                ),
                ClassifiedEvent(
                    id: "event-2",
                    title: "Team Meeting",  // PII - must be removed
                    startDate: event2StartDate,
                    endDate: event2EndDate,
                    classification: .meeting,
                    stressScore: 0.4,
                    isAllDay: false,
                    needsArmor: false,
                    calendarId: "calendar-1"
                )
            ],
            timingConfidence: 0.9
        )

        // When: Sanitizing context
        let sanitized = context.sanitized()

        // Then: Event titles removed, metadata preserved
        XCTAssertNotNil(sanitized.upcomingEvents)
        XCTAssertEqual(sanitized.upcomingEvents?.count, 2)

        let sanitizedEvent1 = sanitized.upcomingEvents?[0]
        XCTAssertEqual(sanitizedEvent1?.id, "event-1")
        XCTAssertEqual(sanitizedEvent1?.classification, "medical")
        XCTAssertEqual(sanitizedEvent1?.stressScore, 0.6)
        XCTAssertEqual(sanitizedEvent1?.needsArmor, true)
        XCTAssertEqual(sanitizedEvent1?.hasTitle, true, "Should flag that title existed")
        // Note: startDate is converted to ISO8601 string format in sanitized version

        let sanitizedEvent2 = sanitized.upcomingEvents?[1]
        XCTAssertEqual(sanitizedEvent2?.id, "event-2")
        XCTAssertEqual(sanitizedEvent2?.classification, "meeting")
        XCTAssertEqual(sanitizedEvent2?.stressScore, 0.4)
        XCTAssertEqual(sanitizedEvent2?.needsArmor, false)
        XCTAssertEqual(sanitizedEvent2?.hasTitle, true, "Should flag that title existed")
    }

    // MARK: - Integration Tests

    func testSanitizeFullContext_RemovesAllPHI() {
        // Given: Full context with all PHI fields
        let eventStartDate = ISO8601DateFormatter().date(from: "2026-01-25T09:00:00Z")!
        let eventEndDate = ISO8601DateFormatter().date(from: "2026-01-25T10:00:00Z")!

        let context = TriggerContext(
            biometrics: TriggerContext.Biometrics(
                heartRate: 110.0,  // PHI
                hrv: 35.0          // PHI
            ),
            timeOfDay: "evening",
            recentMood: 4,
            upcomingEvents: [
                ClassifiedEvent(
                    id: "event-1",
                    title: "Doctor Appointment",  // PII
                    startDate: eventStartDate,
                    endDate: eventEndDate,
                    classification: .medical,
                    stressScore: 0.7,
                    isAllDay: false,
                    needsArmor: true,
                    calendarId: "calendar-1"
                )
            ],
            timingConfidence: 0.95
        )

        // When: Sanitizing full context
        let sanitized = context.sanitized()

        // Then: All PHI removed, metadata preserved

        // Biometrics: categories only
        XCTAssertEqual(sanitized.biometrics?.hasElevatedHR, true)
        XCTAssertEqual(sanitized.biometrics?.hrCategory, "elevated")
        XCTAssertEqual(sanitized.biometrics?.hasLowHRV, false, "35 is not < 30")
        XCTAssertEqual(sanitized.biometrics?.hrvCategory, "low")

        // Events: no titles, only metadata
        XCTAssertEqual(sanitized.upcomingEvents?.count, 1)
        XCTAssertEqual(sanitized.upcomingEvents?[0].classification, "medical")
        XCTAssertEqual(sanitized.upcomingEvents?[0].stressScore, 0.7)
        XCTAssertEqual(sanitized.upcomingEvents?[0].needsArmor, true)
        XCTAssertEqual(sanitized.upcomingEvents?[0].hasTitle, true)

        // Other fields preserved
        XCTAssertEqual(sanitized.timeOfDay, "evening")
        XCTAssertEqual(sanitized.recentMood, 4)
        XCTAssertEqual(sanitized.timingConfidence, 0.95)
    }

    func testSanitizeMinimalContext_HandlesNilFields() {
        // Given: Minimal context with only required fields
        let context = TriggerContext(
            biometrics: nil,
            timeOfDay: nil,
            recentMood: nil,
            upcomingEvents: nil,
            timingConfidence: nil
        )

        // When: Sanitizing minimal context
        let sanitized = context.sanitized()

        // Then: All fields should be nil
        XCTAssertNil(sanitized.biometrics)
        XCTAssertNil(sanitized.timeOfDay)
        XCTAssertNil(sanitized.recentMood)
        XCTAssertNil(sanitized.upcomingEvents)
        XCTAssertNil(sanitized.timingConfidence)
    }
}
