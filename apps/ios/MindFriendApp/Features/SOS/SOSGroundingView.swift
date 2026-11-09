// SOSGroundingView.swift
// MindFriend - 5-4-3-2-1 Grounding Exercise for SOS Intervention

import SwiftUI

/// 5-4-3-2-1 sensory grounding exercise
struct SOSGroundingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var container: DependencyContainer

    var sosCoordinator: SOSCoordinator {
        container.sosCoordinator
    }

    let currentSense: GroundingSense
    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var showingExamples = false

    private var step: (count: Int, sense: GroundingSense, prompt: String, examples: [String]) {
        GroundingExercise.steps.first { $0.sense == currentSense } ?? (5, .see, "Name 5 things you can SEE", [])
    }

    private var progress: CGFloat {
        let total = GroundingSense.orderedSenses.count
        let current = GroundingSense.orderedSenses.firstIndex(of: currentSense) ?? 0
        return CGFloat(current) / CGFloat(total)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: SupportTheme.Spacing.xs) {
                Text("5-4-3-2-1 Grounding")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                    .fontWeight(.bold)
                    .foregroundStyle(SupportTheme.textPrimary)

                Text("Let's anchor you to the present moment")
                    .font(.body)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.8))
            }
            .padding(.top, SupportTheme.Spacing.xl)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(SupportTheme.textPrimary.opacity(0.2))
                        .frame(height: 4)

                    Rectangle()
                        .fill(SupportTheme.textPrimary)
                        .frame(width: geometry.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, SupportTheme.Spacing.l)
            .padding(.top, SupportTheme.Spacing.l)

            Spacer()

            // Main content
            VStack(spacing: SupportTheme.Spacing.xl) {
                // Sense icon
                ZStack {
                    Circle()
                        .fill(SupportTheme.accent.opacity(0.2))
                        .frame(width: 120, height: 120)

                    Image(systemName: currentSense.icon)
                        .font(.system(size: 48))
                        .foregroundStyle(SupportTheme.accent)
                }
                .accessibilityHidden(true)

                // Step info
                VStack(spacing: SupportTheme.Spacing.s) {
                    Text("Step \(6 - currentSense.rawValue) of 5")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textPrimary.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(1)

                    Text(step.prompt)
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)
                        .fontWeight(.medium)
                        .foregroundStyle(SupportTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, SupportTheme.Spacing.l)
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
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.7))
                }

                // Examples
                if showingExamples {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        ForEach(step.examples, id: \.self) { example in
                            HStack(spacing: SupportTheme.Spacing.xs) {
                                Circle()
                                    .fill(SupportTheme.textPrimary.opacity(0.5))
                                    .frame(width: 6, height: 6)
                                Text(example)
                                    .font(.body)
                                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.8))
                            }
                        }
                    }
                    .padding(SupportTheme.Spacing.m)
                    .background(SupportTheme.textPrimary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                    .transition(.opacity)
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : (.easeInOut), value: showingExamples)
                }
            }

            Spacer()

            // Navigation hint
            Text("Take your time. When you're ready, tap to continue.")
                .font(.caption)
                .foregroundStyle(SupportTheme.textPrimary.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, SupportTheme.Spacing.xl)

            Spacer()

            // Controls
            HStack {
                Button("Skip") {
                    onSkip()
                }
                .font(.body)
                .foregroundStyle(SupportTheme.textPrimary.opacity(0.7))
                .padding(.horizontal, SupportTheme.Spacing.l)
                .padding(.vertical, SupportTheme.Spacing.s)

                Spacer()

                Button {
                    sosCoordinator.triggerHaptic(.groundingTap)

                    if currentSense.next != nil {
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
                    .foregroundStyle(SupportTheme.textPrimary)
                    .padding(.horizontal, SupportTheme.Spacing.l)
                    .padding(.vertical, SupportTheme.Spacing.s)
                    .background(SupportTheme.textPrimary.opacity(0.2))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, SupportTheme.Spacing.l)
            .padding(.bottom, SupportTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            SupportTheme.surface
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap anywhere to advance
            sosCoordinator.triggerHaptic(.groundingTap)

            if currentSense.next != nil {
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
