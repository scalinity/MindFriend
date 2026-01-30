//
//  LongitudinalJourneyStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: Your journey over time
//

import SwiftUI

/// Step 1: Introduce long-term tracking concept
struct LongitudinalJourneyStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showTimeline = false

    var body: some View {
        TutorialStepView(
            icon: "calendar.badge.clock",
            iconColor: .teal,
            headline: "Your Journey Over Time",
            subheadline: "Track your progress across months and years, not just days.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 12) {
                // Timeline visualization
                HStack(spacing: 4) {
                    ForEach(0..<6, id: \.self) { month in
                        VStack(spacing: 4) {
                            Spacer(minLength: 0)

                            // Bar
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [.teal.opacity(0.3), .teal],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(width: 24, height: showTimeline ? heights[month] : 0)

                            // Month label
                            Text(monthLabels[month])
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 70)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)

                // Benefits
                VStack(alignment: .leading, spacing: 10) {
                    TimelineFeature(icon: "calendar", text: "Month-by-month view")
                    TimelineFeature(icon: "chart.xyaxis.line", text: "Trend analysis over time")
                    TimelineFeature(icon: "arrow.up.forward", text: "Track long-term growth")
                }
                .padding(12)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .opacity(showTimeline ? 1 : 0)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                    showTimeline = true
                }
            }
        }
    }

    private let heights: [CGFloat] = [30, 42, 38, 50, 54, 62]
    private let monthLabels = ["Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
}

private struct TimelineFeature: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.teal)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    LongitudinalJourneyStep(onNext: {}, onSkip: {})
}
