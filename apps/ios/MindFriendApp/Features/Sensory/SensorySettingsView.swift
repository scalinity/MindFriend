import SwiftUI

struct SensorySettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    @State private var settings: SensorySettings?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    // Local editing state
    @State private var defaultSpeed: SpeedPreset = .medium
    @State private var hapticIntensity: Float = 1.0
    @State private var enableAutoPause = true
    @State private var defaultSessionDuration: Int = 600  // 10 minutes

    private let durationOptions: [(label: String, value: Int)] = [
        ("5 minutes", 300),
        ("10 minutes", 600),
        ("15 minutes", 900),
        ("20 minutes", 1200),
        ("30 minutes", 1800)
    ]

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    ProgressView()
                } else {
                    // Speed preset section
                    speedSection

                    // Haptic intensity section
                    hapticSection

                    // Session preferences
                    sessionSection
                }
            }
            .navigationTitle("Sensory Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveSettings() }
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                await loadSettings()
            }
        }
    }

    // MARK: - Sections

    private var speedSection: some View {
        Section {
            Picker("Default Speed", selection: $defaultSpeed) {
                Text("Slow").tag(SpeedPreset.slow)
                Text("Medium").tag(SpeedPreset.medium)
                Text("Fast").tag(SpeedPreset.fast)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Default Speed")
        } footer: {
            Text("The default speed for tactile patterns and visual animations. You can adjust this for each session.")
        }
    }

    private var hapticSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Intensity")
                    Spacer()
                    Text("\(Int(hapticIntensity * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: $hapticIntensity, in: 0.0...1.0, step: 0.1)
                    .tint(.accentColor)
            }
        } header: {
            Text("Haptic Intensity")
        } footer: {
            Text("Adjust the strength of vibrations for tactile patterns. Lower values are gentler.")
        }
    }

    private var sessionSection: some View {
        Section {
            Toggle("Auto-pause on interruption", isOn: $enableAutoPause)

            Picker("Default Session Duration", selection: $defaultSessionDuration) {
                ForEach(durationOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
        } header: {
            Text("Session Preferences")
        } footer: {
            Text("Auto-pause will pause your session when interrupted by phone calls or notifications. The default duration is used when starting a new session.")
        }
    }

    // MARK: - Methods

    private func loadSettings() async {
        isLoading = true
        
        // Use default settings for MVP
        let defaults = SensorySettings.default
        settings = defaults
        defaultSpeed = defaults.defaultSpeed
        hapticIntensity = defaults.hapticIntensity
        enableAutoPause = defaults.enableAutoPause
        defaultSessionDuration = defaults.defaultSessionDuration

        isLoading = false
    }

    private func saveSettings() async {
        isSaving = true

        let newSettings = SensorySettings(
            defaultSpeed: defaultSpeed,
            hapticIntensity: hapticIntensity,
            enableAutoPause: enableAutoPause,
            defaultSessionDuration: defaultSessionDuration
        )

        guard newSettings.isValid() else {
            errorMessage = "Invalid settings. Please check your values."
            isSaving = false
            return
        }

        do {
            guard let userId = container.supabaseAuthService.currentUser?.id else {
                errorMessage = "You must be signed in to save settings"
                isSaving = false
                return
            }

            struct SensorySettingsUpdate: Encodable {
                let sensory_default_speed: String
                let sensory_haptic_intensity: Float
                let sensory_enable_autopause: Bool
                let sensory_default_duration: Int
            }

            try await container.supabase
                .from("user_settings")
                .update(SensorySettingsUpdate(
                    sensory_default_speed: defaultSpeed.rawValue,
                    sensory_haptic_intensity: hapticIntensity,
                    sensory_enable_autopause: enableAutoPause,
                    sensory_default_duration: defaultSessionDuration
                ))
                .eq("user_id", value: userId.uuidString)
                .execute()

            settings = newSettings
            dismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }
}

#Preview {
    SensorySettingsView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer.preview)
}
