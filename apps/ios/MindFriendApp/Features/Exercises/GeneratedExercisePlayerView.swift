import SwiftUI
import AVFoundation

/// Unified player view for generated exercises with type-specific rendering
struct GeneratedExercisePlayerView: View {
    let content: GeneratedContent
    @StateObject private var viewModel: ExercisePlayerViewModel
    @Environment(\.dismiss) private var dismiss

    init(content: GeneratedContent, container: DependencyContainer) {
        self.content = content
        _viewModel = StateObject(wrappedValue: ExercisePlayerViewModel(
            content: content,
            dataService: container.supabaseDataService
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Type-specific player
                Group {
                    switch content.contentType {
                    case .breathing:
                        if let exercise = content.exerciseContent,
                           case .breathing(let breathingEx) = exercise {
                            BreathingPlayerView(
                                exercise: breathingEx,
                                viewModel: viewModel
                            )
                        } else {
                            textPlayerView
                        }

                    case .meditation, .grounding, .mindfulness:
                        if let exercise = content.exerciseContent {
                            switch exercise {
                            case .meditation(let meditationEx):
                                MeditationPlayerView(
                                    exercise: meditationEx,
                                    viewModel: viewModel
                                )
                            case .grounding(let groundingEx):
                                GroundingPlayerView(
                                    exercise: groundingEx,
                                    viewModel: viewModel
                                )
                            default:
                                textPlayerView
                            }
                        } else {
                            textPlayerView
                        }

                    case .journaling:
                        if let exercise = content.exerciseContent,
                           case .journaling(let journalingEx) = exercise {
                            JournalingPlayerView(
                                exercise: journalingEx,
                                viewModel: viewModel
                            )
                        } else {
                            textPlayerView
                        }

                    default:
                        textPlayerView
                    }
                }
            }
            .supportScreen()
            .navigationTitle(content.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        viewModel.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { viewModel.showRatingPrompt = true }) {
                        Image(systemName: content.userRating != nil ? "star.fill" : "star")
                            .foregroundColor(SupportTheme.accent)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showRatingPrompt) {
                RatingPromptView(
                    content: content,
                    onRate: { rating, feedback in
                        Task {
                            await viewModel.submitRating(rating, feedback: feedback)
                        }
                    },
                    onDismiss: { viewModel.showRatingPrompt = false }
                )
            }
            .onAppear {
                viewModel.start()
            }
            .onDisappear {
                viewModel.stop()
            }
        }
    }

    /// Text-based player with audio playback for generated exercises
    private var textPlayerView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                    // Content type badge
                    HStack {
                        Image(systemName: content.contentType.icon)
                            .foregroundColor(SupportTheme.accent)
                        Text(content.contentType.displayName)
                            .font(.subheadline)
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                    .padding(.bottom, SupportTheme.Spacing.xxs)

                    Text(content.textContent)
                        .font(.body)
                        .lineSpacing(6)
                }
                .padding(SupportTheme.Spacing.m)
            }

            Divider()

            // Playback controls
            VStack(spacing: SupportTheme.Spacing.s) {
                // Progress bar
                if viewModel.isAudioPlaying {
                    ProgressView(value: viewModel.audioProgress)
                        .tint(SupportTheme.accent)

                    // Time display
                    HStack {
                        Text(viewModel.audioElapsedFormatted)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(SupportTheme.textSecondary)
                        Spacer()
                        Text(viewModel.audioRemainingFormatted)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                }

                HStack(spacing: SupportTheme.Spacing.l) {
                    // Play/Stop button
                    Button(action: {
                        if viewModel.isAudioPlaying {
                            viewModel.stopAudio()
                        } else {
                            viewModel.playAudio(for: content)
                        }
                    }) {
                        HStack(spacing: SupportTheme.Spacing.xs) {
                            Image(systemName: viewModel.isAudioPlaying ? "stop.fill" : "play.fill")
                            Text(viewModel.isAudioPlaying ? "Stop" : (content.hasAudio ? "Play Audio" : "Read Aloud"))
                                .font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SupportTheme.Spacing.s)
                        .background(SupportTheme.accent)
                        .foregroundStyle(SupportTheme.onAccent)
                        .cornerRadius(SupportTheme.controlRadius)
                    }

                    // Done button
                    Button(action: {
                        viewModel.stopAudio()
                        viewModel.showRatingPrompt = true
                    }) {
                        HStack(spacing: SupportTheme.Spacing.xs) {
                            Image(systemName: "checkmark")
                            Text("Done")
                                .font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SupportTheme.Spacing.s)
                        .background(SupportTheme.separator)
                        .foregroundStyle(SupportTheme.textPrimary)
                        .cornerRadius(SupportTheme.controlRadius)
                    }
                }
            }
            .padding(SupportTheme.Spacing.m)
            .background(SupportTheme.canvas)
        }
    }
}

