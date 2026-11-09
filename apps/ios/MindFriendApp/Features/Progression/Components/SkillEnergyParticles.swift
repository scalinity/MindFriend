import SwiftUI

struct SkillEnergyParticles: View {
    let themeColor: Color
    let onConverge: (() -> Void)?
    let onBurst: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(themeColor: Color, onConverge: (() -> Void)? = nil, onBurst: (() -> Void)? = nil) {
        self.themeColor = themeColor
        self.onConverge = onConverge
        self.onBurst = onBurst
    }

    var body: some View {
        CelebrationParticles()
            .task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                if !reduceMotion { HapticManager.skillConverge() }
                onConverge?()
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                if !reduceMotion { HapticManager.skillBurst() }
                onBurst?()
            }
    }
}

struct EnergyStreakShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: rect.width / 2)
            .path(in: rect)
    }
}
