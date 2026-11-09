//
//  LongitudinalJourneyStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: Your journey over time
//

import SwiftUI

/// Step 1: Introduce long-term tracking concept
struct LongitudinalJourneyStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showTimeline = false

    var body: some View {
        TutorialStepView(
            icon: "calendar.badge.clock",
            iconColor: SupportTheme.accent,
            headline: "Your Journey Over Time",
            subheadline: "Track your progress across months and years, not just days.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.s) {
                // Timeline visualization
                HStack(spacing: SupportTheme.Spacing.xxs) {
                    ForEach(0..<6, id: \.self) { month in
                        VStack(spacing: SupportTheme.Spacing.xxs) {
                            Spacer(minLength: 0)

                            // Bar
                            RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                                .fill(
                                    SupportTheme.surface
                                )
                                .frame(width: 24, height: showTimeline ? heights[month] : 0)

                            // Month label
                            Text(monthLabels[month])
                                .font(.system(size: 9))
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(height: 70)
                .padding(.vertical, SupportTheme.Spacing.s)
                .padding(.horizontal, SupportTheme.Spacing.m)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                .padding(.horizontal, SupportTheme.Spacing.l)

                // Benefits
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    TimelineFeature(icon: "calendar", text: "Month-by-month view")
                    TimelineFeature(icon: "chart.xyaxis.line", text: "Trend analysis over time")
                    TimelineFeature(icon: "arrow.up.forward", text: "Track long-term growth")
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                .padding(.horizontal, SupportTheme.Spacing.l)
                .opacity(showTimeline ? 1 : 0)
            }
            .onAppear {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : (.easeOut(duration: 0.8).delay(0.3))) {
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
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: icon)
                .foregroundStyle(SupportTheme.accent)
                .frame(minWidth: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    LongitudinalJourneyStep(onNext: {}, onSkip: {})
}
