import SwiftUI
import AVFoundation

struct VoiceJournalRecorderView: View {
    @Environment(\.supportRootEmbedded) private var supportRootEmbedded
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recorder = VoiceJournalRecorder()
    @State private var savedWork: CreativeWork?
    @State private var savedAudio: Data?
    @State private var showAnalysis = false
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        SupportRootNavigation(embedded: supportRootEmbedded) {
            VStack(spacing: SupportTheme.Spacing.xl) {
                Spacer()

                // Instructions
                if !recorder.isRecording && !recorder.hasRecording {
                    VStack(spacing: SupportTheme.Spacing.xs) {
                        Text("Voice Journal")
                            .font(.title2.bold())
                        Text("Speak your thoughts freely. You can explore an AI interpretation of the transcript; it can be wrong.")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, SupportTheme.Spacing.xl)
                    }
                }

                // Waveform Visualization
                WaveformVisualization(levels: recorder.audioLevels, isRecording: recorder.isRecording)
                    .frame(height: 80)
                    .padding(.horizontal, SupportTheme.Spacing.m)

                // Timer
                Text(recorder.formattedDuration)
                    .font(.system(.largeTitle, design: .monospaced).weight(.light))
                    .foregroundStyle(recorder.isRecording ? .primary : SupportTheme.textSecondary)

                // Status
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)

                Spacer()

                // Controls
                HStack(spacing: SupportTheme.Spacing.xl) {
                    // Playback button (only when recording exists)
                    if recorder.hasRecording {
                        Button {
                            recorder.togglePlayback()
                        } label: {
                            Image(systemName: recorder.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title)
                                .frame(width: 60, height: 60)
                                .background(SupportTheme.surface)
                                .clipShape(Circle())
                            .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        }
                        .accessibilityLabel(recorder.isPlaying ? "Pause playback" : "Play recording")
                    }

                    // Record button
                    Button {
                        if recorder.isRecording {
                            recorder.stopRecording()
                        } else if !recorder.hasRecording {
                            Task { await recorder.startRecording() }
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(recorder.isRecording ? Color.red : SupportTheme.accent)
                                .frame(width: 80, height: 80)

                            if recorder.isRecording {
                                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                    .fill(SupportTheme.surface)
                                    .frame(width: 28, height: 28)
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.title)
                                    .foregroundStyle(SupportTheme.textPrimary)
                            }
                        }
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    }
                    .disabled(recorder.hasRecording && !recorder.isRecording)
                    .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")

                    // Save button (only when recording exists)
                    if recorder.hasRecording && !recorder.isRecording {
                        Button {
                            Task { await saveRecording() }
                        } label: {
                            Group {
                                if isSaving {
                                    ProgressView()
                                        .tint(SupportTheme.accent)
                                } else {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .font(.title)
                            .frame(width: 60, height: 60)
                            .background(SupportTheme.accent)
                            .foregroundStyle(SupportTheme.onAccent)
                            .clipShape(Circle())
                            .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        }
                        .disabled(isSaving)
                        .accessibilityLabel("Save recording")
                    }
                }

                // Delete and restart option
                if recorder.hasRecording && !recorder.isRecording {
                    Button(role: .destructive) {
                        recorder.deleteRecording()
                    } label: {
                        Label("Discard & Record Again", systemImage: "trash")
                            .font(.subheadline)
                    }
                    .padding(.top, SupportTheme.Spacing.xs)
                }

                Spacer()

                // Quota info
                Text("Free: 5 min/day • Premium: 60 min/day")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            .padding(SupportTheme.Spacing.m)
            .background(SupportTheme.canvas)
            .sentryMask()  // Voice journal content is highly sensitive PHI
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        recorder.cleanup()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if error != nil {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        if let error = error {
                            Text(error)
                        }

                        Button("OK") { error = nil }
                    }
                    .foregroundStyle(SupportTheme.textSecondary)
                    .buttonStyle(.supportSecondary)
                    .supportCard()
                    .padding(SupportTheme.Spacing.m)
                }
            }
            .sheet(isPresented: $showAnalysis) {
                if let work = savedWork {
                    VoiceJournalAnalysisView(work: work, analyzeOnOpen: true, originalAudio: savedAudio)
                }
            }
            .onDisappear {
                recorder.cleanup()
            }
        }
    }

    private var statusText: String {
        if recorder.isRecording {
            return "Recording..."
        } else if recorder.isPlaying {
            return "Playing..."
        } else if recorder.hasRecording {
            return "Ready to save"
        } else {
            return "Tap to start recording"
        }
    }

    private func saveRecording() async {
        guard let audioData = recorder.getRecordingData() else {
            error = "Failed to get recording data"
            return
        }

        let durationSeconds = Int(ceil(recorder.duration))
        isSaving = true

        do {
            let work = try await container.creativeExpressionService.createVoiceJournal(
                audioData: audioData,
                durationSeconds: durationSeconds
            )

            savedWork = work
            savedAudio = audioData
            showAnalysis = true

        } catch CreativeError.quotaExceeded {
            error = "You've reached your daily voice journal limit. Upgrade to premium for more."
            appState.showPaywall = true
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }
}

