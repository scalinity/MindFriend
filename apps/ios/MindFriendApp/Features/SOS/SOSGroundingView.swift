// SOSGroundingView.swift
// MindFriend - 5-4-3-2-1 Grounding Exercise for SOS Intervention

import SwiftUI

/// 5-4-3-2-1 sensory grounding exercise
struct SOSGroundingView: View {
    @EnvironmentObject var container: DependencyContainer

    var sosCoordinator: SOSCoordinator {
        container.sosCoordinator
    }

    let currentSense: GroundingSense
    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var showingExamples = false

    private var step: (count: Int, sense: GroundingSense, prompt: String, examples: [String]) {
        GroundingExercise.steps.first { $0.sense == currentSense } ??
        (5, .see, "Name 5 things you can SEE", [])
    }

    private var progress: CGFloat {
        let total = GroundingSense.orderedSenses.count
        let current = GroundingSense.orderedSenses.firstIndex(of: currentSense) ?? 0
        return CGFloat(current) / CGFloat(total)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("5-4-3-2-1 Grounding")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Let's anchor you to the present moment")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.top, 40)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)

                    Rectangle()
                        .fill(Color.white)
                        .frame(width: geometry.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()

            // Main content
            VStack(spacing: 32) {
                // Sense icon
                ZStack {
                    Circle()
                        .fill(currentSense.color.opacity(0.2))
                        .frame(width: 120, height: 120)

                    Image(systemName: currentSense.icon)
                        .font(.system(size: 48))
                        .foregroundStyle(currentSense.color)
                }
                .accessibilityHidden(true)

                // Step info
                VStack(spacing: 12) {
                    Text("Step \(6 - currentSense.rawValue) of 5")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(1)

                    Text(step.prompt)
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Examples button
                Button {
                    showingExamples.toggle()
                } label: {
                    HStack {
                        Image(systemName: showingExamples ? "lightbulb.fill" : "lightbulb")
                        Text(showingExamples ? "Hide examples" : "Need ideas?")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                }

                // Examples
                if showingExamples {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(step.examples, id: \.self) { example in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.white.opacity(0.5))
                                    .frame(width: 6, height: 6)
                                Text(example)
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut, value: showingExamples)
                }
            }

            Spacer()

            // Navigation hint
            Text("Take your time. When you're ready, tap to continue.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            // Controls
            HStack {
                Button("Skip") {
                    onSkip()
                }
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

                Spacer()

                Button {
                    sosCoordinator.triggerHaptic(.groundingTap)

                    if let _ = currentSense.next {
                        // More senses to go
                        sosCoordinator.advanceGrounding()
                    } else {
                        // All done
                        onComplete()
                    }
                } label: {
                    HStack {
                        Text(currentSense.next == nil ? "Done" : "Next")
                        Image(systemName: "arrow.right")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.25, blue: 0.35),
                    Color(red: 0.1, green: 0.15, blue: 0.25)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap anywhere to advance
            sosCoordinator.triggerHaptic(.groundingTap)

            if let _ = currentSense.next {
                sosCoordinator.advanceGrounding()
            } else {
                onComplete()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.prompt). Tap to continue.")
    }
}

#Preview {
    SOSGroundingView(
        currentSense: .see,
        onComplete: {},
        onSkip: {}
    )
    .environmentObject(DependencyContainer.preview)
}
