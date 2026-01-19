import SwiftUI
import AVFoundation

struct VoiceJournalRecorderView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recorder = VoiceJournalRecorder()
    @State private var savedWork: CreativeWork?
    @State private var showAnalysis = false
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Instructions
                if !recorder.isRecording && !recorder.hasRecording {
                    VStack(spacing: 8) {
                        Text("Voice Journal")
                            .font(.title2.bold())
                        Text("Speak your thoughts freely. Your recording will be analyzed for emotional insights.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }

                // Waveform Visualization
                WaveformVisualization(levels: recorder.audioLevels, isRecording: recorder.isRecording)
                    .frame(height: 80)
                    .padding(.horizontal)

                // Timer
                Text(recorder.formattedDuration)
                    .font(.system(size: 56, weight: .light, design: .monospaced))
                    .foregroundStyle(recorder.isRecording ? .primary : .secondary)

                // Status
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                // Controls
                HStack(spacing: 40) {
                    // Playback button (only when recording exists)
                    if recorder.hasRecording {
                        Button {
                            recorder.togglePlayback()
                        } label: {
                            Image(systemName: recorder.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title)
                                .frame(width: 60, height: 60)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Circle())
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
                                .fill(recorder.isRecording ? Color.red : Color.accentColor)
                                .frame(width: 80, height: 80)

                            if recorder.isRecording {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white)
                                    .frame(width: 28, height: 28)
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.title)
                                    .foregroundStyle(.white)
                            }
                        }
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
                                        .tint(.white)
                                } else {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .font(.title)
                            .frame(width: 60, height: 60)
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .clipShape(Circle())
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
                    .padding(.top, 8)
                }

                Spacer()

                // Quota info
                Text("Free: 5 min/day • Premium: 60 min/day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
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
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                if let error = error {
                    Text(error)
                }
            }
            .sheet(isPresented: $showAnalysis) {
                if let work = savedWork {
                    VoiceJournalAnalysisView(work: work)
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

        isSaving = true

        do {
            let work = try await container.creativeExpressionService.createVoiceJournal(
                audioData: audioData,
                durationSeconds: Int(recorder.duration)
            )

            savedWork = work
            showAnalysis = true

            // Trigger analysis in background
            Task {
                _ = try? await container.creativeExpressionService.analyzeVoiceJournal(
                    workId: work.id,
                    durationSeconds: Int(recorder.duration)
                )
            }
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
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            isRecording = true
            duration = 0
            hasRecording = false

            // Start duration timer
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.duration += 1
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
        audioRecorder?.stop()
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

extension VoiceJournalRecorder: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
        }
    }
}

// MARK: - Waveform Visualization

struct WaveformVisualization: View {
    let levels: [CGFloat]
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(isRecording ? Color.red : Color.accentColor)
                    .frame(width: 4, height: max(4, level * 60))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
    }
}

// MARK: - Voice Journal Analysis View

struct VoiceJournalAnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var container: DependencyContainer

    let work: CreativeWork
    @State private var analysis: VoiceJournalAnalysis?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Analyzing your voice journal...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else if let analysis = analysis {
                        analysisContent(analysis)
                    } else {
                        ContentUnavailableView(
                            "Analysis Pending",
                            systemImage: "waveform",
                            description: Text("Your recording is being processed. Check back soon.")
                        )
                    }
                }
                .padding()
            }
            .sentryMask()  // Voice journal analysis contains highly sensitive PHI
            .navigationTitle("Voice Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadAnalysis()
            }
        }
    }

    @ViewBuilder
    private func analysisContent(_ analysis: VoiceJournalAnalysis) -> some View {
        // Summary
        if let summary = analysis.aiSummary {
            VStack(alignment: .leading, spacing: 8) {
                Label("Summary", systemImage: "text.quote")
                    .font(.headline)
                Text(summary)
                    .font(.body)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }

        // Sentiment
        VStack(alignment: .leading, spacing: 8) {
            Label("Sentiment", systemImage: "face.smiling")
                .font(.headline)

            HStack {
                Text("Negative")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray4))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(sentimentColor(analysis.overallSentiment))
                            .frame(width: geometry.size.width * CGFloat((analysis.overallSentiment + 1) / 2))
                    }
                }
                .frame(height: 8)

                Text("Positive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)

        // Emotions
        VStack(alignment: .leading, spacing: 12) {
            Label("Emotions Detected", systemImage: "heart")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                ForEach(Array(analysis.emotions.asDictionary.sorted(by: { $0.value > $1.value })), id: \.key) { emotion, value in
                    EmotionBadge(emotion: emotion, value: value)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)

        // Key Themes
        if !analysis.keyThemes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Key Themes", systemImage: "tag")
                    .font(.headline)

                FlowLayout(spacing: 8) {
                    ForEach(analysis.keyThemes, id: \.self) { theme in
                        Text(theme)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(16)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }

        // Reflection Prompts
        if !analysis.reflectionPrompts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Reflection Prompts", systemImage: "lightbulb")
                    .font(.headline)

                ForEach(analysis.reflectionPrompts, id: \.self) { prompt in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .padding(.top, 6)
                            .foregroundStyle(.secondary)
                        Text(prompt)
                            .font(.subheadline)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }

        // Transcription
        if let transcription = analysis.fullTranscription {
            VStack(alignment: .leading, spacing: 8) {
                Label("Transcription", systemImage: "text.alignleft")
                    .font(.headline)
                Text(transcription)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }

    private func sentimentColor(_ sentiment: Double) -> Color {
        if sentiment < -0.3 {
            return .red
        } else if sentiment > 0.3 {
            return .green
        } else {
            return .orange
        }
    }

    private func loadAnalysis() async {
        isLoading = true
        defer { isLoading = false }

        do {
            analysis = try await container.creativeExpressionService.fetchVoiceAnalysis(workId: work.id)
        } catch {
            Log.creative.error("Failed to load analysis", error: error)
        }
    }
}

struct EmotionBadge: View {
    let emotion: String
    let value: Double

    var body: some View {
        HStack(spacing: 4) {
            Text(emotionEmoji)
            Text(emotion.capitalized)
                .font(.caption)
            Text("\(Int(value * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
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