// MARK: - Breathing Player

struct BreathingPlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let exercise: ExerciseContent.BreathingExercise
    @ObservedObject var viewModel: ExercisePlayerViewModel

    var body: some View {
        ZStack {
            // Gradient background that changes with phase
            SupportTheme.canvas
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: viewModel.breathingPhase)

            VStack(spacing: SupportTheme.Spacing.xl) {
                Spacer()

                // Phase text
                Text(viewModel.breathingPhaseText)
                    .font(.title.weight(.medium))
                    .id(viewModel.breathingPhaseText)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.breathingPhaseText)
                    .foregroundColor(SupportTheme.textPrimary)

                // Animated breathing circle
                Circle()
                    .fill(SupportTheme.accent.opacity(0.3))
                    .frame(width: 200, height: 200)
                    .scaleEffect(reduceMotion ? 1 : (viewModel.breathingCircleScale))

                // Timer
                Text(viewModel.timeRemainingFormatted)
                    .font(.system(.largeTitle, design: .rounded).weight(.light))
                    .foregroundColor(SupportTheme.textPrimary)
                    .monospacedDigit()

                // Cycle counter
                Text("Cycle \(viewModel.currentCycle) of \(exercise.cycles)")
                    .font(.subheadline)
                    .foregroundColor(SupportTheme.textPrimary.opacity(0.7))

                Spacer()

                // Controls
                HStack(spacing: SupportTheme.Spacing.xl) {
                    Button(action: viewModel.togglePlayPause) {
                        Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(.largeTitle))
                            .foregroundColor(SupportTheme.textPrimary)
                    }
                }
                .padding(.bottom, SupportTheme.Spacing.xl)
            }
        }
    }
}

// MARK: - Meditation/Mindfulness Player

struct MeditationPlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let exercise: ExerciseContent.MeditationExercise
    @ObservedObject var viewModel: ExercisePlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable script
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                        ForEach(Array(exercise.script.enumerated()), id: \.offset) { index, segment in
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                                Text(segment.text)
                                    .font(.body)
                                    .foregroundColor(index == viewModel.currentSegmentIndex ? .primary : SupportTheme.textSecondary)
                            }
                            .id(index)
                            .padding(.horizontal, SupportTheme.Spacing.m)
                        }
                    }
                    .padding(.vertical, SupportTheme.Spacing.m)
                }
                .onChange(of: viewModel.currentSegmentIndex) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(viewModel.currentSegmentIndex, anchor: .center)
                    }
                }
            }

            Divider()

            // Playback controls
            controlsView
        }
    }

    private var controlsView: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            // Progress bar
            ProgressView(value: viewModel.progress)
                .tint(SupportTheme.accent)

            // Time display
            HStack {
                Text(viewModel.elapsedTimeFormatted)
                Spacer()
                Text(viewModel.timeRemainingFormatted)
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(SupportTheme.textSecondary)

            // Play/Pause button
            Button(action: viewModel.togglePlayPause) {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(.largeTitle))
            }
        }
        .padding(SupportTheme.Spacing.m)
        .background(SupportTheme.canvas)
    }
}

// MARK: - Grounding Player

