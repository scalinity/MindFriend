import SwiftUI

/// Enhanced streak card that displays shield protection status
struct StreakCardWithShields: View {
    let currentStreak: Int
    let longestStreak: Int
    let shieldsRemaining: Int
    let shieldsMax: Int
    let recoveryAvailable: Bool
    let streakBeforeBreak: Int?
    let recoveryExpiresAt: Date?
    let onStartRecovery: (() -> Void)?

    @State private var showShieldUsedAnimation = false

    init(
        currentStreak: Int,
        longestStreak: Int,
        shieldsRemaining: Int = 1,
        shieldsMax: Int = 1,
        recoveryAvailable: Bool = false,
        streakBeforeBreak: Int? = nil,
        recoveryExpiresAt: Date? = nil,
        onStartRecovery: (() -> Void)? = nil
    ) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.shieldsRemaining = shieldsRemaining
        self.shieldsMax = shieldsMax
        self.recoveryAvailable = recoveryAvailable
        self.streakBeforeBreak = streakBeforeBreak
        self.recoveryExpiresAt = recoveryExpiresAt
        self.onStartRecovery = onStartRecovery
    }

    var body: some View {
        VStack(spacing: 12) {
            mainContent

            // Warning when shields depleted (but not in recovery mode)
            if shieldsRemaining == 0 && !recoveryAvailable && currentStreak > 0 {
                shieldsDepletedWarning
            }

            // Recovery banner when available
            if recoveryAvailable, let streakToRecover = streakBeforeBreak {
                RecoveryQuestBanner(
                    streakToRecover: streakToRecover,
                    expiresAt: recoveryExpiresAt ?? Date().addingTimeInterval(24 * 60 * 60),
                    onStart: { onStartRecovery?() }
                )
            }
        }
    }

    private var mainContent: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(currentStreak > 0 ? .orange : .gray)
                    Text(currentStreak > 0 ? "\(currentStreak) day streak" : "Start your streak!")
                        .fontWeight(.semibold)
                }

                if currentStreak >= 7 {
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        Text("Keep it up!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if longestStreak > 0 {
                    Text("Longest: \(longestStreak) days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Shield indicator
            VStack(alignment: .trailing, spacing: 4) {
                StreakShieldIndicator(
                    shieldsRemaining: shieldsRemaining,
                    shieldsMax: shieldsMax
                )

                Text(shieldStatusText)
                    .font(.caption2)
                    .foregroundStyle(shieldStatusColor)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    private var shieldsDepletedWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Complete today's quest to keep your streak!")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var shieldStatusText: String {
        if recoveryAvailable {
            return "Recovery available"
        } else if shieldsRemaining == 0 {
            return "No protection"
        } else if currentStreak > 0 {
            // Only say "Protected" when there's an active streak to protect
            return "Protected"
        } else {
            // No streak yet - show shield availability
            return shieldsRemaining == 1 ? "1 Shield ready" : "\(shieldsRemaining) Shields ready"
        }
    }

    private var shieldStatusColor: Color {
        if recoveryAvailable {
            return .orange
        } else if shieldsRemaining == 0 {
            return .orange
        } else if currentStreak > 0 {
            // Green when actively protecting a streak
            return .green
        } else {
            // Blue when shields are available but no streak yet
            return .blue
        }
    }
}

#Preview("With Shields") {
    VStack(spacing: 16) {
        StreakCardWithShields(
            currentStreak: 14,
            longestStreak: 21,
            shieldsRemaining: 2,
            shieldsMax: 3
        )

        StreakCardWithShields(
            currentStreak: 7,
            longestStreak: 7,
            shieldsRemaining: 0,
            shieldsMax: 1
        )

        StreakCardWithShields(
            currentStreak: 0,
            longestStreak: 14,
            shieldsRemaining: 1,
            shieldsMax: 1,
            recoveryAvailable: true,
            streakBeforeBreak: 14,
            recoveryExpiresAt: Date().addingTimeInterval(12 * 60 * 60)
        )
    }
    .padding()
}
