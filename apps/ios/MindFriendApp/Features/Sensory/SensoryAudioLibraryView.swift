//
//  AudioLibraryView.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-20.
//  List view of audio soundscapes
//

import SwiftUI

struct SensoryAudioLibraryView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @State private var selectedSoundscape: AudioSoundscape?

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

                // Soundscape list
                VStack(spacing: 12) {
                    ForEach(AudioSoundscape.library) { soundscape in
                        SoundscapeRow(
                            soundscape: soundscape
                        ) {
                            selectedSoundscape = soundscape
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Audio")
        .fullScreenCover(item: $selectedSoundscape) { soundscape in
            SessionView(
                modality: .audio,
                patternId: soundscape.id,
                patternName: soundscape.name,
                sensoryService: dependencies.sensoryRegulationService,
                tactileService: dependencies.tactilePatternService,
                visualService: dependencies.visualAnimationService,
                audioService: dependencies.audioSoundscapeService
            )
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
