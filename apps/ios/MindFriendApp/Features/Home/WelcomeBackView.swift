import SwiftUI

/// Welcome back modal shown to returning users after an absence
/// Displays warm messaging based on lapse tier with optional fresh start
struct WelcomeBackView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    let absenceSummary: AbsenceSummary

    @State private var isPerformingFreshStart = false
    @State private var showConfetti = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            // Main content
            ScrollView {
                VStack(spacing: 24) {
                    // Warm illustration
                    illustrationSection

                    // Welcome message
                    messageSection

                    // What you missed (if any activity)
                    if absenceSummary.hasActivity {
                        WhatYouMissedCard(summary: absenceSummary)
                    }

                    // Action buttons
                    actionButtons
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.blue.opacity(0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay {
            if showConfetti {
                WelcomeBackConfettiView()
            }
        }
        .onAppear {
            Analytics.shared.track(.welcomeBackShown, properties: [
                "absence_days": absenceSummary.absenceDays,
                "lapse_tier": absenceSummary.lapseTier.rawValue,
                "has_activity": absenceSummary.hasActivity
            ])

            // Log the event to the database
            Task {
                try? await container.supabaseDataService.logReengagementEvent(
                    type: .welcomeBackShown,
                    absenceDays: absenceSummary.absenceDays
                )
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Spacer()
            Button {
                dismissModal()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close")
        }
        .padding()
    }

    // MARK: - Illustration

    private var illustrationSection: some View {
        VStack(spacing: 16) {
            // Friendly wave/sunrise illustration
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.orange.opacity(0.3),
                                Color.yellow.opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                Image(systemName: illustrationIcon)
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .padding(.top, 16)
    }

    private var illustrationIcon: String {
        switch absenceSummary.lapseTier {
        case .active, .briefBreak:
            return "hand.wave.fill"
        case .extendedBreak:
            return "sun.horizon.fill"
        case .longAbsence:
            return "sunrise.fill"
        case .hiatus:
            return "sparkles"
        }
    }

    // MARK: - Message

    private var messageSection: some View {
        VStack(spacing: 12) {
            Text(absenceSummary.lapseTier.welcomeMessage)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            Text(absenceSummary.lapseTier.subMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal)
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 16) {
            // Primary: Continue Journey
            Button {
                continueJourney()
            } label: {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Continue My Journey")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
            }
            .accessibilityLabel("Continue My Journey")

            // Secondary: Fresh Start (only for extended breaks+)
            if absenceSummary.lapseTier.showFreshStart {
                Button {
                    performFreshStart()
                } label: {
                    HStack {
                        if isPerformingFreshStart {
                            ProgressView()
                                .tint(.primary)
                        } else {
                            Image(systemName: "arrow.counterclockwise.circle")
                            Text("Start Fresh (Day 2 Bonus!)")
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .disabled(isPerformingFreshStart)
                .accessibilityLabel("Start Fresh with Day 2 Bonus")

                Text("Reset your visible streak and start at Day 2 as a welcome-back bonus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func continueJourney() {
        Analytics.shared.track(.welcomeBackContinueChosen, properties: [
            "absence_days": absenceSummary.absenceDays,
            "lapse_tier": absenceSummary.lapseTier.rawValue
        ])

        Task {
            try? await container.supabaseDataService.logReengagementEvent(
                type: .continueChosen,
                absenceDays: absenceSummary.absenceDays
            )
        }

        dismissModal()
    }

    private func performFreshStart() {
        isPerformingFreshStart = true

        Task {
            do {
                let result = try await container.supabaseDataService.performFreshStart()

                await MainActor.run {
                    if result.success {
                        // Update streak in app state
                        appState.currentStreak = result.newStreak

                        // Show brief confetti
                        showConfetti = true

                        Analytics.shared.track(.welcomeBackFreshStartChosen, properties: [
                            "absence_days": absenceSummary.absenceDays,
                            "new_streak": result.newStreak
                        ])

                        // Dismiss after brief celebration
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            dismissModal()
                        }
                    } else {
                        isPerformingFreshStart = false
                        appState.showError(.apiError("Unable to start fresh. Please try again."))
                    }
                }
            } catch {
                await MainActor.run {
                    isPerformingFreshStart = false
                    appState.showError(.apiError("Something went wrong: \(error.localizedDescription)"))
                }
            }
        }
    }

    private func dismissModal() {
        Analytics.shared.track(.welcomeBackDismissed, properties: [
            "absence_days": absenceSummary.absenceDays
        ])

        Task {
            try? await container.supabaseDataService.logReengagementEvent(
                type: .welcomeBackDismissed,
                absenceDays: absenceSummary.absenceDays
            )
        }

        appState.dismissWelcomeBack()
        dismiss()
    }
}

// MARK: - Welcome Back Confetti View (renamed to avoid conflict with CelebrationView.ConfettiView)

private struct WelcomeBackConfettiView: View {
    @State private var animate = false

    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<30, id: \.self) { index in
                WelcomeBackConfettiPiece(
                    color: confettiColors[index % confettiColors.count],
                    size: CGFloat.random(in: 8...16),
                    startX: CGFloat.random(in: 0...geometry.size.width),
                    delay: Double.random(in: 0...0.3)
                )
            }
        }
        .allowsHitTesting(false)
    }

    private var confettiColors: [Color] {
        [.blue, .purple, .orange, .yellow, .green, .pink]
    }
}

private struct WelcomeBackConfettiPiece: View {
    let color: Color
    let size: CGFloat
    let startX: CGFloat
    let delay: Double

    @State private var yOffset: CGFloat = -50
    @State private var rotation: Double = 0
    @State private var opacity: Double = 1

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: size, height: size * 0.6)
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .position(x: startX, y: yOffset)
            .onAppear {
                withAnimation(.easeIn(duration: 2).delay(delay)) {
                    yOffset = UIScreen.main.bounds.height + 100
                    rotation = Double.random(in: 360...720)
                    opacity = 0
                }
            }
    }
}

// MARK: - Preview

#Preview {
    WelcomeBackView(
        absenceSummary: AbsenceSummary(
            absenceDays: 10,
            lapseTier: .extendedBreak,
            hugsReceived: 3,
            circlePosts: 5,
            friendMilestones: [
                .init(name: "Sarah", milestone: "7-day streak!", isStreak: true)
            ]
        )
    )
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
