// MindFriend Creator Models
// Data models for content creator platform: profiles, content, earnings, and revenue sharing

import Foundation

// MARK: - Enums

enum VerificationLevel: String, Codable {
    case pending
    case verified
    case expert
    case partner

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .verified: return "Verified"
        case .expert: return "Expert"
        case .partner: return "Partner"
        }
    }

    var badge: String {
        switch self {
        case .verified: return "checkmark.seal.fill"
        case .expert: return "star.fill"
        case .partner: return "diamond.fill"
        case .pending: return ""
        }
    }
}

enum CreatorStatus: String, Codable {
    case pending
    case approved
    case suspended
    case rejected

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .approved: return "Approved"
        case .suspended: return "Suspended"
        case .rejected: return "Rejected"
        }
    }
}

enum ContentType: String, Codable, CaseIterable {
    case meditation
    case breathing
    case journaling
    case educational
    case movement

    var displayName: String {
        switch self {
        case .meditation: return "Meditation"
        case .breathing: return "Breathing Exercise"
        case .journaling: return "Journaling Prompt"
        case .educational: return "Educational"
        case .movement: return "Movement Guide"
        }
    }

    var icon: String {
        switch self {
        case .meditation: return "brain.head.profile"
        case .breathing: return "wind"
        case .journaling: return "book"
        case .educational: return "lightbulb"
        case .movement: return "figure.walk"
        }
    }
}

enum ContentFormat: String, Codable {
    case audio
    case video
    case text

    var displayName: String {
        switch self {
        case .audio: return "Audio"
        case .video: return "Video"
        case .text: return "Text"
        }
    }
}

enum ContentDifficulty: String, Codable, CaseIterable {
    case beginner
    case intermediate
    case advanced

    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }
}

enum ContentStatus: String, Codable {
    case draft
    case submitted
    case inReview = "in_review"
    case approved
    case rejected
    case published

    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .submitted: return "Submitted"
        case .inReview: return "In Review"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        case .published: return "Published"
        }
    }

    var color: String {
        switch self {
        case .draft: return "gray"
        case .submitted, .inReview: return "yellow"
        case .approved, .published: return "green"
        case .rejected: return "red"
        }
    }
}

enum PayoutStatus: String, Codable {
    case pending
    case processing
    case paid
    case failed
    case belowThreshold = "below_threshold"

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .processing: return "Processing"
        case .paid: return "Paid"
        case .failed: return "Failed"
        case .belowThreshold: return "Below Threshold"
        }
    }
}

enum PeriodStatus: String, Codable {
    case open
    case calculating
    case finalized
    case paid

    var displayName: String {
        switch self {
        case .open: return "Open"
        case .calculating: return "Calculating"
        case .finalized: return "Finalized"
        case .paid: return "Paid"
        }
    }
}

// MARK: - Database Models

