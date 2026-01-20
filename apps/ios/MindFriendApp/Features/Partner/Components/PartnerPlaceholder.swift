import SwiftUI

/// Placeholder shown when partner hasn't shared data
struct PartnerPlaceholder: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .cornerRadius(12)
    }
}

#Preview {
    VStack(spacing: 16) {
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
