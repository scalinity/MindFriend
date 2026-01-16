import SwiftUI

/// Settings view for controlling Proactive Intelligence features
struct ProactiveSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var settings: ProactiveSettings?
    @State private var isLoading = true
    @State private var isSaving = false

    // Local state for edits
    @State private var proactiveEnabled = true
    @State private var maxDaily = 2
    @State private var enabledTypes: Set<ProactiveTriggerType> = Set(ProactiveTriggerType.allCases)

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading settings...")
            } else {
                settingsList
            }
        }
        .navigationTitle("Proactive Check-ins")
        .task { await loadSettings() }
        .trackScreen("proactive_settings")
    }

    private var settingsList: some View {
        List {
            // Info section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.yellow)
                            .font(.title2)
                        Text("MindFriend can proactively reach out to support you based on your patterns and activity.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Main toggle
            Section {
                Toggle(isOn: $proactiveEnabled) {
                    Label("Enable Proactive Check-ins", systemImage: "bell.badge")
                }
                .onChange(of: proactiveEnabled) { _, newValue in
                    saveSettings()
                }
            } footer: {
                Text("When enabled, MindFriend will send helpful nudges based on your wellness patterns.")
            }

            // Trigger types
            if proactiveEnabled {
                Section("What should we check in about?") {
                    ForEach(ProactiveTriggerType.allCases, id: \.self) { type in
                        Toggle(isOn: Binding(
                            get: { enabledTypes.contains(type) },
                            set: { isEnabled in
                                if isEnabled {
                                    enabledTypes.insert(type)
                                } else {
                                    enabledTypes.remove(type)
                                }
                                saveSettings()
                            }
                        )) {
                            HStack(spacing: 12) {
                                Image(systemName: type.icon)
                                    .foregroundColor(type.color)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(type.displayName)
                                    Text(type.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                // Frequency settings
                Section {
                    Stepper(value: $maxDaily, in: 1...5) {
                        HStack {
                            Text("Max daily")
                            Spacer()
                            Text("\(maxDaily) message\(maxDaily == 1 ? "" : "s")")
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: maxDaily) { _, _ in
                        saveSettings()
                    }
                } header: {
                    Text("Frequency")
                } footer: {
                    Text("We'll never send more than this many proactive messages per day.")
                }

                // Quiet hours info
                Section {
                    NavigationLink {
                        QuietHoursInfoView()
                    } label: {
                        HStack {
                            Image(systemName: "moon.fill")
                                .foregroundColor(.indigo)
                            Text("Quiet Hours")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                } footer: {
                    Text("Proactive messages respect your notification quiet hours.")
                }
            }

            // View patterns link
            Section {
                NavigationLink {
                    PatternsView()
                } label: {
                    Label("View Your Patterns", systemImage: "chart.line.uptrend.xyaxis")
                }
            } footer: {
                Text("See what behavioral patterns MindFriend has detected in your wellness data.")
            }
        }
    }

    @MainActor
    private func loadSettings() async {
        isLoading = true

        do {
            let fetchedSettings = try await container.supabaseDataService.getProactiveSettings()
            settings = fetchedSettings

            // Update local state
            proactiveEnabled = fetchedSettings.proactiveEnabled
            maxDaily = fetchedSettings.proactiveMaxDaily
            enabledTypes = Set(fetchedSettings.proactiveTypesEnabled)
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }

        isLoading = false
    }

    private func saveSettings() {
        guard !isSaving else { return }

        Task { @MainActor in
            isSaving = true

            let updatedSettings = ProactiveSettings(
                proactiveEnabled: proactiveEnabled,
                proactiveMaxDaily: maxDaily,
                proactiveTypesEnabled: Array(enabledTypes)
            )

            do {
                try await container.supabaseDataService.updateProactiveSettings(updatedSettings)
                settings = updatedSettings
            } catch {
                // Revert on error
                if let original = settings {
                    proactiveEnabled = original.proactiveEnabled
                    maxDaily = original.proactiveMaxDaily
                    enabledTypes = Set(original.proactiveTypesEnabled)
                }
                appState.showError(.apiError(error.localizedDescription))
            }

            isSaving = false
        }
    }
}

// MARK: - Quiet Hours Info View

struct QuietHoursInfoView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "moon.zzz.fill")
                            .foregroundStyle(.indigo)
                            .font(.largeTitle)
                        VStack(alignment: .leading) {
                            Text("Quiet Hours")
                                .font(.headline)
                            Text("Proactive messages are never sent during your quiet hours.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                HStack {
                    Image(systemName: "gearshape")
                        .foregroundColor(.accentColor)
                    Text("To change quiet hours, go to Settings > Notifications in your main profile settings.")
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("Quiet Hours")
    }
}

// MARK: - Proactive Trigger Type Extensions

extension ProactiveTriggerType {
    var color: Color {
        switch self {
        case .moodDecline:
            return .pink
        case .streakRisk:
            return .orange
        case .milestoneApproach:
            return .yellow
        case .reengagement:
            return .blue
        case .patternInsight:
            return .purple
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProactiveSettingsView()
            .environmentObject(AppState())
            .environmentObject(DependencyContainer())
    }
}
