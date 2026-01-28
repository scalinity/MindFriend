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
    @State private var selectedAnimation: VisualAnimation?

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

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
                            animation: animation
                        ) {
                            selectedAnimation = animation
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
}

// MARK: - Animation Card Component

struct AnimationCard: View {
    let animation: VisualAnimation
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

                    if animation.isPremium {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "crown.fill")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                                    .padding(8)
                            }
                            Spacer()
                        }
                    }

                    // Animation type icon
                    Image(systemName: animationIcon(animation.type))
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.8))
                }

                // Animation info
                VStack(alignment: .leading, spacing: 4) {
                    Text(animation.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(animation.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding()
            .frame(height: 200)
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