struct GroundingPlayerView: View {
    let exercise: ExerciseContent.GroundingExercise
    @ObservedObject var viewModel: ExercisePlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Current prompt display
            ZStack {
                SupportTheme.separator
                    .ignoresSafeArea()

                if viewModel.currentSegmentIndex < exercise.prompts.count {
                    let prompt = exercise.prompts[viewModel.currentSegmentIndex]

                    VStack(spacing: SupportTheme.Spacing.l) {
                        if let sense = prompt.sense {
                            Image(systemName: senseIcon(for: sense))
                                .font(.system(.largeTitle))
                                .foregroundColor(SupportTheme.accent)
                        }

                        Text(prompt.text)
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .padding(SupportTheme.Spacing.m)
                    }
                }
            }

            Divider()

            // Controls
            VStack(spacing: SupportTheme.Spacing.m) {
                // Progress
                HStack {
                    Text("Step \(viewModel.currentSegmentIndex + 1) of \(exercise.prompts.count)")
                        .font(.subheadline)
                        .foregroundColor(SupportTheme.textSecondary)
                    Spacer()
                    Text(viewModel.timeRemainingFormatted)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(SupportTheme.textSecondary)
                }

                // Buttons
                HStack(spacing: SupportTheme.Spacing.m) {
                    Button("Previous") {
                        viewModel.previousSegment()
                    }
                    .disabled(viewModel.currentSegmentIndex == 0)

                    Button(action: viewModel.togglePlayPause) {
                        Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(.largeTitle))
                    }

                    Button("Next") {
                        viewModel.nextSegment()
                    }
                    .disabled(viewModel.currentSegmentIndex >= exercise.prompts.count - 1)
                }
            }
            .padding(SupportTheme.Spacing.m)
            .background(SupportTheme.canvas)
        }
    }

    private func senseIcon(for sense: String) -> String {
        switch sense.lowercased() {
        case "sight": return "eye.fill"
        case "touch": return "hand.raised.fill"
        case "hearing": return "ear.fill"
        case "smell": return "nose.fill"
        case "taste": return "mouth.fill"
        default: return "sparkles"
        }
    }
}

// MARK: - Journaling Player

struct JournalingPlayerView: View {
    let exercise: ExerciseContent.JournalingExercise
    @ObservedObject var viewModel: ExercisePlayerViewModel

    @State private var responses: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                // Header
                Text("Journaling Prompts")
                    .font(.title2.bold())
                    .padding(.horizontal, SupportTheme.Spacing.m)

                // Prompts
                ForEach(Array(exercise.prompts.enumerated()), id: \.offset) { index, prompt in
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        HStack {
                            Text(prompt.category.capitalized)
                                .font(.caption)
                                .padding(.horizontal, SupportTheme.Spacing.xs)
                                .padding(.vertical, SupportTheme.Spacing.xxs)
                                .background(SupportTheme.surface)
                                .foregroundColor(SupportTheme.accent)
                                .cornerRadius(SupportTheme.controlRadius)

                            Spacer()

                            Text("\(index + 1)/\(exercise.prompts.count)")
                                .font(.caption)
                                .foregroundColor(SupportTheme.textSecondary)
                        }

                        Text(prompt.text)
                            .font(.headline)

                        TextEditor(text: binding(for: index))
                            .frame(height: 120)
                            .padding(SupportTheme.Spacing.xs)
                            .background(SupportTheme.separator)
                            .cornerRadius(SupportTheme.controlRadius)
                    }
                    .padding(.horizontal, SupportTheme.Spacing.m)
                }

                // Reflection questions
                if !exercise.reflectionQuestions.isEmpty {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Text("Reflection Questions")
                            .font(.headline)
                            .padding(.horizontal, SupportTheme.Spacing.m)

                        ForEach(exercise.reflectionQuestions, id: \.self) { question in
                            HStack(alignment: .top, spacing: SupportTheme.Spacing.xs) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(SupportTheme.accent)
                                    .font(.caption)

                                Text(question)
                                    .font(.subheadline)
                                    .foregroundColor(SupportTheme.textSecondary)
                            }
                            .padding(.horizontal, SupportTheme.Spacing.m)
                        }
                    }
                    .padding(.vertical, SupportTheme.Spacing.m)
                }

                // Done button
                Button("Complete") {
                    viewModel.showRatingPrompt = true
                }
                .buttonStyle(.supportPrimary)
                .padding(SupportTheme.Spacing.m)
            }
            .padding(.vertical, SupportTheme.Spacing.m)
        }
        .onAppear {
            responses = Array(repeating: "", count: exercise.prompts.count)
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard index < responses.count else { return "" }
                return responses[index]
            },
            set: { newValue in
                if index < responses.count {
                    responses[index] = newValue
                }
            }
        )
    }
}

