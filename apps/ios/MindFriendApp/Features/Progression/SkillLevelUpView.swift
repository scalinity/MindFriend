// MindFriend Skill Level Up View
// Full celebration view for skill level advancement

import SwiftUI

/// Full-screen celebration for skill level-up
struct SkillLevelUpView: View {
    let skillType: ExerciseType
    let oldLevel: Int
    let newLevel: Int
    let xpEarned: Int
    let onDismiss: () -> Void

    @State private var showIcon = false
    @State private var showParticles = false
    @State private var showContent = false
    @State private var iconGlow = false
    @State private var showBurst = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var themeColor: Color { skillType.themeColor }
    private var skillIcon: String { skillType.icon }

    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Energy particles
            if showParticles {
                SkillEnergyParticles(
                    themeColor: themeColor,
                    onConverge: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            iconGlow = true
                        }
                    },
                    onBurst: {
                        showBurst = true
                    }
                )
            }

            // Main content
            VStack(spacing: 24) {
                Spacer()

                // Skill icon with glow
                ZStack {
                    // Glow background
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [themeColor.opacity(0.5), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                        .blur(radius: iconGlow ? 15 : 25)
                        .opacity(iconGlow ? 0.9 : 0.3)

                    // Icon circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [themeColor.opacity(0.8), themeColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: themeColor.opacity(0.5), radius: iconGlow ? 20 : 5)

                    // Skill icon
                    Image(systemName: skillIcon)
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                }
                .scaleEffect(showIcon ? 1 : 0.5)
                .opacity(showIcon ? 1 : 0)

                // "SKILL UP!" title
                Text("SKILL UP!")
                    .font(.largeTitle)
                    .fontWeight(.black)
                    .foregroundStyle(.white)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)

                // Skill name and level
                VStack(spacing: 8) {
                    Text(skillType.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(themeColor)

                    Text("Level \(oldLevel) → \(newLevel)")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))

                    // Level title
                    Text(SkillLevel.titles[safe: newLevel] ?? "Master")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(themeColor.opacity(0.3))
                        .clipShape(Capsule())
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)

                // XP earned
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.yellow)
                    Text("+\(xpEarned) XP")
                        .font(.headline)
                        .foregroundStyle(.yellow)
                }
                .opacity(showContent ? 1 : 0)
                .padding(.top, 8)

                Spacer()

                // Continue button
                Button {
                    dismiss()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(width: 200)
                        .padding(.vertical, 14)
                        .background(themeColor)
                        .cornerRadius(25)
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 30)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            if reduceMotion {
                showIcon = true
                showContent = true
                iconGlow = true
                HapticManager.celebrationSuccess()
            } else {
                startAnimation()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Skill level up! \(skillType.displayName) is now level \(newLevel)")
        .accessibilityAddTraits(.isModal)
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.2)) {
            showContent = false
            showIcon = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }

    private func startAnimation() {
        // Icon appears
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            showIcon = true
        }

        // Particles start rising
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showParticles = true
        }

        // Content fades in after burst
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.4)) {
                showContent = true
            }
            HapticManager.celebrationSuccess()
        }
    }
}

// MARK: - Skill Level Up Event

/// Event data for skill level-up celebration
struct SkillLevelUpEvent: Identifiable, Equatable {
    let id = UUID()
    let skillType: ExerciseType
    let oldLevel: Int
    let newLevel: Int
    let xpEarned: Int
}

// MARK: - View Modifier

/// View modifier for showing skill level-up celebration
struct SkillLevelUpModifier: ViewModifier {
    @EnvironmentObject private var achievementService: AchievementService

    @State private var currentEvent: SkillLevelUpEvent?
    @State private var showingCelebration = false

    func body(content: Content) -> some View {
        content
            .onChange(of: achievementService.pendingSkillLevelUp) { _, newValue in
                if let event = newValue, currentEvent == nil {
                    currentEvent = event
                    showingCelebration = true
                }
            }
            .fullScreenCover(isPresented: $showingCelebration) {
                if let event = currentEvent {
                    SkillLevelUpView(
                        skillType: event.skillType,
                        oldLevel: event.oldLevel,
                        newLevel: event.newLevel,
                        xpEarned: event.xpEarned,
                        onDismiss: {
                            showingCelebration = false
                            currentEvent = nil
                            achievementService.clearPendingSkillLevelUp()
                        }
                    )
                }
            }
    }
}

extension View {
    /// Shows skill level-up celebration overlay
    func skillLevelUpCelebration() -> some View {
        modifier(SkillLevelUpModifier())
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview("Breathing Level 2") {
    SkillLevelUpView(
        skillType: .breathing,
        oldLevel: 1,
        newLevel: 2,
        xpEarned: 150,
        onDismiss: {}
    )
}

#Preview("Meditation Level 3") {
    SkillLevelUpView(
        skillType: .meditation,
        oldLevel: 2,
        newLevel: 3,
        xpEarned: 350,
        onDismiss: {}
    )
}

#Preview("Movement Level 5") {
    SkillLevelUpView(
        skillType: .movement,
        oldLevel: 4,
        newLevel: 5,
        xpEarned: 750,
        onDismiss: {}
    )
}
