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

    // MARK: - Internal Properties

    let dataService: SupabaseDataService

    // MARK: - Private Properties

    private var currentOffset = 0
    private let pageSize = 20
    private var hasMorePages = true
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 1.0

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
            let fetchedStories = try await retryWithBackoff {
                try await self.dataService.fetchWeeklyStories(
                    limit: self.pageSize,
                    offset: 0,
                    favoritesOnly: self.showFavoritesOnly
                )
            }

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

            let fetchedStories = try await retryWithBackoff {
                try await self.dataService.fetchWeeklyStories(
                    limit: self.pageSize,
                    offset: self.currentOffset,
                    favoritesOnly: self.showFavoritesOnly
                )
            }

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
            // If favorites filter is on and story is no longer favorited, remove it
            if showFavoritesOnly && !updatedStory.isFavorite {
                stories.remove(at: index)
            } else {
                // Otherwise, update the story in place
                stories[index] = updatedStory
            }
        }
    }

    // MARK: - Private Helpers

    /// Extracts HTTP status code from various error types
    /// - Parameter error: The error to extract status code from
    /// - Returns: HTTP status code if found, nil otherwise
    private func extractHTTPStatusCode(from error: Error) -> Int? {
        let nsError = error as NSError
        
        // Check for Supabase error with status code
        if let statusCode = nsError.userInfo["statusCode"] as? Int {
            return statusCode
        }
        
        // Check for HTTP response in userInfo
        if let response = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? HTTPURLResponse {
            return response.statusCode
        }
        
        // Check alternate keys
        if let response = nsError.userInfo["response"] as? HTTPURLResponse {
            return response.statusCode
        }
        
        return nil
    }

    /// Retries an async operation with exponential backoff
    /// - Parameter operation: The async throwing operation to retry
    /// - Throws: The last error if all retries fail, or CancellationError if cancelled
    private func retryWithBackoff<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            // Check for cancellation before each attempt
            try Task.checkCancellation()
            
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Don't retry on client errors (4xx) or auth errors
                if let urlError = error as? URLError {
                    // Only retry on network/timeout errors
                    let retryableErrors: Set<URLError.Code> = [
                        .timedOut, .cannotFindHost, .cannotConnectToHost,
                        .networkConnectionLost, .dnsLookupFailed, .notConnectedToInternet
                    ]
                    if !retryableErrors.contains(urlError.code) {
                        throw error
                    }
                } else if let statusCode = extractHTTPStatusCode(from: error),
                          (400..<500).contains(statusCode) {
                    // Don't retry 4xx client errors
                    throw error
                }
                
                // If this wasn't the last attempt, wait before retrying
                if attempt < maxRetries - 1 {
                    let delay = baseRetryDelay * pow(2.0, Double(attempt))
                    
                    // Use cancellation-aware sleep
                    do {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    } catch is CancellationError {
                        // Task was cancelled during sleep - exit immediately
                        throw CancellationError()
                    }
                }
            }
        }
        
        // All retries failed, throw the last error
        throw lastError ?? NSError(domain: "RetryError", code: -1)
    }
}
