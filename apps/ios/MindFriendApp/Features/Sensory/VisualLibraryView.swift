//
//  VisualLibraryView.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-20.
//  Grid view of visual animations
//

import SwiftUI

struct VisualLibraryView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @EnvironmentObject private var appState: AppState
    @State private var selectedAnimation: VisualAnimation?

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
                    Text("Visual Animations")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Watch calming animations to focus your attention")
                        .font(.subheadline)
                        .foregroundColor(SupportTheme.textSecondary)
                }
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Animation grid
                LazyVGrid(columns: columns, spacing: SupportTheme.Spacing.m) {
                    ForEach(VisualAnimation.library) { animation in
                        AnimationCard(
                            animation: animation,
                            isLocked: animation.isPremium && !isPremiumUser
                        ) {
                            handleAnimationTap(animation)
                        }
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)
            }
            .padding(.vertical, SupportTheme.Spacing.m)
        }
        .supportScreen()
        .navigationTitle("Visual")
        .fullScreenCover(item: $selectedAnimation) { animation in
            SessionView(
                modality: .visual,
                patternId: animation.id,
                patternName: animation.name,
                sensoryService: dependencies.sensoryRegulationService,
                tactileService: dependencies.tactilePatternService,
                visualService: dependencies.visualAnimationService,
                audioService: dependencies.audioSoundscapeService
            )
        }
    }

    private func handleAnimationTap(_ animation: VisualAnimation) {
        // Check if this is a premium animation and user is not premium
        if animation.isPremium && !isPremiumUser {
            appState.showPaywall = true
        } else {
            selectedAnimation = animation
        }
    }
}

// MARK: - Animation Card Component

struct AnimationCard: View {
    let animation: VisualAnimation
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                // Preview area with gradient
                ZStack {
                    SupportTheme.surface
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    .opacity(isLocked ? 0.5 : 1.0)

                    if isLocked {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundColor(SupportTheme.textPrimary)
                                    .padding(SupportTheme.Spacing.xxs)
                                    .background(SupportTheme.canvas.opacity(0.5))
                                    .clipShape(Circle())
                                    .padding(SupportTheme.Spacing.xxs)
                            }
                            Spacer()
                        }
                    }

                    // Animation type icon or lock
                    if isLocked {
                        VStack(spacing: SupportTheme.Spacing.xxs) {
                            Image(systemName: "lock.fill")
                                .font(.title)
                                .foregroundColor(SupportTheme.textPrimary)
                            Text("Premium")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(SupportTheme.textPrimary)
                        }
                    } else {
                        Image(systemName: animationIcon(animation.type))
                            .font(.largeTitle)
                            .foregroundColor(SupportTheme.textPrimary.opacity(0.8))
                    }
                }

                // Animation info
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(animation.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isLocked ? .secondary : SupportTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(animation.description)
                        .font(.caption2)
                        .foregroundColor(SupportTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(height: 60, alignment: .top)
            }
            .padding(SupportTheme.Spacing.s)
            .frame(height: 190)
            .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
        }
        .buttonStyle(.plain)
    }

    private func animationIcon(_ type: VisualAnimation.AnimationType) -> String {
        switch type {
        case .expandingCircle: return "circle.fill"
        case .pulsingSquare: return "square.fill"
        case .wave: return "waveform"
        case .bouncingDot: return "circle.circle"
        case .spiral: return "sparkles"
        case .flowerBloom: return "leaf.fill"
        case .dotGrid: return "circle.grid.3x3.fill"
        case .ribbonFlow: return "wind"
        }
    }
}
