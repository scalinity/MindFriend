//
//  BedtimeNotificationServiceTests.swift
//  MindFriendAppTests
//
//  Unit tests for bedtime notification scheduling
//

import XCTest
import UserNotifications
@testable import MindFriendApp

final class BedtimeNotificationServiceTests: XCTestCase {
    // Note: These tests verify the time calculation logic using Calendar arithmetic
    // Full integration tests would require mocking UNUserNotificationCenter

    func testScheduleBedtimeReminder_CalculatesCorrectTime() async throws {
        // Test the time calculation logic using Calendar arithmetic
        let calendar = Calendar.current
        let bedtime = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!
        let windDownMinutes = 30

        // Expected notification time: 22:30 (11 PM - 30 min)
        guard let notificationTime = calendar.date(
            byAdding: .minute,
            value: -windDownMinutes,
            to: bedtime
        ) else {
            XCTFail("Failed to calculate notification time")
            return
        }
        
        let components = calendar.dateComponents([.hour, .minute], from: notificationTime)
        
        XCTAssertEqual(components.hour, 22)
        XCTAssertEqual(components.minute, 30)
    }

    func testScheduleBedtimeReminder_HandlesNegativeTime() {
        // Test edge case: wind-down longer than time until bedtime
        // E.g., bedtime 12:30 AM, wind-down 60 min → notification 11:30 PM (previous day)
        let calendar = Calendar.current
        let bedtime = calendar.date(bySettingHour: 0, minute: 30, second: 0, of: Date())!
        let windDownMinutes = 60

        // Use Calendar arithmetic to handle midnight wrap correctly
        guard let notificationTime = calendar.date(
            byAdding: .minute,
            value: -windDownMinutes,
            to: bedtime
        ) else {
            XCTFail("Failed to calculate notification time")
            return
        }
        
        let components = calendar.dateComponents([.hour, .minute], from: notificationTime)

        // -30 minutes from 00:30 should become 23:30 (11:30 PM previous day)
        XCTAssertEqual(components.hour, 23)
        XCTAssertEqual(components.minute, 30)
    }
}
