import AVFoundation
import Combine

struct NativeSpeechPlaybackState {
    let isSpeaking: Bool
    let isPaused: Bool
    let isPreparing: Bool
    let progress: Double
    let error: String?
}

@MainActor
protocol NativeSpeechPlaying: AnyObject {
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }
    var playbackStates: AnyPublisher<NativeSpeechPlaybackState, Never> { get }
    func speak(_ text: String, settings: NativeTTSService.VoiceSettings)
    func pause()
    func resume()
    func stop()
}

/// Native iOS Text-to-Speech Service using AVSpeechSynthesizer
/// Used for free tier users instead of ElevenLabs (zero cost)
@MainActor
public final class NativeTTSService: NSObject, ObservableObject, NativeSpeechPlaying {

    // MARK: - Published State

    @Published public private(set) var isSpeaking: Bool = false
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var progress: Double = 0.0
    @Published public private(set) var currentText: String = ""
    @Published public private(set) var isPreparing: Bool = false
    @Published public private(set) var error: String?

    var playbackStates: AnyPublisher<NativeSpeechPlaybackState, Never> {
        Publishers.CombineLatest4($isSpeaking, $isPaused, $progress, $error)
            .combineLatest($isPreparing)
            .map { state, preparing in
                NativeSpeechPlaybackState(isSpeaking: state.0, isPaused: state.1,
                                          isPreparing: preparing, progress: state.2, error: state.3)
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Private Properties

    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var totalCharacters: Int = 0
    private var spokenCharacters: Int = 0

    // MARK: - Voice Settings

    public struct VoiceSettings {
        var rate: Float = 0.45          // 0.0 - 1.0, default ~0.5
        var pitch: Float = 1.0          // 0.5 - 2.0
        var volume: Float = 0.9         // 0.0 - 1.0
        var language: String = "en-US"
        var voiceIdentifier: String?    // Specific voice like "com.apple.voice.compact.en-US.Samantha"

        public static let calm = VoiceSettings(rate: 0.4, pitch: 0.95, volume: 0.85)
        public static let meditation = VoiceSettings(rate: 0.35, pitch: 0.9, volume: 0.8)
        public static let breathing = VoiceSettings(rate: 0.38, pitch: 0.95, volume: 0.85)
        public static let affirmation = VoiceSettings(rate: 0.45, pitch: 1.0, volume: 0.9)
        public static let grounding = VoiceSettings(rate: 0.42, pitch: 0.95, volume: 0.85)
    }

    // MARK: - Initialization

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public Methods

    /// Speak text content with optional voice settings
    public func speak(_ text: String, settings: VoiceSettings = .calm) {
        stop()

        let sanitizedText = sanitizeText(text)
        guard !sanitizedText.isEmpty else {
            error = "There is no text to read aloud."
            return
        }
        guard configureAudioSession() else { return }

        currentText = sanitizedText
        // Delegate ranges use UTF-16 offsets, including for emoji and accented text.
        totalCharacters = sanitizedText.utf16.count
        spokenCharacters = 0
        progress = 0.0

        let utterance = AVSpeechUtterance(string: sanitizedText)
        utterance.rate = settings.rate
        utterance.pitchMultiplier = settings.pitch
        utterance.volume = settings.volume
        utterance.preUtteranceDelay = 0.2
        utterance.postUtteranceDelay = 0.1

        // Select voice
        let voice = settings.voiceIdentifier.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
            ?? AVSpeechSynthesisVoice(language: settings.language)
        guard let voice else {
            error = "A built-in voice is unavailable. Try again after checking your device's spoken content voices."
            return
        }
        utterance.voice = voice

        currentUtterance = utterance
        isPreparing = true
        isSpeaking = true
        isPaused = false
        synthesizer.speak(utterance)
    }

    /// Pause current speech
    public func pause() {
        guard isSpeaking, !isPaused else { return }
        isPaused = true
        synthesizer.pauseSpeaking(at: .immediate)
    }

    /// Resume paused speech
    public func resume() {
        guard isPaused else { return }
        guard configureAudioSession() else { return }
        isPaused = false
        synthesizer.continueSpeaking()
    }

    /// Stop current speech
    public func stop() {
        // Invalidate before stopping: cancellation callbacks may arrive after replacement.
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        isPreparing = false
        isSpeaking = false
        isPaused = false
        progress = 0.0
        currentText = ""
        spokenCharacters = 0
        totalCharacters = 0
        error = nil
    }

    /// Get available voices for a language
    public func availableVoices(for language: String = "en") -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.starts(with: language) }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    /// Get premium quality voices (Enhanced/Premium quality)
    public func premiumVoices(for language: String = "en") -> [AVSpeechSynthesisVoice] {
        availableVoices(for: language)
            .filter { $0.quality == .enhanced || $0.quality == .premium }
    }

    /// Get voice settings optimized for content type
    public static func settingsForContentType(_ type: String) -> VoiceSettings {
        switch type {
        case "meditation", "sleep_story", "mindfulness":
            return .meditation
        case "breathing":
            return .breathing
        case "affirmation":
            return .affirmation
        case "grounding":
            return .grounding
        default:
            return .calm
        }
    }

    // MARK: - Private Methods

    private func configureAudioSession() -> Bool {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            self.error = "Unable to start audio. Try again."
            return false
        }
        #endif
        return true
    }

    private func sanitizeText(_ text: String) -> String {
        // Remove markdown-style markers
        var sanitized = text
            .replacingOccurrences(of: "[pause]", with: "...")
            .replacingOccurrences(of: "[inhale", with: "Breathe in")
            .replacingOccurrences(of: "[exhale", with: "Breathe out")
            .replacingOccurrences(of: "[hold", with: "Hold")
            .replacingOccurrences(of: "]", with: ".")

        // Remove other control characters
        sanitized = sanitized.components(separatedBy: CharacterSet.controlCharacters).joined(separator: " ")

        // Normalize whitespace
        sanitized = sanitized.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return sanitized
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension NativeTTSService: AVSpeechSynthesizerDelegate {

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.currentUtterance === utterance else { return }
            self.isPreparing = false
            if self.isPaused {
                self.synthesizer.pauseSpeaking(at: .immediate)
            }
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.currentUtterance === utterance else { return }
            self.currentUtterance = nil
            self.isPreparing = false
            self.isSpeaking = false
            self.isPaused = false
            self.progress = 1.0
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.currentUtterance === utterance else { return }
            if self.isPaused {
                self.synthesizer.pauseSpeaking(at: .immediate)
            }
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.currentUtterance === utterance else { return }
            self.currentUtterance = nil
            self.isPreparing = false
            self.isSpeaking = false
            self.isPaused = false
            self.progress = 0.0
            self.error = "Speech stopped. Try again."
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.currentUtterance === utterance else { return }
            self.spokenCharacters = characterRange.location + characterRange.length
            if self.totalCharacters > 0 {
                self.progress = min(1, Double(self.spokenCharacters) / Double(self.totalCharacters))
            }
        }
    }
}
