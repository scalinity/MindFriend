// SOSBreathingView.swift
// MindFriend - Animated Breathing Exercise for SOS Intervention

import SwiftUI

/// Animated breathing exercise with expanding/contracting circle
struct SOSBreathingView: View {
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
            VStack(spacing: 8) {
                Text("You're safe")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Let's breathe together")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.top, 40)

            Spacer()

            // Breathing Circle
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.cyan.opacity(0.3), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 180
                        )
                    )
                    .frame(width: 360, height: 360)
                    .scaleEffect(circleScale * 1.2)

                // Main circle
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.cyan.opacity(0.6), .blue.opacity(0.3)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 150
                        )
                    )
                    .frame(width: 300, height: 300)
                    .scaleEffect(circleScale)

                // Border
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 2)
                    .frame(width: 300, height: 300)
                    .scaleEffect(circleScale)

                // Instruction text
                VStack(spacing: 12) {
                    Text(currentPhase.instruction)
                        .font(.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .accessibilityLabel("Breathing instruction: \(currentPhase.instruction)")

                    Text("\(Int(currentPhase.duration - (phaseProgress * currentPhase.duration))) sec")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.8))
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(currentPhase.instruction), \(Int(currentPhase.duration)) seconds")

            Spacer()

            // Progress
            VStack(spacing: 16) {
                // Cycle indicators
                HStack(spacing: 8) {
                    ForEach(0..<totalCycles, id: \.self) { index in
                        Circle()
                            .fill(index < currentCycle ? Color.white : Color.white.opacity(0.3))
                            .frame(width: 10, height: 10)
                    }
                }
                .accessibilityLabel("Cycle \(currentCycle + 1) of \(totalCycles)")

                Text("Cycle \(currentCycle + 1) of \(totalCycles)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            // Controls
            HStack {
                Spacer()

                Button("Skip to Help") {
                    breathingTask?.cancel()
                    onSkip()
                }
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.2, blue: 0.4),
                    Color(red: 0.15, green: 0.1, blue: 0.3)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
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
                        let targetScale: CGFloat = phase.name == "inhale" ? 1.0 : (phase.name == "exhale" ? 0.5 : circleScale)

                        withAnimation(.easeInOut(duration: phase.duration)) {
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
