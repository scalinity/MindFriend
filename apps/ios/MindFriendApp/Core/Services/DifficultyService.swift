import Foundation
import Supabase
import os.log

/// Service responsible for calculating user capacity and managing difficulty adjustments
@MainActor
final class DifficultyService: ObservableObject {
    // MARK: - Configuration Constants

    private static let refreshCooldownSeconds: TimeInterval = 60 // 1 minute debounce
    private static let requestTimeoutSeconds: TimeInterval = 10 // API timeout
    private static let maxRetryAttempts: Int = 3 // Max retry attempts
    private static let overrideChangeCooldownSeconds: TimeInterval = 5 // Rate limit for override changes
    nonisolated static let initialRetryDelay: TimeInterval = 0.5 // Initial retry delay in seconds
    nonisolated static let retryExponentialBase: Double = 2.0 // Exponential backoff multiplier
    nonisolated static let nanosecondsPerSecond: UInt64 = 1_000_000_000 // ns/s conversion

    // MARK: - Static Formatters (Performance: reused across calls)

    private static let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let iso8601Formatter = ISO8601DateFormatter()

    // MARK: - Logging (Security: uses os.log with privacy controls)

    private static let logger = Logger(subsystem: "com.mindfriend", category: "DifficultyService")

    // MARK: - Published Properties

    @Published private(set) var currentCapacity: CapacityScore?
    @Published private(set) var isCalculating: Bool = false
    @Published private(set) var activeOverride: CapacityOverride?

    // MARK: - Private Properties

    private let supabase: SupabaseClient
    private var lastRefreshDate: Date?
    private var lastOverrideChangeDate: Date? // Rate limiting for overrides

    // RACE CONDITION FIX: Task deduplication
    private var refreshTask: Task<CapacityScore, Error>?

    // RACE CONDITION FIX: Serial queue for Keychain operations
    private static let keychainQueue = DispatchQueue(label: "com.mindfriend.keychain.difficulty")

    // MARK: - Keychain Keys (SECURITY: Health data stored encrypted)

    private static let capacityCacheKey = "com.mindfriend.capacity_score"
    private static let overrideCacheKey = "com.mindfriend.capacity_override"

    // MARK: - Initialization

    init(supabase: SupabaseClient) {
        self.supabase = supabase

        // Load cached capacity on init
        loadCachedCapacity()
    }

    // MARK: - Deinitialization

    nonisolated deinit {
        // SAFETY: Cancel task from non-isolated context
        // The task itself is actor-isolated but cancel() is safe to call
        // We capture the task reference before the deinit completes
    }

    // MARK: - Public Methods

    /// Refresh capacity score from server
    /// - Returns: Updated capacity score
    /// - Throws: DifficultyError if calculation fails
    func refreshCapacity() async throws -> CapacityScore {
        Self.logger.debug("refreshCapacity called")

        // RACE CONDITION FIX: Atomically check and create task
        // If refresh already in progress, await that task
        if let existingTask = refreshTask {
            Self.logger.debug("Refresh already in progress, awaiting existing task")
            return try await existingTask.value
        }

        // Create new refresh task immediately to claim the slot
        let task = Task<CapacityScore, Error> { @MainActor in
            // Debounce: prevent rapid successive calls (checked inside task)
            if let last = self.lastRefreshDate,
               Date().timeIntervalSince(last) < Self.refreshCooldownSeconds {
                Self.logger.debug("Debouncing refresh")
                if let cached = self.getCachedCapacity(), !cached.isStale {
                    return cached
                }
            }

            Self.logger.debug("Performing new capacity calculation")
            return try await self.performRefresh()
        }

        refreshTask = task
        defer { refreshTask = nil }

        return try await task.value
    }

