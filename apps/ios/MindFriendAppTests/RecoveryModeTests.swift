import XCTest
@testable import MindFriendApp

/// Tests for Recovery Mode UX feature
/// See: kimispecs/03-recovery-mode-ux-spec.md
final class RecoveryModeTests: XCTestCase {

    // MARK: - RecoveryModeState Tests

    func testInactiveRecoveryModeCanManuallyExit() {
        let state = RecoveryModeState.inactive
        XCTAssertFalse(state.isActive)
        XCTAssertTrue(state.canManuallyExit, "Inactive state should allow exit")
    }

    func testActiveRecoveryModeCannotExitBefore24Hours() {
        let enteredAt = Date().addingTimeInterval(-12 * 3600) // 12 hours ago
        let state = RecoveryModeState(
            isActive: true,
            enteredAt: enteredAt,
            reason: .manual
        )

        XCTAssertTrue(state.isActive)
        XCTAssertFalse(state.canManuallyExit, "Should not be able to exit before 24h")
        XCTAssertNotNil(state.hoursUntilExitAllowed, "Should show hours remaining")
        XCTAssertEqual(state.hoursUntilExitAllowed, 12, "Should show 12 hours remaining")
    }

    func testActiveRecoveryModeCanExitAfter24Hours() {
        let enteredAt = Date().addingTimeInterval(-25 * 3600) // 25 hours ago
        let state = RecoveryModeState(
            isActive: true,
            enteredAt: enteredAt,
            reason: .manual
        )

        XCTAssertTrue(state.isActive)
        XCTAssertTrue(state.canManuallyExit, "Should be able to exit after 24h")
        XCTAssertNil(state.hoursUntilExitAllowed, "Should not show hours remaining")
    }

    func testRecoveryModeReasonDisplayText() {
        XCTAssertEqual(
            RecoveryModeReason.manual.displayText,
            "You enabled recovery mode"
        )
        XCTAssertEqual(
            RecoveryModeReason.autoConsecutiveLowMood.displayText,
            "We noticed you've had some tough days"
        )
    }

    func testTimeUntilExitFormatted() {
        // 20 hours ago - should show "4h"
        let state20h = RecoveryModeState(
            isActive: true,
            enteredAt: Date().addingTimeInterval(-20 * 3600),
            reason: .manual
        )
        XCTAssertEqual(state20h.timeUntilExitFormatted, "4h")

        // 23.5 hours ago - should show "< 1h"
        let state23h = RecoveryModeState(
            isActive: true,
            enteredAt: Date().addingTimeInterval(-23.5 * 3600),
            reason: .manual
        )
        XCTAssertEqual(state23h.timeUntilExitFormatted, "< 1h")

        // 25 hours ago - should be nil (can exit)
        let state25h = RecoveryModeState(
            isActive: true,
            enteredAt: Date().addingTimeInterval(-25 * 3600),
            reason: .manual
        )
        XCTAssertNil(state25h.timeUntilExitFormatted)
    }

    // MARK: - ToggleRecoveryModeResult Tests

    func testToggleResultSuccess() {
        let result = ToggleRecoveryModeResult(
            success: true,
            errorMessage: nil,
            newState: RecoveryModeState(isActive: true, enteredAt: Date(), reason: .manual)
        )

        XCTAssertTrue(result.success)
        XCTAssertFalse(result.failed)
        XCTAssertNil(result.errorMessage)
    }

    func testToggleResultFailure() {
        let result = ToggleRecoveryModeResult(
            success: false,
            errorMessage: "Must wait 24 hours before exiting recovery mode",
            newState: .inactive
        )

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.failed)
        XCTAssertNotNil(result.errorMessage)
    }

    // MARK: - CodingKeys Tests

    func testRecoveryModeStateCodingKeys() {
        let json = """
        {
            "recovery_mode_active": true,
            "recovery_mode_entered_at": "2025-01-20T12:00:00Z",
            "recovery_mode_reason": "manual"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let state = try decoder.decode(RecoveryModeState.self, from: json)
            XCTAssertTrue(state.isActive)
            XCTAssertNotNil(state.enteredAt)
            XCTAssertEqual(state.reason, .manual)
        } catch {
            XCTFail("Failed to decode RecoveryModeState: \(error)")
        }
    }

    func testRecoveryModeStateDecodesAutoReason() {
        let json = """
        {
            "recovery_mode_active": true,
            "recovery_mode_entered_at": "2025-01-20T12:00:00Z",
            "recovery_mode_reason": "auto_consecutive_low_mood"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let state = try decoder.decode(RecoveryModeState.self, from: json)
            XCTAssertTrue(state.isActive)
            XCTAssertEqual(state.reason, .autoConsecutiveLowMood)
        } catch {
            XCTFail("Failed to decode RecoveryModeState: \(error)")
        }
    }

    func testRecoveryModeStateHandlesNullFields() {
        let json = """
        {
            "recovery_mode_active": false,
            "recovery_mode_entered_at": null,
            "recovery_mode_reason": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let state = try decoder.decode(RecoveryModeState.self, from: json)
            XCTAssertFalse(state.isActive)
            XCTAssertNil(state.enteredAt)
            XCTAssertNil(state.reason)
        } catch {
            XCTFail("Failed to decode RecoveryModeState with nulls: \(error)")
        }
    }
}