// MARK: - Voice Journal Recorder

@MainActor
class VoiceJournalRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var duration: TimeInterval = 0
    @Published var audioLevels: [CGFloat] = Array(repeating: 0.1, count: 40)
    @Published var hasRecording = false

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var levelTimer: Timer?
    private var recordingURL: URL?

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func startRecording() async {
        // Request permission
        let permission = await AVAudioApplication.requestRecordPermission()
        guard permission else {
            Log.voice.error("Microphone permission denied")
            return
        }

        // Configure audio session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            Log.voice.error("Audio session setup failed", error: error)
            return
        }

        // Create recording URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingURL = documentsPath.appendingPathComponent("voice_journal_\(UUID().uuidString).m4a")

        guard let url = recordingURL else { return }

        // Configure recorder
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            guard audioRecorder?.record(forDuration: 600) == true else { return }

            isRecording = true
            duration = 0
            hasRecording = false

            // Start duration timer
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    self.duration = self.audioRecorder?.currentTime ?? self.duration
                    if self.duration >= 600 { self.stopRecording() }
                }
            }

            // Start level meter
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updateAudioLevels()
                }
            }
        } catch {
            Log.voice.error("Recording failed to start", error: error)
        }
    }

    func stopRecording() {
        // currentTime resets after stop; retain the measured fraction before closing the file.
        if let audioRecorder, audioRecorder.isRecording { duration = audioRecorder.currentTime }
        audioRecorder?.stop()
        if let recordingURL, let file = try? AVAudioFile(forReading: recordingURL) {
            duration = Double(file.length) / file.processingFormat.sampleRate
        }
        timer?.invalidate()
        levelTimer?.invalidate()
        timer = nil
        levelTimer = nil
        isRecording = false
        hasRecording = recordingURL != nil

        // Reset levels
        audioLevels = Array(repeating: 0.1, count: 40)
    }

    func togglePlayback() {
        if isPlaying {
            audioPlayer?.stop()
            isPlaying = false
        } else {
            playRecording()
        }
    }

    private func playRecording() {
        guard let url = recordingURL else { return }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
        } catch {
            Log.voice.error("Playback failed", error: error)
        }
    }

    func deleteRecording() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        hasRecording = false
        duration = 0
        audioLevels = Array(repeating: 0.1, count: 40)
    }

    func getRecordingData() -> Data? {
        guard let url = recordingURL else { return nil }
        return try? Data(contentsOf: url)
    }

    func cleanup() {
        audioRecorder?.stop()
        audioPlayer?.stop()
        timer?.invalidate()
        levelTimer?.invalidate()
        deleteRecording()
    }

    private func updateAudioLevels() {
        guard let recorder = audioRecorder, isRecording else { return }

        recorder.updateMeters()
        let level = recorder.averagePower(forChannel: 0)
        let normalizedLevel = max(0, (level + 60) / 60) // Normalize from -60...0 to 0...1

        // Shift levels and add new one
        audioLevels.removeFirst()
        audioLevels.append(CGFloat(normalizedLevel))
    }
}

