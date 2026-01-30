// MindFriend Certificate Confetti Particles
// Gold confetti and star particles for certificate celebration

import SwiftUI

/// Confetti + star particles falling from top for certificate celebrations
struct CertificateConfettiParticles: View {
    @State private var particles: [CertConfettiParticle] = []
    @State private var animationPhase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let goldColor = Color(red: 0.85, green: 0.65, blue: 0.13)
    private let creamColor = Color(red: 1.0, green: 0.98, blue: 0.94)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Group {
                        switch particle.shape {
                        case .rectangle:
                            Rectangle()
                                .fill(particle.color)
                                .frame(width: particle.size, height: particle.size * 0.6)
                        case .circle:
                            Circle()
                                .fill(particle.color)
                                .frame(width: particle.size, height: particle.size)
                        case .star:
                            Image(systemName: "star.fill")
                                .font(.system(size: particle.size))
                                .foregroundStyle(particle.color)
                        }
                    }
                    .rotationEffect(.degrees(particle.rotation + (animationPhase ? particle.rotationSpeed : 0)))
                    .position(
                        x: particle.x + (animationPhase ? particle.driftX : 0),
                        y: animationPhase ? geometry.size.height + 50 : particle.y
                    )
                    .opacity(animationPhase ? 0 : 1)
                }
            }
            .onAppear {
                createParticles(in: geometry.size)
                if !reduceMotion {
                    withAnimation(.easeOut(duration: 4.0)) {
                        animationPhase = true
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func createParticles(in size: CGSize) {
        let confettiCount = 60
        let starCount = 12

        // Confetti particles
        let confetti = (0..<confettiCount).map { _ in
            CertConfettiParticle(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: -100...size.height * 0.3),
                size: CGFloat.random(in: 8...14),
                color: [goldColor, goldColor.opacity(0.8), creamColor, .white].randomElement()!,
                rotation: Double.random(in: 0...360),
                rotationSpeed: Double.random(in: 180...540),
                driftX: CGFloat.random(in: -80...80),
                shape: [.rectangle, .circle].randomElement()!
            )
        }

        // Star particles
        let stars = (0..<starCount).map { _ in
            CertConfettiParticle(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: -50...size.height * 0.2),
                size: CGFloat.random(in: 12...20),
                color: goldColor,
                rotation: 0,
                rotationSpeed: Double.random(in: 90...180),
                driftX: CGFloat.random(in: -50...50),
                shape: .star
            )
        }

        particles = confetti + stars
    }
}

// MARK: - Confetti Particle Model

private struct CertConfettiParticle: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let color: Color
    let rotation: Double
    let rotationSpeed: Double
    let driftX: CGFloat
    let shape: ParticleShape

    enum ParticleShape {
        case rectangle
        case circle
        case star
    }
}

// MARK: - Preview

#Preview("Certificate Confetti") {
    ZStack {
        Color.black.ignoresSafeArea()
        CertificateConfettiParticles()
    }
}

#Preview("With Background") {
    ZStack {
        LinearGradient(
            colors: [Color(red: 0.1, green: 0.1, blue: 0.2), .black],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        CertificateConfettiParticles()
    }
}
