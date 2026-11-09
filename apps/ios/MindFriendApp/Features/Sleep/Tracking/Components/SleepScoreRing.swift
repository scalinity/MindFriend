import SwiftUI

/// Circular progress ring showing sleep score
struct SleepScoreRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let score: Int
    let size: CGFloat

    private var color: Color {
        switch score {
        case 85...100: return SupportTheme.accent
        case 70..<85: return SupportTheme.Celebration.gold
        case 55..<70: return SupportTheme.accent
        default: return .red
        }
    }

    private var progress: Double {
        Double(score) / 100.0
    }

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(SupportTheme.textSecondary.opacity(0.2), lineWidth: size / 10)
                .frame(width: size, height: size)

            // Progress circle
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: size / 10, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .id(reduceMotion ? score : 0)
                .transition(.opacity)
                .animation(
                    reduceMotion ? .easeInOut(duration: 0.2) : (.spring(response: 0.6, dampingFraction: 0.8)),
                    value: progress)

            // Score text
            VStack(spacing: SupportTheme.Spacing.xxs) {
                Text("\(score)")
                    .font(.system(size: size / 3, weight: .bold))

                Text("MindFriend")
                    .font(.system(size: size / 10))
                    .foregroundColor(SupportTheme.textSecondary)
            }
        }
    }
}

#Preview {
    VStack(spacing: SupportTheme.Spacing.l) {
        SleepScoreRing(score: 92, size: 120)
        SleepScoreRing(score: 75, size: 100)
        SleepScoreRing(score: 62, size: 80)
        SleepScoreRing(score: 45, size: 60)
    }
    .padding()
}
