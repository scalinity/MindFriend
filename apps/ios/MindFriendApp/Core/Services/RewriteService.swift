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

        return try await supabase.functions.invoke(
            "generate-rewrites",
            options: .init(
                body: EncodableValue(request),
                headers: ["Content-Type": "application/json"]
            )
        ).value
    }

    func applyRewrite(conversationId: String, messageId: String, rewrittenText: String, rewriteHistoryId: String) async throws -> ApplyRewriteResponse {
        let request = ApplyRewriteRequest(
            conversationId: conversationId,
            messageId: messageId,
            rewrittenText: rewrittenText,
            rewriteHistoryId: rewriteHistoryId
        )

        return try await supabase.functions.invoke(
            "apply-rewrite",
            options: .init(
                body: EncodableValue(request),
                headers: ["Content-Type": "application/json"]
            )
        ).value
    }

    func fetchHistory(limit: Int, offset: Int, rewriteType: RewriteType?, appliedOnly: Bool?) async throws -> RewriteHistoryResponse {
        var queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]

        if let rewriteType = rewriteType {
            queryItems.append(URLQueryItem(name: "rewriteType", value: rewriteType.rawValue))
        }

        if let appliedOnly = appliedOnly {
            queryItems.append(URLQueryItem(name: "wasApplied", value: String(appliedOnly)))
        }

        let url = supabase.functions.url.absoluteString + "/rewrite-history?" + queryItems.map { $0.name + "=" + ($0.value ?? "") }.joined(separator: "&")

        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(try await supabase.auth.session().accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(RewriteHistoryResponse.self, from: data)
    }

    func submitFeedback(rewriteHistoryId: String, rating: Int, comment: String?) async throws -> RewriteFeedbackResponse {
        let request = RewriteFeedbackRequest(
            rewriteHistoryId: rewriteHistoryId,
            rating: rating,
            comment: comment
        )

        return try await supabase.functions.invoke(
            "rewrite-feedback",
            options: .init(
                body: EncodableValue(request),
                headers: ["Content-Type": "application/json"]
            )
        ).value
    }

    func getQuota() async throws -> RewriteQuota {
        // Check premium status
        let userId = try await supabase.auth.user().id

        let subscriptionResponse: SubscriptionResponse? = try await supabase
            .from("subscriptions")
            .select("status")
            .eq("user_id", userId)
            .in("status", ["active", "trialing"])
            .single()
            .value()

        let isPremium = subscriptionResponse?.status == "active" || subscriptionResponse?.status == "trialing"

        if isPremium {
            return RewriteQuota(dailyCount: 0, lastResetAt: Date(), isPremium: true)
        }

        // Check quota for free users
        let quotaResponse: QuotaResponse? = try await supabase
            .from("rewrite_quota")
            .select("daily_count, last_reset_at")
            .eq("user_id", userId)
            .single()
            .value()

        let lastReset = quotaResponse?.lastResetAt ?? Date(timeIntervalSince1970: 0)
        let today = Calendar.current.startOfDay(for: Date())
        let resetDay = Calendar.current.startOfDay(for: lastReset)

        let dailyCount = resetDay == today ? (quotaResponse?.dailyCount ?? 0) : 0

        return RewriteQuota(dailyCount: dailyCount, lastResetAt: lastReset, isPremium: false)
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
