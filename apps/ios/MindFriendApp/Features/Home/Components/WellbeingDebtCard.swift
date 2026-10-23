//
//  WellbeingDebtCard.swift
//  MindFriendApp
//
//  N006: Wellbeing Debt Calculator - Home Card
//  Displays current debt status with navigation to full dashboard
//

import SwiftUI

// MARK: - Notification Names

extension Notification.Name {
    static let wellbeingDebtDidRecalculate = Notification.Name("wellbeingDebtDidRecalculate")
}

/// Home card displaying wellbeing debt status
/// Taps navigate to WellbeingDebtDashboardView
struct WellbeingDebtCard: View {
    @EnvironmentObject var container: DependencyContainer
    @EnvironmentObject private var appState: AppState
    @State private var loadID = UUID()
    private let reader: (any WellbeingDebtReading)?
    init(reader: (any WellbeingDebtReading)? = nil) { self.reader = reader }
    private var service: any WellbeingDebtReading { reader ?? container.wellbeingDebtService }

    @State private var latestScore: DebtScore?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
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
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
        .task(id: appState.currentUser?.id) {
            await loadDebtScore()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await loadDebtScore() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wellbeingDebtSourcesDidChange).debounce(for: .seconds(1), scheduler: RunLoop.main)) { _ in
            Task { await loadDebtScore() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wellbeingDebtDidRecalculate)) { _ in
            Task {
                await loadDebtScore()
            }
        }
    }

    // MARK: - Score View

    @ViewBuilder
    private func debtScoreView(_ score: DebtScore) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Info section
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(score.thresholdStatus.confidence > 0 ? severityColor(score.thresholdStatus.severity) : .secondary)
                        .frame(width: 10, height: 10)

                    Text("Wellbeing Balance")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                // Trend indicator
                HStack(spacing: 4) {
                    Image(systemName: trendIcon(score.trend.direction))
                        .font(.caption)
                    Text(score.trend.available == true ? trendLabel(score.trend.direction) : "Trend unavailable")
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
                if score.trend.available == true && abs(velocityValue) >= 0.5 {
                    Text("\(velocityValue >= 0 ? "+" : "")\(String(format: "%.1f", velocityValue)) pts/day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Score ring
            DebtScoreRing(
                score: score.rollingDebt14Day,
                severity: score.thresholdStatus.confidence > 0 ? score.thresholdStatus.severity : nil,
                size: 90
            )
        }

        Text("Through \(score.date) UTC").font(.caption2).foregroundStyle(.secondary)

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
            Text(value.formatted())
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
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
            Text("Couldn’t refresh your debt score. Check your connection and tap Retry.")
            Button("Retry") { Task { await loadDebtScore() } }
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
        let requestID = UUID()
        loadID = requestID
        latestScore = nil
        errorMessage = nil
        isLoading = true
        defer { if loadID == requestID { isLoading = false } }
        do {
            let owner = try await service.transactionOwnerID()
            let score = try await service.refreshDebtScoreIfNeeded()
            let activeOwner = try await service.transactionOwnerID()
            guard loadID == requestID, !Task.isCancelled, owner == activeOwner else { return }
            latestScore = score?.userId.lowercased() == owner.lowercased() &&
                score?.isCurrentSourceCalculation(requireSnapshot: true) == true ? score : nil
        } catch {
            guard loadID == requestID, !Task.isCancelled else { return }
            errorMessage = "Failed to load"
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
    let score: Decimal
    let severity: ThresholdSeverity?
    let size: CGFloat

    @State private var animatedProgress: Double = 0

    // Debt is always 0 or positive: 0 = healthy, 50 = warning threshold, 100+ = danger
    private var normalizedProgress: Double {
        // Map 0-100 range into 0-1 for ring display
        // 0 debt = empty ring (healthy)
        // 50 debt = half ring (at threshold)
        // 100+ debt = full ring (severe)
        return min(1.0, max(0, NSDecimalNumber(decimal: score).doubleValue / 100.0))
    }

    private var ringColor: Color {
        switch severity {
        case .safe: return .green
        case .warning: return .orange
        case .danger: return .red
        case nil: return .secondary
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
                Text(score.formatted())
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
