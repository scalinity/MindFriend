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
        .onChange(of: voiceService.connectionState) { _, newState in
            // Show paywall when quota is exhausted
            if case .error(let message) = newState,
               message.localizedCaseInsensitiveContains("quota") {
                errorMessage = "You've used all your free voice minutes for today."
                showUpgradeSheet = true
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
                // Outer pulse rings - animate when user speaking or AI speaking
                if voiceService.isUserSpeaking || voiceService.isSpeaking {
                    Circle()
                        .fill(orbColor.opacity(0.2))
                        .frame(width: 180, height: 180)
                        .scaleEffect(1.3)
                        .animation(
                            .easeInOut(duration: voiceService.isUserSpeaking ? 0.5 : 1.0)
                                .repeatForever(autoreverses: true),
                            value: voiceService.isUserSpeaking || voiceService.isSpeaking
                        )

                    Circle()
                        .fill(orbColor.opacity(0.1))
                        .frame(width: 220, height: 220)
                        .scaleEffect(1.4)
                        .animation(
                            .easeInOut(duration: voiceService.isUserSpeaking ? 0.6 : 1.2)
                                .repeatForever(autoreverses: true),
                            value: voiceService.isUserSpeaking || voiceService.isSpeaking
                        )
                } else if voiceService.isListening {
                    // Subtle pulse when listening but not speaking
                    Circle()
                        .fill(orbColor.opacity(0.1))
                        .frame(width: 160, height: 160)
                        .scaleEffect(1.1)
                        .animation(
                            .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                            value: voiceService.isListening
                        )
                }

                // Main orb
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
                    .scaleEffect(voiceService.isUserSpeaking ? 1.05 : 1.0)
                    .animation(.spring(response: 0.2), value: voiceService.isUserSpeaking)

                Image(systemName: orbIcon)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.white)
            }
            .animation(.spring(response: 0.3), value: voiceService.isListening)
            .animation(.spring(response: 0.3), value: voiceService.isSpeaking)
            .animation(.spring(response: 0.2), value: voiceService.isUserSpeaking)

            Text(voiceStatusText)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var orbColor: Color {
        if voiceService.isUserSpeaking {
            return .green // User is speaking - green for "active"
        } else if voiceService.isSpeaking {
            return .accentColor // AI is responding
        } else if voiceService.isListening {
            return .orange // Ready and listening
        } else {
            return Color(.systemGray3)
        }
    }

    private var orbIcon: String {
        if voiceService.isUserSpeaking {
            return "waveform" // User speaking
        } else if voiceService.isSpeaking {
            return "speaker.wave.2.fill" // AI speaking
        } else if voiceService.isListening {
            return "ear" // Listening for speech
        } else {
            return "mic.fill"
        }
    }

    private var voiceStatusText: String {
        switch voiceService.connectionState {
        case .connected:
            if voiceService.isUserSpeaking {
                return "Listening..."
            } else if voiceService.isSpeaking {
                return "\(voiceService.currentVoice.displayName) is speaking..."
            } else if voiceService.isListening {
                return "Start talking anytime"
            } else {
                return "Initializing..."
            }
        case .connecting:
            return "Connecting..."
        case .reconnecting:
            return "Reconnecting..."
        case .disconnected:
            return "Disconnected"
        case .error:
            return "Connection error"
        }
    }

    // MARK: - Voice Controls

    private var voiceControls: some View {
        HStack(spacing: 48) {
            // End call button
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

            // Center button - Force send (for edge cases when VAD doesn't trigger)
            // With server VAD, this is optional - conversation flows automatically
            Button {
                voiceService.stopListeningAndRespond()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(voiceService.isUserSpeaking ? Color.green : Color.accentColor.opacity(0.6))
                    .clipShape(Circle())
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .disabled(!voiceService.connectionState.isConnected || voiceService.isSpeaking)
            .opacity(voiceService.connectionState.isConnected && !voiceService.isSpeaking ? 1.0 : 0.5)

            // Switch to text button
            Button {
                Task {
                    await voiceService.disconnect()
                    dismiss()
                }
                onSwitchToText()
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
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
}
