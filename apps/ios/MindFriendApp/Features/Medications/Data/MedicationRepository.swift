import Foundation
import Supabase

protocol MedicationRepository {
    func fetchAll() async throws -> [Medication]
    func fetchActive() async throws -> [Medication]
    func create(_ medication: CreateMedicationRequest) async throws -> Medication
    func update(_ id: UUID, with request: UpdateMedicationRequest) async throws -> Medication
    func deactivate(_ id: UUID) async throws
    func archive(_ id: UUID) async throws
}

struct CreateMedicationRequest {
    let name: String
    let dosage: String?
    let purpose: String?
    let icon: MedicationIcon
    let frequency: MedicationFrequency
    let timesPerDay: Int
    let scheduledTimes: [Date]
    let daysOfWeek: [Int]?
    let reminderEnabled: Bool
    let notificationText: String?
    let useGenericNotification: Bool
    let supplyCount: Int?
    let refillReminderCount: Int?
}

struct UpdateMedicationRequest {
    let name: String?
    let dosage: String?
    let purpose: String?
    let reminderEnabled: Bool?
    let notificationText: String?
    let useGenericNotification: Bool?
    let supplyCount: Int?
    let refillReminderCount: Int?
}

final class SupabaseMedicationRepository: MedicationRepository {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    func fetchAll() async throws -> [Medication] {
        let userId = try await supabase.auth.session.user.id

        return try await supabase
            .from("medications")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
    }

    func fetchActive() async throws -> [Medication] {
        let userId = try await supabase.auth.session.user.id

        return try await supabase
            .from("medications")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("is_active", value: true)
            .execute()
            .value
    }

    func create(_ medication: CreateMedicationRequest) async throws -> Medication {
        struct MedicationInsert: Codable {
            let name: String
            let dosage: String?
            let purpose: String?
            let icon: String
            let frequency: String
            let times_per_day: Int
            let reminder_enabled: Bool
            let notification_text: String?
            let use_generic_notification: Bool
            let supply_count: Int?
            let refill_reminder_count: Int?

            enum CodingKeys: String, CodingKey {
                case name, dosage, purpose, icon, frequency
                case times_per_day
                case reminder_enabled
                case notification_text
                case use_generic_notification
                case supply_count
                case refill_reminder_count
            }
        }

        let payload = MedicationInsert(
            name: medication.name,
            dosage: medication.dosage,
            purpose: medication.purpose,
            icon: medication.icon.rawValue,
            frequency: medication.frequency.rawValue,
            times_per_day: medication.timesPerDay,
            reminder_enabled: medication.reminderEnabled,
            notification_text: medication.notificationText,
            use_generic_notification: medication.useGenericNotification,
            supply_count: medication.supplyCount,
            refill_reminder_count: medication.refillReminderCount
        )

        return try await supabase
            .from("medications")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func update(_ id: UUID, with request: UpdateMedicationRequest) async throws -> Medication {
        struct MedicationUpdate: Codable {
            let name: String?
            let dosage: String?
            let purpose: String?
            let reminder_enabled: Bool?
            let notification_text: String?
            let use_generic_notification: Bool?
            let supply_count: Int?
            let refill_reminder_count: Int?
            let updated_at: String

            enum CodingKeys: String, CodingKey {
                case name, dosage, purpose
                case reminder_enabled
                case notification_text
                case use_generic_notification
                case supply_count
                case refill_reminder_count
                case updated_at
            }
        }

        let payload = MedicationUpdate(
            name: request.name,
            dosage: request.dosage,
            purpose: request.purpose,
            reminder_enabled: request.reminderEnabled,
            notification_text: request.notificationText,
            use_generic_notification: request.useGenericNotification,
            supply_count: request.supplyCount,
            refill_reminder_count: request.refillReminderCount,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        return try await supabase
            .from("medications")
            .update(payload)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }

    func deactivate(_ id: UUID) async throws {
        struct DeactivateUpdate: Codable {
            let is_active: Bool
            let ended_at: String
            let updated_at: String

            enum CodingKeys: String, CodingKey {
                case is_active
                case ended_at
                case updated_at
            }
        }

        let payload = DeactivateUpdate(
            is_active: false,
            ended_at: Date().formatted(date: .numeric, time: .omitted),
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        try await supabase
            .from("medications")
            .update(payload)
            .eq("id", value: id.uuidString)
            .execute()
    }

    func archive(_ id: UUID) async throws {
        struct ArchiveUpdate: Codable {
            let archived: Bool
            let updated_at: String

            enum CodingKeys: String, CodingKey {
                case archived
                case updated_at
            }
        }

        let payload = ArchiveUpdate(
            archived: true,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        try await supabase
            .from("medications")
            .update(payload)
            .eq("id", value: id.uuidString)
            .execute()
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
