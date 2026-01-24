import SwiftUI

/// Sleep goals configuration view
struct SleepGoalsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: DependencyContainer
    @StateObject private var viewModel = SleepGoalsViewModel()

    var body: some View {
        Form {
            Section {
                // Target Duration
                Stepper(value: $viewModel.targetDurationHours, in: 4...12) {
                    HStack {
                        Text("Target Sleep Duration")
                        Spacer()
                        Text("\(viewModel.targetDurationHours)h")
                            .foregroundColor(.secondary)
                    }
                }

                // Target Bedtime
                DatePicker("Target Bedtime",
                          selection: $viewModel.targetBedtime,
                          displayedComponents: .hourAndMinute)

                // Target Wake Time
                DatePicker("Target Wake Time",
                          selection: $viewModel.targetWakeTime,
                          displayedComponents: .hourAndMinute)
            } header: {
                Text("Sleep Schedule")
            }

            Section {
                // Wind-Down Duration
                Stepper(value: $viewModel.windDownMinutes, in: 10...60, step: 5) {
                    HStack {
                        Text("Wind-Down Duration")
                        Spacer()
                        Text("\(viewModel.windDownMinutes) min")
                            .foregroundColor(.secondary)
                    }
                }

                // Bedtime Reminder
                Toggle("Bedtime Reminder", isOn: $viewModel.bedtimeReminderEnabled)

                if viewModel.bedtimeReminderEnabled {
                    Stepper(value: $viewModel.reminderOffsetMinutes, in: 15...120, step: 15) {
                        HStack {
                            Text("Remind Me")
                            Spacer()
                            Text("\(viewModel.reminderOffsetMinutes) min before")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Wind-Down Routine")
            }

            Section {
                ForEach(["breathing", "meditation", "journaling", "stretching"], id: \.self) { type in
                    Toggle(type.capitalized, isOn: Binding(
                        get: { viewModel.preferredTypes.contains(type) },
                        set: { isOn in
                            if isOn {
                                viewModel.preferredTypes.insert(type)
                            } else {
                                viewModel.preferredTypes.remove(type)
                            }
                        }
                    ))
                }
            } header: {
                Text("Preferred Activities")
            }

            Section {
                Toggle("Dark Room", isOn: $viewModel.prefersDarkRoom)
                Toggle("Cool Temperature", isOn: $viewModel.prefersCoolRoom)
                Toggle("White Noise", isOn: $viewModel.usesWhiteNoise)
                Toggle("Avoid Blue Light", isOn: $viewModel.avoidsBlueLight)
            } header: {
                Text("Sleep Environment")
            }
        }
        .navigationTitle("Sleep Goals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    Task {
                        await viewModel.save(trackingService: dependencies.sleepTrackingService)
                        dismiss()
                    }
                }
                .disabled(viewModel.isSaving)
            }
        }
        .task {
            await viewModel.load(trackingService: dependencies.sleepTrackingService)
        }
    }
}

// MARK: - View Model

@MainActor
final class SleepGoalsViewModel: ObservableObject {
    @Published var targetDurationHours: Int = 8
    @Published var targetBedtime: Date = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!
    @Published var targetWakeTime: Date = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
    @Published var windDownMinutes: Int = 30
    @Published var bedtimeReminderEnabled: Bool = true
    @Published var reminderOffsetMinutes: Int = 60
    @Published var preferredTypes: Set<String> = ["breathing", "meditation"]
    @Published var prefersDarkRoom: Bool = false
    @Published var prefersCoolRoom: Bool = false
    @Published var usesWhiteNoise: Bool = false
    @Published var avoidsBlueLight: Bool = false
    @Published var isSaving: Bool = false

    private var goalsId: UUID?
    private var userId: UUID?

    func load(trackingService: SleepTrackingService) async {
        do {
            let goals = try await trackingService.fetchGoals()
            goalsId = goals.id
            userId = goals.userId

            targetDurationHours = goals.targetDurationMinutes / 60
            targetBedtime = goals.targetBedtime ?? targetBedtime
            targetWakeTime = goals.targetWakeTime ?? targetWakeTime
            windDownMinutes = goals.windDownDurationMinutes
            bedtimeReminderEnabled = goals.bedtimeReminderEnabled
            reminderOffsetMinutes = goals.bedtimeReminderOffsetMinutes
            preferredTypes = Set(goals.preferredWindDownTypes)

            let prefs = goals.sleepEnvironmentPrefs
            prefersDarkRoom = prefs.prefersDarkRoom ?? false
            prefersCoolRoom = prefs.prefersCoolRoom ?? false
            usesWhiteNoise = prefs.usesWhiteNoise ?? false
            avoidsBlueLight = prefs.hasBlueLight ?? false
        } catch {
            print("Failed to load goals: \(error)")
        }
    }

    func save(trackingService: SleepTrackingService) async {
        guard let goalsId = goalsId, let userId = userId else { return }

        isSaving = true
        defer { isSaving = false }

        let goals = SleepGoals(
            id: goalsId,
            userId: userId,
            targetBedtime: targetBedtime,
            targetWakeTime: targetWakeTime,
            targetDurationMinutes: targetDurationHours * 60,
            windDownDurationMinutes: windDownMinutes,
            bedtimeReminderEnabled: bedtimeReminderEnabled,
            bedtimeReminderOffsetMinutes: reminderOffsetMinutes,
            preferredWindDownTypes: Array(preferredTypes),
            sleepEnvironmentPrefs: SleepEnvironmentPrefs(
                prefersDarkRoom: prefersDarkRoom,
                prefersCoolRoom: prefersCoolRoom,
                usesWhiteNoise: usesWhiteNoise,
                hasBlueLight: avoidsBlueLight
            ),
            createdAt: Date(),
            updatedAt: Date()
        )

        do {
            _ = try await trackingService.upsertGoals(goals)
        } catch {
            print("Failed to save goals: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        SleepGoalsView()
            .environmentObject(DependencyContainer.preview)
    }
}
