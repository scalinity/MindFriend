import Foundation
import Supabase
import Combine

/// Service for managing streak shields, vacation mode, and shield history
@MainActor
final class StreakShieldService: ObservableObject {
    private let supabase: SupabaseClient

    @Published var shieldStatus: StreakShieldStatus?
    @Published var activeVacation: VacationMode?

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Shield Status

    /// Fetch current shield status using existing RPC
    func getShieldStatus(userId: UUID) async throws -> StreakShieldStatus {
        let result: [StreakShieldStatus] = try await supabase
            .rpc("get_shield_status", params: ["p_user_id": userId.uuidString])
            .execute()
            .value

        guard let status = result.first else {
            throw StreakShieldError.statusNotFound
        }

        self.shieldStatus = status
        return status
    }

    // MARK: - Shield History

    /// Fetch shield event history
    func getShieldHistory(userId: UUID, limit: Int = 50) async throws -> [ShieldEvent] {
        let events: [ShieldEvent] = try await supabase
            .from("streak_shield_events")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return events
    }

    // MARK: - Vacation Mode

    /// Toggle vacation mode (activate or deactivate)
    func toggleVacation(
        action: VacationAction,
        startDate: Date? = nil,
        endDate: Date? = nil,
        reason: String? = nil
    ) async throws -> VacationModeResponse {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        let requestBody = VacationToggleRequest(
            action: action.rawValue,
            startDate: startDate.map { dateFormatter.string(from: $0) },
            endDate: endDate.map { dateFormatter.string(from: $0) },
            reason: reason
        )

        let result: VacationModeResponse = try await supabase.functions.invoke(
            "toggle-vacation",
            options: FunctionInvokeOptions(body: requestBody)
        )

        return result
    }

    /// Fetch active vacation for user
    func getActiveVacation(userId: UUID) async throws -> VacationMode? {
        let result: [VacationMode] = try await supabase
            .from("vacation_mode")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("is_active", value: true)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value

        let vacation = result.first
        self.activeVacation = vacation
        return vacation
    }
}

// MARK: - Internal Types

/// Request for vacation toggle Edge Function
private struct VacationToggleRequest: Codable {
    let action: String
    let startDate: String?
    let endDate: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case action
        case startDate
        case endDate
        case reason
    }
}

// MARK: - Supporting Types

enum VacationAction: String {
    case activate
    case deactivate
}

struct VacationModeResponse: Codable {
    let success: Bool
    let vacation: VacationResponseData?
    let message: String?

    struct VacationResponseData: Codable {
        let id: String
        let isActive: Bool
        let startDate: String
        let endDate: String
        let daysCount: Int
    }
}

enum StreakShieldError: LocalizedError {
    case statusNotFound
    case vacationOverlap
    case invalidDates
    case networkError

    var errorDescription: String? {
        switch self {
        case .statusNotFound:
            return "Could not fetch shield status"
        case .vacationOverlap:
            return "You already have an active vacation"
        case .invalidDates:
            return "Invalid vacation dates"
        case .networkError:
            return "Network error. Please check your connection."
        }
    }
}
