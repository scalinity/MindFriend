import SwiftUI

struct ParticleBurstView: View {
    let particleCount: Int
    let colors: [Color]
    let duration: Double

    var body: some View {
        CelebrationParticles(count: particleCount, duration: duration)
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
