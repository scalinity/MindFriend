import SwiftUI

/// Card showing mood sparkline and helpful activities from wellness insights
struct WellnessInsightsCard: View {
    @ObservedObject var insightsService: WellnessInsightsService

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            // Header
            HStack(spacing: SupportTheme.Spacing.xs) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(.subheadline).weight(.semibold))
                    .foregroundColor(SupportTheme.accent)

                Text("Wellness Insights")
                    .font(.system(.body, design: .default).weight(.semibold))
                    .foregroundColor(SupportTheme.accent)

                Spacer()
            }

            // Mood sparkline section
            if !insightsService.weeklyMoodTrend.isEmpty {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Your Week")
                        .font(.system(.caption, design: .default).weight(.medium))
                        .foregroundColor(SupportTheme.textSecondary)

                    MoodSparkline(dataPoints: insightsService.weeklyMoodTrend)
                        .frame(height: 60)
                }
            }

            // Helpful activities section
            if !insightsService.helpfulActivities.isEmpty {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("What's Helping")
                        .font(.system(.caption, design: .default).weight(.medium))
                        .foregroundColor(SupportTheme.textSecondary)

                    HStack(spacing: SupportTheme.Spacing.s) {
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
                        .padding(.vertical, SupportTheme.Spacing.xs)
                    Spacer()
                }
            }

            // Empty state
            if !insightsService.isLoading &&
               insightsService.weeklyMoodTrend.allSatisfy({ !$0.hasMoodData }) &&
               insightsService.helpfulActivities.isEmpty {
                Text("Complete mood check-ins and exercises to see your insights")
                    .font(.system(.caption, design: .default).weight(.regular))
                    .foregroundColor(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SupportTheme.Spacing.xs)
            }
        }
        .padding(SupportTheme.Spacing.m)
        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
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
                            .background(SupportTheme.textSecondary.opacity(0.1))
                        Spacer()
                    }
                    Divider()
                        .background(SupportTheme.textSecondary.opacity(0.1))
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
                        SupportTheme.surface,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                    // Data points
                    ForEach(Array(dataPoints.enumerated()), id: \.element.id) { index, point in
                        if let mood = point.averageMood {
                            let x = CGFloat(index) * pointWidth
                            let normalizedY = CGFloat((mood - minMood) / (maxMood - minMood))
                            let y = height - (normalizedY * (height - 8)) - 4

                            Circle()
                                .fill(SupportTheme.accent)
                                .frame(width: 6, height: 6)
                                .position(x: x, y: y)
                        }
                    }
                }

                // Day labels
                HStack(spacing: 0) {
                    ForEach(dataPoints) { point in
                        Text(point.dayLabel)
                            .font(.system(.caption2, design: .default).weight(.medium))
                            .foregroundColor(SupportTheme.textSecondary.opacity(0.6))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, SupportTheme.Spacing.xxs)
            }
        }
    }
}

// MARK: - Helpful Activity Chip

/// Compact chip showing a helpful activity type
struct HelpfulActivityChip: View {
    let activity: HelpfulActivity

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            Image(systemName: activity.icon)
                .font(.system(.caption).weight(.semibold))
                .foregroundColor(SupportTheme.accent)

            Text(activity.typeName)
                .font(.system(.caption, design: .default).weight(.medium))
                .foregroundColor(SupportTheme.accent)
        }
        .padding(.horizontal, SupportTheme.Spacing.xs)
        .padding(.vertical, SupportTheme.Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                .fill(SupportTheme.accent.opacity(0.1))
        )
    }
}

#Preview {
    VStack {
        WellnessInsightsCard(insightsService: WellnessInsightsService(authService: SupabaseAuthService()))
            .padding(SupportTheme.Spacing.m)

        Spacer()
    }
    .background(SupportTheme.canvas)
}
