//
//  TimeCapsuleModels.swift
//  MindFriendApp
//
//  Wellness Time Capsule feature models
//  Created by dev-pipeline on 2026-01-23
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Time Capsule Models

struct TimeCapsule: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var title: String?
    let contentEncrypted: String
    let contentType: CapsuleContentType
    let theme: CapsuleTheme?
    let createdAt: Date
    let deliverAt: Date
    var deliveredAt: Date?
    var openedAt: Date?
    var status: CapsuleStatus
    var companionLetter: String?
    var companionLetterGeneratedAt: Date?
    let wordCount: Int?
    let mediaCount: Int
    let encryptionKeyId: String
    let metadataSignature: String?
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case contentEncrypted = "content_encrypted"
        case contentType = "content_type"
        case theme
        case createdAt = "created_at"
        case deliverAt = "deliver_at"
        case deliveredAt = "delivered_at"
        case openedAt = "opened_at"
        case status
        case companionLetter = "companion_letter"
        case companionLetterGeneratedAt = "companion_letter_generated_at"
        case wordCount = "word_count"
        case mediaCount = "media_count"
        case encryptionKeyId = "encryption_key_id"
        case metadataSignature = "metadata_signature"
        case deletedAt = "deleted_at"
    }

    var isReady: Bool {
        status == .delivered || (status == .sealed && Date() >= deliverAt)
    }

    var daysUntilDelivery: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: deliverAt).day ?? 0
    }

    var timeAgoCreated: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    var deliveryDateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: deliverAt)
    }
}

enum CapsuleContentType: String, Codable {
    case text
    case audio
    case photo
    case mixed
}

enum CapsuleTheme: String, Codable, CaseIterable {
    case milestone
    case goal
    case gratitude
    case advice
    case encouragement
    case anniversary
    case custom

    var displayName: String {
        switch self {
        case .milestone: return "Celebrate a Milestone"
        case .goal: return "Goals & Dreams"
        case .gratitude: return "Gratitude Capsule"
        case .advice: return "Wisdom for Tomorrow"
        case .encouragement: return "Letter to Future Me"
        case .anniversary: return "Annual Snapshot"
        case .custom: return "Custom Message"
        }
    }

    var iconName: String {
        switch self {
        case .milestone: return "flag.fill"
        case .goal: return "target"
        case .gratitude: return "heart.fill"
        case .advice: return "lightbulb.fill"
        case .encouragement: return "hand.wave.fill"
        case .anniversary: return "calendar"
        case .custom: return "envelope.fill"
        }
    }

    var color: Color {
        switch self {
        case .milestone: return .yellow
        case .goal: return .blue
        case .gratitude: return .pink
        case .advice: return .purple
        case .encouragement: return .green
        case .anniversary: return .orange
        case .custom: return .gray
        }
    }
}

enum CapsuleStatus: String, Codable {
    case sealed
    case delivered
    case opened
}

// MARK: - Capsule Media Models

