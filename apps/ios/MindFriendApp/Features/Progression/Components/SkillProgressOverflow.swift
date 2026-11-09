import SwiftUI

/// Static progress with a brief fade when a skill advances; no looping motion.
struct SkillProgressOverflow: View {
    let progress: Double
    let themeColor: Color
    let isOverflowing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { min(1, max(0, progress)) }

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: "sparkles")
                .foregroundStyle(SupportTheme.Celebration.gold)
                .opacity(isOverflowing ? 1 : 0)
                .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.3), value: isOverflowing)
            ZStack(alignment: .bottom) {
                Capsule().fill(SupportTheme.separator)
                Capsule().fill(SupportTheme.accent)
                    .frame(height: 120 * fraction)
            }
            .frame(width: SupportTheme.Spacing.s, height: 120)
        }
        .frame(width: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Skill progress")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}
