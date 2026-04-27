// AIFirstUseDisclosure.swift
// One-time bottom-sheet disclosure shown the first time a user lands on a screen
// that's about to send data to an AI provider (after consent has been granted).

import SwiftUI

struct AIFirstUseDisclosure: View {
    let feature: AIFeature
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text(NSLocalizedString("ai.firstUse.headline",
                    value: "Heads up",
                    comment: ""))
                    .font(.headline)
                Spacer()
            }
            Text("\(feature.dataSentDescription) Sent to \(feature.providerName).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(NSLocalizedString("ai.firstUse.learnMore",
                    value: "Learn more",
                    comment: "")) {
                    NotificationCenter.default.post(name: .openPrivacyPolicy, object: nil)
                    onDismiss()
                }
                Spacer()
                Button(NSLocalizedString("ai.firstUse.gotIt",
                    value: "Got it",
                    comment: ""),
                    action: onDismiss)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .padding()
    }
}

extension Notification.Name {
    static let openPrivacyPolicy = Notification.Name("openPrivacyPolicy")
}

private struct AIFirstUseModifier: ViewModifier {
    let feature: AIFeature
    @State private var shown = false

    private var seenKey: String { "ai_first_use_seen.\(feature.rawValue)" }

    func body(content: Content) -> some View {
        content
            .task {
                if !UserDefaults.standard.bool(forKey: seenKey) {
                    // Brief delay to avoid showing the moment the screen appears
                    try? await Task.sleep(for: .milliseconds(400))
                    if !UserDefaults.standard.bool(forKey: seenKey) {
                        withAnimation { shown = true }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if shown {
                    AIFirstUseDisclosure(feature: feature) {
                        UserDefaults.standard.set(true, forKey: seenKey)
                        withAnimation { shown = false }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
    }
}

extension View {
    /// Show a one-time disclosure the first time this feature is used.
    /// Should only be applied when the consent for `feature` is granted.
    func aiFirstUseDisclosure(_ feature: AIFeature) -> some View {
        modifier(AIFirstUseModifier(feature: feature))
    }
}
