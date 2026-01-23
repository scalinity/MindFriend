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
            if let fetchedPreferences = try await dataService.fetchNarrativePreferences() {
                preferences = fetchedPreferences
            } else {
                // No preferences exist yet - create default
                let userId = try await dataService.getCurrentUserId()
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
            try await dataService.updateNarrativePreferences(currentPreferences)

            // Show success feedback
            showSuccessToast = true

            // Hide toast after 2 seconds
            Task {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                showSuccessToast = false
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
}
