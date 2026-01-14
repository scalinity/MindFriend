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
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Usage This Month") {
                    HStack {
                        Label("Minutes Used", systemImage: "clock")
                        Spacer()
                        if voiceService.isPremium {
                            Text("Unlimited")
                                .foregroundStyle(.green)
                        } else {
                            let used = 3.0 - voiceService.minutesRemaining
                            Text("\(String(format: "%.1f", max(0, used))) / 3 min")
                                .foregroundStyle(used >= 2.4 ? .red : .secondary)
                        }
                    }

                    if !voiceService.isPremium {
                        Button {
                            showUpgradeSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                Text("Upgrade for Unlimited Voice")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Privacy") {
                    NavigationLink {
                        VoicePrivacyInfoView()
                    } label: {
                        Label("How Voice Data is Used", systemImage: "lock.shield")
                    }
                }

                Section("About Voices") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Voice Personalities")
                            .font(.subheadline.weight(.semibold))
                        Text("Each voice has a unique personality suited for different needs. Ara is warm and conversational, Rex is professional, Sal is calm and balanced, Eve is energetic, and Leo is authoritative.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
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
            HStack(spacing: 12) {
                Circle()
                    .fill(voiceColor(voice))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(voice.displayName.prefix(1))
                            .font(.headline)
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(voice.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)

                        Text("(\(voice.gender))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(voice.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.accentColor)
                } else if !isAvailable {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isAvailable ? 1.0 : 0.6)
    }

    private func voiceColor(_ voice: GrokVoice) -> Color {
        switch voice {
        case .ara: return .pink
        case .rex: return .blue
        case .sal: return .purple
        case .eve: return .orange
        case .leo: return .green
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
            VStack(alignment: .leading, spacing: 20) {
                Text("Voice Data Privacy")
                    .font(.title2.bold())

                Text("MindFriend takes your privacy seriously. Here's how we handle voice data:")
                    .foregroundStyle(.secondary)

                VStack(spacing: 16) {
                    PrivacyInfoCard(
                        icon: "server.rack",
                        title: "Secure Processing",
                        description: "Voice is processed through encrypted connections. Audio data is not stored after your conversation ends."
                    )

                    PrivacyInfoCard(
                        icon: "text.bubble",
                        title: "Transcription Privacy",
                        description: "Transcripts are shown to you in real-time but are not permanently stored unless you save them."
                    )

                    PrivacyInfoCard(
                        icon: "trash",
                        title: "No Voice Storage",
                        description: "We don't store voice recordings, voice prints, or any raw audio data. Your voice remains private."
                    )

                    PrivacyInfoCard(
                        icon: "shield.checkered",
                        title: "Safety Monitoring",
                        description: "Voice conversations include safety monitoring for crisis keywords to ensure your wellbeing, just like text chats."
                    )

                    PrivacyInfoCard(
                        icon: "lock.fill",
                        title: "End-to-End Security",
                        description: "All communication uses TLS encryption. Your API keys and tokens are never exposed to the client."
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Voice Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyInfoCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
}
