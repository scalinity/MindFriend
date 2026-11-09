import XCTest
import AVFoundation
import Supabase
@testable import MindFriendApp

private func assertVoiceThrows<T>(_ expression: @autoclosure () throws -> T, _ message: String = "",
                                  file: StaticString = #filePath, line: UInt = #line,
                                  _ handler: (Error) -> Void = { _ in }) {
    do { _ = try expression(); XCTFail(message.isEmpty ? "Expected an error" : message, file: file, line: line) }
    catch { handler(error) }
}

// Synthetic, deterministic voice lifecycle / transcript tests.
// No microphone, no audio session, no socket, no network, no provider, no real data: every
// boundary (hardware, transport, backend, support-session access, permission prompt) is a fake.

// MARK: - Fakes

@MainActor
final class VoiceTestLog {
    private(set) var entries: [String] = []
    func add(_ entry: String) { entries.append(entry) }
    func index(of entry: String) -> Int? { entries.firstIndex(of: entry) }
}

@MainActor
final class Counter {
    var value = 0
    func bump() { value += 1 }
}

@MainActor
final class FakeCaptureHardware: VoiceCaptureHardware {
    var calls: [String] = []
    var activateError: Error?
    var startEngineErrors: [Error] = []
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    /// The most recently installed tap callback. Tests retain older ones to replay them late.
    var handler: (@Sendable (AVAudioPCMBuffer) -> Void)?

    func activateSession() throws {
        calls.append("activate")
        if let activateError { throw activateError }
    }

    func nativeInputFormat() throws -> AVAudioFormat {
        calls.append("format")
        return format
    }

    func installTap(format: AVAudioFormat, handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        calls.append("installTap")
        self.handler = handler
    }

    func removeTap() { calls.append("removeTap") }

    func startEngine() throws {
        calls.append("startEngine")
        if !startEngineErrors.isEmpty { throw startEngineErrors.removeFirst() }
    }

    func stopEngine() { calls.append("stopEngine") }
    func deactivateSession() { calls.append("deactivate") }

    /// A synthetic, non-silent 10 ms buffer in the fake native format.
    func makeBuffer(frames: AVAudioFrameCount = 480) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = 0.25 * sinf(Float(i) / 8) }
        return buffer
    }
}

@MainActor
final class FakeVoiceCapture: VoiceCaptureControlling {
    var onAudioData: ((Data, VoiceCaptureGeneration) -> Void)?
    var onMicLevelUpdate: ((Float, VoiceCaptureGeneration) -> Void)?
    var startCount = 0
    var stopCount = 0
    var forceStopCount = 0
    var startError: Error?
    /// Generation of the most recent successful start (0 before any).
    private(set) var lastGeneration: VoiceCaptureGeneration = 0
    let log: VoiceTestLog

    init(log: VoiceTestLog) { self.log = log }

    func startCapture() throws -> VoiceCaptureGeneration {
        if let startError {
            log.add("capture.start.failed")
            throw startError
        }
        startCount += 1
        lastGeneration += 1
        log.add("capture.start")
        return lastGeneration
    }

    func stopCapture() {
        stopCount += 1
        log.add("capture.stop")
    }

    func forceStop() {
        forceStopCount += 1
        log.add("capture.forceStop")
    }

    /// Delivers a frame as the capture of `generation` (defaults to the newest).
    func emit(_ bytes: [UInt8] = [1, 2], generation: VoiceCaptureGeneration? = nil) {
        onAudioData?(Data(bytes), generation ?? lastGeneration)
    }
}

@MainActor
final class FakeVoicePlayback: VoicePlaybackControlling {
    var onPlaybackStart: (() -> Void)?
    var onPlaybackEnd: (() -> Void)?
    var onPlaybackLevelUpdate: ((Float) -> Void)?
    var lastPlaybackEndTime: Date? { nil }
    var echoCooldownSeconds: TimeInterval { 0.6 }
    var stopCount = 0
    let log: VoiceTestLog

    init(log: VoiceTestLog) { self.log = log }

    func queueAudioChunk(_ audioData: Data) {}

    func stop() {
        stopCount += 1
        log.add("playback.stop")
    }
}

@MainActor
final class FakeVoiceTransport: VoiceRelayTransport {
    var onMessage: ((URLSessionWebSocketTask.Message) -> Void)?
    var onConnectionLost: ((Bool) -> Void)?
    var sent: [[String: Any]] = []
    var connectCalls: [(sessionId: String, token: String)] = []
    var disconnectCount = 0
    var deliversSessionEvents = true
    let log: VoiceTestLog

    init(log: VoiceTestLog) { self.log = log }

    func connect(sessionId: String, userToken: String) async throws {
        connectCalls.append((sessionId, userToken))
        log.add("transport.connect")
        if deliversSessionEvents { deliver(["type": "session.created"]) }
    }

    func disconnect() {
        disconnectCount += 1
        log.add("transport.disconnect")
    }

    func send(_ message: [String: Any]) {
        sent.append(message)
        let type = message["type"] as? String ?? ""
        log.add("transport.send:\(type)")
        if type == "session.update", deliversSessionEvents { deliver(["type": "session.updated"]) }
    }

    func deliver(_ event: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: event)
        onMessage?(.string(String(data: data, encoding: .utf8)!))
    }

    func sentTypes() -> [String] { sent.compactMap { $0["type"] as? String } }
}

@MainActor
final class FakeVoiceBackend: VoiceRelayBackend {
    var auth: VoiceAuthSnapshot
    var admission: VoiceAdmission
    var admitError: Error?
    var onAdmit: (() -> Void)?
    var admitCalls: [(body: VoiceAdmissionRequestBody, token: String)] = []
    var endCalls: [(request: VoiceSessionEndRequest, token: String)] = []
    /// Suspends `authSnapshot()` (used to model a stalled auth refresh).
    var authHook: (() async -> Void)?
    /// Suspends session-end accounting after it has been recorded.
    var endSessionHook: ((VoiceSessionEndRequest) async -> Void)?
    /// What the fake server answers for session-end accounting.
    var endSessionResult: VoiceAccountingResult = .confirmed
    let log: VoiceTestLog

    init(auth: VoiceAuthSnapshot, admission: VoiceAdmission, log: VoiceTestLog) {
        self.auth = auth
        self.admission = admission
        self.log = log
    }

    func authSnapshot() async throws -> VoiceAuthSnapshot {
        if let authHook { await authHook() }
        return auth
    }

    func admit(_ body: VoiceAdmissionRequestBody, authorization token: String) async throws -> VoiceAdmission {
        log.add("backend.admit")
        admitCalls.append((body, token))
        onAdmit?()
        if let admitError { throw admitError }
        return admission
    }

    func endSession(_ request: VoiceSessionEndRequest, authorization token: String) async -> VoiceAccountingResult {
        log.add("backend.endSession")
        endCalls.append((request, token))
        if let endSessionHook { await endSessionHook(request) }
        return endSessionResult
    }

    func saveVoicePreference(_ voice: GrokVoice, expectedOwner: UUID?) async throws {}
}

@MainActor
final class FakeSupportAccess: VoiceSupportAccess {
    var binding: VoiceSupportBinding
    var isBindingCurrent = true
    var prepareCalls = 0
    var prepareError: Error?
    var appendAttempts = 0
    var failuresRemaining = 0
    var failureToThrow: Error = VoiceSupportAppendError.retryable
    var appended: [VoiceTranscriptEvent] = []
    var appendHook: ((VoiceTranscriptEvent) async throws -> Void)?
    var reconcileCalls = 0
    var explicitRetryEvents: [UUID] = []
    /// Suspends `reconcile` after it has been recorded.
    var reconcileHook: (() async -> Void)?

    init(binding: VoiceSupportBinding) { self.binding = binding }

    func preview() -> VoiceSupportPreview {
        VoiceSupportPreview(title: "Synthetic session", scope: binding.scope)
    }

    func prepare() async throws -> VoiceSupportBinding {
        prepareCalls += 1
        if let prepareError { throw prepareError }
        return binding
    }

    func isCurrent(_ binding: VoiceSupportBinding) -> Bool {
        isBindingCurrent && binding == self.binding
    }

    func appendFinalEvent(_ binding: VoiceSupportBinding, _ event: VoiceTranscriptEvent) async throws {
        appendAttempts += 1
        if let appendHook {
            try await appendHook(event)
            return
        }
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw failureToThrow
        }
        appended.append(event)
    }

    func retryFinalEvent(_ binding: VoiceSupportBinding, _ event: VoiceTranscriptEvent) async throws {
        explicitRetryEvents.append(event.localUUID)
        try await appendFinalEvent(binding, event)
    }

    func reconcile(_ binding: VoiceSupportBinding) async {
        reconcileCalls += 1
        if let reconcileHook { await reconcileHook() }
    }
}

// MARK: - Helpers

private func makeBinding(owner: UUID = UUID(), revision: Int64? = 4) -> VoiceSupportBinding {
    VoiceSupportBinding(
        ownerUUID: owner,
        accountEpoch: 7,
        supportSessionUUID: UUID(),
        conversationUUID: UUID(),
        scope: .personalized,
        privacyRevision: revision
    )
}

private func tokenResponse(sessionId: UUID = UUID(), transport: String = "relay", duration: Int = 120, premium: Bool = true) -> VoiceTokenResponse {
    let json = """
    {"token":"unused","expires_at":"2026-01-01T00:00:00Z","minutes_remaining":3,"voice":"ara",
     "is_premium":\(premium),"available_voices":["ara"],"session_id":"\(sessionId.uuidString)",
     "transport":"\(transport)","max_duration_seconds":\(duration)}
    """
    return try! JSONDecoder().decode(VoiceTokenResponse.self, from: Data(json.utf8))
}

/// A well-formed nested voice_context for `binding`, with an optional mutation to break one field.
private func claimObject(for binding: VoiceSupportBinding, _ mutate: (inout [String: Any]) -> Void = { _ in }) -> [String: Any] {
    var object: [String: Any] = [
        "version": 1,
        "support_session_id": binding.supportSessionUUID.uuidString.lowercased(),
        "conversation_id": binding.conversationUUID.uuidString.lowercased(),
        "context_scope": binding.scope.rawValue,
        "privacy_revision": binding.privacyRevision ?? 4,
        "context_receipt_id": UUID().uuidString.lowercased(),
        "packet_sha256": String(repeating: "ab", count: 32),
        "packet_bytes": 1_234,
        "provider": ["vendor": "openai", "model": "gpt-realtime-2.1-mini", "route_version": "1"],
        "privacy_lease_ms": 5_000,
    ]
    mutate(&object)
    return object
}

private func validClaim(for binding: VoiceSupportBinding) -> VoiceContextClaim {
    guard case .success(let claim) = VoiceContextClaim.parse(object: claimObject(for: binding)) else {
        fatalError("fixture claim must parse")
    }
    return claim
}

/// An admission whose nested voice_context is built from `binding` and then mutated (nil removes it).
private func admission(
    for binding: VoiceSupportBinding, sessionID: UUID, premium: Bool = true,
    _ mutate: (inout [String: Any]) -> Void = { _ in }
) -> VoiceAdmission {
    VoiceAdmission(
        token: tokenResponse(sessionId: sessionID, premium: premium),
        voiceContext: VoiceContextClaim.parse(object: claimObject(for: binding, mutate))
    )
}

private func deterministicAssembler(binding: VoiceSupportBinding) -> VoiceTranscriptAssembler {
    var counter = 0
    return VoiceTranscriptAssembler(
        binding: binding,
        now: { Date(timeIntervalSince1970: 1_000) },
        makeID: {
            counter += 1
            return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", counter))!
        }
    )
}

private func ingest(_ assembler: inout VoiceTranscriptAssembler, _ type: String, _ fields: [String: Any] = [:]) -> [VoiceTranscriptEvent] {
    var json = fields
    json["type"] = type
    return assembler.ingest(type: type, json: json)
}

private func finalEvent(_ binding: VoiceSupportBinding, order: Int64, text: String = "hello", role: VoiceTranscriptRole = .user) -> VoiceTranscriptEvent {
    VoiceTranscriptEvent(
        localUUID: UUID(), binding: binding, role: role, providerItemID: "item-\(order)", providerEventID: nil,
        providerResponseID: nil, order: order, revision: 1, occurredAt: Date(timeIntervalSince1970: 1_000),
        finality: .final, abandonReason: nil, text: text
    )
}

// MARK: - Transcript identity, finality and order

@MainActor
final class VoiceTranscriptAssemblerTests: XCTestCase {

    func testRepeatedIdenticalUtterancesStayDistinctAndOrdered() {
        var assembler = deterministicAssembler(binding: makeBinding())
        var finals: [VoiceTranscriptEvent] = []
        func feed(_ type: String, _ fields: [String: Any] = [:]) {
            finals += ingest(&assembler, type, fields).filter { $0.finality == .final }
        }

        feed("input_audio_buffer.speech_started", ["item_id": "u1"])
        feed("input_audio_buffer.committed", ["item_id": "u1"])
        feed("conversation.item.input_audio_transcription.completed", ["item_id": "u1", "transcript": "Yes", "event_id": "e1"])
        feed("response.created", ["response": ["id": "r1"]])
        feed("response.output_audio_transcript.delta", ["response_id": "r1", "item_id": "a1", "delta": "Okay."])
        feed("response.output_audio_transcript.done", ["response_id": "r1", "item_id": "a1", "transcript": "Okay."])
        feed("response.done", ["response": ["id": "r1", "status": "completed"]])
        feed("input_audio_buffer.speech_started", ["item_id": "u2"])
        feed("input_audio_buffer.committed", ["item_id": "u2"])
        feed("conversation.item.input_audio_transcription.completed", ["item_id": "u2", "transcript": "Yes", "event_id": "e2"])

        XCTAssertEqual(finals.map(\.role), [.user, .assistant, .user])
        XCTAssertEqual(finals.map(\.text), ["Yes", "Okay.", "Yes"])
        XCTAssertEqual(Set(finals.map(\.localUUID)).count, 3, "identical text must not collapse identities")
        XCTAssertEqual(finals.map(\.order), [1, 2, 3])
        XCTAssertEqual(finals.map(\.providerItemID), ["u1", "a1", "u2"])
        XCTAssertEqual(finals.map(\.finality), [.final, .final, .final])
    }

    func testPartialsShareStableIdentityWithTheirFinal() {
        var assembler = deterministicAssembler(binding: makeBinding())
        var events: [VoiceTranscriptEvent] = []
        events += ingest(&assembler, "input_audio_buffer.speech_started", ["item_id": "u1"])
        events += ingest(&assembler, "conversation.item.input_audio_transcription.updated", ["item_id": "u1", "transcript": "he"])
        events += ingest(&assembler, "conversation.item.input_audio_transcription.updated", ["item_id": "u1", "transcript": "hello"])
        events += ingest(&assembler, "conversation.item.input_audio_transcription.completed", ["item_id": "u1", "transcript": "Hello there."])

        XCTAssertEqual(events.map(\.finality), [.partial, .partial, .final])
        XCTAssertEqual(Set(events.map(\.localUUID)).count, 1)
        XCTAssertEqual(events.map(\.revision), [1, 2, 3])
        XCTAssertEqual(events.last?.text, "Hello there.")
        XCTAssertEqual(events.map(\.order), [1, 1, 1])
    }

    func testReplayedFinalIsIgnoredByIdentityButSameTextOnDifferentItemIsKept() {
        var assembler = deterministicAssembler(binding: makeBinding())
        var finals: [VoiceTranscriptEvent] = []
        func feed(_ fields: [String: Any]) {
            finals += ingest(&assembler, "conversation.item.input_audio_transcription.completed", fields)
                .filter { $0.finality == .final }
        }
        feed(["item_id": "u1", "transcript": "Same", "event_id": "e1"])
        feed(["item_id": "u1", "transcript": "Same", "event_id": "e1"])   // exact provider replay
        feed(["item_id": "u1", "transcript": "Same", "event_id": "e9"])   // same item, new event id
        feed(["item_id": "u2", "transcript": "Same", "event_id": "e2"])   // legitimately repeated utterance

        XCTAssertEqual(finals.map(\.providerItemID), ["u1", "u2"])
        XCTAssertEqual(finals.map(\.text), ["Same", "Same"])
    }

    func testLateUserTranscriptKeepsConversationOrderBeforeTheAssistantReply() {
        var assembler = deterministicAssembler(binding: makeBinding())
        _ = ingest(&assembler, "input_audio_buffer.speech_started", ["item_id": "u1"])
        _ = ingest(&assembler, "input_audio_buffer.committed", ["item_id": "u1"])
        _ = ingest(&assembler, "response.created", ["response": ["id": "r1"]])
        _ = ingest(&assembler, "response.output_audio_transcript.done", ["response_id": "r1", "item_id": "a1", "transcript": "Hi."])
        let assistant = ingest(&assembler, "response.done", ["response": ["id": "r1", "status": "completed"]])
        let user = ingest(&assembler, "conversation.item.input_audio_transcription.completed", ["item_id": "u1", "transcript": "Hello"])

        // The assistant finished first, the user's transcript arrived later; order follows the conversation.
        XCTAssertEqual(assistant.first?.order, 2)
        XCTAssertEqual(user.first?.order, 1)
        let sorted = (assistant + user).sorted { $0.order < $1.order }
        XCTAssertEqual(sorted.map(\.role), [.user, .assistant])
    }

    func testCancelledIncompleteOrFailedResponsesNeverBecomeFinalText() {
        let cases: [(status: String, reason: VoiceTranscriptAbandonReason)] = [
            ("cancelled", .responseCancelled), ("incomplete", .responseIncomplete), ("failed", .responseFailed),
        ]
        for testCase in cases {
            var assembler = deterministicAssembler(binding: makeBinding())
            _ = ingest(&assembler, "response.created", ["response": ["id": "r1"]])
            _ = ingest(&assembler, "response.output_audio_transcript.delta", ["response_id": "r1", "item_id": "a1", "delta": "Half of an answ"])
            let done = ingest(&assembler, "response.done", ["response": ["id": "r1", "status": testCase.status]])

            XCTAssertEqual(done.count, 1, testCase.status)
            XCTAssertEqual(done.first?.finality, .abandoned, testCase.status)
            XCTAssertEqual(done.first?.abandonReason, testCase.reason, testCase.status)
            XCTAssertEqual(done.first?.text, "", "no partial text may be carried as completed: \(testCase.status)")
        }
    }

    func testCompletionWithoutStatusRequiresProviderFinalText() {
        var withoutFinal = deterministicAssembler(binding: makeBinding())
        _ = ingest(&withoutFinal, "response.created", ["response": ["id": "r1"]])
        _ = ingest(&withoutFinal, "response.output_audio_transcript.delta", ["response_id": "r1", "item_id": "a1", "delta": "Maybe"])
        let abandoned = ingest(&withoutFinal, "response.done", ["response": ["id": "r1"]])
        XCTAssertEqual(abandoned.map(\.finality), [.abandoned])
        XCTAssertEqual(abandoned.first?.abandonReason, .responseIncomplete)

        var withFinal = deterministicAssembler(binding: makeBinding())
        _ = ingest(&withFinal, "response.created", ["response": ["id": "r1"]])
        _ = ingest(&withFinal, "response.output_audio_transcript.delta", ["response_id": "r1", "item_id": "a1", "delta": "May"])
        _ = ingest(&withFinal, "response.output_audio_transcript.done", ["response_id": "r1", "item_id": "a1", "transcript": "Maybe so."])
        let final = ingest(&withFinal, "response.done", ["response": ["id": "r1"]])
        XCTAssertEqual(final.map(\.finality), [.final])
        XCTAssertEqual(final.first?.text, "Maybe so.")
    }

    func testProviderFinalOutputTranscriptWinsOverDeltas() {
        var assembler = deterministicAssembler(binding: makeBinding())
        _ = ingest(&assembler, "response.created", ["response": ["id": "r1"]])
        _ = ingest(&assembler, "response.output_audio_transcript.delta", ["response_id": "r1", "item_id": "a1", "delta": "Garbled"])
        let done = ingest(&assembler, "response.done", [
            "response": ["id": "r1", "status": "completed",
                         "output": [["id": "a1", "content": [["transcript": "Clean final text."]]]]],
        ])
        XCTAssertEqual(done.map(\.finality), [.final])
        XCTAssertEqual(done.first?.text, "Clean final text.")
        XCTAssertEqual(done.first?.providerResponseID, "r1")
    }

