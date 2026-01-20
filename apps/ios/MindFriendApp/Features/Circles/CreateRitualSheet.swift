import SwiftUI

/// Sheet for creating a new circle ritual
struct CreateRitualSheet: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    let circleId: UUID
    let onCreated: (CircleRitual) -> Void

    @State private var title = ""
    @State private var selectedType: RitualType = .gratitude
    @State private var startNow = true
    @State private var scheduledDate = Date().addingTimeInterval(5 * 60) // 5 min from now
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ritual title", text: $title)
                        .accessibilityLabel("Ritual title")
                } header: {
                    Text("Title")
                }

                Section {
                    Picker("Ritual Type", selection: $selectedType) {
                        ForEach(RitualType.allCases) { type in
                            HStack {
                                Image(systemName: type.icon)
                                    .foregroundColor(type.swiftUIColor)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.inline)

                    if let type = RitualType(rawValue: selectedType.rawValue) {
                        Text(type.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Type")
                }

                Section {
                    Toggle("Start immediately", isOn: $startNow)
                        .accessibilityLabel("Start immediately")

                    if !startNow {
                        DatePicker(
                            "Schedule for",
                            selection: $scheduledDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .accessibilityLabel("Schedule date and time")
                    }
                } header: {
                    Text("When")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("3 minutes", systemImage: "timer")
                            .font(.subheadline)

                        Text("Members will receive a notification and can join within 2 minutes of start time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Duration")
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Create Ritual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createRitual()
                    }
                    .disabled(title.isEmpty || isCreating)
                }
            }
            .disabled(isCreating)
            .overlay {
                if isCreating {
                    ProgressView("Creating...")
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(10)
                }
            }
        }
    }

    private func createRitual() {
        guard !title.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        Task {
            do {
                let ritual = try await container.ritualService.createRitual(
                    circleId: circleId,
                    title: title,
                    ritualType: selectedType,
                    startNow: startNow,
                    scheduledFor: startNow ? nil : scheduledDate
                )

                await MainActor.run {
                    onCreated(ritual)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}

#Preview {
    CreateRitualSheet(circleId: UUID()) { _ in }
        .environmentObject(DependencyContainer())
}
