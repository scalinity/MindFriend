//
//  LongitudinalYearStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: Yearly overview
//

import SwiftUI

/// Step 3: Show the yearly overview visualization
struct LongitudinalYearStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onComplete: () -> Void

    @State private var showYear = false
    @State private var animatedMonths: Set<Int> = []

    var body: some View {
        TutorialStepView(
            icon: "calendar",
            iconColor: SupportTheme.accent,
            headline: "Yearly Overview",
            subheadline: "See your entire year at a glance with our visual heatmap.",
            primaryLabel: "View Dashboard",
            primaryAction: onComplete
        ) {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Year heatmap preview
                VStack(spacing: SupportTheme.Spacing.xxs) {
                    Text("2026")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SupportTheme.textSecondary)

                    // Month grid
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: SupportTheme.Spacing.xxs), count: 6),
                        spacing: SupportTheme.Spacing.xxs
                    ) {
                        ForEach(0..<12, id: \.self) { month in
                            VStack(spacing: SupportTheme.Spacing.xxs) {
                                // Mini heatmap for month
                                LazyVGrid(
                                    columns: Array(
                                        repeating: GridItem(.flexible(), spacing: SupportTheme.Spacing.xxs), count: 7),
                                    spacing: 1
                                ) {
                                    ForEach(0..<35, id: \.self) { day in
                                        Rectangle()
                                            .fill(dayColor(for: day, month: month))
                                            .frame(height: 3)
                                    }
                                }

                                Text(monthNames[month])
                                    .font(.system(size: 8))
                                    .foregroundStyle(SupportTheme.textSecondary)
                            }
                            .opacity(animatedMonths.contains(month) ? 1 : 0.3)
                        }
                    }
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                .padding(.horizontal, SupportTheme.Spacing.l)

                // Legend
                HStack(spacing: SupportTheme.Spacing.s) {
                    YearStepLegendItem(color: SupportTheme.accent, label: "Great")
                    YearStepLegendItem(color: SupportTheme.Celebration.gold, label: "Okay")
                    YearStepLegendItem(color: SupportTheme.accent, label: "Low")
                    YearStepLegendItem(color: SupportTheme.textSecondary.opacity(0.3), label: "No data")
                }
                .opacity(showYear ? 1 : 0)

                // Summary
                Text("Tap any month to see detailed breakdowns")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .opacity(showYear ? 1 : 0)
            }
            .onAppear {
                animateYear()
            }
        }
    }

    private let monthNames = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    private func dayColor(for day: Int, month: Int) -> Color {
        if day >= 28 { return SupportTheme.field }

        let seed = (month * 35 + day) % 10
        switch seed {
        case 0...2: return SupportTheme.textSecondary.opacity(0.3)
        case 3...5: return SupportTheme.accent.opacity(0.6)
        case 6...7: return SupportTheme.Celebration.gold.opacity(0.7)
        default: return SupportTheme.accent.opacity(0.7)
        }
    }

    private func animateYear() {
        for month in 0..<12 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(month) * 0.08) {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : (.easeOut(duration: 0.2))) {
                    _ = animatedMonths.insert(month)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .default) { showYear = true }
        }
    }
}

private struct YearStepLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            Rectangle()
                .fill(color)
                .frame(width: 12, height: 12)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
            Text(label)
                .font(.caption2)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }
}

#Preview {
    LongitudinalYearStep(onComplete: {})
}
