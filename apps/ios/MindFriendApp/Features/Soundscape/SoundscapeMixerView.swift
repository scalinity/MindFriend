import SwiftUI

/// Main view for the soundscape mixer feature
struct SoundscapeMixerView: View {
    @EnvironmentObject private var mixerService: SoundscapeMixerService
    @Environment(\.dismiss) private var dismiss

    @State private var showSoundsLibrary = false
    @State private var showSavedMixes = false
    @State private var showSaveMixSheet = false
    @State private var showSleepTimerSheet = false
    @State private var newMixName = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with sleep timer
                    headerSection

                    // Layers section
                    layersSection

                    // Master controls
                    masterControlsSection

                    // Presets section
                    if mixerService.state.layers.isEmpty {
                        presetsSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Soundscape Mixer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .sheet(isPresented: $showSoundsLibrary) {
                SoundscapeSoundsLibraryView { sound in
                    addSound(sound)
                }
                .environmentObject(mixerService)
            }
            .sheet(isPresented: $showSavedMixes) {
                SavedMixesView()
                    .environmentObject(mixerService)
            }
            .sheet(isPresented: $showSaveMixSheet) {
                saveMixSheet
            }
            .sheet(isPresented: $showSleepTimerSheet) {
                sleepTimerSheet
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .task {
                await loadSounds()
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            // Sleep timer status
            if let _ = mixerService.state.sleepTimerRemaining {
                HStack(spacing: 6) {
                    Image(systemName: mixerService.state.isFading ? "moon.zzz.fill" : "moon.fill")
                        .font(.caption)

                    Text(mixerService.state.formattedSleepTimerRemaining ?? "")
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(mixerService.state.isFading ? .orange : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Capsule())
                .onTapGesture {
                    showSleepTimerSheet = true
                }
            }

            Spacer()

            // Layer count
            Text("\(mixerService.state.layerCount)/5 sounds")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Layers Section

    private var layersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Layers")
                .font(.headline)

            VStack(spacing: 10) {
                // Active layers
                ForEach(mixerService.state.layers) { layer in
                    SoundscapeLayerCard(
                        layer: layer,
                        onVolumeChange: { volume in
                            mixerService.setLayerVolume(layerId: layer.id, volume: volume)
                        },
                        onRemove: {
                            withAnimation {
                                mixerService.removeLayer(id: layer.id)
                            }
                        }
                    )
                }

                // Empty slots
                if mixerService.state.canAddLayer {
                    EmptyLayerSlot(
                        slotNumber: mixerService.state.layerCount + 1,
                        onTap: { showSoundsLibrary = true }
                    )
                }
            }
        }
    }

    // MARK: - Master Controls Section

    private var masterControlsSection: some View {
        VStack(spacing: 20) {
            // Play/Pause button
            HStack(spacing: 20) {
                // Play/Pause
                Button {
                    togglePlayback()
                } label: {
                    ZStack {
                        Circle()
                            .fill(mixerService.state.hasActiveLayers ? Color.accentColor : Color.gray)
                            .frame(width: 64, height: 64)

                        if mixerService.state.isPreparing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: mixerService.state.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .disabled(!mixerService.state.hasActiveLayers || mixerService.state.isPreparing)

                // Stop
                Button {
                    mixerService.stop()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(.secondarySystemGroupedBackground))
                            .frame(width: 48, height: 48)

                        Image(systemName: "stop.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.primary)
                    }
                }
                .disabled(!mixerService.state.isPlaying)
            }

            // Master volume
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Master Volume")
                        .font(.subheadline)

                    Spacer()

                    Text("\(mixerService.state.masterVolumePercentage)%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }

                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)

                    Slider(
                        value: Binding(
                            get: { Double(mixerService.state.masterVolume) },
                            set: { mixerService.setMasterVolume(Float($0)) }
                        ),
                        in: 0...1
                    )
                    .tint(.accentColor)

                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Start Presets")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(MixerPreset.presets) { preset in
                        PresetCard(preset: preset) {
                            applyPreset(preset)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") {
                dismiss()
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    showSavedMixes = true
                } label: {
                    Label("Saved Mixes", systemImage: "folder")
                }

                Button {
                    showSaveMixSheet = true
                } label: {
                    Label("Save Current Mix", systemImage: "square.and.arrow.down")
                }
                .disabled(mixerService.state.layers.isEmpty)

                Divider()

                Button {
                    showSleepTimerSheet = true
                } label: {
                    Label("Sleep Timer", systemImage: "moon.fill")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Save Mix Sheet

    private var saveMixSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Mix Name", text: $newMixName)
                } header: {
                    Text("Name your mix")
                }

                Section {
                    ForEach(mixerService.state.layers) { layer in
                        HStack {
                            Image(systemName: layer.sound.sfSymbol)
                                .foregroundStyle(Color.accentColor)
                            Text(layer.sound.title)
                            Spacer()
                            Text("\(layer.volumePercentage)%")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Sounds in this mix")
                }
            }
            .navigationTitle("Save Mix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showSaveMixSheet = false
                        newMixName = ""
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveMix()
                        }
                    }
                    .disabled(newMixName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Sleep Timer Sheet

    private var sleepTimerSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SleepTimerDuration.allCases.filter { $0 != .endOfTrack }) { duration in
                        Button {
                            mixerService.setSleepTimer(duration)
                            showSleepTimerSheet = false
                        } label: {
                            HStack {
                                Text(duration.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if mixerService.state.sleepTimerDuration == duration {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }

                if mixerService.state.sleepTimerDuration != nil {
                    Section {
                        Button(role: .destructive) {
                            mixerService.cancelSleepTimer()
                            showSleepTimerSheet = false
                        } label: {
                            Text("Cancel Timer")
                        }
                    }
                }
            }
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showSleepTimerSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func loadSounds() async {
        do {
            try await mixerService.fetchAvailableSounds()
            try await mixerService.fetchSavedMixes()
        } catch {
            Log.media.error("Failed to load sounds", error: error)
        }
    }

    private func addSound(_ sound: SoundscapeSound) {
        do {
            try mixerService.addLayer(sound: sound)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func applyPreset(_ preset: MixerPreset) {
        // Clear existing layers - copy IDs first to avoid mutation during iteration
        let existingLayerIds = mixerService.state.layers.map { $0.id }
        for layerId in existingLayerIds {
            mixerService.removeLayer(id: layerId)
        }

        // Add sounds from preset by matching titles (since presets use semantic IDs)
        for (soundId, volume) in preset.soundConfigs {
            // Try to find sound by title matching the semantic ID
            let searchTerm = soundId.replacingOccurrences(of: "-", with: " ")
            if let sound = findSoundMatching(searchTerm) {
                do {
                    let layerId = try mixerService.addLayer(sound: sound)
                    mixerService.setLayerVolume(layerId: layerId, volume: volume)
                } catch {
                    Log.media.warning("Failed to add preset sound: \(soundId)")
                }
            }
        }
    }

    private func findSoundMatching(_ searchTerm: String) -> SoundscapeSound? {
        // Search through all categories for a sound matching the search term
        for category in SoundscapeCategory.allCases {
            for sound in mixerService.getSounds(for: category) {
                if sound.title.localizedCaseInsensitiveContains(searchTerm) {
                    return sound
                }
            }
        }
        return nil
    }

    private func togglePlayback() {
        if mixerService.state.isPlaying {
            mixerService.pause()
        } else {
            do {
                try mixerService.play()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func saveMix() async {
        let name = newMixName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        do {
            _ = try await mixerService.saveMix(name: name)
            showSaveMixSheet = false
            newMixName = ""
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Preset Card

private struct PresetCard: View {
    let preset: MixerPreset
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 60, height: 60)

                    Image(systemName: preset.iconName)
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(preset.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(width: 140)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    SoundscapeMixerView()
        .environmentObject(SoundscapeMixerService(supabase: supabase))
}