struct CapsuleMedia: Codable, Identifiable {
    let id: UUID
    let capsuleId: UUID
    let mediaType: CapsuleMediaType
    let storagePath: String
    let fileSizeBytes: Int
    let durationSeconds: Int?
    let transcription: String?
    let thumbnailPath: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case capsuleId = "capsule_id"
        case mediaType = "media_type"
        case storagePath = "storage_path"
        case fileSizeBytes = "file_size_bytes"
        case durationSeconds = "duration_seconds"
        case transcription
        case thumbnailPath = "thumbnail_path"
        case createdAt = "created_at"
    }

    var fileSizeMB: Double {
        Double(fileSizeBytes) / 1_048_576
    }

    var durationFormatted: String? {
        guard let seconds = durationSeconds else { return nil }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

enum CapsuleMediaType: String, Codable {
    case audio
    case photo
    case video
}

// MARK: - Capsule Template Models

struct CapsuleTemplate: Codable, Identifiable {
    let id: UUID
    let theme: CapsuleTheme
    let title: String
    let prompts: [String]
    let suggestedDuration: String
    let isPremium: Bool
    let sortOrder: Int
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case theme
        case title
        case prompts
        case suggestedDuration = "suggested_duration"
        case isPremium = "is_premium"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}

// MARK: - Capsule Snapshot Models

struct CapsuleSnapshot: Codable {
    let id: UUID
    let capsuleId: UUID
    let currentStreak: Int
    let totalQuestsCompleted: Int
    let totalExercises: Int
    let totalMoodsLogged: Int
    let averageMood30d: Double?
    let badgesEarned: Int
    let level: Int
    let totalXP: Int
    let topEmotions: [String]?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case capsuleId = "capsule_id"
        case currentStreak = "current_streak"
        case totalQuestsCompleted = "total_quests_completed"
        case totalExercises = "total_exercises"
        case totalMoodsLogged = "total_moods_logged"
        case averageMood30d = "average_mood_30d"
        case badgesEarned = "badges_earned"
        case level
        case totalXP = "total_xp"
        case topEmotions = "top_emotions"
        case createdAt = "created_at"
    }
}

// MARK: - Journey Comparison

struct JourneyComparison {
    let thenSnapshot: CapsuleSnapshot
    let nowSnapshot: CapsuleSnapshot

    var streakGrowth: Int {
        nowSnapshot.currentStreak - thenSnapshot.currentStreak
    }

    var questsCompleted: Int {
        nowSnapshot.totalQuestsCompleted - thenSnapshot.totalQuestsCompleted
    }

    var exercisesDone: Int {
        nowSnapshot.totalExercises - thenSnapshot.totalExercises
    }

    var levelGrowth: Int {
        nowSnapshot.level - thenSnapshot.level
    }

    var xpGained: Int {
        nowSnapshot.totalXP - thenSnapshot.totalXP
    }

    var badgesEarned: Int {
        nowSnapshot.badgesEarned - thenSnapshot.badgesEarned
    }

    var moodTrend: MoodTrend {
        guard let thenMood = thenSnapshot.averageMood30d,
              let nowMood = nowSnapshot.averageMood30d else {
            return .unchanged
        }
        let diff = nowMood - thenMood
        if diff > 0.5 { return .improved }
        if diff < -0.5 { return .declined }
        return .unchanged
    }

    enum MoodTrend {
        case improved, declined, unchanged

        var displayText: String {
            switch self {
            case .improved: return "Mood Improved ↑"
            case .declined: return "Mood Declined ↓"
            case .unchanged: return "Mood Stable →"
            }
        }

        var color: Color {
            switch self {
            case .improved: return .green
            case .declined: return .red
            case .unchanged: return .gray
            }
        }
    }

    var highlights: [String] {
        var result: [String] = []

        if questsCompleted >= 100 {
            result.append("Completed an incredible \(questsCompleted) quests!")
        } else if questsCompleted >= 30 {
            result.append("Completed \(questsCompleted) quests")
        }

        if streakGrowth >= 30 {
            result.append("Streak grew from \(thenSnapshot.currentStreak) to \(nowSnapshot.currentStreak) days")
        }

        if levelGrowth >= 5 {
            result.append("Leveled up \(levelGrowth) times")
        }

        if badgesEarned >= 5 {
            result.append("Earned \(badgesEarned) new badges")
        }

        switch moodTrend {
        case .improved:
            if let then = thenSnapshot.averageMood30d, let now = nowSnapshot.averageMood30d {
                result.append("Mood improved from \(String(format: "%.1f", then)) to \(String(format: "%.1f", now))")
            }
        case .declined:
            if let then = thenSnapshot.averageMood30d, let now = nowSnapshot.averageMood30d {
                result.append("Mood shifted from \(String(format: "%.1f", then)) to \(String(format: "%.1f", now))")
            }
        case .unchanged:
            break
        }

        return result
    }
}

// MARK: - Creation Flow Models

