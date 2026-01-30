import Foundation
import Supabase

/// Service responsible for calculating user capacity and managing difficulty adjustments
@MainActor
final class DifficultyService: ObservableObject {
    // MARK: - Configuration Constants

    private static let refreshCooldownSeconds: TimeInterval = 60 // 1 minute debounce
    private static let requestTimeoutSeconds: TimeInterval = 10 // API timeout
    private static let maxRetryAttempts: Int = 3 // Max retry attempts
    static let initialRetryDelay: TimeInterval = 0.5 // Initial retry delay in seconds
    static let retryExponentialBase: Double = 2.0 // Exponential backoff multiplier
    static let nanosecondsPerSecond: UInt64 = 1_000_000_000 // ns/s conversion

    // MARK: - Published Properties

    @Published private(set) var currentCapacity: CapacityScore?
    @Published private(set) var isCalculating: Bool = false
    @Published private(set) var activeOverride: CapacityOverride?

    // MARK: - Private Properties

    private let supabase: SupabaseClient
    private var lastRefreshDate: Date?

    // RACE CONDITION FIX: Task deduplication
    private var refreshTask: Task<CapacityScore, Error>?

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

    deinit {
        // SAFETY: Cancel pending refresh task to prevent memory leak
        refreshTask?.cancel()
    }

    // MARK: - Public Methods

    /// Refresh capacity score from server
    /// - Returns: Updated capacity score
    /// - Throws: DifficultyError if calculation fails
    func refreshCapacity() async throws -> CapacityScore {
        print("[DifficultyService] refreshCapacity called")

        // RACE CONDITION FIX: Atomically check and create task
        // If refresh already in progress, await that task
        if let existingTask = refreshTask {
            print("[DifficultyService] Refresh already in progress, awaiting existing task")
            return try await existingTask.value
        }

        // Create new refresh task immediately to claim the slot
        let task = Task<CapacityScore, Error> { @MainActor in
            // Debounce: prevent rapid successive calls (checked inside task)
            if let last = self.lastRefreshDate,
               Date().timeIntervalSince(last) < Self.refreshCooldownSeconds {
                print("[DifficultyService] Debouncing refresh (last refresh: \(Date().timeIntervalSince(last))s ago)")
                if let cached = self.getCachedCapacity() {
                    return cached
                }
            }

            print("[DifficultyService] Performing new capacity calculation")
            return try await self.performRefresh()
        }

        refreshTask = task
        defer { refreshTask = nil }

        return try await task.value
    }

