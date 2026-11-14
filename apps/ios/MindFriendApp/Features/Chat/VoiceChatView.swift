import SwiftUI
import UIKit
import Supabase

// Compatibility model for the unreleased legacy draft format. This entry point
// records the typed journal; account removal also erases retained legacy draft bytes.
struct VoiceTranscriptDraft: Codable, Equatable {
    let ownerId: UUID
    let conversationId: UUID
    var title: String?
    var messages: [VoiceTranscriptMessage]
}

/// Voice entry for a support session. Nothing here connects, prepares a session, or touches the
/// microphone until the person taps "Start voice". Without support-session access the view shows a
/// truthful unavailable state and offers text instead; there is no legacy fallback.
struct VoiceChatView: View {
    @StateObject private var voiceService: GrokVoiceService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var appState: AppState

    @State private var stateMachine = VoiceStateMachine()
    @State private var showSettings = false
    @State private var showUpgradeSheet = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showMicrophoneSettings = false
    @State private var startTask: Task<Void, Never>?
    @State private var isStartingVoice = false
    /// Owns the End / text-switch decision, bound to an exit generation (see `VoiceLeaveController`).
    @StateObject private var leaveController = VoiceLeaveController()

    // Coordinator maps service events to the orb state machine
    @StateObject private var voiceCoordinator: VoiceCoordinator

    private let supportAccess: (any VoiceSupportAccess)?
    private let onUseText: (() -> Void)?

