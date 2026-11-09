import SwiftUI

/// Full-screen celebration for a confirmed level change.
struct LevelUpCelebrationView: View {
    let oldLevel: Int
    let newLevel: Int
    let xpEarned: Int
    let onDismiss: () -> Void
    @State private var hasDismissed = false

    var body: some View {
        ZStack {
            SupportTheme.canvas.ignoresSafeArea()
                .onTapGesture { finish() }.accessibilityHidden(true)
            CelebrationParticles().ignoresSafeArea()
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    CelebrationEmblem(.text("\(newLevel)"), tint: SupportTheme.Celebration.gold, diameter: 120)
                    VStack(spacing: SupportTheme.Spacing.s) {
                        Text("Level up").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Text("Level \(oldLevel) → \(newLevel)")
                            .font(.title3).foregroundStyle(SupportTheme.textSecondary)
                        Label("+\(xpEarned) XP", systemImage: "sparkles")
                            .font(.headline).foregroundStyle(SupportTheme.Celebration.gold)
                    }
                    .celebrationReveal(delay: 0.2)
                    Button("Continue") { finish() }.buttonStyle(.supportPrimary)
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(SupportTheme.textPrimary)
                .frame(maxWidth: SupportTheme.readableWidth)
                .padding(SupportTheme.Spacing.l)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityAddTraits(.isModal)
        .onAppear { HapticManager.celebrationSuccess() }
        .task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish() {
        guard !hasDismissed else { return }
        hasDismissed = true
        onDismiss()
    }
}
