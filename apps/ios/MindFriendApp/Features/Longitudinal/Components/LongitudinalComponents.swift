import Charts
import SwiftUI

// MARK: - Longitudinal Filter Chip

struct LongitudinalFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, SupportTheme.Spacing.m)
                .padding(.vertical, SupportTheme.Spacing.xs)
                .background(isSelected ? SupportTheme.accent : SupportTheme.surface)
                .foregroundStyle(isSelected ? SupportTheme.onAccent : SupportTheme.textPrimary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quarter Mood Indicator

struct QuarterMoodIndicator: View {
    let quarter: Int
    let mood: Double?

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xxs) {
            Text("Q\(quarter)")
                .font(.caption2)
                .foregroundStyle(SupportTheme.textSecondary)

            if let mood = mood {
                Circle()
                    .fill(moodColor(for: mood))
                    .frame(width: 24, height: 24)
                    .overlay {
                        Text(String(format: "%.0f", mood))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(SupportTheme.textPrimary)
                    }
            } else {
                Circle()
                    .strokeBorder(SupportTheme.field, lineWidth: 1)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Text("--")
                            .font(.caption2)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
            }
        }
    }

    private func moodColor(for mood: Double) -> Color {
        if mood >= 4 { return SupportTheme.accent }
        if mood >= 3 { return SupportTheme.accent }
        if mood >= 2 { return SupportTheme.accent }
        return .red
    }
}

// MARK: - Seasonal Pattern Bar

struct SeasonalPatternBar: View {
    let patterns: SeasonalPatterns

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xs) {
            ForEach(patterns.allSeasons, id: \.name) { season in
                SeasonIndicator(
                    name: season.name,
                    value: season.value,
                    isHighest: season.name.lowercased() == patterns.highestSeason?.lowercased(),
                    isLowest: season.name.lowercased() == patterns.lowestSeason?.lowercased()
                )
            }
        }
    }
}

struct SeasonIndicator: View {
    let name: String
    let value: Double
    let isHighest: Bool
    let isLowest: Bool

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xxs) {
            // Season icon
            Image(systemName: seasonIcon)
                .font(.caption)
                .foregroundStyle(seasonColor)

            // Value bar
            GeometryReader { geometry in
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                        .fill(barColor)
                        .frame(height: geometry.size.height * CGFloat(value / 5.0))
                }
            }
            .frame(height: 40)

            // Label
            Text(name.prefix(3).uppercased())
                .font(.caption2)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var seasonIcon: String {
        switch name.lowercased() {
        case "winter": return "snowflake"
        case "spring": return "leaf"
        case "summer": return "sun.max"
        case "fall": return "wind"
        default: return "circle"
        }
    }

    private var seasonColor: Color {
        switch name.lowercased() {
        case "winter": return SupportTheme.accent
        case "spring": return SupportTheme.accent
        case "summer": return SupportTheme.accent
        case "fall": return SupportTheme.accent
        default: return SupportTheme.textSecondary
        }
    }

    private var barColor: Color {
        if isHighest { return SupportTheme.accent }
        if isLowest { return .red.opacity(0.7) }
        return SupportTheme.accent.opacity(0.6)
    }
}

// MARK: - Longitudinal Pattern Card

struct LongitudinalPatternCard: View {
    let pattern: LongitudinalPattern

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: pattern.patternIcon)
                .font(.title3)
                .foregroundStyle(patternColor)
                .frame(width: 32, height: 32)
                .background(patternColor.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(pattern.patternType.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(pattern.patternDescription)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            // Confidence badge
            Text("\(pattern.confidencePercentage)%")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, SupportTheme.Spacing.xs)
                .padding(.vertical, SupportTheme.Spacing.xxs)
                .background(confidenceColor.opacity(0.1))
                .foregroundStyle(confidenceColor)
                .clipShape(Capsule())
        }
        .padding(.vertical, SupportTheme.Spacing.xs)
    }

    private var patternColor: Color {
        switch pattern.patternType {
        case .seasonalMood: return SupportTheme.accent
        case .weeklyRhythm: return SupportTheme.accent
        case .eventResponse: return SupportTheme.accent
        case .improvementTrend: return SupportTheme.accent
        }
    }

    private var confidenceColor: Color {
        if pattern.confidence >= 0.9 { return SupportTheme.accent }
        if pattern.confidence >= 0.7 { return SupportTheme.accent }
        if pattern.confidence >= 0.5 { return SupportTheme.accent }
        return .red
    }
}

// MARK: - Life Event Row

