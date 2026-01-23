import Foundation
import SwiftUI

/// ViewModel for the narrative detail view
/// Handles rating, favoriting, and sharing logic for a single story
@MainActor
class NarrativeDetailViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var story: WeeklyStory
    @Published var isUpdating = false
    @Published var error: String?

    // MARK: - Private Properties

    private let dataService: SupabaseDataService

    // MARK: - Callback

    /// Callback to notify parent view of story updates
    var onStoryUpdated: ((WeeklyStory) -> Void)?

    // MARK: - Initialization

    init(story: WeeklyStory, dataService: SupabaseDataService) {
        self.story = story
        self.dataService = dataService
    }

    // MARK: - Public Methods

    /// Rates the story (thumbs up/down or removes rating)
    /// - Parameter rating: -1 for thumbs down, 1 for thumbs up, nil to remove rating
    func rateStory(rating: Int?) async {
        guard !isUpdating else { return }

        // Optimistic UI update
        let previousRating = story.userRating
        story.userRating = rating

        isUpdating = true
        error = nil

        do {
            try await dataService.updateStoryRating(id: story.id, rating: rating)

            // Notify parent of update
            onStoryUpdated?(story)

        } catch {
            // Revert on error
            story.userRating = previousRating
            self.error = "Failed to save rating. Please try again."
            print("Rating update failed: \(error.localizedDescription)")
        }

        isUpdating = false
    }

    /// Toggles the favorite status of the story
    func toggleFavorite() async {
        guard !isUpdating else { return }

        // Optimistic UI update
        let previousFavorite = story.isFavorite
        story.isFavorite.toggle()

        isUpdating = true
        error = nil

        do {
            try await dataService.toggleStoryFavorite(id: story.id, isFavorite: story.isFavorite)

            // Haptic feedback for favorite action
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            // Notify parent of update
            onStoryUpdated?(story)

        } catch {
            // Revert on error
            story.isFavorite = previousFavorite
            self.error = "Failed to update favorite. Please try again."
            print("Favorite update failed: \(error.localizedDescription)")
        }

        isUpdating = false
    }

    /// Generates share text for the story
    /// - Returns: Formatted string for sharing
    func getShareText() -> String {
        var text = "My Weekly Wellness Story\n"
        text += "\(story.weekRangeFormatted)\n\n"

        for card in story.cards {
            if let headline = card.data.headline {
                text += "\(headline)\n"
            }
            if let message = card.data.message {
                text += "\(message)\n\n"
            }
        }

        text += "\nTracked with MindFriend"

        return text
    }

    /// Determines if the thumbs up button should be highlighted
    var isThumbsUpActive: Bool {
        story.userRating == 1
    }

    /// Determines if the thumbs down button should be highlighted
    var isThumbsDownActive: Bool {
        story.userRating == -1
    }
}
