import SwiftUI

/// Circular progress ring showing sleep score
struct SleepScoreRing: View {
    let score: Int
    let size: CGFloat

    private var color: Color {
        switch score {
        case 85...100: return .green
        case 70..<85: return .yellow
        case 55..<70: return .orange
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
                .stroke(Color.gray.opacity(0.2), lineWidth: size / 10)
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
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)

            // Score text
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: size / 3, weight: .bold))

                Text("Score")
                    .font(.system(size: size / 10))
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SleepScoreRing(score: 92, size: 120)
        SleepScoreRing(score: 75, size: 100)
        SleepScoreRing(score: 62, size: 80)
        SleepScoreRing(score: 45, size: 60)
    }
    .padding()
}
