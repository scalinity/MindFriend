// MARK: - Ambient Theme Service
// Manages theme state, time-based auto-adjustment, and Supabase persistence

import SwiftUI
import Combine
import OSLog

/// Service that manages ambient themes, background types, and time-based auto-adjustment.
/// Persists preferences to Supabase and provides real-time theme updates to the UI.
@MainActor
final class AmbientThemeService: ObservableObject {
    // MARK: - Published State

    /// The currently active theme (always a resolved theme, never .auto)
    @Published private(set) var currentTheme: AmbientTheme = AmbientTheme.forTimeOfDay()

    /// The stored theme preference (may be .auto)
    @Published private(set) var selectedTheme: AmbientTheme = .auto

    /// The background rendering mode
    @Published private(set) var backgroundType: BackgroundType = .dynamic

    /// Whether auto-adjust is enabled
    @Published private(set) var isAutoAdjustEnabled: Bool = true

    /// Loading state for UI feedback
    @Published private(set) var isLoading: Bool = false

    /// Error message for UI display
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private let dataService: SupabaseDataService
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MindFriend", category: "AmbientTheme")

    // MARK: - Configuration

    /// Interval for checking time-based theme updates (5 minutes)
    private let checkInterval: TimeInterval = 300

    /// Task for time-based monitoring
    private var timeMonitorTask: Task<Void, Never>?

    /// Debounce timer for save operations
    private var saveTask: Task<Void, Error>?
    private let saveDebounceInterval: TimeInterval = 2.0

    /// Track consecutive save failures to surface persistent errors
    private var consecutiveSaveFailures: Int = 0
    private let maxConsecutiveFailuresBeforeAlert: Int = 3

    // MARK: - Initialization

    init(dataService: SupabaseDataService) {
        self.dataService = dataService
        updateResolvedTheme()
    }

