//
//  OutcomesProgressStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: Progress tracking and goals
//

import SwiftUI

/// Step 3: Show progress tracking and goal setting
struct OutcomesProgressStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onComplete: () -> Void

    @State private var showChart = false
    @State private var animatedPoints: Int = 0

    // Simulated progress data points (lower is better for PHQ-9)
    private let progressPoints: [CGFloat] = [18, 15, 14, 11, 9, 7]
    private let months = ["Aug", "Sep", "Oct", "Nov", "Dec", "Jan"]

    var body: some View {
        TutorialStepView(
            icon: "chart.line.uptrend.xyaxis",
            iconColor: SupportTheme.accent,
            headline: "Track Your Progress",
            subheadline: "See how your scores change over time and set personal goals.",
            primaryLabel: "Get Started",
            primaryAction: onComplete
        ) {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Progress chart preview
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    HStack {
                        Text("PHQ-9 Score")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        HStack(spacing: SupportTheme.Spacing.xxs) {
                            Circle()
                                .fill(SupportTheme.accent)
                                .frame(width: 8, height: 8)
                            Text("Improving")
                                .font(.caption2)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                    }

                    // Simple line chart
                    GeometryReader { geo in
                        let width = geo.size.width
                        let height = geo.size.height
                        let maxScore: CGFloat = 20
                        let pointSpacing = width / CGFloat(progressPoints.count - 1)

                        ZStack {
                            // Grid lines
                            ForEach([5, 10, 15], id: \.self) { line in
                                Path { path in
                                    let y = height * (1 - CGFloat(line) / maxScore)
                                    path.move(to: CGPoint(x: 0, y: y))
                                    path.addLine(to: CGPoint(x: width, y: y))
                                }
                                .stroke(SupportTheme.textSecondary.opacity(0.2), lineWidth: 1)
                            }

                            // Line path
                            Path { path in
                                for (index, point) in progressPoints.prefix(animatedPoints).enumerated() {
                                    let x = CGFloat(index) * pointSpacing
                                    let y = height * (1 - point / maxScore)
                                    if index == 0 {
                                        path.move(to: CGPoint(x: x, y: y))
                                    } else {
                                        path.addLine(to: CGPoint(x: x, y: y))
                                    }
                                }
                            }
                            .stroke(
                                SupportTheme.surface,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                            )

                            // Data points
                            ForEach(0..<min(animatedPoints, progressPoints.count), id: \.self) { index in
                                let x = CGFloat(index) * pointSpacing
                                let y = height * (1 - progressPoints[index] / maxScore)
                                Circle()
                                    .fill(SupportTheme.surface)
                                    .frame(width: 10, height: 10)
                                    .overlay(
                                        Circle()
                                            .stroke(index == progressPoints.count - 1 ? SupportTheme.accent : SupportTheme.accent, lineWidth: 2)
                                    )
                                    .position(x: x, y: y)
                            }
                        }
                    }
                    .frame(height: 80)

                    // Month labels
                    HStack {
                        ForEach(months, id: \.self) { month in
                            Text(month)
                                .font(.system(.caption2))
                                .foregroundStyle(SupportTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                .padding(.horizontal, SupportTheme.Spacing.m)
                .opacity(showChart ? 1 : 0)

                // Goal indicator
                HStack(spacing: SupportTheme.Spacing.s) {
                    Image(systemName: "flag.checkered")
                        .font(.title3)
                        .foregroundStyle(SupportTheme.accent)

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text("Set a Goal")
                            .font(.subheadline.weight(.medium))
                        Text("Choose a target score to work toward")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                .padding(.horizontal, SupportTheme.Spacing.m)
                .opacity(showChart ? 1 : 0)
            }
            .onAppear {
                animateChart()
            }
        }
    }

    private func animateChart() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.3)) {
            showChart = true
        }

        for i in 1...progressPoints.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(i) * 0.2) {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.2)) {
                    animatedPoints = i
                }
            }
        }
    }
}

#Preview {
    OutcomesProgressStep(onComplete: {})
}
