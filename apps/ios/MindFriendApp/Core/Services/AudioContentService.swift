import Foundation

@MainActor
final class AudioContentService {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Track Queries

    /// Fetch all active audio tracks
    func fetchAllTracks() async throws -> [AudioTrack] {
        let tracks: [DBAudioTrack] = try await supabase
            .from("audio_tracks")
            .select()
            .eq("is_active", value: true)
            .order("is_featured", ascending: false)
            .order("play_count", ascending: false)
            .execute()
            .value

        return tracks.map { AudioTrack(from: $0) }
    }

    /// Fetch tracks by category
    func fetchTracksByCategory(_ category: AudioCategory) async throws -> [AudioTrack] {
        let tracks: [DBAudioTrack] = try await supabase
            .from("audio_tracks")
            .select()
            .eq("category", value: category.rawValue)
            .eq("is_active", value: true)
            .order("play_count", ascending: false)
            .execute()
            .value

        return tracks.map { AudioTrack(from: $0) }
    }

    /// Fetch featured tracks
    func fetchFeaturedTracks(limit: Int = 8) async throws -> [AudioTrack] {
        let tracks: [DBAudioTrack] = try await supabase
            .from("audio_tracks")
            .select()
            .eq("is_featured", value: true)
            .eq("is_active", value: true)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return tracks.map { AudioTrack(from: $0) }
    }

    /// Search tracks by title or description
    func searchTracks(query: String) async throws -> [AudioTrack] {
        let searchQuery = "%\(query)%"

        let tracks: [DBAudioTrack] = try await supabase
            .from("audio_tracks")
            .select()
            .eq("is_active", value: true)
            .or("title.ilike.\(searchQuery),description.ilike.\(searchQuery)")
            .execute()
            .value

        return tracks.map { AudioTrack(from: $0) }
    }

    /// Fetch track by ID
    func fetchTrack(id: String) async throws -> AudioTrack {
        let tracks: [DBAudioTrack] = try await supabase
            .from("audio_tracks")
            .select()
            .eq("id", value: id)
            .execute()
            .value

        guard let track = tracks.first else {
            throw AudioServiceError.trackNotFound
        }

        return AudioTrack(from: track)
    }

    // MARK: - Recommendations

    /// Get personalized recommendations based on mood, context, and listening history
    func getRecommendations(context: String? = nil, mood: String? = nil, limit: Int = 10) async throws -> [AudioTrack] {
        var body: [String: Any] = ["limit": limit]

        if let context = context {
            body["context"] = context
        }
        if let mood = mood {
            body["mood"] = mood
        }

        let response: [String: Any] = try await supabase.functions
            .invoke("get-audio-recommendations", options: .init(body: body))

        guard let recommendations = response["recommendations"] as? [[String: Any]] else {
            throw AudioServiceError.invalidResponse
        }

        // Convert response to AudioTrack objects
        let tracks = recommendations.compactMap { dict -> AudioTrack? in
            guard let id = dict["id"] as? String,
                  let title = dict["title"] as? String,
                  let slug = dict["slug"] as? String,
                  let audioUrl = dict["audio_url"] as? String,
                  let categoryStr = dict["category"] as? String,
                  let duration = dict["audio_duration_seconds"] as? Int else {
                return nil
            }

            return AudioTrack(
                id: id,
                title: title,
                slug: slug,
                description: dict["description"] as? String,
                category: AudioCategory(rawValue: categoryStr) ?? .meditation,
                subcategory: dict["subcategory"] as? String,
                tags: dict["tags"] as? [String] ?? [],
                audioUrl: URL(string: audioUrl) ?? URL(fileURLWithPath: ""),
                duration: TimeInterval(duration),
                audioFormat: dict["audio_format"] as? String ?? "mp3",
                audioQuality: dict["audio_quality"] as? String ?? "high",
                fileSizeBytes: dict["file_size_bytes"] as? Int,
                previewUrl: nil,
                coverImageUrl: dict["cover_image_url"].flatMap { URL(string: $0 as? String ?? "") },
                backgroundImageUrl: nil,
                primaryColor: nil,
                secondaryColor: nil,
                narrator: nil,
                creatorType: .professional,
                language: "en",
                isLoopable: dict["is_loopable"] as? Bool ?? true,
                hasBackgroundMusic: dict["has_background_music"] as? Bool ?? true,
                energyLevel: nil,
                isPremium: dict["is_premium"] as? Bool ?? false,
                isFeatured: dict["is_featured"] as? Bool ?? false,
                playCount: dict["play_count"] as? Int ?? 0,
                completionCount: dict["completion_count"] as? Int ?? 0,
                averageRating: dict["average_rating"] as? Double,
                ratingCount: dict["rating_count"] as? Int ?? 0
            )
        }

        return tracks
    }

    // MARK: - Playback Sessions

    /// Record playback session start
    func recordPlaybackStart(trackId: String, context: String = "browse") async throws {
        let body: [String: Any] = [
            "trackId": trackId,
            "eventType": "start",
            "positionSeconds": 0,
            "source": context
        ]

        let _: [String: String] = try await supabase.functions
            .invoke("record-playback", options: .init(body: body))
    }

    /// Record playback completion
    func recordPlaybackComplete(trackId: String, positionSeconds: Int, durationListenedSeconds: Int) async throws {
        let body: [String: Any] = [
            "trackId": trackId,
            "eventType": "complete",
            "positionSeconds": positionSeconds,
            "durationListenedSeconds": durationListenedSeconds
        ]

        let _: [String: String] = try await supabase.functions
            .invoke("record-playback", options: .init(body: body))
    }