    func testStoppingAbandonsOpenTurnsWithoutProducingAFinal() {
        var assembler = deterministicAssembler(binding: makeBinding())
        _ = ingest(&assembler, "input_audio_buffer.speech_started", ["item_id": "u1"])
        _ = ingest(&assembler, "conversation.item.input_audio_transcription.updated", ["item_id": "u1", "transcript": "hel"])
        _ = ingest(&assembler, "response.created", ["response": ["id": "r1"]])
        _ = ingest(&assembler, "response.output_audio_transcript.delta", ["response_id": "r1", "item_id": "a1", "delta": "Wait"])

        let abandoned = assembler.abandonOpenTurns()
        XCTAssertEqual(abandoned.count, 2)
        XCTAssertTrue(abandoned.allSatisfy { $0.finality == .abandoned && $0.abandonReason == .sessionStopped && $0.text.isEmpty })
        XCTAssertEqual(assembler.openTurnCount, 0)
    }

    func testEmptyUserTranscriptIsAbandonedNotSaved() {
        var assembler = deterministicAssembler(binding: makeBinding())
        _ = ingest(&assembler, "input_audio_buffer.speech_started", ["item_id": "u1"])
        let events = ingest(&assembler, "conversation.item.input_audio_transcription.completed", ["item_id": "u1", "transcript": "   "])
        XCTAssertEqual(events.map(\.finality), [.abandoned])
        XCTAssertEqual(events.first?.abandonReason, .emptyTranscript)
    }
}

// MARK: - Durability journal

@MainActor
final class VoiceTranscriptJournalTests: XCTestCase {

    func testAutomaticFlushNeverUsesTheExplicitRetryEntryPoint() async {
        let binding = makeBinding()
        let access = FakeSupportAccess(binding: binding)
        access.failuresRemaining = 2
        let journal = VoiceTranscriptJournal(binding: binding, access: access)
        journal.submitFinal(finalEvent(binding, order: 1))
        await journal.flush()
        access.failuresRemaining = 0
        await journal.flush()
        XCTAssertTrue(access.explicitRetryEvents.isEmpty)
        XCTAssertEqual(journal.savedCount, 1)
    }

    func testExplicitRetryUsesItsOwnPassForRejectedAndBackgroundRejectedPendingFinals() async {
        let binding = makeBinding()
        let recording = FakeSupportAccess(binding: binding)
        recording.failureToThrow = VoiceSupportAppendError.rejected
        recording.failuresRemaining = 1
        let journal = VoiceTranscriptJournal(binding: binding, access: recording)
        let rejected = finalEvent(binding, order: 1)
        journal.submitFinal(rejected)
        await journal.flush()
        XCTAssertEqual(journal.state(of: rejected.localUUID), .rejected)
        await journal.retry(includeRejected: true)
        XCTAssertEqual(recording.explicitRetryEvents, [rejected.localUUID])
        XCTAssertEqual(journal.savedCount, 1)

        let pendingAccess = FakeSupportAccess(binding: binding)
        pendingAccess.failuresRemaining = 100
        let pendingJournal = VoiceTranscriptJournal(binding: binding, access: pendingAccess)
        let pending = finalEvent(binding, order: 2)
        pendingJournal.submitFinal(pending)
        await pendingJournal.flush()
        XCTAssertEqual(pendingJournal.state(of: pending.localUUID), .pending)
        pendingAccess.failuresRemaining = 0
        await pendingJournal.retry(includeRejected: true)
        XCTAssertEqual(pendingAccess.explicitRetryEvents, [pending.localUUID], "A background-rejected final may still be pending in the voice journal")
    }

    func testInterruptedExplicitPassDoesNotMarkLaterAutomaticAppendsAsExplicit() async {
        let binding = makeBinding()
        let recording = FakeSupportAccess(binding: binding)
        recording.failuresRemaining = 100
        let journal = VoiceTranscriptJournal(binding: binding, access: recording)
        let first = finalEvent(binding, order: 1), second = finalEvent(binding, order: 2)
        journal.submitFinal(first); journal.submitFinal(second)
        await journal.flush()
        await journal.retry(includeRejected: true)
        XCTAssertEqual(recording.explicitRetryEvents, [first.localUUID])
        recording.failuresRemaining = 0
        await journal.flush()
        XCTAssertEqual(recording.explicitRetryEvents, [first.localUUID], "The later automatic pass must not inherit marks")
        XCTAssertEqual(recording.appended.map(\.localUUID), [first.localUUID, second.localUUID])
    }

    private func waitUntil(_ timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    func testEventIsNotSavedUntilTheAccessConfirms() async {
        let binding = makeBinding()
        let access = FakeSupportAccess(binding: binding)
        var release: CheckedContinuation<Void, Never>?
        access.appendHook = { [unowned access] event in
            await withCheckedContinuation { release = $0 }
            access.appended.append(event)
        }
        let journal = VoiceTranscriptJournal(binding: binding, access: access)
        let event = finalEvent(binding, order: 1)

        journal.submitFinal(event)
        let reached = await waitUntil { release != nil }
        XCTAssertTrue(reached)
        XCTAssertEqual(journal.state(of: event.localUUID), .inFlight)
        XCTAssertEqual(journal.savedCount, 0, "must not be saved before the confirmation returns")
        XCTAssertEqual(journal.unsavedCount, 1)

        release?.resume()
        await journal.flush()
        XCTAssertEqual(journal.state(of: event.localUUID), .saved)
        XCTAssertEqual(journal.savedCount, 1)
        XCTAssertEqual(journal.unsavedCount, 0)
    }

    func testFailedAppendStaysPendingAndRetriesInConversationOrder() async {
        let binding = makeBinding()
        let access = FakeSupportAccess(binding: binding)
        access.failuresRemaining = 1
        let journal = VoiceTranscriptJournal(binding: binding, access: access)
        let first = finalEvent(binding, order: 1, text: "first")
        let second = finalEvent(binding, order: 2, text: "second", role: .assistant)

        journal.submitFinal(second)   // submitted out of order on purpose
        journal.submitFinal(first)
        await journal.flush()          // waits for the failing pass, then makes one more pass

        // The first pass fails on the lowest-order event and stops (head-of-line). The retry pass then
        // appends both strictly in conversation order, although they were submitted out of order.
        XCTAssertEqual(access.appended.map(\.text), ["first", "second"])
        XCTAssertEqual(access.appendAttempts, 3, "one failed attempt plus two confirmed appends")
        XCTAssertEqual(journal.savedCount, 2)
        XCTAssertEqual(journal.unsavedCount, 0)
    }

    func testRetryableFailureKeepsEverythingPendingUntilExplicitRetry() async {
        let binding = makeBinding()
        let access = FakeSupportAccess(binding: binding)
        access.failuresRemaining = 100
        let journal = VoiceTranscriptJournal(binding: binding, access: access)
        let first = finalEvent(binding, order: 1, text: "first")
        let second = finalEvent(binding, order: 2, text: "second")
        journal.submitFinal(first)
        journal.submitFinal(second)

        await journal.retry()
        XCTAssertEqual(journal.savedCount, 0)
        XCTAssertEqual(journal.unsavedCount, 2, "failed events stay pending and retryable")
        XCTAssertEqual(journal.lastFailure, .retryable)
        XCTAssertTrue(access.appended.isEmpty)

        access.failuresRemaining = 0
        await journal.retry()
        XCTAssertEqual(access.appended.map(\.text), ["first", "second"])
        XCTAssertEqual(journal.savedCount, 2)
        XCTAssertEqual(journal.unsavedCount, 0)
    }

    func testRejectedEventDoesNotBlockOthersAndIsNotRetried() async {
        let binding = makeBinding()
        let access = FakeSupportAccess(binding: binding)
        access.failuresRemaining = 1
        access.failureToThrow = VoiceSupportAppendError.rejected
        let journal = VoiceTranscriptJournal(binding: binding, access: access)
        let bad = finalEvent(binding, order: 1, text: "bad")
        let good = finalEvent(binding, order: 2, text: "good")
        journal.submitFinal(bad)
        journal.submitFinal(good)

        await journal.flush()
        XCTAssertEqual(journal.state(of: bad.localUUID), .rejected)
        XCTAssertEqual(journal.state(of: good.localUUID), .saved)
        XCTAssertEqual(journal.rejectedCount, 1)

        let attemptsBefore = access.appendAttempts
        await journal.retry()
        XCTAssertEqual(access.appendAttempts, attemptsBefore, "rejected events are not retried")
    }

    func testStaleBindingStopsAppendingAndKeepsEventsPending() async {
        let binding = makeBinding()
        let access = FakeSupportAccess(binding: binding)
        access.failuresRemaining = 1
        access.failureToThrow = VoiceSupportAppendError.bindingNotCurrent
        let journal = VoiceTranscriptJournal(binding: binding, access: access)
        let event = finalEvent(binding, order: 1)
        journal.submitFinal(event)

        await journal.flush()
        XCTAssertTrue(journal.isBindingStale)
        XCTAssertEqual(journal.state(of: event.localUUID), .pending)
        let attempts = access.appendAttempts
        await journal.retry()
        XCTAssertEqual(access.appendAttempts, attempts, "nothing is appended once the binding is stale")
        XCTAssertTrue(access.appended.isEmpty)
    }

    func testAcknowledgedEventsReleaseTheirTextAndStayIdempotent() async {
        let binding = makeBinding()
        let access = FakeSupportAccess(binding: binding)
        let journal = VoiceTranscriptJournal(binding: binding, access: access)
        let event = finalEvent(binding, order: 1, text: "held only until acknowledged")

        journal.submitFinal(event)
        await journal.flush()

        XCTAssertEqual(journal.savedCount, 1)
        XCTAssertTrue(journal.entries.isEmpty, "text is released once the access acknowledged it")
        XCTAssertEqual(journal.state(of: event.localUUID), .saved)
        journal.submitFinal(event)   // a replay of an acknowledged identity is not appended again
        await journal.flush()
        XCTAssertEqual(access.appended.count, 1)
    }

    func testSubmitIsIdempotentAndIgnoresPartialsAndForeignBindings() async {
        let binding = makeBinding()
        let access = FakeSupportAccess(binding: binding)
        let journal = VoiceTranscriptJournal(binding: binding, access: access)
        let event = finalEvent(binding, order: 1)

        journal.submitFinal(event)
        journal.submitFinal(event)
        let partial = VoiceTranscriptEvent(
            localUUID: UUID(), binding: binding, role: .user, providerItemID: nil, providerEventID: nil,
            providerResponseID: nil, order: 2, revision: 1, occurredAt: Date(), finality: .partial,
            abandonReason: nil, text: "partial"
        )
        journal.submitFinal(partial)
        journal.submitFinal(finalEvent(makeBinding(), order: 3))   // different binding
        await journal.flush()

        XCTAssertEqual(access.appended.count, 1)
        XCTAssertEqual(journal.savedCount, 1)
        XCTAssertEqual(journal.unresolvedCount, 0)
    }
}

// MARK: - Admission contract

final class VoiceAdmissionContractTests: XCTestCase {

    func testBodyCarriesExactlyTheBoundContractFieldsAndNoInstructions() throws {
        let binding = makeBinding(revision: 12)
        let data = try JSONEncoder().encode(VoiceAdmissionRequestBody(binding: binding))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(object.keys), [
            "transport", "schema_version", "expected_owner", "support_session_id",
            "conversation_id", "context_scope", "expected_privacy_revision",
        ])
        XCTAssertEqual(object["transport"] as? String, "relay")
        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["expected_owner"] as? String, binding.ownerUUID.uuidString.lowercased())
        XCTAssertEqual(object["support_session_id"] as? String, binding.supportSessionUUID.uuidString.lowercased())
        XCTAssertEqual(object["conversation_id"] as? String, binding.conversationUUID.uuidString.lowercased())
        XCTAssertEqual(object["context_scope"] as? String, "personalized")
        XCTAssertEqual(object["expected_privacy_revision"] as? Int, 12)
    }

    func testPrivacyRevisionIsOmittedWhenUnknown() throws {
        let data = try JSONEncoder().encode(VoiceAdmissionRequestBody(binding: makeBinding(revision: nil)))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["expected_privacy_revision"])
        XCTAssertEqual(object.count, 6)
    }
}

// MARK: - Capture start / stop cleanup (no audio)

@MainActor
final class VoiceCaptureCleanupTests: XCTestCase {

    func testFailedStartAfterTapInstalledUnwindsEverythingAndRetrySucceeds() throws {
        let hardware = FakeCaptureHardware()
        hardware.startEngineErrors = [NSError(domain: "synthetic", code: 1)]
        let capture = VoiceAudioCapture(hardware: hardware)

        assertVoiceThrows(try capture.startCapture()) { error in
            guard let voiceError = error as? VoiceError, case .audioSessionFailed = voiceError else {
                return XCTFail("start failures are narrowed to an audio-session error")
            }
        }
        XCTAssertEqual(hardware.calls, ["activate", "format", "installTap", "startEngine", "removeTap", "stopEngine", "deactivate"])
        XCTAssertFalse(capture.isRunning)

        hardware.calls.removeAll()
        XCTAssertNoThrow(try capture.startCapture())
        XCTAssertEqual(hardware.calls, ["activate", "format", "installTap", "startEngine"])
        XCTAssertTrue(capture.isRunning)

        hardware.calls.removeAll()
        capture.stopCapture()
        XCTAssertEqual(hardware.calls, ["removeTap", "stopEngine", "deactivate"])
        capture.stopCapture()
        XCTAssertEqual(hardware.calls, ["removeTap", "stopEngine", "deactivate"], "a second stop is a no-op")
    }

    func testSessionActivationFailureAlsoUnwinds() {
        let hardware = FakeCaptureHardware()
        hardware.activateError = NSError(domain: "synthetic", code: 2)
        let capture = VoiceAudioCapture(hardware: hardware)

        assertVoiceThrows(try capture.startCapture())
        XCTAssertEqual(hardware.calls, ["activate", "removeTap", "stopEngine", "deactivate"])
        XCTAssertFalse(capture.isRunning)
    }

    func testForceStopUnwindsEvenWhenCaptureNeverStartedAndFlagsAreUnset() {
        let hardware = FakeCaptureHardware()
        let capture = VoiceAudioCapture(hardware: hardware)

        capture.forceStop()
        XCTAssertEqual(hardware.calls, ["removeTap", "stopEngine", "deactivate"])
    }
}

// MARK: - Service lifecycle (fakes only)

@MainActor
final class VoiceServiceLifecycleTests: XCTestCase {

    @MainActor
    final class Fixture {
        let owner = UUID()
        let sessionID = UUID()
        let log = VoiceTestLog()
        let permission = Counter()
        let backend: FakeVoiceBackend
        let transport: FakeVoiceTransport
        let capture: FakeVoiceCapture
        let playback: FakeVoicePlayback
        let access: FakeSupportAccess
        let service: GrokVoiceService

        var binding: VoiceSupportBinding { access.binding }

        @MainActor
        init(authOwner: UUID? = nil) {
            let owner = self.owner
            let log = self.log
            let permission = self.permission
            let binding = makeBinding(owner: owner)
            access = FakeSupportAccess(binding: binding)
            backend = FakeVoiceBackend(
                auth: VoiceAuthSnapshot(userID: authOwner ?? owner, accessToken: "token-A"),
                admission: admission(for: binding, sessionID: sessionID),
                log: log
            )
            transport = FakeVoiceTransport(log: log)
            capture = FakeVoiceCapture(log: log)
            playback = FakeVoicePlayback(log: log)
            service = GrokVoiceService(
                backend: backend, transport: transport, capture: capture, playback: playback,
                microphonePermission: { permission.bump() }
            )
        }
    }

    private func waitUntil(_ timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    private func transcriptEvents(_ fx: Fixture, user itemID: String, text: String, event: String) {
        fx.transport.deliver(["type": "input_audio_buffer.speech_started", "item_id": itemID])
        fx.transport.deliver(["type": "input_audio_buffer.committed", "item_id": itemID])
        fx.transport.deliver([
            "type": "conversation.item.input_audio_transcription.completed",
            "item_id": itemID, "transcript": text, "event_id": event,
        ])
    }

    // MARK: Presentation / start

    func testNothingStartsWithoutAnExplicitCall() {
        let fx = Fixture()
        _ = fx.access.preview()
        XCTAssertEqual(fx.access.prepareCalls, 0)
        XCTAssertTrue(fx.backend.admitCalls.isEmpty)
        XCTAssertEqual(fx.capture.startCount, 0)
        XCTAssertEqual(fx.permission.value, 0)
        XCTAssertEqual(fx.service.connectionState, .disconnected)
    }

    func testLegacyUnboundConnectIsRejectedWithoutTouchingTheMicrophone() async {
        let fx = Fixture()
        do {
            try await fx.service.connect()
            XCTFail("the unbound path must not exist")
        } catch {
            XCTAssertEqual(error as? VoiceSupportAccessError, .unavailable)
        }
        XCTAssertTrue(fx.backend.admitCalls.isEmpty)
        XCTAssertEqual(fx.capture.startCount, 0)
        XCTAssertEqual(fx.permission.value, 0)
    }

    func testStartVoicePreparesOnlyAfterTheExplicitCallAndConnectsBound() async throws {
        let fx = Fixture()
        try await fx.service.startVoice(access: fx.access)

        XCTAssertEqual(fx.access.prepareCalls, 1)
        XCTAssertEqual(fx.service.connectionState, .connected)
        XCTAssertTrue(fx.service.isListening)
        await fx.service.end(reason: .userEnded)
    }

    func testPrepareFailureIsATruthfulUnavailableStateWithNoMicrophone() async {
        let fx = Fixture()
        fx.access.prepareError = NSError(domain: "synthetic", code: 3)
        do {
            try await fx.service.startVoice(access: fx.access)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? VoiceSupportAccessError, .unavailable)
        }
        XCTAssertTrue(fx.backend.admitCalls.isEmpty)
        XCTAssertEqual(fx.permission.value, 0)
        XCTAssertEqual(fx.capture.startCount, 0)
        XCTAssertEqual(fx.service.lastStopReason, .failedToStart)
    }

    // MARK: Binding / owner / token

    func testBoundConnectSendsTheContractBodyUsesTheOwnerTokenAndSendsNoInstructions() async throws {
        let fx = Fixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access)

        XCTAssertEqual(fx.service.connectionState, .connected)
        XCTAssertEqual(fx.backend.admitCalls.count, 1)
        XCTAssertEqual(fx.backend.admitCalls[0].body, VoiceAdmissionRequestBody(binding: fx.binding))
        XCTAssertEqual(fx.backend.admitCalls[0].token, "token-A")
        XCTAssertEqual(fx.transport.connectCalls.map(\.sessionId), [fx.sessionID.uuidString])
        XCTAssertEqual(fx.transport.connectCalls.map(\.token), ["token-A"])

        let update = fx.transport.sent.first { $0["type"] as? String == "session.update" }
        let session = update?["session"] as? [String: Any]
        XCTAssertNotNil(session)
        XCTAssertNil(session?["instructions"], "instructions and context are server-owned")
        XCTAssertEqual(session?["voice"] as? String, "ara")
        XCTAssertNotNil(session?["turn_detection"])
        XCTAssertEqual(fx.capture.startCount, 1)

