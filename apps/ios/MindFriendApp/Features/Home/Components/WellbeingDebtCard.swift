//
//  WellbeingDebtCard.swift
//  MindFriendApp
//
//  N006: Wellbeing Debt Calculator - Home Card
//  Displays current debt status with navigation to full dashboard
//

import SwiftUI

/// Home card displaying wellbeing debt status
/// Taps navigate to WellbeingDebtDashboardView
struct WellbeingDebtCard: View {
    @EnvironmentObject var container: DependencyContainer

    @State private var latestScore: DebtScore?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationLink {
            WellbeingDebtDashboardView()
                .environmentObject(container)
        } label: {
            cardContent
        }
        .buttonStyle(PlainButtonStyle())
        .task {
            await loadDebtScore()
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(spacing: 16) {
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if let score = latestScore {
                debtScoreView(score)
            } else {
                noDataView
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    // MARK: - Score View

    @ViewBuilder
    private func debtScoreView(_ score: DebtScore) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Info section
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(severityColor(score.thresholdStatus.severity))
                        .frame(width: 10, height: 10)

                    Text("Wellbeing Balance")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                // Trend indicator
                HStack(spacing: 4) {
                    Image(systemName: trendIcon(score.trend.direction))
                        .font(.caption)
                    Text(trendLabel(score.trend.direction))
                        .font(.subheadline)
                }
                .foregroundStyle(trendColor(score.trend.direction))

                // Threshold status
                if score.thresholdStatus.severity != .safe {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text(score.thresholdStatus.severity.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(severityColor(score.thresholdStatus.severity))
                }

                // Velocity info
                let velocityValue = NSDecimalNumber(decimal: score.trend.velocity).doubleValue
                if abs(velocityValue) >= 0.5 {
                    Text("\(velocityValue >= 0 ? "+" : "")\(String(format: "%.1f", velocityValue)) pts/day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Score ring
            DebtScoreRing(
                score: NSDecimalNumber(decimal: score.rollingDebt14Day).intValue,
                severity: score.thresholdStatus.severity,
                size: 90
            )
        }

        // Quick stats row
        HStack(spacing: 16) {
            quickStat(label: String(localized: "7-Day"), value: score.rollingDebt7Day)
            quickStat(label: String(localized: "14-Day"), value: score.rollingDebt14Day)
            quickStat(label: String(localized: "30-Day"), value: score.rollingDebt30Day)
        }

        // View details hint
        HStack {
            Spacer()
            Text("Tap for details")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func quickStat(label: String, value: Decimal) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(NSDecimalNumber(decimal: value).intValue)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(value < 0 ? .red : value > 0 ? .green : .primary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loading/Error/Empty Views

    private var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading wellbeing data...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Unable to load debt data")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    private var noDataView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title)
                .foregroundStyle(.blue)

            Text("Wellbeing Balance")
                .font(.headline)

            Text("Start tracking to see your wellness trends")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Spacer()
                Text("Tap to get started")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    // MARK: - Helpers

    private func loadDebtScore() async {
        do {
            latestScore = try await container.wellbeingDebtService.fetchLatestDebtScore()
            isLoading = false
        } catch {
            errorMessage = "Failed to load"
            isLoading = false
        }
    }

    private func severityColor(_ severity: ThresholdSeverity) -> Color {
        switch severity {
        case .safe: return .green
        case .warning: return .orange
        case .danger: return .red
        }
    }

    private func trendIcon(_ direction: DebtTrendDirection) -> String {
        switch direction {
        case .improving: return "arrow.up.right"
        case .worsening: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    private func trendLabel(_ direction: DebtTrendDirection) -> String {
        switch direction {
        case .improving: return String(localized: "Improving")
        case .worsening: return String(localized: "Declining")
        case .stable: return String(localized: "Stable")
        }
    }

    private func trendColor(_ direction: DebtTrendDirection) -> Color {
        switch direction {
        case .improving: return .green
        case .worsening: return .orange
        case .stable: return .secondary
        }
    }
}

// MARK: - Debt Score Ring

/// Circular ring showing debt score with severity coloring
struct DebtScoreRing: View {
    let score: Int
    let severity: ThresholdSeverity
    let size: CGFloat

    @State private var animatedProgress: Double = 0

    // Debt is always 0 or positive: 0 = healthy, 50 = warning threshold, 100+ = danger
    private var normalizedProgress: Double {
        // Map 0-100 range into 0-1 for ring display
        // 0 debt = empty ring (healthy)
        // 50 debt = half ring (at threshold)
        // 100+ debt = full ring (severe)
        return min(1.0, max(0, Double(score) / 100.0))
    }

    private var ringColor: Color {
        switch severity {
        case .safe: return .green
        case .warning: return .orange
        case .danger: return .red
        }
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(ringColor.opacity(0.2), lineWidth: size * 0.1)

            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    ringColor.gradient,
                    style: StrokeStyle(
                        lineWidth: size * 0.1,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))

            // Score text
            VStack(spacing: 2) {
                Text("\(score > 0 ? "+" : "")\(score)")
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Debt")
                    .font(.system(size: size * 0.12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animatedProgress = normalizedProgress
            }
        }
    }
}

// Preview requires a DependencyContainer instance
// Use in-app for full functionality
