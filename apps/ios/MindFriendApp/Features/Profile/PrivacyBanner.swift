import SwiftUI

/// A banner that displays privacy-first messaging to build user trust
struct PrivacyBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your Privacy Matters", systemImage: "lock.shield.fill")
                .font(.headline)
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 8) {
                PrivacyPoint(icon: "lock.fill", text: "Encrypted in transit and at rest")
                PrivacyPoint(icon: "eye.slash.fill", text: "We never sell your personal information")
                PrivacyPoint(icon: "arrow.down.doc.fill", text: "Export your data anytime")
                PrivacyPoint(icon: "trash.fill", text: "Delete your account and data permanently")
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your Privacy Matters. Encrypted in transit and at rest. We never sell your personal information. Export your data anytime. Delete your account and data permanently.")
    }
}

/// A single privacy point with an icon and text
private struct PrivacyPoint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.green)
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
