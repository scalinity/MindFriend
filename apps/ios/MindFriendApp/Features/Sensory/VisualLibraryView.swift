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
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Visual Animations")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Watch calming animations to focus your attention")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Animation grid
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(VisualAnimation.library) { animation in
                        AnimationCard(
                            animation: animation,
                            isLocked: animation.isPremium && !isPremiumUser
                        ) {
                            handleAnimationTap(animation)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
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
            VStack(alignment: .leading, spacing: 12) {
                // Preview area with gradient
                ZStack {
                    LinearGradient(
                        colors: animation.colors.compactMap { Color(hex: $0) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(isLocked ? 0.5 : 1.0)

                    if isLocked {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                                    .padding(4)
                            }
                            Spacer()
                        }
                    }

                    // Animation type icon or lock
                    if isLocked {
                        VStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.title)
                                .foregroundColor(.white)
                            Text("Premium")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                    } else {
                        Image(systemName: animationIcon(animation.type))
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                // Animation info
                VStack(alignment: .leading, spacing: 4) {
                    Text(animation.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isLocked ? .secondary : .primary)
                        .lineLimit(2)

                    Text(animation.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .frame(height: 60, alignment: .top)
            }
            .padding(12)
            .frame(height: 190)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
            )
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
