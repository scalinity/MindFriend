import SwiftUI

/// Celebratory overlay shown when the account reaches a new level.
struct LevelUpCelebration: View {
    let newLevel: Int
    let newTitle: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            SupportTheme.canvas
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)
            CelebrationParticles().ignoresSafeArea()
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    CelebrationEmblem(.text("\(newLevel)"), tint: SupportTheme.Celebration.gold, diameter: 120)
                    VStack(spacing: SupportTheme.Spacing.xs) {
                        Text("Level \(newLevel)")
                            .font(.largeTitle.bold())
                            .foregroundStyle(SupportTheme.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(newTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(SupportTheme.Celebration.gold)
                        Text("Every small step counted toward this.")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .multilineTextAlignment(.center)
                    .celebrationReveal(delay: 0.2)
                    Button("Continue", action: onDismiss)
                        .buttonStyle(.supportPrimary)
                        .frame(maxWidth: 320)
                        .padding(.top, SupportTheme.Spacing.s)
                        .celebrationReveal(delay: 0.35)
                }
                .frame(maxWidth: SupportTheme.readableWidth)
                .padding(SupportTheme.Spacing.l)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            HapticManager.levelUpPattern()
            AccessibilityNotification.Announcement("Level \(newLevel), \(newTitle)").post()
        }
        .accessibilityAddTraits(.isModal)
    }
}

/// View modifier for showing level-up celebration
struct LevelUpCelebrationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let level: Int
    let title: String

    func body(content: Content) -> some View {
        ZStack {
            content

            if isPresented {
                LevelUpCelebration(
                    newLevel: level,
                    newTitle: title,
                    onDismiss: { isPresented = false }
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
    }
}

extension View {
    /// Shows a level-up celebration overlay
    func levelUpCelebration(
        isPresented: Binding<Bool>,
        level: Int,
        title: String
    ) -> some View {
        modifier(LevelUpCelebrationModifier(
            isPresented: isPresented,
            level: level,
            title: title
        ))
    }
}

#Preview {
    ZStack {
        // Background content
        SupportTheme.canvas
            .ignoresSafeArea()

        Text("Main Content")
            .foregroundStyle(SupportTheme.textPrimary)
    }
    .levelUpCelebration(
        isPresented: .constant(true),
        level: 5,
        title: "Explorer"
    )
}

#Preview("Level 10") {
    LevelUpCelebration(
        newLevel: 10,
        newTitle: "Seeker",
        onDismiss: {}
    )
}

#Preview("Level 25") {
    LevelUpCelebration(
        newLevel: 25,
        newTitle: "Sage",
        onDismiss: {}
    )
}
