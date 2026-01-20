// Community Forums Swift Models
// Per architect plan Phase C: Forum entities with Codable support
// Per decisions.md 2026-01-19: Community Forums Implementation Assumptions

import Foundation

// MARK: - ForumCategory

struct ForumCategory: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let description: String?
    let icon: String // SF Symbol name
    let position: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, description, icon, position
        case createdAt = "created_at"
    }
}

// MARK: - ForumBoard

struct ForumBoard: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let categoryId: UUID
    let name: String
    let description: String?
    let position: Int
    let threadCount: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, description, position
        case categoryId = "category_id"
        case threadCount = "thread_count"
        case createdAt = "created_at"
    }
}

// MARK: - ForumThread

struct ForumThread: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let boardId: UUID
    let authorId: UUID
    let isAnonymous: Bool
    let anonymousName: String?
    let title: String
    let content: String
    let status: ThreadStatus
    let moderationConfidence: Decimal?
    let isCrisis: Bool
    let replyCount: Int
    let helpfulCount: Int
    let createdAt: Date
    let updatedAt: Date

    // UI state (not from database)
    var isHelpfulByMe: Bool = false
    var isSavedByMe: Bool = false
    var isFollowingByMe: Bool = false

    /// Display name for author (handles anonymity)
    var authorDisplayName: String {
        if isAnonymous {
            return anonymousName ?? "Anonymous"
        }
        // For non-anonymous, would fetch from profiles table
        // For MVP, just show "User" or fetch separately
        return "User"
    }

    /// Whether thread was edited (updated_at != created_at)
    var isEdited: Bool {
        updatedAt.timeIntervalSince(createdAt) > 1.0 // Allow 1 second tolerance
    }

    enum CodingKeys: String, CodingKey {
        case id, title, content, status
        case boardId = "board_id"
        case authorId = "author_id"
        case isAnonymous = "is_anonymous"
        case anonymousName = "anonymous_name"
        case moderationConfidence = "moderation_confidence"
        case isCrisis = "is_crisis"
        case replyCount = "reply_count"
        case helpfulCount = "helpful_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - ForumReply

struct ForumReply: Codable, Identifiable, Equatable {
    let id: UUID
    let threadId: UUID
    let parentReplyId: UUID?
    let authorId: UUID
    let isAnonymous: Bool
    let anonymousName: String?
    let content: String
    let status: ThreadStatus
    let moderationConfidence: Decimal?
    let isCrisis: Bool
    let helpfulCount: Int
    let depth: Int
    let createdAt: Date
    let updatedAt: Date

    // Nested replies (populated by recursive query or client-side grouping)
    var replies: [ForumReply] = []

    // UI state
    var isHelpfulByMe: Bool = false

    var authorDisplayName: String {
        if isAnonymous {
            return anonymousName ?? "Anonymous"
        }
        return "User"
    }

    var isEdited: Bool {
        updatedAt.timeIntervalSince(createdAt) > 1.0
    }

    enum CodingKeys: String, CodingKey {
        case id, content, status, depth
        case threadId = "thread_id"
        case parentReplyId = "parent_reply_id"
        case authorId = "author_id"
        case isAnonymous = "is_anonymous"
        case anonymousName = "anonymous_name"
        case moderationConfidence = "moderation_confidence"
        case isCrisis = "is_crisis"
        case helpfulCount = "helpful_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - ForumReport

struct ForumReport: Codable, Identifiable, Equatable {
    let id: UUID
    let reporterId: UUID
    let threadId: UUID?
    let replyId: UUID?
    let reason: ReportReason
    let details: String?
    let status: ReportStatus
    let reviewedBy: UUID?
    let reviewedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, reason, details, status
        case reporterId = "reporter_id"
        case threadId = "thread_id"
        case replyId = "reply_id"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case createdAt = "created_at"
    }
}

// MARK: - Enums

enum ThreadStatus: String, Codable, CaseIterable {
    case pending
    case approved
    case rejected
    case flagged

    var displayName: String {
        switch self {
        case .pending: return "Pending Review"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        case .flagged: return "Flagged for Review"
        }
    }

    var color: String {
        switch self {
        case .pending: return "orange"
        case .approved: return "green"
        case .rejected: return "red"
        case .flagged: return "yellow"
        }
    }
}

enum ReportReason: String, Codable, CaseIterable {
    case harassment
    case spam
    case misinformation
    case selfHarm = "self_harm"
    case other

    var displayName: String {
        switch self {
        case .harassment: return "Harassment or Bullying"
        case .spam: return "Spam or Advertising"
        case .misinformation: return "Misinformation"
        case .selfHarm: return "User May Need Help (Crisis)"
        case .other: return "Other Concern"
        }
    }

    var description: String {
        switch self {
        case .harassment:
            return "Attacking, threatening, or bullying other users"
        case .spam:
            return "Promotional content, repeated posts, or off-topic spam"
        case .misinformation:
            return "False information or harmful medical advice"
        case .selfHarm:
            return "User expressing thoughts of self-harm or suicide"
        case .other:
            return "Other concern not listed above"
        }
    }

    var icon: String {
        switch self {
        case .harassment: return "exclamationmark.triangle.fill"
        case .spam: return "trash.fill"
        case .misinformation: return "info.circle.fill"
        case .selfHarm: return "heart.text.square.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

enum ReportStatus: String, Codable, CaseIterable {
    case pending
    case reviewed
    case dismissed

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .reviewed: return "Reviewed"
        case .dismissed: return "Dismissed"
        }
    }
}

enum ReviewAction {
    case approve
    case reject(message: String)
    case banUser(days: Int?) // nil = permanent ban
}

// MARK: - Thread Sort Order

enum ThreadSortOrder: String, CaseIterable {
    case new
    case popular
    case helpful

    var displayName: String {
        switch self {
        case .new: return "New"
        case .popular: return "Popular"
        case .helpful: return "Helpful"
        }
    }

    var icon: String {
        switch self {
        case .new: return "clock.fill"
        case .popular: return "flame.fill"
        case .helpful: return "hand.thumbsup.fill"
        }
    }
}

// MARK: - Helper Extensions

extension ForumThread {
    /// Helper to build nested reply tree from flat list
    static func buildReplyTree(replies: [ForumReply]) -> [ForumReply] {
        var replyDict: [UUID: ForumReply] = [:]
        var rootReplies: [ForumReply] = []

        // First pass: create dictionary
        for reply in replies {
            replyDict[reply.id] = reply
        }

        // Second pass: build tree
        for reply in replies {
            if let parentId = reply.parentReplyId {
                // This is a nested reply
                if var parent = replyDict[parentId] {
                    parent.replies.append(reply)
                    replyDict[parentId] = parent
                }
            } else {
                // This is a root-level reply
                rootReplies.append(reply)
            }
        }

        // Third pass: attach nested replies to roots
        return rootReplies.map { root in
            var mutableRoot = root
            mutableRoot.replies = attachNestedReplies(to: root.id, from: replyDict)
            return mutableRoot
        }
    }

    private static func attachNestedReplies(
        to parentId: UUID,
        from dict: [UUID: ForumReply]
    ) -> [ForumReply] {
        let children = dict.values.filter { $0.parentReplyId == parentId }
        return children.map { child in
            var mutableChild = child
            mutableChild.replies = attachNestedReplies(to: child.id, from: dict)
            return mutableChild
        }
    }
}

extension Date {
    /// Relative time display (e.g., "2h ago", "3d ago")
    var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
