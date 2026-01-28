//
//  ChatCoachingStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: Cognitive coaching features
//

import SwiftUI

/// Step 3: Explain cognitive coaching and distortion detection
struct ChatCoachingStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showDistortion = false
    @State private var showReframe = false

    var body: some View {
        TutorialStepView(
            icon: "brain.head.profile",
            iconColor: .teal,
            headline: "Cognitive Coaching",
            subheadline: "Your companion can help identify unhelpful thought patterns and suggest healthier perspectives.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 16) {
                // Example thought
                VStack(alignment: .leading, spacing: 8) {
                    Text("You said:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\"I always mess everything up.\"")
                        .font(.subheadline)
                        .italic()
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

                // Distortion detection
                if showDistortion {
                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .font(.title3)
                            .foregroundStyle(.yellow)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pattern Detected")
                                .font(.subheadline.weight(.medium))
                            Text("All-or-nothing thinking")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color.yellow.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Reframe suggestion
                if showReframe {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.title3)
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Try reframing:")
                                .font(.subheadline.weight(.medium))
                            Text("\"I made a mistake this time, but I can learn from it.\"")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
                    showDistortion = true
                }
                withAnimation(.easeOut(duration: 0.4).delay(1.2)) {
                    showReframe = true
                }
            }
        }
    }
}

#Preview {
    ChatCoachingStep(onNext: {}, onSkip: {})
}
