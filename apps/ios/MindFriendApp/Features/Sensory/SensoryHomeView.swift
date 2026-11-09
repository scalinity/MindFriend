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
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                // Header
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Sensory Toolkit")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Use gentle vibrations, calming visuals, or nature sounds to regulate your nervous system")
                        .font(.subheadline)
                        .foregroundColor(SupportTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Modality cards
                VStack(spacing: SupportTheme.Spacing.m) {
                    NavigationLink(destination: TactileLibraryView()) {
                        ModalityCard(
                            title: "Tactile",
                            subtitle: "Feel gentle vibrations",
                            icon: "hand.tap.fill",
                            color: SupportTheme.accent,
                            patternCount: TactilePattern.library.count
                        )
                    }

                    NavigationLink(destination: VisualLibraryView()) {
                        ModalityCard(
                            title: "Visual",
                            subtitle: "Watch calming animations",
                            icon: "eye.fill",
                            color: SupportTheme.accent,
                            patternCount: VisualAnimation.library.count
                        )
                    }

                    NavigationLink(destination: SensoryAudioLibraryView()) {
                        ModalityCard(
                            title: "Audio",
                            subtitle: "Listen to nature sounds",
                            icon: "speaker.wave.3.fill",
                            color: SupportTheme.accent,
                            patternCount: AudioSoundscape.library.count
                        )
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Recent sessions (if any)
                if !recentSessions.isEmpty {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Text("Recent Sessions")
                            .font(.headline)
                .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, SupportTheme.Spacing.m)

                        ForEach(recentSessions.prefix(3)) { session in
                            RecentSessionRow(session: session)
                        }
                    }
                }

                // Tips section
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Text("Tips")
                        .font(.headline)
                .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, SupportTheme.Spacing.m)

                    SensoryTipCard(
                        icon: "headphones",
                        title: "Best Results",
                        message: "Use headphones for audio soundscapes and find a quiet space for tactile patterns."
                    )

                    SensoryTipCard(
                        icon: "moon.fill",
                        title: "Session Length",
                        message: "Start with 5-10 minutes. Sessions auto-pause at 30 minutes to prevent overuse."
                    )
                }
                .padding(.horizontal, SupportTheme.Spacing.m)
            }
            .padding(.vertical, SupportTheme.Spacing.m)
        }
        .supportScreen()
        .navigationTitle("Sensory Toolkit")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadRecentSessions()
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
        HStack(spacing: SupportTheme.Spacing.m) {
            // Icon
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 60, height: 60)

                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
            }
            .fixedSize()

            // Info
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(SupportTheme.textPrimary)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(SupportTheme.textSecondary)
                    .multilineTextAlignment(.leading)

                Text("\(patternCount) patterns available")
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(SupportTheme.textSecondary)
        }
        .supportCard()
    }
}

// MARK: - Recent Session Row

struct RecentSessionRow: View {
    let session: SensorySession

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: session.modality.icon)
                .font(.title3)
                .foregroundColor(SupportTheme.textSecondary)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(session.modality.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let duration = session.durationSeconds {
                    Text("\(duration / 60) min • \(session.startedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                }
            }

            Spacer()
        }
        .supportCard()
        .padding(.horizontal, SupportTheme.Spacing.m)
    }
}

// MARK: - Tip Card

struct SensoryTipCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(SupportTheme.accent)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.leading)

                Text(message)
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SupportTheme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                .fill(SupportTheme.accent.opacity(0.1))
        )
    }
}
