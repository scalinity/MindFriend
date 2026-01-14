import SwiftUI
import Supabase

struct VoiceChatView: View {
    @StateObject private var voiceService: GrokVoiceService
    @Environment(\.dismiss) private var dismiss

    @State private var showSettings = false
    @State private var showUpgradeSheet = false
    @State private var errorMessage: String?
    @State private var showError = false

    private let onSwitchToText: () -> Void

    init(supabase: SupabaseClient, onSwitchToText: @escaping () -> Void) {
        _voiceService = StateObject(wrappedValue: GrokVoiceService(supabase: supabase))
        self.onSwitchToText = onSwitchToText
    }

    var body: some View {
        VStack(spacing: 0) {
            if !voiceService.isPremium {
                usageBar
            }

            connectionStatus

            Spacer()

            voiceVisualization

            Spacer()

            voiceControls
        }
        .background(Color(.systemBackground))
        .navigationTitle("Voice Mode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            VoiceSettingsView(voiceService: voiceService)
        }
        .sheet(isPresented: $showUpgradeSheet) {
            SubscriptionView()
        }
        .alert("Voice Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
            if errorMessage?.localizedCaseInsensitiveContains("quota") == true ||
                errorMessage?.localizedCaseInsensitiveContains("premium") == true {
                Button("Upgrade") {
                    showUpgradeSheet = true
                }
            }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .task {
            await connectVoice()
        }
        .onDisappear {
            Task {
                await voiceService.disconnect()
            }
        }
    }

    // MARK: - Usage Bar

    private var usageBar: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                Text("Voice Minutes")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(String(format: "%.1f", voiceService.minutesRemaining)) / 3 min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(height: 6)

                    Capsule()
                        .fill(usageBarColor)
                        .frame(width: geometry.size.width * usagePercentage, height: 6)
                }
            }
            .frame(height: 6)

            if usagePercentage >= 0.8 {
                Button {
                    showUpgradeSheet = true
                } label: {
                    Text(usagePercentage >= 0.95 ? "Upgrade for Unlimited" : "Running low - Upgrade")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    private var usagePercentage: Double {
        let total = 3.0
        let used = total - voiceService.minutesRemaining
        return min(1.0, max(0, used / total))
    }

    private var usageBarColor: Color {
        if usagePercentage >= 0.95 { return .red }
        if usagePercentage >= 0.8 { return .orange }
        return .accentColor
    }

    // MARK: - Connection Status

    private var connectionStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch voiceService.connectionState {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var statusText: String {
        switch voiceService.connectionState {
        case .connected:
            return "Connected • \(voiceService.currentVoice.displayName)"
        case .connecting:
            return "Connecting..."
        case .reconnecting:
            return "Reconnecting..."
        case .disconnected:
            return "Disconnected"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    // MARK: - Voice Visualization

    private var voiceVisualization: some View {
        VStack(spacing: 24) {
            if !voiceService.transcribedText.isEmpty {
                Text(voiceService.transcribedText)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .scale))
            }

            ZStack {
                if voiceService.isListening || voiceService.isSpeaking {
                    Circle()
                        .fill(orbColor.opacity(0.2))
                        .frame(width: 180, height: 180)
                        .scaleEffect(voiceService.isListening || voiceService.isSpeaking ? 1.3 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                            value: voiceService.isListening || voiceService.isSpeaking
                        )

                    Circle()
                        .fill(orbColor.opacity(0.1))
                        .frame(width: 220, height: 220)
                        .scaleEffect(voiceService.isListening || voiceService.isSpeaking ? 1.4 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                            value: voiceService.isListening || voiceService.isSpeaking
                        )
                }

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [orbColor, orbColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                    .shadow(color: orbColor.opacity(0.4), radius: 20, x: 0, y: 10)

                Image(systemName: orbIcon)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.white)
            }
            .animation(.spring(response: 0.4), value: voiceService.isListening)
            .animation(.spring(response: 0.4), value: voiceService.isSpeaking)

            Text(voiceStatusText)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var orbColor: Color {
        if voiceService.isListening {
            return .red
        } else if voiceService.isSpeaking {
            return .accentColor
        } else {
            return Color(.systemGray3)
        }
    }

    private var orbIcon: String {
        if voiceService.isListening {
            return "waveform"
        } else if voiceService.isSpeaking {
            return "speaker.wave.2.fill"
        } else {
            return "mic.fill"
        }
    }

    private var voiceStatusText: String {
        switch voiceService.connectionState {
        case .connected:
            if voiceService.isListening {
                return "Listening..."
            } else if voiceService.isSpeaking {
                return "Speaking..."
            } else {
                return "Tap to speak"
            }
        case .connecting:
            return "Connecting..."
        case .reconnecting:
            return "Reconnecting..."
        case .disconnected:
            return "Tap to connect"
        case .error:
            return "Connection error"
        }
    }

    // MARK: - Voice Controls

    private var voiceControls: some View {
        HStack(spacing: 48) {
            Button {
                Task {
                    await voiceService.disconnect()
                    dismiss()
                }
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.red)
                    .clipShape(Circle())
            }

            Button {
                toggleVoice()
            } label: {
                Image(systemName: voiceService.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(voiceService.isListening ? Color.red : Color.accentColor)
                    .clipShape(Circle())
                    .shadow(color: (voiceService.isListening ? Color.red : Color.accentColor).opacity(0.4), radius: 10, x: 0, y: 5)
            }
            .disabled(!voiceService.connectionState.isConnected)
            .opacity(voiceService.connectionState.isConnected ? 1.0 : 0.5)

            Button {
                Task {
                    await voiceService.disconnect()
                    dismiss()
                }
                onSwitchToText()
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 22))
                    .foregroundStyle(.accentColor)
                    .frame(width: 56, height: 56)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Circle())
            }
        }
        .padding(.bottom, 48)
    }

    // MARK: - Actions

    private func connectVoice() async {
        do {
            try await voiceService.connect()
        } catch let error as VoiceError {
            errorMessage = error.localizedDescription
            showError = true

            if case .quotaExceeded = error {
                showUpgradeSheet = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func toggleVoice() {
        if voiceService.isListening {
            voiceService.stopListening()
        } else {
            do {
                try voiceService.startListening()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
