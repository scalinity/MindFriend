import Foundation

@MainActor
final class AddMedicationViewModel: ObservableObject {
    @Published var name = ""
    @Published var dosage = ""
    @Published var purpose = ""
    @Published var icon: MedicationIcon = .pill
    @Published var frequency: MedicationFrequency = .daily
    @Published var scheduledTimes: [Date] = [Date()]
    @Published var reminderEnabled = true
    @Published var useGenericNotification = false
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var isSuccessful = false

    private let medicationService: MedicationService

    init(service: MedicationService) {
        self.medicationService = service
    }

    var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func saveMedication() async {
        guard isFormValid else { return }

        isLoading = true
        defer { isLoading = false }

        let request = CreateMedicationRequest(
            name: name,
            dosage: dosage.isEmpty ? nil : dosage,
            purpose: purpose.isEmpty ? nil : purpose,
            icon: icon,
            frequency: frequency,
            scheduledTimes: scheduledTimes,
            reminderEnabled: reminderEnabled,
            useGenericNotification: useGenericNotification
        )

        do {
            _ = try await medicationService.addMedication(request)
            isSuccessful = true
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
            isSuccessful = false
        }
    }
}
