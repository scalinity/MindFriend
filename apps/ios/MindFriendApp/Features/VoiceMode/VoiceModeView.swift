import SwiftUI
import UIKit
import Supabase

// MARK: - Voice Mode View

/// Full-screen voice conversation interface with dynamic orb visualization.
///
/// Nothing here connects, prepares a session or starts the microphone until the person taps
/// "Start voice". Without support-session access the view shows a truthful unavailable state and
/// offers text; there is no legacy fallback. Transcript persistence is owned by the voice service
/// (typed final events through `VoiceSupportAccess`), not by this view.
struct VoiceModeView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState

    // MARK: - State

    @StateObject private var voiceService: GrokVoiceService
    @StateObject private var voiceCoordinator = VoiceCoordinator()
    @State private var stateMachine = VoiceStateMachine()

    @State private var showSettings = false
    @State private var showUpgradeSheet = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showMicrophoneSettings = false
    @State private var showCaptions = true
    @State private var startTask: Task<Void, Never>?
    @State private var isStartingVoice = false
    /// Owns the End / text-switch decision, bound to an exit generation (see `VoiceLeaveController`).
    @StateObject private var leaveController = VoiceLeaveController()

    // MARK: - Callbacks / access

    private let onDismiss: (() -> Void)?
    private let onSwitchToText: (() -> Void)?
    private let supportAccess: (any VoiceSupportAccess)?

    // MARK: - Initialization

    init(
        supabase: SupabaseClient,
        onDismiss: (() -> Void)? = nil,
        onSwitchToText: (() -> Void)? = nil,
        supportAccess: (any VoiceSupportAccess)? = nil
    ) {
        _voiceService = StateObject(wrappedValue: GrokVoiceService(supabase: supabase))
        self.onDismiss = onDismiss
        self.onSwitchToText = onSwitchToText
        self.supportAccess = supportAccess
    }

    private enum Mode {
        case unavailable
        case ready
        case starting
        case active
    }

    private var mode: Mode {
        if supportAccess == nil { return .unavailable }
        if isStartingVoice || voiceService.connectionState == .connecting { return .starting }
        if voiceService.connectionState.isConnected { return .active }
        return .ready
    }

    // MARK: - Body

    var body: some View {
        // Premium gate: Voice mode is premium-only
        if appState.entitlements.tier != .premium {
            VoiceModePaywallView(onUpgrade: {
                appState.showPaywall = true
            }, onDismiss: {
                dismiss()
                onDismiss?()
            })
        } else {
            voiceModeContent
        }
    }

    // MARK: - Voice Mode Content (Premium Only)

    @ViewBuilder
    private var voiceModeContent: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                backgroundGradient

                VStack(spacing: 0) {
                    // Top bar with controls
                    topBar
                        .padding(.top, geometry.safeAreaInsets.top > 0 ? 0 : 16)

                    switch mode {
                    case .unavailable:
                        ScrollView {
                            VoiceUnavailablePanel(onUseText: { leave(reason: .switchedToText) })
                                .padding(.top, 48)
                                .padding(.bottom, 40)
                        }
                    case .ready:
                        ScrollView {
                            VStack(spacing: 20) {
                                VoiceTranscriptSaveBanner(
                                    unsaved: voiceService.unsavedTranscriptCount,
                                    rejected: voiceService.rejectedTranscriptCount,
                                    canLeave: leaveController.isHolding,
                                    onRetry: retrySaving,
                                    onLeaveWithoutSaving: discardAndLeave
                                )
                                VoiceStartPanel(
                                    preview: supportAccess?.preview() ?? VoiceSupportPreview(scope: .conversationOnly),
                                    notice: stopNotice,
                                    isStarting: false,
                                    onStart: startVoice,
                                    onUseText: { leave(reason: .switchedToText) }
                                )
                            }
                            .padding(.top, 32)
                            .padding(.bottom, 40)
                        }
                    case .starting:
                        startingContent
                    case .active:
                        activeContent(size: geometry.size, safeBottom: geometry.safeAreaInsets.bottom)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            VoiceSettingsView(voiceService: voiceService)
        }
        .sheet(isPresented: $showUpgradeSheet) {
            SubscriptionView()
        }
        .alert("Voice Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
            if showMicrophoneSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            if shouldShowUpgradeButton {
                Button("Upgrade") {
                    showUpgradeSheet = true
                }
            }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .task {
            // Wiring only. Nothing connects on presentation: the person must tap Start voice.
            voiceCoordinator.onStateEvent = { event in
                _ = stateMachine.send(event)
            }
            voiceCoordinator.onQuotaExceeded = {
                showUpgradeSheet = true
            }
            voiceService.delegate = voiceCoordinator
            leaveController.exitScreen = { exit in
                dismiss()
                switch exit {
                case .close: onDismiss?()
                case .text: onSwitchToText?()
                }
            }
        }
        .task {
            // Any originating owner / privacy / context change retires pending leave decisions, even
            // after End has already torn the session's own monitoring down.
            if let stream = supportAccess?.invalidations() {
                await leaveController.retireOnInvalidation(from: stream)
            }
        }
        .onDisappear {
            // Safety net only. Correctness does not depend on this callback.
            startTask?.cancel()
            voiceService.stopNow(.userEnded)
        }
        .onChange(of: scenePhase) { _, phase in
            // Background or lock stops capture. Returning shows a paused state, never a live mic.
            if phase == .background {
                startTask?.cancel()
                voiceService.stopNow(.appBackgrounded)
            }
        }
        .onChange(of: appState.accountEpoch) { _, _ in
            handleAccountChange()
        }
        .onChange(of: appState.currentUser?.id) { _, _ in
            handleAccountChange()
        }
        .onChange(of: voiceService.lastStopReason) { _, reason in
            leaveController.noteStop(reason)
            guard reason != nil else { return }
            stateMachine.reset()
            if let message = reason?.statusMessage {
                VoiceAccessibility.announce(message)
            } else {
                VoiceAccessibility.announce("Voice stopped. Microphone is off.")
            }
        }
        .onChange(of: voiceService.isMuted) { _, muted in
            syncMuteIntoStateMachine(muted)
        }
        .onChange(of: voiceService.hasUnresolvedTranscript) { _, _ in
            // Pending, in-flight AND rejected finals all hold the screen. A pending final turning into
            // a rejected one during End must not release the hold.
            leaveController.autoLeaveIfResolved(service: voiceService)
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.12),
                Color(red: 0.08, green: 0.08, blue: 0.18),
                Color(red: 0.05, green: 0.05, blue: 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Close button
            Button {
                leave(reason: .userEnded)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close voice")

            Spacer()

            if mode == .active || mode == .ready {
                // Captions toggle
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                        showCaptions.toggle()
                    }
                } label: {
                    Image(systemName: showCaptions ? "captions.bubble.fill" : "captions.bubble")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(showCaptions ? .white : .white.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(showCaptions ? 0.2 : 0.1))
                        .clipShape(Circle())
                }
                .accessibilityLabel(showCaptions ? "Hide captions" : "Show captions")

                // Voice selection
                Button {
                    showSettings = true
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(voiceColor(voiceService.currentVoice))
                            .frame(width: 10, height: 10)
                        Text(voiceService.currentVoice.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Voice: \(voiceService.currentVoice.displayName). Tap to change.")

                // Settings
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Voice settings")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - Modes

    private var startingContent: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("Starting voice…")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
            Text("The microphone turns on once the connection is ready.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Cancel") {
                startTask?.cancel()
                leave(reason: .userEnded, dismissWhenDone: false)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .controlSize(.large)
            Spacer()
        }
        .accessibilityElement(children: .contain)
    }

    private func activeContent(size: CGSize, safeBottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()

            // Captions area
            if showCaptions {
                captionsView
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }

            // Central orb
            orbSection(size: min(size.width * 0.55, 280))

            Spacer()

            // Status text
            statusView
                .padding(.bottom, 24)

            // Bottom controls
            bottomControls
                .padding(.bottom, safeBottom > 0 ? 24 : 40)
        }
    }

    // MARK: - Captions View

    private var captionsView: some View {
        VoiceCaptionView(caption: voiceService.caption, reduceMotion: reduceMotion)
    }

    // MARK: - Orb Section

    private func orbSection(size: CGFloat) -> some View {
        let orbConfig = OrbView.Configuration(
            state: stateMachine.state,
            micLevel: voiceService.micLevel,
            playbackLevel: voiceService.playbackLevel,
            reducedMotion: reduceMotion
        )

        return OrbContainerView(
            config: orbConfig,
            size: size,
            onTap: {
                handleOrbTap()
            }
        )
        .shadow(color: orbShadowColor.opacity(0.4), radius: 40, x: 0, y: 20)
        .animation(reduceMotion ? nil : .spring(response: 0.4), value: stateMachine.state)
    }

    private var orbShadowColor: Color {
        switch stateMachine.state.orbColor {
        case .userSpeaking:
            return .green
        case .aiSpeaking:
            return .blue
        case .thinking:
            return .purple
        case .ready:
            return .blue.opacity(0.6)
        case .error:
            return .red
        default:
            return .gray
        }
    }

    // MARK: - Status View

    private var statusView: some View {
        VStack(spacing: 8) {
            // Explicit capture indicator: text and icon, never only motion or color.
            VoiceCaptureIndicator(isListening: voiceService.isListening, isMuted: voiceService.isMuted)

            // Connection status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionStatusColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                Text(connectionStatusText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }

            // State status
            Text(stateMachine.state.statusText)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.95))

            Text("Up to two minutes per session")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
            Text(voiceService.isPremium ? "Unlimited monthly voice minutes" :
                String(format: "%.1f of 3 free monthly voice minutes remaining", voiceService.minutesRemaining))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 24)
    }

    private var connectionStatusColor: Color {
        switch voiceService.connectionState {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }

    private var connectionStatusText: String {
        switch voiceService.connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting…"
        case .reconnecting:
            return "Reconnecting…"
        case .disconnected:
            return "Disconnected"
        case .error:
            return "Voice stopped"
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 32) {
            // Mute button (the service owns the mute choice)
            Button {
                toggleMute()
            } label: {
                Image(systemName: voiceService.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(voiceService.isMuted ? .red : .white)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(voiceService.isMuted ? Color.red.opacity(0.2) : Color.white.opacity(0.15))
                    )
            }
            .accessibilityLabel(voiceService.isMuted ? "Unmute microphone" : "Mute microphone")

            // End call button
            Button {
                leave(reason: .userEnded)
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(
                        Circle()
                            .fill(Color.red)
                    )
                    .shadow(color: .red.opacity(0.4), radius: 15, x: 0, y: 8)
            }
            .accessibilityLabel("End voice session")

            // Switch to text button
            Button {
                leave(reason: .switchedToText)
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.15))
                    )
            }
            .accessibilityLabel("Switch to text chat")
            .accessibilityHint("Stops the microphone and returns to this conversation.")
        }
    }

    // MARK: - Actions

    /// Explicit "Start voice": the only place a session is prepared or connected from this view.
    private func startVoice() {
        guard let supportAccess, startTask == nil else { return }
        // A new explicit Start makes every older End / text-switch decision obsolete: its continuation
        // can no longer dismiss this screen or show a hold for a session that has since been replaced.
        leaveController.startBegan()
        stateMachine.reset()
        _ = stateMachine.send(.tapStart)
        _ = stateMachine.send(.micPermissionGranted)
        isStartingVoice = true
        startTask = Task { @MainActor in
            defer {
                startTask = nil
                isStartingVoice = false
            }
            do {
                try await voiceService.startVoice(access: supportAccess, startMuted: false)
                _ = stateMachine.send(.connected)
                VoiceAccessibility.announce("Voice started. Microphone is on.")
            } catch {
                handleStartError(error)
            }
        }
    }

    /// End, then leave. Capture is already stopped when `end` starts waiting, and the wait for remote
    /// work is bounded, so a suspended server call cannot hold this screen. The decision that follows is
    /// bound to an exit generation and ignored if a newer Start has begun in the meantime.
    private func leave(reason: VoiceStopReason, dismissWhenDone: Bool = true) {
        startTask?.cancel()
        Task { @MainActor in
            await leaveController.leave(reason: reason, dismissWhenDone: dismissWhenDone, service: voiceService)
        }
    }

    private func retrySaving() {
        Task { @MainActor in
            await leaveController.retry(service: voiceService)
        }
    }

    /// The explicit, separate decision to give up finals that were not acknowledged.
    private func discardAndLeave() {
        leaveController.discardAndLeave(service: voiceService)
    }

    private func handleAccountChange() {
        // Do not depend on disappearance: stop capture now, before anything else can run.
        startTask?.cancel()
        leaveController.invalidate()
        voiceService.stopNow(.accountChanged)
        dismiss()
        onDismiss?()
    }

    private func toggleMute() {
        do {
            try voiceService.setMuted(!voiceService.isMuted)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// The service owns the mute choice; the orb state machine only mirrors it.
    private func syncMuteIntoStateMachine(_ muted: Bool) {
        guard stateMachine.isMuted != muted else { return }
        _ = stateMachine.send(.toggleMute)
    }

    private func handleOrbTap() {
        // Tapping never starts voice. While the assistant is responding it interrupts playback only;
        // that never changes the mute choice or starts the microphone.
        switch stateMachine.state {
        case .speaking, .thinking, .processing:
            _ = stateMachine.send(.tapInterrupt)
            voiceService.interruptPlayback()
        default:
            break
        }
    }

    private func handleStartError(_ error: Error) {
        stateMachine.reset()
        if error is CancellationError { return }
        errorMessage = error.localizedDescription
        showMicrophoneSettings = false
        if let voiceError = error as? VoiceError {
            switch voiceError {
            case .quotaExceeded:
                showUpgradeSheet = true
            case .microphonePermissionDenied:
                showMicrophoneSettings = true
            default:
                break
            }
        }
        showError = true
    }

    /// Plain-language reason the last session stopped, with an explicit way back in.
    private var stopNotice: String? {
        if case .error(let message) = voiceService.connectionState { return message }
        return voiceService.lastStopReason?.statusMessage
    }

    private var shouldShowUpgradeButton: Bool {
        errorMessage?.lowercased().contains("quota") == true ||
        errorMessage?.lowercased().contains("premium") == true
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
}

// MARK: - Voice Mode Paywall View

/// Paywall view shown to non-premium users when they try to access voice mode
struct VoiceModePaywallView: View {
    let onUpgrade: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dark gradient background matching voice mode
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.12),
                    Color(red: 0.08, green: 0.08, blue: 0.18),
                    Color(red: 0.05, green: 0.05, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Voice icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)

                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: .blue.opacity(0.3), radius: 30, x: 0, y: 10)

                // Title and description
                VStack(spacing: 16) {
                    Text("Voice Mode is Premium")
                        .font(.title.bold())
                        .foregroundStyle(.white)

                    Text("Upgrade to have natural voice conversations with your AI companion. Talk hands-free, get real-time responses, and experience a more personal connection.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // Premium features list
                VStack(alignment: .leading, spacing: 12) {
                    PremiumFeatureRow(icon: "mic.fill", text: "Natural voice conversations")
                    PremiumFeatureRow(icon: "captions.bubble.fill", text: "Live captions & transcripts")
                    PremiumFeatureRow(icon: "infinity", text: "Unlimited monthly minutes · sessions up to two minutes")
                }
                .padding(.horizontal, 40)

                Spacer()

                // Action buttons
                VStack(spacing: 16) {
                    Button(action: onUpgrade) {
                        HStack {
                            Image(systemName: "star.fill")
                            Text("Upgrade to Premium")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                    }

                    Button(action: onDismiss) {
                        Text("Maybe Later")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// A single row in the premium features list
private struct PremiumFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.blue)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

// MARK: - Preview

#Preview("Voice Mode") {
    VoiceModeView(
        supabase: SupabaseClient(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseKey: "mock-key"
        )
    )
    .environmentObject(DependencyContainer.shared)
    .environmentObject(AppState())
}

#Preview("Voice Mode Paywall") {
    VoiceModePaywallView(
        onUpgrade: {},
        onDismiss: {}
    )
}
