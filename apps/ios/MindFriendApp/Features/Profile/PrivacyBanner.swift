import SwiftUI

/// A banner that displays privacy-first messaging to build user trust
struct PrivacyBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Label("Your Privacy Matters", systemImage: "lock.shield.fill")
                .font(.headline)
                .foregroundColor(SupportTheme.accent)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                PrivacyPoint(icon: "lock.fill", text: "Encrypted in transit and at rest")
                PrivacyPoint(icon: "eye.slash.fill", text: "We never sell your personal information")
                PrivacyPoint(icon: "arrow.down.doc.fill", text: "Export your data anytime")
                PrivacyPoint(icon: "trash.fill", text: "Delete your account and data permanently")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Your Privacy Matters. Encrypted in transit and at rest. We never sell your personal information. Export your data anytime. Delete your account and data permanently."
        )
    }
}

/// A single privacy point with an icon and text
private struct PrivacyPoint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(SupportTheme.accent)
                .frame(width: 20)
            Text(text)
                .font(.caption)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        PrivacyBanner()
            .padding()
    }
}
