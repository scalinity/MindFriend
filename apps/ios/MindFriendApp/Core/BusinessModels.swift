import Foundation

// MARK: - Subscription Plan

/// A subscription plan offering from MindFriend
struct SubscriptionPlan: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let description: String?

    // Pricing
    let priceCents: Int
    let currency: String
    let billingPeriod: BillingPeriod
    let billingPeriodMonths: Int?

    // Plan type and capacity
    let planType: PlanType
    let maxSeats: Int?

    // Features
    let features: PlanFeatures
    let aiChatLimit: Int?
    let exerciseLimit: Int?

    // Store IDs
    let appStoreProductId: String?

    // Status
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

    /// Formatted price string (e.g., "$9.99")
    var displayPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: Double(priceCents) / 100)) ?? "$\(priceCents / 100)"
    }

    /// Price per month for multi-month plans (e.g., "$6.67/month" for annual)
    var pricePerMonth: String? {
        guard let months = billingPeriodMonths, months > 1 else { return nil }
        let monthlyPrice = Double(priceCents) / Double(months) / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: monthlyPrice))
    }

    /// Savings percentage for annual plans
    var savingsPercent: Int? {
        billingPeriod == .yearly ? 50 : nil
    }

    // MARK: - Static Defaults

    static let premiumMonthly = SubscriptionPlan(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
        name: "Premium Monthly",
        description: "Unlimited access",
        priceCents: 1299,
        currency: "USD",
        billingPeriod: .monthly,
        billingPeriodMonths: 1,
        planType: .individual,
        maxSeats: 1,
        features: .premium,
        aiChatLimit: nil,
        exerciseLimit: nil,
        appStoreProductId: "com.mindfriend.premium.monthly",
        isActive: true,
        isVisible: true
    )

    static let premiumAnnual = SubscriptionPlan(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID(),
        name: "Premium Annual",
        description: "Save 2 months with annual billing",
        priceCents: 7799,
        currency: "USD",
        billingPeriod: .yearly,
        billingPeriodMonths: 12,
        planType: .individual,
        maxSeats: 1,
        features: .premium,
        aiChatLimit: nil,
        exerciseLimit: nil,
        appStoreProductId: "com.mindfriend.premium.yearly",
        isActive: true,
        isVisible: true
    )

    static let familyAnnual = SubscriptionPlan(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003") ?? UUID(),
        name: "Family Annual",
        description: "Up to 6 family members",
        priceCents: 14999,
        currency: "USD",
        billingPeriod: .yearly,
        billingPeriodMonths: 12,
        planType: .family,
        maxSeats: 6,
        features: .premium,
        aiChatLimit: nil,
        exerciseLimit: nil,
        appStoreProductId: "com.mindfriend.family.annual",
        isActive: true,
        isVisible: true
    )
    
    static let couplesMonthly = SubscriptionPlan(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004") ?? UUID(),
        name: "Couples Monthly",
        description: "For 2 people",
        priceCents: 1999,
        currency: "USD",
        billingPeriod: .monthly,
        billingPeriodMonths: 1,
        planType: .couples,
        maxSeats: 2,
        features: .premium,
        aiChatLimit: nil,
        exerciseLimit: nil,
        appStoreProductId: "com.mindfriend.couples.monthly",
        isActive: true,
        isVisible: true
    )
    
    static let couplesAnnual = SubscriptionPlan(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000005") ?? UUID(),
        name: "Couples Annual",
        description: "For 2 people - Save 50%",
        priceCents: 11999,
        currency: "USD",
        billingPeriod: .yearly,
        billingPeriodMonths: 12,
        planType: .couples,
        maxSeats: 2,
        features: .premium,
        aiChatLimit: nil,
        exerciseLimit: nil,
        appStoreProductId: "com.mindfriend.couples.annual",
        isActive: true,
        isVisible: true
    )
    
    static let familyMonthly = SubscriptionPlan(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000006") ?? UUID(),
        name: "Family Monthly",
        description: "Up to 6 people",
        priceCents: 2499,
        currency: "USD",
        billingPeriod: .monthly,
        billingPeriodMonths: 1,
        planType: .family,
        maxSeats: 6,
        features: .premium,
        aiChatLimit: nil,
        exerciseLimit: nil,
        appStoreProductId: "com.mindfriend.family.monthly",
        isActive: true,
        isVisible: true
    )
    
    static let enterpriseMonthly = SubscriptionPlan(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000007") ?? UUID(),
        name: "Enterprise Monthly",
        description: "For organizations",
        priceCents: 9999,
        currency: "USD",
        billingPeriod: .monthly,
        billingPeriodMonths: 1,
        planType: .enterprise,
        maxSeats: nil,
        features: .premium,
        aiChatLimit: nil,
        exerciseLimit: nil,
        appStoreProductId: "com.mindfriend.enterprise.monthly",
        isActive: true,
        isVisible: true
    )
    
    static let enterpriseAnnual = SubscriptionPlan(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000008") ?? UUID(),
        name: "Enterprise Annual",
        description: "For organizations - Save 50%",
        priceCents: 79999,
        currency: "USD",
        billingPeriod: .yearly,
        billingPeriodMonths: 12,
        planType: .enterprise,
        maxSeats: nil,
        features: .premium,
        aiChatLimit: nil,
        exerciseLimit: nil,
        appStoreProductId: "com.mindfriend.enterprise.annual",
        isActive: true,
        isVisible: true
    )
    
    /// All available plans grouped by plan type
    static var allPlans: [PlanType: [SubscriptionPlan]] {
        [
            .individual: [premiumMonthly, premiumAnnual],
            .couples: [couplesMonthly, couplesAnnual],
            .family: [familyMonthly, familyAnnual],
            .enterprise: [enterpriseMonthly, enterpriseAnnual]
        ]
    }
    
    /// Get monthly plan for a plan type
    static func monthlyPlan(for planType: PlanType) -> SubscriptionPlan? {
        allPlans[planType]?.first { $0.billingPeriod == .monthly }
    }
    
    /// Get annual plan for a plan type
    static func annualPlan(for planType: PlanType) -> SubscriptionPlan? {
        allPlans[planType]?.first { $0.billingPeriod == .yearly }
    }
}