struct CapsuleCreationData {
    var theme: CapsuleTheme = .encouragement
    var title: String = ""
    var textContent: String = ""
    var audioRecordingURL: URL?
    var photos: [UIImage] = []
    var deliverAt: Date = {
        Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    }()
    var selectedPrompts: [String] = []

    var isValid: Bool {
        !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        audioRecordingURL != nil ||
        !photos.isEmpty
    }

    var contentType: CapsuleContentType {
        let hasText = !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAudio = audioRecordingURL != nil
        let hasPhotos = !photos.isEmpty

        let contentCount = [hasText, hasAudio, hasPhotos].filter { $0 }.count

        if contentCount > 1 {
            return .mixed
        }
        if hasAudio { return .audio }
        if hasPhotos { return .photo }
        return .text
    }

    var wordCount: Int {
        let words = textContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return words.count
    }
}

enum CreationStep: Int, CaseIterable {
    case theme = 0
    case content = 1
    case date = 2
    case seal = 3

    var title: String {
        switch self {
        case .theme: return "Choose Theme"
        case .content: return "Write Message"
        case .date: return "Select Delivery Date"
        case .seal: return "Seal Capsule"
        }
    }

    var description: String {
        switch self {
        case .theme: return "Pick a theme for your time capsule"
        case .content: return "Write a message to your future self"
        case .date: return "When should this be delivered?"
        case .seal: return "Review and seal your capsule"
        }
    }
}

// MARK: - Opened Capsule Response

struct OpenedCapsuleResponse: Codable {
    let capsule: TimeCapsule
    let media: [CapsuleMedia]?
    let companionLetter: String?
    let thenSnapshot: CapsuleSnapshot
    let nowSnapshot: CapsuleSnapshot
    let highlights: [String]

    enum CodingKeys: String, CodingKey {
        case capsule
        case media
        case companionLetter = "companion_letter"
        case thenSnapshot = "then_snapshot"
        case nowSnapshot = "now_snapshot"
        case highlights
    }

    var journeyComparison: JourneyComparison {
        JourneyComparison(thenSnapshot: thenSnapshot, nowSnapshot: nowSnapshot)
    }
}

// MARK: - API Error Models

struct CapsuleQuotaError: Codable {
    let error: String
    let message: String
    let limit: QuotaLimit
    let current: QuotaUsage

    struct QuotaLimit: Codable {
        let count: Int
        let storage: Int
    }

    struct QuotaUsage: Codable {
        let count: Int
        let storage: Int
    }
}

// MARK: - Date Preset Options

enum DeliveryDatePreset: String, CaseIterable {
    case oneWeek = "1 week"
    case oneMonth = "1 month"
    case sixMonths = "6 months"
    case oneYear = "1 year"
    case fiveYears = "5 years"
    case custom = "Custom"

    var displayName: String {
        rawValue.capitalized
    }

    func date(from referenceDate: Date = Date()) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .oneWeek:
            return calendar.date(byAdding: .day, value: 7, to: referenceDate)
        case .oneMonth:
            return calendar.date(byAdding: .month, value: 1, to: referenceDate)
        case .sixMonths:
            return calendar.date(byAdding: .month, value: 6, to: referenceDate)
        case .oneYear:
            return calendar.date(byAdding: .year, value: 1, to: referenceDate)
        case .fiveYears:
            return calendar.date(byAdding: .year, value: 5, to: referenceDate)
        case .custom:
            return nil
        }
    }
}

// MARK: - UIImage Extensions for TimeCapsule

#if canImport(UIKit)
import UIKit

extension UIImage {
    /// Compress image to target size in bytes while maintaining quality
    func compressed(toMaxBytes maxBytes: Int, quality: CGFloat = 0.8) -> Data? {
        var compression: CGFloat = quality
        var imageData = self.jpegData(compressionQuality: compression)

        while let data = imageData, data.count > maxBytes && compression > 0.1 {
            compression -= 0.1
            imageData = self.jpegData(compressionQuality: compression)
        }

        return imageData
    }
}
#endif
