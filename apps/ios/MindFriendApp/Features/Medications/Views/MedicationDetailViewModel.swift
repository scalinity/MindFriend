import Foundation
import Combine

@MainActor
final class MedicationDetailViewModel: ObservableObject {
    @Published var medication: Medication
    @Published var adherenceStats: MedicationAdherenceStats?
    @Published var logs: [MedicationLog] = []
    @Published var isLoading = false
    @Published var errorMessage = ""

    private let medicationService: MedicationService

    init(medication: Medication, service: MedicationService) {
        self.medication = medication
        self.medicationService = service
    }

    func loadDetails() async {
        isLoading = true
        defer { isLoading = false }

        // Fetch logs for this medication (last 30 days)
        let _ = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let _ = Date()

        // This would be implemented in a future phase with a method to fetch specific medication logs
        // For now, we'll use the available logs from the service

        errorMessage = ""
    }

    func logDose(scheduledAt: Date) async {
        do {
            try await medicationService.logDose(
                medicationId: medication.id,
                scheduledAt: scheduledAt
            )
            await loadDetails()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func skipDose(scheduledAt: Date, reason: String? = nil) async {
        do {
            try await medicationService.skipDose(
                medicationId: medication.id,
                scheduledAt: scheduledAt,
                reason: reason
            )
            await loadDetails()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
