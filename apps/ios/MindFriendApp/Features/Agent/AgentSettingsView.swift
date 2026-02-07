import SwiftUI

struct AgentSettingsView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AgentSettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                // Enable/Disable Toggle
                Section {
                    Toggle("Enable Wellness Agent", isOn: $viewModel.isEnabled)
                        .tint(.green)
                } footer: {
                    Text("When enabled, the agent will monitor your patterns and send proactive check-ins.")
                }

                if viewModel.isEnabled {
                    // Autonomy Level
                    Section {
                        Picker("Autonomy Level", selection: $viewModel.autonomyLevel) {
                            ForEach(AutonomyLevel.allCases) { level in
                                VStack(alignment: .leading) {
                                    Text(level.displayName)
                                    Text(level.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .tag(level)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    } header: {
                        Text("Autonomy Level")
                    } footer: {
                        Text("Max \(viewModel.autonomyLevel.maxDailyActions) actions per day at this level")
                    }

                    // Quiet Hours
                    Section {
                        DatePicker(
                            "Start",
                            selection: $viewModel.quietHoursStart,
                            displayedComponents: .hourAndMinute
                        )

                        DatePicker(
                            "End",
                            selection: $viewModel.quietHoursEnd,
                            displayedComponents: .hourAndMinute
                        )
                    } header: {
                        Text("Quiet Hours")
                    } footer: {
                        Text("The agent won't send notifications during quiet hours.")
                    }

                    // Enabled Signals
                    Section {
                        ForEach(SignalType.allCases) { signalType in
                            Toggle(isOn: Binding(
                                get: { viewModel.enabledSignals.contains(signalType.rawValue) },
                                set: { enabled in
                                    if enabled {
                                        viewModel.enabledSignals.insert(signalType.rawValue)
                                    } else {
                                        viewModel.enabledSignals.remove(signalType.rawValue)
                                    }
                                }
                            )) {
                                HStack {
                                    Image(systemName: signalType.iconName)
                                        .foregroundStyle(signalType.color)
                                        .frame(width: 24)

                                    Text(signalType.displayName)
                                }
                            }
                        }
                    } header: {
                        Text("Signal Types")
                    } footer: {
                        Text("Choose which patterns the agent should monitor.")
                    }

                    // Notification Channels
                    Section {
                        Toggle("Push Notifications", isOn: Binding(
                            get: { viewModel.preferredChannels.contains("push") },
                            set: { enabled in
                                if enabled {
                                    viewModel.preferredChannels.insert("push")
                                } else {
                                    viewModel.preferredChannels.remove("push")
                                }
                            }
                        ))

                        Toggle("In-App Messages", isOn: Binding(
                            get: { viewModel.preferredChannels.contains("in_app") },
                            set: { enabled in
                                if enabled {
                                    viewModel.preferredChannels.insert("in_app")
                                } else {
                                    viewModel.preferredChannels.remove("in_app")
                                }
                            }
                        ))
                    } header: {
                        Text("Notification Channels")
                    }

                    // Additional Settings
                    Section {
                        Toggle("Explain Reasoning", isOn: $viewModel.explainReasoning)
                    } header: {
                        Text("Transparency")
                    } footer: {
                        Text("Show why the agent took each action.")
                    }
                }
            }
            .navigationTitle("Agent Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let success = await viewModel.saveSettings(service: dependencies.agentService)
                            if success {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .task {
                await viewModel.loadSettings(service: dependencies.agentService)
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                }
            }
            .alert("Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}

// MARK: - View Model

@MainActor
final class AgentSettingsViewModel: ObservableObject {
    @Published var isEnabled = false
    @Published var autonomyLevel: AutonomyLevel = .balanced
    @Published var quietHoursStart = Calendar.current.date(from: DateComponents(hour: 22, minute: 0)) ?? Date()
    @Published var quietHoursEnd = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
    @Published var enabledSignals: Set<String> = Set(SignalType.allCases.map { $0.rawValue })
    @Published var preferredChannels: Set<String> = ["push", "in_app"]
    @Published var explainReasoning = true

    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    private var originalSettings: AgentSettings?

    func loadSettings(service: AgentService) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // fetchSettings creates default settings if none exist
            let settings = try await service.fetchSettings()
            originalSettings = settings

            isEnabled = settings.isEnabled
            autonomyLevel = settings.autonomyLevel
            enabledSignals = Set(settings.enabledSignals)
            preferredChannels = Set(settings.preferredChannels)
            explainReasoning = settings.explainReasoning

            // Parse quiet hours
            if let start = parseTime(settings.quietHoursStart) {
                quietHoursStart = start
            }
            if let end = parseTime(settings.quietHoursEnd) {
                quietHoursEnd = end
            }
        } catch {
            errorMessage = "Failed to load settings: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func saveSettings(service: AgentService) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        guard var settings = originalSettings else {
            errorMessage = "Settings not loaded. Please try again."
            return false
        }

        settings.isEnabled = isEnabled
        settings.autonomyLevel = autonomyLevel
        settings.enabledSignals = Array(enabledSignals)
        settings.preferredChannels = Array(preferredChannels)
        settings.explainReasoning = explainReasoning
        settings.quietHoursStart = formatTime(quietHoursStart)
        settings.quietHoursEnd = formatTime(quietHoursEnd)
        settings.maxDailyOutreach = autonomyLevel.maxDailyActions

        do {
            try await service.updateSettings(settings)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func parseTime(_ timeString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let time = formatter.date(from: timeString) else { return nil }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(from: components)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

#Preview {
    AgentSettingsView()
        .environmentObject(DependencyContainer.preview)
}
