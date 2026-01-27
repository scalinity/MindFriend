import AVFoundation
import Combine

/// Native iOS Text-to-Speech Service using AVSpeechSynthesizer
/// Used for free tier users instead of ElevenLabs (zero cost)
@MainActor
public final class NativeTTSService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published public private(set) var isSpeaking: Bool = false
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var progress: Double = 0.0
    @Published public private(set) var currentText: String = ""

    // MARK: - Private Properties

    private let synthesizer = AVSpeechSynthesizer()
    private var totalCharacters: Int = 0
    private var spokenCharacters: Int = 0
    private var progressTimer: Timer?

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
        configureAudioSession()
    }

    // MARK: - Public Methods

    /// Speak text content with optional voice settings
    public func speak(_ text: String, settings: VoiceSettings = .calm) {
        stop()

        guard !text.isEmpty else { return }

        let sanitizedText = sanitizeText(text)
        currentText = sanitizedText
        totalCharacters = sanitizedText.count
        spokenCharacters = 0
        progress = 0.0

        let utterance = AVSpeechUtterance(string: sanitizedText)
        utterance.rate = settings.rate
        utterance.pitchMultiplier = settings.pitch
        utterance.volume = settings.volume
        utterance.preUtteranceDelay = 0.2
        utterance.postUtteranceDelay = 0.1

        // Select voice
        if let identifier = settings.voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        } else if let voice = AVSpeechSynthesisVoice(language: settings.language) {
            utterance.voice = voice
        }

        isSpeaking = true
        isPaused = false
        synthesizer.speak(utterance)
    }

    /// Pause current speech
    public func pause() {
        guard isSpeaking, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    /// Resume paused speech
    public func resume() {
        guard isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
    }

    /// Stop current speech
    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        progress = 0.0
        currentText = ""
        spokenCharacters = 0
        totalCharacters = 0
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

    private func configureAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("NativeTTSService: Failed to configure audio session: \(error)")
        }
        #endif
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
        sanitized = sanitized.components(separatedBy: CharacterSet.controlCharacters).joined()

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
            self.isSpeaking = true
            self.isPaused = false
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
            self.progress = 1.0
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPaused = true
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPaused = false
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
            self.progress = 0.0
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.spokenCharacters = characterRange.location + characterRange.length
            if self.totalCharacters > 0 {
                self.progress = Double(self.spokenCharacters) / Double(self.totalCharacters)
            }
        }
    }
}
