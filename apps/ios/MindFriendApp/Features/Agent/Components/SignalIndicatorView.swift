import SwiftUI

struct SignalIndicatorView: View {
    let signal: AgentSignal
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Signal Type Icon
                Image(systemName: signal.signalType.iconName)
                    .font(.title3)
                    .foregroundStyle(Color(signal.signalType.colorName))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(signal.signalType.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        SeverityBadge(severity: signal.severity)

                        Text("Confidence: \(Int(signal.confidence * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    withAnimation {
                        showDetails.toggle()
                    }
                } label: {
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }

            if showDetails {
                Divider()

                // Evidence Details
                VStack(alignment: .leading, spacing: 8) {
                    if let trend = signal.evidence.trend {
                        HStack {
                            Image(systemName: trend.direction == "up" ? "arrow.up.right" : "arrow.down.right")
                                .foregroundStyle(trend.direction == "up" ? .green : .orange)

                            Text("\(trend.direction.capitalized) trend over \(trend.durationDays) days")
                                .font(.caption)
                        }
                    }

                    if let comparison = signal.evidence.comparison {
                        HStack {
                            Image(systemName: "chart.bar")
                                .foregroundStyle(.blue)

                            let changeText = comparison.percentChange >= 0
                                ? "+\(Int(comparison.percentChange))%"
                                : "\(Int(comparison.percentChange))%"

                            Text("Change: \(changeText) from baseline")
                                .font(.caption)
                        }
                    }

                    if let dataPoints = signal.evidence.dataPoints, !dataPoints.isEmpty {
                        Text("Based on \(dataPoints.count) data points")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Detected \(timeAgo)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.leading, 40)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch severity {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
}

#Preview {
    VStack(spacing: 16) {
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
                        EvidencePoint(metric: "mood", value: 2.0, timestamp: "2024-01-22", context: nil)
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
