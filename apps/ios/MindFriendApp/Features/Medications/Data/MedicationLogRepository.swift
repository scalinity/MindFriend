import Foundation
import Supabase

protocol MedicationLogRepository {
    func fetchLogs(medicationId: UUID, from: Date, to: Date) async throws -> [MedicationLog]
    func fetchAllLogs(from: Date, to: Date) async throws -> [MedicationLog]
    func fetchTodayLogs() async throws -> [MedicationLog]
    func logDose(medicationId: UUID, scheduledAt: Date, status: MedicationStatus, notes: String?) async throws -> MedicationLog
    func skipDose(medicationId: UUID, scheduledAt: Date, reason: String?) async throws -> MedicationLog
    func updateSupplyCount(medicationId: UUID) async throws -> Int?
}

final class SupabaseMedicationLogRepository: MedicationLogRepository {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    func fetchLogs(medicationId: UUID, from: Date, to: Date) async throws -> [MedicationLog] {
        let userId = try await supabase.auth.session.user.id

        return try await supabase
            .from("medication_logs")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("medication_id", value: medicationId.uuidString)
            .gte("scheduled_at", value: ISO8601DateFormatter().string(from: from))
            .lte("scheduled_at", value: ISO8601DateFormatter().string(from: to))
            .order("scheduled_at", ascending: false)
            .execute()
            .value
    }

    func fetchAllLogs(from: Date, to: Date) async throws -> [MedicationLog] {
        let userId = try await supabase.auth.session.user.id

        return try await supabase
            .from("medication_logs")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("scheduled_at", value: ISO8601DateFormatter().string(from: from))
            .lte("scheduled_at", value: ISO8601DateFormatter().string(from: to))
            .order("scheduled_at", ascending: false)
            .execute()
            .value
    }

    func fetchTodayLogs() async throws -> [MedicationLog] {
        let userId = try await supabase.auth.session.user.id
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        return try await supabase
            .from("medication_logs")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("scheduled_at", value: ISO8601DateFormatter().string(from: startOfDay))
            .lt("scheduled_at", value: ISO8601DateFormatter().string(from: endOfDay))
            .order("scheduled_at", ascending: true)
            .execute()
            .value
    }

    func logDose(medicationId: UUID, scheduledAt: Date, status: MedicationStatus, notes: String?) async throws -> MedicationLog {
        let userId = try await supabase.auth.session.user.id

        struct MedicationLogInsert: Codable {
            let user_id: String
            let medication_id: String
            let scheduled_at: String
            let status: String
            let logged_at: String
            let notes: String?

            enum CodingKeys: String, CodingKey {
                case user_id
                case medication_id
                case scheduled_at
                case status
                case logged_at
                case notes
            }
        }

        let payload = MedicationLogInsert(
            user_id: userId.uuidString,
            medication_id: medicationId.uuidString,
            scheduled_at: ISO8601DateFormatter().string(from: scheduledAt),
            status: status.rawValue,
            logged_at: ISO8601DateFormatter().string(from: Date()),
            notes: notes
        )

        return try await supabase
            .from("medication_logs")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func skipDose(medicationId: UUID, scheduledAt: Date, reason: String?) async throws -> MedicationLog {
        let userId = try await supabase.auth.session.user.id

        struct SkippedDoseLog: Codable {
            let user_id: String
            let medication_id: String
            let scheduled_at: String
            let status: String
            let logged_at: String
            let skip_reason: String?

            enum CodingKeys: String, CodingKey {
                case user_id
                case medication_id
                case scheduled_at
                case status
                case logged_at
                case skip_reason
            }
        }

        let payload = SkippedDoseLog(
            user_id: userId.uuidString,
            medication_id: medicationId.uuidString,
            scheduled_at: ISO8601DateFormatter().string(from: scheduledAt),
            status: MedicationStatus.skipped.rawValue,
            logged_at: ISO8601DateFormatter().string(from: Date()),
            skip_reason: reason
        )

        return try await supabase
            .from("medication_logs")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func updateSupplyCount(medicationId: UUID) async throws -> Int? {
        // Call Edge Function to atomically decrement supply count
        let response = try await supabase.functions.invoke(
            "update-supply-count",
            options: .init(body: ["medicationId": medicationId.uuidString])
        )

        guard let data = response as? [String: Any],
              let supplyCount = data["supply_count"] as? Int else {
            return nil
        }

        return supplyCount
    }
}
