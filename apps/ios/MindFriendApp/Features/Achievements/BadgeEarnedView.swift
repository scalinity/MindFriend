// MindFriend Badge Earned Celebration View
// Displays a celebratory overlay when a badge is earned with hexagonal stamp and shimmer particles

import SwiftUI
import UIKit

struct BadgeEarnedView: View {
    let badge: AchievementBadge
    let onDismiss: () -> Void

    // Animation timing constants
    enum AnimationTiming {
        static let nanosPerSecond: UInt64 = 1_000_000_000
        static let presentationDelay: UInt64 = 450_000_000  // 0.45s - wait for fullScreenCover transition
        static let titleDelay: UInt64 = 400_000_000         // 0.4s after badge stamp
        static let detailsDelay: UInt64 = 500_000_000       // 0.5s after badge stamp
        static let xpDelay: UInt64 = 700_000_000            // 0.7s after badge stamp
        static let buttonDelay: UInt64 = 900_000_000        // 0.9s after badge stamp
        static let dismissDuration: Double = 0.2
        static let dismissDelayNanos: UInt64 = 200_000_000  // Pre-computed: 0.2s in nanoseconds
        static let nextBadgeDelay: UInt64 = 500_000_000     // 0.5s between badges

        // Animation durations for withAnimation calls
        static let fadeInDuration: Double = 0.3
        static let springResponse: Double = 0.4
        static let springDamping: Double = 0.6
    }

    @State private var showBadge = false
    @State private var showShimmer = false
    @State private var showTitle = false
    @State private var showDetails = false
    @State private var showXP = false
    @State private var showButton = false
    @State private var animationTask: Task<Void, Never>?
    @State private var dismissTask: Task<Void, Never>?
    @State private var isDismissing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SupportTheme.canvas
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
                .accessibilityHidden(true)

            if showShimmer {
                CelebrationParticles().ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: SupportTheme.Spacing.m) {

                    if showBadge {
                        CelebrationEmblem(.symbol(badge.sfSymbolName), tint: SupportTheme.Celebration.gold, diameter: 120)
                            .padding(.bottom, SupportTheme.Spacing.s)
                    }

                    Text("Badge earned")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(SupportTheme.textSecondary)
                        .opacity(showTitle ? 1 : 0)

                    VStack(spacing: SupportTheme.Spacing.xs) {
                        Text(badge.name)
                            .font(.title.bold())
                            .foregroundStyle(SupportTheme.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        if let tier = badge.tier {
                            Label(tier.displayName, systemImage: "circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .labelStyle(TierLabelStyle(color: tierColor))
                        }
                        Text(badge.description)
                            .font(.body)
                            .foregroundStyle(SupportTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, SupportTheme.Spacing.xl)
                    }
                    .opacity(showDetails ? 1 : 0)

                    Label("+\(badge.xpReward) XP", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(SupportTheme.Celebration.gold)
                        .opacity(showXP ? 1 : 0)

                    Button("Continue") { dismiss() }
                        .buttonStyle(.supportPrimary)
                        .frame(maxWidth: 360)
                        .padding(.horizontal, SupportTheme.Spacing.l)
                        .padding(.bottom, SupportTheme.Spacing.l)
                        .opacity(showButton ? 1 : 0)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: SupportTheme.readableWidth)
                .padding(SupportTheme.Spacing.l)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showBadge = true
                    showTitle = true
                    showDetails = true
                    showXP = true
                    showButton = true
                }
                HapticManager.celebrationSuccess()
                UIAccessibility.post(notification: .announcement, argument: accessibilityDescription)
            } else {
                startAnimation()
            }
        }
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
            dismissTask?.cancel()
            dismissTask = nil
        }
        .accessibilityAddTraits(.isModal)
        .presentationBackground(.clear)
    }

    private var accessibilityDescription: String {
        let tierText = badge.tier.map { ", \($0.displayName) tier" } ?? ""
        return "Badge earned: \(badge.name)\(tierText). Plus \(badge.xpReward) XP"
    }

    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        animationTask?.cancel()
        dismissTask?.cancel()  // Cancel any pending dismiss to prevent duplicate callbacks
        withAnimation(.easeIn(duration: AnimationTiming.dismissDuration)) {
            showBadge = false
            showShimmer = false
            showTitle = false
            showDetails = false
            showXP = false
            showButton = false
        }
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: AnimationTiming.dismissDelayNanos)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }

    private func startAnimation() {
        animationTask = Task { @MainActor in
            // Wait for fullScreenCover presentation transition to complete
            try? await Task.sleep(nanoseconds: AnimationTiming.presentationDelay)
            guard !Task.isCancelled else { return }

            // The emblem settles into place and the particles begin.
            showBadge = true
            showShimmer = true

            // Title after stamp impact
            try? await Task.sleep(nanoseconds: AnimationTiming.titleDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: AnimationTiming.fadeInDuration)) {
                showTitle = true
            }

            // Details shortly after title
            try? await Task.sleep(nanoseconds: AnimationTiming.detailsDelay - AnimationTiming.titleDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: AnimationTiming.fadeInDuration)) {
                showDetails = true
            }

            // XP reward
            try? await Task.sleep(nanoseconds: AnimationTiming.xpDelay - AnimationTiming.detailsDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: AnimationTiming.springResponse, dampingFraction: AnimationTiming.springDamping)) {
                showXP = true
            }

            // Button
            try? await Task.sleep(nanoseconds: AnimationTiming.buttonDelay - AnimationTiming.xpDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: AnimationTiming.fadeInDuration)) {
                showButton = true
            }
            HapticManager.celebrationSuccess()

            // Announce to VoiceOver after all elements are visible
            UIAccessibility.post(notification: .announcement, argument: accessibilityDescription)
        }
    }

    private struct TierLabelStyle: LabelStyle {
        let color: Color
        func makeBody(configuration: LabelStyleConfiguration) -> some View {
            HStack(spacing: SupportTheme.Spacing.xs) {
                configuration.icon.font(.caption2).foregroundStyle(color).accessibilityHidden(true)
                configuration.title
            }
        }
    }

    private var tierColor: Color { SupportTheme.Celebration.gold }

}