    /// - Parameters:
    ///   - conversationId: Retained for source compatibility. The conversation comes from the
    ///     support-session binding, never from this value.
    ///   - supportAccess: Caller-provided access to the selected support session. When `nil` voice is
    ///     unavailable and the microphone is never started.
    init(supabase: SupabaseClient, conversationId: String? = nil, supportAccess: (any VoiceSupportAccess)? = nil,
         onUseText: (() -> Void)? = nil) {
        _voiceService = StateObject(wrappedValue: GrokVoiceService(supabase: supabase))
        _voiceCoordinator = StateObject(wrappedValue: VoiceCoordinator())
        self.supportAccess = supportAccess
        self.onUseText = onUseText
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

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundGradient

                VStack(spacing: 0) {
                    topBar

                    switch mode {
                    case .unavailable:
                        ScrollView {
                            VoiceUnavailablePanel(onUseText: { leave(reason: .switchedToText) })
                                .padding(.top, SupportTheme.Spacing.xl)
                                .padding(.bottom, SupportTheme.Spacing.xl)
                        }
                    case .ready:
                        ScrollView {
                            VStack(spacing: SupportTheme.Spacing.l) {
                                saveBanner
                                VoiceStartPanel(
                                    preview: supportAccess?.preview() ?? VoiceSupportPreview(scope: .conversationOnly),
                                    notice: stopNotice,
                                    isStarting: false,
                                    onStart: startVoice,
                                    onUseText: { leave(reason: .switchedToText) }
                                )
                            }
                            .padding(.top, SupportTheme.Spacing.xl)
                            .padding(.bottom, SupportTheme.Spacing.xl)
                        }
                    case .starting:
                        startingContent
                    case .active:
                        activeContent(size: geometry.size, safeBottom: geometry.safeAreaInsets.bottom)
                    }
                }
            }
        }
        // Only the background (backgroundGradient) extends under the status bar and Dynamic Island;
        // the controls stay inside the safe area.
        .supportScreen()
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
                if exit == .text { onUseText?() }
                dismiss()
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
        SupportTheme.canvas.ignoresSafeArea()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        (dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: SupportTheme.Spacing.xs))
            : AnyLayout(HStackLayout(spacing: SupportTheme.Spacing.xs))) {
            Button {
                leave(reason: .userEnded)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
                    .voiceBarControl()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close voice")

            Spacer()

            if mode == .active || mode == .ready {
                Button {
                    _ = stateMachine.send(.toggleCaptions)
                } label: {
                    Image(systemName: stateMachine.captionsEnabled ? "captions.bubble.fill" : "captions.bubble")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(stateMachine.captionsEnabled ? SupportTheme.textPrimary : SupportTheme.textPrimary.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .voiceBarControl()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(stateMachine.captionsEnabled ? "Hide captions" : "Show captions")

                Button {
                    showSettings = true
                } label: {
                    HStack(spacing: SupportTheme.Spacing.xs) {
                        Circle()
                            .fill(voiceColor(voiceService.currentVoice))
                            .frame(width: 10, height: 10)
                        Text(voiceService.currentVoice.displayName)
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, SupportTheme.Spacing.m)
                    .frame(minHeight: SupportTheme.minimumTarget)
                    .voiceBarControl()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voice: \(voiceService.currentVoice.displayName). Tap to change.")
            }
        }
        .padding(.horizontal, SupportTheme.Spacing.l)
        .padding(.top, SupportTheme.Spacing.s)
    }

    // MARK: - Modes

    private var startingContent: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(SupportTheme.textPrimary)
            Text("Starting voice…")
                .font(.title3.weight(.medium))
                .foregroundStyle(SupportTheme.textPrimary)
            Text("The microphone turns on once the connection is ready.")
                .font(.footnote)
                .foregroundStyle(SupportTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SupportTheme.Spacing.xl)
            Button("Cancel") {
                startTask?.cancel()
                leave(reason: .userEnded, dismissWhenDone: false)
            }
            .buttonStyle(.supportSecondary)
            .tint(SupportTheme.textPrimary)
            .controlSize(.large)
            Spacer()
        }
        .accessibilityElement(children: .contain)
    }

    private func activeContent(size: CGSize, safeBottom: CGFloat) -> some View {
        VoiceActiveLayout(safeBottom: safeBottom) {
            VStack(spacing: SupportTheme.Spacing.l) {
                if stateMachine.captionsEnabled { captionsView.padding(.horizontal, SupportTheme.Spacing.l) }
                orbSection(size: min(size.width * 0.56, 300))
                statusView.padding(.horizontal, SupportTheme.Spacing.l)
            }
        } controls: {
            bottomControls
        }
    }

    @ViewBuilder
    private var saveBanner: some View {
        VoiceTranscriptSaveBanner(
            unsaved: voiceService.unsavedTranscriptCount,
            rejected: voiceService.rejectedTranscriptCount,
            canLeave: leaveController.isHolding,
            onRetry: retrySaving,
            onLeaveWithoutSaving: discardAndLeave
        )
    }

    // MARK: - Captions

    private var captionsView: some View {
        VoiceCaptionView(caption: voiceService.caption, reduceMotion: reduceMotion)
    }

    // MARK: - Orb

    private func orbSection(size: CGFloat) -> some View {
        let config = OrbView.Configuration(
            state: stateMachine.state,
            micLevel: voiceService.micLevel,
            playbackLevel: voiceService.playbackLevel,
            reducedMotion: reduceMotion
        )

        return OrbContainerView(config: config, size: size) {
            handleOrbTap()
        }
        .shadow(color: orbShadowColor.opacity(0.4), radius: 40, x: 0, y: 20)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4), value: stateMachine.state)
    }

    private var orbShadowColor: Color { OrbView.color(for: stateMachine.state.orbColor) }

    // MARK: - Status

    private var statusView: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            // Explicit capture indicator: text and icon, never only motion or color.
            VoiceCaptureIndicator(isListening: voiceService.isListening, isMuted: voiceService.isMuted)

            HStack(spacing: SupportTheme.Spacing.xs) {
                Circle()
                    .fill(connectionStatusColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                Text(connectionStatusText)
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textPrimary)
            }

            Text(stateMachine.state.statusText)
                .font(.title3.weight(.medium))
                .foregroundStyle(SupportTheme.textPrimary)

            Text("Up to two minutes per session")
                .font(.caption)
                .foregroundStyle(SupportTheme.textPrimary)
            Text(voiceService.isPremium ? "Unlimited monthly voice minutes" :
                String(format: "%.1f of 3 free monthly voice minutes remaining", voiceService.minutesRemaining))
                .font(.caption)
                .foregroundStyle(SupportTheme.textPrimary)
        }
        .padding(.horizontal, SupportTheme.Spacing.l)
    }

    private var connectionStatusColor: Color {
        switch voiceService.connectionState {
        case .connected:
            return SupportTheme.Status.positive
        case .connecting, .reconnecting:
            return SupportTheme.Status.caution
        case .disconnected:
            return SupportTheme.textSecondary
        case .error:
            return SupportTheme.Status.caution
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

    // MARK: - Controls

    private var bottomControls: some View {
        VoiceCallControls(isMuted: voiceService.isMuted, onMute: toggleMute,
            onEnd: { leave(reason: .userEnded) }, onText: { leave(reason: .switchedToText) })
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
        case .ara: return SupportTheme.Area.copingKits.palette.ink
        case .rex: return SupportTheme.Area.voice.palette.ink
        case .sal: return SupportTheme.Area.journal.palette.ink
        case .eve: return SupportTheme.Area.quests.palette.ink
        case .leo: return SupportTheme.Area.insights.palette.ink
        }
    }
}

