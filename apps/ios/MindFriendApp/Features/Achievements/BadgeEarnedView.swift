// MindFriend Badge Earned Celebration View
// Displays a celebratory overlay when a badge is earned

import SwiftUI

struct BadgeEarnedView: View {
    let badge: AchievementBadge
    let onDismiss: () -> Void

    @State private var showContent = false

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            // Content
            VStack(spacing: 24) {
                Spacer()

                // Badge Icon with Animation
                ZStack {
                    // Glow Effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    tierColor.opacity(0.6),
                                    tierColor.opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 50,
                                endRadius: 150
                            )
                        )
                        .frame(width: 300, height: 300)
                        .scaleEffect(showContent ? 1.0 : 0.5)
                        .opacity(showContent ? 1.0 : 0.0)

                    // Badge
                    AsyncImage(url: URL(string: badge.iconUrl)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: "star.circle.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(tierColor)
                    }
                    .frame(width: 120, height: 120)
                    .scaleEffect(showContent ? 1.0 : 0.3)
                    .rotationEffect(.degrees(showContent ? 0 : -30))
                }

                // Text
                VStack(spacing: 12) {
                    Text("Badge Earned!")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    Text(badge.name)
                        .font(.title2)
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
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    // XP Reward
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("+\(badge.xpReward) XP")
                    }
                    .font(.headline)
                    .foregroundStyle(.yellow)
                    .padding(.top, 8)
                }
                .opacity(showContent ? 1.0 : 0.0)
                .offset(y: showContent ? 0 : 30)

                Spacer()

                // Dismiss Button
                Button {
                    onDismiss()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
                .opacity(showContent ? 1.0 : 0.0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showContent = true
            }
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
