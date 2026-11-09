import SwiftUI

/// Compatibility entry point; the shared kit owns theme hues and Reduce Motion.
struct BadgeShimmerParticles: View {
    let tierColor: Color
    let waveCount: Int
    let particlesPerWave: Int

    init(tierColor: Color, waveCount: Int = 3, particlesPerWave: Int = 8) {
        self.tierColor = tierColor
        self.waveCount = waveCount
        self.particlesPerWave = particlesPerWave
    }

    var body: some View {
        CelebrationParticles(count: waveCount * particlesPerWave)
    }
}

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