// MARK: - Leaving a voice screen (shared by both voice views)

/// Captions may grow without displacing the always-available microphone, End and text controls.
struct VoiceActiveLayout<Content: View, Controls: View>: View {
    let safeBottom: CGFloat
    let content: Content
    let controls: Controls

    init(safeBottom: CGFloat, @ViewBuilder content: () -> Content, @ViewBuilder controls: () -> Controls) {
        self.safeBottom = safeBottom
        self.content = content()
        self.controls = controls()
    }

    var body: some View {
        ScrollView {
            content.frame(maxWidth: .infinity).padding(.vertical, SupportTheme.Spacing.l)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            controls.padding(.horizontal, SupportTheme.Spacing.l).padding(.top, SupportTheme.Spacing.s)
                .padding(.bottom, safeBottom > 0 ? max(16, safeBottom) : 20)
        }
    }
}

struct VoiceCallControls: View {
    let isMuted: Bool
    let onMute: () -> Void
    let onEnd: () -> Void
    let onText: () -> Void

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.l) {
            Button(action: onMute) {
                Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(isMuted ? .red : SupportTheme.textPrimary)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(isMuted ? Color.red.opacity(0.2) : SupportTheme.textPrimary.opacity(0.15)))
            }.accessibilityLabel(isMuted ? "Unmute microphone" : "Mute microphone")
            Button(action: onEnd) {
                Image(systemName: "phone.down.fill").font(.system(size: 28, weight: .medium))
                    .foregroundStyle(SupportTheme.textPrimary).frame(width: 72, height: 72)
                    .background(Circle().fill(Color.red))
                    .shadow(color: .red.opacity(0.4), radius: 15, x: 0, y: 8)
            }.accessibilityLabel("End voice session")
            Button(action: onText) {
                Image(systemName: "keyboard").font(.system(size: 24, weight: .medium))
                    .foregroundStyle(SupportTheme.textPrimary).frame(width: 60, height: 60)
                    .background(Circle().fill(SupportTheme.field))
            }
            .accessibilityLabel("Switch to text")
            .accessibilityHint("Stops the microphone and returns to this conversation.")
        }
    }
}

/// Decides what happens after an explicit End or text switch, for both voice views.
///
/// The local stop is synchronous and the wait for remote work is bounded, so this decision arrives
/// while the person may already have pressed Start voice again (the service intentionally allows
/// that). Every decision is therefore bound to an exit generation taken BEFORE the await and checked
/// AFTER it. A new Start, an owner or account change, or a newer leave invalidates it; a decision that
/// is stale neither dismisses the screen nor raises a hold for a session that has been replaced.
/// Rejected finals still count exactly like pending ones when the decision is current.
@MainActor
final class VoiceLeaveController: ObservableObject {
    enum Exit: Equatable {
        case close
        case text
    }

    /// True while the screen is holding for the transcript after an explicit leave.
    @Published private(set) var isHolding = false
    private(set) var pendingExit: Exit?
    private var gate = VoiceExitGate()

    /// Performs the actual navigation. Set by the owning view.
    var exitScreen: ((Exit) -> Void)?

    /// A new explicit Start invalidates every older, unfinished leave decision and clears any hold.
    func startBegan() {
        gate.invalidate()
        isHolding = false
        pendingExit = nil
    }

    /// A stop whose reason means the owner, account or context changed retires every pending decision.
    /// Deliberate stops (End, text switch) are the leave itself and must not cancel it.
    func noteStop(_ reason: VoiceStopReason?) {
        guard let reason, reason.invalidatesPendingLeave else { return }
        invalidate()
    }

    /// Retires pending decisions whenever the originating authority reports a change, including after
    /// End has removed the session's own validity monitoring. Runs until the stream ends or the
    /// owning task is cancelled.
    func retireOnInvalidation(from stream: AsyncStream<Void>) async {
        for await _ in stream { invalidate() }
    }

    /// Owner / account / context change: nothing pending may navigate afterwards.
    func invalidate() {
        gate.invalidate()
        isHolding = false
        pendingExit = nil
    }

