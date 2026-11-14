import SwiftUI

struct FeatureUnlockView: View {
    let unlockedFeatures: [ActivationService.Feature]
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            SupportTheme.Hero.unlock.ignoresSafeArea()
            CelebrationParticles(palette: [SupportTheme.onHero, SupportTheme.onHero.opacity(0.7), SupportTheme.onHero.opacity(0.5)])
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    CelebrationEmblem(.symbol("lock.open"), tint: SupportTheme.Area.voice.palette.ink, diameter: 112)
                    VStack(spacing: SupportTheme.Spacing.xs) {
                        Text("More ways to find support").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                            .foregroundStyle(SupportTheme.onHero)
                        Text("You've unlocked new features").foregroundStyle(SupportTheme.onHero)
                    }
                    .multilineTextAlignment(.center)
                    .celebrationReveal(delay: 0.2)
                    VStack(spacing: SupportTheme.Spacing.s) {
                        ForEach(unlockedFeatures.indices, id: \.self) { index in
                            UnlockedFeatureRow(feature: unlockedFeatures[index])
                        }
                    }
                    .celebrationReveal(delay: 0.3)
                    Button("Continue", action: onDismiss)
                        .buttonStyle(CelebrationLightButtonStyle(label: SupportTheme.Area.voice.palette.deep))
                }
                .foregroundStyle(SupportTheme.textPrimary)
                .frame(maxWidth: SupportTheme.readableWidth)
                .padding(SupportTheme.Spacing.l)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityAddTraits(.isModal)
    }
}

private struct UnlockedFeatureRow: View {
    let feature: ActivationService.Feature

    var body: some View {
        SupportRowLabel(title: feature.displayName, subtitle: featureDescription, icon: tabIcon)
            .supportCard()
    }

    private var featureDescription: String {
        switch feature {
        case .programs: return "Guided exercises and wellness programs"
        case .outcomes: return "Track your progress and insights"
        default: return ""
        }
    }

    private var tabIcon: String {
        switch feature {
        case .home: return "house"
        case .chat: return "bubble.left"
        case .profile: return "person"
        case .programs: return "book"
        case .outcomes: return "chart.line.uptrend.xyaxis"
        }
    }
}
