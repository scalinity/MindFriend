//
//  SensoryHomeView.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-20.
//  Main entry point for Sensory Regulation Toolkit
//

import SwiftUI

struct SensoryHomeView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @State private var recentSessions: [SensorySession] = []

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sensory Toolkit")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Use gentle vibrations, calming visuals, or nature sounds to regulate your nervous system")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                    // Modality cards
                    VStack(spacing: 16) {
                        NavigationLink(destination: TactileLibraryView()) {
                            ModalityCard(
                                title: "Tactile",
                                subtitle: "Feel gentle vibrations",
                                icon: "hand.tap.fill",
                                color: .blue,
                                patternCount: TactilePattern.library.count
                            )
                        }

                        NavigationLink(destination: VisualLibraryView()) {
                            ModalityCard(
                                title: "Visual",
                                subtitle: "Watch calming animations",
                                icon: "eye.fill",
                                color: .purple,
                                patternCount: VisualAnimation.library.count
                            )
                        }

                        NavigationLink(destination: AudioLibraryView()) {
                            ModalityCard(
                                title: "Audio",
                                subtitle: "Listen to nature sounds",
                                icon: "speaker.wave.3.fill",
                                color: .teal,
                                patternCount: AudioSoundscape.library.count
                            )
                        }
                    }
                    .padding(.horizontal)

                    // Recent sessions (if any)
                    if !recentSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Sessions")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(recentSessions.prefix(3)) { session in
                                RecentSessionRow(session: session)
                            }
                        }
                    }

                    // Tips section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tips")
                            .font(.headline)
                            .padding(.horizontal)

                        TipCard(
                            icon: "headphones",
                            title: "Best Results",
                            message: "Use headphones for audio soundscapes and find a quiet space for tactile patterns."
                        )

                        TipCard(
                            icon: "moon.fill",
                            title: "Session Length",
                            message: "Start with 5-10 minutes. Sessions auto-pause at 30 minutes to prevent overuse."
                        )
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadRecentSessions()
            }
        }
    }

    private func loadRecentSessions() async {
        // TODO: Load recent sessions from database
        // For now, leave empty
    }
}

// MARK: - Modality Card Component

struct ModalityCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let patternCount: Int

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 60, height: 60)

                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("\(patternCount) patterns available")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
}

// MARK: - Recent Session Row

struct RecentSessionRow: View {
    let session: SensorySession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.modality.icon)
                .font(.title3)
                .foregroundColor(.secondary)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.modality.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let duration = session.durationSeconds {
                    Text("\(duration / 60) min • \(session.startedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal)
    }
}

// MARK: - Tip Card

struct TipCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
        )
    }
}
