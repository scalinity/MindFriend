//
//  JourneyProgressStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Explains how daily progress works
//

import SwiftUI

/// Step 2: Explain how completing quests advances the journey
struct JourneyProgressStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var currentDay = 1
    @State private var showProgress = false

    var body: some View {
        JourneyTutorialStepLayout(
            icon: "calendar.badge.checkmark",
            iconColor: .green,
            headline: "One Day at a Time",
            subheadline: "Complete your daily quest to advance through your journey.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 16) {
                // Animated day progression
                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { day in
                        dayIndicator(day: day)
                    }
                }
                .padding(.horizontal)

                // Progress explanation
                VStack(spacing: 8) {
                    progressRow(
                        icon: "checkmark.circle.fill",
                        color: .green,
                        text: "Complete today's quest"
                    )

                    Image(systemName: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    progressRow(
                        icon: "arrow.right.circle.fill",
                        color: .blue,
                        text: "Journey advances to next day"
                    )

                    Image(systemName: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    progressRow(
                        icon: "sparkles",
                        color: .orange,
                        text: "Skills build over time"
                    )
                }
                .padding(.horizontal, 20)

                // Note
                Text("**No pressure** - your journey waits for you. Complete at your own pace.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
            .onAppear {
                withAnimation {
                    showProgress = true
                }
                // Animate through days
                animateDays()
            }
        }
    }

    @ViewBuilder
    private func dayIndicator(day: Int) -> some View {
        let isCompleted = day < currentDay
        let isCurrent = day == currentDay
        let isUpcoming = day > currentDay

        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.green : isCurrent ? Color.blue : Color(.systemGray5))
                    .frame(width: 36, height: 36)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else {
                    Text("\(day)")
                        .font(.caption.bold())
                        .foregroundStyle(isCurrent ? .white : .secondary)
                }
            }
            .scaleEffect(isCurrent ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: currentDay)

            Text("Day \(day)")
                .font(.caption2)
                .foregroundStyle(isUpcoming ? .tertiary : .secondary)
        }
    }

    @ViewBuilder
    private func progressRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()
        }
        .opacity(showProgress ? 1 : 0)
        .offset(x: showProgress ? 0 : -20)
    }

    private func animateDays() {
        // Animate through first 3 days
        for i in 2...3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i - 1) * 0.8) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentDay = i
                }
            }
        }
    }
}

#Preview {
    JourneyProgressStep(onNext: {}, onSkip: {})
}
