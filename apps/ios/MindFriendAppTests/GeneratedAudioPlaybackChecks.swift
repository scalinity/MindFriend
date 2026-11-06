// Silent host-only standalone checks for the generated-content player and native speech service.
// Run from the repository root (no app launch, credentials, provider calls or audible speech):
// swiftc -DGENERATED_AUDIO_STANDALONE -parse-as-library \
//   -module-cache-path .artifacts/generated-audio-checks/module-cache \
//   apps/ios/MindFriendApp/Features/GeneratedContent/GeneratedContentModels.swift \
//   apps/ios/MindFriendApp/Core/Services/NativeTTSService.swift \
//   apps/ios/MindFriendApp/Features/Generative/AudioPlayerViewModel.swift \
//   apps/ios/MindFriendAppTests/GeneratedAudioPlaybackChecks.swift \
//   -o .artifacts/generated-audio-checks/playback-checks
// .artifacts/generated-audio-checks/playback-checks
// .artifacts/generated-audio-checks/playback-checks --check-local-media
#if GENERATED_AUDIO_STANDALONE
import AVFoundation
import Combine
import Foundation

#if GENERATED_AUDIO_UI_TYPECHECK
import SwiftUI

// Unrelated sheet and persistence boundaries for focused iOS view typechecking.
struct BackgroundSoundsSheet: View {
    @Binding var selectedSound: BackgroundSoundType?
    @Binding var volume: Float
    var body: some View { Color.clear }
}
extension GeneratedContentType {
    var backgroundColor: Color { .blue }
}
let supabase: Void = ()
struct GeneratedContentService {
    init(supabase: Void) {}
    struct RatingResponse { let message: String }
    func toggleFavorite(contentId: UUID) async throws -> Bool { throw CheckError.unexpectedNetwork }
    func rateContent(contentId: UUID, rating: Int) async throws -> RatingResponse { throw CheckError.unexpectedNetwork }
}
#endif

// No live backend can be reached by these checks, even through a default dependency.
enum SupabaseStorageMedia {
    static func resolve(_ url: URL) async throws -> URL {
        throw CheckError.unexpectedNetwork
    }
}
enum SupabaseConfig {
    static let projectURL = URL(string: "https://example.invalid")!
}
enum VoiceGender: String, Codable { case female, male, neutral }

#if os(macOS)
// AVAudioSession is iOS-only. This host shim exercises interruption decisions without
// activating an audio session. All other AVFoundation/Combine types are the real SDK.
let AVAudioSessionInterruptionTypeKey = "interruptionType"
let AVAudioSessionInterruptionOptionKey = "interruptionOptions"
final class AVAudioSession {
    enum InterruptionType: UInt { case ended = 0, began = 1 }
    struct InterruptionOptions: OptionSet {
        let rawValue: UInt
        static let shouldResume = Self(rawValue: 1)
    }
    struct Category { static let playback = Self() }
    struct Mode { static let spokenAudio = Self() }
    struct CategoryOptions: OptionSet {
        let rawValue: UInt
        static let mixWithOthers = Self(rawValue: 1)
    }
    static let interruptionNotification = Notification.Name("GeneratedPlaybackCheckInterruption")
    static func sharedInstance() -> AVAudioSession { AVAudioSession() }
    func setCategory(_ category: Category, mode: Mode, options: CategoryOptions) throws {}
    func setActive(_ active: Bool) throws {}
}
#endif

enum CheckError: Error { case unexpectedNetwork, expectedFailure, timeout(String) }

@MainActor
final class MockSpeech: NativeSpeechPlaying {
    var isSpeaking = false
    var isPaused = false
    var speakCalls = 0
    var stopCalls = 0
    var resumeCalls = 0
    var lastText: String?
    var lastSettings: NativeTTSService.VoiceSettings?
    let states = CurrentValueSubject<NativeSpeechPlaybackState, Never>(
        NativeSpeechPlaybackState(isSpeaking: false, isPaused: false, isPreparing: false, progress: 0, error: nil)
    )
    var playbackStates: AnyPublisher<NativeSpeechPlaybackState, Never> { states.eraseToAnyPublisher() }

