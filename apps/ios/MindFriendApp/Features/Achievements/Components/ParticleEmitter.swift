// MindFriend Particle Emitter
// SwiftUI particle burst animation for level-up celebrations

import SwiftUI

struct ParticleBurstView: View {
    let particleCount: Int
    let colors: [Color]
    let duration: Double
    
    @State private var particles: [Particle] = []
    @State private var isAnimating = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .position(
                            x: geometry.size.width / 2 + particle.offsetX,
                            y: geometry.size.height / 2 + particle.offsetY
                        )
                        .opacity(particle.opacity)
                }
            }
        }
        .onAppear {
            initializeParticles()
            animateParticles()
        }
    }
    
    private func initializeParticles() {
        particles = (0..<particleCount).map { _ in
            Particle(
                color: colors.randomElement() ?? .purple,
                size: CGFloat.random(in: 4...12),
                offsetX: 0,
                offsetY: 0,
                opacity: 1.0
            )
        }
    }
    
    private func animateParticles() {
        isAnimating = true
        
        for index in particles.indices {
            let angle = Double.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 100...200)
            
            withAnimation(.easeOut(duration: duration)) {
                particles[index].offsetX = cos(angle) * distance
                particles[index].offsetY = sin(angle) * distance
                particles[index].opacity = 0
            }
        }
        
        // Cleanup after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            particles.removeAll()
        }
    }
}

struct Particle: Identifiable {
    let id = UUID()
    var color: Color
    var size: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat
    var opacity: Double
}