        await fx.service.end(reason: .userEnded)
        XCTAssertEqual(fx.backend.endCalls.count, 1)
        XCTAssertEqual(fx.backend.endCalls[0].request.sessionId, fx.sessionID.uuidString)
        XCTAssertEqual(fx.access.reconcileCalls, 1)
    }

    func testOwnerMismatchIsRejectedBeforeAnythingIsDispatched() async {
        let fx = Fixture(authOwner: UUID())
        do {
            try await fx.service.connect(bound: fx.binding, access: fx.access)
            XCTFail("expected an owner mismatch")
        } catch {
            XCTAssertEqual(error as? VoiceSupportAccessError, .ownerMismatch)
        }
        XCTAssertTrue(fx.backend.admitCalls.isEmpty)
        XCTAssertTrue(fx.backend.endCalls.isEmpty)
        XCTAssertTrue(fx.transport.connectCalls.isEmpty)
        XCTAssertEqual(fx.permission.value, 0, "no microphone prompt for a mismatched owner")
        XCTAssertEqual(fx.capture.startCount, 0)
        XCTAssertEqual(fx.service.lastStopReason, .contextInvalidated)
    }

    func testAccountChangeDuringAdmissionIsAccountedForWithTheCapturedOwnerTokenOnly() async {
        let fx = Fixture()
        fx.backend.onAdmit = { [unowned fx] in
            fx.access.isBindingCurrent = false
            fx.backend.auth = VoiceAuthSnapshot(userID: UUID(), accessToken: "token-OTHER-ACCOUNT")
        }
        do {
            try await fx.service.connect(bound: fx.binding, access: fx.access)
            XCTFail("expected the binding to be rejected after the suspension")
        } catch {
            XCTAssertEqual(error as? VoiceSupportAccessError, .bindingNotCurrent)
        }
        XCTAssertEqual(fx.backend.endCalls.count, 1)
        XCTAssertEqual(fx.backend.endCalls[0].token, "token-A", "never account for the session with another account's token")
        XCTAssertTrue(fx.transport.connectCalls.isEmpty, "no socket after the binding went stale")
        XCTAssertEqual(fx.capture.startCount, 0)
        XCTAssertEqual(fx.service.connectionState, .disconnected)
    }

    func testAdmissionForAnotherSessionIsRejectedBeforeTheSocketAndStillAccountedFor() async {
        let fx = Fixture()
        fx.backend.admission = admission(for: fx.binding, sessionID: fx.sessionID) {
            $0["support_session_id"] = UUID().uuidString.lowercased()
        }
        do {
            try await fx.service.connect(bound: fx.binding, access: fx.access)
            XCTFail("expected a rejection")
        } catch {
            XCTAssertEqual(error as? VoiceSupportAccessError, .sessionMismatch)
        }
        XCTAssertTrue(fx.transport.connectCalls.isEmpty)
        XCTAssertEqual(fx.capture.startCount, 0)
        XCTAssertEqual(fx.backend.endCalls.count, 1, "the admitted session must still be accounted for")
    }

    func testStalePrivacyRevisionInTheNestedContextStopsBeforeTheSocket() async {
        let fx = Fixture()
        fx.backend.admission = admission(for: fx.binding, sessionID: fx.sessionID) { $0["privacy_revision"] = 99 }
        do {
            try await fx.service.connect(bound: fx.binding, access: fx.access)
            XCTFail("expected a rejection")
        } catch {
            XCTAssertEqual(error as? VoiceSupportAccessError, .privacyRevisionChanged)
        }
        XCTAssertTrue(fx.transport.connectCalls.isEmpty)
        XCTAssertEqual(fx.service.lastStopReason, .contextInvalidated)
    }

    func testContextInvalidationWhileConnectedStopsOnTheNextProviderEvent() async throws {
        let fx = Fixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        fx.access.isBindingCurrent = false

        fx.transport.deliver(["type": "ping"])

        XCTAssertEqual(fx.service.lastStopReason, .contextInvalidated)
        XCTAssertFalse(fx.service.isListening)
        XCTAssertGreaterThanOrEqual(fx.capture.forceStopCount, 1)
        XCTAssertEqual(fx.transport.disconnectCount, 1)
        await fx.service.end(reason: .userEnded)
    }

    // MARK: Central stop

    func testStopHaltsCaptureAndPlaybackSynchronouslyBeforeAnyNetworkWork() async throws {
        let fx = Fixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        XCTAssertTrue(fx.service.isListening)

        let remote = fx.service.stopNow(.audioInterrupted)

        // Everything below is observed BEFORE the returned task (the network work) has run.
        XCTAssertFalse(fx.service.isListening)
        XCTAssertFalse(fx.service.isSpeaking)
        XCTAssertEqual(fx.playback.stopCount, 1)
        XCTAssertEqual(fx.capture.forceStopCount, 1)
        XCTAssertEqual(fx.transport.disconnectCount, 1)
        XCTAssertTrue(fx.backend.endCalls.isEmpty, "accounting is network work and must come after the halt")
        XCTAssertEqual(fx.service.lastStopReason, .audioInterrupted)
        XCTAssertEqual(fx.service.connectionState, .disconnected)

        await remote.value
        XCTAssertEqual(fx.backend.endCalls.count, 1)
        let entries = fx.log.entries
        let playbackStop = try XCTUnwrap(entries.firstIndex(of: "playback.stop"))
        let captureStop = try XCTUnwrap(entries.firstIndex(of: "capture.forceStop"))
        let socketClose = try XCTUnwrap(entries.lastIndex(of: "transport.disconnect"))
        let accounting = try XCTUnwrap(entries.firstIndex(of: "backend.endSession"))
        XCTAssertLessThan(playbackStop, captureStop)
        XCTAssertLessThan(captureStop, accounting)
        XCTAssertLessThan(socketClose, accounting)
    }

    func testEveryLifecycleReasonStopsTheSameWay() async throws {
        let reasons: [VoiceStopReason] = [
            .appBackgrounded, .deviceLocked, .audioInterrupted, .routeLost, .accountChanged,
            .contextInvalidated, .idleTimeout, .sessionLimit, .userEnded, .switchedToText,
        ]
        for reason in reasons {
            let fx = Fixture()
            try await fx.service.connect(bound: fx.binding, access: fx.access)
            let remote = fx.service.stopNow(reason)
            XCTAssertFalse(fx.service.isListening, "\(reason)")
            XCTAssertEqual(fx.capture.forceStopCount, 1, "\(reason)")
            XCTAssertEqual(fx.service.lastStopReason, reason)
            await remote.value
        }
    }

    func testSystemAudioInterruptionStopsCaptureAndEndingItNeverRestartsTheMicrophone() async throws {
        let fx = Fixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        XCTAssertEqual(fx.capture.startCount, 1)

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )
        let stopped = await waitUntil { fx.service.lastStopReason == .audioInterrupted }
        XCTAssertTrue(stopped)
        XCTAssertFalse(fx.service.isListening)

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue,
            ]
        )
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(fx.capture.startCount, 1, "no automatic microphone restart, even with shouldResume")
        XCTAssertFalse(fx.service.isListening)
        await fx.service.end(reason: .userEnded)
    }

    func testUnmutingAfterAStopDoesNotStartTheMicrophoneWithoutANewConnection() async throws {
        let fx = Fixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        await fx.service.end(reason: .routeLost)

        XCTAssertNoThrow(try fx.service.setMuted(false))
        XCTAssertEqual(fx.capture.startCount, 1)
        XCTAssertFalse(fx.service.isListening)
        assertVoiceThrows(try fx.service.startListening())
    }

    func testStartFailureCleansUpAndRetryIsSafe() async throws {
        let fx = Fixture()
        fx.capture.startError = VoiceError.audioSessionFailed("synthetic")
        do {
            try await fx.service.connect(bound: fx.binding, access: fx.access)
            XCTFail("expected the capture start to fail")
        } catch {
            XCTAssertNotNil(error as? VoiceError)
        }
        XCTAssertFalse(fx.service.isListening)
        XCTAssertEqual(fx.capture.startCount, 0)
        XCTAssertGreaterThanOrEqual(fx.capture.forceStopCount, 1, "hardware is unwound although no flag was set")
        XCTAssertEqual(fx.transport.disconnectCount, 1)
        XCTAssertEqual(fx.backend.endCalls.count, 1, "the admitted session is still accounted for")
        XCTAssertEqual(fx.service.lastStopReason, .failedToStart)
        guard case .error = fx.service.connectionState else { return XCTFail("expected a failed state") }

        fx.capture.startError = nil
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        XCTAssertEqual(fx.service.connectionState, .connected)
        XCTAssertTrue(fx.service.isListening)
        XCTAssertEqual(fx.capture.startCount, 1)
        XCTAssertNil(fx.service.lastStopReason)
        await fx.service.end(reason: .userEnded)
    }

    // MARK: Mute and barge-in

    func testBargeInWhileMutedKeepsTheMuteAndNeverStartsTheMicrophone() async throws {
        let fx = Fixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access, startMuted: true)
        XCTAssertTrue(fx.service.isMuted)
        XCTAssertFalse(fx.service.isListening)
        XCTAssertEqual(fx.capture.startCount, 0)

        fx.transport.deliver(["type": "response.created"])
        XCTAssertTrue(fx.service.isSpeaking)

        fx.service.interruptPlayback()

        XCTAssertFalse(fx.service.isSpeaking)
        XCTAssertTrue(fx.service.isMuted, "interrupting playback must preserve the explicit mute")
        XCTAssertFalse(fx.service.isListening)
        XCTAssertEqual(fx.capture.startCount, 0, "barge-in must never start the microphone")
        XCTAssertTrue(fx.transport.sentTypes().contains("response.cancel"))
        await fx.service.end(reason: .userEnded)
    }

    func testBargeInWhileListeningLeavesCaptureExactlyAsItWas() async throws {
        let fx = Fixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        fx.transport.deliver(["type": "response.created"])

        fx.service.interruptPlayback()

        XCTAssertTrue(fx.service.isListening)
        XCTAssertFalse(fx.service.isMuted)
        XCTAssertEqual(fx.capture.startCount, 1)
        XCTAssertEqual(fx.capture.stopCount, 0)
        await fx.service.end(reason: .userEnded)
    }

    func testServiceOwnsTheMuteChoiceAndRestoresItWhenUnmuteFails() async throws {
        let fx = Fixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access)

        try fx.service.setMuted(true)
        XCTAssertTrue(fx.service.isMuted)
        XCTAssertFalse(fx.service.isListening)
        XCTAssertEqual(fx.capture.stopCount, 1)

        fx.capture.startError = VoiceError.audioSessionFailed("synthetic")
        assertVoiceThrows(try fx.service.setMuted(false))
        XCTAssertTrue(fx.service.isMuted, "the displayed mute must match the real, stopped state")
        XCTAssertFalse(fx.service.isListening)

        fx.capture.startError = nil
        try fx.service.setMuted(false)
        XCTAssertFalse(fx.service.isMuted)
        XCTAssertTrue(fx.service.isListening)
        await fx.service.end(reason: .userEnded)
    }

    func testFramesQueuedBeforeAMuteAreNeverSent() async throws {
        let fx = Fixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access)

        fx.capture.emit([1, 2])
        let sentWhileListening = await waitUntil { fx.transport.sentTypes().contains("input_audio_buffer.append") }
        XCTAssertTrue(sentWhileListening)

        try fx.service.setMuted(true)
        let before = fx.transport.sentTypes().filter { $0 == "input_audio_buffer.append" }.count
        fx.capture.emit([3, 4], generation: 1)
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(fx.transport.sentTypes().filter { $0 == "input_audio_buffer.append" }.count, before)
        await fx.service.end(reason: .userEnded)
    }

    // MARK: Transcripts through the service

    func testFinalsAreAppendedAsTheyArriveAndSavedOnlyAfterConfirmation() async throws {
        let fx = Fixture()
        fx.access.failuresRemaining = 1
        var observed: [VoiceTranscriptEvent] = []
        fx.service.transcriptEventHandler = { observed.append($0) }
        try await fx.service.connect(bound: fx.binding, access: fx.access)

        fx.transport.deliver(["type": "input_audio_buffer.speech_started", "item_id": "u1"])
        fx.transport.deliver(["type": "conversation.item.input_audio_transcription.updated", "item_id": "u1", "transcript": "Hel"])
        XCTAssertEqual(fx.access.appendAttempts, 0, "a partial is display-only and never appended")
        fx.transport.deliver([
            "type": "conversation.item.input_audio_transcription.completed",
            "item_id": "u1", "transcript": "Hello", "event_id": "e1",
        ])

        // The first append fails: nothing is saved and the event stays retryable.
        let attempted = await waitUntil { fx.access.appendAttempts == 1 }
        XCTAssertTrue(attempted)
        XCTAssertEqual(fx.service.savedTranscriptCount, 0)
        XCTAssertEqual(fx.service.unsavedTranscriptCount, 1)
        XCTAssertTrue(fx.access.appended.isEmpty)

        await fx.service.retryUnsavedTranscript()
        XCTAssertEqual(fx.service.savedTranscriptCount, 1)
        XCTAssertEqual(fx.service.unsavedTranscriptCount, 0)
        XCTAssertEqual(fx.access.appended.map(\.text), ["Hello"])
        XCTAssertEqual(fx.access.appended.first?.role, .user)
        XCTAssertEqual(fx.access.appended.first?.binding, fx.binding)
        XCTAssertEqual(observed.map(\.finality), [.partial, .final])
        await fx.service.end(reason: .userEnded)
    }

    func testRepeatedIdenticalUtterancesAreBothPersistedThroughTheService() async throws {
        let fx = Fixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access)

        transcriptEvents(fx, user: "u1", text: "Yes", event: "e1")
        transcriptEvents(fx, user: "u2", text: "Yes", event: "e2")
        await fx.service.end(reason: .userEnded)

        XCTAssertEqual(fx.access.appended.map(\.text), ["Yes", "Yes"])
        XCTAssertEqual(Set(fx.access.appended.map(\.localUUID)).count, 2)
        XCTAssertEqual(fx.access.appended.map(\.order), [1, 2])
    }

    func testUnconfirmedFinalsSurviveEndAndCanStillBeRetried() async throws {
        let fx = Fixture()
        fx.access.failuresRemaining = 100
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        transcriptEvents(fx, user: "u1", text: "Keep me", event: "e1")

        await fx.service.end(reason: .switchedToText)
        XCTAssertTrue(fx.service.hasUnsavedTranscript)
        XCTAssertEqual(fx.service.unsavedTranscriptCount, 1)
        XCTAssertEqual(fx.service.savedTranscriptCount, 0)

        fx.access.failuresRemaining = 0
        await fx.service.retryUnsavedTranscript()
        XCTAssertFalse(fx.service.hasUnsavedTranscript)
        XCTAssertEqual(fx.access.appended.map(\.text), ["Keep me"])
        XCTAssertGreaterThanOrEqual(fx.access.reconcileCalls, 2, "reconcile after End and again after a successful retry")
    }

    func testAnInterruptedAssistantResponseIsNeverPersistedAsCompleteText() async throws {
        let fx = Fixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        fx.transport.deliver(["type": "response.created", "response": ["id": "r1"]])
        fx.transport.deliver([
            "type": "response.output_audio_transcript.delta",
            "response_id": "r1", "item_id": "a1", "delta": "I was about to say",
        ])

        fx.service.interruptPlayback()
        fx.transport.deliver(["type": "response.done", "response": ["id": "r1", "status": "cancelled"]])
        await fx.service.end(reason: .userEnded)

        XCTAssertTrue(fx.access.appended.isEmpty)
        XCTAssertEqual(fx.service.savedTranscriptCount, 0)
    }
}

// MARK: - Shared helpers for the regression groups below

private typealias LifecycleFixture = VoiceServiceLifecycleTests.Fixture

@MainActor
private func settle(_ milliseconds: UInt64 = 80) async {
    try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
}

@MainActor
private func waitUntil(_ timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return true
}

@MainActor
private final class DoneFlag { var done = false }

/// True if `task` finishes within `seconds`. A task that never finishes simply reports false.
@MainActor
private func completes(_ task: Task<Void, Never>, within seconds: TimeInterval) async -> Bool {
    let flag = DoneFlag()
    Task { @MainActor in
        await task.value
        flag.done = true
    }
    return await waitUntil(seconds) { flag.done }
}

@MainActor
private func deliverUserFinal(_ fx: LifecycleFixture, item: String, text: String) {
    fx.transport.deliver(["type": "input_audio_buffer.speech_started", "item_id": item])
    fx.transport.deliver(["type": "input_audio_buffer.committed", "item_id": item])
    fx.transport.deliver([
        "type": "conversation.item.input_audio_transcription.completed",
        "item_id": item, "transcript": text, "event_id": "evt-\(item)",
    ])
}

private func captionEvent(
    _ binding: VoiceSupportBinding, id: UUID, role: VoiceTranscriptRole = .assistant,
    finality: VoiceTranscriptFinality, text: String
) -> VoiceTranscriptEvent {
    VoiceTranscriptEvent(
        localUUID: id, binding: binding, role: role, providerItemID: nil, providerEventID: nil,
        providerResponseID: nil, order: 1, revision: 1, occurredAt: Date(timeIntervalSince1970: 1_000),
        finality: finality, abandonReason: finality == .abandoned ? .responseCancelled : nil,
        text: finality == .abandoned ? "" : text
    )
}

// MARK: - MF-VS-004: statusless completion never promotes unfinished parts

@MainActor
final class VoiceStatuslessCompletionTests: XCTestCase {

    private func streamTwoParts(_ assembler: inout VoiceTranscriptAssembler, secondPartFinal: Bool) {
        _ = ingest(&assembler, "response.created", ["response": ["id": "r1"]])
        _ = ingest(&assembler, "response.output_item.added",
                   ["response_id": "r1", "output_index": 0, "item": ["id": "a1", "role": "assistant"]])
        _ = ingest(&assembler, "response.output_item.added",
                   ["response_id": "r1", "output_index": 1, "item": ["id": "a2", "role": "assistant"]])
        _ = ingest(&assembler, "response.output_audio_transcript.done",
                   ["response_id": "r1", "item_id": "a1", "output_index": 0, "transcript": "Complete part. "])
        _ = ingest(&assembler, "response.output_audio_transcript.delta",
                   ["response_id": "r1", "item_id": "a2", "output_index": 1, "delta": "unfinished fragm"])
        if secondPartFinal {
            _ = ingest(&assembler, "response.output_audio_transcript.done",
                       ["response_id": "r1", "item_id": "a2", "output_index": 1, "transcript": "Second part."])
        }
    }

    func testOneFinalPartDoesNotPromoteAnUnfinishedPartWhenThereIsNoStatus() {
        var assembler = deterministicAssembler(binding: makeBinding())
        streamTwoParts(&assembler, secondPartFinal: false)

        let done = ingest(&assembler, "response.done", ["response": ["id": "r1"]])

        XCTAssertEqual(done.map(\.finality), [.abandoned], "a mixed final/partial reply must not become a final transcript")
        XCTAssertEqual(done.first?.abandonReason, .responseIncomplete)
        XCTAssertEqual(done.first?.text, "")
        XCTAssertFalse(done.contains { $0.text.contains("unfinished") })
    }

    func testEveryPartFinalWithoutStatusIsFinalInOutputOrder() {
        var assembler = deterministicAssembler(binding: makeBinding())
        streamTwoParts(&assembler, secondPartFinal: true)

        let done = ingest(&assembler, "response.done", ["response": ["id": "r1"]])

        XCTAssertEqual(done.map(\.finality), [.final])
        XCTAssertEqual(done.first?.text, "Complete part. Second part.")
    }

    func testPartsKeepProviderOutputOrderEvenWhenTheySettleOutOfOrder() {
        var assembler = deterministicAssembler(binding: makeBinding())
        _ = ingest(&assembler, "response.created", ["response": ["id": "r1"]])
        // The second item settles first; neither item was announced beforehand.
        _ = ingest(&assembler, "response.output_audio_transcript.done",
                   ["response_id": "r1", "item_id": "a2", "output_index": 1, "transcript": "Second."])
        _ = ingest(&assembler, "response.output_audio_transcript.done",
                   ["response_id": "r1", "item_id": "a1", "output_index": 0, "transcript": "First. "])

        let done = ingest(&assembler, "response.done", ["response": ["id": "r1"]])

        XCTAssertEqual(done.map(\.finality), [.final])
        XCTAssertEqual(done.first?.text, "First. Second.")
    }

    func testProviderOutputListIsAuthoritativeAndExcludesAnUnfinishedStreamedPart() {
        var assembler = deterministicAssembler(binding: makeBinding())
        streamTwoParts(&assembler, secondPartFinal: false)

        let done = ingest(&assembler, "response.done", [
            "response": ["id": "r1", "output": [["id": "a1", "content": [["transcript": "Complete part."]]]]],
        ])

        XCTAssertEqual(done.map(\.finality), [.final])
        XCTAssertEqual(done.first?.text, "Complete part.")
    }

    func testAProviderReportedCompletedStatusStillTrustsTheStreamedText() {
        var assembler = deterministicAssembler(binding: makeBinding())
        streamTwoParts(&assembler, secondPartFinal: false)

        let done = ingest(&assembler, "response.done", ["response": ["id": "r1", "status": "completed"]])

        XCTAssertEqual(done.map(\.finality), [.final], "an explicit completed status is the provider's own assertion")
        XCTAssertEqual(done.first?.text, "Complete part. unfinished fragm")
    }
}

// MARK: - MF-VS-005: captions expose their actual finality

@MainActor
final class VoiceCaptionTests: XCTestCase {