    /// Internal refresh implementation
    private func performRefresh() async throws -> CapacityScore {
        print("[DifficultyService] performRefresh started")
        isCalculating = true
        defer { isCalculating = false }

        do {
            // Get current user
            guard let userId = supabase.auth.currentUser?.id else {
                print("[DifficultyService] ERROR: No authenticated user")
                throw DifficultyError.calculationFailed("No authenticated user")
            }

            print("[DifficultyService] User authenticated: \(userId)")

            // Prepare request
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone.current
            let localDate = dateFormatter.string(from: Date())

            let timezone = TimeZone.current.identifier

            let request = CalculateCapacityRequest(
                localDate: localDate,
                timezone: timezone
            )

            print("[DifficultyService] Calling calculate-capacity edge function with localDate=\(localDate), timezone=\(timezone)")
            print("[DifficultyService] Current user session exists: \(supabase.auth.currentSession != nil)")
            if let session = supabase.auth.currentSession {
                #if DEBUG
                print("[DifficultyService] Session token (first 20 chars): \(String(session.accessToken.prefix(20)))...")
                #endif
            }

            // Call Edge Function with timeout and retry
            // SECURITY FIX: Retry with session refresh on 401
            let response: CalculateCapacityResponse = try await withRetry(maxAttempts: Self.maxRetryAttempts) { [self] in
                do {
                    return try await withTimeout(seconds: Self.requestTimeoutSeconds) {
                        try await self.supabase.functions
                            .invoke("calculate-capacity", options: FunctionInvokeOptions(body: request))
                    }
                } catch {
                    // Log detailed error information
                    print("[DifficultyService] Edge function error: \(error)")
                    if let functionsError = error as? FunctionsError {
                        switch functionsError {
                        case .httpError(let code, let data):
                            print("[DifficultyService] HTTP \(code) error, response data: \(String(data: data, encoding: .utf8) ?? "unable to decode")")
                        case .relayError:
                            print("[DifficultyService] Relay error")
                        @unknown default:
                            print("[DifficultyService] Unknown FunctionsError type")
                        }
                    }

                    // If we get a 401, try refreshing the session and retrying once
                    let errorMessage = error.localizedDescription.lowercased()
                    if errorMessage.contains("401") || errorMessage.contains("unauthorized") {
                        print("[DifficultyService] Got 401, attempting session refresh...")
                        do {
                            _ = try await self.supabase.auth.refreshSession()
                            print("[DifficultyService] Session refreshed, retrying request...")
                            // Retry once after refresh
                            return try await withTimeout(seconds: Self.requestTimeoutSeconds) {
                                try await self.supabase.functions
                                    .invoke("calculate-capacity", options: FunctionInvokeOptions(body: request))
                            }
                        } catch {
                            print("[DifficultyService] Session refresh failed: \(error.localizedDescription)")
                            throw error // Throw original 401 error
                        }
                    }
                    throw error
                }
            }

            print("[DifficultyService] Edge function returned: score=\(response.score), level=\(response.level)")

            // Convert to CapacityScore
            guard let capacity = response.toCapacityScore(userId: userId) else {
                throw DifficultyError.invalidResponse
            }

            // Update state
            currentCapacity = capacity
            lastRefreshDate = Date()

            // Save to persistent cache
            saveCachedCapacity(capacity)

            // Fetch active override (if any)
            try await fetchActiveOverride()

            return capacity
        } catch let error as DifficultyError {
            print("[DifficultyService] ERROR: DifficultyError - \(error.localizedDescription)")
            // GRACEFUL DEGRADATION: Fall back to cached data if available
            if let cached = getCachedCapacity(), cached.isValid {
                print("⚠️ Using cached capacity due to error: \(error.localizedDescription)")
                return cached
            }
            throw error
        } catch {
            print("[DifficultyService] ERROR: Unexpected error - \(error.localizedDescription)")
            // GRACEFUL DEGRADATION: Fall back to cached data for network errors
            if let cached = getCachedCapacity(), cached.isValid {
                print("⚠️ Using cached capacity due to network error: \(error.localizedDescription)")
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
        guard let userId = supabase.auth.currentUser?.id else {
            throw DifficultyError.overrideFailed("No authenticated user")
        }

        // Calculate expiration (next midnight)
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
            expiresAt: ISO8601DateFormatter().string(from: expiresAt),
            isActive: true
        )

        do {
            // First, deactivate any existing active overrides for this user
            // This prevents unique constraint violation on idx_capacity_overrides_active_user
            try await supabase
                .from("capacity_overrides")
                .update(["is_active": false])
                .eq("user_id", value: userId.uuidString)
                .eq("is_active", value: true)
                .execute()

            // Now insert the new override
            try await supabase
                .from("capacity_overrides")
                .insert(override)
                .execute()

            // Refresh capacity to apply override
            _ = try await refreshCapacity()

            // Update active override state
            try await fetchActiveOverride()
        } catch {
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
            return
        }

        let now = ISO8601DateFormatter().string(from: Date())

        let overrides: [CapacityOverride] = try await supabase
            .from("capacity_overrides")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("is_active", value: true)
            .gt("expires_at", value: now)
            .execute()
            .value

        activeOverride = overrides.first
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
    private func loadCachedCapacity() {
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

            // Only restore if still valid
            if cached.isValid {
                currentCapacity = cached
            } else {
                // Cache expired, clear it
                clearCachedCapacity()
            }
        } catch {
            // Corrupted cache, clear it
            #if DEBUG
            print("Failed to load cached capacity: \(error)")
            #endif
            clearCachedCapacity()
        }
    }

    /// Save capacity score to Keychain for secure persistence
    /// SECURITY: Uses kSecAttrAccessibleWhenUnlockedThisDeviceOnly for encryption
    private func saveCachedCapacity(_ capacity: CapacityScore) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(capacity)
            
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: Self.capacityCacheKey,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            
            // Delete existing item first
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: Self.capacityCacheKey
            ]
            SecItemDelete(deleteQuery as CFDictionary)
            
            // Add new item
            let status = SecItemAdd(query as CFDictionary, nil)
            if status != errSecSuccess {
                #if DEBUG
                print("Failed to save to Keychain: \(status)")
                #endif
            }
        } catch {
            #if DEBUG
            print("Failed to encode capacity: \(error)")
            #endif
        }
    }

    /// Clear cached capacity from Keychain
    private func clearCachedCapacity() {
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
