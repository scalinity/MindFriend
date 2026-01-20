import SwiftUI

/// Banner displaying the current daily intent
struct DailyIntentBanner: View {
    let intent: DailyIntent
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 12) {
                // Intent icon
                Image(systemName: "target")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's Intent")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    Text(intent.intent)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                Spacer()

                // Time remaining
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(intent.formattedTimeRemaining)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

/// Compact version for use in chat header
struct DailyIntentChip: View {
    let intent: DailyIntent

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "target")
                .font(.caption)
            Text(intent.intent)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            LinearGradient(
                colors: [.purple.opacity(0.15), .blue.opacity(0.15)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
    }
}

/// Prompt to set daily intent when none is active
struct SetIntentPrompt: View {
    let onSetIntent: () -> Void

    var body: some View {
        Button(action: onSetIntent) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Set Today's Intent")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text("Focus your companion on what matters today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [.purple.opacity(0.1), .blue.opacity(0.1)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Banner") {
    let sampleIntent = DailyIntent(
        id: "123",
        intent: "Stay calm during my presentation at 2pm",
        createdAt: Date(),
        expiresAt: Date().addingTimeInterval(8 * 3600)
    )
    DailyIntentBanner(intent: sampleIntent)
        .padding()
}

#Preview("Chip") {
    let sampleIntent = DailyIntent(
        id: "123",
        intent: "Stay calm during my presentation",
        createdAt: Date(),
        expiresAt: Date().addingTimeInterval(8 * 3600)
    )
    DailyIntentChip(intent: sampleIntent)
        .padding()
}

#Preview("Prompt") {
    SetIntentPrompt(onSetIntent: {})
        .padding()
}