    func testPartialIsLiveAndOnlyTheFinalEventMarksItComplete() {
        let binding = makeBinding()
        let turn = UUID()
        var tracker = VoiceCaptionTracker()

        tracker.apply(captionEvent(binding, id: turn, finality: .partial, text: "Hel"))
        XCTAssertEqual(tracker.current?.phase, .live)
        XCTAssertEqual(tracker.current?.phaseLabel, "Live · partial")
        XCTAssertEqual(tracker.current?.accessibilityLabel, "Assistant caption, live, not final")

        tracker.apply(captionEvent(binding, id: turn, finality: .partial, text: "Hello"))
        XCTAssertEqual(tracker.current?.phase, .live, "more partial text never makes a caption complete")
        XCTAssertEqual(tracker.current?.text, "Hello")

        tracker.apply(captionEvent(binding, id: turn, finality: .final, text: "Hello there."))
        XCTAssertEqual(tracker.current?.phase, .complete)
        XCTAssertEqual(tracker.current?.phaseLabel, "Complete")
        XCTAssertEqual(tracker.current?.accessibilityLabel, "Assistant caption, complete")
        XCTAssertEqual(tracker.current?.text, "Hello there.")
    }

    func testALatePartialNeverRegressesACompletedCaption() {
        let binding = makeBinding()
        let turn = UUID()
        var tracker = VoiceCaptionTracker()
        tracker.apply(captionEvent(binding, id: turn, finality: .final, text: "Done."))
        tracker.apply(captionEvent(binding, id: turn, finality: .partial, text: "Don"))
        XCTAssertEqual(tracker.current?.phase, .complete)
        XCTAssertEqual(tracker.current?.text, "Done.")
    }

    func testAbandonedTurnBecomesInterruptedAndIsLabeledNotSaved() {
        let binding = makeBinding()
        let turn = UUID()
        var tracker = VoiceCaptionTracker()
        tracker.apply(captionEvent(binding, id: turn, finality: .partial, text: "I was about to"))
        tracker.apply(captionEvent(binding, id: turn, finality: .abandoned, text: ""))

        XCTAssertEqual(tracker.current?.phase, .interrupted)
        XCTAssertEqual(tracker.current?.text, "I was about to", "the displayed provisional text stays, now labeled")
        XCTAssertEqual(tracker.current?.accessibilityLabel, "Assistant caption, interrupted, not saved")

        tracker.apply(captionEvent(binding, id: turn, finality: .partial, text: "I was about to say"))
        XCTAssertEqual(tracker.current?.phase, .interrupted, "a late partial does not revive an interrupted caption")
    }

    func testAnotherTurnsAbandonmentDoesNotTouchTheCaptionOnScreen() {
        let binding = makeBinding()
        var tracker = VoiceCaptionTracker()
        let shown = UUID()
        tracker.apply(captionEvent(binding, id: shown, role: .user, finality: .partial, text: "Hello"))
        tracker.apply(captionEvent(binding, id: UUID(), finality: .abandoned, text: ""))
        XCTAssertEqual(tracker.current?.phase, .live)
        XCTAssertEqual(tracker.current?.speakerLabel, "You")
    }

    func testClearIfCompleteDropsOnlyFinishedCaptions() {
        let binding = makeBinding()
        var tracker = VoiceCaptionTracker()
        tracker.apply(captionEvent(binding, id: UUID(), finality: .partial, text: "live"))
        tracker.clearIfComplete()
        XCTAssertEqual(tracker.current?.phase, .live)
        tracker.apply(captionEvent(binding, id: UUID(), finality: .final, text: "done"))
        tracker.clearIfComplete()
        XCTAssertNil(tracker.current)
    }

    func testServiceCaptionFollowsTypedFinalityAndInterruptionAndClearsOnStop() async throws {
        let fx = LifecycleFixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access)

        fx.transport.deliver(["type": "input_audio_buffer.speech_started", "item_id": "u1"])
        fx.transport.deliver(["type": "conversation.item.input_audio_transcription.updated", "item_id": "u1", "transcript": "Hel"])
        XCTAssertEqual(fx.service.caption?.phase, .live)
        XCTAssertEqual(fx.service.caption?.role, .user)
        XCTAssertEqual(fx.service.caption?.text, "Hel")

        fx.transport.deliver([
            "type": "conversation.item.input_audio_transcription.completed",
            "item_id": "u1", "transcript": "Hello", "event_id": "e1",
        ])
        XCTAssertEqual(fx.service.caption?.phase, .complete)
        XCTAssertEqual(fx.service.caption?.text, "Hello")

        fx.transport.deliver(["type": "response.created", "response": ["id": "r1"]])
        fx.transport.deliver([
            "type": "response.output_audio_transcript.delta",
            "response_id": "r1", "item_id": "a1", "delta": "Let me",
        ])
        XCTAssertEqual(fx.service.caption?.phase, .live)
        XCTAssertEqual(fx.service.caption?.role, .assistant)

        fx.service.interruptPlayback()
        fx.transport.deliver(["type": "response.done", "response": ["id": "r1", "status": "cancelled"]])
        XCTAssertEqual(fx.service.caption?.phase, .interrupted)
        XCTAssertEqual(fx.service.caption?.text, "Let me")

        await fx.service.end(reason: .userEnded)
        XCTAssertNil(fx.service.caption)
    }
}

// MARK: - MF-VS-003: audio is bound to the capture generation that produced it

@MainActor
final class VoiceCaptureGenerationTests: XCTestCase {

    func testWorkQueuedByAnOldCaptureNeverReachesTheNewCaptureAfterARestart() async throws {
        let hardware = FakeCaptureHardware()
        let capture = VoiceAudioCapture(hardware: hardware)
        var delivered: [VoiceCaptureGeneration] = []
        var levels: [VoiceCaptureGeneration] = []
        capture.onAudioData = { _, generation in delivered.append(generation) }
        capture.onMicLevelUpdate = { _, generation in levels.append(generation) }

        let first = try capture.startCapture()
        let oldTap = try XCTUnwrap(hardware.handler)
        oldTap(hardware.makeBuffer())          // deferred to the main actor, not processed yet
        capture.stopCapture()
        let second = try capture.startCapture() // restarted before the deferred work runs
        XCTAssertNotEqual(first, second)

        await settle()
        XCTAssertTrue(delivered.isEmpty, "bytes from the old capture must not reach the new one")
        XCTAssertTrue(levels.isEmpty, "levels from the old capture must not reach the new one")

        // Control: the new capture's own tap is delivered, stamped with its generation.
        try XCTUnwrap(hardware.handler)(hardware.makeBuffer())
        await settle()
        XCTAssertEqual(delivered, [second])
        XCTAssertEqual(levels, [second])
    }

    func testAnOldTapCallbackInvokedAfterARestartIsIgnoredToo() async throws {
        let hardware = FakeCaptureHardware()
        let capture = VoiceAudioCapture(hardware: hardware)
        var delivered: [VoiceCaptureGeneration] = []
        capture.onAudioData = { _, generation in delivered.append(generation) }

        _ = try capture.startCapture()
        let oldTap = try XCTUnwrap(hardware.handler)
        capture.stopCapture()
        _ = try capture.startCapture()
        oldTap(hardware.makeBuffer())

        await settle()
        XCTAssertTrue(delivered.isEmpty)
    }

    func testTheGenerationIsInvalidatedByEveryStopAndByAFailedStart() throws {
        let hardware = FakeCaptureHardware()
        hardware.startEngineErrors = [NSError(domain: "synthetic", code: 1)]
        let capture = VoiceAudioCapture(hardware: hardware)

        assertVoiceThrows(try capture.startCapture())
        XCTAssertNil(capture.currentGeneration, "a failed start leaves no generation active")

        let running = try capture.startCapture()
        XCTAssertEqual(capture.currentGeneration, running)
        XCTAssertEqual(try capture.startCapture(), running, "starting while running keeps the same generation")

        capture.stopCapture()
        XCTAssertNil(capture.currentGeneration)
        _ = try capture.startCapture()
        capture.forceStop()
        XCTAssertNil(capture.currentGeneration)
    }
}

@MainActor
final class VoiceServiceCaptureGenerationTests: XCTestCase {

    private func appends(_ fx: LifecycleFixture) -> Int {
        fx.transport.sentTypes().filter { $0 == "input_audio_buffer.append" }.count
    }

    func testAudioFromBeforeAMuteIsNeverSentAfterAnUnmuteStartsANewCapture() async throws {
        let fx = LifecycleFixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        let first = fx.capture.lastGeneration

        try fx.service.setMuted(true)
        try fx.service.setMuted(false)
        let second = fx.capture.lastGeneration
        XCTAssertNotEqual(first, second)

        fx.capture.emit([9, 9], generation: first)
        XCTAssertEqual(appends(fx), 0, "a frame produced before the mute must not pass after the unmute")

        fx.capture.emit([1, 2], generation: second)
        XCTAssertEqual(appends(fx), 1, "delivery is synchronous: no extra hop that could outlive a restart")
        await fx.service.end(reason: .userEnded)
    }

    func testAudioFromAnEarlierSessionIsDroppedAfterAReconnect() async throws {
        let fx = LifecycleFixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        let first = fx.capture.lastGeneration
        await fx.service.end(reason: .userEnded)

        try await fx.service.connect(bound: fx.binding, access: fx.access)
        let second = fx.capture.lastGeneration
        XCTAssertNotEqual(first, second)

        fx.capture.emit([7], generation: first)
        XCTAssertEqual(appends(fx), 0)
        fx.capture.emit([7], generation: second)
        XCTAssertEqual(appends(fx), 1)
        await fx.service.end(reason: .userEnded)
    }

    func testAMicLevelFromAnEarlierGenerationIsIgnored() async throws {
        let fx = LifecycleFixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        let first = fx.capture.lastGeneration
        try fx.service.setMuted(true)
        try fx.service.setMuted(false)
        let second = fx.capture.lastGeneration

        fx.capture.onMicLevelUpdate?(0.9, first)
        XCTAssertEqual(fx.service.micLevel, 0)
        fx.capture.onMicLevelUpdate?(0.9, second)
        XCTAssertEqual(fx.service.micLevel, 0.9, accuracy: 0.0001)
        await fx.service.end(reason: .userEnded)
    }
}

// MARK: - MF-VS-001: rejected finals hold the screen and stay recoverable

@MainActor
final class VoiceLeaveAndRecoveryTests: XCTestCase {

    func testTheGateTreatsRejectedExactlyLikePending() {
        XCTAssertEqual(VoiceLeaveGate.decide(unsaved: 0, rejected: 0), .leave)
        XCTAssertEqual(VoiceLeaveGate.decide(unsaved: 1, rejected: 0), .holdForTranscript)
        XCTAssertEqual(VoiceLeaveGate.decide(unsaved: 0, rejected: 1), .holdForTranscript)
        XCTAssertFalse(VoiceLeaveGate.shouldAutoLeave(leaveRequested: true, unsaved: 0, rejected: 1),
                       "a pending final becoming rejected must not release the hold")
        XCTAssertTrue(VoiceLeaveGate.shouldAutoLeave(leaveRequested: true, unsaved: 0, rejected: 0))
        XCTAssertFalse(VoiceLeaveGate.shouldAutoLeave(leaveRequested: false, unsaved: 0, rejected: 0))
    }

    func testARejectedFinalBeforeEndHoldsTheScreenAndRemainsRecoverable() async throws {
        let fx = LifecycleFixture()
        fx.access.failuresRemaining = 1
        fx.access.failureToThrow = VoiceSupportAppendError.rejected
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        deliverUserFinal(fx, item: "u1", text: "Please keep this")
        let rejected = await waitUntil { fx.service.rejectedTranscriptCount == 1 }
        XCTAssertTrue(rejected)

        let outcome = await fx.service.end(reason: .switchedToText)

        XCTAssertEqual(outcome.rejectedTranscripts, 1)
        XCTAssertEqual(outcome.unsavedTranscripts, 0)
        XCTAssertTrue(outcome.hasUnresolvedTranscript)
        XCTAssertTrue(fx.service.hasUnresolvedTranscript)
        XCTAssertEqual(VoiceLeaveGate.decide(unsaved: outcome.unsavedTranscripts, rejected: outcome.rejectedTranscripts),
                       .holdForTranscript, "End must not dismiss over a rejected final")

        // An ordinary retry does not silently resend a permanently rejected final...
        await fx.service.retryUnsavedTranscript()
        XCTAssertEqual(fx.service.rejectedTranscriptCount, 1)
        XCTAssertTrue(fx.access.appended.isEmpty)

        // ...but the person can explicitly retry it, and only then is it saved.
        await fx.service.retryUnsavedTranscript(includeRejected: true)
        XCTAssertEqual(fx.access.appended.map(\.text), ["Please keep this"])
        XCTAssertFalse(fx.service.hasUnresolvedTranscript)
        XCTAssertTrue(VoiceLeaveGate.shouldAutoLeave(
            leaveRequested: true, unsaved: fx.service.unsavedTranscriptCount, rejected: fx.service.rejectedTranscriptCount))
    }

    func testAPendingFinalThatBecomesRejectedDuringEndStillHoldsTheScreen() async throws {
        let fx = LifecycleFixture()
        var gate: CheckedContinuation<Void, Never>?
        fx.access.appendHook = { _ in
            await withCheckedContinuation { gate = $0 }
            throw VoiceSupportAppendError.rejected
        }
        fx.service.endRemoteTimeout = 5
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        deliverUserFinal(fx, item: "u1", text: "Pending then rejected")
        let inFlight = await waitUntil { gate != nil }
        XCTAssertTrue(inFlight)

        let ending = Task { @MainActor in await fx.service.end(reason: .switchedToText) }
        let stopped = await waitUntil { fx.capture.forceStopCount == 1 }
        XCTAssertTrue(stopped, "capture stops immediately, while the append is still suspended")

        gate?.resume()   // the access now rejects the event during End's flush
        let outcome = await ending.value

        XCTAssertEqual(outcome.unsavedTranscripts, 0)
        XCTAssertEqual(outcome.rejectedTranscripts, 1)
        XCTAssertEqual(VoiceLeaveGate.decide(unsaved: outcome.unsavedTranscripts, rejected: outcome.rejectedTranscripts),
                       .holdForTranscript)
        XCTAssertFalse(VoiceLeaveGate.shouldAutoLeave(
            leaveRequested: true, unsaved: fx.service.unsavedTranscriptCount, rejected: fx.service.rejectedTranscriptCount))
        XCTAssertTrue(fx.access.appended.isEmpty)
    }

    func testDiscardingIsAnExplicitSeparateActAndNeverMarksAnythingSaved() async throws {
        let fx = LifecycleFixture()
        fx.access.failuresRemaining = 100   // retryable: stays pending
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        deliverUserFinal(fx, item: "u1", text: "Not yet acknowledged")
        let outcome = await fx.service.end(reason: .userEnded)

        XCTAssertEqual(outcome.unsavedTranscripts, 1)
        XCTAssertTrue(fx.service.hasUnresolvedTranscript, "End alone never drops an unacknowledged final")

        fx.service.discardUnresolvedTranscript()

        XCTAssertFalse(fx.service.hasUnresolvedTranscript)
        XCTAssertEqual(fx.service.unsavedTranscriptCount, 0)
        XCTAssertEqual(fx.service.rejectedTranscriptCount, 0)
        XCTAssertTrue(fx.access.appended.isEmpty, "discarding must not look like a save")
        XCTAssertEqual(VoiceLeaveGate.decide(unsaved: 0, rejected: 0), .leave)
    }

    func testRejectedFinalsAreRetainedUntilRetriedOrDiscarded() async throws {
        let binding = makeBinding()
        let access = FakeSupportAccess(binding: binding)
        access.failuresRemaining = 1
        access.failureToThrow = VoiceSupportAppendError.rejected
        let journal = VoiceTranscriptJournal(binding: binding, access: access)
        let event = finalEvent(binding, order: 1, text: "retained")
        journal.submitFinal(event)
        await journal.flush()

        XCTAssertEqual(journal.state(of: event.localUUID), .rejected)
        XCTAssertEqual(journal.entries[event.localUUID]?.event.text, "retained", "text is held while rejected")
        XCTAssertEqual(journal.unresolvedCount, 1)

        XCTAssertEqual(journal.discardUnresolved(), 1)
        XCTAssertEqual(journal.unresolvedCount, 0)
        XCTAssertEqual(journal.savedCount, 0)
    }
}

// MARK: - MF-VS-002: End never waits indefinitely on remote work

@MainActor
final class VoiceBoundedEndTests: XCTestCase {

    func testEndReturnsWhileAnAppendIsSuspendedAndTheFinalIsNeitherSavedNorDropped() async throws {
        let fx = LifecycleFixture()
        fx.service.endRemoteTimeout = 0.05
        var release: CheckedContinuation<Void, Never>?
        fx.access.appendHook = { [unowned fx] event in
            await withCheckedContinuation { release = $0 }
            fx.access.appended.append(event)
        }
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        deliverUserFinal(fx, item: "u1", text: "In flight")
        let inFlight = await waitUntil { release != nil }
        XCTAssertTrue(inFlight)

        let started = Date()
        let outcome = await fx.service.end(reason: .switchedToText)

        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5, "End must not wait on the suspended append")
        XCTAssertEqual(fx.capture.forceStopCount, 1, "capture stopped synchronously")
        XCTAssertFalse(outcome.remoteWorkCompleted)
        XCTAssertEqual(outcome.accounting, .confirmed, "accounting finished independently of the suspended append")
        XCTAssertEqual(outcome.unsavedTranscripts, 1, "an in-flight final is reported unsaved, never saved")
        XCTAssertTrue(fx.service.hasUnresolvedTranscript)
        XCTAssertTrue(fx.access.appended.isEmpty)
        XCTAssertEqual(fx.backend.endCalls.count, 1, "accounting does not queue behind the suspended append")

        release?.resume()   // the write finally lands: the final was kept, not dropped
        let landed = await waitUntil { fx.service.unsavedTranscriptCount == 0 && fx.access.appended.count == 1 }
        XCTAssertTrue(landed)
        XCTAssertEqual(fx.access.appended.map(\.text), ["In flight"])
        let reconciled = await waitUntil { fx.access.reconcileCalls == 1 }
        XCTAssertTrue(reconciled)
    }

    func testEndReturnsWhileReconcileIsSuspendedAndAFullySavedTranscriptDoesNotHoldNavigation() async throws {
        let fx = LifecycleFixture()
        fx.service.endRemoteTimeout = 0.05
        var release: CheckedContinuation<Void, Never>?
        fx.access.reconcileHook = { await withCheckedContinuation { release = $0 } }
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        deliverUserFinal(fx, item: "u1", text: "Saved already")
        let saved = await waitUntil { fx.access.appended.count == 1 && fx.service.unsavedTranscriptCount == 0 }
        XCTAssertTrue(saved)

        let outcome = await fx.service.end(reason: .switchedToText)

        XCTAssertFalse(outcome.remoteWorkCompleted, "reconcile has not finished and is not reported done")
        XCTAssertFalse(outcome.hasUnresolvedTranscript)
        XCTAssertEqual(VoiceLeaveGate.decide(unsaved: outcome.unsavedTranscripts, rejected: outcome.rejectedTranscripts), .leave,
                       "the text fallback resolves without waiting for reconcile")
        XCTAssertEqual(fx.capture.forceStopCount, 1)
        release?.resume()
    }

    func testEndReturnsWhileSessionAccountingIsSuspendedAndANewStartIsNotBlocked() async throws {
        let fx = LifecycleFixture()
        fx.service.endRemoteTimeout = 0.05
        var release: CheckedContinuation<Void, Never>?
        fx.backend.endSessionHook = { _ in await withCheckedContinuation { release = $0 } }
        try await fx.service.connect(bound: fx.binding, access: fx.access)

        let outcome = await fx.service.end(reason: .userEnded)
        XCTAssertFalse(outcome.remoteWorkCompleted)
        XCTAssertEqual(outcome.accounting, .pending, "an unanswered session-end call is never reported as success")
        XCTAssertFalse(outcome.hasUnresolvedTranscript)
        XCTAssertEqual(fx.backend.endCalls.count, 1)
        XCTAssertTrue(fx.service.isEnding, "the earlier accounting call is still suspended")

        // An explicit new start is its own binding and is not blocked by the earlier accounting.
        fx.backend.endSessionHook = nil
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        XCTAssertEqual(fx.service.connectionState, .connected)
        XCTAssertEqual(fx.backend.admitCalls.count, 2)
        XCTAssertEqual(fx.capture.startCount, 2)

        release?.resume()
        await fx.service.end(reason: .userEnded)
    }

    func testEndReturnsWhileTheAuthRefreshForAccountingIsSuspended() async throws {
        let fx = LifecycleFixture()
        fx.service.endRemoteTimeout = 0.05
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        var release: CheckedContinuation<Void, Never>?
        fx.backend.authHook = { await withCheckedContinuation { release = $0 } }

        let outcome = await fx.service.end(reason: .switchedToText)

        XCTAssertFalse(outcome.remoteWorkCompleted)
        XCTAssertEqual(outcome.accounting, .pending)
        XCTAssertEqual(fx.capture.forceStopCount, 1)
        XCTAssertTrue(fx.backend.endCalls.isEmpty, "accounting is still waiting on auth, and is not claimed done")

        fx.backend.authHook = nil
        release?.resume()
        let accounted = await waitUntil { fx.backend.endCalls.count == 1 }
        XCTAssertTrue(accounted, "the pending accounting still completes in the background")
    }

    func testRepeatedStopsDoNotQueueBehindAnUnresolvedStop() async throws {
        let fx = LifecycleFixture()
        fx.service.endRemoteTimeout = 0.05
        var release: CheckedContinuation<Void, Never>?
        fx.backend.endSessionHook = { _ in await withCheckedContinuation { release = $0 } }
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        let first = fx.service.stopNow(.audioInterrupted)
        let hung = await waitUntil { release != nil }
        XCTAssertTrue(hung)

        let second = fx.service.stopNow(.userEnded)
        let secondCompleted = await completes(second, within: 1)
        XCTAssertTrue(secondCompleted, "a later stop must not wait for the earlier stop's remote work")
        let firstCompleted = await completes(first, within: 0.1)
        XCTAssertFalse(firstCompleted)

        release?.resume()
        let firstFinished = await completes(first, within: 2)
        XCTAssertTrue(firstFinished)
    }

    func testStartFailureAlsoResolvesWithoutWaitingOnRemoteAccounting() async throws {
        let fx = LifecycleFixture()
        fx.service.endRemoteTimeout = 0.05
        var release: CheckedContinuation<Void, Never>?
        fx.backend.endSessionHook = { _ in await withCheckedContinuation { release = $0 } }
        fx.capture.startError = VoiceError.audioSessionFailed("synthetic")

        let started = Date()
        do {
            try await fx.service.connect(bound: fx.binding, access: fx.access)
            XCTFail("expected the capture start to fail")
        } catch {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5, "a failed start is not held by suspended accounting")
        XCTAssertEqual(fx.service.lastStopReason, .failedToStart)
        release?.resume()
    }
}

