import XCTest
@testable import MindFriendApp

/// Unit tests for Spec 15 Business Model data structures
final class BusinessModelsTests: XCTestCase {

    // MARK: - SubscriptionPlan Tests

    func testSubscriptionPlanDisplayPrice() {
        let plan = SubscriptionPlan.premiumMonthly
        XCTAssertEqual(plan.displayPrice, "$9.99")
    }

    func testSubscriptionPlanDisplayPriceAnnual() {
        let plan = SubscriptionPlan.premiumAnnual
        XCTAssertEqual(plan.displayPrice, "$79.99")
    }

    func testSubscriptionPlanPricePerMonth() {
        let plan = SubscriptionPlan.premiumAnnual
        XCTAssertEqual(plan.pricePerMonth, "$6.67")
    }

    func testSubscriptionPlanPricePerMonthNilForMonthly() {
        let plan = SubscriptionPlan.premiumMonthly
        XCTAssertNil(plan.pricePerMonth)
    }

    func testSubscriptionPlanSavingsPercent() {
        let plan = SubscriptionPlan.premiumAnnual
        XCTAssertEqual(plan.savingsPercent, 20)
    }

    func testSubscriptionPlanSavingsPercentNilForMonthly() {
        let plan = SubscriptionPlan.premiumMonthly
        XCTAssertNil(plan.savingsPercent)
    }

    func testSubscriptionPlanCodableEncoding() throws {
        let plan = SubscriptionPlan.premiumMonthly
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(plan)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SubscriptionPlan.self, from: encoded)

