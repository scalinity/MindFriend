import Foundation
import SwiftUI

/// ViewModel for the narrative list view
/// Handles fetching, pagination, and filtering of weekly stories
@MainActor
class NarrativeListViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var stories: [WeeklyStory] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String?
    @Published var showFavoritesOnly = false

    // MARK: - Private Properties

    private let dataService: SupabaseDataService
    private var currentOffset = 0
    private let pageSize = 20
    private var hasMorePages = true

    // MARK: - Initialization

    init(dataService: SupabaseDataService) {
        self.dataService = dataService
    }

    // MARK: - Public Methods

    /// Fetches the first page of stories
    func fetchStories() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil
        currentOffset = 0
        hasMorePages = true

        do {
            let fetchedStories = try await dataService.fetchWeeklyStories(
                limit: pageSize,
                offset: 0,
                favoritesOnly: showFavoritesOnly
            )

            stories = fetchedStories
            hasMorePages = fetchedStories.count == pageSize

        } catch {
            self.error = "Failed to load stories: \(error.localizedDescription)"
            stories = []
        }

        isLoading = false
    }

    /// Loads next page if needed (called when scrolling)
    func loadMoreIfNeeded(currentStory: WeeklyStory) async {
        // Check if we're near the end of the list and can load more
        guard !isLoadingMore,
              !isLoading,
              hasMorePages,
              let index = stories.firstIndex(where: { $0.id == currentStory.id }),
              index >= stories.count - 3 else {
            return
        }

        isLoadingMore = true

        do {
            currentOffset += pageSize

            let fetchedStories = try await dataService.fetchWeeklyStories(
                limit: pageSize,
                offset: currentOffset,
                favoritesOnly: showFavoritesOnly
            )

            stories.append(contentsOf: fetchedStories)
            hasMorePages = fetchedStories.count == pageSize

        } catch {
            // Don't show error for pagination failures, just log
            print("Failed to load more stories: \(error.localizedDescription)")
        }

        isLoadingMore = false
    }

    /// Toggles the favorites filter and refetches
    func toggleFavoritesFilter() {
        showFavoritesOnly.toggle()
        Task {
            await fetchStories()
        }
    }

    /// Refreshes the story list (pull-to-refresh)
    func refresh() async {
        await fetchStories()
    }

    /// Updates a story in the local list after rating/favorite changes
    func updateStory(_ updatedStory: WeeklyStory) {
        if let index = stories.firstIndex(where: { $0.id == updatedStory.id }) {
            stories[index] = updatedStory

            // If favorites filter is on and story is no longer favorited, remove it
            if showFavoritesOnly && !updatedStory.isFavorite {
                stories.remove(at: index)
            }
        }
    }
}