// MARK: - Voice-context contract: strict nested claim

final class VoiceContextClaimTests: XCTestCase {

    private func parse(_ object: Any?) -> Result<VoiceContextClaim, VoiceSupportAccessError> {
        VoiceContextClaim.parse(object: object)
    }

    func testAWellFormedNestedClaimParsesAndMatchesItsBinding() throws {
        let binding = makeBinding(revision: 4)
        let claim = try XCTUnwrap(try? parse(claimObject(for: binding)).get())

        XCTAssertEqual(claim.version, 1)
        XCTAssertEqual(claim.supportSessionID, binding.supportSessionUUID)
        XCTAssertEqual(claim.conversationID, binding.conversationUUID)
        XCTAssertEqual(claim.scope, .personalized)
        XCTAssertEqual(claim.privacyRevision, 4)
        XCTAssertEqual(claim.packetSHA256, String(repeating: "ab", count: 32))
        XCTAssertEqual(claim.provider.vendor, "openai")
        XCTAssertEqual(claim.provider.routeVersion, "1")
        XCTAssertEqual(claim.privacyLeaseMS, 5_000)
        XCTAssertNoThrow(try claim.validate(against: binding))
    }

    func testAMissingOrNullNestedObjectIsALegacyRelay() {
        XCTAssertEqual(parse(nil), .failure(.contextRequired))
        XCTAssertEqual(parse(NSNull()), .failure(.contextRequired))
        XCTAssertEqual(VoiceContextClaim.parse(responseData: Data("{}".utf8)), .failure(.contextRequired))
        XCTAssertEqual(VoiceContextClaim.parse(responseData: Data("not json".utf8)), .failure(.contextRequired))
    }

    func testTopLevelEchoFieldsNeverAdmitALegacyRelay() {
        // An older Edge function ignores the new request fields; echoing them back proves nothing.
        let binding = makeBinding()
        let legacyBody: [String: Any] = [
            "session_id": UUID().uuidString, "transport": "relay", "max_duration_seconds": 120,
            "support_session_id": binding.supportSessionUUID.uuidString.lowercased(),
            "conversation_id": binding.conversationUUID.uuidString.lowercased(),
            "context_scope": binding.scope.rawValue,
            "privacy_revision": 4, "context_receipt_id": UUID().uuidString.lowercased(),
            "packet_sha256": String(repeating: "ab", count: 32), "packet_bytes": 100, "privacy_lease_ms": 5_000,
        ]
        let data = try! JSONSerialization.data(withJSONObject: legacyBody)
        XCTAssertEqual(VoiceContextClaim.parse(responseData: data), .failure(.contextRequired))
    }

    func testANonObjectOrUnversionedClaimIsInvalidAndAnotherVersionIsUnsupported() {
        let binding = makeBinding()
        XCTAssertEqual(parse("voice_context"), .failure(.contextInvalid))
        XCTAssertEqual(parse([Any]()), .failure(.contextInvalid))
        XCTAssertEqual(parse(claimObject(for: binding) { $0["version"] = "1" }), .failure(.contextInvalid))
        XCTAssertEqual(parse(claimObject(for: binding) { $0["version"] = 1.5 }), .failure(.contextInvalid))
        XCTAssertEqual(parse(claimObject(for: binding) { $0.removeValue(forKey: "version") }), .failure(.contextInvalid))
        XCTAssertEqual(parse(claimObject(for: binding) { $0["version"] = 2 }), .failure(.contextVersionUnsupported))
        XCTAssertEqual(parse(claimObject(for: binding) { $0["version"] = 0 }), .failure(.contextVersionUnsupported))
    }

    func testEveryRequiredFieldIsRequired() {
        let binding = makeBinding()
        for key in ["support_session_id", "conversation_id", "context_scope", "privacy_revision",
                    "context_receipt_id", "packet_sha256", "packet_bytes", "provider", "privacy_lease_ms"] {
            XCTAssertEqual(parse(claimObject(for: binding) { $0.removeValue(forKey: key) }), .failure(.contextInvalid), key)
        }
        for key in ["vendor", "model", "route_version"] {
            let result = parse(claimObject(for: binding) { object in
                var provider = object["provider"] as! [String: Any]
                provider.removeValue(forKey: key)
                object["provider"] = provider
            })
            XCTAssertEqual(result, .failure(.contextInvalid), "provider.\(key)")
        }
    }

    func testReceiptHashAndSizeMustBeValid() {
        let binding = makeBinding()
        let badValues: [(String, Any)] = [
            ("context_receipt_id", "not-a-uuid"),
            ("context_receipt_id", "00000000-0000-0000-0000-000000000000"),
            ("context_receipt_id", 42),
            ("packet_sha256", String(repeating: "ab", count: 31)),
            ("packet_sha256", String(repeating: "ab", count: 33)),
            ("packet_sha256", String(repeating: "zz", count: 32)),
            ("packet_sha256", 7),
            ("packet_bytes", 0),
            ("packet_bytes", -5),
            ("packet_bytes", 8_001),
            ("packet_bytes", "1234"),
            ("packet_bytes", 12.5),
            ("privacy_revision", -1),
            ("privacy_revision", 3.5),
            ("context_scope", "everything"),
            ("support_session_id", "nope"),
            ("conversation_id", ""),
        ]
        for (key, value) in badValues {
            XCTAssertEqual(parse(claimObject(for: binding) { $0[key] = value }), .failure(.contextInvalid), "\(key)=\(value)")
        }
    }

    func testBooleansAreNeverAcceptedAsIntegers() throws {
        let binding = makeBinding()
        var object = claimObject(for: binding)
        object["version"] = true
        let wire = try JSONSerialization.data(withJSONObject: ["voice_context": object])
        XCTAssertEqual(VoiceContextClaim.parse(responseData: wire), .failure(.contextInvalid))

        object = claimObject(for: binding)
        object["privacy_lease_ms"] = true
        let wire2 = try JSONSerialization.data(withJSONObject: ["voice_context": object])
        XCTAssertEqual(VoiceContextClaim.parse(responseData: wire2), .failure(.contextInvalid))
    }

    func testValidationRequiresAnExactMatchWithTheBinding() throws {
        let binding = makeBinding(revision: 4)
        func claim(_ mutate: (inout [String: Any]) -> Void) throws -> VoiceContextClaim {
            try XCTUnwrap(try? parse(claimObject(for: binding, mutate)).get())
        }
        assertVoiceThrows(try claim { $0["support_session_id"] = UUID().uuidString }.validate(against: binding)) {
            XCTAssertEqual($0 as? VoiceSupportAccessError, .sessionMismatch)
        }
        assertVoiceThrows(try claim { $0["conversation_id"] = UUID().uuidString }.validate(against: binding)) {
            XCTAssertEqual($0 as? VoiceSupportAccessError, .sessionMismatch)
        }
        assertVoiceThrows(try claim { $0["context_scope"] = "conversation_only" }.validate(against: binding)) {
            XCTAssertEqual($0 as? VoiceSupportAccessError, .scopeMismatch)
        }
        assertVoiceThrows(try claim { $0["privacy_revision"] = 5 }.validate(against: binding)) {
            XCTAssertEqual($0 as? VoiceSupportAccessError, .privacyRevisionChanged)
        }
        for lease in [0, 1_000, 4_999, 5_001, 60_000] {
            assertVoiceThrows(try claim { $0["privacy_lease_ms"] = lease }.validate(against: binding), "lease \(lease)") {
                XCTAssertEqual($0 as? VoiceSupportAccessError, .contextInvalid)
            }
        }
    }

    func testAnUnknownBindingRevisionAcceptsTheServersRevision() throws {
        let binding = makeBinding(revision: nil)
        let claim = try XCTUnwrap(try? parse(claimObject(for: binding) { $0["privacy_revision"] = 11 }).get())
        XCTAssertNoThrow(try claim.validate(against: binding))
        XCTAssertEqual(claim.privacyRevision, 11)
    }

    func testServerCodesMapToNarrowErrors() {
        let table: [(String, VoiceSupportAccessError)] = [
            ("INVALID_VOICE_CONTEXT", .contextInvalid),
            ("VOICE_CONTEXT_VERSION_UNSUPPORTED", .contextVersionUnsupported),
            ("VOICE_CONTEXT_UNAVAILABLE", .contextUnavailable),
            ("SESSION_CONVERSATION_MISMATCH", .sessionMismatch),
            ("SCOPE_MISMATCH", .scopeMismatch),
            ("VOICE_CONTEXT_REQUIRED", .contextRequired),
            ("VOICE_CONTEXT_CHANGED", .contextChanged),
            ("PRIVACY_LEASE_EXPIRED", .privacyLeaseExpired),
            ("PRIVACY_REVISION_CHANGED", .privacyRevisionChanged),
            ("PRIVACY_REVISION_STALE", .privacyRevisionChanged),
        ]
        for (code, expected) in table {
            XCTAssertEqual(VoiceSupportAccessError.fromServerCode(code), expected, code)
            XCTAssertNotNil(expected.errorDescription)
        }
        XCTAssertNil(VoiceSupportAccessError.fromServerCode("SOMETHING_ELSE"))
        XCTAssertNil(VoiceSupportAccessError.fromServerCode(nil))
        // Only a previously valid binding or lease going stale counts as an invalidation.
        XCTAssertTrue(VoiceSupportAccessError.privacyLeaseExpired.isContextInvalidation)
        XCTAssertTrue(VoiceSupportAccessError.contextChanged.isContextInvalidation)
        XCTAssertFalse(VoiceSupportAccessError.contextRequired.isContextInvalidation)
        XCTAssertFalse(VoiceSupportAccessError.contextUnavailable.isContextInvalidation)
    }
}

// MARK: - Actual wire (URLProtocol stub, no network)

/// Answers requests in-process and records exactly what would have been sent.
final class StubWireProtocol: URLProtocol {
    enum Answer {
        case response(status: Int, headers: [String: String], body: Data)
        case failure(Error)
        case redirect(to: URL)
    }

    struct Captured {
        let url: URL
        let method: String
        let headers: [String: String]
        let body: Data
    }

    nonisolated(unsafe) static var handler: ((URLRequest) -> Answer)?
    nonisolated(unsafe) static var captured: [Captured] = []

    static func reset() {
        handler = nil
        captured = []
    }

    private let stopLock = NSLock()
    private var loadingStopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {
        stopLock.lock()
        loadingStopped = true
        stopLock.unlock()
    }

    private var isStopped: Bool {
        stopLock.lock()
        defer { stopLock.unlock() }
        return loadingStopped
    }

    private func bodyData() -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.captured.append(Captured(
            url: url, method: request.httpMethod ?? "", headers: request.allHTTPHeaderFields ?? [:], body: bodyData()
        ))
        switch Self.handler?(request) ?? .response(status: 500, headers: [:], body: Data()) {
        case .response(let status, let headers, let body):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .redirect(let target):
            let response = HTTPURLResponse(url: url, statusCode: 307, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            // When the client declines a redirect the loading system is expected to stop this load. If
            // it has not by the deadline, end the load ourselves so the fixture always terminates and a
            // declined redirect is never mistaken for a hang.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [self] in
                if !isStopped { client?.urlProtocol(self, didFailWithError: URLError(.cancelled)) }
            }
        }
    }
}

@MainActor
private func admissionResponseBody(sessionID: UUID, binding: VoiceSupportBinding, includeVoiceContext: Bool = true) -> Data {
    var object: [String: Any] = [
        "token": "unused", "expires_at": "2026-01-01T00:00:00Z", "minutes_remaining": 3, "voice": "ara",
        "is_premium": true, "available_voices": ["ara"], "session_id": sessionID.uuidString,
        "transport": "relay", "max_duration_seconds": 120,
    ]
    if includeVoiceContext { object["voice_context"] = claimObject(for: binding) }
    return try! JSONSerialization.data(withJSONObject: object)
}

/// Auth comes from a fake (so "ambient account B" can be modelled); admission and session-end go
/// through the REAL raw fixed-host requests of `SupabaseVoiceRelayBackend`.
@MainActor
final class WireBackend: VoiceRelayBackend {
    var auth: VoiceAuthSnapshot
    let wire: SupabaseVoiceRelayBackend

    init(auth: VoiceAuthSnapshot, wire: SupabaseVoiceRelayBackend) {
        self.auth = auth
        self.wire = wire
    }

    func authSnapshot() async throws -> VoiceAuthSnapshot { auth }

    func admit(_ body: VoiceAdmissionRequestBody, authorization token: String) async throws -> VoiceAdmission {
        try await wire.admit(body, authorization: token)
    }

    func endSession(_ request: VoiceSessionEndRequest, authorization token: String) async -> VoiceAccountingResult {
        await wire.endSession(request, authorization: token)
    }

    func saveVoicePreference(_ voice: GrokVoice, expectedOwner: UUID?) async throws {}
}

@MainActor
final class VoiceRelayWireTests: XCTestCase {
    private let projectURL = URL(string: "https://proj-ref.supabase.co")!
    private let anonKey = "anon-key-123"

    private func makeWire() -> SupabaseVoiceRelayBackend {
        StubWireProtocol.reset()
        let client = SupabaseClient(supabaseURL: URL(string: "https://unused.example.supabase.co")!, supabaseKey: "unused")
        return SupabaseVoiceRelayBackend(
            supabase: client,
            session: SupabaseVoiceRelayBackend.makeSession(extraProtocolClasses: [StubWireProtocol.self]),
            projectURL: projectURL,
            anonKey: anonKey
        )
    }

    override func tearDown() { StubWireProtocol.reset() }

    func testAdmissionIsPostedToTheFixedHostWithExactlyTheSuppliedToken() async throws {
        let wire = makeWire()
        let binding = makeBinding(revision: 4)
        let sessionID = UUID()
        StubWireProtocol.handler = { _ in
            .response(status: 200, headers: [:], body: admissionResponseBody(sessionID: sessionID, binding: binding))
        }

        let admitted = try await wire.admit(VoiceAdmissionRequestBody(binding: binding), authorization: "token-OWNER-A")

        XCTAssertEqual(StubWireProtocol.captured.count, 1)
        let sent = try XCTUnwrap(StubWireProtocol.captured.first)
        XCTAssertEqual(sent.url.absoluteString, "https://proj-ref.supabase.co/functions/v1/test-auth-diagnostic")
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.headers["Authorization"], "Bearer token-OWNER-A")
        XCTAssertEqual(sent.headers["apikey"], anonKey)
        XCTAssertEqual(sent.headers["Content-Type"], "application/json")

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        XCTAssertEqual(Set(body.keys), [
            "transport", "schema_version", "expected_owner", "support_session_id",
            "conversation_id", "context_scope", "expected_privacy_revision",
        ])
        XCTAssertEqual(body["transport"] as? String, "relay")
        XCTAssertNil(body["instructions"], "the client never sends trusted instructions")

