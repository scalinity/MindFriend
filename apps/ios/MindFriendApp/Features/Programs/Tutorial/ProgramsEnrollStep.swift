//
//  ProgramsEnrollStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: How to enroll in a program
//

import SwiftUI

/// Step 2: Explain program enrollment
struct ProgramsEnrollStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showCard = false
    @State private var showEnroll = false

    var body: some View {
        TutorialStepView(
            icon: "hand.tap.fill",
            iconColor: SupportTheme.accent,
            headline: "Enroll in a Program",
            subheadline: "Browse our library and commit to a program that matches your goals.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Example program card
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                .fill(SupportTheme.accent)
                                .frame(width: 50, height: 50)

                            Image(systemName: "brain.head.profile")
                                .font(.title3)
                                .foregroundStyle(SupportTheme.onAccent)
                        }

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text("21-Day Anxiety Reset")
                                .font(.subheadline.weight(.semibold))

                            HStack(spacing: SupportTheme.Spacing.xs) {
                                Label("21 days", systemImage: "calendar")
                                Label("15 min/day", systemImage: "clock")
                            }
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                        }

                        Spacer()
                    }

                    // Enroll button
                    Button {
                        // Visual feedback only
                    } label: {
                        Text(showEnroll ? "Enrolled!" : "Start Program")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SupportTheme.Spacing.xs)
                            .background(showEnroll ? SupportTheme.accent : SupportTheme.accent)
                            .foregroundStyle(SupportTheme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    }
                    .disabled(true)
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                .scaleEffect(reduceMotion ? 1 : (showCard ? 1 : 0.9))
                .opacity(showCard ? 1 : 0)
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Enrollment info
                VStack(spacing: SupportTheme.Spacing.xs) {
                    ProgramEnrollInfoRow(icon: "clock.badge.checkmark", text: "Choose your daily reminder time")
                    ProgramEnrollInfoRow(icon: "calendar.badge.plus", text: "Start immediately or schedule for later")
                    ProgramEnrollInfoRow(icon: "arrow.clockwise", text: "Pause anytime if life gets busy")
                }
                .padding(.horizontal, SupportTheme.Spacing.l)
                .opacity(showEnroll ? 1 : 0)
            }
            .onAppear {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.5).delay(0.3)) {
                    showCard = true
                }
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.4).delay(1.0)) {
                    showEnroll = true
                }
            }
        }
    }
}

// MARK: - Info Row

private struct ProgramEnrollInfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(SupportTheme.accent)
                .frame(width: 20)

            Text(text)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

#Preview {
    ProgramsEnrollStep(onNext: {}, onSkip: {})
}
