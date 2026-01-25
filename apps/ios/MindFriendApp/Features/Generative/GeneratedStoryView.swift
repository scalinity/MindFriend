import SwiftUI

/// Full-screen sleep story player with screen dimming, sleep timer, and ambient sounds
/// Optimized for bedtime use with minimal bright UI elements
struct GeneratedStoryView: View {
    let content: GeneratedContent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var player = AudioPlayerViewModel()
    @State private var showBackgroundSounds = false
    @State private var showSleepTimer = false
    @State private var screenBrightness: Double = 0.3
    @State private var originalBrightness: CGFloat = UIScreen.main.brightness
    @State private var isFavorite: Bool

    // UserDefaults key for brightness restoration on force-quit recovery
    private static let originalBrightnessKey = "GeneratedStoryView.originalBrightness"

    init(content: GeneratedContent) {
        self.content = content
        _isFavorite = State(initialValue: content.isFavorite)
    }
    
    var body: some View {
        ZStack {
            // Dark ambient background
            Color.black
                .ignoresSafeArea()
            
            // Subtle starfield or gradient
            storyBackground
            
            VStack(spacing: 32) {
                // Header with dismiss
                headerView
                
                Spacer()
                
                // Story info
                storyInfoView
                
                Spacer()
                
                // Minimalist player controls
                playerControls
                
                // Bottom toolbar
                bottomToolbar
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showBackgroundSounds) {
            BackgroundSoundsSheet(
                selectedSound: $player.backgroundSound,
                volume: $player.backgroundSoundVolume
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSleepTimer) {
            SleepTimerView(selectedMinutes: $player.sleepTimerMinutes)
                .presentationDetents([.height(400)])
        }
        .onAppear {
            loadAudio()
            dimScreen()
        }
        .onDisappear {
            player.cleanup()
            restoreBrightness()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Restore brightness when app goes to background (in case user switches away)
            if newPhase == .background {
                restoreBrightness()
            }
        }
    }

    /// Restore brightness from UserDefaults if app was force-quit while dimmed
    /// Call this from AppDelegate/SceneDelegate on app launch
    static func restoreBrightnessIfNeeded() {
        let defaults = UserDefaults.standard
        if let savedBrightness = defaults.object(forKey: originalBrightnessKey) as? CGFloat {
            UIScreen.main.brightness = savedBrightness
            defaults.removeObject(forKey: originalBrightnessKey)
        }
    }
    
    // MARK: - Story Background
    
    private var storyBackground: some View {
        ZStack {
            // Gradient from deep purple to black
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.3),
                    Color.purple.opacity(0.15),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Subtle stars effect
            GeometryReader { geometry in
                ForEach(0..<30, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(Double.random(in: 0.1...0.4)))
                        .frame(width: CGFloat.random(in: 1...3))
                        .position(
                            x: CGFloat.random(in: 0...geometry.size.width),
                            y: CGFloat.random(in: 0...geometry.size.height * 0.5)
                        )
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Sleep timer indicator
            if let remaining = player.sleepTimerMinutes, remaining > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "moon.zzz")
                    Text(player.formattedSleepTimerRemaining)
                }
                .font(.caption)
                .foregroundStyle(.indigo)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.indigo.opacity(0.2))
                .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - Story Info
    
    private var storyInfoView: some View {
        VStack(spacing: 16) {
            // Moon icon
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.indigo, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text(content.title)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            
            if let duration = content.duration {
                Text("\(duration / 60) min")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            // Loading/error states
            if player.isLoading {
                ProgressView()
                    .tint(.white)
            }
            
            if let error = player.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
    
    // MARK: - Player Controls
    
    private var playerControls: some View {
        VStack(spacing: 24) {
            // Progress bar
            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 1)
                )
                .tint(.indigo)
                
                HStack {
                    Text(player.formattedCurrentTime)
                    Spacer()
                    Text(player.formattedDuration)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            }
            
            // Play/pause with skip
            HStack(spacing: 48) {
                Button {
                    player.skipBackward()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.indigo)
                }
                .disabled(player.isLoading || content.audioUrl == nil)
                
                Button {
                    player.skipForward()
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
    
    // MARK: - Bottom Toolbar
    
    private var bottomToolbar: some View {
        HStack(spacing: 32) {
            // Background sounds
            Button {
                showBackgroundSounds = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: player.backgroundSound != nil ? "waveform.circle.fill" : "waveform.circle")
                    Text("Sounds")
                        .font(.caption2)
                }
                .foregroundStyle(player.backgroundSound != nil ? .indigo : .white.opacity(0.6))
            }
            
            // Sleep timer
            Button {
                showSleepTimer = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: player.sleepTimerMinutes != nil ? "timer.circle.fill" : "timer")
                    Text("Timer")
                        .font(.caption2)
                }
                .foregroundStyle(player.sleepTimerMinutes != nil ? .indigo : .white.opacity(0.6))
            }
            
            // Brightness control
            Button {
                adjustBrightness()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: brightnessIcon)
                    Text("Dim")
                        .font(.caption2)
                }
                .foregroundStyle(.white.opacity(0.6))
            }
            
            // Favorite
            Button {
                toggleFavorite()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                    Text("Save")
                        .font(.caption2)
                }
                .foregroundStyle(isFavorite ? .pink : .white.opacity(0.6))
            }
        }
        .font(.title3)
    }
    
    // MARK: - Brightness
    
    private var brightnessIcon: String {
        if screenBrightness < 0.2 {
            return "sun.min"
        } else if screenBrightness < 0.5 {
            return "sun.max"
        } else {
            return "sun.max.fill"
        }
    }
    
    private func dimScreen() {
        originalBrightness = UIScreen.main.brightness
        // Persist to UserDefaults for force-quit recovery
        UserDefaults.standard.set(originalBrightness, forKey: Self.originalBrightnessKey)
        UIScreen.main.brightness = CGFloat(screenBrightness)
    }

    private func restoreBrightness() {
        UIScreen.main.brightness = originalBrightness
        // Clear persisted value since we've restored
        UserDefaults.standard.removeObject(forKey: Self.originalBrightnessKey)
    }
    
    private func adjustBrightness() {
        // Cycle through brightness levels: 0.1 → 0.3 → 0.5 → 0.1
        if screenBrightness < 0.2 {
            screenBrightness = 0.3
        } else if screenBrightness < 0.4 {
            screenBrightness = 0.5
        } else {
            screenBrightness = 0.1
        }
        UIScreen.main.brightness = CGFloat(screenBrightness)
    }
    
    // MARK: - Actions
    
    private func loadAudio() {
        guard let urlString = content.audioUrl,
              let url = URL(string: urlString) else {
            player.error = "No audio available"
            return
        }
        
        Task {
            do {
                try await player.load(audioURL: url)
            } catch {
                player.error = "Failed to load audio"
            }
        }
    }
    
    private func toggleFavorite() {
        isFavorite.toggle()
        
        Task {
            do {
                let service = GeneratedContentService(supabase: supabase)
                _ = try await service.toggleFavorite(contentId: content.id)
            } catch {
                // Revert on failure
                isFavorite.toggle()
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    GeneratedStoryView(content: .preview)
}
#endif