        XCTAssertEqual(admitted.token.sessionId, sessionID.uuidString)
        guard case .success(let claim) = admitted.voiceContext else { return XCTFail("nested claim expected") }
        XCTAssertEqual(claim.supportSessionID, binding.supportSessionUUID)
    }

    func testSessionEndCarriesTheCapturedTokenAndIsConfirmedOnlyByASuccessfulAnswer() async {
        let wire = makeWire()
        let request = VoiceSessionEndRequest(sessionId: UUID().uuidString, durationSeconds: 7, messagesCount: 2, wasQuotaLimited: false)

        StubWireProtocol.handler = { _ in .response(status: 200, headers: [:], body: Data("{}".utf8)) }
        let confirmed = await wire.endSession(request, authorization: "token-OWNER-A")
        XCTAssertEqual(confirmed, .confirmed)
        let sent = StubWireProtocol.captured.last
        XCTAssertEqual(sent?.url.absoluteString, "https://proj-ref.supabase.co/functions/v1/voice-session-end")
        XCTAssertEqual(sent?.headers["Authorization"], "Bearer token-OWNER-A")
        XCTAssertEqual(sent?.headers["apikey"], anonKey)
        let object = (try? JSONSerialization.jsonObject(with: sent?.body ?? Data())) as? [String: Any]
        XCTAssertEqual(object?["duration_seconds"] as? Int, 7)
        XCTAssertEqual(object?["messages_count"] as? Int, 2)
        XCTAssertEqual(object?["was_quota_limited"] as? Bool, false)

        // Anything else is unknown, never success.
        for answer: StubWireProtocol.Answer in [
            .response(status: 500, headers: [:], body: Data()),
            .response(status: 404, headers: [:], body: Data()),
            .response(status: 200, headers: ["x-relay-error": "true"], body: Data()),
            .failure(URLError(.timedOut)),
            .failure(URLError(.notConnectedToInternet)),
        ] {
            StubWireProtocol.handler = { _ in answer }
            let result = await wire.endSession(request, authorization: "token-OWNER-A")
            XCTAssertEqual(result, .unconfirmed)
        }
    }

    func testAnEmptyTokenIsRejectedBeforeAnyRequestIsMade() async {
        let wire = makeWire()
        do {
            _ = try await wire.admit(VoiceAdmissionRequestBody(binding: makeBinding()), authorization: "")
            XCTFail("an empty token must not be sent")
        } catch {
            XCTAssertNotNil(error as? VoiceError)
        }
        let result = await wire.endSession(
            VoiceSessionEndRequest(sessionId: UUID().uuidString, durationSeconds: 0, messagesCount: 0, wasQuotaLimited: false),
            authorization: ""
        )
        XCTAssertEqual(result, .unconfirmed)
        XCTAssertTrue(StubWireProtocol.captured.isEmpty)
    }

    func testARedirectIsRefusedSoTheTokenNeverLeavesTheConfiguredHost() async {
        let wire = makeWire()
        StubWireProtocol.handler = { _ in .redirect(to: URL(string: "https://attacker.example/steal")!) }

        do {
            _ = try await wire.admit(VoiceAdmissionRequestBody(binding: makeBinding()), authorization: "token-OWNER-A")
            XCTFail("a redirect must not produce an admission")
        } catch {}
        let result = await wire.endSession(
            VoiceSessionEndRequest(sessionId: UUID().uuidString, durationSeconds: 0, messagesCount: 0, wasQuotaLimited: false),
            authorization: "token-OWNER-A"
        )

        XCTAssertEqual(result, .unconfirmed)
        XCTAssertFalse(StubWireProtocol.captured.isEmpty)
        XCTAssertTrue(StubWireProtocol.captured.allSatisfy { $0.url.host == "proj-ref.supabase.co" },
                      "no request may reach another host")
    }

    func testTheNoRedirectDelegateDeclinesEveryRedirectDirectly() {
        let session = SupabaseVoiceRelayBackend.makeSession()
        XCTAssertTrue(session.delegate is VoiceNoRedirectDelegate, "the production session refuses redirects")

        let delegate = VoiceNoRedirectDelegate()
        let task = session.dataTask(with: URL(string: "https://proj-ref.supabase.co/functions/v1/x")!)
        let response = HTTPURLResponse(url: task.originalRequest!.url!, statusCode: 307, httpVersion: "HTTP/1.1",
                                       headerFields: ["Location": "https://attacker.example/steal"])!
        var answered = false
        var followed: URLRequest?
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                            newRequest: URLRequest(url: URL(string: "https://attacker.example/steal")!)) {
            answered = true
            followed = $0
        }
        XCTAssertTrue(answered)
        XCTAssertNil(followed, "a nil answer means the redirect is not followed and no token is forwarded")
        task.cancel()
    }

    func testHttpErrorCodesMapToNarrowErrors() async {
        let wire = makeWire()
        let table: [(String, Int, VoiceSupportAccessError)] = [
            ("INVALID_VOICE_CONTEXT", 400, .contextInvalid),
            ("VOICE_CONTEXT_VERSION_UNSUPPORTED", 400, .contextVersionUnsupported),
            ("VOICE_CONTEXT_UNAVAILABLE", 503, .contextUnavailable),
            ("SESSION_CONVERSATION_MISMATCH", 409, .sessionMismatch),
            ("SCOPE_MISMATCH", 409, .scopeMismatch),
            ("VOICE_CONTEXT_REQUIRED", 426, .contextRequired),
            ("VOICE_CONTEXT_CHANGED", 409, .contextChanged),
            ("PRIVACY_LEASE_EXPIRED", 409, .privacyLeaseExpired),
            ("PRIVACY_REVISION_STALE", 409, .privacyRevisionChanged),
        ]
        for (code, status, expected) in table {
            let body = Data("{\"code\":\"\(code)\"}".utf8)
            StubWireProtocol.handler = { _ in .response(status: status, headers: [:], body: body) }
            do {
                _ = try await wire.admit(VoiceAdmissionRequestBody(binding: makeBinding()), authorization: "t")
                XCTFail("expected \(code)")
            } catch {
                XCTAssertEqual(error as? VoiceSupportAccessError, expected, code)
            }
        }
        // Unchanged narrow mappings.
        StubWireProtocol.handler = { _ in .response(status: 403, headers: [:], body: Data()) }
        do { _ = try await wire.admit(VoiceAdmissionRequestBody(binding: makeBinding()), authorization: "t") } catch {
            guard let voiceError = error as? VoiceError, case .quotaExceeded = voiceError else { return XCTFail("403 stays a quota error") }
        }
    }

    func testALegacyRelayAnswerWithOnlyTopLevelEchoYieldsNoUsableContext() async throws {
        let wire = makeWire()
        let binding = makeBinding()
        let sessionID = UUID()
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(
            with: admissionResponseBody(sessionID: sessionID, binding: binding, includeVoiceContext: false)) as? [String: Any])
        legacy["support_session_id"] = binding.supportSessionUUID.uuidString.lowercased()
        legacy["conversation_id"] = binding.conversationUUID.uuidString.lowercased()
        legacy["privacy_revision"] = 4
        let body = try JSONSerialization.data(withJSONObject: legacy)
        StubWireProtocol.handler = { _ in .response(status: 200, headers: [:], body: body) }

        let admitted = try await wire.admit(VoiceAdmissionRequestBody(binding: binding), authorization: "token-A")

        guard case .failure(let reason) = admitted.voiceContext else { return XCTFail("a legacy answer must not admit") }
        XCTAssertEqual(reason, .contextRequired)
    }

    func testFunctionURLIsHttpsFixedHostOnly() throws {
        let url = try SupabaseVoiceRelayBackend.functionURL("voice-session-end", projectURL: projectURL)
        XCTAssertEqual(url.absoluteString, "https://proj-ref.supabase.co/functions/v1/voice-session-end")
        assertVoiceThrows(try SupabaseVoiceRelayBackend.functionURL("x", projectURL: URL(string: "http://proj-ref.supabase.co")!))
        assertVoiceThrows(try SupabaseVoiceRelayBackend.functionURL("x", projectURL: URL(string: "file:///tmp")!))
    }

    // MARK: Captured owner A while the ambient account is B (real raw wire, through the service)

    func testSessionEndUsesTheCapturedOwnerATokenWhileTheAmbientAccountIsB() async throws {
        let wire = makeWire()
        let log = VoiceTestLog()
        let owner = UUID()
        let binding = makeBinding(owner: owner)
        let access = FakeSupportAccess(binding: binding)
        let transport = FakeVoiceTransport(log: log)
        let capture = FakeVoiceCapture(log: log)
        let backend = WireBackend(auth: VoiceAuthSnapshot(userID: owner, accessToken: "token-OWNER-A"), wire: wire)
        let service = GrokVoiceService(
            backend: backend, transport: transport, capture: capture, playback: FakeVoicePlayback(log: log),
            microphonePermission: {}
        )
        let sessionID = UUID()
        StubWireProtocol.handler = { request in
            if request.url?.lastPathComponent == "test-auth-diagnostic" {
                return .response(status: 200, headers: [:], body: admissionResponseBody(sessionID: sessionID, binding: binding))
            }
            return .response(status: 200, headers: [:], body: Data("{}".utf8))
        }

        try await service.connect(bound: binding, access: access)
        XCTAssertEqual(StubWireProtocol.captured.first?.headers["Authorization"], "Bearer token-OWNER-A")
        XCTAssertEqual(transport.connectCalls.map(\.token), ["token-OWNER-A"])

        // The ambient account switches to B before the session ends.
        backend.auth = VoiceAuthSnapshot(userID: UUID(), accessToken: "token-ACCOUNT-B")
        let outcome = await service.end(reason: .userEnded)

        let ends = StubWireProtocol.captured.filter { $0.url.lastPathComponent == "voice-session-end" }
        XCTAssertEqual(ends.count, 1)
        XCTAssertEqual(ends.first?.headers["Authorization"], "Bearer token-OWNER-A", "never account B's token")
        XCTAssertFalse(StubWireProtocol.captured.contains { $0.headers["Authorization"]?.contains("ACCOUNT-B") == true })
        XCTAssertEqual(outcome.accounting, .confirmed)
    }

    func testALegacyRelayWithoutTheNestedContextOpensNoSocketAndNoMicrophone() async {
        let wire = makeWire()
        let log = VoiceTestLog()
        let owner = UUID()
        let binding = makeBinding(owner: owner)
        let access = FakeSupportAccess(binding: binding)
        let transport = FakeVoiceTransport(log: log)
        let capture = FakeVoiceCapture(log: log)
        let backend = WireBackend(auth: VoiceAuthSnapshot(userID: owner, accessToken: "token-OWNER-A"), wire: wire)
        let service = GrokVoiceService(
            backend: backend, transport: transport, capture: capture, playback: FakeVoicePlayback(log: log),
            microphonePermission: {}
        )
        let sessionID = UUID()
        StubWireProtocol.handler = { request in
            if request.url?.lastPathComponent == "test-auth-diagnostic" {
                return .response(status: 200, headers: [:],
                                 body: admissionResponseBody(sessionID: sessionID, binding: binding, includeVoiceContext: false))
            }
            return .response(status: 200, headers: [:], body: Data("{}".utf8))
        }

        do {
            try await service.connect(bound: binding, access: access)
            XCTFail("a legacy relay must not be used")
        } catch {
            XCTAssertEqual(error as? VoiceSupportAccessError, .contextRequired)
        }

        XCTAssertTrue(transport.connectCalls.isEmpty, "zero sockets")
        XCTAssertEqual(capture.startCount, 0, "zero capture")
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertEqual(service.lastStopReason, .failedToStart)
        guard case .error(let message) = service.connectionState else { return XCTFail("a truthful failed state is expected") }
        XCTAssertEqual(message, VoiceSupportAccessError.contextRequired.errorDescription)
        // The admitted session is still accounted for with the captured owner token.
        let ends = StubWireProtocol.captured.filter { $0.url.lastPathComponent == "voice-session-end" }
        XCTAssertEqual(ends.count, 1)
        XCTAssertEqual(ends.first?.headers["Authorization"], "Bearer token-OWNER-A")
    }
}

// MARK: - Socket URL builder

@MainActor
final class VoiceSocketRequestTests: XCTestCase {
    private let projectURL = URL(string: "https://proj-ref.supabase.co")!

    func testTheBoundSocketUrlClaimsVoiceContextOneOnTheFixedHost() throws {
        let sessionID = UUID()
        let request = try VoiceWebSocketManager.relayRequest(
            sessionId: sessionID.uuidString, userToken: "token-OWNER-A", projectURL: projectURL, anonKey: "anon-key-123"
        )
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "wss")
        XCTAssertEqual(components.host, "proj-ref.supabase.co")
        XCTAssertEqual(components.path, "/functions/v1/test-auth-diagnostic")
        XCTAssertEqual(components.queryItems?.map(\.name), ["session_id", "voice_context"])
        XCTAssertEqual(components.queryItems?.first { $0.name == "voice_context" }?.value, "1")
        XCTAssertEqual(components.queryItems?.first { $0.name == "session_id" }?.value, sessionID.uuidString)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-OWNER-A")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key-123")
    }

    func testTheDefaultBuilderAlwaysClaimsTheContractAndOptingOutIsExplicit() throws {
        let sessionID = UUID().uuidString
        let defaulted = try VoiceWebSocketManager.relayRequest(sessionId: sessionID, userToken: "t")
        XCTAssertTrue(defaulted.url?.query?.contains("voice_context=1") == true)

        let optedOut = try VoiceWebSocketManager.relayRequest(
            sessionId: sessionID, userToken: "t", requiresVoiceContext: false, projectURL: projectURL, anonKey: "k"
        )
        XCTAssertEqual(optedOut.url?.query, "session_id=\(sessionID)")
    }

    func testInvalidInputsNeverProduceASocketRequest() {
        let valid = UUID().uuidString
        assertVoiceThrows(try VoiceWebSocketManager.relayRequest(sessionId: "not-a-uuid", userToken: "t", projectURL: projectURL, anonKey: "k"))
        assertVoiceThrows(try VoiceWebSocketManager.relayRequest(sessionId: valid, userToken: "", projectURL: projectURL, anonKey: "k"))
        assertVoiceThrows(try VoiceWebSocketManager.relayRequest(
            sessionId: valid, userToken: "t", projectURL: URL(string: "http://proj-ref.supabase.co")!, anonKey: "k"))
    }
}

// MARK: - Fail closed before socket and audio

@MainActor
final class VoiceContextContractServiceTests: XCTestCase {

    private func assertRefused(
        _ expected: VoiceSupportAccessError, stopReason: VoiceStopReason,
        file: StaticString = #filePath, line: UInt = #line,
        make: (LifecycleFixture) -> VoiceAdmission
    ) async {
        let fx = LifecycleFixture()
        fx.backend.admission = make(fx)
        do {
            try await fx.service.connect(bound: fx.binding, access: fx.access)
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? VoiceSupportAccessError, expected, file: file, line: line)
        }
        XCTAssertTrue(fx.transport.connectCalls.isEmpty, "zero sockets", file: file, line: line)
        XCTAssertTrue(fx.transport.sent.isEmpty, file: file, line: line)
        XCTAssertEqual(fx.capture.startCount, 0, "zero capture", file: file, line: line)
        XCTAssertEqual(fx.backend.endCalls.count, 1, "the admitted session is still accounted for", file: file, line: line)
        XCTAssertEqual(fx.service.lastStopReason, stopReason, file: file, line: line)
        XCTAssertNil(fx.service.admittedContext, file: file, line: line)
    }

    private func mutated(_ mutate: @escaping (inout [String: Any]) -> Void) -> (LifecycleFixture) -> VoiceAdmission {
        { fx in admission(for: fx.binding, sessionID: fx.sessionID, mutate) }
    }

    func testAMissingNestedContextIsRefusedAsALegacyRelay() async {
        await assertRefused(.contextRequired, stopReason: .failedToStart) { fx in
            // A legacy answer: valid token response, no nested voice_context at all.
            VoiceAdmission(token: tokenResponse(sessionId: fx.sessionID),
                           voiceContext: VoiceContextClaim.parse(responseData: Data("{}".utf8)))
        }
    }

    func testEveryContractViolationFailsClosedBeforeTheSocketOrMicrophone() async {
        await assertRefused(.contextVersionUnsupported, stopReason: .failedToStart, make: mutated { $0["version"] = 2 })
        await assertRefused(.contextInvalid, stopReason: .failedToStart, make: mutated { $0["context_receipt_id"] = "not-a-receipt" })
        await assertRefused(.contextInvalid, stopReason: .failedToStart, make: mutated { $0["packet_sha256"] = "deadbeef" })
        await assertRefused(.contextInvalid, stopReason: .failedToStart, make: mutated { $0["packet_bytes"] = 0 })
        await assertRefused(.contextInvalid, stopReason: .failedToStart, make: mutated { $0["privacy_lease_ms"] = 4_000 })
        await assertRefused(.sessionMismatch, stopReason: .failedToStart, make: mutated { $0["support_session_id"] = UUID().uuidString })
        await assertRefused(.sessionMismatch, stopReason: .failedToStart, make: mutated { $0["conversation_id"] = UUID().uuidString })
        await assertRefused(.scopeMismatch, stopReason: .failedToStart, make: mutated { $0["context_scope"] = "conversation_only" })
        await assertRefused(.privacyRevisionChanged, stopReason: .contextInvalidated, make: mutated { $0["privacy_revision"] = 9 })
    }

    func testHttpLevelContextErrorsAlsoFailClosedWithATruthfulMessage() async {
        let fx = LifecycleFixture()
        fx.backend.admitError = VoiceSupportAccessError.contextUnavailable
        do {
            try await fx.service.connect(bound: fx.binding, access: fx.access)
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? VoiceSupportAccessError, .contextUnavailable)
        }
        XCTAssertTrue(fx.transport.connectCalls.isEmpty)
        XCTAssertEqual(fx.capture.startCount, 0)
        guard case .error(let message) = fx.service.connectionState else { return XCTFail("a failed state is expected") }
        XCTAssertEqual(message, VoiceSupportAccessError.contextUnavailable.errorDescription)
        XCTAssertFalse(message.isEmpty)
    }

    func testAValidNestedContextAdmitsAndExposesOnlyIdentifiersAndHashes() async throws {
        let fx = LifecycleFixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access)

        let context = try XCTUnwrap(fx.service.admittedContext)
        XCTAssertEqual(context.supportSessionID, fx.binding.supportSessionUUID)
        XCTAssertEqual(context.privacyLeaseMS, 5_000)
        XCTAssertEqual(fx.service.connectionState, .connected)
        XCTAssertEqual(fx.capture.startCount, 1)

        await fx.service.end(reason: .userEnded)
        XCTAssertNil(fx.service.admittedContext)
    }

    func testPrivacyTerminalFramesStopTheSessionAndNeverResume() async throws {
        let cases: [(code: String, nested: Bool, reason: VoiceStopReason)] = [
            ("PRIVACY_REVISION_CHANGED", true, .contextInvalidated),
            ("PRIVACY_LEASE_EXPIRED", true, .privacyLeaseExpired),
            ("PRIVACY_LEASE_EXPIRED", false, .privacyLeaseExpired),
            ("VOICE_CONTEXT_CHANGED", true, .contextInvalidated),
            ("VOICE_CONTEXT_REQUIRED", false, .contextInvalidated),
        ]
        for testCase in cases {
            let fx = LifecycleFixture()
            try await fx.service.connect(bound: fx.binding, access: fx.access)
            XCTAssertTrue(fx.service.isListening)

            let frame: [String: Any] = testCase.nested
                ? ["type": "error", "error": ["code": testCase.code]]
                : ["type": "error", "code": testCase.code]
            fx.transport.deliver(frame)

            XCTAssertEqual(fx.service.lastStopReason, testCase.reason, testCase.code)
            XCTAssertFalse(fx.service.isListening, testCase.code)
            XCTAssertGreaterThanOrEqual(fx.capture.forceStopCount, 1, testCase.code)
            XCTAssertEqual(fx.transport.disconnectCount, 1, testCase.code)
            XCTAssertNotNil(testCase.reason.statusMessage)
            // No automatic restart, even though the transport could be asked again.
            try await Task.sleep(nanoseconds: 30_000_000)
            XCTAssertEqual(fx.capture.startCount, 1, testCase.code)
            await fx.service.end(reason: .userEnded)
        }
    }

    func testAnUnrelatedServerErrorIsStillAGenericServerStop() async throws {
        let fx = LifecycleFixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        fx.transport.deliver(["type": "error", "error": ["code": "SOMETHING_ELSE", "message": "provider detail that must never be shown"]])
        XCTAssertEqual(fx.service.lastStopReason, .serverError)
        XCTAssertFalse(VoiceStopReason.serverError.statusMessage?.contains("provider detail") ?? false)
        await fx.service.end(reason: .userEnded)
    }
}

// MARK: - Accounting is unknown unless the server confirms it

@MainActor
final class VoiceAccountingHonestyTests: XCTestCase {

    func testConfirmedOnlyWhenTheSessionEndCallSucceeds() async throws {
        let fx = LifecycleFixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        let outcome = await fx.service.end(reason: .userEnded)
        XCTAssertEqual(outcome.accounting, .confirmed)
        XCTAssertTrue(outcome.remoteWorkCompleted)
    }

    func testAFailedSessionEndIsUnconfirmedAndNeverRefundsMinutes() async throws {
        let fx = LifecycleFixture()
        fx.backend.admission = admission(for: fx.binding, sessionID: fx.sessionID, premium: false)
        fx.backend.endSessionResult = .unconfirmed
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        XCTAssertEqual(fx.service.minutesRemaining, 3, accuracy: 0.0001)

        let outcome = await fx.service.end(reason: .userEnded)

        XCTAssertEqual(outcome.accounting, .unconfirmed, "a failed call is not reported as accounted")
        XCTAssertTrue(outcome.remoteWorkCompleted, "the task ended; that is not the same as success")
        let afterEnd = fx.service.minutesRemaining
        XCTAssertLessThanOrEqual(afterEnd, 3, "minutes are never added back")
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(fx.service.minutesRemaining, afterEnd, "a missing confirmation changes nothing locally")
    }

    func testAnUnansweredSessionEndStaysPendingNotSuccessful() async throws {
        let fx = LifecycleFixture()
        fx.service.endRemoteTimeout = 0.05
        var release: CheckedContinuation<Void, Never>?
        fx.backend.endSessionHook = { _ in await withCheckedContinuation { release = $0 } }
        try await fx.service.connect(bound: fx.binding, access: fx.access)

        let outcome = await fx.service.end(reason: .switchedToText)

        XCTAssertEqual(outcome.accounting, .pending)
        XCTAssertFalse(outcome.remoteWorkCompleted)
        release?.resume()
    }

    func testNothingToAccountForWhenNoSessionWasAdmitted() async {
        let fx = LifecycleFixture()
        let outcome = await fx.service.end(reason: .userEnded)
        XCTAssertEqual(outcome.accounting, .notApplicable)
        XCTAssertTrue(fx.backend.endCalls.isEmpty)
    }

    func testARefusedAdmissionStillReportsItsAccountingHonestly() async {
        let fx = LifecycleFixture()
        fx.backend.endSessionResult = .unconfirmed
        fx.backend.admission = admission(for: fx.binding, sessionID: fx.sessionID) { $0["version"] = 2 }
        do {
            try await fx.service.connect(bound: fx.binding, access: fx.access)
            XCTFail("expected a refusal")
        } catch {}
        XCTAssertEqual(fx.backend.endCalls.count, 1)
    }
}

// MARK: - MF-VS-004-R4: every output item's own terminal status is inspected

@MainActor
final class VoiceStatuslessOutputItemTests: XCTestCase {

