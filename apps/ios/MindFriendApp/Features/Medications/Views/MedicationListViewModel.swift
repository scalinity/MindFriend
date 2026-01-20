import Foundation
import Combine

@MainActor
final class MedicationListViewModel: ObservableObject {
    @Published var medications: [Medication] = []
    @Published var todaySchedule: [ScheduledMedication] = []
    @Published var adherenceRate: Double = 0.0
    @Published var isLoading = false
    @Published var errorMessage = ""

    private let medicationService: MedicationService

    init(service: MedicationService) {
        self.medicationService = service
    }

    func loadMedications() async {
        await medicationService.fetchMedications()
        self.medications = medicationService.medications
    }

    func loadTodaySchedule() async {
        await medicationService.fetchTodaySchedule()
        self.todaySchedule = medicationService.getTodayScheduleItems()
    }

    func calculateAdherence() async {
        await medicationService.calculateAdherence(days: 30)
        self.adherenceRate = medicationService.adherenceRate
    }

    func logDose(medicationId: UUID, scheduledAt: Date) async {
        do {
            try await medicationService.logDose(
                medicationId: medicationId,
                scheduledAt: scheduledAt
            )
            await loadTodaySchedule()
            await calculateAdherence()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func skipDose(medicationId: UUID, scheduledAt: Date, reason: String? = nil) async {
        do {
            try await medicationService.skipDose(
                medicationId: medicationId,
                scheduledAt: scheduledAt,
                reason: reason
            )
            await loadTodaySchedule()
            await calculateAdherence()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
