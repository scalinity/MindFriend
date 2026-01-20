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
    @State private var selectedPattern: TactilePattern?
    @State private var showSession: Bool = false

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

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
                        PatternCard(
                            name: pattern.name,
                            description: pattern.description,
                            category: pattern.category.displayName,
                            isPremium: pattern.isPremium,
                            icon: "hand.tap.fill",
                            color: categoryColor(pattern.category)
                        ) {
                            selectedPattern = pattern
                            showSession = true
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Tactile")
        .fullScreenCover(isPresented: $showSession) {
            if let pattern = selectedPattern {
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

struct PatternCard: View {
    let name: String
    let description: String
    let category: String
    let isPremium: Bool
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
                            .fill(color.opacity(0.2))
                            .frame(width: 50, height: 50)

                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundColor(color)
                    }

                    Spacer()

                    if isPremium {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }

                // Pattern info
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(category)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding()
            .frame(height: 180)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