    private func outputItem(_ id: String, status: String?, text: String?) -> [String: Any] {
        var item: [String: Any] = ["id": id]
        if let status { item["status"] = status }
        if let text { item["content"] = [["transcript": text]] }
        return item
    }

    private func done(_ assembler: inout VoiceTranscriptAssembler, id: String = "r1", status: String? = nil, output: [[String: Any]]) -> [VoiceTranscriptEvent] {
        var response: [String: Any] = ["id": id, "output": output]
        if let status { response["status"] = status }
        return ingest(&assembler, "response.done", ["response": response])
    }

    func testTheReviewedFixtureAnExplicitlyIncompleteOutputItemNeverBecomesFinalText() {
        var assembler = deterministicAssembler(binding: makeBinding())
        // Exactly the reproduced input: no response-level status, one completed and one incomplete item.
        let events = done(&assembler, id: "r2", output: [
            outputItem("a1", status: "completed", text: "Complete. "),
            outputItem("a2", status: "incomplete", text: "unfinished fragm"),
        ])

        XCTAssertEqual(events.map(\.finality), [.abandoned])
        XCTAssertEqual(events.first?.abandonReason, .responseIncomplete)
        XCTAssertEqual(events.first?.text, "")
        XCTAssertFalse(events.contains { $0.text.contains("unfinished") || $0.text.contains("Complete.") })
    }

    func testAResponseReportedCompletedIsStillRefusedWhenOneOfItsItemsIsNot() {
        var assembler = deterministicAssembler(binding: makeBinding())
        let events = done(&assembler, status: "completed", output: [
            outputItem("a1", status: "completed", text: "Complete. "),
            outputItem("a2", status: "incomplete", text: "unfinished fragm"),
        ])
        XCTAssertEqual(events.map(\.finality), [.abandoned])
        XCTAssertEqual(events.first?.abandonReason, .responseIncomplete)
    }

    func testEachExplicitNonCompletedItemStatusMapsToItsOwnReasonAndNeverPromotes() {
        let cases: [(status: String, reason: VoiceTranscriptAbandonReason)] = [
            ("incomplete", .responseIncomplete), ("in_progress", .responseIncomplete),
            ("cancelled", .responseCancelled), ("canceled", .responseCancelled), ("failed", .responseFailed),
        ]
        for testCase in cases {
            var assembler = deterministicAssembler(binding: makeBinding())
            let events = done(&assembler, output: [
                outputItem("a1", status: "completed", text: "Complete. "),
                outputItem("a2", status: testCase.status, text: "tail"),
            ])
            XCTAssertEqual(events.map(\.finality), [.abandoned], testCase.status)
            XCTAssertEqual(events.first?.abandonReason, testCase.reason, testCase.status)
        }
        // Failed outranks cancelled outranks incomplete when several items disagree.
        var assembler = deterministicAssembler(binding: makeBinding())
        let mixed = done(&assembler, output: [
            outputItem("a1", status: "incomplete", text: "x"), outputItem("a2", status: "failed", text: "y"),
        ])
        XCTAssertEqual(mixed.first?.abandonReason, .responseFailed)
    }

    func testAnUnfinishedItemWithoutAnyTextStillBlocksTheOthers() {
        var assembler = deterministicAssembler(binding: makeBinding())
        let events = done(&assembler, output: [
            outputItem("a1", status: "completed", text: "Complete. "),
            outputItem("a2", status: "incomplete", text: nil),
        ])
        XCTAssertEqual(events.map(\.finality), [.abandoned])
    }

    func testPresenceInTheOutputListIsNotFinality() {
        var assembler = deterministicAssembler(binding: makeBinding())
        // No response status, no item status, and no streamed provider-final transcript.
        let events = done(&assembler, output: [outputItem("a1", status: nil, text: "Looks done but nothing says so")])
        XCTAssertEqual(events.map(\.finality), [.abandoned])
        XCTAssertEqual(events.first?.abandonReason, .responseIncomplete)
    }

    func testItemsWithoutStatusAreAcceptedWhenEachHasProviderFinalEvidenceAndKeepProviderOrder() {
        var assembler = deterministicAssembler(binding: makeBinding())
        var earlier: [VoiceTranscriptEvent] = []
        earlier += ingest(&assembler, "response.created", ["response": ["id": "r1"]])
        // The second item settles first on the wire; the provider's output list is the order of record.
        earlier += ingest(&assembler, "response.output_audio_transcript.delta",
                          ["response_id": "r1", "item_id": "a2", "delta": "Second"])
        earlier += ingest(&assembler, "response.output_audio_transcript.done",
                          ["response_id": "r1", "item_id": "a2", "transcript": "Second."])
        earlier += ingest(&assembler, "response.output_audio_transcript.done",
                          ["response_id": "r1", "item_id": "a1", "transcript": "First. "])

        let events = done(&assembler, output: [
            outputItem("a1", status: nil, text: "First. "), outputItem("a2", status: nil, text: "Second."),
        ])

        XCTAssertEqual(events.map(\.finality), [.final])
        XCTAssertEqual(events.first?.text, "First. Second.", "provider output order, not arrival order")
        XCTAssertEqual(events.first?.localUUID, earlier.first { $0.finality == .partial }?.localUUID,
                       "the final keeps the stable identity of the partials that preceded it")
    }

    func testOnlyOneItemWithEvidenceIsNotEnoughForTheWholeStatuslessList() {
        var assembler = deterministicAssembler(binding: makeBinding())
        _ = ingest(&assembler, "response.created", ["response": ["id": "r1"]])
        _ = ingest(&assembler, "response.output_audio_transcript.done",
                   ["response_id": "r1", "item_id": "a1", "transcript": "First. "])
        let events = done(&assembler, output: [
            outputItem("a1", status: nil, text: "First. "), outputItem("a2", status: nil, text: "No evidence"),
        ])
        XCTAssertEqual(events.map(\.finality), [.abandoned])
    }

    func testExplicitlyCompletedItemsFormOneStableFinalAndAReplayIsIgnored() {
        var assembler = deterministicAssembler(binding: makeBinding())
        let output = [outputItem("a1", status: "completed", text: "First. "), outputItem("a2", status: "completed", text: "Second.")]
        let first = done(&assembler, output: output)
        let replay = done(&assembler, output: output)

        XCTAssertEqual(first.map(\.finality), [.final])
        XCTAssertEqual(first.first?.text, "First. Second.")
        XCTAssertEqual(first.first?.providerItemID, "a1")
        XCTAssertTrue(replay.isEmpty, "a replayed response.done never produces a second event")
    }

    func testTheAbandonedTurnKeepsTheIdentityOfItsEarlierPartialsAndIsNotReplayedAsFinal() {
        var assembler = deterministicAssembler(binding: makeBinding())
        var partials: [VoiceTranscriptEvent] = []
        partials += ingest(&assembler, "response.created", ["response": ["id": "r1"]])
        partials += ingest(&assembler, "response.output_audio_transcript.delta",
                           ["response_id": "r1", "item_id": "a2", "delta": "unfinished fragm"])

        let events = done(&assembler, output: [
            outputItem("a1", status: "completed", text: "Complete. "), outputItem("a2", status: "incomplete", text: "unfinished fragm"),
        ])
        let later = done(&assembler, output: [outputItem("a1", status: "completed", text: "Complete. ")])

        XCTAssertEqual(events.first?.finality, .abandoned)
        XCTAssertEqual(events.first?.localUUID, partials.first { $0.finality == .partial }?.localUUID)
        XCTAssertTrue(later.isEmpty, "the turn is closed: a later done cannot revive it as final")
    }
}

// MARK: - MF-VS-006: an obsolete admission is accounted for promptly, boundedly, and honestly

@MainActor
final class VoiceObsoleteAdmissionTests: XCTestCase {

    func testAStaleBindingAtAdmissionReturnRefusesPromptlyDespiteSuspendedAccounting() async throws {
        let fx = LifecycleFixture()
        fx.service.endRemoteTimeout = 0.05
        var release: CheckedContinuation<Void, Never>?
        fx.backend.endSessionHook = { _ in await withCheckedContinuation { release = $0 } }
        fx.backend.onAdmit = { [unowned fx] in
            fx.access.isBindingCurrent = false
            fx.backend.auth = VoiceAuthSnapshot(userID: UUID(), accessToken: "token-ACCOUNT-B")
        }

        let started = Date()
        do {
            try await fx.service.connect(bound: fx.binding, access: fx.access)
            XCTFail("a stale binding must refuse")
        } catch {
            XCTAssertEqual(error as? VoiceSupportAccessError, .bindingNotCurrent)
        }

        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5, "the refusal is not held by suspended accounting")
        XCTAssertNotEqual(fx.service.connectionState, .connecting)
        XCTAssertTrue(fx.transport.connectCalls.isEmpty)
        XCTAssertEqual(fx.capture.startCount, 0)
        XCTAssertEqual(fx.backend.endCalls.count, 1)
        XCTAssertEqual(fx.backend.endCalls.first?.token, "token-A", "accounted for with the captured owner token, never account B's")
        XCTAssertEqual(fx.service.lastStopReason, .contextInvalidated)

        // A deliberate restart is available at once, and is independent of the earlier accounting.
        fx.backend.endSessionHook = nil
        fx.backend.onAdmit = nil
        fx.access.isBindingCurrent = true
        fx.backend.auth = VoiceAuthSnapshot(userID: fx.owner, accessToken: "token-A")
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        XCTAssertEqual(fx.service.connectionState, .connected)
        XCTAssertEqual(fx.backend.admitCalls.count, 2)
        release?.resume()
        await fx.service.end(reason: .userEnded)
    }

    func testAStaleBindingRefusesPromptlyEvenWhenTheAuthRefreshForAccountingIsSuspended() async throws {
        let fx = LifecycleFixture()
        fx.service.endRemoteTimeout = 0.05
        var release: CheckedContinuation<Void, Never>?
        fx.backend.onAdmit = { [unowned fx] in
            fx.access.isBindingCurrent = false
            // From here every auth call (the one accounting makes to refresh its token) is suspended.
            fx.backend.authHook = { await withCheckedContinuation { release = $0 } }
        }

        let started = Date()
        do {
            try await fx.service.connect(bound: fx.binding, access: fx.access)
            XCTFail("a stale binding must refuse")
        } catch {
            XCTAssertEqual(error as? VoiceSupportAccessError, .bindingNotCurrent)
        }

        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5, "suspended auth does not hold the refusal")
        XCTAssertTrue(fx.backend.endCalls.isEmpty, "accounting is waiting on auth and is not claimed done")
        XCTAssertTrue(fx.transport.connectCalls.isEmpty)
        XCTAssertEqual(fx.capture.startCount, 0)

        fx.backend.authHook = nil
        release?.resume()
        let accounted = await waitUntil { fx.backend.endCalls.count == 1 }
        XCTAssertTrue(accounted, "the pending accounting still completes in the background")
        XCTAssertEqual(fx.backend.endCalls.first?.token, "token-A")
    }

    func testASupersededAttemptAccountsSeparatelyAndNeverTouchesALaterAttempt() async throws {
        let fx = LifecycleFixture()
        fx.service.endRemoteTimeout = 0.05
        var release: CheckedContinuation<Void, Never>?
        fx.backend.endSessionHook = { _ in await withCheckedContinuation { release = $0 } }
        // The person ends (or the app backgrounds) while the admission is still in flight.
        fx.backend.onAdmit = { [unowned fx] in fx.service.stopNow(.userEnded) }

        let started = Date()
        do {
            try await fx.service.connect(bound: fx.binding, access: fx.access)
            XCTFail("a superseded attempt must not continue")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
        XCTAssertEqual(fx.service.obsoleteAdmissionAccounting, .pending, "unknown until the server answers; never claimed")
        XCTAssertEqual(fx.backend.endCalls.count, 1)
        XCTAssertEqual(fx.backend.endCalls.first?.token, "token-A")
        XCTAssertTrue(fx.transport.connectCalls.isEmpty)
        XCTAssertEqual(fx.capture.startCount, 0)

        // A later explicit start is not blocked, and the old accounting finishing later does not touch it.
        fx.backend.endSessionHook = nil
        fx.backend.onAdmit = nil
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        XCTAssertEqual(fx.service.connectionState, .connected)
        XCTAssertNotNil(fx.service.admittedContext)
        release?.resume()
        let settled = await waitUntil { fx.service.obsoleteAdmissionAccounting == .confirmed }
        XCTAssertTrue(settled)
        XCTAssertEqual(fx.service.connectionState, .connected, "the older accounting never alters the newer session")
        XCTAssertTrue(fx.service.isListening)
        XCTAssertNotNil(fx.service.admittedContext)
        await fx.service.end(reason: .userEnded)
    }

    func testAnUnconfirmedObsoleteAccountingIsNeverReportedAsSuccessAndRefundsNothing() async throws {
        let fx = LifecycleFixture()
        fx.service.endRemoteTimeout = 0.5
        fx.backend.endSessionResult = .unconfirmed
        fx.backend.admission = admission(for: fx.binding, sessionID: fx.sessionID, premium: false)
        fx.backend.onAdmit = { [unowned fx] in fx.service.stopNow(.userEnded) }
        let minutesBefore = fx.service.minutesRemaining

        do { try await fx.service.connect(bound: fx.binding, access: fx.access) } catch {}

        let settled = await waitUntil { fx.service.obsoleteAdmissionAccounting != .pending }
        XCTAssertTrue(settled)
        XCTAssertEqual(fx.service.obsoleteAdmissionAccounting, .unconfirmed)
        XCTAssertEqual(fx.service.minutesRemaining, minutesBefore, "nothing is refunded on an unconfirmed answer")
    }

    func testACancelledStartAccountsThroughTheBoundedStopAndReleasesTheScreen() async throws {
        let fx = LifecycleFixture()
        fx.service.endRemoteTimeout = 0.05
        var release: CheckedContinuation<Void, Never>?
        fx.backend.endSessionHook = { _ in await withCheckedContinuation { release = $0 } }
        var starting: Task<Void, Error>!
        fx.backend.onAdmit = { starting.cancel() }
        starting = Task { @MainActor in
            try await fx.service.connect(bound: fx.binding, access: fx.access)
        }

        let started = Date()
        do {
            try await starting.value
            XCTFail("a cancelled start must not continue")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
        XCTAssertEqual(fx.backend.endCalls.count, 1)
        XCTAssertEqual(fx.backend.endCalls.first?.token, "token-A")
        XCTAssertTrue(fx.transport.connectCalls.isEmpty)
        XCTAssertEqual(fx.capture.startCount, 0)
        XCTAssertNotEqual(fx.service.connectionState, .connecting)

        // Cancel followed by a deliberate restart: available at once, not blocked by the older accounting.
        fx.backend.onAdmit = nil
        fx.backend.endSessionHook = nil
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        XCTAssertEqual(fx.service.connectionState, .connected)
        XCTAssertEqual(fx.backend.admitCalls.count, 2)
        XCTAssertTrue(fx.service.isListening)
        release?.resume()
        await fx.service.end(reason: .userEnded)
    }
}

// MARK: - MF-VS-007: every capture start is gated on the immutable binding

@MainActor
final class VoiceStaleUnmuteTests: XCTestCase {

    func testUnmutingAfterTheBindingWentStaleStopsInsteadOfStartingTheMicrophone() async throws {
        let fx = LifecycleFixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access, startMuted: true)
        XCTAssertEqual(fx.capture.startCount, 0)

        // The authority changes before any event or validity tick has been processed.
        fx.access.isBindingCurrent = false
        assertVoiceThrows(try fx.service.setMuted(false)) {
            XCTAssertEqual($0 as? VoiceSupportAccessError, .bindingNotCurrent)
        }

        XCTAssertEqual(fx.capture.startCount, 0, "the microphone is never started under a stale binding")
        XCTAssertEqual(fx.capture.lastGeneration, 0)
        XCTAssertFalse(fx.service.isListening)
        XCTAssertTrue(fx.service.isMuted, "the displayed state matches the real, stopped state")
        XCTAssertEqual(fx.service.lastStopReason, .contextInvalidated)
        XCTAssertEqual(fx.service.connectionState, .disconnected)
        XCTAssertEqual(fx.transport.disconnectCount, 1, "stale binding stops the transport too")
        await fx.service.end(reason: .userEnded)
    }

    func testStartListeningIsGatedTheSameWay() async throws {
        let fx = LifecycleFixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access, startMuted: true)
        fx.access.isBindingCurrent = false

        assertVoiceThrows(try fx.service.startListening())

        XCTAssertEqual(fx.capture.startCount, 0)
        XCTAssertFalse(fx.service.isListening)
        XCTAssertEqual(fx.service.lastStopReason, .contextInvalidated)
    }

    func testNothingRestartsTheMicrophoneAfterAStaleStop() async throws {
        let fx = LifecycleFixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access, startMuted: true)
        fx.access.isBindingCurrent = false
        _ = try? fx.service.setMuted(false)

        // Even if the authority becomes valid again, only a new explicit Start can bring capture back.
        fx.access.isBindingCurrent = true
        XCTAssertNoThrow(try fx.service.setMuted(false), "not connected: the flag changes, hardware does not")
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(fx.capture.startCount, 0)
        XCTAssertFalse(fx.service.isListening)
        assertVoiceThrows(try fx.service.startListening())
    }

    func testADeliberateUnmuteWithACurrentBindingStillStartsCapture() async throws {
        let fx = LifecycleFixture()
        try await fx.service.connect(bound: fx.binding, access: fx.access, startMuted: true)

        try fx.service.setMuted(false)

        XCTAssertEqual(fx.capture.startCount, 1)
        XCTAssertTrue(fx.service.isListening)
        XCTAssertFalse(fx.service.isMuted)
        await fx.service.end(reason: .userEnded)
    }
}

// MARK: - MF-VS-008: an older End can never act on a session started after it

@MainActor
final class VoiceExitGateTests: XCTestCase {
    func testGenerationsOrderLeavesAndInvalidationObsoletesThemAll() {
        var gate = VoiceExitGate()
        let first = gate.begin()
        XCTAssertTrue(gate.isCurrent(first))
        let second = gate.begin()
        XCTAssertFalse(gate.isCurrent(first), "a newer leave supersedes an older one")
        XCTAssertTrue(gate.isCurrent(second))
        gate.invalidate()
        XCTAssertFalse(gate.isCurrent(second), "Start / owner or context change obsoletes every pending leave")
    }
}

@MainActor
final class VoiceLeaveControllerTests: XCTestCase {

    private final class Exits {
        var values: [VoiceLeaveController.Exit] = []
    }

    private func makeController(_ exits: Exits) -> VoiceLeaveController {
        let controller = VoiceLeaveController()
        controller.exitScreen = { exits.values.append($0) }
        return controller
    }

    func testWithoutANewStartAnEndLeavesAsBeforeForBothActions() async throws {
        for (reason, expected) in [(VoiceStopReason.userEnded, VoiceLeaveController.Exit.close),
                                   (VoiceStopReason.switchedToText, VoiceLeaveController.Exit.text)] {
            let fx = LifecycleFixture()
            let exits = Exits()
            let controller = makeController(exits)
            try await fx.service.connect(bound: fx.binding, access: fx.access)

            await controller.leave(reason: reason, service: fx.service)

            XCTAssertEqual(exits.values, [expected])
            XCTAssertFalse(controller.isHolding)
        }
    }

    func testAnOldEndCannotDismissAfterANewExplicitStartForBothActions() async throws {
        for reason in [VoiceStopReason.userEnded, VoiceStopReason.switchedToText] {
            let fx = LifecycleFixture()
            fx.service.endRemoteTimeout = 0.3
            let exits = Exits()
            let controller = makeController(exits)
            var release: CheckedContinuation<Void, Never>?
            fx.backend.endSessionHook = { _ in await withCheckedContinuation { release = $0 } }
            try await fx.service.connect(bound: fx.binding, access: fx.access)

            // End: capture stops at once, then the decision waits (bounded) on suspended accounting.
            let leaving = Task { @MainActor in await controller.leave(reason: reason, service: fx.service) }
            let stopped = await waitUntil { fx.capture.forceStopCount == 1 && release != nil }
            XCTAssertTrue(stopped)

            // The ready screen exposes Start; the person starts again before the old decision returns.
            fx.backend.endSessionHook = nil
            controller.startBegan()
            try await fx.service.connect(bound: fx.binding, access: fx.access)
            XCTAssertEqual(fx.service.connectionState, .connected)

            await leaving.value   // the old continuation now finishes

            XCTAssertTrue(exits.values.isEmpty, "the old End must not dismiss the new session (\(reason))")
            XCTAssertEqual(fx.service.connectionState, .connected)
            XCTAssertTrue(fx.service.isListening)
            XCTAssertEqual(fx.capture.startCount, 2)
            XCTAssertFalse(controller.isHolding)
            release?.resume()
            await fx.service.end(reason: .userEnded)
        }
    }

