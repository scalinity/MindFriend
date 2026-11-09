import SwiftUI

/// Placeholder shown when partner hasn't shared data
struct PartnerPlaceholder: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(SupportTheme.textSecondary)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(SupportTheme.textSecondary)
                Spacer()
            }

            HStack {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)

                Spacer()
            }
        }
        .supportCard()
    }
}

#Preview {
    VStack(spacing: SupportTheme.Spacing.m) {
        PartnerPlaceholder(
            icon: "face.smiling",
            title: "Mood not shared",
            message: "Your partner hasn't enabled mood sharing yet"
        )

        PartnerPlaceholder(
            icon: "star",
            title: "Quests not shared",
            message: "Your partner hasn't enabled exercise sharing yet"
        )
    }
    .padding()
}
