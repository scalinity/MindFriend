//
//  CrashReporterTests.swift
//  MindFriendAppTests
//
//  Created by Claude Code on 2026-01-18.
//  Copyright © 2026 MindFriend. All rights reserved.
//

import XCTest
@testable import MindFriendApp
import Sentry

final class CrashReporterTests: XCTestCase {

    // MARK: - Email Scrubbing Tests

    func testScrubEmail_BasicEmail() {
        let input = "Contact us at support@mindfriend.app"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "Contact us at [EMAIL_REDACTED]")
    }

    func testScrubEmail_MultipleEmails() {
        let input = "Email john@example.com or jane@company.org for help"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "Email [EMAIL_REDACTED] or [EMAIL_REDACTED] for help")
    }

    func testScrubEmail_EmailWithSubdomain() {
        let input = "Admin email: admin@support.mindfriend.app"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "Admin email: [EMAIL_REDACTED]")
    }

    // MARK: - Phone Number Scrubbing Tests

    func testScrubPhone_USFormat() {
        let input = "Call 555-123-4567 for support"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "Call [PHONE_REDACTED] for support")
    }

    func testScrubPhone_ParenthesesFormat() {
        let input = "Emergency: (555) 987-6543"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "Emergency: [PHONE_REDACTED]")
    }

    func testScrubPhone_InternationalFormat() {
        let input = "International: +1-555-123-4567"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "International: [PHONE_REDACTED]")
    }

    func testScrubPhone_DotsFormat() {
        let input = "Contact: 555.123.4567"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "Contact: [PHONE_REDACTED]")
    }

    // MARK: - Token/API Key Scrubbing Tests

    func testScrubToken_BearerToken() {
        let input = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "Authorization: [TOKEN_REDACTED]")
    }

    func testScrubToken_APIKey() {
        let input = "API_KEY=sk_live_51H8xJ2KqF9xY3zC8"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "API_KEY=[TOKEN_REDACTED]")
    }

    func testScrubToken_AccessToken() {
        let input = "access_token: ghp_1234567890abcdefghijklmnopqrstuvwxyz"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "access_token: [TOKEN_REDACTED]")
    }

    // MARK: - Credit Card Scrubbing Tests

    func testScrubCreditCard_Visa() {
        let input = "Card: 4532-1234-5678-9010"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "Card: [CARD_REDACTED]")
    }

    func testScrubCreditCard_NoSpaces() {
        let input = "Payment: 4532123456789010"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "Payment: [CARD_REDACTED]")
    }

    func testScrubCreditCard_WithSpaces() {
        let input = "CC: 4532 1234 5678 9010"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "CC: [CARD_REDACTED]")
    }

    // MARK: - SSN Scrubbing Tests

    func testScrubSSN_DashFormat() {
        let input = "SSN: 123-45-6789"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "SSN: [SSN_REDACTED]")
    }

    func testScrubSSN_NoSpaces() {
        let input = "Social Security: 987654321"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "Social Security: [SSN_REDACTED]")
    }

    // MARK: - UUID Scrubbing Tests

    func testScrubUUID_Standard() {
        let input = "User ID: 550e8400-e29b-41d4-a716-446655440000"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "User ID: [UUID_REDACTED]")
    }

    func testScrubUUID_Uppercase() {
        let input = "Session: 550E8400-E29B-41D4-A716-446655440000"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "Session: [UUID_REDACTED]")
    }

    // MARK: - Multiple Pattern Tests

    func testScrubMultiplePatterns() {
        let input = """
        User: user@example.com
        Phone: 555-123-4567
        Card: 4532-1234-5678-9010
        SSN: 123-45-6789
        UUID: 550e8400-e29b-41d4-a716-446655440000
        Token: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9
        """

        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertTrue(scrubbed.contains("[EMAIL_REDACTED]"))
        XCTAssertTrue(scrubbed.contains("[PHONE_REDACTED]"))
        XCTAssertTrue(scrubbed.contains("[CARD_REDACTED]"))
        XCTAssertTrue(scrubbed.contains("[SSN_REDACTED]"))
        XCTAssertTrue(scrubbed.contains("[UUID_REDACTED]"))
        XCTAssertTrue(scrubbed.contains("[TOKEN_REDACTED]"))

        // Ensure original values are NOT present
        XCTAssertFalse(scrubbed.contains("user@example.com"))
        XCTAssertFalse(scrubbed.contains("555-123-4567"))
        XCTAssertFalse(scrubbed.contains("4532-1234-5678-9010"))
        XCTAssertFalse(scrubbed.contains("123-45-6789"))
        XCTAssertFalse(scrubbed.contains("550e8400-e29b-41d4-a716-446655440000"))
        XCTAssertFalse(scrubbed.contains("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"))
    }

    func testScrubNoMatchReturnsOriginal() {
        let input = "This is a normal message with no PII"
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, input)
    }

    // MARK: - Edge Cases

    func testScrubEmptyString() {
        let input = ""
        let scrubbed = CrashReporter.scrubText(input)

        XCTAssertEqual(scrubbed, "")
    }

    func testScrubVeryLongString() {
        // Test max depth protection (default 10 levels)
        let input = String(repeating: "user@example.com ", count: 100)
        let scrubbed = CrashReporter.scrubText(input)

        // Should redact all emails
        XCTAssertFalse(scrubbed.contains("user@example.com"))
        XCTAssertTrue(scrubbed.contains("[EMAIL_REDACTED]"))
    }

    func testScrubPIIInSentryEvent() {
        // Create a test event with PII
        let event = Event()
        event.message = SentryMessage(formatted: "User email: user@example.com, phone: 555-123-4567")

        // Apply scrubbing
        let scrubbedEvent = CrashReporter.scrubPII(event)

        // Verify PII was scrubbed
        XCTAssertNotNil(scrubbedEvent?.message?.formatted)
        XCTAssertTrue(scrubbedEvent!.message!.formatted.contains("[EMAIL_REDACTED]"))
        XCTAssertTrue(scrubbedEvent!.message!.formatted.contains("[PHONE_REDACTED]"))
        XCTAssertFalse(scrubbedEvent!.message!.formatted.contains("user@example.com"))
        XCTAssertFalse(scrubbedEvent!.message!.formatted.contains("555-123-4567"))
    }

    func testScrubPIIInException() {
        let event = Event()
        let exception = Exception(
            value: "Error processing payment for card 4532-1234-5678-9010",
            type: "PaymentError"
        )
        event.exceptions = [exception]

        let scrubbedEvent = CrashReporter.scrubPII(event)

        XCTAssertNotNil(scrubbedEvent?.exceptions?.first?.value)
        XCTAssertTrue(scrubbedEvent!.exceptions!.first!.value!.contains("[CARD_REDACTED]"))
        XCTAssertFalse(scrubbedEvent!.exceptions!.first!.value!.contains("4532-1234-5678-9010"))
    }

    func testScrubPIIInBreadcrumbs() {
        let event = Event()
        let breadcrumb = Breadcrumb()
        breadcrumb.message = "User logged in from user@example.com"
        event.breadcrumbs = [breadcrumb]

        let scrubbedEvent = CrashReporter.scrubPII(event)

        XCTAssertNotNil(scrubbedEvent?.breadcrumbs?.first?.message)
        XCTAssertTrue(scrubbedEvent!.breadcrumbs!.first!.message!.contains("[EMAIL_REDACTED]"))
        XCTAssertFalse(scrubbedEvent!.breadcrumbs!.first!.message!.contains("user@example.com"))
    }

    func testScrubPIIInUserData() {
        let event = Event()
        let user = User()
        user.email = "user@example.com"
        user.userId = "550e8400-e29b-41d4-a716-446655440000"
        event.user = user

        let scrubbedEvent = CrashReporter.scrubPII(event)

        // User email and ID should be scrubbed
        XCTAssertNotNil(scrubbedEvent?.user?.email)
        XCTAssertEqual(scrubbedEvent?.user?.email, "[EMAIL_REDACTED]")
        XCTAssertNotNil(scrubbedEvent?.user?.userId)
        XCTAssertEqual(scrubbedEvent?.user?.userId, "[UUID_REDACTED]")
    }

    func testScrubPIIInExtraData() {
        let event = Event()
        event.extra = [
            "userEmail": "user@example.com",
            "phoneNumber": "555-123-4567",
            "normalData": "This is fine"
        ]

        let scrubbedEvent = CrashReporter.scrubPII(event)

        XCTAssertNotNil(scrubbedEvent?.extra)
        XCTAssertEqual(scrubbedEvent?.extra?["userEmail"] as? String, "[EMAIL_REDACTED]")
        XCTAssertEqual(scrubbedEvent?.extra?["phoneNumber"] as? String, "[PHONE_REDACTED]")
        XCTAssertEqual(scrubbedEvent?.extra?["normalData"] as? String, "This is fine")
    }

    func testScrubPIIInTags() {
        let event = Event()
        event.tags = [
            "email": "user@example.com",
            "session": "550e8400-e29b-41d4-a716-446655440000",
            "environment": "production"
        ]

        let scrubbedEvent = CrashReporter.scrubPII(event)

        XCTAssertNotNil(scrubbedEvent?.tags)
        XCTAssertEqual(scrubbedEvent?.tags?["email"], "[EMAIL_REDACTED]")
        XCTAssertEqual(scrubbedEvent?.tags?["session"], "[UUID_REDACTED]")
        XCTAssertEqual(scrubbedEvent?.tags?["environment"], "production")
    }

    // MARK: - Performance Tests

    func testScrubTextPerformance() {
        let input = String(repeating: "user@example.com phone:555-123-4567 card:4532-1234-5678-9010 ", count: 10)

        measure {
            _ = CrashReporter.scrubText(input)
        }
    }

    func testScrubPIIEventPerformance() {
        let event = Event()
        event.message = SentryMessage(formatted: "user@example.com 555-123-4567")
        event.extra = [
            "data1": "user@example.com",
            "data2": "555-123-4567",
            "data3": "4532-1234-5678-9010"
        ]

        measure {
            _ = CrashReporter.scrubPII(event)
        }
    }
}
