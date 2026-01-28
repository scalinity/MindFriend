// MindFriend Creator Models
// Data models for content creator platform: profiles, content, earnings, and revenue sharing

import Foundation
import SwiftUI

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

    var color: Color {
        switch self {
        case .draft: return .gray
        case .submitted, .inReview: return .yellow
        case .approved, .published: return .green
        case .rejected: return .red
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

    init(
        id: UUID,
        displayName: String,
        bio: String? = nil,
        profileImageUrl: String? = nil,
        websiteUrl: String? = nil,
        verificationLevel: VerificationLevel = .pending,
        verifiedAt: Date? = nil,
        status: CreatorStatus = .pending,
        followerCount: Int = 0,
        contentCount: Int = 0,
        totalPlays: Int = 0,
        totalMinutes: Int = 0,
        averageRating: Double? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.bio = bio
        self.profileImageUrl = profileImageUrl
        self.websiteUrl = websiteUrl
        self.verificationLevel = verificationLevel
        self.verifiedAt = verifiedAt
        self.status = status
        self.followerCount = followerCount
        self.contentCount = contentCount
        self.totalPlays = totalPlays
        self.totalMinutes = totalMinutes
        self.averageRating = averageRating
    }

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
    let transcript: String?
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

    init(
        id: UUID,
        creatorId: UUID,
        contentType: ContentType,
        format: ContentFormat,
        title: String,
        description: String? = nil,
        durationSeconds: Int? = nil,
        difficulty: ContentDifficulty? = nil,
        mediaUrl: String? = nil,
        coverImageUrl: String? = nil,
        category: String = "",
        tags: [String] = [],
        transcript: String? = nil,
        status: ContentStatus = .draft,
        submittedAt: Date? = nil,
        publishedAt: Date? = nil,
        playCount: Int = 0,
        uniqueListeners: Int = 0,
        averageRating: Double? = nil,
        ratingCount: Int = 0
    ) {
        self.id = id
        self.creatorId = creatorId
        self.contentType = contentType
        self.format = format
        self.title = title
        self.description = description
        self.durationSeconds = durationSeconds
        self.difficulty = difficulty
        self.mediaUrl = mediaUrl
        self.coverImageUrl = coverImageUrl
        self.category = category
        self.tags = tags
        self.transcript = transcript
        self.status = status
        self.submittedAt = submittedAt
        self.publishedAt = publishedAt
        self.playCount = playCount
        self.uniqueListeners = uniqueListeners
        self.averageRating = averageRating
        self.ratingCount = ratingCount
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
        self.transcript = db.transcript
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

// MARK: - Application Types

enum LicenseType: String, Codable, CaseIterable, Identifiable {
    case lmft = "LMFT"
    case lcsw = "LCSW"
    case phd = "PhD"
    case psyd = "PsyD"
    case lpc = "LPC"
    case lmhc = "LMHC"
    case lpcc = "LPCC"
    case mbsr = "MBSR Teacher"
    case mbct = "MBCT Teacher"
    case yoga = "Yoga Teacher (500hr+)"
    case other = "Other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lmft: return "Licensed Marriage & Family Therapist (LMFT)"
        case .lcsw: return "Licensed Clinical Social Worker (LCSW)"
        case .phd: return "PhD in Psychology or Related Field"
        case .psyd: return "PsyD (Doctor of Psychology)"
        case .lpc: return "Licensed Professional Counselor (LPC)"
        case .lmhc: return "Licensed Mental Health Counselor (LMHC)"
        case .lpcc: return "Licensed Professional Clinical Counselor (LPCC)"
        case .mbsr: return "MBSR (Mindfulness-Based Stress Reduction) Teacher"
        case .mbct: return "MBCT (Mindfulness-Based Cognitive Therapy) Teacher"
        case .yoga: return "Yoga Teacher (500hr+)"
        case .other: return "Other"
        }
    }

    var requiresLicenseNumber: Bool {
        switch self {
        case .mbsr, .mbct, .yoga, .other: return false
        default: return true
        }
    }
}

struct Certification: Identifiable, Codable {
    var id: UUID
    var name: String
    var issuer: String
    var yearObtained: String

    init(id: UUID = UUID(), name: String = "", issuer: String = "", yearObtained: String = "") {
        self.id = id
        self.name = name
        self.issuer = issuer
        self.yearObtained = yearObtained
    }
}

enum Specialty: String, Codable, CaseIterable, Identifiable {
    case anxiety
    case depression
    case sleep
    case stress
    case trauma
    case grief
    case relationships
    case adhd = "ADHD"
    case addiction
    case panic
    case ptsd = "PTSD"
    case ocd = "OCD"
    case selfEsteem = "self_esteem"
    case burnout
    case emotionalRegulation = "emotional_regulation"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anxiety: return "Anxiety"
        case .depression: return "Depression"
        case .sleep: return "Sleep"
        case .stress: return "Stress"
        case .trauma: return "Trauma"
        case .grief: return "Grief"
        case .relationships: return "Relationships"
        case .adhd: return "ADHD"
        case .addiction: return "Addiction"
        case .panic: return "Panic"
        case .ptsd: return "PTSD"
        case .ocd: return "OCD"
        case .selfEsteem: return "Self-Esteem"
        case .burnout: return "Burnout"
        case .emotionalRegulation: return "Emotional Regulation"
        }
    }
}

// Note: TherapeuticApproach is defined in TherapistModels.swift
// Reuse the existing enum for consistency across the codebase

enum ContentCategory: String, Codable, CaseIterable, Identifiable {
    case all
    case meditation
    case breathing
    case journaling
    case movement
    case educational

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .meditation: return "Meditation"
        case .breathing: return "Breathing"
        case .journaling: return "Journaling"
        case .movement: return "Movement"
        case .educational: return "Educational"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .meditation: return "brain.head.profile"
        case .breathing: return "wind"
        case .journaling: return "book"
        case .movement: return "figure.walk"
        case .educational: return "lightbulb"
        }
    }
}

enum SubscriptionTier: String, Codable, CaseIterable {
    case monthly
    case annual

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .annual: return "Annual"
        }
    }

    var price: Int {
        switch self {
        case .monthly: return 799  // $7.99
        case .annual: return 6999  // $69.99/year
        }
    }

    var displayPrice: String {
        let dollars = Double(price) / 100.0
        return String(format: "$%.2f", dollars)
    }
}
