//
//  DebtTransactionsStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Shows what activities count as deposits vs withdrawals
//

import SwiftUI

/// Step 2: Two-column layout showing deposits (green) vs withdrawals (red)
struct DebtTransactionsStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var visibleItems: Set<String> = []

    private let deposits: [(icon: String, label: String)] = [
        ("moon.stars.fill", "Quality Sleep"),
        ("figure.run", "Exercise"),
        ("person.2.fill", "Social Connection"),
        ("checkmark.seal.fill", "Quests Completed")
    ]

    private let withdrawals: [(icon: String, label: String)] = [
        ("moon.zzz.fill", "Poor Sleep"),
        ("bolt.fill", "Stress"),
        ("person.fill.xmark", "Isolation"),
        ("cloud.rain.fill", "Low Moods")
    ]

    var body: some View {
        TutorialStepLayout(
            icon: "arrow.left.arrow.right.circle.fill",
            iconColor: .purple,
            headline: "What Fills & Drains",
            subheadline: "Your daily activities affect your wellbeing balance.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            HStack(alignment: .top, spacing: 16) {
                // Deposits column
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                        Text("Deposits")
                            .font(.headline)
                            .foregroundStyle(.green)
                    }

                    ForEach(deposits, id: \.label) { item in
                        transactionRow(
                            icon: item.icon,
                            label: item.label,
                            color: .green,
                            isVisible: visibleItems.contains(item.label)
                        )
                    }
                }
                .frame(maxWidth: .infinity)

                // Divider
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1)
                    .padding(.vertical, 8)

                // Withdrawals column
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Withdrawals")
                            .font(.headline)
                            .foregroundStyle(.orange)
                    }

                    ForEach(withdrawals, id: \.label) { item in
                        transactionRow(
                            icon: item.icon,
                            label: item.label,
                            color: .orange,
                            isVisible: visibleItems.contains(item.label)
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            .onAppear {
                animateItems()
            }
        }
    }

    @ViewBuilder
    private func transactionRow(icon: String, label: String, color: Color, isVisible: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(label)
                .font(.caption)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 10)
    }

    private func animateItems() {
        let allItems = deposits.map(\.label) + withdrawals.map(\.label)
        for (index, item) in allItems.enumerated() {
            withAnimation(.easeOut(duration: 0.3).delay(Double(index) * 0.1)) {
                visibleItems.insert(item)
            }
        }
    }
}

#Preview {
    DebtTransactionsStep(onNext: {}, onSkip: {})
}
