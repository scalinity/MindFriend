import SwiftUI

/// Sheet for selecting encouragement type before sending
struct EncouragementPickerSheet: View {
    let onSelect: (BuddyEncouragement.MessageType) -> Void
    var isLoading: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "hand.wave.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)

                    Text("Send Encouragement")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("Choose a message to send to your partner")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // Options
                VStack(spacing: 12) {
                    EncouragementOption(
                        icon: "hands.clap.fill",
                        title: "Encouragement",
                        description: "Send positive vibes and support",
                        isLoading: isLoading
                    ) {
                        onSelect(.encouragement)
                    }

                    EncouragementOption(
                        icon: "party.popper.fill",
                        title: "Celebration",
                        description: "Celebrate their achievements",
                        isLoading: isLoading
                    ) {
                        onSelect(.celebration)
                    }

                    EncouragementOption(
                        icon: "message.fill",
                        title: "Check In",
                        description: "Let them know you're thinking of them",
                        isLoading: isLoading
                    ) {
                        onSelect(.checkIn)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Encouragement Option

private struct EncouragementOption: View {
    let icon: String
    let title: String
    let description: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    EncouragementPickerSheet(
        onSelect: { type in
            print("Selected: \(type)")
        }
    )
}
