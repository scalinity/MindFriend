//
//  OutcomesProgressStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: Progress tracking and goals
//

import SwiftUI

/// Step 3: Show progress tracking and goal setting
struct OutcomesProgressStep: View {
    let onComplete: () -> Void

    @State private var showChart = false
    @State private var animatedPoints: Int = 0

    // Simulated progress data points (lower is better for PHQ-9)
    private let progressPoints: [CGFloat] = [18, 15, 14, 11, 9, 7]
    private let months = ["Aug", "Sep", "Oct", "Nov", "Dec", "Jan"]

    var body: some View {
        TutorialStepView(
            icon: "chart.line.uptrend.xyaxis",
            iconColor: .green,
            headline: "Track Your Progress",
            subheadline: "See how your scores change over time and set personal goals.",
            primaryLabel: "Get Started",
            primaryAction: onComplete
        ) {
            VStack(spacing: 20) {
                // Progress chart preview
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("PHQ-9 Score")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("Improving")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
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
                                LinearGradient(
                                    colors: [.blue, .green],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                            )

                            // Data points
                            ForEach(0..<min(animatedPoints, progressPoints.count), id: \.self) { index in
                                let x = CGFloat(index) * pointSpacing
                                let y = height * (1 - progressPoints[index] / maxScore)
                                Circle()
                                    .fill(.white)
                                    .frame(width: 10, height: 10)
                                    .overlay(
                                        Circle()
                                            .stroke(index == progressPoints.count - 1 ? Color.green : Color.blue, lineWidth: 2)
                                    )
                                    .position(x: x, y: y)
                            }
                        }
                    }
                    .frame(height: 100)

                    // Month labels
                    HStack {
                        ForEach(months, id: \.self) { month in
                            Text(month)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .opacity(showChart ? 1 : 0)

                // Goal indicator
                HStack(spacing: 12) {
                    Image(systemName: "flag.checkered")
                        .font(.title3)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Set a Goal")
                            .font(.subheadline.weight(.medium))
                        Text("Choose a target score to work toward")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .opacity(showChart ? 1 : 0)
            }
            .onAppear {
                animateChart()
            }
        }
    }

    private func animateChart() {
        withAnimation(.easeOut(duration: 0.3)) {
            showChart = true
        }

        for i in 1...progressPoints.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(i) * 0.2) {
                withAnimation(.easeOut(duration: 0.2)) {
                    animatedPoints = i
                }
            }
        }
    }
}

#Preview {
    OutcomesProgressStep(onComplete: {})
}