    func leave(reason: VoiceStopReason, dismissWhenDone: Bool = true, service: any VoiceServiceProtocol) async {
        // A new leave replaces whatever an older one left behind BEFORE anything suspends. Otherwise
        // the older hold (and its destination) would still be live while this End waits, and a count
        // change in that window would release it toward the OLD exit and invalidate this newer choice.
        // The unsaved / rejected counts stay visible: they come from the service, not from this flag.
        isHolding = false
        pendingExit = nil
        let ticket = gate.begin()
        let exit: Exit = reason == .switchedToText ? .text : .close
        let outcome = await service.end(reason: reason)

        // Decided by the generation, after every await.
        guard gate.isCurrent(ticket) else { return }
        guard dismissWhenDone else { return }
        // Defence in depth: a session that is live again is never closed by an older End, whichever
        // path started it.
        guard !Self.hasLiveSession(service) else { return }

        switch VoiceLeaveGate.decide(unsaved: outcome.unsavedTranscripts, rejected: outcome.rejectedTranscripts) {
        case .leave:
            complete(exit)
        case .holdForTranscript:
            pendingExit = exit
            isHolding = true
        }
    }

    /// Releases a hold once nothing is pending, in flight or rejected any more.
    func autoLeaveIfResolved(service: any VoiceServiceProtocol) {
        guard isHolding,
              VoiceLeaveGate.shouldAutoLeave(
                leaveRequested: true,
                unsaved: service.unsavedTranscriptCount,
                rejected: service.rejectedTranscriptCount),
              !Self.hasLiveSession(service) else { return }
        complete(pendingExit ?? .close)
    }

    /// Explicit retry (also retries rejected finals), then leaves if everything is resolved.
    func retry(service: any VoiceServiceProtocol) async {
        let ticket = gate.generation
        await service.retryUnsavedTranscript(includeRejected: true)
        guard gate.isCurrent(ticket) else { return }
        autoLeaveIfResolved(service: service)
    }

    /// The explicit, separate decision to give up finals that were not acknowledged.
    func discardAndLeave(service: any VoiceServiceProtocol) {
        service.discardUnresolvedTranscript()
        complete(pendingExit ?? .close)
    }

    private func complete(_ exit: Exit) {
        pendingExit = nil
        isHolding = false
        gate.invalidate()
        exitScreen?(exit)
    }

    private static func hasLiveSession(_ service: any VoiceServiceProtocol) -> Bool {
        service.connectionState == .connecting || service.connectionState.isConnected
    }
}

// MARK: - Shared voice UI (used by VoiceChatView and VoiceModeView)

enum VoiceAccessibility {
    /// Announces a state change to VoiceOver without moving focus.
    static func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}

/// Selected session and context scope with an explicit Start voice. Shown before anything connects.
struct VoiceStartPanel: View {
    @ScaledMetric(relativeTo: .largeTitle) private var orbSize: CGFloat = 160
    let preview: VoiceSupportPreview
    let notice: String?
    let isStarting: Bool
    let onStart: () -> Void
    let onUseText: () -> Void

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                // The orb at rest in its paused color: decoration only, the microphone is off.
                OrbContainerView(
                    config: OrbView.Configuration(state: .idleDisconnected, micLevel: 0, playbackLevel: 0,
                                                  reducedMotion: false, showsIcon: false),
                    size: min(orbSize, 280)
                )
                .accessibilityHidden(true)
                Text("Talk by voice")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(preview.displayTitle)
                    .font(.headline)
                Text(preview.scopeSummary)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                if let note = preview.attachmentNote {
                    Text(note)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(SupportTheme.textPrimary)
            .accessibilityElement(children: .combine)

            if let notice {
                Text(notice)
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(SupportTheme.Spacing.s)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: SupportTheme.controlRadius).fill(SupportTheme.surface))
            }

            Text("The microphone stays off until you tap Start voice.")
                .font(.footnote)
                .foregroundStyle(SupportTheme.textPrimary)
                .multilineTextAlignment(.center)

            Button(action: onStart) {
                Text("Start voice")
                    .frame(maxWidth: .infinity, minHeight: SupportTheme.primaryButtonHeight)
            }
            .buttonStyle(.supportPrimary)
            .controlSize(.large)
            .disabled(isStarting)

            Button(action: onUseText) {
                Text("Continue by text")
                    .frame(maxWidth: .infinity, minHeight: SupportTheme.minimumTarget)
            }
            .buttonStyle(.supportSecondary)
            .tint(SupportTheme.textPrimary)
            .controlSize(.large)
        }
        .padding(.horizontal, SupportTheme.Spacing.l)
        .frame(maxWidth: SupportTheme.readableWidth)
    }
}

