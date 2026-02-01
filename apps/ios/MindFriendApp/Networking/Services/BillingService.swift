import Foundation
import StoreKit
import Supabase
import OSLog

/// Service for managing subscriptions, promotions, gifts, and HSA/FSA integrations
@MainActor
final class BillingService: ObservableObject {
    private let authService: SupabaseAuthService

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPurchasing = false
    @Published private(set) var entitlements: Entitlements = .free
    @Published private(set) var subscription: Subscription?
    @Published private(set) var familyGroup: FamilyGroup?
    @Published private(set) var familyMembers: [FamilyMember] = []

    // Business Model features
    @Published private(set) var availablePlans: [SubscriptionPlan] = []
    @Published private(set) var validatedPromoCode: PromoCode?
    @Published private(set) var activeGift: GiftSubscription?
    @Published private(set) var hsaRecord: HSAFSARecord?

    @Published var isValidatingPromo = false
    @Published var isPurchasingGift = false
    @Published var isRedeemingGift = false
    @Published var isGeneratingHSAReceipt = false

    private var transactionListener: Task<Void, Never>?

    // P3-P6: Cache products to avoid redundant StoreKit requests
    private var productsLoaded = false
    private var productsLoadTask: Task<Void, Never>?

    // All available product IDs for premium subscriptions
    static let productIds = [
        // Individual plans
        "com.mindfriend.premium.monthly",
        "com.mindfriend.premium.yearly",
        // Couples plans
        "com.mindfriend.couples.monthly",
        "com.mindfriend.couples.annual",
        // Family plans
        "com.mindfriend.family.monthly",
        "com.mindfriend.family.annual"
    ]

    // Map product IDs to plan types for UI display
    static let productPlanTypes: [String: PlanType] = [
        "com.mindfriend.premium.monthly": .individual,
        "com.mindfriend.premium.yearly": .individual,
        "com.mindfriend.couples.monthly": .couples,
        "com.mindfriend.couples.annual": .couples,
        "com.mindfriend.family.monthly": .family,
        "com.mindfriend.family.annual": .family
    ]

    // Map product IDs to billing periods
    static let productBillingPeriods: [String: BillingPeriod] = [
        "com.mindfriend.premium.monthly": .monthly,
        "com.mindfriend.premium.yearly": .yearly,
        "com.mindfriend.couples.monthly": .monthly,
        "com.mindfriend.couples.annual": .yearly,
        "com.mindfriend.family.monthly": .monthly,
        "com.mindfriend.family.annual": .yearly
    ]