    func testAStaleEndShowsNoFakeHoldWhileTheRealCountsStayHonest() async throws {
        let fx = LifecycleFixture()
        fx.service.endRemoteTimeout = 0.3
        let exits = Exits()
        let controller = makeController(exits)
        fx.access.failuresRemaining = 1
        fx.access.failureToThrow = VoiceSupportAppendError.rejected
        var release: CheckedContinuation<Void, Never>?
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        deliverUserFinal(fx, item: "u1", text: "Rejected earlier")
        let rejected = await waitUntil { fx.service.rejectedTranscriptCount == 1 }
        XCTAssertTrue(rejected)
        fx.backend.endSessionHook = { _ in await withCheckedContinuation { release = $0 } }

        let leaving = Task { @MainActor in await controller.leave(reason: .switchedToText, service: fx.service) }
        let stopped = await waitUntil { fx.capture.forceStopCount == 1 && release != nil }
        XCTAssertTrue(stopped)
        fx.backend.endSessionHook = nil
        controller.startBegan()
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        await leaving.value

        XCTAssertFalse(controller.isHolding, "a superseded End raises no hold for a session that was replaced")
        XCTAssertTrue(exits.values.isEmpty)
        XCTAssertEqual(fx.service.rejectedTranscriptCount, 1, "the real rejected count is untouched and still visible")
        release?.resume()
        await fx.service.end(reason: .userEnded)
    }

    func testACurrentEndStillCountsRejectedFinalsAndHoldsUntilResolved() async throws {
        let fx = LifecycleFixture()
        let exits = Exits()
        let controller = makeController(exits)
        fx.access.failuresRemaining = 1
        fx.access.failureToThrow = VoiceSupportAppendError.rejected
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        deliverUserFinal(fx, item: "u1", text: "Keep me")
        let rejected = await waitUntil { fx.service.rejectedTranscriptCount == 1 }
        XCTAssertTrue(rejected)

        await controller.leave(reason: .switchedToText, service: fx.service)

        XCTAssertTrue(controller.isHolding)
        XCTAssertTrue(exits.values.isEmpty, "a rejected final holds the screen exactly as before")
        controller.autoLeaveIfResolved(service: fx.service)
        XCTAssertTrue(exits.values.isEmpty)

        await controller.retry(service: fx.service)   // explicit retry also retries the rejected final
        XCTAssertEqual(fx.access.appended.map(\.text), ["Keep me"])
        XCTAssertEqual(exits.values, [.text], "resolved: the held text switch completes")
        XCTAssertFalse(controller.isHolding)
    }

    func testExplicitDiscardIsSeparateAndLeavesWithTheHeldIntent() async throws {
        let fx = LifecycleFixture()
        let exits = Exits()
        let controller = makeController(exits)
        fx.access.failuresRemaining = 100
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        deliverUserFinal(fx, item: "u1", text: "Pending")
        await controller.leave(reason: .userEnded, service: fx.service)
        XCTAssertTrue(controller.isHolding)

        controller.discardAndLeave(service: fx.service)

        XCTAssertEqual(exits.values, [.close])
        XCTAssertFalse(fx.service.hasUnresolvedTranscript)
        XCTAssertTrue(fx.access.appended.isEmpty, "discarding never looks like a save")
    }

    func testANewerLeaveSupersedesAnOlderOne() async throws {
        let fx = LifecycleFixture()
        fx.service.endRemoteTimeout = 0.3
        let exits = Exits()
        let controller = makeController(exits)
        var release: CheckedContinuation<Void, Never>?
        fx.backend.endSessionHook = { _ in await withCheckedContinuation { release = $0 } }
        try await fx.service.connect(bound: fx.binding, access: fx.access)

        let older = Task { @MainActor in await controller.leave(reason: .userEnded, service: fx.service) }
        let hung = await waitUntil { release != nil }
        XCTAssertTrue(hung)
        fx.backend.endSessionHook = nil
        let newer = Task { @MainActor in await controller.leave(reason: .switchedToText, service: fx.service) }
        await older.value
        await newer.value

        XCTAssertEqual(exits.values, [.text], "only the newest decision acts")
        release?.resume()
    }

    func testStartBeganAloneObsoletesAPendingLeaveBeforeAnySessionIsLive() async throws {
        let fx = LifecycleFixture()
        fx.service.endRemoteTimeout = 0.3
        let exits = Exits()
        let controller = makeController(exits)
        var release: CheckedContinuation<Void, Never>?
        fx.backend.endSessionHook = { _ in await withCheckedContinuation { release = $0 } }
        try await fx.service.connect(bound: fx.binding, access: fx.access)

        let leaving = Task { @MainActor in await controller.leave(reason: .userEnded, service: fx.service) }
        let hung = await waitUntil { release != nil }
        XCTAssertTrue(hung)

        // Start was pressed, but no session is connecting or connected yet (or the start failed fast):
        // the older End still must not act, because the generation, not the live state, decides.
        controller.startBegan()
        XCTAssertFalse(fx.service.connectionState.isConnected)
        XCTAssertNotEqual(fx.service.connectionState, .connecting)
        await leaving.value

        XCTAssertTrue(exits.values.isEmpty, "Start invalidates the older leave even when nothing is live yet")
        XCTAssertFalse(controller.isHolding)
        release?.resume()
    }

    func testAnOwnerOrContextChangeInvalidatesAPendingLeave() async throws {
        let fx = LifecycleFixture()
        fx.service.endRemoteTimeout = 0.3
        let exits = Exits()
        let controller = makeController(exits)
        var release: CheckedContinuation<Void, Never>?
        fx.backend.endSessionHook = { _ in await withCheckedContinuation { release = $0 } }
        try await fx.service.connect(bound: fx.binding, access: fx.access)

        let leaving = Task { @MainActor in await controller.leave(reason: .userEnded, service: fx.service) }
        let hung = await waitUntil { release != nil }
        XCTAssertTrue(hung)
        controller.invalidate()
        await leaving.value

        XCTAssertTrue(exits.values.isEmpty)
        release?.resume()
    }

    func testALiveSessionStartedByAnyPathIsNeverClosedByAnOlderEnd() async throws {
        let fx = LifecycleFixture()
        fx.service.endRemoteTimeout = 0.3
        let exits = Exits()
        let controller = makeController(exits)
        var release: CheckedContinuation<Void, Never>?
        fx.backend.endSessionHook = { _ in await withCheckedContinuation { release = $0 } }
        try await fx.service.connect(bound: fx.binding, access: fx.access)

        let leaving = Task { @MainActor in await controller.leave(reason: .userEnded, service: fx.service) }
        let hung = await waitUntil { release != nil }
        XCTAssertTrue(hung)
        fx.backend.endSessionHook = nil
        // Deliberately NOT calling startBegan(): another path restarted the session.
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        await leaving.value

        XCTAssertTrue(exits.values.isEmpty)
        XCTAssertEqual(fx.service.connectionState, .connected)
        release?.resume()
        await fx.service.end(reason: .userEnded)
    }

    func testAnInFlightRetryCannotLeaveAfterANewStart() async throws {
        let fx = LifecycleFixture()
        let exits = Exits()
        let controller = makeController(exits)
        fx.access.failuresRemaining = 1
        fx.access.failureToThrow = VoiceSupportAppendError.rejected
        try await fx.service.connect(bound: fx.binding, access: fx.access)
        deliverUserFinal(fx, item: "u1", text: "Rejected once")
        let rejected = await waitUntil { fx.service.rejectedTranscriptCount == 1 }
        XCTAssertTrue(rejected)
        await controller.leave(reason: .userEnded, service: fx.service)
        XCTAssertTrue(controller.isHolding)

        var gate: CheckedContinuation<Void, Never>?
        fx.access.appendHook = { [unowned fx] event in
            await withCheckedContinuation { gate = $0 }
            fx.access.appended.append(event)
        }
        let retrying = Task { @MainActor in await controller.retry(service: fx.service) }
        let inFlight = await waitUntil { gate != nil }
        XCTAssertTrue(inFlight)

        controller.startBegan()       // the person starts voice again while the retry is still suspended
        gate?.resume()
        await retrying.value

        XCTAssertTrue(exits.values.isEmpty, "the retry's continuation is obsolete and must not leave")
        XCTAssertFalse(controller.isHolding)
    }
}

// MARK: - MF-VS-008-R5a/R5b: a newer leave owns the destination; context changes retire pending leaves

@MainActor
final class VoiceLeaveHoldRaceTests: XCTestCase {

    private final class Exits {
        var values: [VoiceLeaveController.Exit] = []
    }

    private func makeController(_ exits: Exits) -> VoiceLeaveController {
        let controller = VoiceLeaveController()
        controller.exitScreen = { exits.values.append($0) }
        return controller
    }

    private func unresolvedService(rejected: Int = 1, unsaved: Int = 0) -> MockVoiceService {
        let mock = MockVoiceService()
        mock.rejectedTranscriptCount = rejected
        mock.unsavedTranscriptCount = unsaved
        mock.hasUnresolvedTranscript = rejected + unsaved > 0
        mock.endOutcome = VoiceEndOutcome(unsavedTranscripts: unsaved, rejectedTranscripts: rejected, remoteWorkCompleted: true)
        return mock
    }

    private func resolve(_ mock: MockVoiceService) {
        mock.rejectedTranscriptCount = 0
        mock.unsavedTranscriptCount = 0
        mock.hasUnresolvedTranscript = false
    }

    /// Suspends the mock's End until `release()` is called, and reports when it has started waiting.
    private final class DeferredEnd {
        var continuation: CheckedContinuation<Void, Never>?
        var isWaiting: Bool { continuation != nil }
        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    private func defer_(_ mock: MockVoiceService) -> DeferredEnd {
        let deferred = DeferredEnd()
        mock.endGate = { await withCheckedContinuation { deferred.continuation = $0 } }
        return deferred
    }

    // MARK: The reviewed race

    func testAnOldHeldCloseCannotBeReleasedTowardCloseWhileANewerUseTextWaits() async throws {
        let mock = unresolvedService()
        let exits = Exits()
        let controller = makeController(exits)

        // 1. End returns unresolved finals: the screen holds with the destination .close.
        await controller.leave(reason: .userEnded, service: mock)
        XCTAssertTrue(controller.isHolding)
        XCTAssertEqual(controller.pendingExit, .close)

        // 2. The person chooses Use text. Its End is deferred (remote work still running).
        let deferred = defer_(mock)
        mock.endOutcome = VoiceEndOutcome(unsavedTranscripts: 0, rejectedTranscripts: 0, remoteWorkCompleted: true)
        let useText = Task { @MainActor in await controller.leave(reason: .switchedToText, service: mock) }
        let waiting = await waitUntil { deferred.isWaiting }
        XCTAssertTrue(waiting)

        // The older hold is gone synchronously, before the await; the real counts are still visible.
        XCTAssertFalse(controller.isHolding)
        XCTAssertNil(controller.pendingExit)
        XCTAssertEqual(mock.rejectedTranscriptCount, 1, "unsaved / rejected visibility is untouched")

        // 3. Transcript saving finishes during the wait; the view's count observer fires.
        resolve(mock)
        controller.autoLeaveIfResolved(service: mock)
        XCTAssertTrue(exits.values.isEmpty, "the old auto-leave must not choose the old exit")

        // 4. The newer End finishes: ITS destination is the only one taken.
        deferred.release()
        await useText.value
        XCTAssertEqual(exits.values, [.text])
        XCTAssertFalse(controller.isHolding)
    }

    func testTheInverseAnOldHeldTextSwitchCannotOverrideANewerClose() async throws {
        let mock = unresolvedService()
        let exits = Exits()
        let controller = makeController(exits)
        await controller.leave(reason: .switchedToText, service: mock)
        XCTAssertEqual(controller.pendingExit, .text)

        let deferred = defer_(mock)
        mock.endOutcome = VoiceEndOutcome(unsavedTranscripts: 0, rejectedTranscripts: 0, remoteWorkCompleted: true)
        let close = Task { @MainActor in await controller.leave(reason: .userEnded, service: mock) }
        let waiting = await waitUntil { deferred.isWaiting }
        XCTAssertTrue(waiting)
        resolve(mock)
        controller.autoLeaveIfResolved(service: mock)
        XCTAssertTrue(exits.values.isEmpty)

        deferred.release()
        await close.value
        XCTAssertEqual(exits.values, [.close])
    }

    func testANonDismissingLeaveAlsoRetiresAnOlderHoldAndNeverNavigates() async throws {
        let mock = unresolvedService()
        let exits = Exits()
        let controller = makeController(exits)
        await controller.leave(reason: .userEnded, service: mock)
        XCTAssertTrue(controller.isHolding)

        let deferred = defer_(mock)
        let cancel = Task { @MainActor in
            await controller.leave(reason: .userEnded, dismissWhenDone: false, service: mock)
        }
        let waiting = await waitUntil { deferred.isWaiting }
        XCTAssertTrue(waiting)
        XCTAssertFalse(controller.isHolding)
        resolve(mock)
        controller.autoLeaveIfResolved(service: mock)
        deferred.release()
        await cancel.value

        XCTAssertTrue(exits.values.isEmpty, "no stale hold navigates, and a non-dismissing leave never does")
        XCTAssertFalse(controller.isHolding)
    }

    // MARK: Current controls (unchanged behavior)

    func testTheNewerLeaveThatStillHasUnresolvedFinalsHoldsWithItsOwnDestination() async throws {
        let mock = unresolvedService()
        let exits = Exits()
        let controller = makeController(exits)
        await controller.leave(reason: .userEnded, service: mock)
        XCTAssertEqual(controller.pendingExit, .close)

        let deferred = defer_(mock)   // the newer End returns with the counts still unresolved
        let useText = Task { @MainActor in await controller.leave(reason: .switchedToText, service: mock) }
        let waiting = await waitUntil { deferred.isWaiting }
        XCTAssertTrue(waiting)
        deferred.release()
        await useText.value

        XCTAssertTrue(controller.isHolding)
        XCTAssertEqual(controller.pendingExit, .text, "the hold now belongs to the newest choice")
        XCTAssertTrue(exits.values.isEmpty, "rejected finals still hold the screen exactly as before")

        resolve(mock)
        controller.autoLeaveIfResolved(service: mock)
        XCTAssertEqual(exits.values, [.text])
    }

    func testExplicitDiscardAfterANewerLeaveUsesTheNewDestination() async throws {
        let mock = unresolvedService()
        let exits = Exits()
        let controller = makeController(exits)
        await controller.leave(reason: .userEnded, service: mock)
        await controller.leave(reason: .switchedToText, service: mock)
        XCTAssertEqual(controller.pendingExit, .text)

        controller.discardAndLeave(service: mock)

        XCTAssertEqual(exits.values, [.text])
        XCTAssertFalse(mock.hasUnresolvedTranscript)
    }

    func testALeaveWithNothingUnresolvedStillNavigatesImmediately() async throws {
        let mock = MockVoiceService()
        let exits = Exits()
        let controller = makeController(exits)
        await controller.leave(reason: .switchedToText, service: mock)
        XCTAssertEqual(exits.values, [.text])
        XCTAssertFalse(controller.isHolding)
    }

    // MARK: Context changes are bound to the exit generation

    func testOnlyOwnerAccountOrContextStopReasonsRetireAPendingLeave() {
        let retiring: [VoiceStopReason] = [.accountChanged, .contextInvalidated, .privacyLeaseExpired]
        let notRetiring: [VoiceStopReason] = [
            .userEnded, .switchedToText, .appBackgrounded, .deviceLocked, .audioInterrupted, .routeLost,
            .sessionLimit, .idleTimeout, .quotaReached, .connectionLost, .serverError, .failedToStart,
        ]
        for reason in retiring { XCTAssertTrue(reason.invalidatesPendingLeave, "\(reason)") }
        for reason in notRetiring { XCTAssertFalse(reason.invalidatesPendingLeave, "\(reason)") }
    }

    func testAContextStopRetiresALeaveThatIsStillWaitingOnEnd() async throws {
        for reason in [VoiceStopReason.contextInvalidated, .accountChanged, .privacyLeaseExpired] {
            let mock = unresolvedService(rejected: 0)
            let exits = Exits()
            let controller = makeController(exits)
            let deferred = defer_(mock)
            let leaving = Task { @MainActor in await controller.leave(reason: .userEnded, service: mock) }
            let waiting = await waitUntil { deferred.isWaiting }
            XCTAssertTrue(waiting)

            controller.noteStop(reason)   // what the views' lastStopReason handler now does
            deferred.release()
            await leaving.value

            XCTAssertTrue(exits.values.isEmpty, "\(reason): the retired decision navigates nowhere")
            XCTAssertFalse(controller.isHolding)
        }
    }

    func testADeliberateStopNeverCancelsTheLeaveThatCausedIt() async throws {
        for reason in [VoiceStopReason.userEnded, .switchedToText, .appBackgrounded, .audioInterrupted] {
            let mock = MockVoiceService()
            let exits = Exits()
            let controller = makeController(exits)
            let deferred = defer_(mock)
            let leaving = Task { @MainActor in await controller.leave(reason: .userEnded, service: mock) }
            let waiting = await waitUntil { deferred.isWaiting }
            XCTAssertTrue(waiting)

            controller.noteStop(reason)
            deferred.release()
            await leaving.value

            XCTAssertEqual(exits.values, [.close], "\(reason) must not retire the pending leave")
        }
    }

    func testAContextChangeWhileHoldingClearsTheHoldButKeepsTheCountsVisible() async throws {
        let mock = unresolvedService(rejected: 1, unsaved: 2)
        let exits = Exits()
        let controller = makeController(exits)
        await controller.leave(reason: .userEnded, service: mock)
        XCTAssertTrue(controller.isHolding)

        controller.noteStop(.contextInvalidated)

        XCTAssertFalse(controller.isHolding)
        XCTAssertEqual(mock.unsavedTranscriptCount, 2, "unsaved stays visible")
        XCTAssertEqual(mock.rejectedTranscriptCount, 1, "rejected stays visible")
        resolve(mock)
        controller.autoLeaveIfResolved(service: mock)
        XCTAssertTrue(exits.values.isEmpty, "the retired hold cannot navigate when counts later resolve")

        // The person can still choose to leave again, and that new choice holds or leaves normally.
        mock.rejectedTranscriptCount = 1
        mock.hasUnresolvedTranscript = true
        mock.endOutcome = VoiceEndOutcome(unsavedTranscripts: 0, rejectedTranscripts: 1, remoteWorkCompleted: true)
        await controller.leave(reason: .userEnded, service: mock)
        XCTAssertTrue(controller.isHolding)
    }

    func testTheAccessInvalidationSignalRetiresPendingLeavesEvenAfterEndRemovedTheSession() async throws {
        var continuation: AsyncStream<Void>.Continuation!
        let stream = AsyncStream<Void> { continuation = $0 }
        let mock = unresolvedService(rejected: 0)
        let exits = Exits()
        let controller = makeController(exits)
        let observer = Task { @MainActor in await controller.retireOnInvalidation(from: stream) }

        // A leave waiting on End.
        let deferred = defer_(mock)
        let leaving = Task { @MainActor in await controller.leave(reason: .userEnded, service: mock) }
        let waiting = await waitUntil { deferred.isWaiting }
        XCTAssertTrue(waiting)
        continuation.yield(())
        try await Task.sleep(nanoseconds: 40_000_000)
        deferred.release()
        await leaving.value
        XCTAssertTrue(exits.values.isEmpty)

        // A transcript hold, with the session long gone.
        mock.endGate = nil
        mock.rejectedTranscriptCount = 1
        mock.hasUnresolvedTranscript = true
        mock.endOutcome = VoiceEndOutcome(unsavedTranscripts: 0, rejectedTranscripts: 1, remoteWorkCompleted: true)
        await controller.leave(reason: .switchedToText, service: mock)
        XCTAssertTrue(controller.isHolding)
        continuation.yield(())
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertFalse(controller.isHolding)
        XCTAssertEqual(mock.rejectedTranscriptCount, 1, "still visible after the signal")
        resolve(mock)
        controller.autoLeaveIfResolved(service: mock)
        XCTAssertTrue(exits.values.isEmpty)

        continuation.finish()
        await observer.value
    }
}
