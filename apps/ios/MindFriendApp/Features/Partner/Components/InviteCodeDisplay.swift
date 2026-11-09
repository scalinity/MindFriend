import SwiftUI

/// Display for an invite code with copy and share actions
struct InviteCodeDisplay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let code: String
    let expiresAt: Date

    @State private var showCopied = false

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                Text("Your invite code")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)

                // Code display
                ScrollView(.horizontal) {
                    HStack(spacing: SupportTheme.Spacing.xs) {
                        ForEach(Array(code.enumerated()), id: \.offset) { _, char in
                            Text(String(char))
                                .font(.title3.monospaced())
                                .fontWeight(.bold)
                                .foregroundStyle(SupportTheme.textPrimary)
                                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.primaryButtonHeight)
                                .background(SupportTheme.surface)
                                .cornerRadius(SupportTheme.controlRadius)
                        }
                    }

                }

                Text("Expires in \(daysRemaining) days")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            // Action buttons
            HStack(spacing: SupportTheme.Spacing.s) {
                Button(action: copyCode) {
                    HStack {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        Text(showCopied ? "Copied!" : "Copy Code")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(showCopied ? SupportTheme.accent : SupportTheme.textPrimary)
                }
                .buttonStyle(.supportSecondary)
                .accessibilityLabel("Copy invite code")

                ShareLink(item: shareMessage) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)

                }
                .buttonStyle(.supportSecondary)
                .accessibilityLabel("Share invite code")
            }
        }
        .supportCard()
    }

    private var daysRemaining: Int {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
        return max(0, days)
    }

    private var shareMessage: String {
        """
        Join me on MindFriend! Use my partner code: \(code)

        Open Partner Mode in MindFriend and enter this 8-character code exactly as shown. Uppercase and lowercase letters are different.

        Download MindFriend: https://getmindfriend.app
        """
    }

    private func copyCode() {
        UIPasteboard.general.string = code

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Show confirmation
        withAnimation(reduceMotion ? nil : .default) {
            showCopied = true
        }

        // Reset after delay
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation(reduceMotion ? nil : .default) {
                    showCopied = false
                }
            }
        }
    }
}

#Preview {
    InviteCodeDisplay(
        code: "Ab7x2Qp9",
        expiresAt: Date().addingTimeInterval(30 * 24 * 60 * 60)
    )
    .padding()
}
