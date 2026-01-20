import Foundation
import OSLog

/// Aggregates context from all providers with caching
@MainActor
final class ContextEngine: ObservableObject {
    // Context providers
    private let calendarProvider: CalendarContextProviding
    private let locationProvider: LocationContextProviding
    private let biometricProvider: BiometricContextProviding
    private let focusModeProvider: FocusModeProviding

    // Cache
    private var cachedContext: UnifiedContext?
    private var cacheTimestamp: Date?
    private let cacheDuration: TimeInterval = 300 // 5 minutes

    // Published state
    @Published private(set) var currentContext: UnifiedContext = .default
    @Published private(set) var shouldSuppressNotifications = false

    init(
        calendarProvider: CalendarContextProviding = CalendarContextProvider(),
        locationProvider: LocationContextProviding = LocationContextProvider(),
        biometricProvider: BiometricContextProviding = BiometricContextProvider(),
        focusModeProvider: FocusModeProviding = FocusModeProvider()
    ) {
        self.calendarProvider = calendarProvider
        self.locationProvider = locationProvider
        self.biometricProvider = biometricProvider
        self.focusModeProvider = focusModeProvider
    }

    // MARK: - Public Interface

    /// Get current unified context (uses cache if valid)
    func getCurrentContext() async -> UnifiedContext {
        // Return cached context if still valid
        if let cached = cachedContext,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheDuration {
            return cached
        }

        // Fetch fresh context
        let context = await fetchFreshContext()

        // Update cache and published state
        cachedContext = context
        cacheTimestamp = Date()
        currentContext = context
        shouldSuppressNotifications = context.shouldSuppressNotification

        return context
    }

    /// Invalidate cache (call on Focus Mode change, app foreground, etc.)
    func invalidateCache() {
        cachedContext = nil
        cacheTimestamp = nil
        Log.notifications.debug("[ContextEngine] Cache invalidated")
    }

    /// Request all necessary permissions
    func requestAllPermissions() async {
        async let calendar = calendarProvider.requestAccess()
        async let location = locationProvider.requestAccess()
        async let biometric = biometricProvider.requestAccess()

        let results = await (calendar, location, biometric)
        Log.notifications.debug("[ContextEngine] Permissions - Calendar: \(results.0), Location: \(results.1), Biometric: \(results.2)")
    }

    // MARK: - Private Methods

    private func fetchFreshContext() async -> UnifiedContext {
        let startTime = Date()

        // Fetch all contexts in parallel
        async let calendarContext = calendarProvider.getContext()
        async let locationContext = locationProvider.getContext()
        async let biometricContext = biometricProvider.getContext()
        async let focusModeContext = focusModeProvider.getContext()

        let (calendar, location, biometric, focusMode) = await (
            calendarContext,
            locationContext,
            biometricContext,
            focusModeContext
        )

        // Calculate suppression
        let (shouldSuppress, reason) = calculateSuppression(
            calendar: calendar,
            biometric: biometric,
            focusMode: focusMode
        )

        let elapsed = Date().timeIntervalSince(startTime) * 1000
        Log.notifications.debug("[ContextEngine] Context fetched in \(elapsed, privacy: .public)ms")

        // Warn if taking too long
        if elapsed > 500 {
            Log.notifications.warning("[ContextEngine] Context fetch exceeded 500ms target")
        }

        return UnifiedContext(
            calendar: calendar,
            location: location,
            biometric: biometric,
            focusMode: focusMode,
            timestamp: Date(),
            shouldSuppressNotification: shouldSuppress,
            suppressionReason: reason
        )
    }

    /// Calculate whether notifications should be suppressed
    private func calculateSuppression(
        calendar: CalendarContext,
        biometric: BiometricContext,
        focusMode: FocusModeContext
    ) -> (Bool, String?) {
        // Sleep Focus always suppresses (highest priority)
        if focusMode.activeMode == .sleep {
            return (true, "Sleep Focus active")
        }

        // DND suppresses
        if focusMode.activeMode == .doNotDisturb {
            return (true, "Do Not Disturb active")
        }

        // Driving suppresses
        if focusMode.activeMode == .driving {
            return (true, "Driving Focus active")
        }

        // In a meeting suppresses
        if calendar.isBusy {
            return (true, "In meeting: \(calendar.currentEventTitle ?? "Unknown")")
        }

        // High stress suppresses optional notifications
        if biometric.isStressed {
            return (true, "High stress detected")
        }

        return (false, nil)
    }
}

// MARK: - Context Observation

extension ContextEngine {
    /// Start observing for context changes that should invalidate cache
    func startObserving() {
        // Observe app becoming active (invalidate cache)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.invalidateCache()
            }
        }

        // Observe significant time change (timezone change, etc.)
        NotificationCenter.default.addObserver(
            forName: UIApplication.significantTimeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.invalidateCache()
            }
        }
    }

    /// Stop observing
    func stopObserving() {
        NotificationCenter.default.removeObserver(self)
    }
}
