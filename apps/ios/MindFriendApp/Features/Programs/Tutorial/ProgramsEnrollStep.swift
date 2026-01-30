//
//  ProgramsEnrollStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: How to enroll in a program
//

import SwiftUI

/// Step 2: Explain program enrollment
struct ProgramsEnrollStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showCard = false
    @State private var showEnroll = false

    var body: some View {
        TutorialStepView(
            icon: "hand.tap.fill",
            iconColor: .blue,
            headline: "Enroll in a Program",
            subheadline: "Browse our library and commit to a program that matches your goals.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 16) {
                // Example program card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.cyan.gradient)
                                .frame(width: 50, height: 50)

                            Image(systemName: "brain.head.profile")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("21-Day Anxiety Reset")
                                .font(.subheadline.weight(.semibold))

                            HStack(spacing: 8) {
                                Label("21 days", systemImage: "calendar")
                                Label("15 min/day", systemImage: "clock")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                            .padding(.vertical, 10)
                            .background(showEnroll ? Color.green : Color.cyan)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(true)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .scaleEffect(showCard ? 1 : 0.9)
                .opacity(showCard ? 1 : 0)
                .padding(.horizontal, 20)

                // Enrollment info
                VStack(spacing: 8) {
                    ProgramEnrollInfoRow(icon: "clock.badge.checkmark", text: "Choose your daily reminder time")
                    ProgramEnrollInfoRow(icon: "calendar.badge.plus", text: "Start immediately or schedule for later")
                    ProgramEnrollInfoRow(icon: "arrow.clockwise", text: "Pause anytime if life gets busy")
                }
                .padding(.horizontal, 24)
                .opacity(showEnroll ? 1 : 0)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                    showCard = true
                }
                withAnimation(.easeOut(duration: 0.4).delay(1.0)) {
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
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.cyan)
                .frame(width: 20)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

#Preview {
    ProgramsEnrollStep(onNext: {}, onSkip: {})
}
