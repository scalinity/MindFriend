import SwiftUI

// MARK: - Emotion Badge

/// Floating emotion indicator badge with pulse animation
/// Displays the detected emotion during voice mode
struct EmotionBadge: View {

    // MARK: - Properties

    /// The emotion snapshot to display
    let emotion: EmotionSnapshot

    /// Action when badge is tapped
    let onTap: () -> Void

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - State

    @State private var isVisible = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var autoHideTask: Task<Void, Never>?
    @State private var pulseTask: Task<Void, Never>?

    // MARK: - Configuration

    private let badgeSize: CGFloat = 48
    private let iconSize: CGFloat = 20
    private let autoHideDuration: Double = 8.0  // Longer duration for visibility

    // MARK: - Body

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Background circle with emotion color
                Circle()
                    .fill(emotionColor.opacity(0.2))
                    .frame(width: badgeSize, height: badgeSize)

                // Border with confidence-based thickness
                Circle()
                    .strokeBorder(emotionColor, lineWidth: confidenceBorderWidth)
                    .frame(width: badgeSize, height: badgeSize)

                // Emotion icon
                Image(systemName: emotion.icon)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(emotionColor)
            }
            .scaleEffect(pulseScale)
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .frame(width: badgeSize + 16, height: badgeSize + 16)  // Touch target 64x64
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to view emotion details")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            animateIn()
            startPulseAnimation()
            scheduleAutoHide()
        }
        .onDisappear {
            autoHideTask?.cancel()
            pulseTask?.cancel()
        }
        .onChange(of: emotion.id) { _, _ in
            // Reset animations when emotion changes
            animateIn()
            startPulseAnimation()
            scheduleAutoHide()
        }
    }

    // MARK: - Computed Properties

    /// Color for the emotion - uses shared helper
    private var emotionColor: Color {
        emotion.color
    }

    /// Border width based on confidence level
    private var confidenceBorderWidth: CGFloat {
        if emotion.confidence >= 0.8 { return 3 }
        if emotion.confidence >= 0.6 { return 2 }
        return 1.5
    }

    /// Accessibility label for VoiceOver
    private var accessibilityLabel: String {
        let confidencePercent = Int(emotion.confidence * 100)
        return "You sound \(emotion.emotion), \(confidencePercent)% confidence"
    }

    // MARK: - Animations

    private func animateIn() {
        isVisible = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            isVisible = true
        }
    }

    private func startPulseAnimation() {
        guard !reduceMotion else { return }

        // Cancel any existing pulse task
        pulseTask?.cancel()

        // Subtle pulse animation that repeats 3 times
        withAnimation(
            .easeInOut(duration: 1.0)
            .repeatCount(3, autoreverses: true)
        ) {
            pulseScale = 1.08
        }

        // Reset scale after animation
        pulseTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    pulseScale = 1.0
                }
            }
        }
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(autoHideDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    isVisible = false
                }
            }
        }
    }
}

// MARK: - Compact Emotion Badge

/// Smaller emotion indicator for use in lists or compact spaces
struct CompactEmotionBadge: View {

    let emotion: String
    let confidence: Double

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(emotionColor)
                .frame(width: 8, height: 8)

            Text(emotion.capitalized)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(emotionColor.opacity(0.1))
        .clipShape(Capsule())
    }

    /// Color for the emotion - uses shared helper
    private var emotionColor: Color {
        EmotionSnapshot.color(for: emotion)
    }
}

// MARK: - Preview

#Preview("Emotion Badge - Happy") {
    ZStack {
        Color.black.ignoresSafeArea()

        EmotionBadge(
            emotion: EmotionSnapshot(
                emotion: "happy",
                confidence: 0.85,
                timestamp: 0
            ),
            onTap: { print("Tapped") }
        )
    }
}

#Preview("Emotion Badge - Sad") {
    ZStack {
        Color.black.ignoresSafeArea()

        EmotionBadge(
            emotion: EmotionSnapshot(
                emotion: "sad",
                confidence: 0.72,
                timestamp: 0
            ),
            onTap: { print("Tapped") }
        )
    }
}

#Preview("Compact Badges") {
    HStack(spacing: 8) {
        CompactEmotionBadge(emotion: "happy", confidence: 0.8)
        CompactEmotionBadge(emotion: "sad", confidence: 0.65)
        CompactEmotionBadge(emotion: "calm", confidence: 0.9)
    }
    .padding()
}
