// ActiveSessionView.swift
// MindFriend - Active Live Session Experience

import SwiftUI
import AVFoundation

struct ActiveSessionView: View {
    let session: LiveSession
    @ObservedObject var liveService: LiveService

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showLeaveConfirmation = false
    @State private var isCompleting = false
    @State private var audioPlayer: AVPlayer?
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var timeRemaining: TimeInterval = 0
    @State private var progressTimer: Timer?

    private let reactionEmojis = ["🙏", "💙", "✨", "🌟", "❤️", "👏"]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                backgroundGradient

                VStack(spacing: 0) {
                    // Top bar
                    topBar

                    Spacer()

                    // Main content
                    mainContent(geometry: geometry)

                    Spacer()

                    // Reaction bar
                    reactionBar

                    // Progress bar
                    sessionProgress
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            setupAudio()
            startProgressTimer()
        }
        .onDisappear {
            cleanupAudio()
            progressTimer?.invalidate()
        }
        .confirmationDialog(
            "Leave Session?",
            isPresented: $showLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                Task { await leaveSession() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll miss out on bonus XP if you leave early.")
        }
    }

    // MARK: - Subviews

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [typeColor.opacity(0.3), typeColor.opacity(0.1), Color(.systemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Button {
                showLeaveConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            Spacer()

            // Participant count
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Image(systemName: "person.2.fill")
                Text("\(liveService.participantCount)")
                    .fontWeight(.medium)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
        }
        .padding()
    }

    private func mainContent(geometry: GeometryProxy) -> some View {
        VStack(spacing: 24) {
            // Session type icon with animation
            ZStack {
                // Outer ring
                Circle()
                    .stroke(typeColor.opacity(0.3), lineWidth: 4)
                    .frame(width: 160, height: 160)

                // Animated inner ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(typeColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                // Icon
                Image(systemName: session.sessionType.icon)
                    .font(.system(size: 60))
                    .foregroundStyle(typeColor)
            }

            // Session info
            VStack(spacing: 8) {
                Text(session.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(session.sessionType.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Time remaining
            Text(formatTime(timeRemaining))
                .font(.system(size: 48, weight: .light, design: .rounded))
                .monospacedDigit()

            // Play/Pause button
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(typeColor)
            }

            // Reactions feed
            reactionsOverlay
        }
    }

    private var reactionsOverlay: some View {
        HStack(spacing: 8) {
            ForEach(Array(liveService.recentReactions.enumerated()), id: \.offset) { index, emoji in
                Text(emoji)
                    .font(.title2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: liveService.recentReactions)
        .frame(height: 40)
    }

    private var reactionBar: some View {
        HStack(spacing: 16) {
            ForEach(reactionEmojis, id: \.self) { emoji in
                Button {
                    Task { await sendReaction(emoji) }
                } label: {
                    Text(emoji)
                        .font(.title)
                        .frame(width: 50, height: 50)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
        }
        .padding()
    }

    private var sessionProgress: some View {
        VStack(spacing: 12) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                        .cornerRadius(3)

                    Rectangle()
                        .fill(typeColor)
                        .frame(width: geometry.size.width * progress, height: 6)
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)
            .padding(.horizontal)

            // Complete button (shows when session is ending)
            if timeRemaining < 60 || progress > 0.9 {
                Button {
                    Task { await completeSession() }
                } label: {
                    HStack {
                        if isCompleting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Complete Session")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(isCompleting)
                .padding(.horizontal)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom)
        .animation(.spring(), value: progress > 0.9)
    }

    // MARK: - Helpers

    private var typeColor: Color {
        switch session.sessionType {
        case .breathing: return .blue
        case .meditation: return .purple
        case .bodyScan: return .green
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - Audio

    private func setupAudio() {
        guard let urlString = session.audioUrl,
              let url = URL(string: urlString) else { return }

        audioPlayer = AVPlayer(url: url)

        // Configure audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }

        // Auto-play
        audioPlayer?.play()
        isPlaying = true
    }

    private func cleanupAudio() {
        audioPlayer?.pause()
        audioPlayer = nil
    }

    private func togglePlayback() {
        if isPlaying {
            audioPlayer?.pause()
        } else {
            audioPlayer?.play()
        }
        isPlaying.toggle()
    }

    // MARK: - Progress Timer

    private func startProgressTimer() {
        let endTime = session.scheduledEnd
        updateProgress(endTime: endTime)

        progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            updateProgress(endTime: endTime)
        }
    }

    private func updateProgress(endTime: Date) {
        let totalDuration = endTime.timeIntervalSince(session.scheduledStart)
        let elapsed = Date().timeIntervalSince(session.scheduledStart)
        timeRemaining = max(0, endTime.timeIntervalSinceNow)
        progress = min(1, max(0, elapsed / totalDuration))

        // Auto-complete when time is up
        if timeRemaining <= 0 && !isCompleting {
            Task { await completeSession() }
        }
    }

    // MARK: - Actions

    private func sendReaction(_ emoji: String) async {
        do {
            try await liveService.sendReaction(emoji: emoji)
        } catch {
            print("Failed to send reaction: \(error)")
        }
    }

    private func leaveSession() async {
        do {
            try await liveService.leaveSession()
            dismiss()
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }

    private func completeSession() async {
        isCompleting = true

        do {
            let result = try await liveService.completeSession()

            // Show celebration
            await MainActor.run {
                appState.showCelebration(
                    title: "Session Complete!",
                    subtitle: "+\(result.xpAwarded) XP",
                    icon: "star.fill"
                )
            }

            dismiss()
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }

        isCompleting = false
    }
}

#Preview {
    let session = LiveSession(
        id: "1",
        title: "Morning Calm",
        description: "Start your day with mindfulness",
        sessionType: .breathing,
        scheduledStart: Date(),
        scheduledEnd: Date().addingTimeInterval(600),
        audioUrl: nil,
        participantCount: 12
    )

    ActiveSessionView(
        session: session,
        liveService: LiveService()
    )
    .environmentObject(AppState())
}