// MARK: - Rating Prompt

struct RatingPromptView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: GeneratedContent
    let onRate: (Int, String?) -> Void
    let onDismiss: () -> Void

    @State private var rating: Int = 0
    @State private var feedback: String = ""
    @State private var showFeedback = false

    var body: some View {
        NavigationStack {
            VStack(spacing: SupportTheme.Spacing.l) {
                Text("How was this exercise?")
                    .font(.title2.weight(.semibold))

                // Star rating
                HStack(spacing: SupportTheme.Spacing.s) {
                    ForEach(1...5, id: \.self) { star in
                        Button(action: { rating = star }) {
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.largeTitle)
                                .foregroundColor(star <= rating ? .yellow : SupportTheme.textSecondary)
                        }
                    }
                }

                if rating > 0 {
                    Button(showFeedback ? "Hide Feedback" : "Add Feedback (Optional)") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showFeedback.toggle()
                        }
                    }
                    .font(.subheadline)

                    if showFeedback {
                        TextEditor(text: $feedback)
                            .frame(height: 100)
                            .padding(SupportTheme.Spacing.xs)
                            .background(SupportTheme.separator)
                            .cornerRadius(SupportTheme.controlRadius)
                    }

                    Button("Submit Rating") {
                        onRate(rating, feedback.isEmpty ? nil : feedback)
                        onDismiss()
                    }
                    .buttonStyle(.supportPrimary)
                }

                Button("Skip") {
                    onDismiss()
                }
                .font(.subheadline)
                .foregroundColor(SupportTheme.textSecondary)

                Spacer()
            }
            .padding(SupportTheme.Spacing.m)
            .supportScreen()
            .navigationTitle("Rate Exercise")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - ViewModel

@MainActor
class ExercisePlayerViewModel: ObservableObject {
    let content: GeneratedContent
    let dataService: SupabaseDataService

    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timeRemaining: TimeInterval = 0
    @Published var currentSegmentIndex = 0
    @Published var showRatingPrompt = false

    // Breathing-specific
    @Published var breathingPhase: BreathingPhase = .inhale
    @Published var breathingCircleScale: CGFloat = 0.5
    @Published var currentCycle: Int = 1

    // Audio playback for text-based player
    @Published var isAudioPlaying = false
    @Published var audioProgress: Double = 0
    @Published var audioElapsed: TimeInterval = 0
    @Published var audioDuration: TimeInterval = 0

    private var timer: Timer?
    private var breathingTimer: Timer?
    private var audioPlayer: AVPlayer?
    private var audioSetupTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var playerEndObserver: NSObjectProtocol?

    var audioElapsedFormatted: String {
        formatTime(audioElapsed)
    }

    var audioRemainingFormatted: String {
        let remaining = max(0, audioDuration - audioElapsed)
        return "-\(formatTime(remaining))"
    }

    var breathingPhaseText: String {
        switch breathingPhase {
        case .inhale: return "Breathe In"
        case .hold: return "Hold"
        case .exhale: return "Breathe Out"
        case .pause: return "Pause"
        }
    }

