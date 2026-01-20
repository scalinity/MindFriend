// Community Forums Service
// Per architect plan Phase D: Complete forum API with search, moderation, realtime
// Per decisions.md 2026-01-19: Community Forums Implementation Assumptions

import Foundation
import Supabase

@MainActor
final class ForumService: ObservableObject {
    let supabase: SupabaseClient  // Internal for Realtime subscriptions

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Categories & Boards

    /// Fetch all forum categories with their boards
    func fetchCategoriesWithBoards() async throws -> [(ForumCategory, [ForumBoard])] {
        // Fetch categories
        let categories: [ForumCategory] = try await supabase
            .from("forum_categories")
            .select()
            .order("position", ascending: true)
            .execute()
            .value

        // Fetch all boards
        let boards: [ForumBoard] = try await supabase
            .from("forum_boards")
            .select()
            .order("position", ascending: true)
            .execute()
            .value

        // Group boards by category
        var result: [(ForumCategory, [ForumBoard])] = []
        for category in categories {
            let categoryBoards = boards.filter { $0.categoryId == category.id }
            result.append((category, categoryBoards))
        }

        return result
    }

    /// Fetch single board by ID
    func fetchBoard(id: UUID) async throws -> ForumBoard {
        return try await supabase
            .from("forum_boards")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }

    // MARK: - Threads

    /// Create new thread (auto-generates anonymous name if isAnonymous=true)
    func createThread(
        boardId: UUID,
        title: String,
        content: String,
        isAnonymous: Bool
    ) async throws -> ForumThread {
        guard let userId = supabase.auth.currentUser?.id else {
            throw ForumError.notAuthenticated
        }

        // Insert thread with status='pending' (will be moderated)
        let threadData: [String: AnyEncodable] = [
            "board_id": AnyEncodable(boardId.uuidString),
            "author_id": AnyEncodable(userId.uuidString),
            "title": AnyEncodable(title),
            "content": AnyEncodable(content),
            "is_anonymous": AnyEncodable(isAnonymous),
            "status": AnyEncodable("pending"),
        ]

        let thread: ForumThread = try await supabase
            .from("forum_threads")
            .insert(threadData)
            .select()
            .single()
            .execute()
            .value

        // Trigger moderation (async)
        try await moderateContent(contentType: "thread", contentId: thread.id, title: title, content: content)

        return thread
    }

    /// Fetch threads for a board with pagination and sorting
    func fetchThreads(
        boardId: UUID,
        sortBy: ThreadSortOrder,
        cursor: Date? = nil,
        limit: Int = 20
    ) async throws -> [ForumThread] {
        // Build base filter query
        var baseQuery = supabase
            .from("forum_threads")
            .select()
            .eq("board_id", value: boardId.uuidString)
            .eq("status", value: "approved") // Only show approved threads

        // Apply cursor pagination filter if provided
        if let cursor = cursor {
            baseQuery = baseQuery.lt("created_at", value: cursor.ISO8601Format())
        }

        // Apply sorting and limit
        let threads: [ForumThread]
        switch sortBy {
        case .new:
            threads = try await baseQuery
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
        case .popular:
            threads = try await baseQuery
                .order("reply_count", ascending: false)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
        case .helpful:
            threads = try await baseQuery
                .order("helpful_count", ascending: false)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
        }

        return threads
    }

    /// Fetch single thread by ID
    func fetchThread(id: UUID) async throws -> ForumThread {
        var thread: ForumThread = try await supabase
            .from("forum_threads")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value

        // Fetch user's interaction state
        thread.isHelpfulByMe = try await isMarkedHelpful(threadId: id, replyId: nil)
        thread.isSavedByMe = try await isThreadSaved(id: id)
        thread.isFollowingByMe = try await isThreadFollowing(id: id)

        return thread
    }

    /// Update thread (only within 15 minutes or moderator)
    func updateThread(id: UUID, title: String?, content: String?) async throws -> ForumThread {
        var updates: [String: AnyEncodable] = [:]
        if let title = title {
            updates["title"] = AnyEncodable(title)
        }
        if let content = content {
            updates["content"] = AnyEncodable(content)
        }

        if updates.isEmpty {
            throw ForumError.invalidRequest("No fields to update")
        }

        return try await supabase
            .from("forum_threads")
            .update(updates)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }

