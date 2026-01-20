import Foundation

@MainActor
final class AddMedicationViewModel: ObservableObject {
    @Published var name = ""
    @Published var dosage = ""
    @Published var purpose = ""
    @Published var icon: MedicationIcon = .pill
    @Published var frequency: MedicationFrequency = .daily
    @Published var timesPerDay = 1
    @Published var scheduledTimes: [Date] = [Date()]
    @Published var daysOfWeek: [Int]? = nil
    @Published var notificationText = ""
    @Published var reminderEnabled = true
    @Published var useGenericNotification = false
    @Published var supplyCount: Int? = nil
    @Published var refillReminderCount: Int? = nil
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
            timesPerDay: timesPerDay,
            scheduledTimes: scheduledTimes,
            daysOfWeek: daysOfWeek,
            reminderEnabled: reminderEnabled,
            notificationText: notificationText.isEmpty ? nil : notificationText,
            useGenericNotification: useGenericNotification,
            supplyCount: supplyCount,
            refillReminderCount: refillReminderCount
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
