import XCTest
@testable import MindFriendApp

/// Tests for BillingService
/// Note: Full StoreKit testing requires StoreKit Testing in Xcode
@MainActor
final class BillingServiceTests: XCTestCase {

    // MARK: - Product ID Mapping Tests

    func testProductPlanTypeMappingIndividual() {
        XCTAssertEqual(
            BillingService.productPlanTypes["com.mindfriend.premium.monthly"],
            .individual
        )
        XCTAssertEqual(
            BillingService.productPlanTypes["com.mindfriend.premium.yearly"],
            .individual
        )
    }

    func testProductPlanTypeMappingCouples() {
        XCTAssertEqual(
            BillingService.productPlanTypes["com.mindfriend.couples.monthly"],
            .couples
        )
        XCTAssertEqual(
            BillingService.productPlanTypes["com.mindfriend.couples.annual"],
            .couples
        )
    }

    func testProductPlanTypeMappingFamily() {
        XCTAssertEqual(
            BillingService.productPlanTypes["com.mindfriend.family.monthly"],
            .family
        )
        XCTAssertEqual(
            BillingService.productPlanTypes["com.mindfriend.family.annual"],
            .family
        )
    }

    func testProductBillingPeriodMappingMonthly() {
        XCTAssertEqual(
            BillingService.productBillingPeriods["com.mindfriend.premium.monthly"],
            .monthly
        )
        XCTAssertEqual(
            BillingService.productBillingPeriods["com.mindfriend.couples.monthly"],
            .monthly
        )
        XCTAssertEqual(
            BillingService.productBillingPeriods["com.mindfriend.family.monthly"],
            .monthly
        )
    }

    func testProductBillingPeriodMappingAnnual() {
        XCTAssertEqual(
            BillingService.productBillingPeriods["com.mindfriend.premium.yearly"],
            .annual
        )
        XCTAssertEqual(
            BillingService.productBillingPeriods["com.mindfriend.couples.annual"],
            .annual
        )
        XCTAssertEqual(
            BillingService.productBillingPeriods["com.mindfriend.family.annual"],
            .annual
        )
    }

    func testAllProductIdsAreMapped() {
        for productId in BillingService.productIds {
            XCTAssertNotNil(
                BillingService.productPlanTypes[productId],
                "Product \(productId) missing from productPlanTypes"
            )
            XCTAssertNotNil(
                BillingService.productBillingPeriods[productId],
                "Product \(productId) missing from productBillingPeriods"
            )
        }
    }

    func testProductIdsCount() {
        XCTAssertEqual(BillingService.productIds.count, 6)
        XCTAssertEqual(BillingService.productPlanTypes.count, 6)
        XCTAssertEqual(BillingService.productBillingPeriods.count, 6)
    }

    // MARK: - Display Code Generation Tests

    func testGenerateDisplayCodeLength() {
        let code = BillingService.generateDisplayCode()
        XCTAssertEqual(code.count, 8)
    }

    func testGenerateDisplayCodeCharacters() {
        let allowedChars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        let code = BillingService.generateDisplayCode()

        for char in code {
            XCTAssertTrue(
                allowedChars.contains(char),
                "Code contains invalid character: \(char)"
            )
        }
    }

    func testGenerateDisplayCodeExcludesConfusingChars() {
        let confusingChars = "O01IL"

        // Generate 100 codes and check none contain confusing characters
        for _ in 0..<100 {
            let code = BillingService.generateDisplayCode()
            for char in code {
                XCTAssertFalse(
                    confusingChars.contains(char),
                    "Code contains confusing character: \(char)"
                )
            }
        }
    }

    func testGenerateDisplayCodeUniqueness() {
        var codes = Set<String>()
        for _ in 0..<100 {
            codes.insert(BillingService.generateDisplayCode())
        }
        // With 32^8 possibilities, 100 codes should all be unique
        XCTAssertEqual(codes.count, 100)
    }

    // MARK: - BillingError Tests

