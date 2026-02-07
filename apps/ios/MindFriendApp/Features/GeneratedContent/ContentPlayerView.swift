import SwiftUI
import AVFoundation

/// View for playing generated audio content
/// Supports both ElevenLabs audio (premium) and native iOS TTS (free tier)
struct ContentPlayerView: View {
    let content: GeneratedContent
    let service: GeneratedContentService

    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: ContentPlayerViewModel
    @StateObject private var ttsService = NativeTTSService()

    init(content: GeneratedContent, service: GeneratedContentService) {
        self.content = content
        self.service = service
        _viewModel = StateObject(wrappedValue: ContentPlayerViewModel(
            content: content,
            service: service
        ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header with artwork
                headerSection

                // Playback controls - ElevenLabs audio (premium) or native TTS (free)
                if content.hasAudio {
                    playbackSection
                } else {
                    nativeTTSSection
                }

                // Text content
                textContentSection

                // Rating section
                ratingSection

                // Actions
                actionsSection

                // Disclaimer
                disclaimerSection
            }
            .padding()
        }
        .navigationTitle(content.contentType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $viewModel.showFlagSheet) {
            FlagContentSheet(
                contentId: content.id,
                service: service
            )
        }
        .alert("Rate Content", isPresented: $viewModel.showRatingAlert) {
            Button("Submit") {
                Task {
                    await viewModel.submitRating()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("How would you rate this \(content.contentType.displayName.lowercased())?")
        }
        .onAppear {
            Task {
                await viewModel.recordPlay()
            }
        }
        .onDisappear {
            viewModel.stopPlayback()
            ttsService.stop()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Artwork
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.6), Color.accentColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 200)

                VStack(spacing: 12) {
                    Image(systemName: content.contentType.icon)
                        .font(.system(size: 50))
                        .foregroundStyle(.white)

                    if viewModel.isPlaying {
                        AudioWaveform()
                            .frame(height: 30)
                    }
                }
            }

            // Title
            Text(content.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            // Metadata
            HStack(spacing: 16) {
                if content.hasAudio {
                    Label(content.formattedDuration, systemImage: "clock")
                }

                if let rating = content.averageRating {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", rating))
                    }
                }

                if content.playCount > 0 {
                    Label("\(content.playCount) plays", systemImage: "play.circle")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            // Trigger warnings
            if let warnings = content.triggerWarnings, !warnings.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)

                    Text("Contains: \(warnings.joined(separator: ", ").replacingOccurrences(of: "_", with: " "))")
                        .font(.caption)
                }
                .padding(8)
                .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Playback Section

    private var playbackSection: some View {
        VStack(spacing: 16) {
            // Progress bar
            VStack(spacing: 4) {
                Slider(
                    value: $viewModel.playbackProgress,
                    in: 0...1,
                    onEditingChanged: { editing in
                        if !editing {
                            viewModel.seekTo(progress: viewModel.playbackProgress)
                        }
                    }
                )
                .tint(Color.accentColor)

                HStack {
                    Text(viewModel.currentTimeString)
                    Spacer()
                    Text(viewModel.durationString)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // Controls
            HStack(spacing: 40) {
                // Rewind
                Button {
                    viewModel.skip(seconds: -15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }

                // Play/Pause
                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }

                // Forward
                Button {
                    viewModel.skip(seconds: 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
            }
            .foregroundStyle(.primary)

            // Speed control
            HStack {
                Text("Speed")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Speed", selection: $viewModel.playbackSpeed) {
                    Text("0.5x").tag(0.5)
                    Text("0.75x").tag(0.75)
                    Text("1x").tag(1.0)
                    Text("1.25x").tag(1.25)
                    Text("1.5x").tag(1.5)
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.playbackSpeed) { _, newValue in
                    viewModel.setPlaybackSpeed(newValue)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Native TTS Section (Free Tier)

    private var nativeTTSSection: some View {
        VStack(spacing: 16) {
            // Info banner
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.blue)
                Text("Using device voice")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    appState.showPaywall = true
                } label: {
                    Text("Upgrade")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .padding(10)
            .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            // Progress indicator
            if ttsService.isSpeaking {
                ProgressView(value: ttsService.progress)
                    .tint(.accentColor)
            }

            // Controls
            HStack(spacing: 40) {
                // Play/Pause
                Button {
                    if ttsService.isSpeaking {
                        if ttsService.isPaused {
                            ttsService.resume()
                        } else {
                            ttsService.pause()
                        }
                    } else {
                        let settings = NativeTTSService.settingsForContentType(content.contentType.rawValue)
                        ttsService.speak(content.textContent, settings: settings)
                    }
                } label: {
                    Image(systemName: ttsService.isSpeaking && !ttsService.isPaused ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }

                // Stop
                if ttsService.isSpeaking {
                    Button {
                        ttsService.stop()
                    } label: {
                        Image(systemName: "stop.circle")
                            .font(.title)
                    }
                }
            }
            .foregroundStyle(.primary)

            // Duration estimate
            if let duration = content.duration {
                Text("~\(duration / 60) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Text Content Section

    private var textContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Content")
                    .font(.headline)

                Spacer()

                Button {
                    viewModel.showFullText.toggle()
                } label: {
                    Text(viewModel.showFullText ? "Show Less" : "Show More")
                        .font(.caption)
                }
            }

            Text(content.textContent)
                .font(.body)
                .lineLimit(viewModel.showFullText ? nil : 5)
                .animation(.easeInOut, value: viewModel.showFullText)
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Rating Section

    private var ratingSection: some View {
        VStack(spacing: 12) {
            Text("How was this content?")
                .font(.subheadline)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        viewModel.userRating = star
                    } label: {
                        Image(systemName: star <= viewModel.userRating ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(star <= viewModel.userRating ? .yellow : .gray)
                    }
                }
            }

            if viewModel.userRating > 0 && !viewModel.hasSubmittedRating {
                Button("Submit Rating") {
                    Task {
                        await viewModel.submitRating()
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }

            if viewModel.hasSubmittedRating {
                Label("Thanks for your feedback!", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        HStack(spacing: 20) {
            Button {
                Task {
                    await viewModel.toggleFavorite()
                }
            } label: {
                Label(
                    viewModel.isFavorite ? "Favorited" : "Favorite",
                    systemImage: viewModel.isFavorite ? "heart.fill" : "heart"
                )
            }
            .foregroundStyle(viewModel.isFavorite ? .red : .primary)

            Divider()
                .frame(height: 20)

            Button {
                viewModel.showFlagSheet = true
            } label: {
                Label("Report", systemImage: "flag")
            }
            .foregroundStyle(.secondary)

            Divider()
                .frame(height: 20)

            ShareLink(
                item: content.title,
                subject: Text("Check out this \(content.contentType.displayName)"),
                message: Text("I created this with MindFriend")
            ) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    // MARK: - Disclaimer Section

    private var disclaimerSection: some View {
        Text(ContentDisclaimer.standard)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
    }
}

// MARK: - Audio Waveform Animation

private struct AudioWaveform: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white)
                    .frame(width: 4)
                    .scaleEffect(y: animating ? CGFloat.random(in: 0.3...1.0) : 0.5, anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever()
                            .delay(Double(index) * 0.1),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

// MARK: - Flag Content Sheet

private struct FlagContentSheet: View {
    let contentId: UUID
    let service: GeneratedContentService

    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: ContentFlagReason?
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if submitted {
                    submittedView
                } else {
                    formView
                }
            }
            .padding()
            .navigationTitle("Report Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var formView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Why are you reporting this content?")
                .font(.headline)

            ForEach(ContentFlagReason.allCases, id: \.rawValue) { reason in
                Button {
                    selectedReason = reason
                } label: {
                    HStack {
                        Image(systemName: reason.icon)
                            .frame(width: 24)
                        Text(reason.displayName)
                        Spacer()
                        if selectedReason == reason {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding()
                    .background(
                        selectedReason == reason ? Color.accentColor.opacity(0.1) : Color(.systemGray6),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .buttonStyle(.plain)
            }

            if selectedReason == .other {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Please provide details")
                        .font(.subheadline)

                    TextEditor(text: $details)
                        .frame(height: 100)
                        .padding(8)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Spacer()

            Button {
                Task {
                    await submitFlag()
                }
            } label: {
                HStack {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Submit Report")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(selectedReason != nil ? Color.accentColor : Color.gray)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(selectedReason == nil || isSubmitting || (selectedReason == .other && details.count < 10))
        }
    }

    private var submittedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Report Submitted")
                .font(.title2)
                .fontWeight(.bold)

            Text("Thank you for helping keep MindFriend safe. Our team will review this content.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func submitFlag() async {
        guard let reason = selectedReason else { return }

        isSubmitting = true

        do {
            _ = try await service.flagContent(
                contentId: contentId,
                reason: reason,
                details: details.isEmpty ? nil : details
            )
            submitted = true
        } catch {
            // Handle error
            print("Error submitting flag: \(error)")
        }

        isSubmitting = false
    }
}

// MARK: - View Model

@MainActor
final class ContentPlayerViewModel: ObservableObject {
    private let content: GeneratedContent
    private let service: GeneratedContentService
    private var player: AVPlayer?
    private var timeObserver: Any?

    @Published var isPlaying = false
    @Published var playbackProgress: Double = 0
    @Published var currentTime: TimeInterval = 0
    @Published var playbackSpeed: Double = 1.0
    @Published var showFullText = false
    @Published var isFavorite: Bool
    @Published var userRating = 0
    @Published var hasSubmittedRating = false
    @Published var showFlagSheet = false
    @Published var showRatingAlert = false

    var currentTimeString: String {
        formatTime(currentTime)
    }

    var durationString: String {
        formatTime(TimeInterval(content.duration ?? 0))
    }

    init(content: GeneratedContent, service: GeneratedContentService) {
        self.content = content
        self.service = service
        self.isFavorite = content.isFavorite

        setupPlayer()
    }

    deinit {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
    }

    private func setupPlayer() {
        guard let audioUrl = content.audioUrl,
              let url = URL(string: audioUrl) else { return }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        // Add time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }

            MainActor.assumeIsolated {
                guard let duration = self.player?.currentItem?.duration,
                      duration.isNumeric else { return }

                let currentSeconds = time.seconds
                let totalSeconds = duration.seconds

                self.currentTime = currentSeconds
                self.playbackProgress = currentSeconds / totalSeconds
            }
        }

        // Observe when playback ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isPlaying = false
                self?.playbackProgress = 0
                self?.currentTime = 0
                self?.player?.seek(to: .zero)
            }
        }
    }

    func togglePlayback() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }

    func stopPlayback() {
        player?.pause()
        isPlaying = false
    }

    func seekTo(progress: Double) {
        guard let duration = player?.currentItem?.duration,
              duration.isNumeric else { return }

        let totalSeconds = duration.seconds
        let targetTime = CMTime(seconds: totalSeconds * progress, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: targetTime)
    }

    func skip(seconds: Double) {
        guard let currentTime = player?.currentTime() else { return }
        let newTime = CMTime(seconds: currentTime.seconds + seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: newTime)
    }

    func setPlaybackSpeed(_ speed: Double) {
        player?.rate = Float(speed)
        if isPlaying {
            player?.play()
        }
    }

    func toggleFavorite() async {
        do {
            isFavorite = try await service.toggleFavorite(contentId: content.id)
        } catch {
            // Revert on error
            isFavorite.toggle()
        }
    }

    func submitRating() async {
        guard userRating > 0 else { return }

        do {
            _ = try await service.rateContent(contentId: content.id, rating: userRating)
            hasSubmittedRating = true
        } catch {
            // Handle error silently
        }
    }

    func recordPlay() async {
        do {
            try await service.recordPlay(contentId: content.id)
        } catch {
            // Silently fail
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        ContentPlayerView(content: .preview, service: .preview)
    }
}
#endif
