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
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tactile Patterns")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Feel gentle vibrations to calm your nervous system")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Pattern grid
                LazyVGrid(columns: columns, spacing: 16) {
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
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
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
        case .grounding: return .brown
        case .calming: return .blue
        case .energizing: return .orange
        case .focus: return .purple
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
            VStack(alignment: .leading, spacing: 12) {
                // Icon and premium badge
                HStack {
                    ZStack {
                        Circle()
                            .fill(color.opacity(isLocked ? 0.1 : 0.2))
                            .frame(width: 50, height: 50)

                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.title2)
                                .foregroundColor(.gray)
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
                            .foregroundColor(.gray)
                            .padding(4)
                            .background(Color.gray.opacity(0.2))
                            .clipShape(Circle())
                    }
                }

                // Pattern info
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.headline)
                        .foregroundColor(isLocked ? .secondary : .primary)

                    Text(category)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()
                
                if isLocked {
                    Text("Premium")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.6))
                        .clipShape(Capsule())
                }
            }
            .padding()
            .frame(height: 180)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
            )
            .opacity(isLocked ? 0.8 : 1.0)
        }
        .buttonStyle(.plain)
    }
}
