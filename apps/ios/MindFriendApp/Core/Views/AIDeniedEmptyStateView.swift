// AIDeniedEmptyStateView.swift
// Reusable empty state shown when an AI feature's consent is denied or unknown.

import SwiftUI

struct AIDeniedEmptyStateView: View {
    let feature: AIFeature
    let offlineAlternativeTitle: String?
    let offlineAlternativeAction: (() -> Void)?

    @EnvironmentObject private var appState: AppState

    init(
        feature: AIFeature,
        offlineAlternativeTitle: String? = nil,
        offlineAlternativeAction: (() -> Void)? = nil
    ) {
        self.feature = feature
        self.offlineAlternativeTitle = offlineAlternativeTitle
        self.offlineAlternativeAction = offlineAlternativeAction
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor.opacity(0.6))

            Text(NSLocalizedString("ai.empty.title",
                value: "AI features are turned off",
                comment: "Title shown when an AI feature's consent is denied"))
                .font(.title3.weight(.semibold))

            Text(disabledCopy)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                Button {
                    appState.openAIConsentSettings = true
                } label: {
                    Text(NSLocalizedString("ai.empty.enableInSettings",
                        value: "Enable in Settings",
                        comment: "Primary CTA on AI denied empty state"))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }

                if let title = offlineAlternativeTitle, let action = offlineAlternativeAction {
                    Button(title, action: action)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)
        }
        .padding(.vertical, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(NSLocalizedString("ai.empty.a11y",
            value: "AI features are off for this section",
            comment: ""))
    }

    private var disabledCopy: String {
        switch feature {
        case .chat:
            return NSLocalizedString("ai.empty.chat",
                value: "Enable AI chat to talk with your wellness companion. We'll send your messages to xAI to generate replies.",
                comment: "")
        case .journalAI:
            return NSLocalizedString("ai.empty.journal_ai",
                value: "Enable AI journal analysis to get reframes and reflections. We'll send your journal text to xAI.",
                comment: "")
        case .voiceJournalAI:
            return NSLocalizedString("ai.empty.voice_journal_ai",
                value: "Enable AI voice journaling to transcribe and analyze recordings. We'll send your audio and transcript to xAI.",
                comment: "")
        case .imageGen:
            return NSLocalizedString("ai.empty.image_gen",
                value: "Enable AI image generation to create custom artwork. We'll send your prompt to OpenAI.",
                comment: "")
        case .insights:
            return NSLocalizedString("ai.empty.insights",
                value: "Enable AI insights to get weekly stories and pattern analysis. We'll send aggregated activity data to xAI.",
                comment: "")
        case .ttsVoice:
            return NSLocalizedString("ai.empty.tts_voice",
                value: "Enable spoken meditation playback. We'll send the meditation script text to Google Cloud Text-to-Speech.",
                comment: "")
        }
    }
}