    /// Delete thread (own threads or moderator)
    func deleteThread(id: UUID) async throws {
        try await supabase
            .from("forum_threads")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Replies

    /// Create new reply (auto-generates anonymous name if isAnonymous=true)
    func createReply(
        threadId: UUID,
        parentReplyId: UUID?,
        content: String,
        isAnonymous: Bool
    ) async throws -> ForumReply {
        guard let userId = supabase.auth.currentUser?.id else {
            throw ForumError.notAuthenticated
        }

        var replyData: [String: AnyEncodable] = [
            "thread_id": AnyEncodable(threadId.uuidString),
            "author_id": AnyEncodable(userId.uuidString),
            "content": AnyEncodable(content),
            "is_anonymous": AnyEncodable(isAnonymous),
            "status": AnyEncodable("pending"),
        ]

        if let parentReplyId = parentReplyId {
            replyData["parent_reply_id"] = AnyEncodable(parentReplyId.uuidString)
        }

        let reply: ForumReply = try await supabase
            .from("forum_replies")
            .insert(replyData)
            .select()
            .single()
            .execute()
            .value

        // Trigger moderation (async)
        try await moderateContent(contentType: "reply", contentId: reply.id, title: nil, content: content)

        return reply
    }

    /// Fetch replies for a thread with pagination (flattened list)
    func fetchReplies(
        threadId: UUID,
        cursor: Date? = nil,
        limit: Int = 50
    ) async throws -> [ForumReply] {
        var query = supabase
            .from("forum_replies")
            .select()
            .eq("thread_id", value: threadId.uuidString)
            .eq("status", value: "approved")

        if let cursor = cursor {
            query = query.gt("created_at", value: cursor.ISO8601Format())
        }

        let replies: [ForumReply] = try await query
            .order("created_at", ascending: true) // Chronological order
            .limit(limit)
            .execute().value

        // Fetch helpful state for each reply
        var repliesWithState = replies
        for (index, reply) in replies.enumerated() {
            repliesWithState[index].isHelpfulByMe = try await isMarkedHelpful(threadId: nil, replyId: reply.id)
        }

        return repliesWithState
    }

    /// Delete reply (own replies or moderator)
    func deleteReply(id: UUID) async throws {
        try await supabase
            .from("forum_replies")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Helpful (Upvote)

    /// Mark thread or reply as helpful
    func markHelpful(threadId: UUID?, replyId: UUID?) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw ForumError.notAuthenticated
        }

        guard (threadId != nil && replyId == nil) || (threadId == nil && replyId != nil) else {
            throw ForumError.invalidRequest("Must specify exactly one of threadId or replyId")
        }

        var data: [String: AnyEncodable] = [
            "user_id": AnyEncodable(userId.uuidString),
        ]

        if let threadId = threadId {
            data["thread_id"] = AnyEncodable(threadId.uuidString)
        }
        if let replyId = replyId {
            data["reply_id"] = AnyEncodable(replyId.uuidString)
        }

        // Unique constraint will prevent duplicates
        try await supabase
            .from("forum_helpful")
            .insert(data)
            .execute()
    }

