//
//  DebtBreakdownView.swift
//  MindFriendApp
//
//  N006: Wellbeing Debt Calculator - Transaction Breakdown
//  Displays detailed transaction history for a specific date range
//

import SwiftUI

struct DebtBreakdownView: View {
    @EnvironmentObject var container: DependencyContainer
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) var dismiss

    let debtScore: DebtScore
    private let transactionReader: (any WellbeingTransactionReading)?

    @State private var transactions: [WellbeingTransaction] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedDateRange: DateRange = .week
    @State private var displayedWindow: DebtTransactionWindow?
    @State private var loadID = UUID()

    init(debtScore: DebtScore, transactionReader: (any WellbeingTransactionReading)? = nil) {
        self.debtScore = debtScore
        self.transactionReader = transactionReader
    }

    enum DateRange: String, CaseIterable {
        case week = "7 Days"
        case twoWeeks = "14 Days"
        case month = "30 Days"

        var days: Int {
            switch self {
            case .week: return 7
            case .twoWeeks: return 14
            case .month: return 30
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Date range picker
                Picker("Range", selection: $selectedDateRange) {
                    ForEach(DateRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                if let window = displayedWindow {
                    Text("\(window.start) – \(window.end) · \(window.timezone)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                if isLoading {
                    ProgressView("Loading transactions...")
                        .padding(.top, 100)
                } else if let error = errorMessage {
                    errorView(error)
                } else if transactions.isEmpty {
                    emptyView
                } else {
                    transactionsList
                }
            }
            .navigationTitle("Transaction Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task(id: "\(selectedDateRange.days)-\(appState.currentUser?.id.uuidString ?? "signed-out")") {
                await loadTransactions()
            }
        }
    }

    // MARK: - Transactions List

    @ViewBuilder
    private var transactionsList: some View {
        List {
            Section {
                Text("Missing circle activity is not treated as social isolation. Historical inferred penalties are excluded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Summary section
            Section {
                summaryStats
            }

            // Deposits section
            if !deposits.isEmpty {
                Section("Deposits (\(deposits.count))") {
                    ForEach(deposits, id: \.id) { transaction in
                        transactionRow(transaction)
                    }
                }
            }

            // Withdrawals section
            if !withdrawals.isEmpty {
                Section("Withdrawals (\(withdrawals.count))") {
                    ForEach(withdrawals, id: \.id) { transaction in
                        transactionRow(transaction)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var summaryStats: some View {
        VStack(spacing: 16) {
            HStack {
                statCard("Deposits", value: totalDeposits, color: .green)
                statCard("Withdrawals", value: totalWithdrawals, color: .red)
            }

            Divider()

            HStack {
                Text("Net Balance")
                    .font(.headline)

                Spacer()

                Text("\(netBalance > 0 ? "+" : "")\(NSDecimalNumber(decimal: netBalance).stringValue)")
                    .font(.title2.bold())
                    .foregroundStyle(netBalance >= 0 ? .green : .red)
            }
        }
    }

    @ViewBuilder
    private func statCard(_ label: String, value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(value > 0 ? "+" : "")\(NSDecimalNumber(decimal: value).stringValue)")
                .font(.title3.bold())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func transactionRow(_ transaction: WellbeingTransaction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: transaction.type == .deposit ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(transaction.type == .deposit ? .green : .red)
                .font(.title3)

            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(formatCategory(transaction.category))
                    .font(.subheadline.bold())

                if let description = transaction.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("\(transaction.source.rawValue) • \(transaction.date)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Amount
            Text("\(transaction.type == .deposit ? "+" : "-")\(NSDecimalNumber(decimal: transaction.amount).stringValue)")
                .font(.subheadline.bold())
                .foregroundStyle(transaction.type == .deposit ? .green : .red)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty View

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Transactions")
                .font(.title2.bold())

            Text("No transactions recorded for this period.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 100)
    }

    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.red)

            Text("Error Loading Transactions")
                .font(.title2.bold())

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                Task {
                    await loadTransactions()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 100)
    }

    // MARK: - Computed Properties

    private var deposits: [WellbeingTransaction] {
        transactions.filter { $0.type == .deposit }
    }

    private var withdrawals: [WellbeingTransaction] {
        transactions.filter { $0.type == .withdrawal }
    }

    private var totalDeposits: Decimal {
        deposits.reduce(0) { $0 + $1.amount }
    }

    private var totalWithdrawals: Decimal {
        withdrawals.reduce(0) { $0 + $1.amount }
    }

    private var netBalance: Decimal {
        totalDeposits - totalWithdrawals
    }

    // MARK: - Helper Methods

    private func loadTransactions() async {
        let requestID = UUID()
        loadID = requestID
        isLoading = true
        transactions = []
        errorMessage = nil
        defer { if loadID == requestID { isLoading = false } }

        do {
            let reader = transactionReader ?? container.wellbeingDebtService
            let owner = try await reader.transactionOwnerID()
            let window = DebtTransactionWindow(days: selectedDateRange.days)
            displayedWindow = window
            let loaded: [WellbeingTransaction]
            if let snapshot = debtScore.calculationTransactions {
                guard debtScore.date == window.end, debtScore.userId.lowercased() == owner.lowercased() else {
                    throw WellbeingDebtError.needsMoreData("This calculation is out of date. Refresh the debt dashboard to view a current breakdown.")
                }
                loaded = snapshot
            } else {
                loaded = try await reader.fetchTransactions(from: window.start, to: window.end)
            }
            let activeOwner = try await reader.transactionOwnerID()
            guard loadID == requestID, !Task.isCancelled, activeOwner == owner else { return }
            transactions = window.accounted(loaded, owner: owner)
        } catch {
            guard loadID == requestID, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func formatCategory(_ category: TransactionCategory) -> String {
        category.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

#Preview {
    DebtBreakdownView(
        debtScore: DebtScore(
            id: UUID(),
            userId: "test-user",
            date: "2026-01-24",
            dailyBalance: -5,
            rollingDebt7Day: 15,
            rollingDebt14Day: 28,
            rollingDebt30Day: 45,
            trend: TrendData(
                direction: .worsening,
                velocity: -2.5,
                projection7Day: -20
            ),
            thresholdStatus: ThresholdStatus(
                currentDebt: 28,
                threshold: -50,
                severity: .warning,
                daysUntilCrash: 5,
                confidence: 0.75
            ),
            createdAt: Date()
        )
    )
    .environmentObject(DependencyContainer()).environmentObject(AppState())
}
