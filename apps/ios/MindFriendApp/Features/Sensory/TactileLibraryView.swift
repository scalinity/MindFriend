//
//  TactileLibraryView.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-20.
//  Grid view of tactile haptic patterns
//

import SwiftUI

struct TactileLibraryView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @EnvironmentObject private var appState: AppState
    @State private var selectedPattern: TactilePattern?

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    private var isPremiumUser: Bool {
        appState.entitlements.tier == .premium
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                // Header
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Tactile Patterns")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Feel gentle vibrations to calm your nervous system")
                        .font(.subheadline)
                        .foregroundColor(SupportTheme.textSecondary)
                }
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Pattern grid
                LazyVGrid(columns: columns, spacing: SupportTheme.Spacing.m) {
                    ForEach(TactilePattern.library) { pattern in
                        TactilePatternCard(
                            name: pattern.name,
                            description: pattern.description,
                            category: pattern.category.displayName,
                            isPremium: pattern.isPremium,
                            isLocked: pattern.isPremium && !isPremiumUser,
                            icon: "hand.tap.fill",
                            color: categoryColor(pattern.category)
                        ) {
                            handlePatternTap(pattern)
                        }
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)
            }
            .padding(.vertical, SupportTheme.Spacing.m)
        }
        .supportScreen()
        .navigationTitle("Tactile")
        .fullScreenCover(item: $selectedPattern) { pattern in
            SessionView(
                modality: .tactile,
                patternId: pattern.id,
                patternName: pattern.name,
                sensoryService: dependencies.sensoryRegulationService,
                tactileService: dependencies.tactilePatternService,
                visualService: dependencies.visualAnimationService,
                audioService: dependencies.audioSoundscapeService
            )
        }
    }

    private func handlePatternTap(_ pattern: TactilePattern) {
        if pattern.isPremium && !isPremiumUser {
            appState.showPaywall = true
        } else {
            selectedPattern = pattern
        }
    }

    private func categoryColor(_ category: TactilePattern.PatternCategory) -> Color {
        switch category {
        case .grounding: return SupportTheme.accent
        case .calming: return SupportTheme.accent
        case .energizing: return SupportTheme.accent
        case .focus: return SupportTheme.accent
        }
    }
}

// MARK: - Pattern Card Component

struct TactilePatternCard: View {
    let name: String
    let description: String
    let category: String
    let isPremium: Bool
    let isLocked: Bool
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                // Icon and premium badge
                HStack {
                    ZStack {
                        Circle()
                            .fill(color.opacity(isLocked ? 0.1 : 0.2))
                            .frame(width: 50, height: 50)

                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.title2)
                                .foregroundColor(SupportTheme.textSecondary)
                        } else {
                            Image(systemName: icon)
                                .font(.title2)
                                .foregroundColor(color)
                        }
                    }

                    Spacer()

                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundColor(SupportTheme.textSecondary)
                            .padding(SupportTheme.Spacing.xxs)
                            .background(SupportTheme.textSecondary.opacity(0.2))
                            .clipShape(Circle())
                    }
                }

                // Pattern info
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(name)
                        .font(.headline)
                        .foregroundColor(isLocked ? .secondary : SupportTheme.textPrimary)

                    Text(category)
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)

                    Text(description)
                        .font(.caption2)
                        .foregroundColor(SupportTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isLocked {
                    Text("Premium")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(SupportTheme.textPrimary)
                        .padding(.horizontal, SupportTheme.Spacing.xs)
                        .padding(.vertical, SupportTheme.Spacing.xxs)
                        .background(SupportTheme.textSecondary.opacity(0.6))
                        .clipShape(Capsule())
                }
            }
            .padding(SupportTheme.Spacing.m)
            .frame(height: 180)
            .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
            .opacity(isLocked ? 0.8 : 1.0)
        }
        .buttonStyle(.plain)
    }
}
