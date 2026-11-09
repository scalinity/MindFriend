import SwiftUI

struct XPSparkleParticles: View {
    let particleCount: Int

    init(particleCount: Int = 12) {
        self.particleCount = particleCount
    }

    var body: some View {
        CelebrationParticles(count: particleCount, duration: 1.2)
    }
}