extension VoiceJournalRecorder: AVAudioPlayerDelegate, AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.isRecording else { return }
            self.stopRecording()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
        }
    }
}

// MARK: - Waveform Visualization

struct WaveformVisualization: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let levels: [CGFloat]
    let isRecording: Bool

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                    .fill(isRecording ? Color.red : SupportTheme.accent)
                    .frame(width: 4, height: max(4, level * 60))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: level)
            }
        }
    }
}

// MARK: - Voice Journal Analysis View

struct VoiceJournalAnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var container: DependencyContainer

    let work: CreativeWork
    var analyzeOnOpen = false
    var originalAudio: Data?
    @State private var analysis: VoiceJournalAnalysis?
    @State private var isLoading = true
    @State private var analysisError: String?
    @State private var analysisAttempt = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.m) {
                    if isLoading {
                        VStack(spacing: SupportTheme.Spacing.m) {
                            ProgressView()
                            Text("Analyzing your voice journal...")
                                .font(.subheadline)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, SupportTheme.Spacing.xl)
                    } else if let analysis = analysis {
                        analysisContent(analysis)
                    } else {
                        ContentUnavailableView {
                            Label("Voice Journal Analysis", systemImage: "waveform")
                        } description: {
                            Text(analysisError ?? "Analyze your saved recording for themes and reflection prompts.")
                        } actions: {
                            Button("Analyze Recording") { analysisAttempt += 1 }
                        }
                    }
                }
                .padding(SupportTheme.Spacing.m)
            }
            .sentryMask()  // Voice journal analysis contains highly sensitive PHI
            .supportScreen()
            .navigationTitle("Voice Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: analysisAttempt) {
                if analyzeOnOpen || analysisAttempt > 0 { await analyzeRecording() }
                else { await loadAnalysis() }
            }
        }
    }

    @ViewBuilder
    private func analysisContent(_ analysis: VoiceJournalAnalysis) -> some View {
        // Summary
        if let summary = analysis.aiSummary {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                Label("Summary", systemImage: "text.quote")
                    .font(.headline)
                Text(summary)
                    .font(.body)
            }
            .padding(SupportTheme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SupportTheme.surface)
            .cornerRadius(SupportTheme.controlRadius)
        }

        // Sentiment
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Label("Sentiment", systemImage: "face.smiling")
                .font(.headline)

            HStack {
                Text("Negative")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                            .fill(SupportTheme.separator)

                        RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                            .fill(sentimentColor(analysis.overallSentiment))
                            .frame(width: geometry.size.width * CGFloat((analysis.overallSentiment + 1) / 2))
                    }
                }
                .frame(height: 8)

                Text("Positive")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .padding(SupportTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)

        // Emotions
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Label("Possible emotions in the wording", systemImage: "heart")
                .accessibilityHint("AI interpretation of the transcript, not an emotion measurement")
                .font(.headline)

            Text("AI interpretation of transcript language. It can be wrong and does not measure your voice or how you feel.")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: SupportTheme.Spacing.xs) {
                ForEach(Array(analysis.emotions.asDictionary.sorted(by: { $0.value > $1.value })), id: \.key) { emotion, value in
                    AnalysisEmotionBadge(emotion: emotion, value: value)
                }
            }
        }
        .padding(SupportTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)

        // Key Themes
        if !analysis.keyThemes.isEmpty {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                Label("Key Themes", systemImage: "tag")
                    .font(.headline)

                FlowLayout(spacing: SupportTheme.Spacing.xs) {
                    ForEach(analysis.keyThemes, id: \.self) { theme in
                        Text(theme)
                            .font(.caption)
                            .padding(.horizontal, SupportTheme.Spacing.s)
                            .padding(.vertical, SupportTheme.Spacing.xxs)
                            .background(SupportTheme.surface)
                            .cornerRadius(SupportTheme.cardRadius)
                    }
                }
            }
            .padding(SupportTheme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SupportTheme.surface)
            .cornerRadius(SupportTheme.controlRadius)
        }

        // Reflection Prompts
        if !analysis.reflectionPrompts.isEmpty {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                Label("Reflection Prompts", systemImage: "lightbulb")
                    .font(.headline)

                ForEach(analysis.reflectionPrompts, id: \.self) { prompt in
                    HStack(alignment: .top, spacing: SupportTheme.Spacing.xs) {
                        Image(systemName: "circle.fill")
                            .font(.system(.caption2))
                            .padding(.top, SupportTheme.Spacing.xxs)
                            .foregroundStyle(SupportTheme.textSecondary)
                        Text(prompt)
                            .font(.subheadline)
                    }
                }
            }
            .padding(SupportTheme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SupportTheme.surface)
            .cornerRadius(SupportTheme.controlRadius)
        }

        // Transcription
        if let transcription = analysis.fullTranscription {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                Label("Transcription", systemImage: "text.alignleft")
                    .font(.headline)
                Text(transcription)
                    .font(.body)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            .padding(SupportTheme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SupportTheme.surface)
            .cornerRadius(SupportTheme.controlRadius)
        }
    }

    private func sentimentColor(_ sentiment: Double) -> Color {
        if sentiment < -0.3 {
            return .red
        } else if sentiment > 0.3 {
            return SupportTheme.accent
        } else {
            return SupportTheme.accent
        }
    }

    private func loadAnalysis() async {
        isLoading = true
        defer { isLoading = false }

        do {
            analysis = try await container.creativeExpressionService.fetchVoiceAnalysis(workId: work.id)
        } catch { /* A saved recording can explicitly start or retry analysis below. */ }
    }

    private func analyzeRecording() async {
        isLoading = true
        analysisError = nil
        defer { isLoading = false }
        do {
            analysis = try await container.creativeExpressionService.analyzeVoiceJournal(
                workId: work.id, durationSeconds: work.durationSeconds ?? 1, originalAudio: originalAudio
            )
        } catch {
            guard !Task.isCancelled else { return }
            if case CreativeError.quotaExceeded = error {
                analysisError = "You've reached your daily voice journal analysis limit. Your recording is saved."
            } else {
                analysisError = (error as? CreativeError)?.localizedDescription
                    ?? "Analysis could not be completed. Your recording is saved; try again when available."
            }
        }
    }
}