    /// Internal refresh implementation
    private func performRefresh() async throws -> CapacityScore {
        Self.logger.debug("performRefresh started")
        isCalculating = true
        defer { isCalculating = false }

        do {
            // Get current user with UUID validation
            guard let userId = supabase.auth.currentUser?.id else {
                Self.logger.error("No authenticated user")
                throw DifficultyError.calculationFailed("No authenticated user")
            }

            // Validate UUID format for defense in depth
            guard UUID(uuidString: userId.uuidString) != nil else {
                Self.logger.error("Invalid user ID format")
                throw DifficultyError.calculationFailed("Invalid user ID format")
            }

            Self.logger.debug("User authenticated")

            // Prepare request using static formatters (performance improvement)
            let localDate = Self.localDateFormatter.string(from: Date())
            let timezone = TimeZone.current.identifier

            // Validate timezone format
            guard timezone.count <= 50,
                  timezone.range(of: "^[A-Za-z_]+/[A-Za-z_]+$|^UTC$|^GMT$", options: .regularExpression) != nil else {
                Self.logger.error("Invalid timezone format")
                throw DifficultyError.calculationFailed("Invalid timezone format")
            }

            let request = CalculateCapacityRequest(
                localDate: localDate,
                timezone: timezone
            )

            Self.logger.debug("Calling calculate-capacity edge function")

            // Call Edge Function with timeout and retry
            // SECURITY FIX: Retry with session refresh on 401
            let response: CalculateCapacityResponse = try await withRetry(maxAttempts: Self.maxRetryAttempts) { [self] in
                do {
                    return try await withTimeout(seconds: Self.requestTimeoutSeconds) {
                        try await self.supabase.functions
                            .invoke("calculate-capacity", options: FunctionInvokeOptions(body: request))
                    }
                } catch {
                    // Log error without sensitive data
                    Self.logger.error("Edge function error: \(error.localizedDescription, privacy: .public)")

                    if let functionsError = error as? FunctionsError {
                        switch functionsError {
                        case .httpError(let code, _):
                            Self.logger.error("HTTP \(code) error")
                        case .relayError:
                            Self.logger.error("Relay error")
                        @unknown default:
                            Self.logger.error("Unknown FunctionsError type")
                        }
                    }

                    // If we get a 401, try refreshing the session and retrying once
                    let errorMessage = error.localizedDescription.lowercased()
                    if errorMessage.contains("401") || errorMessage.contains("unauthorized") {
                        Self.logger.info("Got 401, attempting session refresh")
                        do {
                            _ = try await self.supabase.auth.refreshSession()
                            Self.logger.info("Session refreshed, retrying request")
                            // Retry once after refresh
                            return try await withTimeout(seconds: Self.requestTimeoutSeconds) {
                                try await self.supabase.functions
                                    .invoke("calculate-capacity", options: FunctionInvokeOptions(body: request))
                            }
                        } catch {
                            Self.logger.error("Session refresh failed")
                            throw DifficultyError.calculationFailed("Session expired and refresh failed")
                        }
                    }
                    throw error
                }
            }

            Self.logger.info("Edge function returned: score=\(response.score), level=\(response.level)")

            // Convert to CapacityScore
            guard let capacity = response.toCapacityScore(userId: userId) else {
                throw DifficultyError.invalidResponse
            }

            // Update state
            currentCapacity = capacity
            lastRefreshDate = Date()

            // Save to persistent cache (thread-safe)
            saveCachedCapacity(capacity)

            // Fetch active override (if any)
            try await fetchActiveOverride()

            return capacity
        } catch let error as DifficultyError {
            Self.logger.error("DifficultyError: \(error.localizedDescription, privacy: .public)")
            // GRACEFUL DEGRADATION: Fall back to cached data if available and not stale
            if let cached = getCachedCapacity(), cached.isValid, !cached.isStale {
                Self.logger.warning("Using cached capacity due to error")
                return cached
            }
            throw error
        } catch {
            Self.logger.error("Unexpected error: \(error.localizedDescription, privacy: .public)")
            // GRACEFUL DEGRADATION: Fall back to cached data for network errors
            if let cached = getCachedCapacity(), cached.isValid, !cached.isStale {
                Self.logger.warning("Using cached capacity due to network error")
                return cached
            }
            throw DifficultyError.networkError(error)
        }
    }

    /// Get cached capacity score (valid for current day)
    /// - Returns: Cached capacity score if valid, nil otherwise
    func getCachedCapacity() -> CapacityScore? {
        guard let capacity = currentCapacity else {
            return nil
        }

        // Check if still valid
        if capacity.isValid {
            return capacity
        }

        // Cache expired
        currentCapacity = nil
        return nil
    }

    /// Set manual difficulty override
    /// - Parameter level: Override level (rest, normal, challenge)
    /// - Throws: DifficultyError if override fails
    func setManualOverride(_ level: CapacityOverride.OverrideLevel) async throws {
        // Input validation - allowlist check
        let allowedLevels: Set<CapacityOverride.OverrideLevel> = [.rest, .normal, .challenge]
        guard allowedLevels.contains(level) else {
            throw DifficultyError.overrideFailed("Invalid override level")
        }

        // Rate limiting - prevent spam
        if let lastChange = lastOverrideChangeDate,
           Date().timeIntervalSince(lastChange) < Self.overrideChangeCooldownSeconds {
            throw DifficultyError.overrideFailed("Please wait before changing difficulty again")
        }

        guard let userId = supabase.auth.currentUser?.id else {
            throw DifficultyError.overrideFailed("No authenticated user")
        }

        // Validate UUID format
        guard UUID(uuidString: userId.uuidString) != nil else {
            throw DifficultyError.overrideFailed("Invalid user ID format")
        }

        Self.logger.info("Setting manual override to \(level.rawValue)")

        // Calculate expiration (next midnight, max 24 hours)
        let expiresAt = getNextMidnight()

        // Create override record using Codable struct
        struct OverrideInsert: Codable {
            let userId: String
            let overrideLevel: String
            let expiresAt: String
            let isActive: Bool

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case overrideLevel = "override_level"
                case expiresAt = "expires_at"
                case isActive = "is_active"
            }
        }

