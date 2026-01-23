import Foundation
import Supabase

/// Service responsible for calculating user capacity and managing difficulty adjustments
@MainActor
final class DifficultyService: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var currentCapacity: CapacityScore?
    @Published private(set) var isCalculating: Bool = false
    @Published private(set) var activeOverride: CapacityOverride?

    // MARK: - Private Properties

    private let supabase: SupabaseClient
    private var lastRefreshDate: Date?
    private let refreshCooldown: TimeInterval = 60 // 1 minute debounce

    // MARK: - Initialization

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Public Methods

    /// Refresh capacity score from server
    /// - Returns: Updated capacity score
    /// - Throws: DifficultyError if calculation fails
    func refreshCapacity() async throws -> CapacityScore {
        // Debounce: prevent rapid successive calls
        if let last = lastRefreshDate, Date().timeIntervalSince(last) < refreshCooldown {
            if let cached = getCachedCapacity() {
                return cached
            }
        }

        isCalculating = true
        defer { isCalculating = false }

        do {
            // Get current user
            guard let userId = try await supabase.auth.session.user.id else {
                throw DifficultyError.calculationFailed("No authenticated user")
            }

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

            // Call Edge Function
            let response: CalculateCapacityResponse = try await supabase.functions
                .invoke("calculate-capacity", options: FunctionInvokeOptions(body: request))
                .value

            // Convert to CapacityScore
            guard let capacity = response.toCapacityScore(userId: userId) else {
                throw DifficultyError.invalidResponse
            }

            // Update state
            currentCapacity = capacity
            lastRefreshDate = Date()

            // Fetch active override (if any)
            try await fetchActiveOverride()

            return capacity
        } catch let error as DifficultyError {
            throw error
        } catch {
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
        guard let userId = try await supabase.auth.session.user.id else {
            throw DifficultyError.overrideFailed("No authenticated user")
        }

        // Calculate expiration (next midnight)
        let expiresAt = getNextMidnight()

        // Create override record
        let override = [
            "user_id": userId.uuidString,
            "override_level": level.rawValue,
            "expires_at": ISO8601DateFormatter().string(from: expiresAt),
            "is_active": true,
        ] as [String: Any]

        do {
            // Upsert override (will replace existing active override due to unique constraint)
            try await supabase
                .from("capacity_overrides")
                .upsert(override)
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
        guard let userId = try await supabase.auth.session.user.id else {
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
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        return calendar.startOfDay(for: tomorrow)
    }
}

// MARK: - Helper Extensions

extension CapacityLevel {
    /// Get the difficulty multiplier for this capacity level
    var difficultyMultiplier: Double {
        switch self {
        case .low:
            return 0.5   // Halve duration (easier)
        case .moderate:
            return 1.0   // Standard duration
        case .high:
            return 1.25  // Extend duration by 25% (harder)
        }
    }
}
