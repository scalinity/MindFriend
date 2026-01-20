import SwiftUI

/// Card showing partner's status, streak, and encouragement button
struct PartnerStatusCard: View {
    let partnerInfo: PartnerInfo
    let onSendEncouragement: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                // Avatar
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(String(partnerInfo.partnerName.prefix(1)).uppercased())
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.accentColor)
                    )

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(partnerInfo.partnerName)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Image(systemName: statusIcon)
                            .font(.caption)
                            .foregroundStyle(statusColor)

                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Streak
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("\(partnerInfo.partnerStreak)")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)

                    Text("streak")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
                .padding(.vertical, 12)
                .background(Color.accentColor.opacity(0.1))
                .foregroundStyle(Color.accentColor)
                .cornerRadius(10)
            }
            .accessibilityLabel("Send encouragement to \(partnerInfo.partnerName)")
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .padding(.horizontal, 16)
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
            return .green
        } else if Calendar.current.isDateInToday(partnerInfo.lastActive) {
            return .blue
        } else {
            return .orange
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
    VStack(spacing: 20) {
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