struct DBCreator: Codable {
    let id: UUID
    let userId: UUID
    let displayName: String
    let bio: String?
    let profileImageUrl: String?
    let websiteUrl: String?
    let socialLinks: [String: String]?
    let verificationLevel: String
    let verifiedAt: String?
    let status: String
    let statusReason: String?
    let payoutEnabled: Bool
    let taxInfoComplete: Bool
    let followerCount: Int
    let contentCount: Int
    let totalPlays: Int
    let totalMinutes: Int
    let averageRating: Double?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case displayName = "display_name"
        case bio
        case profileImageUrl = "profile_image_url"
        case websiteUrl = "website_url"
        case socialLinks = "social_links"
        case verificationLevel = "verification_level"
        case verifiedAt = "verified_at"
        case status
        case statusReason = "status_reason"
        case payoutEnabled = "payout_enabled"
        case taxInfoComplete = "tax_info_complete"
        case followerCount = "follower_count"
        case contentCount = "content_count"
        case totalPlays = "total_plays"
        case totalMinutes = "total_minutes"
        case averageRating = "average_rating"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DBCreatorContent: Codable {
    let id: UUID
    let creatorId: UUID
    let contentType: String
    let format: String
    let title: String
    let description: String?
    let durationSeconds: Int?
    let difficulty: String?
    let mediaUrl: String?
    let coverImageUrl: String?
    let thumbnailUrl: String?
    let category: String
    let tags: [String]
    let transcript: String?
    let hasCaptions: Bool
    let triggerWarnings: [String]?
    let ageRating: String
    let seriesId: UUID?
    let seriesOrder: Int?
    let status: String
    let submittedAt: String?
    let reviewedAt: String?
    let reviewFeedback: String?
    let publishedAt: String?
    let playCount: Int
    let uniqueListeners: Int
    let completionCount: Int
    let averageCompletionRate: Double
    let averageRating: Double?
    let ratingCount: Int
    let isPremium: Bool
    let isFeatured: Bool
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case creatorId = "creator_id"
        case contentType = "content_type"
        case format
        case title, description
        case durationSeconds = "duration_seconds"
        case difficulty
        case mediaUrl = "media_url"
        case coverImageUrl = "cover_image_url"
        case thumbnailUrl = "thumbnail_url"
        case category, tags, transcript
        case hasCaptions = "has_captions"
        case triggerWarnings = "trigger_warnings"
        case ageRating = "age_rating"
        case seriesId = "series_id"
        case seriesOrder = "series_order"
        case status
        case submittedAt = "submitted_at"
        case reviewedAt = "reviewed_at"
        case reviewFeedback = "review_feedback"
        case publishedAt = "published_at"
        case playCount = "play_count"
        case uniqueListeners = "unique_listeners"
        case completionCount = "completion_count"
        case averageCompletionRate = "average_completion_rate"
        case averageRating = "average_rating"
        case ratingCount = "rating_count"
        case isPremium = "is_premium"
        case isFeatured = "is_featured"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DBCreatorEarnings: Codable {
    let id: UUID
    let creatorId: UUID
    let periodId: UUID
    let totalMinutes: Int
    let premiumMinutes: Int
    let sharePercentage: Double
    let grossEarnings: Double
    let platformFee: Double
    let netEarnings: Double
    let payoutStatus: String
    let paidAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case creatorId = "creator_id"
        case periodId = "period_id"
        case totalMinutes = "total_minutes"
        case premiumMinutes = "premium_minutes"
        case sharePercentage = "share_percentage"
        case grossEarnings = "gross_earnings"
        case platformFee = "platform_fee"
        case netEarnings = "net_earnings"
        case payoutStatus = "payout_status"
        case paidAt = "paid_at"
        case createdAt = "created_at"
    }
}

struct DBRevenuePeriod: Codable {
    let id: UUID
    let periodMonth: String
    let periodStart: String
    let periodEnd: String
    let totalSubscriptionRevenue: Double?
    let creatorPoolPercentage: Double
    let totalCreatorPool: Double?
    let totalPremiumMinutes: Int
    let status: String
    let finalizedAt: String?
    let paidAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case periodMonth = "period_month"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case totalSubscriptionRevenue = "total_subscription_revenue"
        case creatorPoolPercentage = "creator_pool_percentage"
        case totalCreatorPool = "total_creator_pool"
        case totalPremiumMinutes = "total_premium_minutes"
        case status
        case finalizedAt = "finalized_at"
        case paidAt = "paid_at"
    }
}

// MARK: - Domain Models

struct Creator: Identifiable, Hashable {
    let id: UUID
    let displayName: String
    let bio: String?
    let profileImageUrl: String?
    let websiteUrl: String?
    let verificationLevel: VerificationLevel
    let verifiedAt: Date?
    let status: CreatorStatus
    let followerCount: Int
    let contentCount: Int
    let totalPlays: Int
    let totalMinutes: Int
    let averageRating: Double?

    init(from db: DBCreator) {
        self.id = db.id
        self.displayName = db.displayName
        self.bio = db.bio
        self.profileImageUrl = db.profileImageUrl
        self.websiteUrl = db.websiteUrl
        self.verificationLevel = VerificationLevel(rawValue: db.verificationLevel) ?? .pending
        self.verifiedAt = db.verifiedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        self.status = CreatorStatus(rawValue: db.status) ?? .pending
        self.followerCount = db.followerCount
        self.contentCount = db.contentCount
        self.totalPlays = db.totalPlays
        self.totalMinutes = db.totalMinutes
        self.averageRating = db.averageRating
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Creator, rhs: Creator) -> Bool {
        lhs.id == rhs.id
    }
}

