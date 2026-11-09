import SwiftUI

/// A confirmed skill level change uses the same celebration language as account levels.
struct SkillLevelUpView: View {
    let skillType: ExerciseType
    let oldLevel: Int
    let newLevel: Int
    let xpEarned: Int
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            SupportTheme.canvas.ignoresSafeArea()
                .onTapGesture(perform: onDismiss).accessibilityHidden(true)
            CelebrationParticles().ignoresSafeArea()
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    CelebrationEmblem(.symbol(skillType.icon), tint: SupportTheme.Celebration.gold, diameter: 120)
                    VStack(spacing: SupportTheme.Spacing.s) {
                        Text("Skill level up").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Text(skillType.displayName).font(.title2.weight(.semibold))
                        Text("Level \(oldLevel) → \(newLevel)")
                            .font(.headline).foregroundStyle(SupportTheme.textSecondary)
                        Text(SkillLevel.titles[safe: newLevel] ?? "Master")
                            .foregroundStyle(SupportTheme.textSecondary)
                        Label("+\(xpEarned) XP", systemImage: "sparkles")
                            .font(.headline).foregroundStyle(SupportTheme.Celebration.gold)
                    }
                    .celebrationReveal(delay: 0.2)
                    Button("Continue", action: onDismiss).buttonStyle(.supportPrimary)
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(SupportTheme.textPrimary)
                .frame(maxWidth: SupportTheme.readableWidth)
                .padding(SupportTheme.Spacing.l)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            HapticManager.celebrationSuccess()
            AccessibilityNotification.Announcement("\(skillType.displayName), level \(newLevel)").post()
        }
        .accessibilityAddTraits(.isModal)
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
