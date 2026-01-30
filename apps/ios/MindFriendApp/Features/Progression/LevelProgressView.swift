import SwiftUI

/// Displays the user's current level and XP progress with immersive animations
struct LevelProgressView: View {
    let userLevel: UserLevel

    // Animated state (interpolated values)
    @State private var displayedXP: Int = 0
    @State private var displayedProgress: CGFloat = 0
    @State private var displayedWeeklyXP: Int = 0
    @State private var isAnimating = false
    @State private var showGlow = false
    @State private var hasInitialized = false

    // Cancellable work items for timer cleanup
    @State private var animationWorkItems: [DispatchWorkItem] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Level badge - matches Achievements page design
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 56, height: 56)

                    Text("\(userLevel.level)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Level \(userLevel.level)")
                        .font(.headline)
                    Text(userLevel.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Animated XP display
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(displayedXP) XP")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: displayedXP)

                    Text("this week: \(displayedWeeklyXP)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: displayedWeeklyXP)
                }
            }

            // Animated progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)

                    // Animated fill bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.accentColor, .accentColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geometry.size.width * displayedProgress), height: 8)
                        .animation(.spring(response: 0.8, dampingFraction: 0.7), value: displayedProgress)

                    // Glow overlay (during animation)
                    if showGlow {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.5))
                            .frame(width: max(0, geometry.size.width * displayedProgress), height: 8)
                            .blur(radius: 6)
                            .animation(.spring(response: 0.8, dampingFraction: 0.7), value: displayedProgress)
                    }
                }
            }
            .frame(height: 8)

            // XP to next level
            if userLevel.level < 50 {
                Text("\(userLevel.xpToNextLevel) XP to next level")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Max level reached!")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Level \(userLevel.level), \(userLevel.title). \(displayedXP) XP total. \(userLevel.xpToNextLevel) XP to next level.")
        .onAppear {
            // Initialize without animation on first appear
            if !hasInitialized {
                displayedXP = userLevel.currentXP
                displayedProgress = userLevel.progress
                displayedWeeklyXP = userLevel.xpThisWeek
                hasInitialized = true
            }
        }
        .onChange(of: userLevel.currentXP) { oldValue, newValue in
            guard hasInitialized, oldValue != newValue else { return }
            animateXPChange(from: oldValue, to: newValue)
        }
        .onDisappear {
            cancelAllAnimations()
        }
    }

    // MARK: - Animation Cleanup

    private func cancelAllAnimations() {
        animationWorkItems.forEach { $0.cancel() }
        animationWorkItems.removeAll()
        isAnimating = false
    }

    // MARK: - Animation Logic

    private func animateXPChange(from oldXP: Int, to newXP: Int) {
        guard !reduceMotion else {
            // Instant update for reduced motion
            displayedXP = newXP
            displayedProgress = userLevel.progress
            displayedWeeklyXP = userLevel.xpThisWeek
            return
        }

        // Cancel any in-progress animations to prevent race conditions
        cancelAllAnimations()

        isAnimating = true
        showGlow = true

        // Animate progress bar (spring animation handles this via the binding)
        withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
            displayedProgress = userLevel.progress
        }

        // Count up XP number with smooth interpolation
        animateNumber(from: oldXP, to: newXP, duration: 0.8) { value in
            displayedXP = value
        }

        // Update weekly XP with animation
        animateNumber(from: displayedWeeklyXP, to: userLevel.xpThisWeek, duration: 0.6) { value in
            displayedWeeklyXP = value
        }

        // Glow pulse - fade out after peak
        let glowWorkItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.5)) {
                showGlow = false
            }
        }
        animationWorkItems.append(glowWorkItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: glowWorkItem)

        // Haptic on completion
        let completionWorkItem = DispatchWorkItem {
            HapticManager.badgeRipple()
            isAnimating = false
        }
        animationWorkItems.append(completionWorkItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: completionWorkItem)
    }

    private func animateNumber(from start: Int, to end: Int, duration: Double, update: @escaping (Int) -> Void) {
        guard start != end else {
            update(end)
            return
        }

        let steps = 15
        let stepDuration = duration / Double(steps)
        let difference = end - start

        for i in 0...steps {
            let workItem = DispatchWorkItem {
                // Use easeOut curve for more satisfying feel (fast start, slow end)
                let progress = Double(i) / Double(steps)
                let easedProgress = 1 - pow(1 - progress, 3) // Cubic ease-out

                let value = start + Int(Double(difference) * easedProgress)
                update(i == steps ? end : value) // Ensure we hit exact end value
            }
            animationWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i), execute: workItem)
        }
    }
}

/// Compact version for smaller spaces
struct LevelBadgeView: View {
    let level: Int
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 28, height: 28)

                Text("\(level)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        LevelProgressView(userLevel: UserLevel(
            level: 12,
            title: "Explorer",
            currentXP: 3850,
            nextLevelXP: 4500,
            xpThisWeek: 180
        ))

        LevelProgressView(userLevel: UserLevel(
            level: 50,
            title: "Transcendent",
            currentXP: 65000,
            nextLevelXP: 63700,
            xpThisWeek: 450
        ))

        LevelBadgeView(level: 12, title: "Explorer")
    }
    .padding()
}
