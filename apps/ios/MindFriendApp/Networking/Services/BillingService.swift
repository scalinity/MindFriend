import Foundation
import StoreKit

/// Service for billing and subscriptions
@MainActor
final class BillingService: ObservableObject {
    private let apiClient: APIClient

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPurchasing = false
    @Published private(set) var entitlements: Entitlements = .free

    private var transactionListener: Task<Void, Error>?

    static let productIds = [
        "com.mindfriend.premium.monthly",
        "com.mindfriend.premium.yearly"
    ]

    init(apiClient: APIClient) {
        self.apiClient = apiClient
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
        let response: EntitlementsResponse = try await apiClient.request(.getEntitlements)
        entitlements = response.entitlements
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
        guard let jwsRepresentation = String(data: transaction.jsonRepresentation, encoding: .utf8) else {
            throw BillingError.invalidTransaction
        }

        let _: SubmitTransactionResponse = try await apiClient.request(
            .submitAppleTransaction(signedTransaction: jwsRepresentation)
        )

        // Refresh entitlements after successful transaction
        try await refreshEntitlements()
    }
}

// MARK: - Response Types

struct EntitlementsResponse: Decodable {
    let entitlements: Entitlements
}

struct SubmitTransactionResponse: Decodable {
    let status: String
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