    var currentPhaseColors: [Color] {
        switch breathingPhase {
        case .inhale: return [SupportTheme.accent.opacity(0.6), SupportTheme.accent.opacity(0.4)]
        case .hold: return [SupportTheme.accent.opacity(0.5), SupportTheme.accent.opacity(0.4)]
        case .exhale: return [SupportTheme.accent.opacity(0.5), SupportTheme.accent.opacity(0.4)]
        case .pause: return [SupportTheme.accent.opacity(0.5), SupportTheme.accent.opacity(0.4)]
        }
    }

    var timeRemainingFormatted: String {
        formatTime(timeRemaining)
    }

    var elapsedTimeFormatted: String {
        formatTime(elapsedTime)
    }

    init(content: GeneratedContent, dataService: SupabaseDataService) {
        self.content = content
        self.dataService = dataService
        self.timeRemaining = TimeInterval(content.duration ?? 300)
    }

    func start() {
        guard !isPlaying else { return }

        if let exercise = content.exerciseContent {
            switch exercise {
            case .breathing(let breathingEx):
                startBreathingExercise(breathingEx)
            case .meditation, .grounding:
                startTimedExercise()
            case .journaling:
                // Journaling doesn't auto-play
                break
            }
        } else {
            startTimedExercise()
        }
    }

    func stop() {
        isPlaying = false
        timer?.invalidate()
        breathingTimer?.invalidate()
        timer = nil
        breathingTimer = nil
        stopAudio()
    }

    func togglePlayPause() {
        if isPlaying {
            stop()
        } else {
            start()
        }
    }

    func nextSegment() {
        currentSegmentIndex = min(currentSegmentIndex + 1, getSegmentCount() - 1)
    }

    func previousSegment() {
        currentSegmentIndex = max(currentSegmentIndex - 1, 0)
    }

    func submitRating(_ rating: Int, feedback: String?) async {
        do {
            try await dataService.rateContent(
                contentId: content.id.uuidString,
                rating: rating,
                feedback: feedback
            )
        } catch {
            print("Failed to submit rating: \(error)")
        }
    }

    func playAudio(for content: GeneratedContent) {
        audioSetupTask?.cancel()
        audioSetupTask = Task { [weak self] in await self?.startAudio(for: content) }
    }

