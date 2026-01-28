import SwiftUI

/// Card showing mood sparkline and helpful activities from wellness insights
struct WellnessInsightsCard: View {
    @ObservedObject var insightsService: WellnessInsightsService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.4))

                Text("Wellness Insights")
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))

                Spacer()
            }

            // Mood sparkline section
            if !insightsService.weeklyMoodTrend.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Week")
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundColor(.gray)

                    MoodSparkline(dataPoints: insightsService.weeklyMoodTrend)
                        .frame(height: 60)
                }
            }

            // Helpful activities section
            if !insightsService.helpfulActivities.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What's Helping")
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundColor(.gray)

                    HStack(spacing: 12) {
                        ForEach(insightsService.helpfulActivities) { activity in
                            HelpfulActivityChip(activity: activity)
                        }
                    }
                }
            }

            // Loading state
            if insightsService.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 8)
                    Spacer()
                }
            }

            // Empty state
            if !insightsService.isLoading &&
               insightsService.weeklyMoodTrend.allSatisfy({ !$0.hasMoodData }) &&
               insightsService.helpfulActivities.isEmpty {
                Text("Complete mood check-ins and exercises to see your insights")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .task {
            await insightsService.loadAll()
        }
    }
}

// MARK: - Mood Sparkline

/// Simple sparkline chart showing 7-day mood trend
struct MoodSparkline: View {
    let dataPoints: [WellnessMoodDataPoint]

    private var maxMood: Double { 5.0 }
    private var minMood: Double { 1.0 }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let pointWidth = width / CGFloat(max(1, dataPoints.count - 1))

            ZStack(alignment: .bottom) {
                // Background grid lines
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        Divider()
                            .background(Color.gray.opacity(0.1))
                        Spacer()
                    }
                    Divider()
                        .background(Color.gray.opacity(0.1))
                }

                // Line path
                if dataPoints.contains(where: { $0.hasMoodData }) {
                    Path { path in
                        var started = false
                        for (index, point) in dataPoints.enumerated() {
                            guard let mood = point.averageMood else { continue }
                            let x = CGFloat(index) * pointWidth
                            let normalizedY = CGFloat((mood - minMood) / (maxMood - minMood))
                            let y = height - (normalizedY * (height - 8)) - 4

                            if !started {
                                path.move(to: CGPoint(x: x, y: y))
                                started = true
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.2, green: 0.6, blue: 0.4),
                                Color(red: 0.3, green: 0.7, blue: 0.5)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                    // Data points
                    ForEach(Array(dataPoints.enumerated()), id: \.element.id) { index, point in
                        if let mood = point.averageMood {
                            let x = CGFloat(index) * pointWidth
                            let normalizedY = CGFloat((mood - minMood) / (maxMood - minMood))
                            let y = height - (normalizedY * (height - 8)) - 4

                            Circle()
                                .fill(Color(red: 0.2, green: 0.6, blue: 0.4))
                                .frame(width: 6, height: 6)
                                .position(x: x, y: y)
                        }
                    }
                }

                // Day labels
                HStack(spacing: 0) {
                    ForEach(dataPoints) { point in
                        Text(point.dayLabel)
                            .font(.system(size: 10, weight: .medium, design: .default))
                            .foregroundColor(.gray.opacity(0.6))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Helpful Activity Chip

/// Compact chip showing a helpful activity type
struct HelpfulActivityChip: View {
    let activity: HelpfulActivity

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: activity.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(activity.color)

            Text(activity.typeName)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(activity.color.opacity(0.1))
        )
    }
}

#Preview {
    VStack {
        WellnessInsightsCard(insightsService: WellnessInsightsService(authService: SupabaseAuthService()))
            .padding()

        Spacer()
    }
    .background(Color(red: 0.95, green: 0.97, blue: 1.0))
}
