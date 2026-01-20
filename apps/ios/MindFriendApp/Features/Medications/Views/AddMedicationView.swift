import SwiftUI

struct AddMedicationView: View {
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var dosage = ""
    @State private var purpose = ""
    @State private var icon: MedicationIcon = .pill
    @State private var frequency: MedicationFrequency = .daily
    @State private var time1 = Date()
    @State private var reminderEnabled = true
    @State private var useGenericNotification = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication Details") {
                    TextField("Name *", text: $name)
                    TextField("Dosage", text: $dosage)
                    TextField("Purpose", text: $purpose)

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
                        DatePicker("Time", selection: $time1, displayedComponents: .hourAndMinute)
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
                        // TODO: Save medication
                        isPresented = false
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AddMedicationView(isPresented: .constant(true))
    }
}
