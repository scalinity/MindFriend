import Foundation

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
        let userId = try await supabase.auth.session.user.id

        let payload: [String: Any] = [
            "user_id": userId.uuidString,
            "name": medication.name,
            "dosage": medication.dosage as Any,
            "purpose": medication.purpose as Any,
            "icon": medication.icon.rawValue,
            "frequency": medication.frequency.rawValue,
            "times_per_day": medication.timesPerDay,
            "scheduled_times": medication.scheduledTimes.map { formatTime($0) },
            "days_of_week": medication.daysOfWeek as Any,
            "reminder_enabled": medication.reminderEnabled,
            "notification_text": medication.notificationText as Any,
            "use_generic_notification": medication.useGenericNotification,
            "supply_count": medication.supplyCount as Any,
            "refill_reminder_count": medication.refillReminderCount as Any,
        ]

        return try await supabase
            .from("medications")
            .insert([payload])
            .select()
            .single()
            .execute()
            .value
    }

    func update(_ id: UUID, with request: UpdateMedicationRequest) async throws -> Medication {
        var payload: [String: Any] = [:]

        if let name = request.name {
            payload["name"] = name
        }
        if let dosage = request.dosage {
            payload["dosage"] = dosage
        }
        if let purpose = request.purpose {
            payload["purpose"] = purpose
        }
        if let reminderEnabled = request.reminderEnabled {
            payload["reminder_enabled"] = reminderEnabled
        }
        if let notificationText = request.notificationText {
            payload["notification_text"] = notificationText
        }
        if let useGenericNotification = request.useGenericNotification {
            payload["use_generic_notification"] = useGenericNotification
        }
        if let supplyCount = request.supplyCount {
            payload["supply_count"] = supplyCount
        }
        if let refillReminderCount = request.refillReminderCount {
            payload["refill_reminder_count"] = refillReminderCount
        }

        payload["updated_at"] = ISO8601DateFormatter().string(from: Date())

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
        try await supabase
            .from("medications")
            .update([
                "is_active": false,
                "ended_at": Date().formatted(date: .numeric, time: .omitted),
                "updated_at": ISO8601DateFormatter().string(from: Date()),
            ])
            .eq("id", value: id.uuidString)
            .execute()
    }

    func archive(_ id: UUID) async throws {
        try await supabase
            .from("medications")
            .update([
                "archived_at": ISO8601DateFormatter().string(from: Date()),
                "updated_at": ISO8601DateFormatter().string(from: Date()),
            ])
            .eq("id", value: id.uuidString)
            .execute()
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
