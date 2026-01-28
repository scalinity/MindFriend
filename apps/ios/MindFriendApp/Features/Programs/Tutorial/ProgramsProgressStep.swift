//
//  ProgramsProgressStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: Daily progress and streaks
//

import SwiftUI

/// Step 3: Show how daily program progress works
struct ProgramsProgressStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var currentDay = 0
    @State private var progress: Double = 0
    @State private var showFeatures = false

    var body: some View {
        TutorialStepView(
            icon: "chart.line.uptrend.xyaxis",
            iconColor: .green,
            headline: "Track Your Progress",
            subheadline: "Complete each day's content to advance through the program and build momentum.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 24) {
                // Progress visualization
                VStack(spacing: 12) {
                    // Day indicator
                    HStack {
                        Text("Day \(currentDay) of 21")
                            .font(.headline)
                            .contentTransition(.numericText())

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                            Text("\(currentDay) day streak")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.systemGray5))

                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [.cyan, .green],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 12)

                    // Day circles
                    HStack(spacing: 4) {
                        ForEach(1...7, id: \.self) { day in
                            Circle()
                                .fill(day <= currentDay ? Color.green : Color(.systemGray5))
                                .frame(width: 24, height: 24)
                                .overlay {
                                    if day <= currentDay {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                    } else {
                                        Text("\(day)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                        }
                        Text("...")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)

                // Features
                VStack(spacing: 8) {
                    ProgressFeature(icon: "bell.fill", text: "Daily reminders keep you on track")
                    ProgressFeature(icon: "arrow.uturn.backward", text: "Review past days anytime")
                    ProgressFeature(icon: "pause.circle.fill", text: "Pause without losing progress")
                }
                .padding(.horizontal, 32)
                .opacity(showFeatures ? 1 : 0)
            }
            .onAppear {
                animateProgress()
            }
        }
    }

    private func animateProgress() {
        for day in 1...7 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(day) * 0.2) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    currentDay = day
                    progress = Double(day) / 21.0
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation {
                showFeatures = true
            }
        }
    }
}

// MARK: - Progress Feature Row

private struct ProgressFeature: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.green)
                .frame(width: 20)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

#Preview {
    ProgramsProgressStep(onNext: {}, onSkip: {})
}
