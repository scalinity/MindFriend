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
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Warm illustration
                    illustrationSection

                    // Welcome message
                    messageSection

                    // What you missed (if any activity)
                    if hasVisibleActivity { missedActivityCard }

                    // Action buttons
                    actionButtons
                }
                .padding(.horizontal, SupportTheme.Spacing.l)
                .padding(.bottom, SupportTheme.Spacing.xl)
            }
        }
        .supportSheet()
        .foregroundStyle(SupportTheme.textPrimary)
        .overlay {
            if showConfetti {
                CelebrationParticles()
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

    private var hasVisibleActivity: Bool {
        absenceSummary.hugsReceived > 0 || absenceSummary.circlePosts > 0
            || absenceSummary.friendMilestones.contains { !$0.isStreak }
    }

    private var missedActivityCard: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("While you were away").font(.headline).accessibilityAddTraits(.isHeader)
            if absenceSummary.hugsReceived > 0 {
                SupportRowLabel(title: absenceSummary.hugsReceived == 1
                    ? "Someone sent you a hug" : "\(absenceSummary.hugsReceived) people sent you hugs", icon: "heart")
            }
            if absenceSummary.circlePosts > 0 {
                SupportRowLabel(title: absenceSummary.circlePosts == 1
                    ? "1 new post in your circles" : "\(absenceSummary.circlePosts) new posts in your circles", icon: "bubble.left.and.bubble.right")
            }
            ForEach(absenceSummary.friendMilestones.filter { !$0.isStreak }.prefix(3)) { milestone in
                SupportRowLabel(title: "\(milestone.name)'s milestone", subtitle: milestone.milestone, icon: "star")
            }
        }
        .supportCard()
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
                    .foregroundStyle(SupportTheme.textSecondary)
                    .frame(width: SupportTheme.minimumTarget, height: SupportTheme.minimumTarget)
            }
            .accessibilityLabel("Close")
        }
        .padding(SupportTheme.Spacing.m)
    }

    // MARK: - Illustration

    private var illustrationSection: some View {
        CelebrationEmblem(.symbol(illustrationIcon), diameter: 96)
            .padding(.top, SupportTheme.Spacing.m)
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
        VStack(spacing: SupportTheme.Spacing.s) {
            Text(absenceSummary.lapseTier.welcomeMessage)
                .font(.title2)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)
                .multilineTextAlignment(.center)
                .foregroundStyle(SupportTheme.textPrimary)

            Text(absenceSummary.lapseTier.subMessage)
                .font(.body)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, SupportTheme.Spacing.m)
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            // Primary: Continue Journey
            Button {
                continueJourney()
            } label: {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Continue My Journey")
                }
            }
            .buttonStyle(.supportPrimary)
            .accessibilityLabel("Continue My Journey")

            // Secondary: Fresh Start (only for extended breaks+)
            if absenceSummary.lapseTier.showFreshStart {
                Button {
                    performFreshStart()
                } label: {
                    HStack {
                        if isPerformingFreshStart {
                            ProgressView()
                                .tint(SupportTheme.textPrimary)
                        } else {
                            Image(systemName: "arrow.counterclockwise.circle")
                            Text("Start fresh")
                        }
                    }
                }
                .buttonStyle(.supportSecondary)
                .disabled(isPerformingFreshStart)
                .accessibilityLabel("Start fresh")

                Text("Make room for a fresh start. Your completed activities and earned XP stay with you.")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, SupportTheme.Spacing.xs)
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

// MARK: - Preview

#Preview {
    WelcomeBackView(
        absenceSummary: AbsenceSummary(
            absenceDays: 10,
            lapseTier: .extendedBreak,
            hugsReceived: 3,
            circlePosts: 5,
            friendMilestones: [
                .init(name: "Sarah", milestone: "A new level reached", isStreak: false)
            ]
        )
    )
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
