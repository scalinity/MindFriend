import SwiftUI

struct VoiceSettingsView: View {
    @ObservedObject var voiceService: GrokVoiceService
    @Environment(\.dismiss) private var dismiss

    @State private var showUpgradeSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(GrokVoice.allCases) { voice in
                        voiceRow(voice)
                    }
                } header: {
                    Text("AI Voice")
                } footer: {
                    if !voiceService.isPremium {
                        Text("Upgrade to Premium to unlock all 5 voices.")
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
                .listRowBackground(SupportTheme.surface)

                Section("Usage This Month") {
                    HStack {
                        Label("Minutes Used", systemImage: "clock")
                        Spacer()
                        if voiceService.isPremium {
                            Text("Premium access")
                                .foregroundStyle(SupportTheme.textSecondary)
                        } else {
                            let used = 3.0 - voiceService.minutesRemaining
                            Text("\(String(format: "%.1f", max(0, used))) / 3 min")
                                .foregroundStyle(used >= 2.4 ? .red : SupportTheme.textSecondary)
                        }
                    }

                    if !voiceService.isPremium {
                        Button {
                            showUpgradeSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(SupportTheme.Celebration.gold)
                                Text("Explore Premium voice")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(SupportTheme.textSecondary)
                            }
                        }
                    }
                }

                .listRowBackground(SupportTheme.surface)

                Section("Privacy") {
                    NavigationLink {
                        VoicePrivacyInfoView()
                    } label: {
                        Label("How Voice Data is Used", systemImage: "lock.shield")
                    }
                }

                .listRowBackground(SupportTheme.surface)

                Section("About Voices") {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        Text("Voice Personalities")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            "Each voice has a unique personality suited for different needs. Ara is warm and conversational, Rex is professional, Sal is calm and balanced, Eve is energetic, and Leo is authoritative."
                        )
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .padding(.vertical, SupportTheme.Spacing.xxs)
                }

                .listRowBackground(SupportTheme.surface)
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("Voice Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showUpgradeSheet) {
                SubscriptionView()
            }
        }
    }

    @ViewBuilder
    private func voiceRow(_ voice: GrokVoice) -> some View {
        let isAvailable = voiceService.availableVoices.contains(voice)
        let isSelected = voiceService.currentVoice == voice

        Button {
            selectVoice(voice)
        } label: {
            HStack(spacing: SupportTheme.Spacing.s) {
                Circle()
                    .fill(voiceColor(voice))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(voice.displayName.prefix(1))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                            .foregroundStyle(SupportTheme.textPrimary)
                    }

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    HStack(spacing: SupportTheme.Spacing.xs) {
                        Text(voice.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(SupportTheme.textPrimary)

                        Text("(\(voice.gender))")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Text(voice.description)
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(SupportTheme.accent)
                } else if !isAvailable {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isAvailable ? 1.0 : 0.6)
    }

    private func voiceColor(_ voice: GrokVoice) -> Color {
        switch voice {
        case .ara: return SupportTheme.accent
        case .rex: return SupportTheme.accent
        case .sal: return SupportTheme.accent
        case .eve: return SupportTheme.accent
        case .leo: return SupportTheme.accent
        }
    }

    private func selectVoice(_ voice: GrokVoice) {
        guard voiceService.availableVoices.contains(voice) else {
            showUpgradeSheet = true
            return
        }

        Task {
            try? await voiceService.setVoice(voice)
        }
    }
}

struct VoicePrivacyInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                Text("Voice Data Privacy")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)

                Text("MindFriend takes your privacy seriously. Here's how we handle voice data:")
                    .foregroundStyle(SupportTheme.textSecondary)

                VStack(spacing: SupportTheme.Spacing.m) {
                    PrivacyInfoCard(
                        icon: "server.rack",
                        title: "Secure Processing",
                        description:
                            "Live audio goes through MindFriend’s relay to the configured AI provider over encrypted connections. Review the privacy policy for processor and retention details."
                    )

                    PrivacyInfoCard(
                        icon: "text.bubble",
                        title: "Transcription Privacy",
                        description:
                            "Live captions are marked while partial. Completed turns are saved to your conversation after confirmation; a failed save remains visible for retry."
                    )

                    PrivacyInfoCard(
                        icon: "trash",
                        title: "Live Audio",
                        description:
                            "MindFriend does not create a saved recording of this call. Your conversation keeps the confirmed text transcript."
                    )

                    PrivacyInfoCard(
                        icon: "shield.checkered",
                        title: "Support Options",
                        description:
                            "You can stop voice or switch to text. Voice is not an emergency service; crisis resources remain available from the app."
                    )

                    PrivacyInfoCard(
                        icon: "lock.fill",
                        title: "Encrypted Connections",
                        description:
                            "The relay keeps provider API keys on the server. Your app uses its signed-in account to connect."
                    )
                }
            }
            .padding()
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Voice Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyInfoCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: SupportTheme.Spacing.m) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(SupportTheme.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(description)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)
    }
}
