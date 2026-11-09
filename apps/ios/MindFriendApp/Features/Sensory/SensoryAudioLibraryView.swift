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
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                // Header
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Audio Soundscapes")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Listen to nature sounds to relax your mind")
                        .font(.subheadline)
                        .foregroundColor(SupportTheme.textSecondary)
                }
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Content states
                if isLoading {
                    VStack(spacing: SupportTheme.Spacing.m) {
                        ProgressView()
                        Text("Loading soundscapes...")
                            .font(.subheadline)
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SupportTheme.Spacing.xl)
                } else if let error = error {
                    VStack(spacing: SupportTheme.Spacing.m) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(.largeTitle))
                            .foregroundColor(SupportTheme.accent)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(SupportTheme.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadSoundscapes() }
                        }
                        .buttonStyle(.supportSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SupportTheme.Spacing.xl)
                    .padding(.horizontal, SupportTheme.Spacing.m)
                } else if soundscapes.isEmpty {
                    // Coming soon state
                    VStack(spacing: SupportTheme.Spacing.m) {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(.largeTitle))
                            .foregroundColor(SupportTheme.accent.opacity(0.5))

                        Text("Coming Soon")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Nature soundscapes are being prepared. Check back soon!")
                            .font(.subheadline)
                            .foregroundColor(SupportTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SupportTheme.Spacing.xl)
                    .padding(.horizontal, SupportTheme.Spacing.m)
                } else {
                    VStack(spacing: SupportTheme.Spacing.s) {
                        ForEach(soundscapes) { soundscape in
                            SleepSoundscapeRow(
                                soundscape: soundscape,
                                isLocked: soundscape.isPremium && !isPremiumUser
                            ) {
                                handleSoundscapeTap(soundscape)
                            }
                        }
                    }
                    .padding(.horizontal, SupportTheme.Spacing.m)
                }
            }
            .padding(.vertical, SupportTheme.Spacing.m)
        }
        .supportScreen()
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
            HStack(spacing: SupportTheme.Spacing.m) {
                // Icon
                ZStack {
                    Circle()
                        .fill(SupportTheme.accent.opacity(isLocked ? 0.1 : 0.2))
                        .frame(width: 60, height: 60)

                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.title2)
                            .foregroundColor(SupportTheme.textSecondary)
                    } else {
                        Image(systemName: categoryIcon(soundscape.category))
                            .font(.title2)
                            .foregroundColor(SupportTheme.accent)
                    }
                }

                // Soundscape info
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    HStack {
                        Text(soundscape.title)
                            .font(.headline)
                            .foregroundColor(isLocked ? .secondary : SupportTheme.textPrimary)

                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundColor(SupportTheme.textSecondary)
                        }
                    }

                    if let description = soundscape.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(SupportTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: SupportTheme.Spacing.xs) {
                        if isLocked {
                            Text("Premium")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(SupportTheme.textPrimary)
                                .padding(.horizontal, SupportTheme.Spacing.xxs)
                                .padding(.vertical, SupportTheme.Spacing.xxs)
                                .background(SupportTheme.textSecondary.opacity(0.6))
                                .clipShape(Capsule())
                        } else {
                            Label(soundscape.formattedDuration, systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(SupportTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .fixedSize()

                            if soundscape.isLoopable {
                                Image(systemName: "repeat")
                                    .font(.caption)
                                    .foregroundColor(SupportTheme.textSecondary)
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: isLocked ? "lock.fill" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
            }
            .supportCard()
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
            SupportTheme.canvas
            .ignoresSafeArea()

            VStack(spacing: SupportTheme.Spacing.xl) {
                // Header
                HStack {
                    Button {
                        audioPlayerService.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(SupportTheme.textPrimary.opacity(0.8))
                            .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                            .accessibilityLabel("Close")
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xxs) {
                        Text(soundscape.title)
                            .font(.headline)
                            .foregroundColor(SupportTheme.textPrimary)

                        Text(soundscape.category.displayName)
                            .font(.caption)
                            .foregroundColor(SupportTheme.textPrimary.opacity(0.7))
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)
                .padding(.top, SupportTheme.Spacing.m)

                Spacer()

                // Album art / visual
                ZStack {
                    Circle()
                        .fill(SupportTheme.accent.opacity(0.3))
                        .frame(width: 200, height: 200)

                    Image(systemName: categoryIcon(soundscape.category))
                        .font(.system(.largeTitle))
                        .foregroundColor(SupportTheme.textPrimary.opacity(0.8))
                }

                Spacer()

                // Timer display
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Text(formatTime(currentTime))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundColor(SupportTheme.textPrimary)

                    if let duration = soundscape.audioURL.flatMap({ _ in Double(soundscape.durationSeconds) }), duration > 0 {
                        ProgressView(value: currentTime / duration)
                            .tint(SupportTheme.accent)
                            .frame(width: 200)
                    }
                }

                Spacer()

                // Controls
                HStack(spacing: SupportTheme.Spacing.xl) {
                    // Play/Pause button
                    Button {
                        togglePlayPause()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(SupportTheme.surface)
                                .frame(width: 80, height: 80)

                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.title)
                                .foregroundColor(SupportTheme.textPrimary)
                        }
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        .accessibilityLabel(isPlaying ? "Pause" : "Play")
                    }

                    // Stop button
                    Button {
                        audioPlayerService.stop()
                        dismiss()
                    } label: {
                        VStack(spacing: SupportTheme.Spacing.xxs) {
                            Image(systemName: "stop.fill")
                                .font(.title2)
                            Text("End")
                                .font(.caption)
                        }
                        .foregroundColor(SupportTheme.textPrimary.opacity(0.8))
                    }
                }
                .padding(.bottom, SupportTheme.Spacing.xl)
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
        .safeAreaInset(edge: .bottom) {
                if showErrorAlert {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    if let error = error {
                        Text(error)
                    }

                    Button("OK") { showErrorAlert = false;
                        error = nil
                        dismiss()
                    }
                }
                    .foregroundStyle(SupportTheme.textSecondary)
                    .buttonStyle(.supportSecondary)
                    .supportCard()
                    .padding(SupportTheme.Spacing.m)
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
            HStack(spacing: SupportTheme.Spacing.m) {
                // Icon
                ZStack {
                    Circle()
                        .fill(SupportTheme.accent.opacity(0.2))
                        .frame(width: 60, height: 60)

                    Image(systemName: soundscapeIcon(soundscape.id))
                        .font(.title2)
                        .foregroundColor(SupportTheme.accent)
                }

                // Soundscape info
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    HStack {
                        Text(soundscape.name)
                            .font(.headline)
                            .foregroundColor(SupportTheme.textPrimary)

                        if soundscape.isPremium {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundColor(SupportTheme.accent)
                        }
                    }

                    Text(soundscape.description)
                        .font(.subheadline)
                        .foregroundColor(SupportTheme.textSecondary)

                    HStack(spacing: SupportTheme.Spacing.s) {
                        Label("\(soundscape.durationSeconds / 60) min", systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(SupportTheme.textSecondary)

                        if soundscape.loopable {
                            Label("Loopable", systemImage: "repeat")
                                .font(.caption)
                                .foregroundColor(SupportTheme.textSecondary)
                        }

                        if let tags = soundscape.tags, !tags.isEmpty {
                            ForEach(tags.prefix(2), id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, SupportTheme.Spacing.xs)
                                    .padding(.vertical, SupportTheme.Spacing.xxs)
                                    .background(SupportTheme.surface)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
            }
            .supportCard()
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