    /// Get user's recently played tracks
    func fetchRecentlyPlayed(limit: Int = 10) async throws -> [AudioTrack] {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AudioServiceError.notAuthenticated
        }

        let sessions: [DBPlaybackSession] = try await supabase
            .from("playback_sessions")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("started_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let trackIds = Set(sessions.map { $0.trackId })
        let allTracks = try await fetchAllTracks()
        return allTracks.filter { trackIds.contains($0.id) }
    }

    // MARK: - Favorites

    /// Get user's favorite tracks
    func fetchFavoriteTracks() async throws -> [AudioTrack] {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AudioServiceError.notAuthenticated
        }

        struct Favorite: Codable {
            let track_id: String
        }

        let favorites: [Favorite] = try await supabase
            .from("user_audio_favorites")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value

        let favoriteIds = Set(favorites.map { $0.track_id })
        let allTracks = try await fetchAllTracks()
        return allTracks.filter { favoriteIds.contains($0.id) }
    }

    /// Check if track is favorited
    func isFavoritedTrack(_ trackId: String) async throws -> Bool {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AudioServiceError.notAuthenticated
        }

        let favorites: [String] = try await supabase
            .from("user_audio_favorites")
            .select("track_id")
            .eq("user_id", value: userId.uuidString)
            .eq("track_id", value: trackId)
            .execute()
            .value

        return !favorites.isEmpty
    }

    /// Add track to favorites
    func addFavorite(trackId: String) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AudioServiceError.notAuthenticated
        }

        try await supabase
            .from("user_audio_favorites")
            .insert([
                "user_id": userId.uuidString,
                "track_id": trackId
            ])
            .execute()
    }

    /// Remove track from favorites
    func removeFavorite(trackId: String) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AudioServiceError.notAuthenticated
        }

        try await supabase
            .from("user_audio_favorites")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .eq("track_id", value: trackId)
            .execute()
    }

    // MARK: - Ratings

    /// Rate a track
    func rateTrack(trackId: String, rating: Int) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AudioServiceError.notAuthenticated
        }

        guard rating >= 1 && rating <= 5 else {
            throw AudioServiceError.invalidRating
        }

        // Upsert rating (update if exists, insert if not)
        try await supabase
            .from("audio_ratings")
            .upsert([
                "user_id": userId.uuidString,
                "track_id": trackId,
                "rating": rating
            ])
            .execute()
    }

    /// Get user's rating for a track
    func getTrackRating(trackId: String) async throws -> Int? {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AudioServiceError.notAuthenticated
        }

        struct Rating: Codable {
            let rating: Int
        }

        let ratings: [Rating] = try await supabase
            .from("audio_ratings")
            .select("rating")
            .eq("user_id", value: userId.uuidString)
            .eq("track_id", value: trackId)
            .execute()
            .value

        return ratings.first?.rating
    }

    // MARK: - Collections

    /// Fetch all audio collections
    func fetchCollections() async throws -> [AudioCollection] {
        let collections: [AudioCollection] = try await supabase
            .from("audio_collections")
            .select()
            .eq("is_active", value: true)
            .order("created_at", ascending: false)
            .execute()
            .value

        return collections
    }

    /// Fetch collection with tracks
    func fetchCollection(id: String) async throws -> (collection: AudioCollection, tracks: [AudioTrack]) {
        let collections: [AudioCollection] = try await supabase
            .from("audio_collections")
            .select()
            .eq("id", value: id)
            .execute()
            .value

        guard let collection = collections.first else {
            throw AudioServiceError.collectionNotFound
        }

        // Fetch tracks in collection
        struct CollectionTrack: Codable {
            let track_id: String
        }

        let collectionTracks: [CollectionTrack] = try await supabase
            .from("audio_collection_tracks")
            .select("track_id")
            .eq("collection_id", value: id)
            .order("order", ascending: true)
            .execute()
            .value

        let trackIds = collectionTracks.map { $0.track_id }
        let allTracks = try await fetchAllTracks()
        let tracks = allTracks.filter { trackIds.contains($0.id) }

        return (collection, tracks)
    }

    // MARK: - Statistics

    /// Get user's listening statistics
    func getUserStatistics() async throws -> AudioStatistics {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AudioServiceError.notAuthenticated
        }

        struct SessionStats: Codable {
            let count: Int?
            let total_duration: Int?
        }

        let stats: [SessionStats] = try await supabase
            .rpc("get_user_audio_stats", params: ["user_id": userId.uuidString])
            .execute()
            .value

        let stat = stats.first ?? SessionStats(count: 0, total_duration: 0)

        return AudioStatistics(
            totalSessionsCompleted: stat.count ?? 0,
            totalMinutesListened: (stat.total_duration ?? 0) / 60,
            favoriteCount: try await fetchFavoriteTracks().count,
            lastPlayedAt: nil
        )
    }
}

// MARK: - Models

struct AudioCollection: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let coverImageUrl: String?
    let isActive: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case coverImageUrl = "cover_image_url"
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

struct AudioStatistics {
    let totalSessionsCompleted: Int
    let totalMinutesListened: Int
    let favoriteCount: Int
    let lastPlayedAt: Date?
}

// MARK: - Errors

enum AudioServiceError: LocalizedError {
    case trackNotFound
    case collectionNotFound
    case notAuthenticated
    case invalidResponse
    case invalidRating
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .trackNotFound:
            return "Track not found"
        case .collectionNotFound:
            return "Collection not found"
        case .notAuthenticated:
            return "User not authenticated"
        case .invalidResponse:
            return "Invalid server response"
        case .invalidRating:
            return "Rating must be between 1 and 5"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
