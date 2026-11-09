import SwiftUI

/// Card showing partner's status and encouragement button
struct PartnerStatusCard: View {
    let partnerInfo: PartnerInfo
    let onSendEncouragement: () -> Void

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            HStack(spacing: SupportTheme.Spacing.s) {
                // Avatar
                Circle()
                    .fill(SupportTheme.accent.opacity(0.2))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(String(partnerInfo.partnerName.prefix(1)).uppercased())
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(SupportTheme.accent)
                    )

                // Info
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(partnerInfo.partnerName)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        Image(systemName: statusIcon)
                            .font(.caption)
                            .foregroundStyle(statusColor)

                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }

                Spacer()


            }

            // Encouragement button
            Button(action: onSendEncouragement) {
                HStack {
                    Image(systemName: "hand.wave.fill")
                    Text(partnerInfo.hasCompletedToday ? "Send encouragement" : "Check in on them")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.supportSecondary)
            .accessibilityLabel("Send encouragement to \(partnerInfo.partnerName)")
        }
        .supportCard()
        .padding(.horizontal, SupportTheme.Spacing.m)
    }

    // MARK: - Status Helpers

    private var statusIcon: String {
        if partnerInfo.hasCompletedToday {
            return "checkmark.circle.fill"
        } else if Calendar.current.isDateInToday(partnerInfo.lastActive) {
            return "circle.fill"
        } else {
            return "moon.zzz.fill"
        }
    }

    private var statusColor: Color {
        if partnerInfo.hasCompletedToday {
            return SupportTheme.accent
        } else if Calendar.current.isDateInToday(partnerInfo.lastActive) {
            return SupportTheme.accent
        } else {
            return SupportTheme.accent
        }
    }

    private var statusMessage: String {
        if partnerInfo.hasCompletedToday {
            return "Completed quest today"
        } else if Calendar.current.isDateInToday(partnerInfo.lastActive) {
            return "Active today"
        } else {
            let days = Calendar.current.dateComponents([.day], from: partnerInfo.lastActive, to: Date()).day ?? 0
            if days == 1 {
                return "Last active yesterday"
            } else {
                return "Last active \(days) days ago"
            }
        }
    }
}

#Preview {
    VStack(spacing: SupportTheme.Spacing.l) {
        PartnerStatusCard(
            partnerInfo: PartnerInfo(
                partnerId: UUID(),
                partnerName: "Jamie",
                partnerStreak: 12,
                hasCompletedToday: true,
                lastActive: Date(),
                isSharingMood: true,
                isSharingExercises: true
            ),
            onSendEncouragement: {}
        )

        PartnerStatusCard(
            partnerInfo: PartnerInfo(
                partnerId: UUID(),
                partnerName: "Alex",
                partnerStreak: 5,
                hasCompletedToday: false,
                lastActive: Date().addingTimeInterval(-3 * 24 * 60 * 60),
                isSharingMood: false,
                isSharingExercises: false
            ),
            onSendEncouragement: {}
        )
    }
    .padding()
}