    init(authService: SupabaseAuthService) {
        self.authService = authService
        startTransactionListener()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Products

    /// Load products from StoreKit with caching to avoid redundant requests (P3-P6)
    func loadProducts() async {
        // Return early if products already loaded
        guard !productsLoaded else { return }

        // If a load is already in progress, wait for it
        if let existingTask = productsLoadTask {
            await existingTask.value
            return
        }

        // Start new load task
        productsLoadTask = Task {
            do {
                let loadedProducts = try await Product.products(for: Self.productIds)
                    .sorted { $0.price < $1.price }
                products = loadedProducts
                productsLoaded = true
            } catch {
                Log.billing.error("Failed to load products: \(error)")
            }
            productsLoadTask = nil
        }

        await productsLoadTask?.value
    }

    /// Force refresh products (bypasses cache)
    func refreshProducts() async {
        productsLoaded = false
        await loadProducts()
    }

    /// Get products filtered by plan type
    func products(for planType: PlanType) -> [Product] {
        products.filter { Self.productPlanTypes[$0.id] == planType }
    }

    /// Get products filtered by billing period
    func products(for billingPeriod: BillingPeriod) -> [Product] {
        products.filter { Self.productBillingPeriods[$0.id] == billingPeriod }
    }

    /// Get a specific product by plan type and billing period
    func product(for planType: PlanType, billingPeriod: BillingPeriod) -> Product? {
        products.first {
            Self.productPlanTypes[$0.id] == planType &&
            Self.productBillingPeriods[$0.id] == billingPeriod
        }
    }

    // MARK: - Available Plans

    /// Load all available subscription plans from database
    func loadAvailablePlans() async throws {
        struct DBPlan: Codable {
            let id: String
            let name: String
            let description: String?
            let priceCents: Int
            let currency: String
            let billingPeriod: String
            let billingPeriodMonths: Int?
            let planType: String
            let maxSeats: Int?
            let features: PlanFeatures
            let aiChatLimit: Int?
            let exerciseLimit: Int?
            let appStoreProductId: String?
            let isActive: Bool
            let isVisible: Bool

            enum CodingKeys: String, CodingKey {
                case id, name, description, currency, features
                case priceCents = "price_cents"
                case billingPeriod = "billing_period"
                case billingPeriodMonths = "billing_period_months"
                case planType = "plan_type"
                case maxSeats = "max_seats"
                case aiChatLimit = "ai_chat_limit"
                case exerciseLimit = "exercise_limit"
                case appStoreProductId = "app_store_product_id"
                case isActive = "is_active"
                case isVisible = "is_visible"
            }
        }

        let plans: [DBPlan] = try await supabase
            .from("subscription_plans")
            .select()
            .eq("is_active", value: true)
            .eq("is_visible", value: true)
            .order("price_cents", ascending: true)
            .execute()
            .value

        availablePlans = plans.compactMap { dbPlan in
            guard let billingPeriod = BillingPeriod(rawValue: dbPlan.billingPeriod),
                  let planType = PlanType(rawValue: dbPlan.planType),
                  let id = UUID(uuidString: dbPlan.id) else {
                return nil
            }

            return SubscriptionPlan(
                id: id,
                name: dbPlan.name,
                description: dbPlan.description,
                priceCents: dbPlan.priceCents,
                currency: dbPlan.currency,
                billingPeriod: billingPeriod,
                billingPeriodMonths: dbPlan.billingPeriodMonths,
                planType: planType,
                maxSeats: dbPlan.maxSeats,
                features: dbPlan.features,
                aiChatLimit: dbPlan.aiChatLimit,
                exerciseLimit: dbPlan.exerciseLimit,
                appStoreProductId: dbPlan.appStoreProductId,
                isActive: dbPlan.isActive,
                isVisible: dbPlan.isVisible
            )
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product, promoCode: String? = nil) async throws {
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            try await submitTransaction(transaction, jwsRepresentation: verification.jwsRepresentation, promoCode: promoCode)
            await transaction.finish()

        case .pending:
            // Transaction is pending approval
            break

        case .userCancelled:
            throw BillingError.cancelled

        @unknown default:
            throw BillingError.unknown
        }
    }

    // MARK: - Restore

    func restorePurchases() async throws {
        try await AppStore.sync()

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                try await submitTransaction(transaction, jwsRepresentation: result.jwsRepresentation)
            }
        }

