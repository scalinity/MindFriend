import SwiftUI

struct AddMedicationView: View {
    @EnvironmentObject private var container: DependencyContainer
    @Binding var isPresented: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var name = ""
    @State private var dosage = ""
    @State private var purpose = ""
    @State private var icon: MedicationIcon = .pill
    @State private var frequency: MedicationFrequency = .daily
    @State private var time1 = Date()
    @State private var time2 = Calendar.current.date(byAdding: .hour, value: 8, to: Date()) ?? Date()
    @State private var time3 = Calendar.current.date(byAdding: .hour, value: 16, to: Date()) ?? Date()
    @State private var reminderEnabled = true
    @State private var useGenericNotification = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication Details") {
                    TextField("Name *", text: $name)
                        .onChange(of: name) { _, newValue in
                            if newValue.count > 100 { name = String(newValue.prefix(100)) }
                        }
                    TextField("Dosage", text: $dosage)
                        .onChange(of: dosage) { _, newValue in
                            if newValue.count > 50 { dosage = String(newValue.prefix(50)) }
                        }
                    TextField("Purpose", text: $purpose)
                        .onChange(of: purpose) { _, newValue in
                            if newValue.count > 200 { purpose = String(newValue.prefix(200)) }
                        }

                    Picker("Type", selection: $icon) {
                        ForEach(MedicationIcon.allCases, id: \.self) { icon in
                            Label(icon.rawValue.capitalized, systemImage: icon.systemImage)
                                .tag(icon)
                        }
                    }
                }

                Section("Schedule") {
                    Picker("Frequency", selection: $frequency) {
                        Text(MedicationFrequency.daily.description).tag(MedicationFrequency.daily)
                        Text(MedicationFrequency.twiceDaily.description).tag(MedicationFrequency.twiceDaily)
                        Text(MedicationFrequency.threeTimesDaily.description).tag(MedicationFrequency.threeTimesDaily)
                        Text(MedicationFrequency.weekly.description).tag(MedicationFrequency.weekly)
                        Text(MedicationFrequency.asNeeded.description).tag(MedicationFrequency.asNeeded)
                    }

                    if frequency != .asNeeded {
                        DatePicker(frequency == .daily || frequency == .weekly ? "Time" : "First dose", selection: $time1, displayedComponents: .hourAndMinute)

                        if frequency == .twiceDaily || frequency == .threeTimesDaily {
                            DatePicker("Second dose", selection: $time2, displayedComponents: .hourAndMinute)
                        }

                        if frequency == .threeTimesDaily {
                            DatePicker("Third dose", selection: $time3, displayedComponents: .hourAndMinute)
                        }
                    }
                }

                Section("Reminders") {
                    Toggle("Enable Reminders", isOn: $reminderEnabled)
                    Toggle("Generic Text", isOn: $useGenericNotification)
                }
            }
            .navigationTitle("Add Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        Task { await saveMedication() }
                    }
                    .disabled(name.isEmpty || isSaving)
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func saveMedication() async {
        isSaving = true
        defer { isSaving = false }

        do {
            guard let userId = container.supabaseAuthService.currentUser?.id else {
                errorMessage = "You must be signed in to add medications"
                return
            }

            struct MedicationInsert: Encodable {
                let id: String
                let user_id: String
                let name: String
                let dosage: String?
                let purpose: String?
                let icon: String
                let frequency: String
                let scheduled_times: [String]
                let reminder_enabled: Bool
                let use_generic_notification: Bool
                let is_active: Bool
            }

            // Build scheduled times array based on frequency
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone(identifier: "UTC")
            var scheduledTimes: [String] = []

            switch frequency {
            case .daily, .weekly:
                scheduledTimes = [formatter.string(from: time1)]
            case .twiceDaily:
                scheduledTimes = [formatter.string(from: time1), formatter.string(from: time2)]
            case .threeTimesDaily:
                scheduledTimes = [formatter.string(from: time1), formatter.string(from: time2), formatter.string(from: time3)]
            case .asNeeded, .custom:
                scheduledTimes = []
            }

            let insert = MedicationInsert(
                id: UUID().uuidString,
                user_id: userId.uuidString,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                dosage: dosage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : dosage.trimmingCharacters(in: .whitespacesAndNewlines),
                purpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : purpose.trimmingCharacters(in: .whitespacesAndNewlines),
                icon: icon.rawValue,
                frequency: frequency.rawValue,
                scheduled_times: scheduledTimes,
                reminder_enabled: reminderEnabled,
                use_generic_notification: useGenericNotification,
                is_active: true
            )

            try await container.supabase
                .from("medications")
                .insert(insert)
                .execute()

            isPresented = false
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        AddMedicationView(isPresented: .constant(true))
    }
}
