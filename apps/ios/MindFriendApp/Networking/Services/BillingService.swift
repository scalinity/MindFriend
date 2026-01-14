import Foundation
import StoreKit
import Supabase

/// Service for billing and subscriptions - uses Supabase Edge Functions
@MainActor
final class BillingService: ObservableObject {
    private let authService: SupabaseAuthService

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPurchasing = false
    @Published private(set) var entitlements: Entitlements = .free

    private var transactionListener: Task<Void, Error>?

    static let productIds = [
        "com.mindfriend.premium.monthly",
        "com.mindfriend.premium.yearly"
    ]

    init(authService: SupabaseAuthService) {
        self.authService = authService
        startTransactionListener()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            products = try await Product.products(for: Self.productIds)
                .sorted { $0.price < $1.price }
        } catch {
            print("Failed to load products: \(error)")
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
    }

    // MARK: - Private

    private func startTransactionListener() {
        transactionListener = Task {
            for await result in Transaction.updates {
                do {
                    let transaction = try checkVerified(result)
                    try await submitTransaction(transaction)
                    await transaction.finish()
                } catch {
                    print("Transaction update error: \(error)")
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

// Response from verify-purchase Edge Function
struct VerifyPurchaseResponse: Codable {
    let valid: Bool
    let productId: String?
    let message: String?
}

// MARK: - Billing Error

enum BillingError: Error, LocalizedError {
    case cancelled
    case verificationFailed
    case invalidTransaction
    case unknown

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
        }
    }
}
