import SwiftUI

/// Displays daily wellness score with visual ring indicator
/// MVP implementation showing score placeholder until backend integration complete
struct WellnessScoreCard: View {
    let score: Int // 0-100
    let confidence: Int // 0-100
    let trend: [Int] // Last 7 days
    let delta: Int? // Change from yesterday

    @State private var showBreakdown = false

    /// Mock initializer for development
    init(score: Int = 75, confidence: Int = 85, trend: [Int] = [68, 72, 70, 73, 71, 75, 75], delta: Int? = 2) {
        self.score = score
        self.confidence = confidence
        self.trend = trend
        self.delta = delta
    }

    private var colorZone: ColorZone {
        switch score {
        case 0..<40: return .low
        case 40..<70: return .medium
        default: return .high
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                // Score information
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today's Wellness")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    if let delta = delta {
                        HStack(spacing: 4) {
                            Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption)
                            Text("\(delta >= 0 ? "+" : "")\(delta) from yesterday")
                                .font(.subheadline)
                        }
                        .foregroundStyle(delta >= 0 ? .green : .orange)
                    }

                    Text(colorZone.label)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if confidence < 80 {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                            Text("Confidence: \(confidence)%")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Score ring
                WellnessScoreRing(score: score, colorZone: colorZone, size: 100)
            }

            // 7-day trend sparkline
            if !trend.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("7-Day Trend")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    MiniTrendLine(scores: trend)
                        .frame(height: 40)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        .onTapGesture {
            showBreakdown = true
        }
        .sheet(isPresented: $showBreakdown) {
            ScoreBreakdownPlaceholder(score: score)
        }
    }
}

/// Circular progress ring showing wellness score
struct WellnessScoreRing: View {
    let score: Int
    let colorZone: ColorZone
    let size: CGFloat

    @State private var animatedProgress: Double = 0

    private var progress: Double {
        Double(score) / 100.0
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(colorZone.color.opacity(0.2), lineWidth: size * 0.12)

            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    colorZone.color.gradient,
                    style: StrokeStyle(
                        lineWidth: size * 0.12,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))

            // Score text
            VStack(spacing: size * 0.02) {
                Text("\(score)")
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Wellness")
                    .font(.system(size: size * 0.12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animatedProgress = progress
            }
        }
    }
}

/// Mini trend line showing 7-day score history
struct MiniTrendLine: View {
    let scores: [Int]

    var body: some View {
        GeometryReader { geometry in
            let maxScore = max(scores.max() ?? 100, 100)
            let minScore = scores.min() ?? 0  // Fixed: removed incorrect min() wrapper
            let range = max(maxScore - minScore, 20)
            let width = geometry.size.width
            let height = geometry.size.height
            let stepX = width / CGFloat(max(scores.count - 1, 1))

            Path { path in
                for (index, score) in scores.enumerated() {
                    let x = CGFloat(index) * stepX
                    let normalizedScore = CGFloat(score - minScore) / CGFloat(range)
                    let y = height - (normalizedScore * height)

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.blue.gradient, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // Fill area under line
            Path { path in
                for (index, score) in scores.enumerated() {
                    let x = CGFloat(index) * stepX
                    let normalizedScore = CGFloat(score - minScore) / CGFloat(range)
                    let y = height - (normalizedScore * height)

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: height))
                        path.addLine(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                path.addLine(to: CGPoint(x: width, y: height))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [Color.blue.opacity(0.3), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

/// Placeholder breakdown view (MVP)
struct ScoreBreakdownPlaceholder: View {
    let score: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Overall score display
                VStack(spacing: 8) {
                    WellnessScoreRing(score: score, colorZone: colorZoneForScore(score), size: 140)

                    Text(labelForScore(score))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(colorForScore(score))
                }
                .padding(.top)

                // Component breakdown placeholder
                VStack(alignment: .leading, spacing: 16) {
                    Text("What Contributed")
                        .font(.headline)

                    Text("Component breakdown will be available once backend integration is complete.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer()
            }
            .padding()
            .navigationTitle("Wellness Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func colorZoneForScore(_ score: Int) -> ColorZone {
        switch score {
        case 0..<40: return .low
        case 40..<70: return .medium
        default: return .high
        }
    }

    private func labelForScore(_ score: Int) -> String {
        colorZoneForScore(score).label
    }

    private func colorForScore(_ score: Int) -> Color {
        colorZoneForScore(score).color
    }
}

#Preview {
    WellnessScoreCard()
}
