import XCTest
@testable import MindFriendApp

final class SafetyPlanTests: XCTestCase {
    func testSafetyPlanCacheExpiry() {
        let payload = SafetyPlanPayload(warningSigns: [SafetyPlanItem(text: "Overwhelmed")])
        let settings = SafetyPlanSettings(allowAiReference: false, pinnedToQuickActions: false)
        let expired = SafetyPlanCachePayload(
            payload: payload,
            settings: settings,
            version: 1,
            cachedAt: Date().addingTimeInterval(-3600),
            expiresAt: Date().addingTimeInterval(-60)
        )
        let active = SafetyPlanCachePayload(
            payload: payload,
            settings: settings,
            version: 1,
            cachedAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )

        XCTAssertTrue(expired.isExpired)
        XCTAssertFalse(active.isExpired)
    }

    func testTrustedContactValidationAndFormatting() {
        let validContact = TrustedContact(
            name: "Sam",
            phone: "+15555551234",
            relationship: .friend,
            preferredMethod: .text
        )

        let invalidContact = TrustedContact(
            name: "Alex",
            phone: "5551234",
            relationship: .friend,
            preferredMethod: .call
        )

        XCTAssertTrue(validContact.isValidPhone)
        XCTAssertFalse(invalidContact.isValidPhone)
        XCTAssertEqual(validContact.formattedPhone, "+15555551234")
    }
}
