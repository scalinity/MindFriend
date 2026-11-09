import SwiftUI
import UIKit

// MARK: - Feature Unlock View

/// A celebration view shown when a user unlocks new features through activation.
/// Displays a congratulatory message, lists unlocked features, and includes celebration animations.
struct FeatureUnlockView: View {
    let unlockedFeatures: [ActivationService.Feature]
    let onDismiss: () -> Void

    @State private var showContent = false
    @State private var showFeatures = false
    @State private var showButton = false
    @State private var particleOpacity: Double = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.15, green: 0.1, blue: 0.25),
                    Color(red: 0.1, green: 0.1, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Celebration particles
            CelebrationParticles().opacity(particleOpacity).ignoresSafeArea()

            // Main content
            VStack(spacing: 32) {
                Spacer()

                // Unlock icon with glow
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.blue.opacity(0.4), .clear],
                                center: .center,
                                startRadius: 40,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                        .blur(radius: 20)

                    // Icon background
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(color: .blue.opacity(0.5), radius: 20, x: 0, y: 10)

                    // Unlock icon
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 50, weight: .medium))
                        .foregroundStyle(.white)
                }
                .scaleEffect(showContent || reduceMotion ? 1 : 0.5)
                .opacity(showContent ? 1 : 0)

                // Congratulations text
                VStack(spacing: 12) {
                    Text("Congratulations!")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)

                    Text("You've unlocked new features")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent || reduceMotion ? 0 : 20)

                Spacer()

                // Unlocked features list
                VStack(spacing: 16) {
                    ForEach(unlockedFeatures.indices, id: \.self) { index in
                        let feature = unlockedFeatures[index]
                        UnlockedFeatureRow(feature: feature)
                            .opacity(showFeatures ? 1 : 0)
                            .offset(x: showFeatures || reduceMotion ? 0 : -50)
                            .accessibleAnimation(
                                .spring(response: 0.5, dampingFraction: 0.7)
                                    .delay(Double(index) * 0.15),
                                value: showFeatures
                            )
                    }
                }
                .padding(.horizontal, 32)

                Spacer()

                // Continue button
                Button(action: onDismiss) {
                    Text("Let's Go!")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: .blue.opacity(0.4), radius: 15, x: 0, y: 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton || reduceMotion ? 0 : 30)
            }
        }
        .onAppear {
            // Staggered animation sequence
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showContent = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation {
                    showFeatures = true
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showButton = true
                }
            }

            // Fade out particles after a while
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 1.0)) {
                    particleOpacity = 0.3
                }
            }
        }
    }
}

// MARK: - Unlocked Feature Row

private struct UnlockedFeatureRow: View {
    let feature: ActivationService.Feature

    var body: some View {
        HStack(spacing: 16) {
            // Checkmark icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
            }

            // Feature info
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.displayName)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(featureDescription)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            // Tab icon
            Image(systemName: tabIcon)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(16)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }

    private var featureDescription: String {
        switch feature {
        case .programs:
            return "Guided exercises and wellness programs"
        case .outcomes:
            return "Track your progress and insights"
        default:
            return ""
        }
    }

    private var tabIcon: String {
        switch feature {
        case .home: return "house.fill"
        case .chat: return "bubble.left.fill"
        case .profile: return "person.fill"
        case .programs: return "book.fill"
        case .outcomes: return "chart.line.uptrend.xyaxis"
        }
    }
}


// MARK: - Preview

#Preview("Feature Unlock") {
    FeatureUnlockView(
        unlockedFeatures: [.programs, .outcomes],
        onDismiss: {}
    )
}
