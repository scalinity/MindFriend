import Foundation
import Combine

@MainActor
final class AudioLibraryViewModel: ObservableObject {
    @Published var allTracks: [AudioTrack] = []
    @Published var featuredTracks: [AudioTrack] = []
    @Published var recentlyPlayed: [AudioTrack] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var userCompletionCount: Int?

    private let container: DependencyContainer
    private var cancellables = Set<AnyCancellable>()

    init(container: DependencyContainer) {
        self.container = container
    }

    // MARK: - Data Loading

    func loadContent() async {
        isLoading = true
        error = nil

        do {
            // Load all tracks
            let allTracks: [DBAudioTrack] = try await container.supabase
                .from("audio_tracks")
                .select()
                .eq("is_active", value: true)
                .order("is_featured", ascending: false)
                .order("play_count", ascending: false)
                .execute()
                .value

            self.allTracks = allTracks.map { AudioTrack(from: $0) }

            // Load featured tracks (featured + recently released)
            self.featuredTracks = self.allTracks.filter { $0.isFeatured }.prefix(8).map { $0 }
            if featuredTracks.count < 3 {
                let recent = self.allTracks.filter { !$0.isFeatured }.prefix(3 - featuredTracks.count)
                featuredTracks.append(contentsOf: recent)
            }

            // Load recently played
            guard let userId = container.supabase.auth.currentUser?.id else {
                isLoading = false
                return
            }

            let recentSessions: [DBPlaybackSession] = try await container.supabase
                .from("playback_sessions")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("started_at", ascending: false)
                .limit(10)
                .execute()
                .value

            let recentTrackIds = Set(recentSessions.map { $0.trackId })
            self.recentlyPlayed = self.allTracks.filter { recentTrackIds.contains($0.id) }

            // Load user completion count
            let completions: [DBPlaybackSession] = try await container.supabase
                .from("playback_sessions")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("completed", value: true)
                .execute()
                .value

            self.userCompletionCount = completions.count

            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - Track Actions

    func playTrack(_ track: AudioTrack) async {
        await container.audioPlayerService.play(track, context: "browse")
    }

    func toggleFavorite(_ track: AudioTrack) async {
        await container.audioPlayerService.toggleFavorite(track)
    }

    func isFavorite(_ track: AudioTrack) -> Bool {
        container.audioPlayerService.isFavorite(track)
    }
}
