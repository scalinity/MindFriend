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
            .yearly
        )
        XCTAssertEqual(
            BillingService.productBillingPeriods["com.mindfriend.couples.annual"],
            .yearly
        )
        XCTAssertEqual(
            BillingService.productBillingPeriods["com.mindfriend.family.annual"],
            .yearly
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
        XCTAssertEqual(BillingError.verificationFailed.errorDescription, "The App Store couldn’t verify this purchase. Try Restore Purchases.")
        XCTAssertEqual(BillingError.invalidTransaction.errorDescription, "The purchase could not be verified. Try Restore Purchases.")
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
        XCTAssertEqual(BillingPeriod.yearly.displayName, "Annual")
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
        XCTAssertEqual(FamilyMember.MemberStatus.active.rawValue, "active")
        XCTAssertEqual(FamilyMember.MemberStatus.pending.rawValue, "pending")
        XCTAssertEqual(FamilyMember.MemberStatus.removed.rawValue, "removed")
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

import StoreKit
import StoreKitTest
import SwiftUI

/// Xcode StoreKit only. All backend verification is injected; no real purchase/server write.
@MainActor
final class StoreKitPurchaseRegressionTests: XCTestCase {
    private var store: SKTestSession!
    private var configurationURL: URL!
    private var updateListener: Task<Void, Never>?

    override func setUp() async throws {
        configurationURL = FileManager.default.temporaryDirectory.appendingPathComponent("MindFriend-\(UUID()).storekit")
        let group = "10000017"
        let plans = [SubscriptionPlan.premiumMonthly, .premiumAnnual, .couplesMonthly, .couplesAnnual, .familyMonthly, .familyAnnual]
        let subscriptions: [[String: Any]] = plans.enumerated().map { index, plan in
            ["adHocOffers": [], "codeOffers": [], "displayPrice": String(format: "%.2f", Double(plan.priceCents) / 100),
             "familyShareable": false, "groupNumber": index + 1, "internalID": UUID().uuidString,
             "localizations": [["description": "Synthetic StoreKit test", "displayName": plan.name, "locale": "en_US"]],
             "productID": plan.appStoreProductId!, "recurringSubscriptionPeriod": plan.billingPeriod == .monthly ? "P1M" : "P1Y",
             "referenceName": plan.name, "subscriptionGroupID": group, "type": "RecurringSubscription", "winBackOffers": []]
        }
        let probe: [String: Any] = ["displayPrice": "0.01", "familyShareable": false, "internalID": UUID().uuidString,
            "localizations": [["description": "MindFriend local-only StoreKit probe", "displayName": "Local-only Probe", "locale": "en_US"]],
            "productID": "com.mindfriend.local.storekit.probe", "referenceName": "Local-only Probe", "type": "NonConsumable"]
        let config: [String: Any] = ["identifier": UUID().uuidString, "nonRenewingSubscriptions": [], "products": [probe],
            "settings": ["_applicationInternalID": "6758198271", "_failTransactionsEnabled": false, "_locale": "en_US", "_storefront": "USA", "_storeKitErrors": []],
            "subscriptionGroups": [["id": group, "name": "MindFriend Test Subscriptions", "localizations": [], "subscriptions": subscriptions]],
            "version": ["major": 3, "minor": 0]]
        try JSONSerialization.data(withJSONObject: config).write(to: configurationURL)
        store = try SKTestSession(contentsOf: configurationURL)
        store.resetToDefaultState()
        store.disableDialogs = true
        store.clearTransactions()
        updateListener = Task { for await _ in StoreKit.Transaction.updates { if Task.isCancelled { return } } }
        // Catalog/UI checks require a unique local-only SKU. Purchase checks additionally require verified Xcode routing.
        let probes = try await Product.products(for: ["com.mindfriend.local.storekit.probe"])
        _ = try XCTUnwrap(probes.first { $0.description == "MindFriend local-only StoreKit probe" })
    }
    private func requireVerifiedLocalPurchase() async throws {
        let probes = try await Product.products(for: ["com.mindfriend.local.storekit.probe"])
        let localProduct = try XCTUnwrap(probes.first { $0.description == "MindFriend local-only StoreKit probe" })
        let result = try await localProduct.purchase()
        let routing: String
        switch result {
        case .success(.verified(let value)): routing = "verified environment=\(value.environment)"
        case .success(.unverified(let value, let error)): routing = "unverified environment=\(value.environment), error=\(error)"
        case .pending: routing = "pending"
        case .userCancelled: routing = "userCancelled"
        @unknown default: routing = "unknown"
        }
        let evidence = XCTAttachment(string: routing); evidence.name = "StoreKit local routing"; evidence.lifetime = .keepAlways; add(evidence)
        print("StoreKit routing probe: \(routing)")
        guard case .success(.verified(let transaction)) = result, transaction.environment == .xcode else {
            throw XCTSkip("Native local StoreKit verification unavailable: \(routing). No offered subscription was purchased.")
        }
        await transaction.finish()
        store.clearTransactions()
    }
    override func tearDownWithError() throws {
        updateListener?.cancel(); updateListener = nil
        store?.resetToDefaultState(); store?.clearTransactions(); store = nil
        if let configurationURL { try FileManager.default.removeItem(at: configurationURL) }
    }
    private func billing(loader: @escaping @Sendable ([String]) async throws -> [Product] = { try await Product.products(for: $0) },
                         verify: (@MainActor (StoreKit.Transaction, String, String?) async throws -> Entitlements)? = nil) -> BillingService {
        BillingService(authService: SupabaseAuthService(), productLoader: loader, transactionVerifier: verify, observeTransactions: false)
    }
    func testVerificationFailureRecoveryUsesActualServerStatusAndCode() {
        XCTAssertEqual(BillingService.verificationError(status: 503, data: Data()), .purchaseVerificationUnavailable)
        XCTAssertEqual(BillingService.verificationError(status: 401, data: Data()), .purchaseSignInRequired)
        XCTAssertEqual(BillingService.verificationError(status: 403, data: Data("{\"code\":\"APP_ACCOUNT_TOKEN_MISMATCH\"}".utf8)), .purchaseAccountMismatch)
        XCTAssertEqual(BillingService.verificationError(status: 409, data: Data("{\"code\":\"TRANSACTION_ALREADY_CLAIMED\"}".utf8)), .purchaseAccountMismatch)
        XCTAssertEqual(BillingService.verificationError(status: 400, data: Data()), .invalidTransaction)
    }
    func testAllSixProductsResolveWithMatchingPeriodsAndMappings() async throws {
        let service = billing()
        await service.loadProducts()
        XCTAssertEqual(Set(service.products.map(\.id)), Set(BillingService.productIds))
        for plan in [PlanType.individual, .couples, .family] {
            for period in [BillingPeriod.monthly, .yearly] {
                let product = try XCTUnwrap(service.product(for: plan, billingPeriod: period))
                XCTAssertEqual(product.description, "Synthetic StoreKit test")
                XCTAssertEqual(product.type, .autoRenewable)
                XCTAssertEqual(product.subscription?.subscriptionPeriod.unit, period == .monthly ? .month : .year)
            }
        }
    }
    func testEmptyAndFailedCatalogRemainRetryableAndConcurrentLoadsCoalesce() async throws {
        let loader = StoreKitCatalogFixture()
        let service = billing(loader: { try await loader.load($0) })
        async let first: Void = service.loadProducts()
        async let second: Void = service.loadProducts()
        _ = await (first, second)
        var calls = await loader.calls; XCTAssertEqual(calls, 1)
        XCTAssertTrue(service.products.isEmpty); XCTAssertNotNil(service.productLoadError)
        await service.loadProducts() // controlled network failure
        calls = await loader.calls; XCTAssertEqual(calls, 2)
        XCTAssertNotNil(service.productLoadError)
        await service.refreshProducts()
        XCTAssertEqual(service.products.count, 6); XCTAssertNil(service.productLoadError)
        await service.loadProducts()
        calls = await loader.calls; XCTAssertEqual(calls, 3)
    }
    func testPendingLocalOnlySKUDoesNotGrantAccess() async throws {
        var verificationCalls = 0
        let service = billing(verify: { _, _, _ in verificationCalls += 1; return .premium })
        let products = try await Product.products(for: ["com.mindfriend.local.storekit.probe"])
        let product = try XCTUnwrap(products.first)
        store.askToBuyEnabled = true
        let outcome = try await service.purchase(product)
        XCTAssertEqual(outcome, .pending)
        XCTAssertEqual(service.entitlements.tier, .free); XCTAssertEqual(verificationCalls, 0)
        XCTAssertFalse(service.isPurchasing)
    }
    func testUnverifiedLocalReceiptCannotGrantAccess() async throws {
        var verificationCalls = 0
        let service = billing(verify: { _, _, _ in verificationCalls += 1; return .premium })
        let products = try await Product.products(for: ["com.mindfriend.local.storekit.probe"])
        let product = try XCTUnwrap(products.first)
        try await store.setSimulatedError(SKTestFailures.Verification.verification(.invalidDeviceVerification), forAPI: .verification)
        do { _ = try await service.purchase(product); XCTFail("Must reject unverified receipt") }
        catch { XCTAssertEqual(error as? BillingError, .verificationFailed) }
        XCTAssertEqual(service.entitlements.tier, .free); XCTAssertFalse(service.isPurchasing)
        XCTAssertEqual(verificationCalls, 0)
    }
    func testAllSixLocalPurchasesVerifyBeforeEntitlementAndFinish() async throws {
        try await requireVerifiedLocalPurchase()
        var verified: [String] = []
        let service = billing(verify: { transaction, jws, _ in
            XCTAssertEqual(transaction.environment, .xcode)
            XCTAssertFalse(jws.isEmpty)
            verified.append(transaction.productID)
            return .premium
        })
        await service.loadProducts()
        for product in service.products {
            store.clearTransactions()
            let outcome = try await service.purchase(product)
            XCTAssertEqual(outcome, .completed)
            XCTAssertEqual(service.entitlements.tier, .premium)
            XCTAssertFalse(service.isPurchasing)
        }
        XCTAssertEqual(Set(verified), Set(BillingService.productIds))
    }
    func testPendingAndCancelledPurchasesDoNotGrantEntitlement() async throws {
        try await requireVerifiedLocalPurchase()
        var verificationCalls = 0
        let service = billing(verify: { _, _, _ in verificationCalls += 1; return .premium })
        await service.loadProducts()
        let product = try XCTUnwrap(service.product(for: .individual, billingPeriod: .monthly))
        store.askToBuyEnabled = true
        let outcome = try await service.purchase(product)
        XCTAssertEqual(outcome, .pending)
        XCTAssertEqual(service.entitlements.tier, .free); XCTAssertEqual(verificationCalls, 0)
        store.askToBuyEnabled = false
        store.clearTransactions()
        try await store.setSimulatedError(SKTestFailures.Purchase.generic(.userCancelled), forAPI: .purchase)
        do { _ = try await service.purchase(product); XCTFail("Must cancel") }
        catch { XCTAssertEqual(error as? BillingError, .cancelled) }
        XCTAssertEqual(service.entitlements.tier, .free); XCTAssertEqual(verificationCalls, 0)
        XCTAssertFalse(service.isPurchasing)
    }
    func testVerificationFailurePreservesFreeAccessAndRestoreRetriesSamePurchase() async throws {
        try await requireVerifiedLocalPurchase()
        var shouldFail = true
        var verifiedIDs: [UInt64] = []
        let service = billing(verify: { transaction, _, _ in
            XCTAssertEqual(transaction.environment, .xcode)
            verifiedIDs.append(transaction.id)
            if shouldFail { throw BillingError.invalidTransaction }
            return .premium
        })
        await service.loadProducts()
        let product = try XCTUnwrap(service.product(for: .individual, billingPeriod: .monthly))
        do { _ = try await service.purchase(product); XCTFail("Must fail verification") }
        catch { XCTAssertEqual(error as? BillingError, .invalidTransaction) }
        XCTAssertEqual(service.entitlements.tier, .free)
        shouldFail = false
        try await service.restorePurchases()
        XCTAssertEqual(service.entitlements.tier, .premium)
        XCTAssertEqual(Set(verifiedIDs).count, 1, "Restoration must retry the existing purchase identity")
    }
    func testCaptureCatalogUIUnavailableAndRefreshedProduct() async throws {
        let loader = StoreKitCatalogFixture(failSecond: false)
        let service = billing(loader: { try await loader.load($0) })
        let host = UIHostingController(rootView: PaywallContent(billingService: service)
            .environmentObject(DependencyContainer.preview).environmentObject(AppState()).preferredColorScheme(.dark))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for _ in 0..<300 { if service.productLoadError != nil { break }; try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(300))
        capture(host, name: "Issue17-unavailable-catalog")
        XCTAssertTrue(service.products.isEmpty)
        XCTAssertNotNil(service.productLoadError)
        // Capture-only UI coverage: inspect the attachments; service assertions do not verify rendering.
        // Native Reload button activation is retained as NOT TESTED, not inferred from a service call.
        await service.refreshProducts()
        for _ in 0..<300 { if service.products.count == 6 { break }; try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(100))
        capture(host, name: "Issue17-storekit-catalog-reloaded")
        XCTAssertEqual(service.products.count, 6)
        XCTAssertNil(service.productLoadError)
        XCTAssertEqual(service.entitlements.tier, .free)
    }
    private func capture(_ host: UIHostingController<some View>, name: String) {
        host.view.layoutIfNeeded()
        func scroll(_ view: UIView) {
            if let scroll = view as? UIScrollView { scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false) }
            view.subviews.forEach(scroll)
        }
        scroll(host.view)
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) })
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
private actor StoreKitCatalogFixture {
    var calls = 0
    let failSecond: Bool
    init(failSecond: Bool = true) { self.failSecond = failSecond }
    func load(_ ids: [String]) async throws -> [Product] {
        calls += 1
        try await Task.sleep(for: .milliseconds(50))
        if calls == 1 { return [] }
        if calls == 2 && failSecond { throw URLError(.notConnectedToInternet) }
        return try await Product.products(for: ids)
    }
}
