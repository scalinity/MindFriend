import SwiftUI

/// A subtle, non-alarming card that shows current wellness insights
/// Designed to be encouraging rather than clinical
struct RiskInsightCard: View {
    let assessment: RiskAssessment?
    let onTap: (() -> Void)?

    @State private var isAnimating = false

    init(assessment: RiskAssessment?, onTap: (() -> Void)? = nil) {
        self.assessment = assessment
        self.onTap = onTap
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            content
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        HStack(spacing: 16) {
            // Wellness indicator (subtle orb)
            wellnessOrb

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let assessment {
                    HStack(spacing: 4) {
                        if let trend = assessment.predictedTrend7d {
                            Image(systemName: trend.icon)
                                .font(.caption)
                                .foregroundStyle(trend.color)
                        }
                        Text(subtitleText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Tap to learn more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
    }

    private var wellnessOrb: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(orbColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .animation(
                    .easeInOut(duration: 2)
                    .repeatForever(autoreverses: true),
                    value: isAnimating
                )

            // Inner circle with icon
            Circle()
                .fill(orbColor.opacity(0.3))
                .frame(width: 36, height: 36)

            Image(systemName: orbIcon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(orbColor)
        }
        .onAppear { isAnimating = true }
    }

    private var orbColor: Color {
        guard let assessment else { return .blue }

        switch assessment.riskLevel {
        case .low:
            return .green
        case .medium:
            return .yellow
        case .high:
            return .orange
        case .crisis:
            return .pink
        }
    }

    private var orbIcon: String {
        guard let assessment else { return "heart.fill" }

        switch assessment.riskLevel {
        case .low:
            return "checkmark.circle.fill"
        case .medium:
            return "sun.max.fill"
        case .high:
            return "heart.fill"
        case .crisis:
            return "heart.fill"
        }
    }

    private var titleText: String {
        guard let assessment else { return "Wellness Insights" }
        return assessment.riskLevel.description
    }

    private var subtitleText: String {
        guard let assessment else { return "Enable to see your patterns" }

        if let trend = assessment.predictedTrend7d {
            return trend.description
        }

        if !assessment.topFactors.isEmpty {
            return assessment.topFactors.first ?? ""
        }

        return "Updated \(assessment.timeAgo)"
    }

    private var cardBackground: some View {
        Group {
            if let assessment {
                LinearGradient(
                    colors: [
                        assessment.riskLevel.color.opacity(0.1),
                        Color(.secondarySystemBackground)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                Color(.secondarySystemBackground)
            }
        }
    }
}

// MARK: - Compact Variant

struct RiskInsightCompact: View {
    let assessment: RiskAssessment?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor.opacity(0.3))
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        guard let assessment else { return .gray }
        return assessment.riskLevel.color
    }

    private var statusText: String {
        guard let assessment else { return "Wellness tracking off" }
        return assessment.riskLevel.description
    }
}

// MARK: - Preview

#Preview("With Assessment") {
    VStack(spacing: 16) {
        RiskInsightCard(
            assessment: RiskAssessment(
                id: UUID(),
                userId: UUID(),
                assessedAt: Date(),
                riskScore: 15,
                riskLevel: .low,
                factors: .empty,
                topFactors: ["Consistent mood", "Regular check-ins"],
                predictedMood24h: 7.5,
                predictedTrend7d: .improving,
                modelVersion: "v1.0.0",
                confidence: 0.85,
                dailySignalId: nil,
                interventionTriggered: false
            )
        ) {
            print("Tapped")
        }

        RiskInsightCard(
            assessment: RiskAssessment(
                id: UUID(),
                userId: UUID(),
                assessedAt: Date().addingTimeInterval(-3600),
                riskScore: 35,
                riskLevel: .medium,
                factors: .empty,
                topFactors: ["Mood has been variable"],
                predictedMood24h: 5.5,
                predictedTrend7d: .stable,
                modelVersion: "v1.0.0",
                confidence: 0.75,
                dailySignalId: nil,
                interventionTriggered: false
            )
        )

        RiskInsightCard(assessment: nil)
    }
    .padding()
}

#Preview("Compact") {
    VStack(spacing: 8) {
        RiskInsightCompact(
            assessment: RiskAssessment(
                id: UUID(),
                userId: UUID(),
                assessedAt: Date(),
                riskScore: 15,
                riskLevel: .low,
                factors: .empty,
                topFactors: [],
                predictedMood24h: nil,
                predictedTrend7d: nil,
                modelVersion: "v1.0.0",
                confidence: nil,
                dailySignalId: nil,
                interventionTriggered: false
            )
        )

        RiskInsightCompact(assessment: nil)
    }
    .padding()
}
