// CreatorContentPlayerView.swift
// Audio player UI for creator content with playback controls

import SwiftUI
import AVFoundation
import Combine

struct CreatorContentPlayerView: View {
    let content: CreatorContent
    @ObservedObject var creatorService: CreatorService

    @Environment(\.dismiss) var dismiss
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var totalDuration: TimeInterval = 0
    @State private var volume: Double = 1.0
    @State private var showRatingSheet = false
    @State private var userRating: Int = 0
    @State private var reviewText = ""
    @State private var hasRated = false
    @State private var sessionId = UUID()

    @State private var player: AVPlayer?
    @State private var timeObserver: Any?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // Cover Art
                    ZStack {
                        if let imageUrl = content.coverImageUrl, let url = URL(string: imageUrl) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                LinearGradient(
                                    colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            }
                        } else {
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .overlay {
                                Image(systemName: content.contentType.icon)
                                    .font(.system(size: 60))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    // Content Info
                    VStack(spacing: 8) {
                        Text(content.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 16) {
                            Label(content.contentType.displayName, systemImage: content.contentType.icon)
                            if let difficulty = content.difficulty {
                                Text(difficulty.displayName)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.tertiarySystemGroupedBackground))
                                    .clipShape(Capsule())
                            }
                            if let rating = content.averageRating {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                    Text(String(format: "%.1f", rating))
                                }
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if let description = content.description {
                            Text(description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal)

                    // Player Controls
                    VStack(spacing: 20) {
                        // Progress Bar
                        VStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { currentTime },
                                    set: { newValue in
                                        seek(to: newValue)
                                    }
                                ),
                                in: 0...max(totalDuration, 1)
                            )
                            .tint(.accentColor)

                            HStack {
                                Text(formatTime(currentTime))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(formatTime(totalDuration))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal)

                        // Playback Controls
                        HStack(spacing: 40) {
                            // Skip Back
                            Button {
                                skip(seconds: -15)
                            } label: {
                                Image(systemName: "gobackward.15")
                                    .font(.title)
                            }

                            // Play/Pause
                            Button {
                                togglePlayPause()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 70, height: 70)

                                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                        .font(.title)
                                        .foregroundStyle(.white)
                                        .offset(x: isPlaying ? 0 : 2)
                                }
                            }

                            // Skip Forward
                            Button {
                                skip(seconds: 15)
                            } label: {
                                Image(systemName: "goforward.15")
                                    .font(.title)
                            }
                        }

                        // Volume Control
                        HStack(spacing: 12) {
                            Image(systemName: "speaker.fill")
                                .foregroundStyle(.secondary)
                            Slider(value: $volume, in: 0...1)
                                .tint(.accentColor)
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    // Action Buttons
                    HStack(spacing: 16) {
                        Button {
                            // Download for offline
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            // Share
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)

                    // Transcript Section
                    if let transcript = content.transcript, !transcript.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Transcript")
                                .font(.headline)

                            Text(transcript)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(10)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top)
            }

            // Completion Rating Banner
            if !hasRated && completionPercentage >= 0.8 {
                VStack(spacing: 8) {
                    Text("How was this session?")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                userRating = star
                                showRatingSheet = true
                            } label: {
                                Image(systemName: star <= userRating ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.yellow.opacity(0.1))
            }
        }
        .navigationTitle(content.contentType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        // Report content
                    } label: {
                        Label("Report", systemImage: "flag")
                    }
                    Button {
                        // View in browser
                    } label: {
                        Label("Open in Browser", systemImage: "safari")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            setupPlayer()
            await loadUserRating()
        }
        .onDisappear {
            cleanupPlayer()
            recordEngagement()
        }
        .sheet(isPresented: $showRatingSheet) {
            RatingSheetView(
                rating: $userRating,
                review: $reviewText,
                onSubmit: submitRating
            )
            .presentationDetents([.medium])
        }
    }

    private var completionPercentage: Double {
        guard totalDuration > 0 else { return 0 }
        return currentTime / totalDuration
    }

    private func setupPlayer() {
        guard let mediaUrl = content.mediaUrl,
              let url = URL(string: mediaUrl) else { return }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        // Observe time
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time.seconds
            if totalDuration == 0 {
                totalDuration = playerItem.duration.seconds
            }
        }

        // Observe playback status
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            isPlaying = false
            recordCompletion()
        }
    }

    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
    }

    private func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime)
    }

    private func skip(seconds: Double) {
        let newTime = max(0, min(currentTime + seconds, totalDuration))
        seek(to: newTime)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func recordEngagement() {
        Task {
            do {
                try await creatorService.recordEngagement(
                    contentId: content.id,
                    sessionId: sessionId,
                    durationSeconds: Int(currentTime),
                    completionPercentage: completionPercentage,
                    isUserPremium: true // Should check actual subscription status
                )
            } catch {
                print("Failed to record engagement: \(error)")
            }
        }
    }

    private func recordCompletion() {
        hasRated = true
    }

    private func loadUserRating() async {
        // Check if user already rated this content
        // This would need a service method to check existing ratings
    }

    private func submitRating() {
        Task {
            do {
                try await creatorService.rateContent(
                    contentId: content.id,
                    rating: userRating,
                    review: reviewText.isEmpty ? nil : reviewText
                )
                hasRated = true
                showRatingSheet = false
            } catch {
                print("Failed to submit rating: \(error)")
            }
        }
    }
}

// MARK: - Rating Sheet View

struct RatingSheetView: View {
    @Binding var rating: Int
    @Binding var review: String
    let onSubmit: () -> Void

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Rate this session")
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            rating = star
                        } label: {
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.largeTitle)
                                .foregroundStyle(.yellow)
                        }
                    }
                }

                TextField("Write a review (optional)", text: $review, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                    .padding(.horizontal)

                Button(action: {
                    onSubmit()
                    dismiss()
                }) {
                    Text("Submit Rating")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(rating > 0 ? Color.accentColor : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(rating == 0)
                .padding(.horizontal)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CreatorContentPlayerView(
            content: CreatorContent(
                id: UUID(),
                creatorId: UUID(),
                contentType: .meditation,
                format: .audio,
                title: "Morning Calm Meditation",
                description: "A gentle 10-minute meditation to start your day with clarity and peace.",
                durationSeconds: 600,
                difficulty: .beginner,
                mediaUrl: "https://example.com/meditation.mp3",
                coverImageUrl: nil,
                category: "Meditation",
                tags: ["morning", "calm", "beginner"],
                status: .published,
                submittedAt: nil,
                publishedAt: Date(),
                playCount: 1500,
                uniqueListeners: 1200,
                averageRating: 4.8,
                ratingCount: 234
            ),
            creatorService: CreatorService(supabase: supabase)
        )
    }
}