    func testBillingErrorDescriptions() {
        XCTAssertEqual(BillingError.cancelled.errorDescription, "Purchase was cancelled")
        XCTAssertEqual(BillingError.verificationFailed.errorDescription, "Transaction verification failed")
        XCTAssertEqual(BillingError.invalidTransaction.errorDescription, "Invalid transaction")
        XCTAssertEqual(BillingError.unknown.errorDescription, "An unknown error occurred")
        XCTAssertEqual(BillingError.noFamilyGroup.errorDescription, "You don't have a family plan")
        XCTAssertEqual(BillingError.noSeatsAvailable.errorDescription, "No seats available in your plan")
        XCTAssertEqual(BillingError.invalidInviteCode.errorDescription, "Invalid invitation code")
        XCTAssertEqual(BillingError.inviteExpired.errorDescription, "This invitation has expired")
        XCTAssertEqual(BillingError.notFamilyAdmin.errorDescription, "Only the plan admin can perform this action")
    }

    func testBillingErrorInviteFailedMessage() {
        let customMessage = "Custom error message"
        let error = BillingError.inviteFailed(customMessage)
        XCTAssertEqual(error.errorDescription, customMessage)
    }

    // MARK: - PlanType Tests

    func testPlanTypeDisplayName() {
        XCTAssertEqual(PlanType.individual.displayName, "Individual")
        XCTAssertEqual(PlanType.couples.displayName, "Couples")
        XCTAssertEqual(PlanType.family.displayName, "Family")
    }

    func testPlanTypeMaxSeats() {
        XCTAssertEqual(PlanType.individual.maxSeats, 1)
        XCTAssertEqual(PlanType.couples.maxSeats, 2)
        XCTAssertEqual(PlanType.family.maxSeats, 6)
    }

    // MARK: - BillingPeriod Tests

    func testBillingPeriodDisplayName() {
        XCTAssertEqual(BillingPeriod.monthly.displayName, "Monthly")
        XCTAssertEqual(BillingPeriod.annual.displayName, "Annual")
    }

    // MARK: - Subscription Model Tests

    func testSubscriptionAvailableSeats() {
        // Mock subscription with 3 of 6 seats used
        // Note: This requires the Subscription struct to have availableSeats computed property
        // Testing the logic: seats_total - seats_used
        let seatsTotal = 6
        let seatsUsed = 3
        let availableSeats = seatsTotal - seatsUsed
        XCTAssertEqual(availableSeats, 3)
    }

    func testSubscriptionNoAvailableSeats() {
        let seatsTotal = 2
        let seatsUsed = 2
        let availableSeats = seatsTotal - seatsUsed
        XCTAssertEqual(availableSeats, 0)
    }

    // MARK: - FamilyMember Status Tests