// MARK: - Plan Features

/// Feature set for a subscription plan
struct PlanFeatures: Codable, Equatable, Hashable {
    let unlimitedChat: Bool
    let unlimitedExercises: Bool
    let premiumContent: Bool
    let prioritySupport: Bool
    let familySharing: Bool
    let offlineMode: Bool
    let customThemes: Bool
    let advancedInsights: Bool

    enum CodingKeys: String, CodingKey {
        case unlimitedChat = "unlimited_chat"
        case unlimitedExercises = "unlimited_exercises"
        case premiumContent = "premium_content"
        case prioritySupport = "priority_support"
        case familySharing = "family_sharing"
        case offlineMode = "offline_mode"
        case customThemes = "custom_themes"
        case advancedInsights = "advanced_insights"
    }

    // MARK: - Static Defaults

    static let free = PlanFeatures(
        unlimitedChat: false,
        unlimitedExercises: false,
        premiumContent: false,
        prioritySupport: false,
        familySharing: false,
        offlineMode: false,
        customThemes: false,
        advancedInsights: false
    )

    static let premium = PlanFeatures(
        unlimitedChat: true,
        unlimitedExercises: true,
        premiumContent: true,
        prioritySupport: true,
        familySharing: false,
        offlineMode: true,
        customThemes: true,
        advancedInsights: true
    )

    static let family = PlanFeatures(
        unlimitedChat: true,
        unlimitedExercises: true,
        premiumContent: true,
        prioritySupport: true,
        familySharing: true,
        offlineMode: true,
        customThemes: true,
        advancedInsights: true
    )
}

// MARK: - Promo Code

/// A promotional code for subscription discounts or trial extensions
struct PromoCode: Codable, Identifiable, Equatable {
    let id: UUID
    let code: String
    let discountType: DiscountType
    let discountValue: Int
    let trialExtensionDays: Int?

    let applicablePlans: [UUID]?
    let minBillingPeriod: BillingPeriod?
    let firstTimeOnly: Bool

    let maxUses: Int?
    let usesCount: Int
    let maxUsesPerUser: Int?

    let validFrom: Date
    let validUntil: Date?
    let isActive: Bool

    let campaignName: String?

    enum CodingKeys: String, CodingKey {
        case id, code
        case discountType = "discount_type"
        case discountValue = "discount_value"
        case trialExtensionDays = "trial_extension_days"
        case applicablePlans = "applicable_plans"
        case minBillingPeriod = "min_billing_period"
        case firstTimeOnly = "first_time_only"
        case maxUses = "max_uses"
        case usesCount = "uses_count"
        case maxUsesPerUser = "max_uses_per_user"
        case validFrom = "valid_from"
        case validUntil = "valid_until"
        case isActive = "is_active"
        case campaignName = "campaign_name"
    }

    /// Whether this promo code is valid and can be applied
    var isValid: Bool {
        guard isActive else { return false }
        let now = Date()
        if now < validFrom { return false }
        if let until = validUntil, now > until { return false }
        if let max = maxUses, usesCount >= max { return false }
        return true
    }

    /// Human-readable discount description
    var discountDescription: String {
        switch discountType {
        case .percent:
            return "\(discountValue)% off"
        case .fixed:
            return "$\(discountValue / 100) off"
        case .trialExtension:
            return "\(trialExtensionDays ?? 0) days free trial"
        }
    }
}

// MARK: - Discount Type

enum DiscountType: String, Codable {
    case percent
    case fixed
    case trialExtension = "trial_extension"
}

