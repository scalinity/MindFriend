// MindFriend Skill Energy Particles
// Rising energy streaks that converge and burst for skill level-up celebrations

import SwiftUI

/// Elongated particles that rise upward, converge at center, then burst outward
struct SkillEnergyParticles: View {
    let themeColor: Color
    let onConverge: (() -> Void)?
    let onBurst: (() -> Void)?

    @State private var risingParticles: [EnergyParticle] = []
    @State private var burstParticles: [EnergyParticle] = []
    @State private var phase: EnergyPhase = .idle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(themeColor: Color, onConverge: (() -> Void)? = nil, onBurst: (() -> Void)? = nil) {
        self.themeColor = themeColor
        self.onConverge = onConverge
        self.onBurst = onBurst
    }

    var body: some View {
        GeometryReader { geometry in
            let _ = geometry.size.height / 2

            ZStack {
                // Rising particles
                ForEach(risingParticles) { particle in
                    EnergyStreakShape()
                        .fill(
                            LinearGradient(
                                colors: [particle.color.opacity(0.8), particle.color.opacity(0.2)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: particle.width, height: particle.height)
                        .offset(
                            x: phase == .rising ? particle.convergenceX : particle.startX,
                            y: phase == .rising ? 0 : particle.startY
                        )
                        .opacity(phase == .rising ? 0.9 : 0)
                        .rotationEffect(.degrees(particle.angle))
                        .animation(
                            .easeInOut(duration: 0.6)
                                .delay(particle.delay),
                            value: phase
                        )
                }

                // Burst particles
                ForEach(burstParticles) { particle in
                    EnergyStreakShape()
                        .fill(
                            LinearGradient(
                                colors: [particle.color, particle.color.opacity(0.3)],
                                startPoint: .center,
                                endPoint: .leading
                            )
                        )
                        .frame(width: particle.width, height: particle.height)
                        .offset(
                            x: phase == .burst ? particle.burstX : 0,
                            y: phase == .burst ? particle.burstY : 0
                        )
                        .opacity(phase == .burst ? 0 : 0.9)
                        .rotationEffect(.degrees(particle.burstAngle))
                        .animation(
                            .easeOut(duration: 0.5),
                            value: phase
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                generateParticles(in: geometry.size)
                if !reduceMotion {
                    startAnimation()
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func generateParticles(in size: CGSize) {
        let risingCount = 20
        let burstCount = 20

        // Rising particles start from bottom edges, converge to center
        risingParticles = (0..<risingCount).map { index in
            let spreadX = CGFloat.random(in: -size.width/2...size.width/2)
            let convergenceSpread = CGFloat.random(in: -20...20)

            return EnergyParticle(
                startX: spreadX,
                startY: size.height / 2 + CGFloat.random(in: 50...150),
                convergenceX: convergenceSpread,
                width: CGFloat.random(in: 3...6),
                height: CGFloat.random(in: 20...40),
                color: index % 4 == 0 ? .white : themeColor,
                angle: Double.random(in: -15...15),
                delay: Double.random(in: 0...0.2)
            )
        }

        // Burst particles radiate outward from center
        burstParticles = (0..<burstCount).map { index in
            let angle = (CGFloat(index) / CGFloat(burstCount)) * 2 * .pi
            let distance = CGFloat.random(in: 80...150)

            return EnergyParticle(
                startX: 0,
                startY: 0,
                burstX: cos(angle) * distance,
                burstY: sin(angle) * distance,
                burstAngle: Double(angle * 180 / .pi),
                width: CGFloat.random(in: 4...8),
                height: CGFloat.random(in: 15...30),
                color: index % 3 == 0 ? .white : themeColor,
                angle: 0,
                delay: 0
            )
        }
    }

    private func startAnimation() {
        // Phase 1: Rising
        withAnimation {
            phase = .rising
        }

        // Phase 2: Converge (trigger haptic)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            HapticManager.skillConverge()
            onConverge?()
        }

        // Phase 3: Burst
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation {
                phase = .burst
            }
            HapticManager.skillBurst()
            onBurst?()
        }
    }
}

// MARK: - Energy Phase

private enum EnergyPhase {
    case idle
    case rising
    case burst
}

// MARK: - Energy Particle Model

private struct EnergyParticle: Identifiable {
    let id = UUID()
    let startX: CGFloat
    let startY: CGFloat
    var convergenceX: CGFloat = 0
    var burstX: CGFloat = 0
    var burstY: CGFloat = 0
    var burstAngle: Double = 0
    let width: CGFloat
    let height: CGFloat
    let color: Color
    let angle: Double
    let delay: Double
}

// MARK: - Energy Streak Shape

/// Elongated rounded rectangle for energy streaks
struct EnergyStreakShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: rect.width / 2)
            .path(in: rect)
    }
}

// MARK: - Preview

#Preview("Breathing Skill") {
    ZStack {
        Color.black.ignoresSafeArea()
        SkillEnergyParticles(themeColor: .cyan)
    }
}

#Preview("Meditation Skill") {
    ZStack {
        Color.black.ignoresSafeArea()
        SkillEnergyParticles(themeColor: .purple)
    }
}

#Preview("Movement Skill") {
    ZStack {
        Color.black.ignoresSafeArea()
        SkillEnergyParticles(themeColor: .pink)
    }
}
