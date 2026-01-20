import SwiftUI

/// View for managing voice preferences for generated content
struct VoicePreferencesView: View {
    @StateObject private var viewModel: VoicePreferencesViewModel

    init(service: GeneratedContentService) {
        _viewModel = StateObject(wrappedValue: VoicePreferencesViewModel(service: service))
    }

    var body: some View {
        List {
            // Global voice preference
            Section {
                ForEach(DefaultVoice.all) { voice in
                    VoiceRow(
                        voice: voice,
                        isSelected: viewModel.defaultVoiceId == voice.id
                    ) {
                        viewModel.defaultVoiceId = voice.id
                    }
                }
            } header: {
                Text("Default Voice")
            } footer: {
                Text("This voice will be used for all content types unless you set a specific preference below.")
            }

            // Playback settings
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Playback Speed")
                        Spacer()
                        Text("\(viewModel.defaultSpeed, specifier: "%.2f")x")
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $viewModel.defaultSpeed, in: 0.5...2.0, step: 0.25)
                }
            } header: {
                Text("Playback")
            }

            // Background sounds
            Section {
                Toggle("Enable Background Sounds", isOn: $viewModel.backgroundEnabled)

                if viewModel.backgroundEnabled {
                    ForEach(BackgroundSoundType.allCases, id: \.rawValue) { sound in
                        BackgroundSoundRow(
                            sound: sound,
                            isSelected: viewModel.defaultBackgroundSound == sound
                        ) {
                            viewModel.defaultBackgroundSound = sound
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Background Volume")
                            Spacer()
                            Text("\(Int(viewModel.backgroundVolume * 100))%")
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $viewModel.backgroundVolume, in: 0.1...1.0, step: 0.1)
                    }
                }
            } header: {
                Text("Background Sounds")
            }

            // Per-content-type preferences
            Section {
                ForEach(GeneratedContentType.allCases.filter(\.supportsAudio)) { type in
                    NavigationLink {
                        ContentTypeVoiceSettingsView(
                            contentType: type,
                            viewModel: viewModel
                        )
                    } label: {
                        HStack {
                            Image(systemName: type.icon)
                                .frame(width: 24)

                            Text(type.displayName)

                            Spacer()

                            if let preference = viewModel.preferences[type] {
                                Text(DefaultVoice.voice(for: preference.preferredVoiceId)?.name ?? "Custom")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Default")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Content-Specific Settings")
            } footer: {
                Text("Override the default voice for specific content types.")
            }

            // Save button
            Section {
                Button {
                    Task {
                        await viewModel.savePreferences()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Text("Save Preferences")
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isSaving)
            }
        }
        .navigationTitle("Voice Settings")
        .alert("Saved", isPresented: $viewModel.showSavedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your voice preferences have been saved.")
        }
        .task {
            await viewModel.loadPreferences()
        }
    }
}

// MARK: - Voice Row

private struct VoiceRow: View {
    let voice: VoiceOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(voice.name)
                        .font(.headline)

                    HStack(spacing: 8) {
                        Label(voice.gender.rawValue.capitalized, systemImage: "person.fill")
                        Label(voice.style.capitalized, systemImage: "waveform")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Background Sound Row

private struct BackgroundSoundRow: View {
    let sound: BackgroundSoundType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: sound.icon)
                    .frame(width: 24)

                Text(sound.displayName)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Content Type Voice Settings

private struct ContentTypeVoiceSettingsView: View {
    let contentType: GeneratedContentType
    @ObservedObject var viewModel: VoicePreferencesViewModel

    @State private var selectedVoiceId: String?
    @State private var speed: Double = 1.0
    @State private var backgroundSound: BackgroundSoundType?
    @State private var backgroundVolume: Double = 0.3

    var body: some View {
        List {
            Section {
                Toggle("Use Custom Settings", isOn: Binding(
                    get: { viewModel.preferences[contentType] != nil },
                    set: { enabled in
                        if enabled {
                            selectedVoiceId = viewModel.defaultVoiceId
                        } else {
                            viewModel.preferences[contentType] = nil
                        }
                    }
                ))
            }

            if viewModel.preferences[contentType] != nil || selectedVoiceId != nil {
                Section("Voice") {
                    ForEach(DefaultVoice.all) { voice in
                        VoiceRow(
                            voice: voice,
                            isSelected: selectedVoiceId == voice.id
                        ) {
                            selectedVoiceId = voice.id
                            updatePreference()
                        }
                    }
                }

                Section("Speed") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Playback Speed")
                            Spacer()
                            Text("\(speed, specifier: "%.2f")x")
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $speed, in: 0.5...2.0, step: 0.25) { _ in
                            updatePreference()
                        }
                    }
                }

                Section("Background") {
                    ForEach(BackgroundSoundType.allCases, id: \.rawValue) { sound in
                        BackgroundSoundRow(
                            sound: sound,
                            isSelected: backgroundSound == sound
                        ) {
                            backgroundSound = sound
                            updatePreference()
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Volume")
                            Spacer()
                            Text("\(Int(backgroundVolume * 100))%")
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $backgroundVolume, in: 0.1...1.0, step: 0.1) { _ in
                            updatePreference()
                        }
                    }
                }
            }
        }
        .navigationTitle(contentType.displayName)
        .onAppear {
            loadCurrentSettings()
        }
    }

    private func loadCurrentSettings() {
        if let preference = viewModel.preferences[contentType] {
            selectedVoiceId = preference.preferredVoiceId
            speed = preference.preferredSpeed
            backgroundSound = preference.backgroundSoundType
            backgroundVolume = preference.backgroundSoundVolume
        } else {
            selectedVoiceId = viewModel.defaultVoiceId
            speed = viewModel.defaultSpeed
            backgroundSound = viewModel.defaultBackgroundSound
            backgroundVolume = viewModel.backgroundVolume
        }
    }

    private func updatePreference() {
        guard let voiceId = selectedVoiceId else { return }

        // Create a minimal preference object for local tracking
        // The actual save happens when the user taps Save Preferences
        viewModel.updateContentTypePreference(
            contentType: contentType,
            voiceId: voiceId,
            speed: speed,
            backgroundSound: backgroundSound,
            backgroundVolume: backgroundVolume
        )
    }
}