/// The voice screen's top controls: compact field-coloured shapes sized to their content, not the
/// full-width secondary button style.
private extension View {
    func voiceBarControl() -> some View {
        self
            .foregroundStyle(SupportTheme.accent)
            .background(SupportTheme.field, in: Capsule())
            .overlay(Capsule().strokeBorder(SupportTheme.border, lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// Shown when no support-session access was provided. Voice is not started and no fallback is used.
struct VoiceUnavailablePanel: View {
    let onUseText: () -> Void

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "mic.slash")
                .font(.system(size: 44))
                .foregroundStyle(SupportTheme.textPrimary)
                .accessibilityHidden(true)
            Text("Voice isn't available right now")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SupportTheme.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("This conversation can't be used for voice at the moment. The microphone is off. You can keep going by text.")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textPrimary)
                .multilineTextAlignment(.center)
            Button(action: onUseText) {
                Text("Continue by text")
                    .frame(maxWidth: .infinity, minHeight: SupportTheme.primaryButtonHeight)
            }
            .buttonStyle(.supportPrimary)
            .controlSize(.large)
        }
        .padding(.horizontal, SupportTheme.Spacing.l)
        .frame(maxWidth: SupportTheme.readableWidth)
    }
}

/// Text-and-icon capture state. Not conveyed by color or animation alone.
struct VoiceCaptureIndicator: View {
    let isListening: Bool
    let isMuted: Bool

    private var text: String {
        if isListening { return "Microphone on" }
        return isMuted ? "Microphone off · muted" : "Microphone off"
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: isListening ? "mic.fill" : "mic.slash.fill")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isListening ? SupportTheme.accent : SupportTheme.textPrimary.opacity(0.9))
        .padding(.horizontal, SupportTheme.Spacing.s)
        .padding(.vertical, SupportTheme.Spacing.xs)
        .background(Capsule().fill(SupportTheme.surface))
        .accessibilityElement(children: .combine)
    }
}

/// The live / complete / interrupted caption. The phase is shown as visible text with an icon and
/// exposed to VoiceOver, and changes only when the typed final (or abandoned) event arrives.
struct VoiceCaptionView: View {
    let caption: VoiceCaption?
    let reduceMotion: Bool

    private func symbol(_ phase: VoiceCaption.Phase) -> String {
        switch phase {
        case .live: return "waveform"
        case .complete: return "checkmark.circle"
        case .interrupted: return "exclamationmark.circle"
        }
    }

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            if let caption, !caption.text.isEmpty {
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Label {
                        Text("\(caption.speakerLabel) · \(caption.phaseLabel)")
                    } icon: {
                        Image(systemName: symbol(caption.phase))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SupportTheme.textPrimary)

                    Text(caption.text)
                        .font(.body)
                        .foregroundStyle(SupportTheme.textPrimary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, SupportTheme.Spacing.l)
                .padding(.vertical, SupportTheme.Spacing.m)
                .background(
                    RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                        .fill(SupportTheme.surface)
                )
                .transition(reduceMotion ? .opacity.animation(.easeInOut(duration: 0.2)) : .opacity.combined(with: .scale(scale: 0.95)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(caption.accessibilityLabel)
                .accessibilityValue(caption.text)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3), value: caption)
        .frame(minHeight: 60)
    }
}

/// Reports finals that are not confirmed saved. "Saved" is never implied here. Pending, in-flight and
/// rejected finals all keep the screen: leaving without saving is a separate, explicit choice.
struct VoiceTranscriptSaveBanner: View {
    let unsaved: Int
    let rejected: Int
    /// True once the person asked to leave (End / text switch) and the screen is holding.
    let canLeave: Bool
    let onRetry: () -> Void
    let onLeaveWithoutSaving: () -> Void

    var body: some View {
        if unsaved > 0 || rejected > 0 {
            VStack(spacing: SupportTheme.Spacing.s) {
                if unsaved > 0 {
                    Text(unsaved == 1
                         ? "1 message from this voice conversation isn't saved yet."
                         : "\(unsaved) messages from this voice conversation aren't saved yet.")
                }
                if rejected > 0 {
                    Text(rejected == 1
                         ? "1 message couldn't be saved."
                         : "\(rejected) messages couldn't be saved.")
                }
                HStack(spacing: SupportTheme.Spacing.s) {
                    Button("Retry saving", action: onRetry)
                        .buttonStyle(.supportPrimary)
                    if canLeave {
                        Button("Leave without saving", role: .destructive, action: onLeaveWithoutSaving)
                            .buttonStyle(.supportSecondary)
                    }
                }
                .controlSize(.regular)
            }
            .font(.subheadline)
            .foregroundStyle(SupportTheme.textPrimary)
            .multilineTextAlignment(.center)
            .padding(SupportTheme.Spacing.m)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: SupportTheme.controlRadius).fill(SupportTheme.accent.opacity(0.28)))
            .padding(.horizontal, SupportTheme.Spacing.l)
            .accessibilityElement(children: .contain)
        }
    }
}