// MARK: - Analysis Emotion Badge

/// Compact emotion badge for voice analysis display
/// Different from VoiceMode EmotionBadge which handles EmotionSnapshot
private struct AnalysisEmotionBadge: View {
    let emotion: String
    let value: Double

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            Text(emotionEmoji)
            Text(emotion.capitalized)
                .font(.caption)
        }
        .padding(.horizontal, SupportTheme.Spacing.xs)
        .padding(.vertical, SupportTheme.Spacing.xxs)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)
    }

    private var emotionEmoji: String {
        switch emotion.lowercased() {
        case "joy": return "😊"
        case "sadness": return "😢"
        case "anger": return "😠"
        case "fear": return "😨"
        case "surprise": return "😮"
        case "trust": return "🤝"
        case "anticipation": return "🤔"
        case "disgust": return "😖"
        default: return "😐"
        }
    }
}

struct EmotionPercentageBadge: View {
    let emotion: String
    let value: Double

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            Text(emotionEmoji)
            Text(emotion.capitalized)
                .font(.caption)
            Text("\(Int(value * 100))%")
                .font(.caption2)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .padding(.horizontal, SupportTheme.Spacing.xs)
        .padding(.vertical, SupportTheme.Spacing.xxs)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)
    }

    private var emotionEmoji: String {
        switch emotion.lowercased() {
        case "joy": return "😊"
        case "sadness": return "😢"
        case "anger": return "😠"
        case "fear": return "😨"
        case "surprise": return "😮"
        case "trust": return "🤝"
        case "anticipation": return "🤔"
        case "disgust": return "😖"
        default: return "😐"
        }
    }
}

#Preview {
    VoiceJournalRecorderView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
