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
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 1.0

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
            try await retryWithBackoff {
                try await self.dataService.updateStoryRating(id: self.story.id, rating: rating)
            }

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
            try await retryWithBackoff {
                try await self.dataService.toggleStoryFavorite(id: self.story.id, isFavorite: self.story.isFavorite)
            }

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
                text += "\(sanitizeText(headline))\n"
            }
            if let message = card.data.message {
                text += "\(sanitizeText(message))\n\n"
            }
        }

        text += "\nTracked with MindFriend"
        
        // Limit total length to prevent excessive sharing
        let maxLength = 1000
        if text.count > maxLength {
            let truncated = String(text.prefix(maxLength - 3))
            text = truncated + "..."
        }

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

    // MARK: - Private Helpers

    /// Sanitizes text for safe sharing
    /// - Parameter text: Raw text from AI-generated content
    /// - Returns: Sanitized text with harmful characters removed
    private func sanitizeText(_ text: String) -> String {
        var sanitized = text
        
        // Remove HTML tags and entities
        sanitized = sanitized.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        sanitized = sanitized.replacingOccurrences(of: "&[a-z]+;", with: "", options: .regularExpression)
        
        // Remove script injection attempts
        sanitized = sanitized.replacingOccurrences(of: "javascript:", with: "", options: .caseInsensitive)
        sanitized = sanitized.replacingOccurrences(of: "data:", with: "", options: .caseInsensitive)
        
        // Remove potentially harmful control characters (keep newlines and tabs)
        let allowedControlChars = CharacterSet.newlines.union(.whitespaces)
        sanitized = sanitized.components(separatedBy: CharacterSet.controlCharacters.subtracting(allowedControlChars)).joined()
        
        // Limit individual field length
        let maxFieldLength = 300
        if sanitized.count > maxFieldLength {
            sanitized = String(sanitized.prefix(maxFieldLength - 3)) + "..."
        }
        
        // Trim whitespace
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return sanitized
    }

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
