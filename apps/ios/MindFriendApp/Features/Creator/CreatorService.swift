// CreatorService.swift
// Service for managing creator profiles, content, earnings, and consumer features

import Foundation
import Supabase

@MainActor
final class CreatorService: ObservableObject {
    @Published var creatorProfile: Creator?
    @Published var myContent: [CreatorContent] = []
    @Published var earnings: [CreatorEarnings] = []
    @Published var isLoading = false
    @Published var error: Error?

    // For consumers
    @Published var followedCreators: [Creator] = []
    @Published var discoverCreators: [Creator] = []

    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Creator Profile Management

    func loadCreatorProfile() async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw CreatorError.notAuthenticated
        }

        isLoading = true
        defer { isLoading = false }

        let creator: DBCreator? = try await supabase
            .from("creators")
            .select()
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
            .value

        if let creator = creator {
            self.creatorProfile = Creator(from: creator)
        }
    }

    func updateCreatorProfile(
        displayName: String,
        bio: String?,
        profileImageUrl: String?,
        websiteUrl: String?,
        socialLinks: [String: String]? = nil
    ) async throws {
        guard let creatorId = creatorProfile?.id else {
            throw CreatorError.notCreator
        }

        try await supabase
            .from("creators")
            .update([
                "display_name": CreatorAnyEncodable(displayName),
                "bio": CreatorAnyEncodable(bio),
                "profile_image_url": CreatorAnyEncodable(profileImageUrl),
                "website_url": CreatorAnyEncodable(websiteUrl),
                "social_links": CreatorAnyEncodable(socialLinks)
            ])
            .eq("id", value: creatorId.uuidString)
            .execute()

        try await loadCreatorProfile()
    }

    // MARK: - Content Management

    func loadMyContent() async throws {
        guard let creatorId = creatorProfile?.id else {
            throw CreatorError.notCreator
        }

        isLoading = true
        defer { isLoading = false }

        let content: [DBCreatorContent] = try await supabase
            .from("creator_content")
            .select()
            .eq("creator_id", value: creatorId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value

        self.myContent = content.map { CreatorContent(from: $0) }
    }

    func createContent(
        title: String,
        contentType: ContentType,
        format: ContentFormat,
        category: String,
        description: String? = nil
    ) async throws -> CreatorContent {
        guard let creatorId = creatorProfile?.id else {
            throw CreatorError.notCreator
        }

        let content: DBCreatorContent = try await supabase
            .from("creator_content")
            .insert([
                "creator_id": CreatorAnyEncodable(creatorId.uuidString),
                "title": CreatorAnyEncodable(title),
                "content_type": CreatorAnyEncodable(contentType.rawValue),
                "format": CreatorAnyEncodable(format.rawValue),
                "category": CreatorAnyEncodable(category),
                "description": CreatorAnyEncodable(description),
                "status": CreatorAnyEncodable("draft")
            ])
            .select()
            .single()
            .execute()
            .value

        let domainContent = CreatorContent(from: content)
        myContent.insert(domainContent, at: 0)
        return domainContent
    }

    func updateContent(
        contentId: UUID,
        title: String? = nil,
        description: String? = nil,
        category: String? = nil,
        difficulty: ContentDifficulty? = nil
    ) async throws {
        guard creatorProfile != nil else {
            throw CreatorError.notCreator
        }

        var updates: [String: CreatorAnyEncodable] = [:]
        if let title = title { updates["title"] = CreatorAnyEncodable(title) }
        if let description = description { updates["description"] = CreatorAnyEncodable(description) }
        if let category = category { updates["category"] = CreatorAnyEncodable(category) }
        if let difficulty = difficulty { updates["difficulty"] = CreatorAnyEncodable(difficulty.rawValue) }

        try await supabase
            .from("creator_content")
            .update(updates)
            .eq("id", value: contentId.uuidString)
            .execute()

        if let index = myContent.firstIndex(where: { $0.id == contentId }) {
            // Reload the content to get updated data
            let updated: DBCreatorContent = try await supabase
                .from("creator_content")
                .select()
                .eq("id", value: contentId.uuidString)
                .single()
                .execute()
                .value

            myContent[index] = CreatorContent(from: updated)
        }
    }

    func uploadContentMedia(_ fileUrl: URL) async throws -> String {
        guard let creatorId = creatorProfile?.id else {
            throw CreatorError.notCreator
        }

        let fileName = "\(UUID().uuidString).\(fileUrl.pathExtension)"
        let path = "creator-content/\(creatorId.uuidString)/\(fileName)"

        let fileData = try Data(contentsOf: fileUrl)

        try await supabase.storage
            .from("content")
            .upload(path: path, file: fileData)

        let publicUrl = try supabase.storage
            .from("content")
            .getPublicURL(path: path)

        return publicUrl.absoluteString
    }

    func submitContentForReview(_ contentId: UUID) async throws {
        _ = try await supabase.functions.invoke(
            "submit-content",
            options: FunctionInvokeOptions(body: ["contentId": contentId.uuidString])
        )

        if let index = myContent.firstIndex(where: { $0.id == contentId }) {
            myContent[index] = try await {
                let updated: DBCreatorContent = try await supabase
                    .from("creator_content")
                    .select()
                    .eq("id", value: contentId.uuidString)
                    .single()
                    .execute()
                    .value
                return CreatorContent(from: updated)
            }()
        }
    }

    func deleteContent(_ contentId: UUID) async throws {
        guard let content = myContent.first(where: { $0.id == contentId }) else {
            throw CreatorError.contentNotFound
        }

        guard content.status == .draft else {
            throw CreatorError.cannotDeletePublished
        }

        try await supabase
            .from("creator_content")
            .delete()
            .eq("id", value: contentId.uuidString)
            .execute()

        myContent.removeAll { $0.id == contentId }
    }

    // MARK: - Earnings & Revenue

    func loadEarnings() async throws {
        guard let creatorId = creatorProfile?.id else {
            throw CreatorError.notCreator
        }

        isLoading = true
        defer { isLoading = false }

        let earnings: [DBCreatorEarnings] = try await supabase
            .from("creator_earnings")
            .select()
            .eq("creator_id", value: creatorId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value

        self.earnings = earnings.map { CreatorEarnings(from: $0) }
    }

    var totalEarnings: Double {
        earnings.reduce(0) { $0 + $1.netEarnings }
    }

    var pendingEarnings: Double {
        earnings
            .filter { $0.payoutStatus == .pending }
            .reduce(0) { $0 + $1.netEarnings }
    }

    // MARK: - Consumer Features: Browse & Discover

    func browseCreators(limit: Int = 20) async throws -> [Creator] {
        let creators: [DBCreator] = try await supabase
            .from("creators")
            .select()
            .eq("status", value: "approved")
            .order("follower_count", ascending: false)
            .limit(limit)
            .execute()
            .value

        return creators.map { Creator(from: $0) }
    }

    func getCreatorContent(creatorId: UUID, limit: Int = 50) async throws -> [CreatorContent] {
        let content: [DBCreatorContent] = try await supabase
            .from("creator_content")
            .select()
            .eq("creator_id", value: creatorId.uuidString)
            .eq("status", value: "published")
            .order("published_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return content.map { CreatorContent(from: $0) }
    }

    // MARK: - Following

    func followCreator(_ creator: Creator) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw CreatorError.notAuthenticated
        }

        try await supabase
            .from("creator_followers")
            .insert([
                "creator_id": creator.id.uuidString,
                "user_id": userId.uuidString
            ])
            .execute()

        if !followedCreators.contains(where: { $0.id == creator.id }) {
            followedCreators.append(creator)
        }
    }

    func unfollowCreator(_ creator: Creator) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw CreatorError.notAuthenticated
        }

        try await supabase
            .from("creator_followers")
            .delete()
            .eq("creator_id", value: creator.id.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()

        followedCreators.removeAll { $0.id == creator.id }
    }

    func loadFollowedCreators() async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw CreatorError.notAuthenticated
        }

        // Define intermediate structure for nested query result
        struct FollowRelation: Decodable {
            let creator: DBCreator

            enum CodingKeys: String, CodingKey {
                case creator = "creators"
            }
        }

        let relations: [FollowRelation] = try await supabase
            .from("creator_followers")
            .select("creators!inner(*)")
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value

        self.followedCreators = relations.map { Creator(from: $0.creator) }
    }

    func isFollowing(_ creator: Creator) -> Bool {
        followedCreators.contains { $0.id == creator.id }
    }

    // MARK: - Content Rating

    func rateContent(contentId: UUID, rating: Int, review: String?) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw CreatorError.notAuthenticated
        }

        guard rating >= 1 && rating <= 5 else {
            throw CreatorError.invalidInput("Rating must be between 1 and 5")
        }

        try await supabase
            .from("content_ratings")
            .upsert([
                "content_id": CreatorAnyEncodable(contentId.uuidString),
                "user_id": CreatorAnyEncodable(userId.uuidString),
                "rating": CreatorAnyEncodable(rating),
                "review": CreatorAnyEncodable(review)
            ], onConflict: "content_id,user_id")
            .execute()
    }

    // MARK: - Record Engagement

    func recordEngagement(
        contentId: UUID,
        sessionId: UUID,
        durationSeconds: Int,
        completionPercentage: Double,
        isUserPremium: Bool
    ) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw CreatorError.notAuthenticated
        }

        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let month = String(today.prefix(7))

        try await supabase
            .from("content_engagement")
            .insert([
                "content_id": CreatorAnyEncodable(contentId.uuidString),
                "user_id": CreatorAnyEncodable(userId.uuidString),
                "session_id": CreatorAnyEncodable(sessionId.uuidString),
                "started_at": CreatorAnyEncodable(ISO8601DateFormatter().string(from: Date())),
                "duration_seconds": CreatorAnyEncodable(durationSeconds),
                "completion_percentage": CreatorAnyEncodable(completionPercentage),
                "user_is_premium": CreatorAnyEncodable(isUserPremium),
                "engagement_date": CreatorAnyEncodable(String(today)),
                "engagement_month": CreatorAnyEncodable(month)
            ])
            .execute()
    }
}

// MARK: - Helper
private struct CreatorAnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ wrapped: T) { _encode = wrapped.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
