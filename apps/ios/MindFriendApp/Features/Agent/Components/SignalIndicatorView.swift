import SwiftUI

struct SignalIndicatorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let signal: AgentSignal
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            HStack {
                // Signal Type Icon
                Image(systemName: signal.signalType.iconName)
                    .font(.title3)
                    .foregroundStyle(SupportTheme.accent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(signal.signalType.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: SupportTheme.Spacing.xs) {
                        SeverityBadge(severity: signal.severity)

                        Text("Confidence: \(Int(signal.confidence * 100))%")
                            .font(.caption2)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }

                Spacer()

                Button {
                    withAnimation(reduceMotion ? nil : .default) {
                        showDetails.toggle()
                    }
                } label: {
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                .accessibilityLabel(showDetails ? "Hide details" : "Show details")
            }

            if showDetails {
                Divider()

                // Evidence Details
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    if let trend = signal.evidence.trend {
                        HStack {
                            Image(systemName: trend.direction == "up" ? "arrow.up.right" : "arrow.down.right")
                                .foregroundStyle(trend.direction == "up" ? SupportTheme.accent : SupportTheme.accent)

                            Text("\(trend.direction.capitalized) trend over \(trend.durationDays) days")
                                .font(.caption)
                        }
                    }

                    if let comparison = signal.evidence.comparison {
                        HStack {
                            Image(systemName: "chart.bar")
                                .foregroundStyle(SupportTheme.accent)

                            let changeText =
                                comparison.percentChange >= 0
                                ? "+\(Int(comparison.percentChange))%"
                                : "\(Int(comparison.percentChange))%"

                            Text("Change: \(changeText) from baseline")
                                .font(.caption)
                        }
                    }

                    if let dataPoints = signal.evidence.dataPoints, !dataPoints.isEmpty {
                        Text("Based on \(dataPoints.count) data points")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Text("Detected \(timeAgo)")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .padding(.leading, SupportTheme.Spacing.xl)
            }
        }
        .supportCard()
    }

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: signal.detectedAt, relativeTo: Date())
    }
}

struct SeverityBadge: View {
    let severity: Severity

    var body: some View {
        Text(severity.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, SupportTheme.Spacing.xs)
            .padding(.vertical, SupportTheme.Spacing.xxs)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch severity {
        case .low: return SupportTheme.accent
        case .medium: return SupportTheme.Celebration.gold
        case .high: return SupportTheme.accent
        case .critical: return .red
        }
    }
}

#Preview {
    VStack(spacing: SupportTheme.Spacing.m) {
        SignalIndicatorView(
            signal: AgentSignal(
                id: UUID(),
                userId: UUID(),
                signalType: .moodDecline,
                severity: .medium,
                confidence: 0.85,
                evidence: SignalEvidence(
                    dataPoints: [
                        EvidencePoint(metric: "mood", value: 3.0, timestamp: "2024-01-20", context: nil),
                        EvidencePoint(metric: "mood", value: 2.5, timestamp: "2024-01-21", context: nil),
                        EvidencePoint(metric: "mood", value: 2.0, timestamp: "2024-01-22", context: nil),
                    ],
                    trend: TrendInfo(direction: "down", magnitude: 0.5, durationDays: 3),
                    comparison: ComparisonInfo(baseline: 3.5, current: 2.0, percentChange: -43)
                ),
                detectedAt: Date().addingTimeInterval(-3600),
                expiresAt: nil,
                isResolved: false,
                resolvedAt: nil,
                resolutionType: nil,
                createdAt: Date().addingTimeInterval(-3600)
            )
        )

        SignalIndicatorView(
            signal: AgentSignal(
                id: UUID(),
                userId: UUID(),
                signalType: .positiveMomentum,
                severity: .low,
                confidence: 0.75,
                evidence: SignalEvidence(
                    dataPoints: nil,
                    trend: TrendInfo(direction: "up", magnitude: 0.3, durationDays: 7),
                    comparison: nil
                ),
                detectedAt: Date().addingTimeInterval(-7200),
                expiresAt: nil,
                isResolved: false,
                resolvedAt: nil,
                resolutionType: nil,
                createdAt: Date().addingTimeInterval(-7200)
            )
        )
    }
    .padding()
}
