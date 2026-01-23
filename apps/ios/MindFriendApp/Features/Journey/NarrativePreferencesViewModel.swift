import Foundation
import SwiftUI

/// ViewModel for the narrative preferences view
/// Handles loading and saving user preferences for story generation
@MainActor
class NarrativePreferencesViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var preferences: NarrativePreferences?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: String?
    @Published var showSuccessToast = false

    // MARK: - Private Properties

    private let dataService: SupabaseDataService
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 1.0
    private var toastHideTask: Task<Void, Never>?

    // MARK: - Computed Properties

    /// Current tone setting (defaults to warm if preferences not loaded)
    var currentTone: NarrativePreferences.ToneOption {
        preferences?.preferredTone ?? .warm
    }

    /// Current length setting (defaults to standard if preferences not loaded)
    var currentLength: NarrativePreferences.LengthOption {
        preferences?.preferredLength ?? .standard
    }

    /// Current metrics inclusion setting (defaults to true if preferences not loaded)
    var currentIncludeMetrics: Bool {
        preferences?.includeMetrics ?? true
    }

    /// Current frequency setting (defaults to weekly if preferences not loaded)
    var currentFrequency: NarrativePreferences.FrequencyOption {
        preferences?.generationFrequency ?? .weekly
    }

    // MARK: - Initialization

    init(dataService: SupabaseDataService) {
        self.dataService = dataService
    }

    // MARK: - Public Methods

    /// Loads user preferences from the database
    func loadPreferences() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            let fetchedPreferences = try await retryWithBackoff {
                try await self.dataService.fetchNarrativePreferences()
            }
            
            if let fetchedPreferences = fetchedPreferences {
                preferences = fetchedPreferences
            } else {
                // No preferences exist yet - create default
                let userId = try await retryWithBackoff {
                    try await self.dataService.getCurrentUserId()
                }
                preferences = NarrativePreferences(
                    userId: userId,
                    preferredTone: .warm,
                    preferredLength: .standard,
                    includeMetrics: true,
                    generationFrequency: .weekly,
                    createdAt: Date(),
                    updatedAt: Date()
                )
            }
        } catch {
            self.error = "Failed to load preferences: \(error.localizedDescription)"
            print("Preferences load error: \(error)")
        }

        isLoading = false
    }

    /// Updates a specific preference field
    /// - Parameters:
    ///   - tone: New tone option (optional)
    ///   - length: New length option (optional)
    ///   - includeMetrics: New metrics inclusion setting (optional)
    ///   - frequency: New frequency option (optional)
    func updatePreferences(
        tone: NarrativePreferences.ToneOption? = nil,
        length: NarrativePreferences.LengthOption? = nil,
        includeMetrics: Bool? = nil,
        frequency: NarrativePreferences.FrequencyOption? = nil
    ) async {
        guard var currentPreferences = preferences, !isSaving else { return }

        // Update the specified fields
        if let tone = tone {
            currentPreferences.preferredTone = tone
        }
        if let length = length {
            currentPreferences.preferredLength = length
        }
        if let includeMetrics = includeMetrics {
            currentPreferences.includeMetrics = includeMetrics
        }
        if let frequency = frequency {
            currentPreferences.generationFrequency = frequency
        }

        // Update timestamp
        currentPreferences.updatedAt = Date()

        // Optimistic UI update
        preferences = currentPreferences

        isSaving = true
        error = nil
        showSuccessToast = false

        do {
            try await retryWithBackoff {
                try await self.dataService.updateNarrativePreferences(currentPreferences)
            }

            // Show success feedback
            showSuccessToast = true

            // Cancel previous auto-hide task if still running
            toastHideTask?.cancel()
            
            // Hide toast after 2 seconds
            toastHideTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    if !Task.isCancelled {
                        showSuccessToast = false
                    }
                } catch {
                    // Cancelled - do nothing
                }
            }

        } catch {
            self.error = "Failed to save preferences: \(error.localizedDescription)"
            print("Preferences save error: \(error)")

            // Reload to revert optimistic update
            await loadPreferences()
        }

        isSaving = false
    }

    /// Resets preferences to defaults
    func resetToDefaults() async {
        await updatePreferences(
            tone: .warm,
            length: .standard,
            includeMetrics: true,
            frequency: .weekly
        )
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