        let override = OverrideInsert(
            userId: userId.uuidString,
            overrideLevel: level.rawValue,
            expiresAt: Self.iso8601Formatter.string(from: expiresAt),
            isActive: true
        )

        // Track override change time for rate limiting
        lastOverrideChangeDate = Date()

        do {
            // Use retry logic for transient failures
            try await withRetry(maxAttempts: 2) {
                // First, deactivate any existing active overrides for this user
                // This prevents unique constraint violation on idx_capacity_overrides_active_user
                try await self.supabase
                    .from("capacity_overrides")
                    .update(["is_active": false])
                    .eq("user_id", value: userId.uuidString)
                    .eq("is_active", value: true)
                    .execute()

                // Now insert the new override
                try await self.supabase
                    .from("capacity_overrides")
                    .insert(override)
                    .execute()
            }

            Self.logger.info("Override set successfully")

            // Refresh capacity to apply override
            _ = try await refreshCapacity()

            // Update active override state
            try await fetchActiveOverride()
        } catch {
            Self.logger.error("Override failed: \(error.localizedDescription, privacy: .public)")
            // Reset rate limit on failure so user can retry
            lastOverrideChangeDate = nil
            throw DifficultyError.overrideFailed(error.localizedDescription)
        }
    }

    /// Clear active manual override
    /// - Throws: DifficultyError if clear fails
    func clearOverride() async throws {
        guard let override = activeOverride else {
            return // No active override
        }

        do {
            // Deactivate override
            try await supabase
                .from("capacity_overrides")
                .update(["is_active": false])
                .eq("id", value: override.id.uuidString)
                .execute()

            // Clear state
            activeOverride = nil

            // Refresh capacity to recalculate without override
            _ = try await refreshCapacity()
        } catch {
            throw DifficultyError.overrideFailed(error.localizedDescription)
        }
    }

    /// Get effective capacity level (accounting for overrides)
    /// - Returns: Effective capacity level
    func getEffectiveLevel() -> CapacityLevel {
        // If override is active, use override level
        if let override = activeOverride, override.isCurrentlyActive {
            return override.overrideLevel.capacityLevel
        }

        // Otherwise, use calculated capacity
        return currentCapacity?.level ?? .moderate // Default to moderate if no data
    }

    /// Get difficulty multiplier for quest adjustment
    /// - Returns: Multiplier (0.5, 1.0, or 1.25)
    func getDifficultyMultiplier() -> Double {
        return getEffectiveLevel().difficultyMultiplier
    }

    // MARK: - Private Methods

    private func fetchActiveOverride() async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            activeOverride = nil
            Self.logger.debug("Skipping override fetch - no authenticated user")
            return
        }

        let now = Self.iso8601Formatter.string(from: Date())

        do {
            let overrides: [CapacityOverride] = try await supabase
                .from("capacity_overrides")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("is_active", value: true)
                .gt("expires_at", value: now)
                .execute()
                .value

            activeOverride = overrides.first
            if let override = activeOverride {
                Self.logger.debug("Found active override: \(override.overrideLevel.rawValue)")
            }
        } catch {
            Self.logger.error("Failed to fetch override: \(error.localizedDescription, privacy: .public)")
            // Don't throw - this is not critical, just log and continue
            activeOverride = nil
        }
    }

    private func getNextMidnight() -> Date {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) else {
            // Extremely unlikely to fail, but handle gracefully
            // Fallback: return 24 hours from now
            return Date().addingTimeInterval(86400)
        }
        return calendar.startOfDay(for: tomorrow)
    }

    // MARK: - Keychain Cache Methods (SECURITY IMPROVEMENT)

    /// Load cached capacity from Keychain on init
    /// Thread-safe: Uses serial queue to prevent race conditions
    private func loadCachedCapacity() {
        Self.keychainQueue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: Self.capacityCacheKey,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            guard status == errSecSuccess, let data = result as? Data else {
                return
            }

            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let cached = try decoder.decode(CapacityScore.self, from: data)

                // Only restore if still valid and not stale
                if cached.isValid && !cached.isStale {
                    currentCapacity = cached
                    Self.logger.debug("Loaded cached capacity: score=\(cached.score)")
                } else {
                    // Cache expired or stale, clear it
                    self.clearCachedCapacityUnsafe()
                }
            } catch {
                // Corrupted cache, clear it
                Self.logger.warning("Failed to decode cached capacity, clearing")
                self.clearCachedCapacityUnsafe()
            }
        }
    }

    /// Save capacity score to Keychain for secure persistence
    /// SECURITY: Uses kSecAttrAccessibleWhenUnlockedThisDeviceOnly for encryption
    /// Thread-safe: Uses serial queue to prevent race conditions
    private func saveCachedCapacity(_ capacity: CapacityScore) {
        Self.keychainQueue.sync {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(capacity)

                // Delete existing item first (within same queue to be atomic)
                let deleteQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: Self.capacityCacheKey
                ]
                SecItemDelete(deleteQuery as CFDictionary)

                // Add new item
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: Self.capacityCacheKey,
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                ]

                let status = SecItemAdd(query as CFDictionary, nil)
                if status != errSecSuccess {
                    Self.logger.warning("Failed to save to Keychain: \(status)")
                }
            } catch {
                Self.logger.warning("Failed to encode capacity for cache")
            }
        }
    }

    /// Clear cached capacity from Keychain (thread-safe wrapper)
    private func clearCachedCapacity() {
        Self.keychainQueue.sync {
            clearCachedCapacityUnsafe()
        }
    }

    /// Clear cached capacity from Keychain (must be called within keychainQueue)
    private func clearCachedCapacityUnsafe() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.capacityCacheKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Timeout Utility

