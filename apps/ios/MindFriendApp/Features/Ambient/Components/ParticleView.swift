// MARK: - Particle View
// SF Symbol particle animation for ambient backgrounds

import SwiftUI

/// A view that renders animated particles (SF Symbols) floating across the screen.
/// Respects accessibility settings and automatically disables when Reduce Motion is enabled.
struct ParticleView: View {
    // MARK: - Properties

    let theme: AmbientTheme
    let particleCount: Int

    @State private var particles: [Particle] = []
    @State private var isActive = true
    @State private var cachedSymbolImage: Image?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Particle Model

    struct Particle: Identifiable {
        let id = UUID()
        var position: CGPoint
        var opacity: Double
        var scale: CGFloat
        var rotation: Angle
        var velocity: CGVector

        /// Update particle position based on velocity and delta time
        mutating func update(deltaTime: TimeInterval, bounds: CGSize) {
            position.x += velocity.dx * deltaTime
            position.y += velocity.dy * deltaTime
            rotation += .degrees(deltaTime * 10)

            // Wrap around screen edges
            if position.x < -50 { position.x = bounds.width + 50 }
            if position.x > bounds.width + 50 { position.x = -50 }
            if position.y < -50 { position.y = bounds.height + 50 }
            if position.y > bounds.height + 50 { position.y = -50 }
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            if !reduceMotion && isActive {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    Canvas { context, size in
                        renderParticles(context: context, size: size)
                    }
                    .onChange(of: timeline.date) { _, newDate in
                        updateParticles(deltaTime: 1.0 / 30.0, bounds: geometry.size)
                    }
                }
                .onAppear {
                    // Cache the SF Symbol once to avoid allocation in render loop
                    cachedSymbolImage = Image(systemName: theme.particleSymbol)
                        .renderingMode(.template)
                    initializeParticles(in: geometry.size)
                }
                .onChange(of: theme) { _, newTheme in
                    // Update cached symbol when theme changes
                    cachedSymbolImage = Image(systemName: newTheme.particleSymbol)
                        .renderingMode(.template)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Particle Rendering

    private func renderParticles(context: GraphicsContext, size: CGSize) {
        // Use cached symbol to avoid allocation in render loop (30 fps = 750 allocations/sec otherwise)
        guard let symbol = cachedSymbolImage else { return }

        // Resolve symbol with theme accent color once per frame
        let resolvedSymbol = context.resolve(symbol)

        for particle in particles {
            var particleContext = context
            particleContext.opacity = particle.opacity
            particleContext.translateBy(x: particle.position.x, y: particle.position.y)
            particleContext.rotate(by: particle.rotation)
            particleContext.scaleBy(x: particle.scale, y: particle.scale)

            // Draw cached symbol
            particleContext.draw(resolvedSymbol, at: .zero)
        }
    }

    // MARK: - Particle Management

    private func initializeParticles(in bounds: CGSize) {
        particles = (0..<particleCount).map { _ in
            createRandomParticle(in: bounds)
        }
    }

    private func createRandomParticle(in bounds: CGSize) -> Particle {
        let velocityMagnitude = theme.particleVelocity
        let direction = theme.particleDirection.radians

        // Add some randomness to direction (±30 degrees)
        let randomAngle = direction + Double.random(in: -0.5...0.5)

        return Particle(
            position: CGPoint(
                x: CGFloat.random(in: 0...bounds.width),
                y: CGFloat.random(in: 0...bounds.height)
            ),
            opacity: Double.random(in: 0.2...0.6),
            scale: CGFloat.random(in: 0.5...1.5),
            rotation: .degrees(Double.random(in: 0...360)),
            velocity: CGVector(
                dx: velocityMagnitude * cos(randomAngle),
                dy: -velocityMagnitude * sin(randomAngle) // Negative because Y increases downward
            )
        )
    }

    private func updateParticles(deltaTime: TimeInterval, bounds: CGSize) {
        for i in particles.indices {
            particles[i].update(deltaTime: deltaTime, bounds: bounds)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ParticleView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            LinearGradient.forTheme(.ocean)
            ParticleView(theme: .ocean, particleCount: 25)
        }
        .ignoresSafeArea()
    }
}
#endif