// MARK: - Gift Subscription

/// A subscription purchased as a gift for another user
struct GiftSubscription: Codable, Identifiable, Equatable {
    let id: UUID
    let purchaserUserId: UUID?
    let purchaserEmail: String

    let planId: UUID
    let durationMonths: Int
    let priceCents: Int

    let recipientEmail: String
    let recipientName: String?
    let personalMessage: String?

    let deliveryDate: Date
    let deliveredAt: Date?

    let redemptionCode: String
    let redeemedAt: Date?
    let redeemedByUserId: UUID?

    var status: GiftStatus
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case purchaserUserId = "purchaser_user_id"
        case purchaserEmail = "purchaser_email"
        case planId = "plan_id"
        case durationMonths = "duration_months"
        case priceCents = "price_cents"
        case recipientEmail = "recipient_email"
        case recipientName = "recipient_name"
        case personalMessage = "personal_message"
        case deliveryDate = "delivery_date"
        case deliveredAt = "delivered_at"
        case redemptionCode = "redemption_code"
        case redeemedAt = "redeemed_at"
        case redeemedByUserId = "redeemed_by_user_id"
        case status
        case expiresAt = "expires_at"
    }

    /// Whether this gift can still be redeemed
    var canBeRedeemed: Bool {
        status == .pending && (expiresAt == nil || Date() < expiresAt!)
    }

    /// Formatted gift amount
    var displayPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: Double(priceCents) / 100)) ?? "$\(priceCents / 100)"
    }
}

// MARK: - Gift Status

enum GiftStatus: String, Codable {
    case pending
    case delivered
    case redeemed
    case expired
    case refunded
}

// MARK: - HSA/FSA Record

/// A record for HSA/FSA eligible subscription with receipt and Letter of Medical Necessity
struct HSAFSARecord: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let subscriptionId: UUID?

    let isHSAEligible: Bool
    let isFSAEligible: Bool

    let lomnGeneratedAt: Date?
    let lomnUrl: String?

    let receiptGeneratedAt: Date?
    let receiptUrl: String?
    let receiptAmountCents: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case subscriptionId = "subscription_id"
        case isHSAEligible = "is_hsa_eligible"
        case isFSAEligible = "is_fsa_eligible"
        case lomnGeneratedAt = "lomn_generated_at"
        case lomnUrl = "lomn_url"
        case receiptGeneratedAt = "receipt_generated_at"
        case receiptUrl = "receipt_url"
        case receiptAmountCents = "receipt_amount_cents"
    }

    /// Whether a Letter of Medical Necessity has been generated
    var hasLetterOfMedicalNecessity: Bool {
        lomnUrl != nil
    }

    /// Whether an itemized receipt has been generated
    var hasReceipt: Bool {
        receiptUrl != nil
    }

    /// Formatted receipt amount if available
    var displayReceiptAmount: String? {
        guard let cents = receiptAmountCents else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: Double(cents) / 100))
    }

    // MARK: - Static Defaults

    static let sample = HSAFSARecord(
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
}

// MARK: - Billing Period

enum BillingPeriod: String, Codable, CaseIterable {
    case monthly
    case yearly

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly: return "Annual"
        }
    }

    var savingsPercent: Int? {
        switch self {
        case .monthly: return nil
        case .yearly: return 20
        }
    }
}

// MARK: - Plan Type

enum PlanType: String, Codable, CaseIterable {
    case individual
    case couples
    case family
    case enterprise
    case gift

    var displayName: String {
        switch self {
        case .individual: return "Individual"
        case .couples: return "Couples"
        case .family: return "Family"
        case .enterprise: return "Enterprise"
        case .gift: return "Gift"
        }
    }

    var maxSeats: Int {
        switch self {
        case .individual: return 1
        case .couples: return 2
        case .family: return 6
        case .enterprise: return Int.max
        case .gift: return 1
        }
    }

    var description: String {
        switch self {
        case .individual: return "Just for you"
        case .couples: return "For 2 people"
        case .family: return "Up to 6 people"
        case .enterprise: return "For organizations"
        case .gift: return "Gift to someone"
        }
    }

    var isFamilyPlan: Bool {
        self == .family || self == .couples
    }
}

// MARK: - Response Types

/// Response from create-gift Edge Function
struct GiftPurchaseResponse: Codable {
    let success: Bool
    let gift: GiftSubscription
}

/// Response from generate-hsa-receipt Edge Function
struct HSAReceiptResponse: Codable {
    let success: Bool
    let receiptUrl: String
    let receiptNumber: String

    enum CodingKeys: String, CodingKey {
        case success
        case receiptUrl = "receipt_url"
        case receiptNumber = "receipt_number"
    }
}

/// Response from validate-promo-code Edge Function
struct ValidatePromoResponse: Codable {
    let success: Bool
    let promo: PromoCode?
    let message: String?
}
