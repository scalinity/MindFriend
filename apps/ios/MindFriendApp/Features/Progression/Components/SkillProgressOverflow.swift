// MindFriend Skill Progress Overflow
// Vertical progress bar with overflow glow effect

import SwiftUI

/// Vertical progress bar that overflows with energy effect when leveling up
struct SkillProgressOverflow: View {
    let progress: Double
    let themeColor: Color
    let isOverflowing: Bool

    @State private var fillHeight: CGFloat = 0
    @State private var glowOpacity: Double = 0
    @State private var sparkleOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barWidth: CGFloat = 12
    private let barHeight: CGFloat = 120

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background track
            RoundedRectangle(cornerRadius: barWidth / 2)
                .fill(Color(.systemGray5))
                .frame(width: barWidth, height: barHeight)

            // Fill
            RoundedRectangle(cornerRadius: barWidth / 2)
                .fill(
                    LinearGradient(
                        colors: [themeColor.opacity(0.7), themeColor],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: barWidth, height: fillHeight)

            // Overflow glow at top
            if isOverflowing {
                ZStack {
                    // Glow circle
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [themeColor, themeColor.opacity(0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 30
                            )
                        )
                        .frame(width: 60, height: 60)
                        .opacity(glowOpacity)
                        .blur(radius: 8)

                    // Sparkle particles at top
                    ForEach(0..<6, id: \.self) { index in
                        Circle()
                            .fill(.white)
                            .frame(width: 4, height: 4)
                            .offset(
                                x: sparkleOffset(for: index),
                                y: sparkleOffsetY(for: index) - sparkleOffset
                            )
                            .opacity(glowOpacity * 0.8)
                    }
                }
                .offset(y: -barHeight / 2 - 10)
            }
        }
        .frame(width: 60, height: barHeight + 40)
        .onAppear {
            animateProgress()
        }
        .onChange(of: isOverflowing) { _, newValue in
            if newValue {
                animateOverflow()
            }
        }
    }

    private func sparkleOffset(for index: Int) -> CGFloat {
        let angle = CGFloat(index) * .pi / 3
        return cos(angle) * 15
    }

    private func sparkleOffsetY(for index: Int) -> CGFloat {
        let angle = CGFloat(index) * .pi / 3
        return sin(angle) * 15
    }

    private func animateProgress() {
        let targetHeight = barHeight * CGFloat(min(progress, 1.0))

        if reduceMotion {
            fillHeight = targetHeight
        } else {
            withAnimation(.easeOut(duration: 0.6)) {
                fillHeight = targetHeight
            }
        }
    }

    private func animateOverflow() {
        guard !reduceMotion else {
            glowOpacity = 0.8
            return
        }

        // Pulse the glow
        withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
            glowOpacity = 0.8
        }

        // Rise the sparkles
        withAnimation(.easeOut(duration: 0.6)) {
            sparkleOffset = 20
        }
    }
}

// MARK: - Preview

#Preview("50% Progress") {
    ZStack {
        Color.black.ignoresSafeArea()
        SkillProgressOverflow(
            progress: 0.5,
            themeColor: .cyan,
            isOverflowing: false
        )
    }
}

#Preview("100% + Overflow") {
    ZStack {
        Color.black.ignoresSafeArea()
        SkillProgressOverflow(
            progress: 1.0,
            themeColor: .purple,
            isOverflowing: true
        )
    }
}

#Preview("Movement Overflow") {
    ZStack {
        Color.black.ignoresSafeArea()
        SkillProgressOverflow(
            progress: 1.0,
            themeColor: .pink,
            isOverflowing: true
        )
    }
}