// MARK: - View Model

@MainActor
final class VoicePreferencesViewModel: ObservableObject {
    private let service: GeneratedContentService

    @Published var defaultVoiceId: String = DefaultVoice.sarah.id
    @Published var defaultSpeed: Double = 1.0
    @Published var backgroundEnabled: Bool = false
    @Published var defaultBackgroundSound: BackgroundSoundType = .silence
    @Published var backgroundVolume: Double = 0.3
    @Published var preferences: [GeneratedContentType: VoicePreference] = [:]
    @Published var isSaving = false
    @Published var showSavedAlert = false

    // Temporary storage for content-type specific settings
    private var pendingPreferences: [GeneratedContentType: (voiceId: String, speed: Double, background: BackgroundSoundType?, volume: Double)] = [:]

    init(service: GeneratedContentService) {
        self.service = service
    }

    func loadPreferences() async {
        do {
            let loadedPreferences = try await service.fetchVoicePreferences()

            // Build preferences dictionary
            for preference in loadedPreferences {
                preferences[preference.contentType] = preference
            }

            // Set defaults from first preference if available
            if let firstPreference = loadedPreferences.first {
                defaultVoiceId = firstPreference.preferredVoiceId
                defaultSpeed = firstPreference.preferredSpeed
                backgroundEnabled = firstPreference.backgroundSoundEnabled
                defaultBackgroundSound = firstPreference.backgroundSoundType ?? .silence
                backgroundVolume = firstPreference.backgroundSoundVolume
            }
        } catch {
            // Use defaults on error
        }
    }

    func updateContentTypePreference(
        contentType: GeneratedContentType,
        voiceId: String,
        speed: Double,
        backgroundSound: BackgroundSoundType?,
        backgroundVolume: Double
    ) {
        pendingPreferences[contentType] = (voiceId, speed, backgroundSound, backgroundVolume)
    }

    func savePreferences() async {
        isSaving = true

        do {
            // Save default preferences for all audio-supporting content types
            for contentType in GeneratedContentType.allCases where contentType.supportsAudio {
                let voiceId: String
                let speed: Double
                let background: BackgroundSoundType?
                let volume: Double

                if let pending = pendingPreferences[contentType] {
                    voiceId = pending.voiceId
                    speed = pending.speed
                    background = pending.background
                    volume = pending.volume
                } else {
                    voiceId = defaultVoiceId
                    speed = defaultSpeed
                    background = backgroundEnabled ? defaultBackgroundSound : nil
                    volume = backgroundVolume
                }

                try await service.updateVoicePreference(
                    contentType: contentType,
                    voiceId: voiceId,
                    speed: speed,
                    backgroundSound: background,
                    backgroundVolume: volume
                )
            }

            showSavedAlert = true
        } catch {
            // Handle error
            print("Error saving preferences: \(error)")
        }

        isSaving = false
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        VoicePreferencesView(service: .preview)
    }
}
#endif