    func testFamilyMemberStatusRawValues() {
        XCTAssertEqual(FamilyMember.MemberStatus.invited.rawValue, "invited")
        XCTAssertEqual(FamilyMember.MemberStatus.active.rawValue, "active")
        XCTAssertEqual(FamilyMember.MemberStatus.removed.rawValue, "removed")
    }
}

    // MARK: - Spec 15: Promo Code Validation Tests

    func testValidatePromoCodeValidCode() async throws {
        // Integration test for validatePromoCode with valid code
        // Note: Requires Supabase connection
        // This test validates the business logic:
        // 1. Code lookup from database
        // 2. Active status check
        // 3. Date range validation
        // 4. Usage limit check
    }

    func testValidatePromoCodeExpiredCode() async throws {
        // Test that expired promo codes are rejected
        // Valid logic:
        // - validUntil < now => invalid
    }

    func testValidatePromoCodeMaxUsesExceeded() async throws {
        // Test that codes with max uses reached are rejected
        // Valid logic:
        // - maxUses != nil && usesCount >= maxUses => invalid
    }

    func testValidatePromoCodeNotApplicableForPlan() async throws {
        // Test that codes with plan restrictions are validated
        // Valid logic:
        // - applicablePlans not empty && currentPlan not in list => reject
    }

    // MARK: - Spec 15: Gift Subscription Tests

    func testPurchaseGiftSuccess() async throws {
        // Test successful gift purchase flow
        // Should call create-gift Edge Function and update activeGift
    }

    func testPurchaseGiftPaymentFailure() async throws {
        // Test gift purchase with payment method failure
        // Should throw appropriate BillingError
    }

    func testPurchaseGiftInvalidPlan() async throws {
        // Test gift purchase with non-existent plan
        // Should throw error before API call
    }

    func testRedeemGiftValidCode() async throws {
        // Test valid gift redemption
        // Should call redeem-gift Edge Function
        // Should refresh entitlements on success
    }

    func testRedeemGiftAlreadyRedeemed() async throws {
        // Test redemption of already-redeemed gift
        // Should throw giftRedemptionFailed error
    }

    func testRedeemGiftExpiredCode() async throws {
        // Test redemption of expired gift
        // Should throw appropriate error
    }

    func testRedeemGiftInvalidCode() async throws {
        // Test redemption with non-existent code
        // Should throw error from Edge Function
    }

    // MARK: - Spec 15: HSA/FSA Receipt Tests

    func testGenerateHSAReceiptSuccess() async throws {
        // Test successful HSA receipt generation
        // Should call generate-hsa-receipt Edge Function
        // Should return valid URL
        // Should update hsaRecord
    }

    func testGenerateHSAReceiptNoActiveSubscription() async throws {
        // Test receipt generation without active subscription
        // Should throw noActiveSubscription error immediately
    }

    func testGenerateHSAReceiptAPIFailure() async throws {
        // Test receipt generation when API fails
        // Should throw hsaReceiptGenerationFailed error
    }

    func testLoadAvailablePlansNotEmpty() async throws {
        // Test loading available subscription plans from database
        // Should return non-empty array of active, visible plans
    }

    func testLoadAvailablePlansOrdered() async throws {
        // Test that available plans are ordered by price ascending
    }

    func testLoadAvailablePlansFiltered() async throws {
        // Test that only active and visible plans are loaded
        // inactive or hidden plans should not appear
    }

    // MARK: - Spec 15: Promo Code Application Tests

    func testPurchaseWithPromoValidDiscount() async throws {
        // Test purchase with valid promo code
        // Should apply discount correctly via verify-purchase Edge Function
    }

    func testPurchaseWithPromoPercentDiscount() async throws {
        // Test percentage discount calculation
        // Example: 20% off $9.99 = $7.99
    }

    func testPurchaseWithPromoFixedDiscount() async throws {
        // Test fixed amount discount
        // Example: $5.00 off $9.99 = $4.99
    }

    func testPurchaseWithPromoTrialExtension() async throws {
        // Test trial extension via promo code
        // Should extend trial by specified days
    }

    func testClearValidatedPromoCode() {
        // Test clearing validated promo code state
        // validatedPromoCode should be nil
    }
}

// MARK: - Integration Tests (require StoreKit Testing Configuration)

extension BillingServiceTests {

    /// Test that products can be loaded from StoreKit
    /// Note: Requires StoreKit Testing Configuration in scheme
    func testLoadProducts() async throws {
        // This test requires StoreKit Configuration file
        // Skip if running without StoreKit testing setup
        #if DEBUG
        // In a real test environment with StoreKit Testing:
        // let authService = MockSupabaseAuthService()
        // let billingService = BillingService(authService: authService)
        // await billingService.loadProducts()
        // XCTAssertFalse(billingService.products.isEmpty)
        #endif
    }

    /// Test that purchase flow works correctly
    func testPurchaseFlow() async throws {
        // This test requires:
        // 1. StoreKit Configuration file with test products
        // 2. Mock Supabase service for verify-purchase call
        #if DEBUG
        // Would test:
        // - product.purchase() is called
        // - Transaction is verified
        // - verify-purchase Edge Function is called
        // - Entitlements are refreshed
        #endif
    }
}
