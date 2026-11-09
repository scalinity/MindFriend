// SOSBreathingView.swift
// MindFriend - Animated Breathing Exercise for SOS Intervention

import SwiftUI

/// Animated breathing exercise with expanding/contracting circle
struct SOSBreathingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var container: DependencyContainer

    var sosCoordinator: SOSCoordinator {
        container.sosCoordinator
    }

    @State private var circleScale: CGFloat = 0.5
    @State private var currentPhaseIndex = 0
    @State private var currentCycle = 0
    @State private var breathingTask: Task<Void, Never>?
    @State private var phaseProgress: CGFloat = 0

    let onComplete: () -> Void
    let onSkip: () -> Void

    private var pattern: BreathingPattern {
        sosCoordinator.settings?.preferredBreathingPattern ?? .calm478
    }

    private var phases: [(name: String, instruction: String, duration: TimeInterval)] {
        pattern.phases
    }

    private var totalCycles: Int {
        pattern.defaultCycles
    }

    private var currentPhase: (name: String, instruction: String, duration: TimeInterval) {
        phases[currentPhaseIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: SupportTheme.Spacing.xs) {
                Text("You're safe")
                    .font(.title)
                    .accessibilityAddTraits(.isHeader)
                    .fontWeight(.bold)
                    .foregroundStyle(SupportTheme.textPrimary)

                Text("Let's breathe together")
                    .font(.title3)
                    .accessibilityAddTraits(.isHeader)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.8))
            }
            .padding(.top, SupportTheme.Spacing.xl)

            Spacer()

            // Breathing Circle
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        SupportTheme.surface
                    )
                    .frame(width: 360, height: 360)
                    .scaleEffect(reduceMotion ? 1 : (circleScale * 1.2))

                // Main circle
                Circle()
                    .fill(
                        SupportTheme.surface
                    )
                    .frame(width: 300, height: 300)
                    .scaleEffect(reduceMotion ? 1 : (circleScale))
                    .opacity(reduceMotion ? (circleScale >= 1 ? 1 : 0.55) : 1)

                // Border
                Circle()
                    .stroke(SupportTheme.textPrimary.opacity(0.5), lineWidth: 2)
                    .frame(width: 300, height: 300)
                    .scaleEffect(reduceMotion ? 1 : (circleScale))
                    .opacity(reduceMotion ? (circleScale >= 1 ? 1 : 0.55) : 1)

                // Instruction text
                VStack(spacing: SupportTheme.Spacing.s) {
                    Text(currentPhase.instruction)
                        .font(.title)
                        .accessibilityAddTraits(.isHeader)
                        .fontWeight(.semibold)
                        .foregroundStyle(SupportTheme.textPrimary)
                        .accessibilityLabel("Breathing instruction: \(currentPhase.instruction)")

                    Text("\(max(1, Int(ceil(currentPhase.duration * (1 - phaseProgress))))) sec")
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)
                        .foregroundStyle(SupportTheme.textPrimary.opacity(0.8))
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(currentPhase.instruction), \(Int(currentPhase.duration)) seconds")

            Spacer()

            // Progress
            VStack(spacing: SupportTheme.Spacing.m) {
                // Cycle indicators
                HStack(spacing: SupportTheme.Spacing.xs) {
                    ForEach(0..<totalCycles, id: \.self) { index in
                        Circle()
                            .fill(
                                index < currentCycle ? SupportTheme.textPrimary : SupportTheme.textPrimary.opacity(0.3)
                            )
                            .frame(width: 10, height: 10)
                    }
                }
                .accessibilityLabel("Cycle \(currentCycle + 1) of \(totalCycles)")

                Text("Cycle \(currentCycle + 1) of \(totalCycles)")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.7))
            }

            Spacer()

            // Controls
            HStack {
                Spacer()

                Button {
                    breathingTask?.cancel()
                    breathingTask = nil
                    onSkip()
                } label: {
                    Text("Skip to Help")
                        .font(.body)
                        .foregroundStyle(SupportTheme.textPrimary.opacity(0.8))
                        .padding(.horizontal, SupportTheme.Spacing.l)
                        .padding(.vertical, SupportTheme.Spacing.s)
                        .background(SupportTheme.textPrimary.opacity(0.2))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, SupportTheme.Spacing.l)
            .padding(.bottom, SupportTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            SupportTheme.surface
        )
        .onAppear {
            startBreathingCycles()
        }
        .onDisappear {
            breathingTask?.cancel()
        }
    }

    private func startBreathingCycles() {
        breathingTask = Task {
            for cycle in 0..<totalCycles {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    currentCycle = cycle
                }

                for (index, phase) in phases.enumerated() {
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        currentPhaseIndex = index
                        phaseProgress = 0

                        // Trigger haptic
                        sosCoordinator.triggerHaptic(sosCoordinator.hapticForBreathingPhase(phase.name))

                        // Animate circle
                        let targetScale: CGFloat =
                            phase.name == "inhale" ? 1.0 : (phase.name == "exhale" ? 0.5 : circleScale)

                        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : (.easeInOut(duration: phase.duration)))
                        {
                            circleScale = targetScale
                        }
                    }

                    // Wait for phase duration with progress updates
                    let steps = 10
                    let stepDuration = phase.duration / Double(steps)

                    for step in 1...steps {
                        guard !Task.isCancelled else { return }

                        do {
                            try await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
                        } catch {
                            return
                        }

                        await MainActor.run {
                            phaseProgress = CGFloat(step) / CGFloat(steps)
                        }
                    }
                }
            }

            // Complete
            if !Task.isCancelled {
                await MainActor.run {
                    onComplete()
                }
            }
        }
    }
}

#Preview {
    SOSBreathingView(onComplete: {}, onSkip: {})
        .environmentObject(DependencyContainer.preview)
}
