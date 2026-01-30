// MindFriend Badge Earned Celebration View
// Displays a celebratory overlay when a badge is earned with hexagonal stamp and shimmer particles

import SwiftUI

struct BadgeEarnedView: View {
    let badge: AchievementBadge
    let onDismiss: () -> Void

    @State private var showBadge = false
    @State private var showShimmer = false
    @State private var showTitle = false
    @State private var showDetails = false
    @State private var showXP = false
    @State private var showButton = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Shimmer particles (behind badge)
            if showShimmer {
                BadgeShimmerParticles(tierColor: tierColor)
                    .frame(width: 350, height: 350)
            }

            // Content
            VStack(spacing: 20) {
                Spacer()

                // Hexagonal Badge Stamp Effect
                if showBadge {
                    BadgeStampEffect(
                        tierColor: tierColor,
                        sfSymbol: badge.sfSymbolName,
                        onImpact: {
                            // Trigger shimmer after stamp impact
                            withAnimation {
                                showShimmer = true
                            }
                        }
                    )
                    .frame(height: 180)
                }

                // "BADGE EARNED!" Title
                Text("BADGE EARNED!")
                    .font(.title2)
                    .fontWeight(.black)
                    .foregroundStyle(.white)
                    .tracking(2)
                    .opacity(showTitle ? 1 : 0)
                    .offset(y: showTitle ? 0 : 20)

                // Badge details
                VStack(spacing: 10) {
                    Text(badge.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(tierColor)

                    if let tier = badge.tier {
                        Text(tier.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(tierColor.opacity(0.3))
                            .clipShape(Capsule())
                    }

                    Text(badge.description)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .opacity(showDetails ? 1 : 0)
                .offset(y: showDetails ? 0 : 20)

                // XP Reward
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("+\(badge.xpReward) XP")
                }
                .font(.headline)
                .foregroundStyle(.yellow)
                .opacity(showXP ? 1 : 0)
                .scaleEffect(showXP ? 1 : 0.8)
                .padding(.top, 8)

                Spacer()

                // Continue Button
                Button {
                    dismiss()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(tierColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 30)
            }
        }
        .onAppear {
            if reduceMotion {
                // Instant display for reduced motion
                showBadge = true
                showShimmer = true
                showTitle = true
                showDetails = true
                showXP = true
                showButton = true
                HapticManager.celebrationSuccess()
            } else {
                startAnimation()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Badge earned: \(badge.name), \(badge.tier?.displayName ?? "") tier. Plus \(badge.xpReward) XP")
        .accessibilityAddTraits(.isModal)
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.2)) {
            showButton = false
            showBadge = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }

    private func startAnimation() {
        // Badge stamps down immediately
        showBadge = true

        // Title after stamp impact (0.4s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.3)) {
                showTitle = true
            }
        }

        // Details after title (0.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                showDetails = true
            }
        }

        // XP reward (0.7s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                showXP = true
            }
        }

        // Button (0.9s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeOut(duration: 0.3)) {
                showButton = true
            }
            HapticManager.celebrationSuccess()
        }
    }

    private var tierColor: Color {
        if let tier = badge.tier {
            return Color(hex: tier.color) ?? .purple
        }
        return .purple
    }
}

// MARK: - Badge Earned Modifier

struct BadgeEarnedModifier: ViewModifier {
    @EnvironmentObject private var achievementService: AchievementService

    @State private var currentBadge: AchievementBadge?
    @State private var showingCelebration = false

    func body(content: Content) -> some View {
        content
            .onChange(of: achievementService.newlyEarnedBadges) { oldValue, newValue in
                if let badge = newValue.first, currentBadge == nil {
                    currentBadge = badge
                    showingCelebration = true
                }
            }
            .fullScreenCover(isPresented: $showingCelebration) {
                if let badge = currentBadge {
                    BadgeEarnedView(badge: badge) {
                        showingCelebration = false
                        // Remove from newly earned and check for more
                        Task {
                            try? await achievementService.markBadgeAsSeen(badgeId: badge.id)
                            currentBadge = nil

                            // Show next badge if any
                            if let nextBadge = achievementService.newlyEarnedBadges.first {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    currentBadge = nextBadge
                                    showingCelebration = true
                                }
                            }
                        }
                    }
                }
            }
    }
}

extension View {
    func badgeEarnedCelebration() -> some View {
        modifier(BadgeEarnedModifier())
    }
}

#Preview {
    BadgeEarnedView(
        badge: AchievementBadge(from: DBBadge(
            id: UUID(),
            slug: "first-quest",
            name: "First Steps",
            description: "Complete your first quest",
            iconUrl: "",
            backgroundColor: nil,
            animationType: nil,
            category: "getting_started",
            subcategory: nil,
            tier: "bronze",
            tierOrder: 1,
            parentBadgeId: nil,
            requirementType: "count",
            requirementConfig: [:],
            progressTrackable: true,
            progressMetric: nil,
            rarity: "common",
            isSecret: false,
            revealHint: nil,
            isSeasonal: false,
            seasonId: nil,
            availableFrom: nil,
            availableUntil: nil,
            xpReward: 50,
            unlockContent: nil,
            totalEarners: 1000,
            isActive: true,
            sortOrder: 1,
            createdAt: "2024-01-01T00:00:00Z"
        )),
        onDismiss: {}
    )
}