    /// Unmark thread or reply as helpful
    func unmarkHelpful(threadId: UUID?, replyId: UUID?) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw ForumError.notAuthenticated
        }

        var query = supabase
            .from("forum_helpful")
            .delete()
            .eq("user_id", value: userId.uuidString)

        if let threadId = threadId {
            query = query.eq("thread_id", value: threadId.uuidString)
        }
        if let replyId = replyId {
            query = query.eq("reply_id", value: replyId.uuidString)
        }

        try await query.execute()
    }

    /// Check if thread/reply is marked helpful by current user
    func isMarkedHelpful(threadId: UUID?, replyId: UUID?) async throws -> Bool {
        guard let userId = supabase.auth.currentUser?.id else {
            return false
        }

        var query = supabase
            .from("forum_helpful")
            .select("id", head: true, count: .exact)
            .eq("user_id", value: userId.uuidString)

        if let threadId = threadId {
            query = query.eq("thread_id", value: threadId.uuidString)
        }
        if let replyId = replyId {
            query = query.eq("reply_id", value: replyId.uuidString)
        }

        let response = try await query.execute()
        return (response.count ?? 0) > 0
    }

    // MARK: - Save/Bookmark

    /// Save thread for later reading
    func saveThread(id: UUID) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw ForumError.notAuthenticated
        }

        let data: [String: AnyEncodable] = [
            "user_id": AnyEncodable(userId.uuidString),
            "thread_id": AnyEncodable(id.uuidString),
        ]

        try await supabase
            .from("forum_saved")
            .insert(data)
            .execute()
    }

    /// Unsave thread
    func unsaveThread(id: UUID) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw ForumError.notAuthenticated
        }

        try await supabase
            .from("forum_saved")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .eq("thread_id", value: id.uuidString)
            .execute()
    }

    /// Check if thread is saved by current user
    func isThreadSaved(id: UUID) async throws -> Bool {
        guard let userId = supabase.auth.currentUser?.id else {
            return false
        }

        let response = try await supabase
            .from("forum_saved")
            .select("id", head: true, count: .exact)
            .eq("user_id", value: userId.uuidString)
            .eq("thread_id", value: id.uuidString)
            .execute()

        return (response.count ?? 0) > 0
    }

    /// Fetch all saved threads for current user
    func fetchSavedThreads(cursor: Date? = nil, limit: Int = 20) async throws -> [ForumThread] {
        guard let userId = supabase.auth.currentUser?.id else {
            throw ForumError.notAuthenticated
        }

        // Query saved threads with join
        let query = """
            forum_saved!inner(user_id, created_at),
            *
        """

        var request = supabase
            .from("forum_threads")
            .select(query)
            .eq("forum_saved.user_id", value: userId.uuidString)

        if let cursor = cursor {
            request = request.lt("forum_saved.created_at", value: cursor.ISO8601Format())
        }

        return try await request
            .order("forum_saved.created_at", ascending: false)
            .limit(limit)
            .execute().value
    }

    // MARK: - Follow

    /// Follow thread for realtime updates
    func followThread(id: UUID) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw ForumError.notAuthenticated
        }

        let data: [String: AnyEncodable] = [
            "user_id": AnyEncodable(userId.uuidString),
            "thread_id": AnyEncodable(id.uuidString),
        ]

        try await supabase
            .from("forum_follows")
            .insert(data)
            .execute()
    }

    /// Unfollow thread
    func unfollowThread(id: UUID) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw ForumError.notAuthenticated
        }

        try await supabase
            .from("forum_follows")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .eq("thread_id", value: id.uuidString)
            .execute()
    }

    /// Check if thread is followed by current user
    func isThreadFollowing(id: UUID) async throws -> Bool {
        guard let userId = supabase.auth.currentUser?.id else {
            return false
        }

        let response = try await supabase
            .from("forum_follows")
            .select("id", head: true, count: .exact)
            .eq("user_id", value: userId.uuidString)
            .eq("thread_id", value: id.uuidString)
            .execute()

        return (response.count ?? 0) > 0
    }

    // MARK: - Reporting

    /// Report thread or reply for violation
    func reportContent(
        threadId: UUID?,
        replyId: UUID?,
        reason: ReportReason,
        details: String?
    ) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw ForumError.notAuthenticated
        }

        guard (threadId != nil && replyId == nil) || (threadId == nil && replyId != nil) else {
            throw ForumError.invalidRequest("Must specify exactly one of threadId or replyId")
        }

        var data: [String: AnyEncodable] = [
            "reporter_id": AnyEncodable(userId.uuidString),
            "reason": AnyEncodable(reason.rawValue),
        ]

        if let threadId = threadId {
            data["thread_id"] = AnyEncodable(threadId.uuidString)
        }
        if let replyId = replyId {
            data["reply_id"] = AnyEncodable(replyId.uuidString)
        }
        if let details = details {
            data["details"] = AnyEncodable(details)
        }

        try await supabase
            .from("forum_reports")
            .insert(data)
            .execute()
    }

    // MARK: - Search

    /// Full-text search across thread titles and content
    func searchThreads(
        query: String,
        boardId: UUID? = nil,
        cursor: Date? = nil,
        limit: Int = 20
    ) async throws -> [ForumThread] {
        guard query.count >= 3 else {
            throw ForumError.invalidRequest("Search query must be at least 3 characters")
        }

        // Use PostgreSQL full-text search with tsv column
        var request = supabase
            .from("forum_threads")
            .select()
            .eq("status", value: "approved")
            .textSearch("tsv", query: query, config: "english")

        if let boardId = boardId {
            request = request.eq("board_id", value: boardId.uuidString)
        }

        if let cursor = cursor {
            request = request.lt("created_at", value: cursor.ISO8601Format())
        }

        return try await request.limit(limit).execute().value
    }

    // MARK: - Moderator Functions

    /// Fetch pending reports (moderators only)
    func fetchPendingReports(cursor: Date? = nil, limit: Int = 50) async throws -> [ForumReport] {
        var query = supabase
            .from("forum_reports")
            .select()
            .eq("status", value: "pending")

        if let cursor = cursor {
            query = query.gt("created_at", value: cursor.ISO8601Format())
        }

        return try await query
            .order("created_at", ascending: true) // Oldest first
            .limit(limit)
            .execute().value
    }

    /// Fetch low confidence threads (0.3-0.8 score, moderators only)
    func fetchLowConfidenceQueue(cursor: Date? = nil, limit: Int = 50) async throws -> [ForumThread] {
        var query = supabase
            .from("forum_threads")
            .select()
            .gte("moderation_confidence", value: 0.3)
            .lte("moderation_confidence", value: 0.8)

        if let cursor = cursor {
            query = query.gt("created_at", value: cursor.ISO8601Format())
        }

        return try await query
            .order("created_at", ascending: true)
            .limit(limit)
            .execute().value
    }

    /// Fetch crisis events (isCrisis=true, moderators only)
    func fetchCrisisEvents(cursor: Date? = nil, limit: Int = 50) async throws -> [ForumThread] {
        var query = supabase
            .from("forum_threads")
            .select()
            .eq("is_crisis", value: true)

        if let cursor = cursor {
            query = query.lt("created_at", value: cursor.ISO8601Format())
        }

        return try await query
            .order("created_at", ascending: false) // Newest first
            .limit(limit)
            .execute().value
    }

    /// Review report and take action (moderators only)
    func reviewReport(id: UUID, action: ReviewAction) async throws {
        // Fetch report to get threadId/replyId
        let report: ForumReport = try await supabase
            .from("forum_reports")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value

        // Update report status
        try await supabase
            .from("forum_reports")
            .update([
                "status": AnyEncodable("reviewed"),
                "reviewed_at": AnyEncodable(Date.now.ISO8601Format())
            ])
            .eq("id", value: id.uuidString)
            .execute()

        // Take action based on moderator decision
        switch action {
        case .approve:
            // Approve the content
            if let threadId = report.threadId {
                try await supabase
                    .from("forum_threads")
                    .update(["status": AnyEncodable("approved")])
                    .eq("id", value: threadId.uuidString)
                    .execute()
            } else if let replyId = report.replyId {
                try await supabase
                    .from("forum_replies")
                    .update(["status": AnyEncodable("approved")])
                    .eq("id", value: replyId.uuidString)
                    .execute()
            }

        case .reject:
            // Reject the content
            if let threadId = report.threadId {
                try await supabase
                    .from("forum_threads")
                    .update(["status": AnyEncodable("rejected")])
                    .eq("id", value: threadId.uuidString)
                    .execute()
            } else if let replyId = report.replyId {
                try await supabase
                    .from("forum_replies")
                    .update(["status": AnyEncodable("rejected")])
                    .eq("id", value: replyId.uuidString)
                    .execute()
            }

        case .banUser:
            // Reject content and ban the author
            let authorId: UUID
            if let threadId = report.threadId {
                let thread: ForumThread = try await supabase
                    .from("forum_threads")
                    .select()
                    .eq("id", value: threadId.uuidString)
                    .single()
                    .execute()
                    .value
                authorId = thread.authorId

                try await supabase
                    .from("forum_threads")
                    .update(["status": AnyEncodable("rejected")])
                    .eq("id", value: threadId.uuidString)
                    .execute()
            } else if let replyId = report.replyId {
                let reply: ForumReply = try await supabase
                    .from("forum_replies")
                    .select()
                    .eq("id", value: replyId.uuidString)
                    .single()
                    .execute()
                    .value
                authorId = reply.authorId

                try await supabase
                    .from("forum_replies")
                    .update(["status": AnyEncodable("rejected")])
                    .eq("id", value: replyId.uuidString)
                    .execute()
            } else {
                return
            }

            // Create ban record
            let userId = try await supabase.auth.session.user.id
            try await supabase
                .from("forum_bans")
                .insert([
                    "user_id": AnyEncodable(authorId.uuidString),
                    "reason": AnyEncodable(report.reason.rawValue),
                    "banned_by": AnyEncodable(userId.uuidString),
                    "banned_until": AnyEncodable(Date.now.addingTimeInterval(30 * 24 * 60 * 60).ISO8601Format()) // 30 days
                ])
                .execute()
        }
    }

    // MARK: - Private Helpers

    /// Call moderate-forum-content Edge Function
    private func moderateContent(
        contentType: String,
        contentId: UUID,
        title: String?,
        content: String
    ) async throws {
        var body: [String: AnyEncodable] = [
            "contentType": AnyEncodable(contentType),
            "contentId": AnyEncodable(contentId.uuidString),
            "content": AnyEncodable(content),
        ]

        if let title = title {
            body["title"] = AnyEncodable(title)
        }

        // Fire and forget - moderation happens asynchronously
        _ = try? await supabase.functions.invoke(
            "moderate-forum-content",
            options: FunctionInvokeOptions(
                body: body
            )
        )
    }
}

// MARK: - Errors

enum ForumError: LocalizedError {
    case notAuthenticated
    case invalidRequest(String)
    case moderationFailed
    case rateLimitExceeded
    case bannedUser

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to perform this action."
        case .invalidRequest(let message):
            return message
        case .moderationFailed:
            return "Content moderation failed. Please try again."
        case .rateLimitExceeded:
            return "You've posted too much content recently. Please wait before posting again."
        case .bannedUser:
            return "Your account is suspended. Contact support for details."
        }
    }
}

// AnyEncodable helper is defined in SupabaseAuthService.swift as a reusable component
