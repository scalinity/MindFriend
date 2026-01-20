import SwiftUI
import Combine

/// ViewModel for the Sleep & Wind-Down feature
@MainActor
final class SleepViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var featuredContent: [SleepContent] = []
    @Published var stories: [SleepContent] = []
    @Published var soundscapes: [SleepContent] = []
    @Published var recentSessions: [SleepSession] = []
    @Published var isLoading = false
    @Published var error: String?

    // Player state
    @Published var playerState = SleepPlayerState()
    @Published var currentSession: SleepSession?

    // MARK: - Dependencies

    private let sleepService: SleepService
    private let audioPlayerService: AudioPlayerService
    private let notificationManager: NotificationManager
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(container: DependencyContainer, appState: AppState) {
        self.sleepService = container.sleepService
        self.audioPlayerService = container.audioPlayerService
        self.notificationManager = NotificationManager.shared
        self.appState = appState

        setupBindings()
    }

    private func setupBindings() {
        // Observe audio player state changes
        audioPlayerService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playbackState in
                self?.playerState.isPlaying = playbackState.isPlaying
                self?.playerState.isBuffering = playbackState.isBuffering
                self?.playerState.currentTime = playbackState.currentTime
                self?.playerState.duration = playbackState.duration
            }
            .store(in: &cancellables)

        // Observe sleep timer state
        audioPlayerService.$sleepTimerRemaining
            .receive(on: DispatchQueue.main)
            .sink { [weak self] remaining in
                self?.playerState.sleepTimerRemaining = remaining > 0 ? remaining : nil
            }
            .store(in: &cancellables)
    }

    // MARK: - Data Loading

    func loadContent() async {
        isLoading = true
        error = nil

        do {
            async let featuredTask = sleepService.fetchFeaturedContent(limit: 8)
            async let storiesTask = sleepService.fetchContent(type: .story)
            async let soundscapesTask = sleepService.fetchContent(type: .soundscape)
            async let sessionsTask = sleepService.fetchRecentSessions(limit: 5)

            let (featured, storiesResult, soundscapesResult, sessions) = try await (
                featuredTask,
                storiesTask,
                soundscapesTask,
                sessionsTask
            )

            self.featuredContent = featured
            self.stories = storiesResult
            self.soundscapes = soundscapesResult
            self.recentSessions = sessions
        } catch {
            self.error = "Failed to load sleep content: \(error.localizedDescription)"
            Log.general.error("SleepViewModel loadContent failed", error: error)
        }

        isLoading = false
    }

    func loadStories(category: SleepCategory? = nil) async {
        do {
            stories = try await sleepService.fetchContent(type: .story, category: category)
        } catch {
            Log.general.error("Failed to load stories", error: error)
        }
    }

    func loadSoundscapes(category: SleepCategory? = nil) async {
        do {
            soundscapes = try await sleepService.fetchContent(type: .soundscape, category: category)
        } catch {
            Log.general.error("Failed to load soundscapes", error: error)
        }
    }

    // MARK: - Playback Control

    func play(_ content: SleepContent) async {
        // Check premium entitlement before playing premium content
        if content.isPremium {
            guard let appState = appState, appState.entitlements.tier == .premium else {
                // Show paywall for non-premium users
                await MainActor.run {
                    self.appState?.showPaywall = true
                }
                Log.general.info("Premium content blocked - user not subscribed: \(content.id)")
                return
            }
        }

        playerState.currentContent = content
        playerState.isBuffering = true

        // Check for resume position
        let resumePosition = try? await sleepService.getResumePosition(for: content.id)

        // Start session
        // Note: sleepTimerDuration.rawValue can be -1 for .endOfTrack, so we only pass positive values
        let timerMinutes: Int? = {
            guard let duration = playerState.sleepTimerDuration else { return nil }
            let rawValue = duration.rawValue
            return rawValue > 0 ? rawValue : nil
        }()

        do {
            let session = try await sleepService.startSession(
                contentId: content.id,
                sleepTimerMinutes: timerMinutes
            )
            currentSession = session
        } catch {
            Log.general.error("Failed to start sleep session", error: error)
        }

        // Convert SleepContent to AudioTrack for the audio player
        let track = AudioTrack(
            id: content.id,
            title: content.title,
            slug: content.id,
            description: content.description,
            authorName: content.narrator,
            imageUrl: content.thumbnailUrl,
            audioUrl: content.audioUrl,
            category: mapSleepCategoryToAudioCategory(content.category),
            duration: TimeInterval(content.durationSeconds),
            playCount: 0,
            createdAt: content.createdAt
        )

        await audioPlayerService.play(track, context: "sleep")

        // Seek to resume position if available
        if let position = resumePosition, position > 0 {
            audioPlayerService.seek(to: TimeInterval(position))
        }

        Analytics.shared.track(.featureUsed, properties: [
            "feature": "sleep",
            "action": "play_content",
            "content_type": content.contentType.rawValue,
            "content_id": content.id,
            "is_premium": content.isPremium
        ])
    }

    func togglePlayPause() {
        audioPlayerService.togglePlayPause()
    }

    func seek(to time: TimeInterval) {
        audioPlayerService.seek(to: time)
    }

    func seekForward(_ seconds: TimeInterval = 15) {
        audioPlayerService.seekForward(seconds)
    }

    func seekBackward(_ seconds: TimeInterval = 15) {
        audioPlayerService.seekBackward(seconds)
    }

    func stop() {
        // End session if active
        if let session = currentSession {
            Task {
                try? await sleepService.endSession(
                    sessionId: session.id,
                    completed: playerState.progress > 0.95,
                    lastPosition: Int(playerState.currentTime),
                    durationListened: Int(playerState.currentTime)
                )
            }
        }

        audioPlayerService.stop()
        playerState = SleepPlayerState()
        currentSession = nil
    }

    // MARK: - Sleep Timer

    func setSleepTimer(_ duration: SleepTimerDuration) {
        playerState.sleepTimerDuration = duration
        audioPlayerService.setSleepTimer(duration)

        Analytics.shared.track(.featureUsed, properties: [
            "feature": "sleep",
            "action": "set_timer",
            "duration_minutes": duration.rawValue
        ])
    }

    func cancelSleepTimer() {
        playerState.sleepTimerDuration = nil
        playerState.sleepTimerRemaining = nil
        audioPlayerService.cancelSleepTimer()
    }

    /// Start gradual fade out (30 seconds for sleep content)
    func startSleepFade() {
        playerState.isFading = true
        audioPlayerService.fadeOutAndStopWithDuration(30.0) { [weak self] in
            self?.playerState.isFading = false
            self?.stop()
        }
    }

    // MARK: - Bedtime Reminder

    func scheduleBedtimeReminder(hour: Int, minute: Int) async throws {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        try await notificationManager.scheduleBedtimeReminder(at: components)
    }

    func cancelBedtimeReminder() {
        notificationManager.cancelBedtimeReminder()
    }

    // MARK: - Helpers

    private func mapSleepCategoryToAudioCategory(_ category: SleepCategory) -> AudioCategory {
        switch category {
        case .nature:
            return .sounds
        case .ambient, .whiteNoise:
            return .sounds
        case .fiction, .nonfiction:
            return .story
        case .asmr:
            return .sounds
        case .binaural:
            return .focus
        case .routine:
            return .sleep
        }
    }
}
