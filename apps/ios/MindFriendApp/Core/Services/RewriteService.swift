import Foundation
import Supabase

protocol RewriteServiceProtocol {
    func generateRewrites(conversationId: String, messageId: String, messageText: String, rewriteType: RewriteType) async throws -> GenerateRewritesResponse
    func applyRewrite(conversationId: String, messageId: String, rewrittenText: String, rewriteHistoryId: String) async throws -> ApplyRewriteResponse
    func fetchHistory(limit: Int, offset: Int, rewriteType: RewriteType?, appliedOnly: Bool?) async throws -> RewriteHistoryResponse
    func submitFeedback(rewriteHistoryId: String, rating: Int, comment: String?) async throws -> RewriteFeedbackResponse
    func getQuota() async throws -> RewriteQuota
}

@MainActor
final class RewriteService: RewriteServiceProtocol {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    func generateRewrites(conversationId: String, messageId: String, messageText: String, rewriteType: RewriteType) async throws -> GenerateRewritesResponse {
        let request = GenerateRewritesRequest(
            conversationId: conversationId,
            messageId: messageId,
            messageText: messageText,
            rewriteType: rewriteType.rawValue,
            locale: nil
        )

        let response: GenerateRewritesResponse = try await supabase.functions.invoke(
            "generate-rewrites",
            options: .init(body: request)
        )
        return response
    }

    func applyRewrite(conversationId: String, messageId: String, rewrittenText: String, rewriteHistoryId: String) async throws -> ApplyRewriteResponse {
        let request = ApplyRewriteRequest(
            conversationId: conversationId,
            messageId: messageId,
            rewrittenText: rewrittenText,
            rewriteHistoryId: rewriteHistoryId
        )

        let response: ApplyRewriteResponse = try await supabase.functions.invoke(
            "apply-rewrite",
            options: .init(body: request)
        )
        return response
    }

    func fetchHistory(limit: Int, offset: Int, rewriteType: RewriteType?, appliedOnly: Bool?) async throws -> RewriteHistoryResponse {
        var query = supabase
            .from("rewrite_history")
            .select()
        
        if let rewriteType = rewriteType {
            query = query.eq("rewrite_type", value: rewriteType.rawValue)
        }
        
        if let appliedOnly = appliedOnly {
            query = query.eq("was_applied", value: appliedOnly)
        }
        
        let entries: [RewriteHistoryEntry] = try await query
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value
        
        return RewriteHistoryResponse(
            entries: entries,
            total: entries.count,
            hasMore: entries.count == limit,
            stats: RewriteStats(totalRewrites: entries.count, appliedCount: entries.filter { $0.wasApplied }.count, averageRating: nil, favoriteType: nil)
        )
    }

    func submitFeedback(rewriteHistoryId: String, rating: Int, comment: String?) async throws -> RewriteFeedbackResponse {
        let request = RewriteFeedbackRequest(
            rewriteHistoryId: rewriteHistoryId,
            rating: rating,
            comment: comment
        )

        let response: RewriteFeedbackResponse = try await supabase.functions.invoke(
            "rewrite-feedback",
            options: .init(body: request)
        )
        return response
    }

    func getQuota() async throws -> RewriteQuota {
        // Check premium status
        let userId = try await supabase.auth.user().id

        let subscriptions: [SubscriptionResponse] = try await supabase
            .from("subscriptions")
            .select("status")
            .eq("user_id", value: userId)
            .in("status", values: ["active", "trialing"])
            .execute()
            .value

        let isPremium = subscriptions.first?.status == "active" || subscriptions.first?.status == "trialing"

        if isPremium {
            return RewriteQuota(dailyCount: 0, lastResetAt: Date(), isPremium: true)
        }

        // Check quota for free users
        let quotas: [QuotaResponse] = try await supabase
            .from("rewrite_quota")
            .select("daily_count, last_reset_at")
            .eq("user_id", value: userId)
            .execute()
            .value

        guard let quota = quotas.first else {
            return RewriteQuota(dailyCount: 100, lastResetAt: Date(), isPremium: false)
        }

        return RewriteQuota(
            dailyCount: quota.dailyCount ?? 100,
            lastResetAt: quota.lastResetAt ?? Date(),
            isPremium: false
        )
    }
}

// MARK: - Response Types

private struct SubscriptionResponse: Codable {
    let status: String?
}

private struct QuotaResponse: Codable {
    let dailyCount: Int?
    let lastResetAt: Date?

    enum CodingKeys: String, CodingKey {
        case dailyCount = "daily_count"
        case lastResetAt = "last_reset_at"
    }
}
