//
//  AudioLibraryView.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-20.
//  List view of audio soundscapes - fetches from sleep_content database
//

import SwiftUI

struct SensoryAudioLibraryView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @EnvironmentObject private var appState: AppState
    @State private var soundscapes: [SleepContent] = []
    @State private var selectedSoundscape: SleepContent?
    @State private var isLoading = true
    @State private var error: String?
    
    private var isPremiumUser: Bool {
        appState.entitlements.tier == .premium
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio Soundscapes")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Listen to nature sounds to relax your mind")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Content states
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading soundscapes...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else if let error = error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadSoundscapes() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .padding(.horizontal)
                } else if soundscapes.isEmpty {
                    // Coming soon state
                    VStack(spacing: 16) {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.teal.opacity(0.5))

                        Text("Coming Soon")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Nature soundscapes are being prepared. Check back soon!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .padding(.horizontal)
                } else {
                    VStack(spacing: 12) {
                        ForEach(soundscapes) { soundscape in
                            SleepSoundscapeRow(
                                soundscape: soundscape,
                                isLocked: soundscape.isPremium && !isPremiumUser
                            ) {
                                handleSoundscapeTap(soundscape)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Audio")
        .task {
            await loadSoundscapes()
        }
        .fullScreenCover(item: $selectedSoundscape) { soundscape in
            SleepSoundscapePlayerView(
                soundscape: soundscape,
                audioPlayerService: dependencies.audioPlayerService
            )
        }
    }
    
    private func handleSoundscapeTap(_ soundscape: SleepContent) {
        if soundscape.isPremium && !isPremiumUser {
            appState.showPaywall = true
        } else {
            selectedSoundscape = soundscape
        }
    }

    private func loadSoundscapes() async {
        isLoading = true
        error = nil

        do {
            // Fetch soundscapes from the sleep_content table
            let filter = SleepContentFilter.soundscapes()
            soundscapes = try await dependencies.sleepService.fetchContent(filter: filter)
        } catch {
            self.error = "Failed to load soundscapes. Please try again."
        }

        isLoading = false
    }
}

// MARK: - Sleep Soundscape Row Component

struct SleepSoundscapeRow: View {
    let soundscape: SleepContent
    var isLocked: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(isLocked ? 0.1 : 0.2))
                        .frame(width: 60, height: 60)

                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    } else {
                        Image(systemName: categoryIcon(soundscape.category))
                            .font(.title2)
                            .foregroundColor(.teal)
                    }
                }

                // Soundscape info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(soundscape.title)
                            .font(.headline)
                            .foregroundColor(isLocked ? .secondary : .primary)

                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }

                    if let description = soundscape.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        if isLocked {
                            Text("Premium")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.6))
                                .clipShape(Capsule())
                        } else {
                            Label(soundscape.formattedDuration, systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .fixedSize()

                            if soundscape.isLoopable {
                                Image(systemName: "repeat")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: isLocked ? "lock.fill" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
            )
            .opacity(isLocked ? 0.8 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private func categoryIcon(_ category: SleepCategory) -> String {
        switch category {
        case .nature: return "leaf.fill"
        case .ambient: return "cloud.fill"
        case .whiteNoise: return "waveform.circle.fill"
        case .binaural: return "headphones"
        default: return "speaker.wave.3.fill"
        }
    }
}

// MARK: - Sleep Soundscape Player View

struct SleepSoundscapePlayerView: View {
    let soundscape: SleepContent
    let audioPlayerService: AudioPlayerService
    @Environment(\.dismiss) private var dismiss
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var error: String?
    @State private var showErrorAlert = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.teal.opacity(0.3), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                // Header
                HStack {
                    Button {
                        audioPlayerService.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(soundscape.title)
                            .font(.headline)
                            .foregroundColor(.white)

                        Text(soundscape.category.displayName)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)

                Spacer()

                // Album art / visual
                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(0.3))
                        .frame(width: 200, height: 200)

                    Image(systemName: categoryIcon(soundscape.category))
                        .font(.system(size: 80))
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                // Timer display
                VStack(spacing: 8) {
                    Text(formatTime(currentTime))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if let duration = soundscape.audioURL.flatMap({ _ in Double(soundscape.durationSeconds) }), duration > 0 {
                        ProgressView(value: currentTime / duration)
                            .tint(.white)
                            .frame(width: 200)
                    }
                }

                Spacer()

                // Controls
                HStack(spacing: 40) {
                    // Play/Pause button
                    Button {
                        togglePlayPause()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 80, height: 80)

                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.title)
                                .foregroundColor(.black)
                        }
                    }

                    // Stop button
                    Button {
                        audioPlayerService.stop()
                        dismiss()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.title2)
                            Text("End")
                                .font(.caption)
                        }
                        .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
        .task {
            await startPlayback()
        }
        .onReceive(audioPlayerService.$state) { state in
            isPlaying = state.isPlaying
            currentTime = state.currentTime
            // Sync error from player service
            if let stateError = state.error, stateError != error {
                error = stateError
            }
        }
        .onChange(of: error) { _, newValue in
            showErrorAlert = newValue != nil
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") {
                error = nil
                dismiss()
            }
        } message: {
            if let error = error {
                Text(error)
            }
        }
    }

    private func startPlayback() async {
        // Convert SleepContent to AudioTrack for the player service
        let track = AudioTrack(
            id: soundscape.id,
            title: soundscape.title,
            slug: soundscape.id,
            description: soundscape.description,
            authorName: soundscape.narrator,
            imageUrl: soundscape.thumbnailUrl,
            audioUrl: soundscape.audioUrl,
            category: .sounds,
            duration: TimeInterval(soundscape.durationSeconds),
            isFeatured: soundscape.isFeatured,
            playCount: 0,
            createdAt: soundscape.createdAt
        )

        await audioPlayerService.play(track, context: "sensory")
    }

    private func togglePlayPause() {
        audioPlayerService.togglePlayPause()
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func categoryIcon(_ category: SleepCategory) -> String {
        switch category {
        case .nature: return "leaf.fill"
        case .ambient: return "cloud.fill"
        case .whiteNoise: return "waveform.circle.fill"
        case .binaural: return "headphones"
        default: return "speaker.wave.3.fill"
        }
    }
}

// MARK: - Soundscape Row Component

struct SoundscapeRow: View {
    let soundscape: AudioSoundscape
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(0.2))
                        .frame(width: 60, height: 60)

                    Image(systemName: soundscapeIcon(soundscape.id))
                        .font(.title2)
                        .foregroundColor(.teal)
                }

                // Soundscape info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(soundscape.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        if soundscape.isPremium {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    }

                    Text(soundscape.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Label("\(soundscape.durationSeconds / 60) min", systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if soundscape.loopable {
                            Label("Loopable", systemImage: "repeat")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let tags = soundscape.tags, !tags.isEmpty {
                            ForEach(tags.prefix(2), id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.teal.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func soundscapeIcon(_ id: String) -> String {
        switch id {
        case "audio-rain": return "cloud.rain.fill"
        case "audio-ocean-waves": return "water.waves"
        default: return "speaker.wave.3.fill"
        }
    }
}
