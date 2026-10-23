//
//  WellbeingDebtDashboardView.swift
//  MindFriendApp
//
//  N006: Wellbeing Debt Calculator - Main Dashboard
//  Displays current debt status, trend, and threshold warnings
//

import SwiftUI

struct WellbeingDebtDashboardView: View {
    @EnvironmentObject var container: DependencyContainer
    @EnvironmentObject private var appState: AppState
    private let reader: (any WellbeingDebtReading)?
    @State private var loadID = UUID()
    @State private var needsRefresh = false

    init(reader: (any WellbeingDebtReading)? = nil) { self.reader = reader }
    private var service: any WellbeingDebtReading { reader ?? container.wellbeingDebtService }
    @Environment(\.dismiss) var dismiss

    @State private var latestScore: DebtScore?
    @State private var profile: WellbeingDebtProfile?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingBreakdown = false
    @State private var showingRecoveryProgram = false
    @State private var hasActiveRecoveryProgram = false
    @State private var isCalculating = false
    @State private var calculationProgress: String?
    @State private var isRecalculating = false
    @State private var recalculationProgress: String?

    // Tutorial state
    @AppStorage("wellbeing_debt_tutorial_completed") private var tutorialCompleted = false
    @State private var showingTutorial = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    ProgressView("Loading debt status...")
                        .padding(.top, 100)
                } else if let error = errorMessage {
                    errorView(error)
                } else if let score = latestScore {
                    VStack(spacing: 24) {
                        // Main status card
                        statusCard(score)

                        // Trend indicator
                        trendCard(score.trend)

                        // Threshold warning (if danger/warning)
                        if score.thresholdStatus.severity != .safe {
                            thresholdWarningCard(score.thresholdStatus)
                        }

                        // Quick stats
                        quickStatsSection(score)

                        // Action buttons
                        actionButtons
                    }
                    .padding()
                } else {
                    noDataView
                }
            }
            .navigationTitle("Wellbeing Debt")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingBreakdown = true
                        } label: {
                            Label("View Breakdown", systemImage: "chart.bar")
                        }
                        .disabled(latestScore == nil)

                        Button {
                            Task {
                                await loadData()
                            }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }

                        Divider()

                        Button {
                            Task {
                                await recalculateFromHistory()
                            }
                        } label: {
                            Label("Recalculate from History", systemImage: "arrow.counterclockwise.circle")
                        }
                        .disabled(isRecalculating)

                        Divider()

                        Button {
                            showingTutorial = true
                        } label: {
                            Label("View Tutorial", systemImage: "questionmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingBreakdown) {
                if let score = latestScore {
                    DebtBreakdownView(debtScore: score)
                        .environmentObject(container)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("No Data Available")
                            .font(.headline)
                        Text("Please try again after loading your debt status.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Close") {
                            showingBreakdown = false
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
            }
            .sheet(isPresented: $showingRecoveryProgram) {
                RecoveryProgramView()
                    .environmentObject(container)
            }
            .task(id: appState.currentUser?.id) {
                await loadData()
            }
            .overlay {
                if isRecalculating {
                    recalculatingOverlay
                }
            }
            .onAppear {
                // Show tutorial on first access
                if !tutorialCompleted {
                    showingTutorial = true
                }
            }
            .fullScreenCover(isPresented: $showingTutorial) {
                WellbeingDebtTutorialFlow(onComplete: {
                    tutorialCompleted = true
                    showingTutorial = false
                })
                .environmentObject(container)
            }
        }
    }

    // MARK: - Recalculating Overlay

    @ViewBuilder
    private var recalculatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("Recalculating")
                    .font(.headline)
                    .foregroundStyle(.white)

                if let progress = recalculationProgress {
                    Text(progress)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Status Card

    @ViewBuilder
    private func statusCard(_ score: DebtScore) -> some View {
        VStack(spacing: 16) {
            // Severity indicator
            HStack {
                Circle()
                    .fill(score.thresholdStatus.confidence > 0 ? severityColor(score.thresholdStatus.severity) : .secondary)
                    .frame(width: 12, height: 12)

                Text(score.thresholdStatus.confidence > 0 ? score.thresholdStatus.severity.displayName : "Reference threshold · limited history")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(score.thresholdStatus.confidence > 0 ? severityColor(score.thresholdStatus.severity) : .primary)

                Spacer()

                Text("Through \(score.date) UTC")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Main debt indicator
            VStack(spacing: 8) {
                Text(score.rollingDebt14Day.formatted())
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(score.thresholdStatus.confidence > 0 ? severityColor(score.thresholdStatus.severity) : .primary)

                Text("14-Day Debt Score")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            // Threshold progress bar
            if let threshold = score.thresholdStatus.threshold, threshold != 0 {
                thresholdProgressBar(
                    current: score.thresholdStatus.currentDebt,
                    threshold: threshold
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func thresholdProgressBar(current: Decimal, threshold: Decimal) -> some View {
        let progress = min(1.0, Double(truncating: current as NSDecimalNumber) / abs(Double(truncating: threshold as NSDecimalNumber)))

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reference Threshold")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                        .clipShape(Capsule())

                    Rectangle()
                        .fill(progressGradient(progress))
                        .frame(width: geometry.size.width * progress, height: 8)
                        .clipShape(Capsule())
                }
            }
            .frame(height: 8)
        }
    }

    private func progressGradient(_ progress: Double) -> LinearGradient {
        if progress < 0.7 {
            return LinearGradient(colors: [.green, .green], startPoint: .leading, endPoint: .trailing)
        } else if progress < 0.9 {
            return LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
        } else {
            return LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
        }
    }

    // MARK: - Trend Card

    @ViewBuilder
    private func trendCard(_ trend: TrendData) -> some View {
        HStack(spacing: 16) {
            Image(systemName: trend.available == true ? trendIcon(trend.direction) : "clock")
                .font(.title2)
                .foregroundStyle(trend.available == true ? trendColor(trend.direction) : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                if trend.available == true {
                    Text("Trend: \(trend.direction.rawValue.capitalized)")
                        .font(.headline)

                    Text("Velocity: \(String(format: "%.1f", Double(truncating: trend.velocity as NSDecimalNumber))) pts/day")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("7-day trend estimate: \(trend.projection7Day.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Based on \(trend.observedDays ?? 0) recorded days; an estimate, not a forecast of your health.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Trend unavailable").font(.headline)
                    Text("Record activity on at least two days to estimate a trend.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func trendIcon(_ direction: DebtTrendDirection) -> String {
        switch direction {
        case .improving: return "arrow.up.right.circle.fill"
        case .worsening: return "arrow.down.right.circle.fill"
        case .stable: return "arrow.right.circle.fill"
        }
    }

    private func trendColor(_ direction: DebtTrendDirection) -> Color {
        switch direction {
        case .improving: return .green
        case .worsening: return .red
        case .stable: return .blue
        }
    }

    // MARK: - Threshold Warning

    @ViewBuilder
    private func thresholdWarningCard(_ status: ThresholdStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                Text(status.severity == .danger ? "Action Needed" : "Approaching Threshold")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            if let days = status.daysUntilCrash, days > 0 {
                Text("If this recorded trend continues, the reference threshold may be reached in \(days) \(days == 1 ? "day" : "days"). This is an estimate.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                showingRecoveryProgram = true
            } label: {
                Text(hasActiveRecoveryProgram ? "View Recovery Program" : "Start Recovery Program")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(hasActiveRecoveryProgram ? Color.green : Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Quick Stats

    @ViewBuilder
    private func quickStatsSection(_ score: DebtScore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rolling Debts")
                .font(.headline)

            HStack(spacing: 16) {
                statPill(String(localized: "7-Day"), value: score.rollingDebt7Day)
                statPill(String(localized: "14-Day"), value: score.rollingDebt14Day)
                statPill(String(localized: "30-Day"), value: score.rollingDebt30Day)
            }
        }
    }

    @ViewBuilder
    private func statPill(_ label: String, value: Decimal) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value.formatted())
                .font(.title3.bold())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                showingBreakdown = true
            } label: {
                Label("View Transaction Breakdown", systemImage: "chart.bar.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if let profile = profile, !profile.topDrains.categories.isEmpty {
                NavigationLink {
                    topDrainsView(profile)
                } label: {
                    Label("Top Drains Analysis", systemImage: "chart.line.downtrend.xyaxis")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    @ViewBuilder
    private func topDrainsView(_ profile: WellbeingDebtProfile) -> some View {
        List {
            Section("Top Drains (Last 30 Days)") {
                ForEach(profile.topDrains.categories, id: \.category) { stat in
                    HStack {
                        Text(stat.category)
                        Spacer()
                        Text("\(Int(truncating: stat.totalAmount as NSDecimalNumber)) pts")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Top Deposits (Last 30 Days)") {
                ForEach(profile.topDeposits.categories, id: \.category) { stat in
                    HStack {
                        Text(stat.category)
                        Spacer()
                        Text("+\(Int(truncating: stat.totalAmount as NSDecimalNumber)) pts")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .navigationTitle("Category Analysis")
    }

    // MARK: - No Data View

    @ViewBuilder
    private var noDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text(needsRefresh ? "Calculation Needs Updating" : "No Debt Data Yet")
                .font(.title2.bold())

            Text("Calculate from recorded sleep, completed activities and logged events for the last 30 complete UTC days. Missing data adds no event.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let progress = calculationProgress {
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            Button {
                Task {
                    await calculateNow()
                }
            } label: {
                if isCalculating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .frame(width: 16, height: 16)
                        Text("Analyzing...")
                    }
                } else {
                    Label("Analyze History", systemImage: "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCalculating)
            .padding(.top, 8)
        }
        .padding(.top, 100)
    }

    private func calculateNow() async {
        isCalculating = true
        let requestID = UUID()
        loadID = requestID
        errorMessage = nil
        calculationProgress = nil

        defer { isCalculating = false; calculationProgress = nil }
        do {
            // Step 1: Backfill transactions from historical data
            calculationProgress = "Detecting transactions from mood history..."
            let transactionCount = try await service.backfillTransactions(days: 30)

            // Step 2: Calculate debt score
            calculationProgress = "Found \(transactionCount) transactions. Calculating score..."
            let score = try await service.calculateDebtScore(for: nil)

            // Step 3: Fetch profile
            let loadedProfile = try await service.fetchProfile()
            let owner = try await service.transactionOwnerID()
            guard loadID == requestID, !Task.isCancelled, score.userId.lowercased() == owner.lowercased() else { return }
            latestScore = score
            profile = loadedProfile
            needsRefresh = false
            calculationProgress = nil

            // Notify WellbeingDebtCard to refresh
            NotificationCenter.default.post(name: .wellbeingDebtDidRecalculate, object: nil)
        } catch {
            guard loadID == requestID, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            calculationProgress = nil
        }

        isCalculating = false
    }

    private func recalculateFromHistory() async {
        isRecalculating = true
        recalculationProgress = "Scanning mood history..."
        let requestID = UUID()
        loadID = requestID
        errorMessage = nil

        defer { isRecalculating = false; recalculationProgress = nil }
        do {
            // Step 1: Backfill transactions from historical data (past 30 days)
            let transactionCount = try await service.backfillTransactions(days: 30)

            // Step 2: Calculate debt score
            recalculationProgress = "Found \(transactionCount) transactions.\nCalculating debt score..."
            let score = try await service.calculateDebtScore(for: nil)

            // Step 3: Fetch profile
            recalculationProgress = "Updating profile..."
            let loadedProfile = try await service.fetchProfile()
            let owner = try await service.transactionOwnerID()
            guard loadID == requestID, !Task.isCancelled, score.userId.lowercased() == owner.lowercased() else { return }
            latestScore = score
            profile = loadedProfile
            needsRefresh = false

            // Notify WellbeingDebtCard to refresh
            NotificationCenter.default.post(name: .wellbeingDebtDidRecalculate, object: nil)
        } catch {
            guard loadID == requestID, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }

        isRecalculating = false
        recalculationProgress = nil
    }

    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.red)

            Text("Error Loading Data")
                .font(.title2.bold())

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                Task {
                    await loadData()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 100)
    }

    // MARK: - Helper Methods

    private func severityColor(_ severity: ThresholdSeverity) -> Color {
        switch severity {
        case .safe: return .green
        case .warning: return .orange
        case .danger: return .red
        }
    }

    private func loadData() async {
        let requestID = UUID()
        loadID = requestID
        isLoading = true
        errorMessage = nil
        latestScore = nil
        profile = nil
        needsRefresh = false
        defer { if loadID == requestID { isLoading = false } }
        do {
            let owner = try await service.transactionOwnerID()
            async let scoreTask = service.fetchLatestDebtScore()
            async let profileTask = service.fetchProfile()
            async let recoveryTask = service.fetchActiveRecoveryProgram()
            let (score, loadedProfile, recovery) = try await (scoreTask, profileTask, recoveryTask)
            let activeOwner = try await service.transactionOwnerID()
            guard loadID == requestID, !Task.isCancelled, activeOwner == owner else { return }
            if let score, score.userId.lowercased() == owner.lowercased() {
                needsRefresh = !score.isCurrentSourceCalculation(requireSnapshot: true)
                latestScore = needsRefresh ? nil : score
            }
            profile = loadedProfile?.userId.lowercased() == owner.lowercased() ? loadedProfile : nil
            hasActiveRecoveryProgram = recovery?.userId.lowercased() == owner.lowercased()
        } catch {
            guard loadID == requestID, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

}

#Preview {
    NavigationStack {
        WellbeingDebtDashboardView()
            .environmentObject(DependencyContainer()).environmentObject(AppState())
    }
}
