//
//  LongitudinalYearStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: Yearly overview
//

import SwiftUI

/// Step 3: Show the yearly overview visualization
struct LongitudinalYearStep: View {
    let onComplete: () -> Void

    @State private var showYear = false
    @State private var animatedMonths: Set<Int> = []

    var body: some View {
        TutorialStepView(
            icon: "calendar",
            iconColor: .blue,
            headline: "Yearly Overview",
            subheadline: "See your entire year at a glance with our visual heatmap.",
            primaryLabel: "View Dashboard",
            primaryAction: onComplete
        ) {
            VStack(spacing: 20) {
                // Year heatmap preview
                VStack(spacing: 4) {
                    Text("2026")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    // Month grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                        ForEach(0..<12, id: \.self) { month in
                            VStack(spacing: 2) {
                                // Mini heatmap for month
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                                    ForEach(0..<35, id: \.self) { day in
                                        Rectangle()
                                            .fill(dayColor(for: day, month: month))
                                            .frame(height: 3)
                                    }
                                }

                                Text(monthNames[month])
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                            .opacity(animatedMonths.contains(month) ? 1 : 0.3)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)

                // Legend
                HStack(spacing: 16) {
                    YearStepLegendItem(color: .green, label: "Great")
                    YearStepLegendItem(color: .yellow, label: "Okay")
                    YearStepLegendItem(color: .orange, label: "Low")
                    YearStepLegendItem(color: .gray.opacity(0.3), label: "No data")
                }
                .opacity(showYear ? 1 : 0)

                // Summary
                Text("Tap any month to see detailed breakdowns")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .opacity(showYear ? 1 : 0)
            }
            .onAppear {
                animateYear()
            }
        }
    }

    private let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private func dayColor(for day: Int, month: Int) -> Color {
        if day >= 28 { return Color(.systemGray5) }

        let seed = (month * 35 + day) % 10
        switch seed {
        case 0...2: return .gray.opacity(0.3)
        case 3...5: return .orange.opacity(0.6)
        case 6...7: return .yellow.opacity(0.7)
        default: return .green.opacity(0.7)
        }
    }

    private func animateYear() {
        for month in 0..<12 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(month) * 0.08) {
                withAnimation(.easeOut(duration: 0.2)) {
                    _ = animatedMonths.insert(month)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showYear = true }
        }
    }
}

private struct YearStepLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(color)
                .frame(width: 12, height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    LongitudinalYearStep(onComplete: {})
}