    private func startAudio(for content: GeneratedContent) async {
        // Configure audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }

        if let urlString = content.audioUrl, let url = URL(string: urlString) {
            guard let accessURL = try? await SupabaseStorageMedia.resolve(url), !Task.isCancelled else { return }
            let playerItem = AVPlayerItem(url: accessURL)
            audioPlayer = AVPlayer(playerItem: playerItem)

            // Observe time progress
            let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
            timeObserver = audioPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self else { return }
                MainActor.assumeIsolated {
                    let elapsed = time.seconds
                    let duration = self.audioPlayer?.currentItem?.duration.seconds ?? 0
                    guard duration.isFinite && duration > 0 else { return }
                    self.audioElapsed = elapsed
                    self.audioDuration = duration
                    self.audioProgress = elapsed / duration
                }
            }

            // Observe playback end
            playerEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isAudioPlaying = false
                    self?.audioProgress = 1.0
                }
            }

            isAudioPlaying = true
            audioProgress = 0
            audioElapsed = 0
            audioPlayer?.play()
        } else {
            // Fallback: use native TTS when no audio URL available
            playNativeTTS(content.textContent)
        }
    }

    func stopAudio() {
        audioSetupTask?.cancel()
        audioSetupTask = nil
        // Stop AVPlayer
        audioPlayer?.pause()
        if let observer = timeObserver {
            audioPlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = playerEndObserver {
            NotificationCenter.default.removeObserver(observer)
            playerEndObserver = nil
        }
        audioPlayer = nil
        isAudioPlaying = false
        audioProgress = 0
        audioElapsed = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func playNativeTTS(_ text: String) {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        isAudioPlaying = true
        synthesizer.speak(utterance)
    }

    // MARK: - Private Methods

    private func startBreathingExercise(_ exercise: ExerciseContent.BreathingExercise) {
        isPlaying = true
        breathingPhase = .inhale
        currentCycle = 1
        animateBreathingPhase(exercise.pattern, phase: .inhale)
    }

    private func animateBreathingPhase(_ pattern: ExerciseContent.BreathingExercise.Pattern, phase: BreathingPhase) {
        guard isPlaying else { return }

        breathingPhase = phase

        let duration: Double
        let targetScale: CGFloat

        switch phase {
        case .inhale:
            duration = pattern.inhaleSeconds
            targetScale = 1.0
        case .hold:
            duration = pattern.holdInSeconds
            targetScale = 1.0
        case .exhale:
            duration = pattern.exhaleSeconds
            targetScale = 0.5
        case .pause:
            duration = pattern.holdOutSeconds
            targetScale = 0.5
        }

        withAnimation(.easeInOut(duration: duration)) {
            breathingCircleScale = targetScale
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.transitionBreathingPhase(pattern)
        }
    }

    private func transitionBreathingPhase(_ pattern: ExerciseContent.BreathingExercise.Pattern) {
        guard let exercise = content.exerciseContent,
              case .breathing(let breathingEx) = exercise else { return }

        switch breathingPhase {
        case .inhale:
            if pattern.holdInSeconds > 0 {
                animateBreathingPhase(pattern, phase: .hold)
            } else {
                animateBreathingPhase(pattern, phase: .exhale)
            }
        case .hold:
            animateBreathingPhase(pattern, phase: .exhale)
        case .exhale:
            if pattern.holdOutSeconds > 0 {
                animateBreathingPhase(pattern, phase: .pause)
            } else {
                completeCycle(breathingEx, pattern)
            }
        case .pause:
            completeCycle(breathingEx, pattern)
        }
    }

    private func completeCycle(_ exercise: ExerciseContent.BreathingExercise, _ pattern: ExerciseContent.BreathingExercise.Pattern) {
        if currentCycle >= exercise.cycles {
            stop()
            showRatingPrompt = true
        } else {
            currentCycle += 1
            animateBreathingPhase(pattern, phase: .inhale)
        }
    }

    private func startTimedExercise() {
        isPlaying = true

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                self.elapsedTime += 1
                self.timeRemaining = max(0, TimeInterval(self.content.duration ?? 300) - self.elapsedTime)
                self.progress = self.elapsedTime / TimeInterval(self.content.duration ?? 300)

                // Auto-advance segments
                if let exercise = self.content.exerciseContent {
                    switch exercise {
                    case .meditation(let meditationEx):
                        self.updateMeditationSegment(meditationEx)
                    case .grounding(let groundingEx):
                        self.updateGroundingSegment(groundingEx)
                    default:
                        break
                    }
                }

                if self.timeRemaining <= 0 {
                    self.stop()
                    self.showRatingPrompt = true
                }
            }
        }
    }

    private func updateMeditationSegment(_ exercise: ExerciseContent.MeditationExercise) {
        let currentTime = Int(elapsedTime)
        if let nextIndex = exercise.script.firstIndex(where: { $0.timestamp > currentTime }) {
            currentSegmentIndex = max(0, nextIndex - 1)
        } else {
            currentSegmentIndex = exercise.script.count - 1
        }
    }

    private func updateGroundingSegment(_ exercise: ExerciseContent.GroundingExercise) {
        let currentTime = Int(elapsedTime)
        if let nextIndex = exercise.prompts.firstIndex(where: { $0.timestamp > currentTime }) {
            currentSegmentIndex = max(0, nextIndex - 1)
        } else if currentTime >= (exercise.prompts.last?.timestamp ?? 0) {
            currentSegmentIndex = exercise.prompts.count - 1
        }
    }

    private func getSegmentCount() -> Int {
        guard let exercise = content.exerciseContent else { return 0 }

        switch exercise {
        case .meditation(let meditationEx):
            return meditationEx.script.count
        case .grounding(let groundingEx):
            return groundingEx.prompts.count
        default:
            return 0
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

enum BreathingPhase {
    case inhale, hold, exhale, pause
}

// MARK: - Primary Button Style