    deinit {
        timeMonitorTask?.cancel()
        saveTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Start the service: load preferences and begin time monitoring
    func start() async {
        logger.info("Starting AmbientThemeService")

        // Load preferences from Supabase
        await loadPreferences()

        // Start time-based monitoring
        startTimeBasedMonitoring()
    }

    /// Stop time monitoring (call when app enters background for extended period)
    func stop() {
        logger.info("Stopping AmbientThemeService")
        timeMonitorTask?.cancel()
        timeMonitorTask = nil
    }

    // MARK: - Theme Management

    /// Set the active theme
    /// - Parameter theme: The theme to apply
    func setTheme(_ theme: AmbientTheme) {
        guard theme != selectedTheme else { return }

        logger.info("Setting theme to: \(theme.rawValue)")

        // If selecting a manual theme, disable auto-adjust
        if !theme.isAutoAdjustable && theme != .auto {
            isAutoAdjustEnabled = false
        }

        selectedTheme = theme
        updateResolvedTheme()
        debouncedSave()
    }

    /// Set the background type
    /// - Parameter type: The background rendering mode
    func setBackgroundType(_ type: BackgroundType) {
        guard type != backgroundType else { return }

        logger.info("Setting background type to: \(type.rawValue)")
        backgroundType = type
        debouncedSave()
    }

    /// Toggle auto-adjust mode
    /// - Parameter enabled: Whether to enable auto-adjust
    func setAutoAdjust(_ enabled: Bool) {
        guard enabled != isAutoAdjustEnabled else { return }

        logger.info("Setting auto-adjust to: \(enabled)")
        isAutoAdjustEnabled = enabled

        if enabled {
            // Switch to auto theme when enabling
            selectedTheme = .auto
            updateResolvedTheme()
        }

        debouncedSave()
    }

    // MARK: - Private Methods

    /// Update the resolved theme based on current settings and time
    private func updateResolvedTheme() {
        if isAutoAdjustEnabled || selectedTheme == .auto {
            currentTheme = AmbientTheme.forTimeOfDay()
        } else {
            currentTheme = selectedTheme
        }
    }

    /// Load preferences from Supabase
    private func loadPreferences() async {
        guard dataService.currentUserId != nil else {
            logger.warning("No user ID, using default preferences")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            if let prefs = try await dataService.fetchAmbientPreferences() {
                selectedTheme = prefs.activeTheme
                backgroundType = prefs.backgroundType
                isAutoAdjustEnabled = prefs.autoAdjustEnabled
                updateResolvedTheme()
                logger.info("Loaded ambient preferences: theme=\(prefs.activeTheme.rawValue), bg=\(prefs.backgroundType.rawValue), auto=\(prefs.autoAdjustEnabled)")
            } else {
                logger.info("No existing preferences, using defaults")
            }
        } catch {
            logger.error("Failed to load ambient preferences: \(error.localizedDescription)")
            // Continue with defaults on error
        }
    }

    /// Save preferences to Supabase with debouncing
    private func debouncedSave() {
        saveTask?.cancel()

        saveTask = Task {
            try await Task.sleep(nanoseconds: UInt64(saveDebounceInterval * 1_000_000_000))

            guard !Task.isCancelled else { return }

            await savePreferences()
        }
    }

    /// Save current preferences to Supabase
    private func savePreferences() async {
        guard let userId = dataService.currentUserId else {
            logger.warning("Cannot save preferences: no user ID")
            return
        }

        let prefs = AmbientPreferences(
            userId: userId,
            activeTheme: selectedTheme,
            backgroundType: backgroundType,
            autoAdjustEnabled: isAutoAdjustEnabled,
            createdAt: Date(),
            updatedAt: Date()
        )

        do {
            try await saveWithRetry(prefs)
            consecutiveSaveFailures = 0
            logger.info("Saved ambient preferences successfully")
            errorMessage = nil
        } catch {
            consecutiveSaveFailures += 1
            logger.error("Failed to save ambient preferences (attempt \(consecutiveSaveFailures)): \(error.localizedDescription)")

            // Surface error after multiple consecutive failures
            if consecutiveSaveFailures >= maxConsecutiveFailuresBeforeAlert {
                errorMessage = "Unable to sync theme preferences. Changes may be lost when you close the app."
            }
        }
    }

    /// Save with exponential backoff retry
    private func saveWithRetry(_ prefs: AmbientPreferences, maxAttempts: Int = 3) async throws {
        var attempts = 0

        while attempts < maxAttempts {
            do {
                try await dataService.upsertAmbientPreferences(prefs)
                return
            } catch {
                attempts += 1
                if attempts >= maxAttempts {
                    throw error
                }

                // Exponential backoff: 2^attempts seconds
                let delay = pow(2.0, Double(attempts))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    /// Start time-based theme monitoring
    private func startTimeBasedMonitoring() {
        timeMonitorTask?.cancel()

        // Capture interval by value to avoid issues with weak self
        let interval = checkInterval

        timeMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                // Wait for check interval
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)

                guard !Task.isCancelled else { break }

                await self?.checkAndUpdateTheme()
            }
        }
    }

    /// Check if theme needs to update based on time
    private func checkAndUpdateTheme() {
        guard isAutoAdjustEnabled else { return }

        let newTheme = AmbientTheme.forTimeOfDay()

        if newTheme != currentTheme {
            logger.info("Time-based theme change: \(self.currentTheme.rawValue) → \(newTheme.rawValue)")
            currentTheme = newTheme
        }
    }
}


// MARK: - Preview Support

#if DEBUG
extension AmbientThemeService {
    /// Create a preview instance with mock data
    static var preview: AmbientThemeService {
        let authService = SupabaseAuthService()
        let dataService = SupabaseDataService(authService: authService)
        let service = AmbientThemeService(dataService: dataService)
        service.selectedTheme = .ocean
        service.backgroundType = .animated
        service.isAutoAdjustEnabled = false
        return service
    }
}
#endif
