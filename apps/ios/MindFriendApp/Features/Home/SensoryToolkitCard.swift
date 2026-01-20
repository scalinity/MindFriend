//
//  SensoryToolkitCard.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-20.
//  Home dashboard card for Sensory Regulation Toolkit
//

import SwiftUI

struct SensoryToolkitCard: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var showSensoryHome = false
    @State private var lastUsedModality: SensoryModality?

    var body: some View {
        NavigationLink(destination: SensoryHomeView()) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2)
                        .foregroundColor(.teal)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sensory Toolkit")
                            .font(.headline)

                        Text("Calm your nervous system")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Quick modality icons
                HStack(spacing: 20) {
                    ModalityQuickIcon(
                        icon: "hand.tap.fill",
                        label: "Tactile",
                        color: .blue,
                        isLastUsed: lastUsedModality == .tactile
                    )

                    ModalityQuickIcon(
                        icon: "eye.fill",
                        label: "Visual",
                        color: .purple,
                        isLastUsed: lastUsedModality == .visual
                    )

                    ModalityQuickIcon(
                        icon: "speaker.wave.3.fill",
                        label: "Audio",
                        color: .teal,
                        isLastUsed: lastUsedModality == .audio
                    )
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .task {
            loadLastUsedModality()
        }
    }

    private func loadLastUsedModality() {
        // Load from UserDefaults
        if let modalityString = UserDefaults.standard.string(forKey: "lastUsedSensoryModality"),
           let modality = SensoryModality(rawValue: modalityString) {
            lastUsedModality = modality
        }
    }
}

// MARK: - Modality Quick Icon

struct ModalityQuickIcon: View {
    let icon: String
    let label: String
    let color: Color
    let isLastUsed: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(isLastUsed ? 0.3 : 0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
            }

            Text(label)
                .font(.caption2)
                .foregroundColor(isLastUsed ? .primary : .secondary)
                .fontWeight(isLastUsed ? .semibold : .regular)
        }
    }
}
