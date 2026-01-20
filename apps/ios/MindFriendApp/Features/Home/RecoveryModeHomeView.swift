import SwiftUI

/// Simplified home view for users in Recovery Mode
/// Shows only 3 core actions to reduce cognitive load:
/// 1. Quick mood check-in
/// 2. Breathing exercise
/// 3. AI chat for support
/// See: kimispecs/03-recovery-mode-ux-spec.md
struct RecoveryModeHomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    let recoveryState: RecoveryModeState
    let onExitRecoveryMode: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Recovery mode banner
                recoveryBanner

                // Crisis resources always available
                if container.sosCoordinator.settings?.sosEnabled != false {
                    crisisResourceButton
                }

                // Three simplified actions
                VStack(spacing: 16) {
                    moodCheckInCard
                    breathingExerciseCard
                    aiChatCard
                }

                Spacer(minLength: 32)
            }
            .padding()
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Recovery Banner

    private var recoveryBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(.pink)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recovery Mode")
                        .font(.headline)

                    Text(recoveryState.reason?.displayText ?? "Taking things easy")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text("We've simplified things to help you focus on what matters most. Take your time.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            // Exit button (only if allowed)
            if recoveryState.canManuallyExit {
                Button(action: onExitRecoveryMode) {
                    HStack {
                        Image(systemName: "arrow.up.right.circle")
                        Text("Exit Recovery Mode")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            } else if let timeRemaining = recoveryState.timeUntilExitFormatted {
                Text("You can exit in \(timeRemaining)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.pink.opacity(0.1))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.pink.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Crisis Resources (Always Available)

    private var crisisResourceButton: some View {
        Button {
            appState.showCrisisResources = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square.fill")
                    .font(.title2)
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Crisis Resources")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text("Always available when you need support")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Crisis Resources")
        .accessibilityHint("Tap to access crisis support and resources")
    }

    // MARK: - Action Cards

    private var moodCheckInCard: some View {
        NavigationLink {
            MoodCheckInView()
        } label: {
            recoveryActionCard(
                icon: "face.smiling",
                iconColor: .yellow,
                title: "How are you feeling?",
                subtitle: "A quick check-in, no pressure",
                isPrimary: true
            )
        }
        .buttonStyle(.plain)
    }

    private var breathingExerciseCard: some View {
        NavigationLink {
            ExerciseLibraryView()
        } label: {
            recoveryActionCard(
                icon: "wind",
                iconColor: .cyan,
                title: "Breathing Exercise",
                subtitle: "A calm moment just for you",
                isPrimary: false
            )
        }
        .buttonStyle(.plain)
    }

    private var aiChatCard: some View {
        NavigationLink {
            ChatListView()
        } label: {
            recoveryActionCard(
                icon: "bubble.left.and.bubble.right.fill",
                iconColor: .purple,
                title: "Talk to MindFriend",
                subtitle: "I'm here to listen",
                isPrimary: false
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reusable Card Component

    private func recoveryActionCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        isPrimary: Bool
    ) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 56, height: 56)

                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            isPrimary
                ? iconColor.opacity(0.1)
                : Color(uiColor: .secondarySystemBackground)
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isPrimary ? iconColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RecoveryModeHomeView(
            recoveryState: RecoveryModeState(
                isActive: true,
                enteredAt: Date().addingTimeInterval(-12 * 3600), // 12 hours ago
                reason: .autoConsecutiveLowMood
            ),
            onExitRecoveryMode: {}
        )
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
    }
}
