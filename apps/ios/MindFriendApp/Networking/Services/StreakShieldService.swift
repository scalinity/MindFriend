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
            .eq("user_id", userId.uuidString)
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

        var requestBody: [String: Any] = ["action": action.rawValue]

        if let startDate = startDate {
            requestBody["startDate"] = dateFormatter.string(from: startDate)
        }

        if let endDate = endDate {
            requestBody["endDate"] = dateFormatter.string(from: endDate)
        }

        if let reason = reason {
            requestBody["reason"] = reason
        }

        let response = try await supabase.functions.invoke(
            "toggle-vacation",
            options: .init(body: requestBody)
        )

        let result = try JSONDecoder().decode(VacationModeResponse.self, from: response.data)
        return result
    }

    /// Fetch active vacation for user
    func getActiveVacation(userId: UUID) async throws -> VacationMode? {
        let result: [VacationMode] = try await supabase
            .from("vacation_mode")
            .select()
            .eq("user_id", userId.uuidString)
            .eq("is_active", true)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value

        let vacation = result.first
        self.activeVacation = vacation
        return vacation
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