        // Refresh entitlements
        try await refreshEntitlements()
    }

    // MARK: - Entitlements

    func refreshEntitlements() async throws {
        // Fetch entitlements from Supabase profile
        guard let userId = authService.userId else { return }

        // Use dedicated struct for partial select to avoid decoding errors
        struct DBEntitlementsRow: Codable {
            let subscriptionTier: String
            let dailyAiQuota: Int
            let dailyAiUsed: Int

            enum CodingKeys: String, CodingKey {
                case subscriptionTier = "subscription_tier"
                case dailyAiQuota = "daily_ai_quota"
                case dailyAiUsed = "daily_ai_used"
            }
        }

        let entitlementsRow: DBEntitlementsRow = try await supabase
            .from(Tables.profiles)
            .select("subscription_tier, daily_ai_quota, daily_ai_used")
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        entitlements = Entitlements(
            tier: Tier(rawValue: entitlementsRow.subscriptionTier) ?? .free,
            dailyAiQuota: entitlementsRow.dailyAiQuota,
            dailyAiUsed: entitlementsRow.dailyAiUsed
        )

        // Also load subscription details
        await loadSubscription()
    }

    // MARK: - Subscription

    func loadSubscription() async {
        guard let userId = authService.userId else { return }

        do {
            let results: [Subscription] = try await supabase
                .from("subscriptions")
                .select()
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value

            let result = results.first
            subscription = result

            // If user has a family group, load it
            if result?.familyId != nil {
                await loadFamilyGroup()
            }
        } catch {
            Log.billing.error("Failed to load subscription: \(error)")
        }
    }

    // MARK: - Family Management

    /// Get the user's family group (if admin or member)
    func loadFamilyGroup() async {
        guard let userId = authService.userId else { return }

        // First check if user is admin - wrap in separate try to isolate failure
        var group: FamilyGroup?
        
        do {
            let adminGroups: [FamilyGroup] = try await supabase
                .from("family_groups")
                .select()
                .eq("admin_user_id", value: userId)
                .limit(1)
                .execute()
                .value
            group = adminGroups.first
        } catch {
            // Log but don't fail - user might still be a member
            Log.billing.warning("Failed to check admin family groups: \(error)")
        }

        // If not admin, check if member
        if group == nil {
            do {
                // Check family_members for this user's family
                struct MembershipResult: Codable {
                    let familyId: String

                    enum CodingKeys: String, CodingKey {
                        case familyId = "family_id"
                    }
                }

                let memberships: [MembershipResult] = try await supabase
                    .from("family_members")
                    .select("family_id")
                    .eq("user_id", value: userId)
                    .eq("status", value: "active")
                    .limit(1)
                    .execute()
                    .value

                if let membership = memberships.first {
                    group = try await supabase
                        .from("family_groups")
                        .select()
                        .eq("id", value: membership.familyId)
                        .single()
                        .execute()
                        .value
                }
            } catch {
                // Log but don't fail - user might not have a family
                Log.billing.warning("Failed to check family membership: \(error)")
            }
        }

        familyGroup = group

        // Load members if we have a group
        if group != nil {
            await loadFamilyMembers()
        }
    }

    /// Load all members of the user's family group
    func loadFamilyMembers() async {
        guard let group = familyGroup else { return }

        do {
            // Query family_members with joined profile data
            struct MemberWithProfile: Codable {
                let id: String
                let familyId: String
                let userId: String
                let invitedEmail: String?
                let invitedPhone: String?
                let status: FamilyMember.MemberStatus
                let invitedAt: Date
                let joinedAt: Date?
                let removedAt: Date?
                let profiles: ProfileData?

                struct ProfileData: Codable {
                    let displayName: String?
                    let handle: String?

                    enum CodingKeys: String, CodingKey {
                        case displayName = "display_name"
                        case handle
                    }
                }

                enum CodingKeys: String, CodingKey {
                    case id
                    case familyId = "family_id"
                    case userId = "user_id"
                    case invitedPhone = "invited_phone"
                    case invitedEmail = "invited_email"
                    case status
                    case invitedAt = "invited_at"
                    case joinedAt = "joined_at"
                    case removedAt = "removed_at"
                    case profiles
                }
            }

            let results: [MemberWithProfile] = try await supabase
                .from("family_members")
                .select("*, profiles(display_name, handle)")
                .eq("family_id", value: group.id)
                .neq("status", value: "removed")
                .execute()
                .value

            familyMembers = results.map { member in
                FamilyMember(
                    id: member.id,
                    familyId: member.familyId,
                    userId: member.userId,
                    invitedEmail: member.invitedEmail,
                    invitedPhone: member.invitedPhone,
                    status: member.status,
                    invitedAt: member.invitedAt,
                    joinedAt: member.joinedAt,
                    removedAt: member.removedAt,
                    displayName: member.profiles?.displayName,
                    handle: member.profiles?.handle
                )
            }
        } catch {
            Log.billing.error("Failed to load family members: \(error)")
            // Don't crash - just leave members empty
            familyMembers = []
        }
    }

    /// Send an invitation to join the family plan
    func inviteFamilyMember(email: String, sendEmail: Bool = false) async throws -> SendInviteResponse {
        guard familyGroup != nil else {
            throw BillingError.noFamilyGroup
        }

        guard let sub = subscription, sub.availableSeats > 0 else {
            throw BillingError.noSeatsAvailable
        }

        struct InviteRequest: Encodable {
            let email: String
            let sendEmail: Bool

            enum CodingKeys: String, CodingKey {
                case email
                case sendEmail = "send_email"
            }
        }

        let response: SendInviteResponse = try await supabase.functions.invoke(
            "send-family-invite",
            options: .init(body: InviteRequest(email: email, sendEmail: sendEmail))
        )

        if !response.success {
            throw BillingError.inviteFailed(response.message)
        }

        return response
    }

    /// Accept a family invitation using an invite code
    func acceptFamilyInvitation(code: String) async throws -> AcceptInviteResponse {
        let response: AcceptInviteResponse = try await supabase.functions.invoke(
            "accept-family-invite",
            options: .init(body: [
                "invite_code": code.uppercased()
            ])
        )

        if !response.success {
            throw BillingError.invalidInviteCode
        }

        // Refresh to get updated subscription and family info
        try await refreshEntitlements()

        return response
    }

    /// Remove a member from the family plan (admin only)
    func removeFamilyMember(memberId: String) async throws {
        guard let group = familyGroup,
              let currentUserId = authService.userId,
              group.adminUserId == currentUserId.uuidString else {
            throw BillingError.notFamilyAdmin
        }

        struct RemoveMemberUpdate: Encodable {
            let status: String
            let removedAt: String

            enum CodingKeys: String, CodingKey {
                case status
                case removedAt = "removed_at"
            }
        }

        try await supabase
            .from("family_members")
            .update(RemoveMemberUpdate(
                status: "removed",
                removedAt: ISO8601DateFormatter().string(from: Date())
            ))
            .eq("id", value: memberId)
            .execute()

        // Decrement seats used on admin subscription
        if let sub = subscription {
            struct SeatsUpdate: Encodable {
                let seatsUsed: Int
                let updatedAt: String

                enum CodingKeys: String, CodingKey {
                    case seatsUsed = "seats_used"
                    case updatedAt = "updated_at"
                }
            }

            try await supabase
                .from("subscriptions")
                .update(SeatsUpdate(
                    seatsUsed: max(1, sub.seatsUsed - 1),
                    updatedAt: ISO8601DateFormatter().string(from: Date())
                ))
                .eq("id", value: sub.id)
                .execute()
        }

        // Reload family members
        await loadFamilyMembers()
        await loadSubscription()
    }

    /// Get pending invitations for the family (admin only)
    func getPendingInvitations() async throws -> [FamilyInvitation] {
        guard let group = familyGroup,
              let currentUserId = authService.userId,
              group.adminUserId == currentUserId.uuidString else {
            return []
        }

        return try await supabase
            .from("family_invitations")
            .select()
            .eq("family_id", value: group.id)
            .is("accepted_at", value: nil)
            .gt("expires_at", value: ISO8601DateFormatter().string(from: Date()))
            .execute()
            .value
    }

    /// Check if current user is the family admin
    var isFamilyAdmin: Bool {
        guard let currentUserId = authService.userId else { return false }
        return familyGroup?.adminUserId == currentUserId.uuidString
    }

    // MARK: - Promo Codes

    /// Validate a promo code and fetch its details
    func validatePromoCode(_ code: String) async throws -> PromoCode {
        isValidatingPromo = true
        defer { isValidatingPromo = false }

        let response: PromoCode = try await supabase
            .from("promo_codes")
            .select()
            .eq("code", value: code.uppercased())
            .eq("is_active", value: true)
            .single()
            .execute()
            .value

        guard response.isValid else {
            throw BillingError.invalidPromoCode
        }

        validatedPromoCode = response
        return response
    }

    /// Clear the currently validated promo code
    func clearValidatedPromoCode() {
        validatedPromoCode = nil
    }

    // MARK: - Gift Subscriptions

    /// Purchase a subscription as a gift
    func purchaseGift(plan: SubscriptionPlan, recipient: GiftRecipient) async throws -> GiftSubscription {
        isPurchasingGift = true
        defer { isPurchasingGift = false }

        struct CreateGiftRequest: Encodable {
            let planId: String
            let recipientEmail: String
            let recipientName: String?
            let personalMessage: String?
            let deliveryDate: String
            let paymentMethodId: String

            enum CodingKeys: String, CodingKey {
                case planId = "plan_id"
                case recipientEmail = "recipient_email"
                case recipientName = "recipient_name"
                case personalMessage = "personal_message"
                case deliveryDate = "delivery_date"
                case paymentMethodId = "payment_method_id"
            }
        }

        let formatter = ISO8601DateFormatter()
        let request = CreateGiftRequest(
            planId: plan.id.uuidString,
            recipientEmail: recipient.email,
            recipientName: recipient.name,
            personalMessage: recipient.message,
            deliveryDate: formatter.string(from: recipient.deliveryDate),
            paymentMethodId: recipient.paymentMethodId
        )

        let result: GiftPurchaseResponse = try await supabase.functions.invoke(
            "create-gift",
            options: .init(body: request)
        )
        activeGift = result.gift
        return result.gift
    }

    /// Redeem a gift subscription using the redemption code
    func redeemGift(code: String) async throws {
        isRedeemingGift = true
        defer { isRedeemingGift = false }

        struct RedeemGiftRequest: Encodable {
            let redemptionCode: String

            enum CodingKeys: String, CodingKey {
                case redemptionCode = "redemption_code"
            }
        }

        // Verify success
        let result: GiftRedeemResponse = try await supabase.functions.invoke(
            "redeem-gift",
            options: .init(body: RedeemGiftRequest(redemptionCode: code))
        )
        if !result.success {
            throw BillingError.giftRedemptionFailed
        }

        // Refresh subscription to reflect redeemed gift
        try await refreshEntitlements()
    }

    // MARK: - HSA/FSA

    /// Load HSA/FSA record for current user's subscription
    func loadHSARecord() async throws {
        guard let userId = authService.userId else { return }

        do {
            let records: [HSAFSARecord] = try await supabase
                .from("hsa_fsa_records")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            hsaRecord = records.first
        } catch {
            Log.billing.error("Failed to load HSA/FSA record: \(error)")
        }
    }

    /// Generate an HSA/FSA compliant receipt for the current subscription
    func generateHSAReceipt() async throws -> URL {
        isGeneratingHSAReceipt = true
        defer { isGeneratingHSAReceipt = false }

        guard let subscriptionId = subscription?.id else {
            throw BillingError.noActiveSubscription
        }

        struct GenerateReceiptRequest: Encodable {
            let subscriptionId: String

            enum CodingKeys: String, CodingKey {
                case subscriptionId = "subscription_id"
            }
        }

        let result: HSAReceiptResponse = try await supabase.functions.invoke(
            "generate-hsa-receipt",
            options: .init(body: GenerateReceiptRequest(subscriptionId: subscriptionId))
        )

        guard result.success, let url = URL(string: result.receiptUrl) else {
            throw BillingError.hsaReceiptGenerationFailed
        }

        // Update local HSA record
        try await loadHSARecord()

        return url
    }

    /// Generate a Letter of Medical Necessity for HSA/FSA reimbursement
    func generateLetterOfMedicalNecessity() async throws -> URL {
        guard let subscriptionId = subscription?.id else {
            throw BillingError.noActiveSubscription
        }

        struct GenerateLOMNRequest: Encodable {
            let subscriptionId: String

            enum CodingKeys: String, CodingKey {
                case subscriptionId = "subscription_id"
            }
        }

        let result: LOmnResponse = try await supabase.functions.invoke(
            "generate-lomn",
            options: .init(body: GenerateLOMNRequest(subscriptionId: subscriptionId))
        )

        guard result.success, let url = URL(string: result.lomnUrl) else {
            throw BillingError.lomnGenerationFailed
        }

        // Update local HSA record
        try await loadHSARecord()

        return url
    }

    // MARK: - Private

    private func startTransactionListener() {
        transactionListener = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                do {
                    let transaction = try self.checkVerified(result)
                    try await self.submitTransaction(transaction, jwsRepresentation: result.jwsRepresentation)
                    await transaction.finish()
                } catch {
                    Log.billing.error("Transaction update error: \(error)")
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw BillingError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    private func submitTransaction(_ transaction: Transaction, jwsRepresentation: String, promoCode: String? = nil) async throws {
        // Use the JWS representation from VerificationResult for server-side verification
        struct VerifyPurchaseRequest: Encodable {
            let signedTransaction: String
            let environment: String
            let promoCode: String?

            enum CodingKeys: String, CodingKey {
                case signedTransaction
                case environment
                case promoCode = "promo_code"
            }
        }

        let _: VerifyPurchaseResponse = try await supabase.functions.invoke(
            "verify-purchase",
            options: .init(body: VerifyPurchaseRequest(
                signedTransaction: jwsRepresentation,
                environment: transaction.environment == .sandbox ? "sandbox" : "production",
                promoCode: promoCode
            ))
        )

        // Refresh entitlements after successful transaction
        try await refreshEntitlements()
    }
}

// MARK: - Gift Recipient

/// Information needed to purchase a gift subscription
struct GiftRecipient {
    let email: String
    let name: String?
    let message: String?
    let deliveryDate: Date
    let paymentMethodId: String
}

// MARK: - Billing Error

enum BillingError: Error, LocalizedError, Equatable {
    case cancelled
    case verificationFailed
    case invalidTransaction
    case unknown
    case noFamilyGroup
    case noSeatsAvailable
    case invalidInviteCode
    case inviteExpired
    case inviteFailed(String)
    case notFamilyAdmin
    case invalidPromoCode
    case giftRedemptionFailed
    case noActiveSubscription
    case hsaReceiptGenerationFailed
    case lomnGenerationFailed
    case productNotFound

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Purchase was cancelled"
        case .verificationFailed:
            return "Transaction verification failed"
        case .invalidTransaction:
            return "Invalid transaction"
        case .unknown:
            return "An unknown error occurred"
        case .noFamilyGroup:
            return "You don't have a family plan"
        case .noSeatsAvailable:
            return "No seats available in your plan"
        case .invalidInviteCode:
            return "Invalid invitation code"
        case .inviteExpired:
            return "This invitation has expired"
        case .inviteFailed(let message):
            return message
        case .notFamilyAdmin:
            return "Only the plan admin can perform this action"
        case .invalidPromoCode:
            return "This promo code is invalid or expired"
        case .giftRedemptionFailed:
            return "Failed to redeem gift subscription"
        case .noActiveSubscription:
            return "No active subscription found"
        case .hsaReceiptGenerationFailed:
            return "Failed to generate HSA/FSA receipt"
        case .lomnGenerationFailed:
            return "Failed to generate Letter of Medical Necessity"
        case .productNotFound:
            return "Product not found in the App Store"
        }
    }
}

// MARK: - Response Types

/// Response from gift redemption Edge Function
struct GiftRedeemResponse: Codable {
    let success: Bool
    let message: String?
}

/// Response from generate-lomn Edge Function
struct LOmnResponse: Codable {
    let success: Bool
    let lomnUrl: String
    let lomnNumber: String

    enum CodingKeys: String, CodingKey {
        case success
        case lomnUrl = "lomn_url"
        case lomnNumber = "lomn_number"
    }
}

// MARK: - Helper for invite code generation (client-side display)

extension BillingService {
    /// Generate an 8-character invite code (for display purposes only - real codes come from server)
    static func generateDisplayCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<8).map { _ in chars.randomElement()! })
    }
}