        XCTAssertEqual(decoded.id, plan.id)
        XCTAssertEqual(decoded.name, plan.name)
        XCTAssertEqual(decoded.priceCents, plan.priceCents)
    }

    func testSubscriptionPlanCodingKeysSnakeCase() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "name": "Test Plan",
            "description": "A test plan",
            "price_cents": 1999,
            "currency": "USD",
            "billing_period": "monthly",
            "billing_period_months": 1,
            "plan_type": "individual",
            "max_seats": 1,
            "features": {
                "unlimited_chat": true,
                "unlimited_exercises": true,
                "premium_content": true,
                "priority_support": true,
                "family_sharing": false,
                "offline_mode": true,
                "custom_themes": true,
                "advanced_insights": true
            },
            "ai_chat_limit": null,
            "exercise_limit": null,
            "app_store_product_id": "com.test.product",
            "is_active": true,
            "is_visible": true
        }
        """

        let decoder = JSONDecoder()
        let plan = try decoder.decode(SubscriptionPlan.self, from: jsonData(from: json))

        XCTAssertEqual(plan.priceCents, 1999)
        XCTAssertEqual(plan.billingPeriodMonths, 1)
        XCTAssertEqual(plan.planType, .individual)
        XCTAssertTrue(plan.isActive)
    }

    func testSubscriptionPlanFamilyAnnual() {
        let plan = SubscriptionPlan.familyAnnual
        XCTAssertEqual(plan.planType, .family)
        XCTAssertEqual(plan.maxSeats, 6)
        XCTAssertEqual(plan.features.familySharing, true)
    }

    // MARK: - PlanFeatures Tests

    func testPlanFeaturesFree() {
        let features = PlanFeatures.free
        XCTAssertFalse(features.unlimitedChat)
        XCTAssertFalse(features.unlimitedExercises)
        XCTAssertFalse(features.premiumContent)
        XCTAssertFalse(features.prioritySupport)
    }

    func testPlanFeaturesPremium() {
        let features = PlanFeatures.premium
        XCTAssertTrue(features.unlimitedChat)
        XCTAssertTrue(features.unlimitedExercises)
        XCTAssertTrue(features.premiumContent)
        XCTAssertFalse(features.familySharing)
    }

    func testPlanFeaturesFamily() {
        let features = PlanFeatures.family
        XCTAssertTrue(features.unlimitedChat)
        XCTAssertTrue(features.familySharing)
        XCTAssertTrue(features.advancedInsights)
    }

    // MARK: - PlanFeatures Lenient Decode (regression: paywall outage 2026-04-27)
    //
    // The remote subscription_plans.features JSONB has historically drifted
    // (camelCase keys, renamed flags). A strict Codable decode there crashed
    // BillingService.loadAvailablePlans() with "The data couldn't be read
    // because it is missing." and took the entire gift/paywall sheet down.
    // PlanFeatures.init(from:) is now lenient: any missing or wrong-typed
    // key defaults to false. These tests lock that contract in.

    func testPlanFeaturesDecodesEmptyObjectAsAllFalse() throws {
        let json = Data("{}".utf8)
        let features = try JSONDecoder().decode(PlanFeatures.self, from: json)
        XCTAssertEqual(features, PlanFeatures.free)
    }

    func testPlanFeaturesDecodesPartialObjectFillingMissingWithFalse() throws {
        let json = Data(#"{"unlimited_chat": true, "advanced_insights": true}"#.utf8)
        let features = try JSONDecoder().decode(PlanFeatures.self, from: json)
        XCTAssertTrue(features.unlimitedChat)
        XCTAssertTrue(features.advancedInsights)
        XCTAssertFalse(features.unlimitedExercises)
        XCTAssertFalse(features.premiumContent)
        XCTAssertFalse(features.prioritySupport)
        XCTAssertFalse(features.familySharing)
        XCTAssertFalse(features.offlineMode)
        XCTAssertFalse(features.customThemes)
    }

    func testPlanFeaturesIgnoresLegacyCamelCaseKeys() throws {
        // Mirrors the original broken seed: camelCase keys, plus made-up flags
        // like priorityResponse / advancedAnalytics that never existed in the
        // Swift model. The decoder must produce all-false rather than throw.
        let json = Data(#"""
        {
            "unlimitedChat": true,
            "priorityResponse": true,
            "advancedAnalytics": true,
            "smartReminders": true
        }
        """#.utf8)
        let features = try JSONDecoder().decode(PlanFeatures.self, from: json)
        XCTAssertEqual(features, PlanFeatures.free)
    }

    func testPlanFeaturesIgnoresWrongTypedValues() throws {
        // A string "true" instead of bool true must not throw — it falls
        // back to false rather than poisoning the whole decode.
        let json = Data(#"{"unlimited_chat": "true", "premium_content": true}"#.utf8)
        let features = try JSONDecoder().decode(PlanFeatures.self, from: json)
        XCTAssertFalse(features.unlimitedChat)  // wrong type → false
        XCTAssertTrue(features.premiumContent)  // correct type → true
    }

    func testPlanFeaturesRoundTripPreservesAllFields() throws {
        let original = PlanFeatures.premium
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlanFeatures.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func testPlanFeaturesDecodesNullValuesAsFalse() throws {
        let json = Data(#"{"unlimited_chat": null, "premium_content": true}"#.utf8)
        let features = try JSONDecoder().decode(PlanFeatures.self, from: json)
        XCTAssertFalse(features.unlimitedChat)
        XCTAssertTrue(features.premiumContent)
    }

    // MARK: - PromoCode Tests

    func testPromoCodeIsValidActive() {
        let promo = PromoCode(
            id: UUID(),
            code: "SAVE20",
            discountType: .percent,
            discountValue: 20,
            trialExtensionDays: nil,
            applicablePlans: nil,
            minBillingPeriod: nil,
            firstTimeOnly: false,
            maxUses: 100,
            usesCount: 50,
            maxUsesPerUser: nil,
            validFrom: Date(timeIntervalSinceNow: -86400),
            validUntil: Date(timeIntervalSinceNow: 86400),
            isActive: true,
            campaignName: "Summer Sale"
        )

        XCTAssertTrue(promo.isValid)
    }

    func testPromoCodeIsValidInactive() {
        let promo = PromoCode(
            id: UUID(),
            code: "SAVE20",
            discountType: .percent,
            discountValue: 20,
            trialExtensionDays: nil,
            applicablePlans: nil,
            minBillingPeriod: nil,
            firstTimeOnly: false,
            maxUses: 100,
            usesCount: 50,
            maxUsesPerUser: nil,
            validFrom: Date(),
            validUntil: nil,
            isActive: false,
            campaignName: nil
        )

        XCTAssertFalse(promo.isValid)
    }

    func testPromoCodeIsValidNotYetActive() {
        let promo = PromoCode(
            id: UUID(),
            code: "SAVE20",
            discountType: .percent,
            discountValue: 20,
            trialExtensionDays: nil,
            applicablePlans: nil,
            minBillingPeriod: nil,
            firstTimeOnly: false,
            maxUses: 100,
            usesCount: 0,
            maxUsesPerUser: nil,
            validFrom: Date(timeIntervalSinceNow: 86400),
            validUntil: nil,
            isActive: true,
            campaignName: nil
        )

        XCTAssertFalse(promo.isValid)
    }

    func testPromoCodeIsValidExpired() {
        let promo = PromoCode(
            id: UUID(),
            code: "SAVE20",
            discountType: .percent,
            discountValue: 20,
            trialExtensionDays: nil,
            applicablePlans: nil,
            minBillingPeriod: nil,
            firstTimeOnly: false,
            maxUses: 100,
            usesCount: 0,
            maxUsesPerUser: nil,
            validFrom: Date(timeIntervalSinceNow: -86400),
            validUntil: Date(timeIntervalSinceNow: -1),
            isActive: true,
            campaignName: nil
        )

        XCTAssertFalse(promo.isValid)
    }

    func testPromoCodeIsValidMaxUsesExceeded() {
        let promo = PromoCode(
            id: UUID(),
            code: "SAVE20",
            discountType: .percent,
            discountValue: 20,
            trialExtensionDays: nil,
            applicablePlans: nil,
            minBillingPeriod: nil,
            firstTimeOnly: false,
            maxUses: 100,
            usesCount: 100,
            maxUsesPerUser: nil,
            validFrom: Date(timeIntervalSinceNow: -86400),
            validUntil: nil,
            isActive: true,
            campaignName: nil
        )

        XCTAssertFalse(promo.isValid)
    }

    func testPromoCodeDiscountDescriptionPercent() {
        let promo = PromoCode(
            id: UUID(),
            code: "SAVE20",
            discountType: .percent,
            discountValue: 20,
            trialExtensionDays: nil,
            applicablePlans: nil,
            minBillingPeriod: nil,
            firstTimeOnly: false,
            maxUses: nil,
            usesCount: 0,
            maxUsesPerUser: nil,
            validFrom: Date(),
            validUntil: nil,
            isActive: true,
            campaignName: nil
        )

        XCTAssertEqual(promo.discountDescription, "20% off")
    }

    func testPromoCodeDiscountDescriptionFixed() {
        let promo = PromoCode(
            id: UUID(),
            code: "SAVE5",
            discountType: .fixed,
            discountValue: 500,
            trialExtensionDays: nil,
            applicablePlans: nil,
            minBillingPeriod: nil,
            firstTimeOnly: false,
            maxUses: nil,
            usesCount: 0,
            maxUsesPerUser: nil,
            validFrom: Date(),
            validUntil: nil,
            isActive: true,
            campaignName: nil
        )

        XCTAssertEqual(promo.discountDescription, "$5.00 off")
    }

    func testPromoCodeDiscountDescriptionTrialExtension() {
        let promo = PromoCode(
            id: UUID(),
            code: "TRIAL14",
            discountType: .trialExtension,
            discountValue: 0,
            trialExtensionDays: 14,
            applicablePlans: nil,
            minBillingPeriod: nil,
            firstTimeOnly: false,
            maxUses: nil,
            usesCount: 0,
            maxUsesPerUser: nil,
            validFrom: Date(),
            validUntil: nil,
            isActive: true,
            campaignName: nil
        )

        XCTAssertEqual(promo.discountDescription, "14 days free trial")
    }

    func testPromoCodeCodableDecoding() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "code": "SAVE20",
            "discount_type": "percent",
            "discount_value": 20,
            "trial_extension_days": null,
            "applicable_plans": null,
            "min_billing_period": null,
            "first_time_only": false,
            "max_uses": 100,
            "uses_count": 50,
            "max_uses_per_user": null,
            "valid_from": "2024-01-01T00:00:00Z",
            "valid_until": "2024-12-31T23:59:59Z",
            "is_active": true,
            "campaign_name": "Summer Sale"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let promo = try decoder.decode(PromoCode.self, from: jsonData(from: json))

        XCTAssertEqual(promo.code, "SAVE20")
        XCTAssertEqual(promo.discountType, .percent)
        XCTAssertEqual(promo.discountValue, 20)
        XCTAssertTrue(promo.isActive)
    }

    // MARK: - GiftSubscription Tests

    func testGiftSubscriptionCanBeRedeemed() {
        let gift = GiftSubscription(
            id: UUID(),
            purchaserUserId: UUID(),
            purchaserEmail: "purchaser@example.com",
            planId: UUID(),
            durationMonths: 12,
            priceCents: 7999,
            recipientEmail: "recipient@example.com",
            recipientName: "John Doe",
            personalMessage: "Enjoy this gift!",
            deliveryDate: Date(),
            deliveredAt: Date(),
            redemptionCode: "GIFT123456",
            redeemedAt: nil,
            redeemedByUserId: nil,
            status: .pending,
            expiresAt: Date(timeIntervalSinceNow: 86400)
        )

        XCTAssertTrue(gift.canBeRedeemed)
    }

    func testGiftSubscriptionCanNotBeRedeemedAlreadyRedeemed() {
        let gift = GiftSubscription(
            id: UUID(),
            purchaserUserId: UUID(),
            purchaserEmail: "purchaser@example.com",
            planId: UUID(),
            durationMonths: 12,
            priceCents: 7999,
            recipientEmail: "recipient@example.com",
            recipientName: "John Doe",
            personalMessage: nil,
            deliveryDate: Date(),
            deliveredAt: Date(),
            redemptionCode: "GIFT123456",
            redeemedAt: Date(),
            redeemedByUserId: UUID(),
            status: .redeemed,
            expiresAt: nil
        )

        XCTAssertFalse(gift.canBeRedeemed)
    }

    func testGiftSubscriptionCanNotBeRedeemedExpired() {
        let gift = GiftSubscription(
            id: UUID(),
            purchaserUserId: UUID(),
            purchaserEmail: "purchaser@example.com",
            planId: UUID(),
            durationMonths: 12,
            priceCents: 7999,
            recipientEmail: "recipient@example.com",
            recipientName: nil,
            personalMessage: nil,
            deliveryDate: Date(),
            deliveredAt: Date(),
            redemptionCode: "GIFT123456",
            redeemedAt: nil,
            redeemedByUserId: nil,
            status: .pending,
            expiresAt: Date(timeIntervalSinceNow: -1)
        )

        XCTAssertFalse(gift.canBeRedeemed)
    }

    func testGiftSubscriptionDisplayPrice() {
        let gift = GiftSubscription(
            id: UUID(),
            purchaserUserId: UUID(),
            purchaserEmail: "purchaser@example.com",
            planId: UUID(),
            durationMonths: 12,
            priceCents: 7999,
            recipientEmail: "recipient@example.com",
            recipientName: nil,
            personalMessage: nil,
            deliveryDate: Date(),
            deliveredAt: nil,
            redemptionCode: "GIFT123456",
            redeemedAt: nil,
            redeemedByUserId: nil,
            status: .pending,
            expiresAt: nil
        )

        XCTAssertEqual(gift.displayPrice, "$79.99")
    }

    func testGiftSubscriptionStatusTransitions() {
        let pendingGift = GiftSubscription(
            id: UUID(),
            purchaserUserId: UUID(),
            purchaserEmail: "purchaser@example.com",
            planId: UUID(),
            durationMonths: 12,
            priceCents: 7999,
            recipientEmail: "recipient@example.com",
            recipientName: nil,
            personalMessage: nil,
            deliveryDate: Date(),
            deliveredAt: nil,
            redemptionCode: "GIFT123456",
            redeemedAt: nil,
            redeemedByUserId: nil,
            status: .pending,
            expiresAt: nil
        )

        XCTAssertEqual(pendingGift.status, .pending)

        var deliveredGift = pendingGift
        deliveredGift.status = .delivered
        XCTAssertEqual(deliveredGift.status, .delivered)

        var redeemedGift = deliveredGift
        redeemedGift.status = .redeemed
        XCTAssertEqual(redeemedGift.status, .redeemed)
    }

    func testGiftSubscriptionCodableDecoding() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "purchaser_user_id": "550e8400-e29b-41d4-a716-446655440001",
            "purchaser_email": "purchaser@example.com",
            "plan_id": "550e8400-e29b-41d4-a716-446655440002",
            "duration_months": 12,
            "price_cents": 7999,
            "recipient_email": "recipient@example.com",
            "recipient_name": "John Doe",
            "personal_message": "Enjoy!",
            "delivery_date": "2024-01-01T00:00:00Z",
            "delivered_at": null,
            "redemption_code": "GIFT123456",
            "redeemed_at": null,
            "redeemed_by_user_id": null,
            "status": "pending",
            "expires_at": null
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let gift = try decoder.decode(GiftSubscription.self, from: jsonData(from: json))

        XCTAssertEqual(gift.recipientEmail, "recipient@example.com")
        XCTAssertEqual(gift.status, .pending)
        XCTAssertEqual(gift.durationMonths, 12)
    }

    // MARK: - HSAFSARecord Tests

    func testHSAFSARecordHasLetterOfMedicalNecessity() {
        let record = HSAFSARecord(
            id: UUID(),
            userId: UUID(),
            subscriptionId: UUID(),
            isHSAEligible: true,
            isFSAEligible: true,
            lomnGeneratedAt: Date(),
            lomnUrl: "https://example.com/lomn.pdf",
            receiptGeneratedAt: nil,
            receiptUrl: nil,
            receiptAmountCents: nil
        )

        XCTAssertTrue(record.hasLetterOfMedicalNecessity)
    }

    func testHSAFSARecordHasReceiptFalse() {
        let record = HSAFSARecord(
            id: UUID(),
            userId: UUID(),
            subscriptionId: UUID(),
            isHSAEligible: true,
            isFSAEligible: false,
            lomnGeneratedAt: nil,
            lomnUrl: nil,
            receiptGeneratedAt: nil,
            receiptUrl: nil,
            receiptAmountCents: nil
        )

        XCTAssertFalse(record.hasReceipt)
    }

    func testHSAFSARecordHasReceiptTrue() {
        let record = HSAFSARecord(
            id: UUID(),
            userId: UUID(),
            subscriptionId: UUID(),
            isHSAEligible: true,
            isFSAEligible: true,
            lomnGeneratedAt: nil,
            lomnUrl: nil,
            receiptGeneratedAt: Date(),
            receiptUrl: "https://example.com/receipt.pdf",
            receiptAmountCents: 7999
        )

        XCTAssertTrue(record.hasReceipt)
    }

    func testHSAFSARecordDisplayReceiptAmount() {
        let record = HSAFSARecord(
            id: UUID(),
            userId: UUID(),
            subscriptionId: UUID(),
            isHSAEligible: true,
            isFSAEligible: true,
            lomnGeneratedAt: nil,
            lomnUrl: nil,
            receiptGeneratedAt: Date(),
            receiptUrl: "https://example.com/receipt.pdf",
            receiptAmountCents: 7999
        )

        XCTAssertEqual(record.displayReceiptAmount, "$79.99")
    }

    func testHSAFSARecordDisplayReceiptAmountNil() {
        let record = HSAFSARecord(
            id: UUID(),
            userId: UUID(),
            subscriptionId: UUID(),
            isHSAEligible: true,
            isFSAEligible: true,
            lomnGeneratedAt: nil,
            lomnUrl: nil,
            receiptGeneratedAt: nil,
            receiptUrl: nil,
            receiptAmountCents: nil
        )

        XCTAssertNil(record.displayReceiptAmount)
    }

    func testHSAFSARecordCodableDecoding() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "user_id": "550e8400-e29b-41d4-a716-446655440001",
            "subscription_id": "550e8400-e29b-41d4-a716-446655440002",
            "is_hsa_eligible": true,
            "is_fsa_eligible": true,
            "lomn_generated_at": "2024-01-01T00:00:00Z",
            "lomn_url": "https://example.com/lomn.pdf",
            "receipt_generated_at": "2024-01-02T00:00:00Z",
            "receipt_url": "https://example.com/receipt.pdf",
            "receipt_amount_cents": 7999
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(HSAFSARecord.self, from: jsonData(from: json))

        XCTAssertTrue(record.isHSAEligible)
        XCTAssertTrue(record.isFSAEligible)
        XCTAssertEqual(record.receiptAmountCents, 7999)
    }

    // MARK: - Enums Tests

    func testBillingPeriodCaseIterable() {
        let allPeriods = BillingPeriod.allCases
        XCTAssertEqual(allPeriods.count, 4)
        XCTAssertTrue(allPeriods.contains(.monthly))
        XCTAssertTrue(allPeriods.contains(.yearly))
    }

    func testBillingPeriodDisplayNames() {
        XCTAssertEqual(BillingPeriod.monthly.displayName, "Monthly")
        XCTAssertEqual(BillingPeriod.yearly.displayName, "Annual")
    }

    func testPlanTypeDisplayNames() {
        XCTAssertEqual(PlanType.individual.displayName, "Individual")
        XCTAssertEqual(PlanType.family.displayName, "Family")
        XCTAssertEqual(PlanType.enterprise.displayName, "Enterprise")
    }

    func testDiscountTypeCodable() throws {
        let json = "[\"percent\", \"fixed\", \"trial_extension\"]"
        let decoder = JSONDecoder()
        let types = try decoder.decode([DiscountType].self, from: jsonData(from: json))

        XCTAssertEqual(types, [.percent, .fixed, .trialExtension])
    }

    func testGiftStatusCodable() throws {
        let json = "[\"pending\", \"delivered\", \"redeemed\", \"expired\", \"refunded\"]"
        let decoder = JSONDecoder()
        let statuses = try decoder.decode([GiftStatus].self, from: jsonData(from: json))

        XCTAssertEqual(statuses.count, 5)
        XCTAssertTrue(statuses.contains(.pending))
        XCTAssertTrue(statuses.contains(.redeemed))
    }

    // MARK: - Edge Cases

    func testSubscriptionPlanWithZeroPrice() {
        let plan = SubscriptionPlan(
            id: UUID(),
            name: "Free Trial",
            description: nil,
            priceCents: 0,
            currency: "USD",
            billingPeriod: .monthly,
            billingPeriodMonths: 1,
            planType: .individual,
            maxSeats: 1,
            features: .free,
            aiChatLimit: 20,
            exerciseLimit: nil,
            appStoreProductId: nil,
            isActive: true,
            isVisible: true
        )

        XCTAssertEqual(plan.displayPrice, "$0.00")
    }

    func testPromoCodeEmptyMaxUses() {
        let promo = PromoCode(
            id: UUID(),
            code: "UNLIMITED",
            discountType: .percent,
            discountValue: 10,
            trialExtensionDays: nil,
            applicablePlans: nil,
            minBillingPeriod: nil,
            firstTimeOnly: false,
            maxUses: nil,
            usesCount: 1000,
            maxUsesPerUser: nil,
            validFrom: Date(timeIntervalSinceNow: -1),
            validUntil: nil,
            isActive: true,
            campaignName: nil
        )

        XCTAssertTrue(promo.isValid)
    }

    func testGiftSubscriptionNoExpiration() {
        let gift = GiftSubscription(
            id: UUID(),
            purchaserUserId: UUID(),
            purchaserEmail: "purchaser@example.com",
            planId: UUID(),
            durationMonths: 12,
            priceCents: 7999,
            recipientEmail: "recipient@example.com",
            recipientName: nil,
            personalMessage: nil,
            deliveryDate: Date(),
            deliveredAt: Date(),
            redemptionCode: "GIFT123456",
            redeemedAt: nil,
            redeemedByUserId: nil,
            status: .pending,
            expiresAt: nil
        )

        XCTAssertTrue(gift.canBeRedeemed)
    }
}

// MARK: - Migration Contract Tests
// =============================================================================
// Locks in the contract between the iOS data models and the SQL migrations.
// If either side drifts (a Swift case added/removed, or a CHECK constraint
// reworded), one of these tests fails before the drift can ship and break
// production decoding the way the paywall did on 2026-04-27.
// =============================================================================

final class MigrationContractTests: XCTestCase {

    // MARK: - Cognitive Distortion (currently disabled migration)
    //
    // The Postgres CHECK constraint in
    //   supabase/migrations/20260123000001_cognitive_distortion.sql.disabled
    // restricts distortion_events.distortion_type to these 10 strings. If we
    // ever re-enable the migration, the Swift enum MUST stay in sync —
    // otherwise rows we insert get rejected and rows we read fail to decode.
    private static let expectedDistortionRawValues: Set<String> = [
        "all_or_nothing",
        "overgeneralization",
        "mental_filter",
        "disqualifying_positive",
        "jumping_to_conclusions",
        "magnification_minimization",
        "emotional_reasoning",
        "should_statements",
        "labeling",
        "personalization",
    ]

    func testDistortionTypeMatchesMigrationCheckConstraint() {
        let swiftRawValues = Set(DistortionType.allCases.map(\.rawValue))
        XCTAssertEqual(
            swiftRawValues,
            Self.expectedDistortionRawValues,
            "DistortionType drifted from the cognitive_distortion migration's "
            + "CHECK constraint. Either the migration or the Swift enum was "
            + "changed without updating the other."
        )
    }

    func testDistortionTypeRoundTripsViaCodable() throws {
        for type in DistortionType.allCases {
            let encoded = try JSONEncoder().encode([type])
            let decoded = try JSONDecoder().decode([DistortionType].self, from: encoded)
            XCTAssertEqual(decoded, [type], "Round-trip failed for \(type)")
        }
    }

    // MARK: - Plan Features (subscription_plans.features JSONB)
    //
    // The seed in 20260124040000_create_subscription_plans_table.sql and the
    // repair in 20260427210000_fix_subscription_plan_features.sql both write
    // these 8 snake_case keys. PlanFeatures.CodingKeys must list exactly these
    // — anything else is the failure mode that took the gift sheet down.
    private static let expectedPlanFeatureKeys: Set<String> = [
        "unlimited_chat",
        "unlimited_exercises",
        "premium_content",
        "priority_support",
        "family_sharing",
        "offline_mode",
        "custom_themes",
        "advanced_insights",
    ]

    func testPlanFeaturesCodingKeysMatchMigrationJSONB() throws {
        let encoded = try JSONEncoder().encode(PlanFeatures.premium)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
        XCTAssertEqual(
            Set(json.keys),
            Self.expectedPlanFeatureKeys,
            "PlanFeatures encoded with unexpected keys. Either CodingKeys "
            + "drifted or new fields were added to the Swift struct without "
            + "extending the migration."
        )
    }

    // MARK: - Capacity Override (dynamic_difficulty migration)
    //
    // The Postgres CHECK constraint on capacity_overrides.override_level allows
    // these three values (see 20260427230000_dynamic_difficulty.sql, formerly
    // 20260123000000). DifficultyService.setManualOverride relies on the Swift
    // enum's rawValues being a subset of these — anything else fails the DB
    // CHECK at INSERT time.
    private static let expectedOverrideRawValues: Set<String> = [
        "rest",
        "normal",
        "challenge",
    ]

    func testCapacityOverrideLevelsMatchMigrationCheckConstraint() {
        // OverrideLevel is not CaseIterable; enumerate the 3 known cases.
        let allKnownLevels: [CapacityOverride.OverrideLevel] = [.rest, .normal, .challenge]
        let swiftRawValues = Set(allKnownLevels.map(\.rawValue))
        XCTAssertEqual(
            swiftRawValues,
            Self.expectedOverrideRawValues,
            "CapacityOverride.OverrideLevel drifted from the dynamic_difficulty "
            + "migration's CHECK constraint. Inserts would fail at the DB layer."
        )

        for raw in Self.expectedOverrideRawValues {
            XCTAssertNotNil(
                CapacityOverride.OverrideLevel(rawValue: raw),
                "Migration allows '\(raw)' but Swift can't decode it"
            )
        }
    }
}
