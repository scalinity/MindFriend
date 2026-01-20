import SwiftUI

/// Display for an invite code with copy and share actions
struct InviteCodeDisplay: View {
    let code: String
    let expiresAt: Date

    @State private var showCopied = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Your invite code")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Code display
                HStack(spacing: 8) {
                    ForEach(Array(code.enumerated()), id: \.offset) { _, char in
                        Text(String(char))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 48)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(8)
                    }
                }

                Text("Expires in \(daysRemaining) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(action: copyCode) {
                    HStack {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        Text(showCopied ? "Copied!" : "Copy Code")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(showCopied ? .green : .primary)
                    .cornerRadius(10)
                }
                .accessibilityLabel("Copy invite code")

                ShareLink(item: shareMessage) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
                }
                .accessibilityLabel("Share invite code")
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    private var daysRemaining: Int {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
        return max(0, days)
    }

    private var shareMessage: String {
        """
        Join me on MindFriend! Use my partner code: \(code)

        Or tap this link: mindfriend://partner/accept?code=\(code)

        Download MindFriend: https://getmindfriend.app
        """
    }

    private func copyCode() {
        UIPasteboard.general.string = code

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Show confirmation
        withAnimation {
            showCopied = true
        }

        // Reset after delay
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation {
                    showCopied = false
                }
            }
        }
    }
}

#Preview {
    InviteCodeDisplay(
        code: "AB7X2Q",
        expiresAt: Date().addingTimeInterval(30 * 24 * 60 * 60)
    )
    .padding()
}
