import Foundation
import Combine

@MainActor
class MedicationService: ObservableObject {
    @Published var medications: [Medication] = []
    @Published var todayLogs: [MedicationLog] = []
    @Published var adherenceRate: Double = 0.0
    @Published var moodCorrelation: MedicationMoodCorrelation?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let medicationRepository: MedicationRepository
    private let logRepository: MedicationLogRepository
    private let notificationScheduler: NotificationScheduler
    private let adherenceCalculator: AdherenceCalculator

    init(
        medicationRepository: MedicationRepository,
        logRepository: MedicationLogRepository,
        notificationScheduler: NotificationScheduler,
        adherenceCalculator: AdherenceCalculator
    ) {
        self.medicationRepository = medicationRepository
        self.logRepository = logRepository
        self.notificationScheduler = notificationScheduler
        self.adherenceCalculator = adherenceCalculator
    }

    // MARK: - Medications CRUD

    func fetchMedications() async {
        isLoading = true
        defer { isLoading = false }

        do {
            medications = try await medicationRepository.fetchActive()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addMedication(_ request: CreateMedicationRequest) async throws -> Medication {
        let medication = try await medicationRepository.create(request)
        medications.append(medication)

        // Schedule notifications
        await notificationScheduler.schedule(medication: medication)

        return medication
    }

    func updateMedication(_ id: UUID, with request: UpdateMedicationRequest) async throws -> Medication {
        let medication = try await medicationRepository.update(id, with: request)
        if let index = medications.firstIndex(where: { $0.id == id }) {
            medications[index] = medication
        }

        // Reschedule notifications after update
        if let updated = medications.first(where: { $0.id == id }) {
            await notificationScheduler.cancel(medicationId: id)
            await notificationScheduler.schedule(medication: updated)
        }

        return medication
    }

    func deactivateMedication(_ id: UUID) async throws {
        try await medicationRepository.deactivate(id)
        medications.removeAll { $0.id == id }

        // Cancel notifications
        await notificationScheduler.cancel(medicationId: id)
    }

    func archiveMedication(_ id: UUID) async throws {
        try await medicationRepository.archive(id)
        medications.removeAll { $0.id == id }
    }

    // MARK: - Logging

    func logDose(medicationId: UUID, scheduledAt: Date, notes: String? = nil) async throws {
        let status = determineDoseStatus(scheduledAt: scheduledAt)

        let log = try await logRepository.logDose(
            medicationId: medicationId,
            scheduledAt: scheduledAt,
            status: status,
            notes: notes
        )

        // Update today's logs
        if isToday(scheduledAt) {
            if let index = todayLogs.firstIndex(where: { $0.medicationId == medicationId && isSameHour($0.scheduledAt, scheduledAt) }) {
                todayLogs[index] = log
            } else {
                todayLogs.append(log)
            }
        }

        // Decrement supply count
        try await updateSupplyCount(medicationId: medicationId)

        // Recalculate adherence
        await calculateAdherence(days: 30)
    }

    func skipDose(medicationId: UUID, scheduledAt: Date, reason: String? = nil) async throws {
        let log = try await logRepository.skipDose(
            medicationId: medicationId,
            scheduledAt: scheduledAt,
            reason: reason
        )

        // Update today's logs
        if isToday(scheduledAt) {
            if let index = todayLogs.firstIndex(where: { $0.medicationId == medicationId && isSameHour($0.scheduledAt, scheduledAt) }) {
                todayLogs[index] = log
            } else {
                todayLogs.append(log)
            }
        }

        // Recalculate adherence
        await calculateAdherence(days: 30)
    }

    // MARK: - Today's Schedule

    func fetchTodaySchedule() async {
        do {
            todayLogs = try await logRepository.fetchTodayLogs()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func getTodayScheduleItems() -> [ScheduledMedication] {
        var items: [ScheduledMedication] = []

        // Build a lookup dictionary for O(1) log searches instead of O(p) linear scan
        let logsByMedication = Dictionary(grouping: todayLogs, by: { $0.medicationId })

        for med in medications {
            let medsLogs = logsByMedication[med.id] ?? []
            for time in med.scheduledTimes {
                let hour = Calendar.current.component(.hour, from: time)
                let minute = Calendar.current.component(.minute, from: time)
                let scheduledAt = Calendar.current.date(
                    bySettingHour: hour,
                    minute: minute,
                    second: 0,
                    of: Date()
                ) ?? Date()

                let existingLog = medsLogs.first {
                    isSameHour($0.scheduledAt, scheduledAt)
                }

                items.append(ScheduledMedication(
                    id: UUID(),
                    medication: med,
                    scheduledAt: scheduledAt,
                    status: existingLog?.status ?? .pending,
                    log: existingLog
                ))
            }
        }

        return items.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    // MARK: - Adherence

    func calculateAdherence(days: Int = 30) async {
        do {
            let logs = try await logRepository.fetchAllLogs(
                from: Calendar.current.date(byAdding: .day, value: -days, to: Date())!,
                to: Date()
            )

            let taken = logs.filter { $0.status == .taken || $0.status == .late }.count
            let total = logs.count

            adherenceRate = total > 0 ? Double(taken) / Double(total) : 1.0
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Mood Correlation

    func calculateMoodCorrelation() async {
        // Placeholder - would fetch moods from mood service
        // Implementation deferred to Phase 3
    }

    // MARK: - Helper Methods

    private func determineDoseStatus(scheduledAt: Date) -> MedicationStatus {
        let minutesDifference = Calendar.current.dateComponents([.minute], from: scheduledAt, to: Date()).minute ?? 0

        if minutesDifference > 30 {
            return .late
        } else {
            return .taken
        }
    }

    private func updateSupplyCount(medicationId: UUID) async throws {
        _ = try await logRepository.updateSupplyCount(medicationId: medicationId)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func isSameHour(_ date1: Date, _ date2: Date) -> Bool {
        Calendar.current.isDate(date1, equalTo: date2, toGranularity: .hour)
    }
}
