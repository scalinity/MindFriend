import Foundation

// TEMPORARY STUB - BusinessModels.swift exists but not added to project yet
// This allows PromoCodeField and PlanCard to compile

struct PromoCode: Codable, Identifiable, Equatable {
    let id: UUID
    let code: String
    let discountType: DiscountType
    let discountValue: Int
    let trialExtensionDays: Int?

    enum DiscountType: String, Codable {
        case percent
        case fixed
    }

    var discountDescription: String {
        switch discountType {
        case .percent:
            return "\(discountValue)% off"
        case .fixed:
            return "$\(discountValue) off"
        }
    }
}

struct SubscriptionPlan: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let description: String
    let priceCents: Int
    let currency: String
    let billingPeriod: BillingPeriod
    let billingPeriodMonths: Int
    let planType: PlanType
    let maxSeats: Int
    let features: [String]
    let aiChatLimit: Int?
    let exerciseLimit: Int?
    let appStoreProductId: String
    let isActive: Bool
    let isVisible: Bool

    enum BillingPeriod: String, Codable {
        case monthly
        case yearly
    }

    enum PlanType: String, Codable {
        case free
        case premium
        case family
    }

    static let premiumMonthly = SubscriptionPlan(
        id: UUID(),
        name: "Premium Monthly",
        description: "Unlock all features",
        priceCents: 999,
        currency: "USD",
        billingPeriod: .monthly,
        billingPeriodMonths: 1,
        planType: .premium,
        maxSeats: 1,
        features: [],
        aiChatLimit: nil,
        exerciseLimit: nil,
        appStoreProductId: "com.mindfriend.premium.monthly",
        isActive: true,
        isVisible: true
    )
}