    func emit(speaking: Bool, paused: Bool = false, preparing: Bool = false,
              progress: Double = 0, error: String? = nil) {
        isSpeaking = speaking
        isPaused = paused
        states.send(NativeSpeechPlaybackState(isSpeaking: speaking, isPaused: paused,
                                             isPreparing: preparing, progress: progress, error: error))
    }
    func speak(_ text: String, settings: NativeTTSService.VoiceSettings) {
        speakCalls += 1
        // Match the real service's synchronous completion-state reset before a new utterance.
        states.send(NativeSpeechPlaybackState(isSpeaking: false, isPaused: false,
                                             isPreparing: false, progress: states.value.progress, error: nil))
        stop()
        lastText = text
        lastSettings = settings
        emit(speaking: true, preparing: true)
    }
    func pause() {
        guard isSpeaking else { return }
        emit(speaking: true, paused: true, progress: states.value.progress)
    }
    func resume() {
        resumeCalls += 1
        emit(speaking: true, progress: states.value.progress)
    }
    func stop() {
        stopCalls += 1
        emit(speaking: false)
    }
}

@MainActor
final class HeldResolver {
    var calls: [URL] = []
    var continuation: CheckedContinuation<URL, Error>?
    func resolve(_ url: URL) async throws -> URL {
        calls.append(url)
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func fail() {
        continuation?.resume(throwing: CheckError.expectedFailure)
        continuation = nil
    }
    func succeed(_ url: URL) {
        continuation?.resume(returning: url)
        continuation = nil
    }
}

@main
@MainActor
struct GeneratedAudioPlaybackChecks {
    static var passed = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ label: String,
                       file: StaticString = #file, line: UInt = #line) {
        precondition(condition(), "FAIL: \(label)", file: file, line: line)
        passed += 1
    }
    static func settle() async {
        for _ in 0..<8 { await Task.yield() }
    }
    static func waitUntil(_ label: String, _ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw CheckError.timeout(label)
    }
    static func content(type: GeneratedContentType = .meditation, audio: String? = nil,
                        text: String = "Breathe gently. Notice the quiet.", favorite: Bool = false) -> GeneratedContent {
        GeneratedContent(id: UUID(), userId: UUID(), contentType: type, title: "Offline fixture",
                         textContent: text, audioUrl: audio, voiceId: nil, duration: 60, qualityScore: nil,
                         status: .completed, generationPrompt: nil, aiModel: nil, processingTimeMs: nil,
                         triggerWarnings: nil, averageRating: nil, ratingCount: 0, seriesId: nil,
                         seriesOrder: nil, isFavorite: favorite, playCount: 0, lastPlayedAt: nil,
                         generationContext: nil, userRating: nil, createdAt: Date(), updatedAt: Date())
    }
    static func interrupt(_ type: AVAudioSession.InterruptionType, shouldResume: Bool = false) async {
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
                                        userInfo: [AVAudioSessionInterruptionTypeKey: type.rawValue,
                                                   AVAudioSessionInterruptionOptionKey: shouldResume ? UInt(1) : UInt(0)])
        await settle()
    }
    static func localMediaChecks() async throws {
        // A short silent WAV fixture verifies actual AVURLAsset/AVPlayer readiness offline.
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".artifacts/generated-audio-checks/silence.wav")
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        text("RIFF"); u32(16036); text("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(8000); u32(16000); u16(2); u16(16)
        text("data"); u32(16000); data.append(Data(repeating: 0, count: 16000))
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let resolver = HeldResolver()
        let speech = MockSpeech()
        let player = AudioPlayerViewModel(speech: speech, resolveAudioURL: resolver.resolve)
        defer { player.cleanup() }
        let loading = Task { await player.load(content: content(audio: "https://example.invalid/audio.mp3")) }
        try await waitUntil("local-media resolver") { resolver.continuation != nil }
        player.play()
        resolver.succeed(url)
        await loading.value
        try await waitUntil("local-media ready") { !player.isLoading }
        expect(player.error == nil && player.isPlaying && player.isPlaybackRequested, "pending Play starts at real AVPlayer readiness")
        expect(player.canSeek && player.duration > 0.9, "recorded media preserves duration and seeking")
        player.pause()
        expect(!player.isPlaying, "recorded media pauses")
        player.play()
        expect(player.isPlaying && speech.speakCalls == 0, "recorded media resumes without speech")
        await interrupt(.began)
        expect(!player.isPlaying, "recorded interruption pauses playback")
        await interrupt(.ended, shouldResume: true)
        expect(player.isPlaying, "recorded interruption legitimately resumes playback")
        await interrupt(.began)
        player.pause()
        await interrupt(.ended, shouldResume: true)
        expect(!player.isPlaying && !player.isPlaybackRequested,
               "explicit recorded pause during interruption cancels resumption")
        player.play()
        await interrupt(.began)
        player.sleepTimerMinutes = 0
        try await waitUntil("recorded timer expires during interruption") { player.sleepTimerMinutes == nil }
        await interrupt(.ended, shouldResume: true)
        expect(!player.isPlaying && !player.isPlaybackRequested && player.sleepTimerRemaining == 0 && speech.speakCalls == 0,
               "recorded timer cutoff during interruption prevents resumption")
        player.play()
        player.seek(to: player.duration)
        player.play()
        expect(player.isPlaying && player.currentTime < player.duration, "recorded media replays after reaching end")
        player.cleanup()
        await settle()
        expect(!player.isPlaying && !player.canPlay, "recorded media cleanup ignores queued callbacks")

        let pausedLoading = Task { await player.load(content: content(audio: "https://example.invalid/audio.mp3")) }
        try await waitUntil("paused local-media resolver") { resolver.continuation != nil }
        player.play()
        player.pause()
        resolver.succeed(url)
        await pausedLoading.value
        try await waitUntil("paused local-media ready") { !player.isLoading }
        expect(player.error == nil && !player.isPlaying && !player.isPlaybackRequested, "Pause during preparation prevents autoplay at readiness")

        let dismissedLoading = Task { await player.load(content: content(audio: "https://example.invalid/audio.mp3")) }
        try await waitUntil("dismissed local-media resolver") { resolver.continuation != nil }
        player.play()
        player.cleanup()
        resolver.succeed(url)
        await dismissedLoading.value
        expect(!player.isPlaying && !player.canPlay && player.error == nil, "successful stale resolution cannot revive dismissed media")

        let replacedLoading = Task { await player.load(content: content(audio: "https://example.invalid/audio.mp3")) }
        try await waitUntil("replaced local-media resolver") { resolver.continuation != nil }
        player.play()
        await player.load(content: content(type: .sleepStory))
        player.play()
        resolver.succeed(url)
        await replacedLoading.value
        expect(player.usesBuiltInVoice && player.isPlaying && player.isPlaybackRequested && speech.speakCalls == 1,
               "successful stale resolution cannot replace current built-in speech")
        print("PASS: AVPlayer readiness, pending Play, pause/resume, seeking, replay and cleanup (silent host-only checks)")
    }
    static func main() async throws {
        if CommandLine.arguments.contains("--check-local-media") {
            try await localMediaChecks()
            print("PASS: \(passed) local-media assertions")
            return
        }
        // Fresh, history and favorite items take the same text-only path, including sleep stories.
        for type in [GeneratedContentType.meditation, .sleepStory, .breathing, .affirmation] {
            for favorite in [false, true] {
                let speech = MockSpeech()
                var resolutions = 0
                let player = AudioPlayerViewModel(speech: speech, resolveAudioURL: { url in
                    resolutions += 1
                    return url
                })
                await player.load(content: content(type: type, favorite: favorite))
                expect(player.usesBuiltInVoice && player.canPlay && !player.canSeek, "text-only mode playable")
                expect(!player.isPlaying && !player.isLoading, "load does not autoplay")
                player.togglePlayback()
                expect(speech.speakCalls == 1 && player.isPlaybackRequested, "Play starts native speech")
                expect(speech.lastText == "Breathe gently. Notice the quiet.", "script reaches native speech")
                expect(player.isLoading, "voice preparation is visible")
                speech.emit(speaking: true, progress: 0.35)
                expect(!player.isLoading && player.isPlaying && player.progress == 0.35, "speech progress reaches player")
                player.seek(to: 0.9)
                player.skipForward()
                player.skipBackward()
                expect(player.progress == 0.35, "speech cannot seek to fictional audio seconds")
                player.togglePlayback()
                expect(speech.isPaused && !player.isPlaying && !player.isPlaybackRequested, "Pause pauses speech")
                player.togglePlayback()
                expect(speech.resumeCalls == 1 && speech.speakCalls == 1 && player.isPlaying, "resume retains utterance")
                speech.emit(speaking: false, progress: 1)
                expect(!player.isPlaying && !player.isPlaybackRequested && player.progress == 1, "natural end updates player")
                player.play()
                expect(speech.speakCalls == 2 && player.isPlaybackRequested, "Play after end restarts speech")
                player.togglePlayback()
                expect(speech.isPaused && !player.isPlaybackRequested, "replayed speech can still pause")
                expect(resolutions == 0, "text-only playback never signs or fetches media")
                player.cleanup()
                expect(!speech.isSpeaking && !player.canPlay && !player.isPlaying && player.progress == 0, "dismiss stops speech")
                speech.emit(speaking: true, progress: 0.7)
                expect(!player.isPlaying && player.progress == 0, "late speech state after dismissal ignored")
            }
        }
        print("PASS: text-only fresh/history/favorite playback, pause/resume/end/replay, cleanup, zero media calls")

        let speech = MockSpeech()
        let player = AudioPlayerViewModel(speech: speech)
        await player.load(content: content(type: .meditation))
        player.play()
        expect(speech.lastSettings?.rate == NativeTTSService.VoiceSettings.meditation.rate, "meditation voice settings")
        speech.emit(speaking: true, progress: 0.4)
        await interrupt(.began)
        expect(!player.isPlaying && speech.isPaused, "interruption pauses speech")
        await interrupt(.ended, shouldResume: true)
        expect(player.isPlaying && speech.resumeCalls == 1, "eligible interruption resumes speech")
        player.pause()
        await interrupt(.began)
        await interrupt(.ended, shouldResume: true)
        expect(!player.isPlaying && speech.resumeCalls == 1, "previously paused speech does not autoresume")
        player.play()
        await interrupt(.began)
        await interrupt(.ended, shouldResume: false)
        expect(!player.isPlaying, "interruption without resume permission stays paused")
        player.play()
        await interrupt(.began)
        let speaksBeforeCutoff = speech.speakCalls
        let resumesBeforeCutoff = speech.resumeCalls
        player.sleepTimerMinutes = 0
        try await waitUntil("speech timer expires during interruption") { player.sleepTimerMinutes == nil }
        expect(!player.isPlaying && !player.isPlaybackRequested && player.sleepTimerRemaining == 0,
               "speech timer expires while interruption is active")
        await interrupt(.ended, shouldResume: true)
        expect(!player.isPlaying && !player.isPlaybackRequested && speech.isPaused &&
               speech.speakCalls == speaksBeforeCutoff && speech.resumeCalls == resumesBeforeCutoff,
               "speech timer cutoff cancels interrupted resume without a new utterance or resume")
        player.play()
        await interrupt(.began)
        let speaksBeforePause = speech.speakCalls
        let resumesBeforePause = speech.resumeCalls
        player.pause()
        await interrupt(.ended, shouldResume: true)
        expect(!player.isPlaying && !player.isPlaybackRequested && speech.isPaused &&
               speech.speakCalls == speaksBeforePause && speech.resumeCalls == resumesBeforePause,
               "explicit speech pause during interruption cancels resumption")
        player.cleanup()
        await interrupt(.ended, shouldResume: true)
        expect(!player.isPlaying && !player.canPlay, "interruption cannot revive dismissed speech")
        print("PASS: interruption pause, conditional resume, timer cutoff, explicit pause and dismissal (host state checks)")

        await player.load(content: content(text: " \n\t "))
        expect(player.error != nil && !player.canPlay, "empty text gives actionable failure")
        await player.load(content: content(audio: "   "))
        expect(player.usesBuiltInVoice && player.canPlay, "empty audio URL uses text")
        player.play()
        speech.emit(speaking: false, error: "Voice unavailable")
        expect(player.error == "Voice unavailable" && !player.isLoading && !player.isPlaying, "native failure reaches UI")
        await player.load(content: content(type: .sleepStory))
        expect(player.error == nil && player.canPlay, "retry replaces failed speech state")
        player.play()
        player.sleepTimerMinutes = 0
        await settle()
        expect(!player.isPlaying && !player.isPlaybackRequested, "sleep timer pauses built-in voice")
        player.cleanup()
        print("PASS: empty content, empty URL, native failure, retry and speech sleep timer")

        let mediaURL = URL(string: "https://example.invalid/storage/v1/object/public/generated-audio/fixture/audio.mp3")!
        let resolver = HeldResolver()
        let mediaSpeech = MockSpeech()
        let mediaPlayer = AudioPlayerViewModel(speech: mediaSpeech, resolveAudioURL: resolver.resolve)
        let loading = Task { await mediaPlayer.load(content: content(audio: mediaURL.absoluteString)) }
        try await waitUntil("resolver entered") { resolver.continuation != nil }
        expect(resolver.calls == [mediaURL], "recorded audio uses signed-media resolver")
        expect(mediaPlayer.isLoading && mediaPlayer.canPlay && !mediaPlayer.usesBuiltInVoice, "recorded media preparation state")
        mediaPlayer.togglePlayback()
        expect(mediaPlayer.isPlaybackRequested && !mediaPlayer.isPlaying, "Play during preparation is retained")
        mediaPlayer.togglePlayback()
        expect(!mediaPlayer.isPlaybackRequested, "Pause cancels pending Play")
        mediaPlayer.play()
        mediaPlayer.cleanup()
        resolver.fail()
        await loading.value
        expect(!mediaPlayer.isLoading && !mediaPlayer.isPlaying && !mediaPlayer.isPlaybackRequested && mediaPlayer.error == nil,
               "late resolver failure after dismissal ignored")
        expect(mediaSpeech.speakCalls == 0, "recorded audio preserves recorded route")

        let replacement = Task { await mediaPlayer.load(content: content(audio: mediaURL.absoluteString)) }
        try await waitUntil("replacement resolver entered") { resolver.continuation != nil }
        mediaPlayer.play()
        await mediaPlayer.load(content: content(type: .sleepStory, text: "Replacement story."))
        mediaPlayer.play()
        resolver.fail()
        await replacement.value
        expect(mediaPlayer.usesBuiltInVoice && mediaPlayer.isPlaybackRequested && mediaPlayer.error == nil,
               "stale media failure cannot overwrite replacement speech")
        expect(mediaSpeech.lastText == "Replacement story.", "replacement uses current text")
        mediaPlayer.cleanup()

        let failure = Task { await mediaPlayer.load(content: content(audio: mediaURL.absoluteString)) }
        try await waitUntil("failing resolver entered") { resolver.continuation != nil }
        mediaPlayer.play()
        resolver.fail()
        await failure.value
        expect(mediaPlayer.error != nil && !mediaPlayer.isLoading && !mediaPlayer.isPlaying && !mediaPlayer.isPlaybackRequested,
               "media resolution failure clears pending Play")
        let cancelled = Task { await mediaPlayer.load(content: content(audio: mediaURL.absoluteString)) }
        try await waitUntil("cancelled resolver entered") { resolver.continuation != nil }
        cancelled.cancel()
        resolver.fail()
        await cancelled.value
        expect(!mediaPlayer.isLoading && mediaPlayer.error == nil && !mediaPlayer.canPlay, "task cancellation clears preparing state")
        mediaPlayer.cleanup()
        print("PASS: signed resolver, pending Play/Pause, failure, task cancellation, dismissal and replacement races")

        // Exercise the real service's early failure and late delegate guards without calling speak on audible text.
        let native = NativeTTSService()
        native.speak(" \n\t ")
        expect(native.error != nil && !native.isSpeaking && !native.isPreparing, "native service rejects empty speech")
        native.stop()
        let synthesizer = AVSpeechSynthesizer()
        let stale = AVSpeechUtterance(string: "Synthetic stale callback fixture.")
        native.speechSynthesizer(synthesizer, didStart: stale)
        native.speechSynthesizer(synthesizer, willSpeakRangeOfSpeechString: NSRange(location: 0, length: 4), utterance: stale)
        native.speechSynthesizer(synthesizer, didFinish: stale)
        native.speechSynthesizer(synthesizer, didCancel: stale)
        await settle()
        expect(!native.isSpeaking && !native.isPaused && !native.isPreparing && native.progress == 0 && native.error == nil,
               "stopped native service ignores stale start/progress/end/cancel callbacks")
        print("PASS: actual native speech empty-input and stale delegate guards")
        print("PASS: \(passed) offline assertions")
    }
}
#endif
