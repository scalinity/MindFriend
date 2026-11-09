//
//  DebtTransactionsStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Shows what activities count as deposits vs withdrawals
//

import SwiftUI

/// Step 2: Two-column layout showing deposits (green) vs withdrawals (red)
struct DebtTransactionsStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var visibleItems: Set<String> = []

    private let deposits: [(icon: String, label: String)] = [
        ("moon.stars.fill", "Quality Sleep"),
        ("figure.run", "Exercise"),
        ("person.2.fill", "Social Connection"),
        ("checkmark.seal.fill", "Quests Completed"),
    ]

    private let withdrawals: [(icon: String, label: String)] = [
        ("moon.zzz.fill", "Poor Sleep"),
        ("bolt.fill", "Stress"),
        ("person.fill.xmark", "Isolation"),
        ("cloud.rain.fill", "Low Moods"),
    ]

    var body: some View {
        TutorialStepLayout(
            icon: "arrow.left.arrow.right.circle.fill",
            iconColor: SupportTheme.accent,
            headline: "What Fills & Drains",
            subheadline: "Your daily activities affect your wellbeing balance.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            HStack(alignment: .top, spacing: SupportTheme.Spacing.m) {
                // Deposits column
                VStack(spacing: SupportTheme.Spacing.xs) {
                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.accent)
                        Text("Deposits")
                            .font(.subheadline.bold())
                            .foregroundStyle(SupportTheme.accent)
                    }

                    ForEach(deposits, id: \.label) { item in
                        transactionRow(
                            icon: item.icon,
                            label: item.label,
                            color: SupportTheme.accent,
                            isVisible: visibleItems.contains(item.label)
                        )
                    }
                }
                .frame(maxWidth: .infinity)

                // Divider
                Rectangle()
                    .fill(SupportTheme.separator)
                    .frame(width: 1)
                    .padding(.vertical, SupportTheme.Spacing.xs)

                // Withdrawals column
                VStack(spacing: SupportTheme.Spacing.xs) {
                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        Image(systemName: "minus.circle.fill")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.accent)
                        Text("Withdrawals")
                            .font(.subheadline.bold())
                            .foregroundStyle(SupportTheme.accent)
                    }

                    ForEach(withdrawals, id: \.label) { item in
                        transactionRow(
                            icon: item.icon,
                            label: item.label,
                            color: SupportTheme.accent,
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
        HStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(minWidth: 20)

            Text(label)
                .font(.caption2)
                .foregroundStyle(SupportTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.vertical, SupportTheme.Spacing.xxs)
        .padding(.horizontal, SupportTheme.Spacing.xs)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
        .opacity(isVisible ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (isVisible ? 0 : 10))
    }

    private func animateItems() {
        let allItems = deposits.map(\.label) + withdrawals.map(\.label)
        for (index, item) in allItems.enumerated() {
            _ = withAnimation(
                reduceMotion ? .easeInOut(duration: 0.2) : (.easeOut(duration: 0.3).delay(Double(index) * 0.1))
            ) {
                visibleItems.insert(item)
            }
        }
    }
}

#Preview {
    DebtTransactionsStep(onNext: {}, onSkip: {})
}