struct CreatorContent: Identifiable, Hashable {
    let id: UUID
    let creatorId: UUID
    let contentType: ContentType
    let format: ContentFormat
    let title: String
    let description: String?
    let durationSeconds: Int?
    let difficulty: ContentDifficulty?
    let mediaUrl: String?
    let coverImageUrl: String?
    let category: String
    let tags: [String]
    let status: ContentStatus
    let submittedAt: Date?
    let publishedAt: Date?
    let playCount: Int
    let uniqueListeners: Int
    let averageRating: Double?
    let ratingCount: Int

    var formattedDuration: String {
        guard let seconds = durationSeconds else { return "--:--" }
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    init(from db: DBCreatorContent) {
        self.id = db.id
        self.creatorId = db.creatorId
        self.contentType = ContentType(rawValue: db.contentType) ?? .meditation
        self.format = ContentFormat(rawValue: db.format) ?? .audio
        self.title = db.title
        self.description = db.description
        self.durationSeconds = db.durationSeconds
        self.difficulty = db.difficulty.flatMap { ContentDifficulty(rawValue: $0) }
        self.mediaUrl = db.mediaUrl
        self.coverImageUrl = db.coverImageUrl
        self.category = db.category
        self.tags = db.tags
        self.status = ContentStatus(rawValue: db.status) ?? .draft
        self.submittedAt = db.submittedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        self.publishedAt = db.publishedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        self.playCount = db.playCount
        self.uniqueListeners = db.uniqueListeners
        self.averageRating = db.averageRating
        self.ratingCount = db.ratingCount
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CreatorContent, rhs: CreatorContent) -> Bool {
        lhs.id == rhs.id
    }
}

struct CreatorEarnings: Identifiable {
    let id: UUID
    let totalMinutes: Int
    let premiumMinutes: Int
    let sharePercentage: Double
    let grossEarnings: Double
    let platformFee: Double
    let netEarnings: Double
    let payoutStatus: PayoutStatus
    let paidAt: Date?

    var formattedNetEarnings: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: NSNumber(value: netEarnings)) ?? "$0.00"
    }

    init(from db: DBCreatorEarnings) {
        self.id = db.id
        self.totalMinutes = db.totalMinutes
        self.premiumMinutes = db.premiumMinutes
        self.sharePercentage = db.sharePercentage
        self.grossEarnings = db.grossEarnings
        self.platformFee = db.platformFee
        self.netEarnings = db.netEarnings
        self.payoutStatus = PayoutStatus(rawValue: db.payoutStatus) ?? .pending
        self.paidAt = db.paidAt.flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}

struct RevenuePeriod: Identifiable {
    let id: UUID
    let periodMonth: String
    let periodStart: Date
    let periodEnd: Date
    let totalSubscriptionRevenue: Double?
    let totalCreatorPool: Double?
    let totalPremiumMinutes: Int
    let status: PeriodStatus

    var formattedMonth: String {
        let parts = periodMonth.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else { return periodMonth }

        let date = Calendar.current.date(from: DateComponents(year: year, month: month))!
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    init(from db: DBRevenuePeriod) {
        self.id = db.id
        self.periodMonth = db.periodMonth
        self.periodStart = ISO8601DateFormatter().date(from: db.periodStart) ?? Date()
        self.periodEnd = ISO8601DateFormatter().date(from: db.periodEnd) ?? Date()
        self.totalSubscriptionRevenue = db.totalSubscriptionRevenue
        self.totalCreatorPool = db.totalCreatorPool
        self.totalPremiumMinutes = db.totalPremiumMinutes
        self.status = PeriodStatus(rawValue: db.status) ?? .open
    }
}

// MARK: - Errors

enum CreatorError: Error, LocalizedError {
    case notAuthenticated
    case notCreator
    case cannotDeletePublished
    case contentNotFound
    case invalidInput(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in."
        case .notCreator:
            return "You are not a creator. Apply to become one."
        case .cannotDeletePublished:
            return "Published content cannot be deleted."
        case .contentNotFound:
            return "Content not found."
        case .invalidInput(let message):
            return message
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
