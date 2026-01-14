import Foundation
import StoreKit
import Supabase
import OSLog

/// Service for billing and subscriptions - uses Supabase Edge Functions
@MainActor
final class BillingService: ObservableObject {
    private let authService: SupabaseAuthService

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPurchasing = false
    @Published private(set) var entitlements: Entitlements = .free
    @Published private(set) var subscription: Subscription?
    @Published private(set) var familyGroup: FamilyGroup?
    @Published private(set) var familyMembers: [FamilyMember] = []

    private var transactionListener: Task<Void, Error>?

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
        "com.mindfriend.premium.yearly": .annual,
        "com.mindfriend.couples.monthly": .monthly,
        "com.mindfriend.couples.annual": .annual,
        "com.mindfriend.family.monthly": .monthly,
        "com.mindfriend.family.annual": .annual
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

    // MARK: - Purchase

    func purchase(_ product: Product) async throws {
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            try await submitTransaction(transaction)
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
                try await submitTransaction(transaction)
            }
        }

        // Refresh entitlements
        try await refreshEntitlements()
    }

    // MARK: - Entitlements

    func refreshEntitlements() async throws {
        // Fetch entitlements from Supabase profile
        guard let userId = authService.userId else { return }

        let profile: DBProfile = try await supabase
            .from(Tables.profiles)
            .select("subscription_tier, daily_ai_quota, daily_ai_used")
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        entitlements = Entitlements(
            tier: Tier(rawValue: profile.subscriptionTier) ?? .free,
            dailyAiQuota: profile.dailyAiQuota,
            dailyAiUsed: profile.dailyAiUsed
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

        do {
            // First check if user is admin
            let adminGroups: [FamilyGroup] = try await supabase
                .from("family_groups")
                .select()
                .eq("admin_user_id", value: userId)
                .limit(1)
                .execute()
                .value

            var group: FamilyGroup? = adminGroups.first

            // If not admin, check if member
            if group == nil {
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
            }

            familyGroup = group

            // Load members if we have a group
            if group != nil {
                await loadFamilyMembers()
            }
        } catch {
            Log.billing.error("Failed to load family group: \(error)")
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

    // MARK: - Private

    private func startTransactionListener() {
        transactionListener = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                do {
                    let transaction = try self.checkVerified(result)
                    try await self.submitTransaction(transaction)
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

    private func submitTransaction(_ transaction: Transaction) async throws {
        // Call verify-purchase Edge Function
        let _: VerifyPurchaseResponse = try await supabase.functions.invoke(
            "verify-purchase",
            options: .init(body: [
                "originalTransactionId": String(transaction.originalID),
                "productId": transaction.productID,
                "environment": transaction.environment == .sandbox ? "sandbox" : "production"
            ])
        )

        // Refresh entitlements after successful transaction
        try await refreshEntitlements()
    }
}

// NOTE: VerifyPurchaseResponse is defined in Models.swift (extended version with family plan fields)

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
        }
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
