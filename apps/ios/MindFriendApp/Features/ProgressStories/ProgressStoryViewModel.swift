import SwiftUI
import Photos
import OSLog

/// ViewModel for managing weekly story state and actions
@MainActor
@Observable
final class ProgressStoryViewModel {
    // MARK: - Published State

    /// Current weekly story (nil if not loaded)
    var story: WeeklyStory?

    /// Current card index in the story viewer
    var currentIndex: Int = 0

    /// Loading state
    var isLoading: Bool = false

    /// Whether currently exporting a card
    var isExporting: Bool = false

    /// Error state
    var error: StoryViewError?

    /// Whether to show error alert
    var showError: Bool = false

    /// Whether to show circle share sheet
    var showCircleShare: Bool = false

    /// Exported image for sharing
    var exportedImage: UIImage?

    /// Index of card being exported
    var exportingCardIndex: Int?

    // MARK: - Private

    private let dataService: SupabaseDataService
    private let weekStart: String

    private let logger = Log.general

    // MARK: - Initialization

    init(dataService: SupabaseDataService, weekStart: Date = Date()) {
        self.dataService = dataService
        self.weekStart = weekStart.weekStartString
    }

    // MARK: - Retry Logic

    private func retryWithBackoff<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var delay = initialDelay

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch let error as URLError where error.code == .timedOut ||
                                                error.code == .networkConnectionLost {
                // Transient error - retry
                lastError = error
                if attempt < maxAttempts {
                    logger.info("[ProgressStory] Transient error, retrying in \(delay)s (attempt \(attempt)/\(maxAttempts))")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay *= 2.0 // Exponential backoff
                }
            } catch {
                // Permanent error - give up immediately
                throw error
            }
        }

        throw lastError ?? DataError.operationFailed("Failed after \(maxAttempts) attempts")
    }

    // MARK: - Timeout Protection

    private func withTimeout<T>(
        timeoutSeconds: TimeInterval = 30,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Start the actual operation
            group.addTask {
                try await operation()
            }

            // Start a timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw DataError.operationFailed("Operation timed out after \(Int(timeoutSeconds))s")
            }

            // Return result from whichever completes first
            let result = try await group.next()
            group.cancelAll()
            return result!
        }
    }

    // MARK: - Offline Caching

    private let cacheKey = "progress_story_cache"

    private func cacheStory(_ story: WeeklyStory) {
        do {
            let data = try JSONEncoder().encode(story)
            UserDefaults.standard.set(data, forKey: cacheKey)
        } catch {
            logger.error("[ProgressStory] Failed to cache story: \(error)")
        }
    }

    private func getCachedStory() -> WeeklyStory? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(WeeklyStory.self, from: data)
    }

    private func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }

    // MARK: - Public Methods

    /// Load story for the current week
    func loadStory() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let story = try await withTimeout(timeoutSeconds: 30) {
                try await self.retryWithBackoff {
                    try await self.dataService.getWeeklyStory(weekStart: self.weekStart)
                }
            }

            if let story = story {
                self.story = story
                cacheStory(story)
                Analytics.shared.track(.weeklyStoryViewed, properties: [
                    "week_start": weekStart,
                    "card_count": story.cards.count
                ])
            } else {
                // Try to use cached story if available
                if let cached = getCachedStory() {
                    self.story = cached
                    logger.info("[ProgressStory] Using cached story")
                } else {
                    // No cached story, generate new one
                    await generateStory()
                }
            }
        } catch {
            // Network error - try cache
            if let cached = getCachedStory() {
                self.story = cached
                logger.info("[ProgressStory] Network error, using cached story")
            } else {
                logger.error("[ProgressStory] Failed to load story: \(error)")
                self.error = .loadFailed(error.localizedDescription)
                showError = true
            }
        }
    }

    /// Generate a new story for the current week
    func generateStory() async {
        isLoading = true
        defer { isLoading = false }

        do {
            story = try await withTimeout(timeoutSeconds: 30) {
                try await self.retryWithBackoff {
                    try await self.dataService.generateWeeklyStory(weekStart: self.weekStart)
                }
            }
            logger.info("[ProgressStory] Generated story with \(self.story?.cards.count ?? 0) cards")
        } catch {
            logger.error("[ProgressStory] Failed to generate story: \(error)")
            self.error = .generationFailed(error.localizedDescription)
            showError = true
        }
    }

    /// Export a card at the given index as UIImage
    /// - Parameter index: Card index to export
    /// - Returns: Rendered UIImage or nil on failure
    @MainActor
    func exportCard(at index: Int) async -> UIImage? {
        guard let cards = story?.cards,
              index >= 0,
              index < cards.count else {
            logger.warning("[ProgressStory] Invalid card index: \(index)")
            return nil
        }

        let card = cards[index]

        isExporting = true
        exportingCardIndex = index
        defer {
            isExporting = false
            exportingCardIndex = nil
        }

        // Use ImageRenderer to convert SwiftUI view to UIImage
        let renderer = ImageRenderer(
            content: StoryCardView(card: card, privacyMode: false, isExport: true)
                .frame(width: 1080, height: 1920)
        )
        renderer.scale = 1.0 // Use 1x scale for 1080x1920 output

        Analytics.shared.track(.weeklyStoryCardExported, properties: [
            "week_start": weekStart,
            "card_index": index,
            "card_type": card.cardType.rawValue
        ])

        return renderer.uiImage
    }

    /// Save the card at the given index to Photos library
    /// - Parameter index: Card index to save
    func saveToPhotos(index: Int) async {
        guard let image = await exportCard(at: index) else {
            error = .exportFailed("Unable to render card image")
            showError = true
            return
        }

        // Check Photos permission
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            error = .photosPermissionDenied
            showError = true
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            }

            Analytics.shared.track(.weeklyStorySavedToPhotos, properties: [
                "week_start": weekStart,
                "card_index": index
            ])

            // Show success feedback (handled by view)
        } catch {
            logger.error("[ProgressStory] Failed to save to Photos: \(error)")
            self.error = .saveFailed(error.localizedDescription)
            showError = true
        }
    }

    /// Prepare card for sharing (export and store)
    /// - Parameter index: Card index to share
    func prepareShare(index: Int) async {
        guard let image = await exportCard(at: index) else {
            error = .exportFailed("Unable to render card image")
            showError = true
            return
        }

        exportedImage = image

        Analytics.shared.track(.weeklyStoryShared, properties: [
            "week_start": weekStart,
            "card_index": index
        ])
    }

    /// Share a card to a circle
    /// - Parameters:
    ///   - index: Card index to share
    ///   - circleId: Circle to share to
    ///   - caption: Optional caption
    func shareToCircle(index: Int, circleId: UUID, caption: String?) async {
        // Get image from cache or export
        var image = exportedImage
        if image == nil {
            image = await exportCard(at: index)
        }

        guard let validImage = image,
              let imageData = validImage.pngData() else {
            error = .exportFailed("Unable to prepare image for sharing")
            showError = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Upload image to Supabase Storage
            let imageUrl = try await dataService.uploadStoryCardImage(
                imageData: imageData,
                weekStart: weekStart,
                cardIndex: index
            )

            // Create circle post
            try await dataService.shareStoryToCircle(
                imageUrl: imageUrl,
                circleId: circleId,
                caption: caption
            )

            logger.info("[ProgressStory] Shared story card to circle \(circleId)")
            showCircleShare = false
            exportedImage = nil
        } catch {
            logger.error("[ProgressStory] Failed to share to circle: \(error)")
            self.error = .shareFailed(error.localizedDescription)
            showError = true
        }
    }

    /// Move to next card
    func nextCard() {
        guard let story = story, currentIndex < story.cards.count - 1 else { return }
        currentIndex += 1
    }

    /// Move to previous card
    func previousCard() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    /// Reset state for reuse
    func reset() {
        story = nil
        currentIndex = 0
        isLoading = false
        isExporting = false
        error = nil
        showError = false
        exportedImage = nil
    }
}

// MARK: - Error Types

enum StoryViewError: LocalizedError {
    case loadFailed(String)
    case generationFailed(String)
    case exportFailed(String)
    case saveFailed(String)
    case shareFailed(String)
    case photosPermissionDenied

    var errorDescription: String? {
        switch self {
        case .loadFailed(let message):
            return "Unable to load story: \(message)"
        case .generationFailed(let message):
            return "Unable to generate story: \(message)"
        case .exportFailed(let message):
            return "Unable to export card: \(message)"
        case .saveFailed(let message):
            return "Unable to save to Photos: \(message)"
        case .shareFailed(let message):
            return "Unable to share: \(message)"
        case .photosPermissionDenied:
            return "Please grant Photos access in Settings to save story cards."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .photosPermissionDenied:
            return "Go to Settings > Privacy & Security > Photos > MindFriend"
        case .loadFailed, .generationFailed:
            return "Check your internet connection and try again."
        case .exportFailed, .saveFailed, .shareFailed:
            return "Try again in a moment."
        }
    }
}