struct LifeEventRow: View {
    let event: LifeEvent

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: event.eventType.icon)
                .font(.title3)
                .foregroundStyle(impactColor)
                .frame(width: 32, height: 32)
                .background(impactColor.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(event.eventType.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(event.formattedDate)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            Spacer()

            // Impact indicator
            if let impact = event.impactScore {
                HStack(spacing: SupportTheme.Spacing.xxs) {
                    Image(systemName: event.impactIcon)
                        .font(.caption)
                    Text(impactLabel(impact))
                        .font(.caption)
                }
                .foregroundStyle(impactColor)
            }
        }
        .padding(.vertical, SupportTheme.Spacing.xxs)
    }

    private var impactColor: Color {
        guard let score = event.impactScore else { return SupportTheme.textSecondary }
        if score > 0 { return SupportTheme.accent }
        if score < 0 { return .red }
        return SupportTheme.textSecondary
    }

    private func impactLabel(_ score: Double) -> String {
        if score > 0.5 { return "Positive" }
        if score < -0.5 { return "Challenging" }
        return "Neutral"
    }
}

// MARK: - Milestone Badge

struct MilestoneBadge: View {
    let milestone: Milestone

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: milestoneIcon)
                .font(.caption)
                .foregroundStyle(SupportTheme.Celebration.gold)

            Text(milestone.name)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, SupportTheme.Spacing.s)
        .padding(.vertical, SupportTheme.Spacing.xs)
        .background(SupportTheme.surface)
        .clipShape(Capsule())
    }

    private var milestoneIcon: String {
        switch milestone.type.lowercased() {
        case "badge": return "star.fill"
        case "streak": return "leaf.fill"
        case "completion": return "checkmark.seal.fill"
        default: return "trophy.fill"
        }
    }
}

// MARK: - Mood Trend Chart

struct MoodTrendChart: View {
    let data: [MonthlyStat]

    var body: some View {
        Chart {
            ForEach(data) { stat in
                if let mood = stat.avgMood {
                    LineMark(
                        x: .value("Month", stat.monthStart, unit: .month),
                        y: .value("Mood", mood)
                    )
                    .foregroundStyle(SupportTheme.accent)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Month", stat.monthStart, unit: .month),
                        y: .value("Mood", mood)
                    )
                    .foregroundStyle(
                        SupportTheme.surface
                    )
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Month", stat.monthStart, unit: .month),
                        y: .value("Mood", mood)
                    )
                    .foregroundStyle(SupportTheme.accent)
                    .symbolSize(30)
                }
            }
        }
        .chartYScale(domain: 1...5)
        .chartYAxis {
            AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text(moodLabel(for: intValue))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
    }

    private func moodLabel(for value: Int) -> String {
        switch value {
        case 1: return "Low"
        case 3: return "Mid"
        case 5: return "High"
        default: return ""
        }
    }
}

// MARK: - Weekly Stat Mini Card

struct WeeklyStatMiniCard: View {
    let stat: WeeklyStat

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text(stat.formattedWeekStart)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)

            HStack {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("Mood")
                        .font(.caption2)
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text(stat.formattedMood)
                        .font(.title3)
                        .accessibilityAddTraits(.isHeader)
                        .fontWeight(.semibold)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xxs) {
                    Text("Active Days")
                        .font(.caption2)
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text("\(stat.activeDays ?? 0)/7")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }

            // Activity indicator
            HStack(spacing: SupportTheme.Spacing.xxs) {
                ForEach(0..<7, id: \.self) { day in
                    Circle()
                        .fill(day < (stat.activeDays ?? 0) ? SupportTheme.accent : SupportTheme.field)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .supportCard()
        .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Trend Arrow

struct TrendArrow: View {
    let trend: MoodTrend

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            Image(systemName: iconName)
            Text(trend.rawValue.capitalized)
                .font(.caption)
        }
        .foregroundStyle(trendColor)
    }

    private var iconName: String {
        switch trend {
        case .improving: return "arrow.up.right"
        case .declining: return "arrow.down.right"
        case .stable: return "arrow.right"
        case .baseline, .insufficientData: return "minus"
        }
    }

    private var trendColor: Color {
        switch trend {
        case .improving: return SupportTheme.accent
        case .declining: return .red
        case .stable, .baseline, .insufficientData: return SupportTheme.textSecondary
        }
    }
}

// MARK: - Preview

#if DEBUG
    struct LongitudinalComponents_Previews: PreviewProvider {
        static var previews: some View {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Quarter indicators
                    HStack {
                        QuarterMoodIndicator(quarter: 1, mood: 3.5)
                        QuarterMoodIndicator(quarter: 2, mood: 4.2)
                        QuarterMoodIndicator(quarter: 3, mood: nil)
                        QuarterMoodIndicator(quarter: 4, mood: 3.8)
                    }

                    // Trend arrows
                    HStack(spacing: SupportTheme.Spacing.l) {
                        TrendArrow(trend: .improving)
                        TrendArrow(trend: .declining)
                        TrendArrow(trend: .stable)
                    }
                }
                .padding()
            }
        }
    }
#endif
