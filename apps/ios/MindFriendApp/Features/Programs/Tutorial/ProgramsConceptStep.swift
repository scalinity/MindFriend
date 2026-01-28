//
//  ProgramsConceptStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: What are programs?
//

import SwiftUI

/// Step 1: Introduce the concept of multi-day programs
struct ProgramsConceptStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showElements = false

    var body: some View {
        TutorialStepView(
            icon: "book.fill",
            iconColor: .cyan,
            headline: "What Are Programs?",
            subheadline: "Programs are structured multi-day journeys designed to help you build lasting skills and habits.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 16) {
                // Comparison: Quest vs Program
                HStack(spacing: 16) {
                    // Quest card
                    VStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)

                        Text("Quest")
                            .font(.subheadline.weight(.medium))

                        Text("Single day challenge")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(showElements ? 1 : 0)
                    .offset(y: showElements ? 0 : 10)

                    // Arrow
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .opacity(showElements ? 1 : 0)

                    // Program card
                    VStack(spacing: 8) {
                        Image(systemName: "book.fill")
                            .font(.title2)
                            .foregroundStyle(.cyan)

                        Text("Program")
                            .font(.subheadline.weight(.medium))

                        Text("Multi-week journey")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.cyan.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(showElements ? 1 : 0.3)
                    .offset(y: showElements ? 0 : 10)
                }
                .padding(.horizontal, 24)

                // Program features
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(features.enumerated()), id: \.element.text) { index, feature in
                        HStack(spacing: 10) {
                            Image(systemName: feature.icon)
                                .font(.caption)
                                .foregroundStyle(feature.color)
                                .frame(width: 20)

                            Text(feature.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .opacity(showElements ? 1 : 0)
                        .animation(
                            .easeOut(duration: 0.3).delay(0.5 + Double(index) * 0.1),
                            value: showElements
                        )
                    }
                }
                .padding(.horizontal, 32)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                    showElements = true
                }
            }
        }
    }

    private var features: [(icon: String, color: Color, text: String)] {
        [
            ("calendar", .blue, "7-30 day structured curriculum"),
            ("brain.head.profile", .purple, "Science-backed methodologies"),
            ("chart.line.uptrend.xyaxis", .green, "Progressive skill building"),
            ("rosette", .orange, "Earn completion certificates")
        ]
    }
}

#Preview {
    ProgramsConceptStep(onNext: {}, onSkip: {})
}