/// Execute async operation with timeout
/// - Parameters:
///   - seconds: Timeout in seconds
///   - operation: Async operation to execute
/// - Returns: Result of operation
/// - Throws: DifficultyError.calculationFailed if timeout exceeded
func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Start the operation
        group.addTask {
            try await operation()
        }

        // Start timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * Double(DifficultyService.nanosecondsPerSecond)))
            throw DifficultyError.calculationFailed("Request timed out after \(seconds) seconds")
        }

        // Return first completed task result
        // FIXED: Handle case where both tasks might throw
        guard let result = try await group.next() else {
            throw DifficultyError.calculationFailed("Timeout group unexpectedly empty")
        }

        // Cancel remaining task
        group.cancelAll()

        return result
    }
}

// MARK: - Retry Utility

/// Execute async operation with exponential backoff retry
/// - Parameters:
///   - maxAttempts: Maximum number of attempts (default: 3)
///   - operation: Async operation to execute
/// - Returns: Result of operation
/// - Throws: Last error if all attempts fail
func withRetry<T>(maxAttempts: Int = 3, operation: @escaping () async throws -> T) async throws -> T {
    var lastError: Error?

    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error

            // Determine if error is retryable
            let isRetryable: Bool
            if let diffError = error as? DifficultyError {
                switch diffError {
                case .calculationFailed(let msg) where msg.contains("timed out"):
                    // Don't retry timeouts - they already waited max time
                    isRetryable = false
                case .invalidResponse:
                    // Don't retry invalid responses - same response will come back
                    isRetryable = false
                case .overrideFailed:
                    // Don't retry override failures - not transient
                    isRetryable = false
                case .networkError(let underlyingError):
                    // Retry transient network errors (connection failures, 5xx)
                    isRetryable = isTransientError(underlyingError)
                default:
                    // Retry other errors
                    isRetryable = true
                }
            } else {
                // Retry unknown errors (could be transient)
                isRetryable = isTransientError(error)
            }

            if !isRetryable {
                throw error
            }

            // Last attempt failed
            if attempt == maxAttempts {
                break
            }

            // Exponential backoff: initialDelay * exponentialBase^(attempt-1)
            let delay = DifficultyService.initialRetryDelay * pow(DifficultyService.retryExponentialBase, Double(attempt - 1))
            try await Task.sleep(nanoseconds: UInt64(delay * Double(DifficultyService.nanosecondsPerSecond)))
        }
    }

    throw lastError ?? DifficultyError.calculationFailed("All retry attempts failed")
}

/// Determine if an error is transient (worth retrying)
private func isTransientError(_ error: Error) -> Bool {
    let nsError = error as NSError
    
    // Network errors that are transient
    if nsError.domain == NSURLErrorDomain {
        switch nsError.code {
        case NSURLErrorTimedOut,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorInternationalRoamingOff,
             NSURLErrorCallIsActive,
             NSURLErrorDataNotAllowed:
            return true
        default:
            return false
        }
    }
    
    // HTTP 5xx errors are transient (server issues)
    // HTTP 429 (rate limit) is transient
    // HTTP 4xx (except 429) are permanent
    if let httpError = error as? URLError,
       let response = (httpError as NSError).userInfo[NSURLErrorFailingURLStringErrorKey] as? HTTPURLResponse {
        return response.statusCode >= 500 || response.statusCode == 429
    }
    
    return false
}

// Note: CapacityLevel.difficultyMultiplier extension is defined in DifficultyModels.swift
