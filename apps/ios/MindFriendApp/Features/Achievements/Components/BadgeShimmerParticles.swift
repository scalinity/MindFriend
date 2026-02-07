// MindFriend Badge Shimmer Particles
// Diamond-shaped particles that pulse outward in waves

import SwiftUI

/// Diamond-shaped particles in pulsing waves for badge celebrations
struct BadgeShimmerParticles: View {
    let tierColor: Color
    let waveCount: Int
    let particlesPerWave: Int

    @State private var particles: [[ShimmerParticle]] = []
    @State private var activeWaves: Set<Int> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(tierColor: Color, waveCount: Int = 3, particlesPerWave: Int = 8) {
        self.tierColor = tierColor
        self.waveCount = waveCount
        self.particlesPerWave = particlesPerWave
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<waveCount, id: \.self) { waveIndex in
                    ForEach(particles[safe: waveIndex] ?? []) { particle in
                        DiamondShape()
                            .fill(particle.color)
                            .frame(width: particle.size, height: particle.size)
                            .offset(
                                x: activeWaves.contains(waveIndex) ? particle.targetX : 0,
                                y: activeWaves.contains(waveIndex) ? particle.targetY : 0
                            )
                            .opacity(activeWaves.contains(waveIndex) ? 0 : 0.8)
                            .rotationEffect(.degrees(particle.rotation))
                            .animation(
                                .easeOut(duration: 0.8)
                                    .delay(Double(waveIndex) * 0.3),
                                value: activeWaves.contains(waveIndex)
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                generateParticles(in: geometry.size)
                if !reduceMotion {
                    triggerWaves()
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func generateParticles(in size: CGSize) {
        particles = (0..<waveCount).map { _ in
            (0..<particlesPerWave).map { index in
                let angle = (CGFloat(index) / CGFloat(particlesPerWave)) * 2 * .pi
                let distance = CGFloat.random(in: 100...180)

                return ShimmerParticle(
                    targetX: cos(angle) * distance,
                    targetY: sin(angle) * distance,
                    size: CGFloat.random(in: 8...16),
                    color: index % 3 == 0 ? .white.opacity(0.9) : tierColor.opacity(0.8),
                    rotation: Double.random(in: 0...360)
                )
            }
        }
    }

    private func triggerWaves() {
        for waveIndex in 0..<waveCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(waveIndex) * 0.3) {
                withAnimation {
                    _ = activeWaves.insert(waveIndex)
                }
            }
        }
    }
}

// MARK: - Shimmer Particle Model

private struct ShimmerParticle: Identifiable {
    let id = UUID()
    let targetX: CGFloat
    let targetY: CGFloat
    let size: CGFloat
    let color: Color
    let rotation: Double
}

// MARK: - Diamond Shape

/// Diamond/rhombus shape for shimmer particles
struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centerX = rect.midX
        let centerY = rect.midY
        let _ = rect.width / 2
        let _ = rect.height / 2

        path.move(to: CGPoint(x: centerX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: centerY))
        path.addLine(to: CGPoint(x: centerX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: centerY))
        path.closeSubpath()

        return path
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview("Bronze Shimmer") {
    ZStack {
        Color.black.ignoresSafeArea()
        BadgeShimmerParticles(tierColor: Color(hex: "#CD7F32") ?? .orange)
    }
}

#Preview("Gold Shimmer") {
    ZStack {
        Color.black.ignoresSafeArea()
        BadgeShimmerParticles(tierColor: Color(hex: "#FFD700") ?? .yellow)
    }
}

#Preview("Diamond Tier Shimmer") {
    ZStack {
        Color.black.ignoresSafeArea()
        BadgeShimmerParticles(tierColor: Color(hex: "#B9F2FF") ?? .cyan)
    }
}