// MARK: - Badge Earned Modifier

struct BadgeEarnedModifier: ViewModifier {
    @EnvironmentObject private var achievementService: AchievementService

    @State private var currentBadge: AchievementBadge?
    @State private var badgeQueueTask: Task<Void, Never>?
    @State private var isProcessingQueue = false
    @State private var shownBadgeIds: [UUID] = []  // Array for FIFO eviction order

    /// Maximum number of badge IDs to track to prevent unbounded memory growth
    private static let maxShownBadgeIds = 50

    func body(content: Content) -> some View {
        content
            .onChange(of: achievementService.newlyEarnedBadges) { oldValue, newValue in
                // Only trigger from onChange when NOT already processing the queue
                // This prevents a race where markBadgeAsSeen mutates the array,
                // triggering onChange while badgeQueueTask is still handling transitions
                // NOTE: Don't track badge here - track on dismiss when user definitely saw it
                if let badge = newValue.first,
                   currentBadge == nil,
                   !isProcessingQueue,
                   !shownBadgeIds.contains(badge.id) {
                    currentBadge = badge
                }
            }
            .fullScreenCover(item: $currentBadge) { badge in
                BadgeEarnedView(badge: badge) {
                    // Cancel old task FIRST, then set flag AFTER to prevent defer race
                    // (old task's defer { isProcessingQueue = false } runs on cancel)
                    badgeQueueTask?.cancel()
                    badgeQueueTask = nil
                    isProcessingQueue = true
                    // Track badge NOW - user definitely saw it since they dismissed it
                    trackShownBadge(badge.id)
                    currentBadge = nil
                    // Note: ViewModifier @State is managed by SwiftUI's storage system,
                    // not traditional object retain cycles. Task closures here capture
                    // bindings to @State, which SwiftUI manages independently.
                    badgeQueueTask = Task { @MainActor in
                        defer { isProcessingQueue = false }

                        do {
                            try await achievementService.markBadgeAsSeen(badgeId: badge.id)
                        } catch {
                            print("[BadgeEarned] Failed to mark badge as seen: \(error)")
                        }
                        guard !Task.isCancelled else { return }
                        // Queue next badge if any remain (skip already-shown badges)
                        if let nextBadge = achievementService.newlyEarnedBadges.first(where: { !shownBadgeIds.contains($0.id) }) {
                            try? await Task.sleep(nanoseconds: BadgeEarnedView.AnimationTiming.nextBadgeDelay)
                            guard !Task.isCancelled else { return }
                            currentBadge = nextBadge
                        }
                    }
                }
            }
            .onDisappear {
                // Complete cleanup when view hierarchy disappears
                badgeQueueTask?.cancel()
                badgeQueueTask = nil
                currentBadge = nil
                isProcessingQueue = false
            }
    }

    /// Track a shown badge ID with memory cap to prevent unbounded growth.
    /// Uses FIFO eviction - oldest badges are removed first when cap is reached.
    /// O(n) contains() check is acceptable for n <= 50.
    private func trackShownBadge(_ id: UUID) {
        // Skip if already tracked (prevents duplicates)
        guard !shownBadgeIds.contains(id) else { return }

        // Evict oldest entries (FIFO) when at capacity
        if shownBadgeIds.count >= Self.maxShownBadgeIds {
            let removeCount = Self.maxShownBadgeIds / 2
            shownBadgeIds.removeFirst(removeCount)
        }
        shownBadgeIds.append(id)
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
