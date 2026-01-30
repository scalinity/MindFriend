// MindFriend XP Sparkle Particles
// Small sparkles that drift outward from XP gain toast

import SwiftUI

/// Sparkle particles that emit outward for XP gain celebrations
struct XPSparkleParticles: View {
    let particleCount: Int

    @State private var particles: [XPSparkle] = []
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let goldColor = Color(red: 1.0, green: 0.84, blue: 0.0) // #FFD700
    private let orangeGold = Color(red: 1.0, green: 0.65, blue: 0.0) // #FFA500

    init(particleCount: Int = 12) {
        self.particleCount = particleCount
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Image(systemName: "sparkle")
                        .font(.system(size: particle.size))
                        .foregroundStyle(particle.color)
                        .offset(
                            x: isAnimating ? particle.targetX : 0,
                            y: isAnimating ? particle.targetY : 0
                        )
                        .opacity(isAnimating ? 0 : 0.9)
                        .scaleEffect(isAnimating ? 0.3 : 1.0)
                        .rotationEffect(.degrees(isAnimating ? particle.rotation + 180 : particle.rotation))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                generateParticles(in: geometry.size)
                if !reduceMotion {
                    triggerAnimation()
                }
            }
            .onDisappear {
                // Clean up state on disappear to prevent stale animations
                particles.removeAll()
                isAnimating = false
            }
        }
        .allowsHitTesting(false)
    }

    private func generateParticles(in size: CGSize) {
        particles = (0..<particleCount).map { index in
            let angle = (CGFloat(index) / CGFloat(particleCount)) * 2 * .pi
            let distance = CGFloat.random(in: 40...80)

            // Mix of gold, orange-gold, and white sparkles
            let color: Color = {
                switch index % 4 {
                case 0: return goldColor
                case 1: return orangeGold
                case 2: return .white.opacity(0.9)
                default: return goldColor.opacity(0.8)
                }
            }()

            return XPSparkle(
                targetX: cos(angle) * distance + CGFloat.random(in: -10...10),
                targetY: sin(angle) * distance + CGFloat.random(in: -10...10),
                size: CGFloat.random(in: 8...14),
                color: color,
                rotation: Double.random(in: 0...360)
            )
        }
    }

    private func triggerAnimation() {
        withAnimation(.easeOut(duration: 0.8)) {
            isAnimating = true
        }
    }
}

// MARK: - XP Sparkle Model

private struct XPSparkle: Identifiable {
    let id = UUID()
    let targetX: CGFloat
    let targetY: CGFloat
    let size: CGFloat
    let color: Color
    let rotation: Double
}

// MARK: - Preview

#Preview("XP Sparkles") {
    ZStack {
        Color.black.opacity(0.6).ignoresSafeArea()

        VStack {
            Text("+50 XP")
                .font(.title.bold())
                .foregroundStyle(.yellow)
        }
        .background {
            XPSparkleParticles()
                .frame(width: 200, height: 100)
        }
    }
}

#Preview("More Particles") {
    ZStack {
        Color.black.opacity(0.6).ignoresSafeArea()
        XPSparkleParticles(particleCount: 20)
            .frame(width: 200, height: 200)
    }
}
