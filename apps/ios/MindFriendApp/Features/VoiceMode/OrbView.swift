import SwiftUI
import UIKit

// MARK: - Orb View

/// A dynamic, audio-reactive orb visualization for Voice Mode
/// Uses Canvas + TimelineView for 60fps smooth animations
/// Audio-reactive: orb scale, deformation, and glow all respond to audio amplitude
struct OrbView: View {

    // MARK: - Configuration

    struct Configuration {
        var state: VoiceStateMachine.State
        var micLevel: Float           // 0.0 - 1.0, smoothed RMS from microphone
        var playbackLevel: Float      // 0.0 - 1.0, smoothed RMS from TTS output
        var reducedMotion: Bool

        static let idle = Configuration(
            state: .idle,
            micLevel: 0,
            playbackLevel: 0,
            reducedMotion: false
        )
    }

    // MARK: - Audio-Reactivity Tuning Parameters

    /// How much the orb scales with audio (0.0 = none, 0.3 = dramatic)
    private let audioScaleIntensity: CGFloat = 0.18

    /// How much audio affects blob deformation (0.0 = none, 0.25 = very wobbly)
    private let audioDeformIntensity: CGFloat = 0.20

    /// How much audio affects glow ring expansion
    private let audioGlowIntensity: CGFloat = 0.35

    /// Base glow opacity (audio adds to this)
    private let baseGlowOpacity: Double = 0.12

    /// Peak glow opacity at max audio
    private let peakGlowOpacity: Double = 0.35

    /// Number of harmonic frequencies for organic deformation
    private let deformHarmonics: Int = 5

    let config: Configuration
    let size: CGFloat
    let onTap: (() -> Void)?

    init(config: Configuration, size: CGFloat = 200, onTap: (() -> Void)? = nil) {
        self.config = config
        self.size = size
        self.onTap = onTap
    }

    // MARK: - Body

    var body: some View {
        if config.reducedMotion {
            reducedMotionOrb
        } else {
            animatedOrb
        }
    }

    // MARK: - Animated Orb (Full Animation)

    private var animatedOrb: some View {
        TimelineView(.animation(minimumInterval: 1.0 / targetFrameRate)) { timeline in
            Canvas { context, canvasSize in
                let time = timeline.date.timeIntervalSinceReferenceDate
                drawOrb(context: context, size: canvasSize, time: time)
            }
            .frame(width: size, height: size)
        }
        .contentShape(Circle())
        .onTapGesture {
            onTap?()
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    /// Target frame rate based on activity level (saves battery when idle)
    private var targetFrameRate: Double {
        switch config.state {
        case .idle, .ready:
            return 20.0  // Low frame rate when idle
        case .listening:
            return config.micLevel > 0.05 ? 60.0 : 20.0
        case .userSpeaking, .thinking, .processing, .speaking:
            return 60.0  // High frame rate when active
        default:
            return 30.0
        }
    }

    // MARK: - Reduced Motion Orb

    private var reducedMotionOrb: some View {
        ZStack {
            // Audio-reactive scale even in reduced motion
            let audioScale = 1.0 + CGFloat(effectiveLevel) * audioScaleIntensity * 0.5

            Circle()
                .fill(stateGradient)
                .frame(width: size * audioScale, height: size * audioScale)
                .opacity(orbOpacity)

            Image(systemName: config.state.orbIcon)
                .font(.system(size: size * 0.24, weight: .medium))
                .foregroundStyle(.white)
        }
        .contentShape(Circle())
        .onTapGesture {
            onTap?()
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .animation(.easeOut(duration: 0.1), value: config.micLevel)
        .animation(.easeOut(duration: 0.1), value: config.playbackLevel)
        .animation(.easeInOut(duration: 0.3), value: config.state)
    }

    // MARK: - Canvas Drawing

    private func drawOrb(context: GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = min(size.width, size.height) / 2 * 0.95

        // Audio level drives everything
        let level = effectiveLevel
        let levelCG = CGFloat(level)

        // Audio-reactive base radius: orb pulses with audio amplitude
        let audioScale = 1.0 + levelCG * audioScaleIntensity
        let baseRadius = min(size.width, size.height) / 2 * 0.55 * audioScale

        // Slow ambient breathing (subtle, audio takes priority)
        let ambientBreath = sin(time * ambientBreathingSpeed) * 0.02 + 1.0

        // Draw outer glow rings (audio-reactive)
        if config.state.isActive || level > 0.05 {
            drawGlowRings(
                context: context,
                center: center,
                baseRadius: baseRadius,
                maxRadius: maxRadius,
                time: time,
                level: level
            )
        }

        // Draw main orb with audio-reactive deformation
        drawMainOrb(
            context: context,
            center: center,
            baseRadius: baseRadius * ambientBreath,
            maxRadius: maxRadius,
            time: time,
            level: level
        )
    }

    private func drawGlowRings(
        context: GraphicsContext,
        center: CGPoint,
        baseRadius: CGFloat,
        maxRadius: CGFloat,
        time: Double,
        level: Float
    ) {
        let color = stateColor
        let levelCG = CGFloat(level)

        // Ring 1: Primary audio-reactive glow
        // Expands significantly with audio, opacity increases with level
        let ring1Expansion = 1.0 + levelCG * audioGlowIntensity
        let ring1Pulse = sin(time * 2.5) * 0.03 + 1.0  // Subtle ambient pulse
        let ring1Radius = min(baseRadius * 1.25 * ring1Expansion * ring1Pulse, maxRadius)
        let ring1Opacity = baseGlowOpacity + Double(level) * (peakGlowOpacity - baseGlowOpacity)

        var ring1Path = Path()
        ring1Path.addEllipse(in: CGRect(
            x: center.x - ring1Radius,
            y: center.y - ring1Radius,
            width: ring1Radius * 2,
            height: ring1Radius * 2
        ))
        context.fill(ring1Path, with: .color(color.opacity(ring1Opacity)))

        // Ring 2: Secondary glow (appears at higher audio levels)
        if level > 0.2 {
            let ring2Expansion = 1.0 + levelCG * audioGlowIntensity * 1.3
            let ring2Pulse = sin(time * 1.8 + 1.0) * 0.04 + 1.0
            let ring2Radius = min(baseRadius * 1.45 * ring2Expansion * ring2Pulse, maxRadius)
            let ring2Opacity = (Double(level) - 0.2) * 0.15

            var ring2Path = Path()
            ring2Path.addEllipse(in: CGRect(
                x: center.x - ring2Radius,
                y: center.y - ring2Radius,
                width: ring2Radius * 2,
                height: ring2Radius * 2
            ))
            context.fill(ring2Path, with: .color(color.opacity(ring2Opacity)))
        }

        // Ring 3: Outer burst (appears at peak audio)
        if level > 0.5 {
            let ring3Expansion = 1.0 + levelCG * audioGlowIntensity * 1.6
            let ring3Radius = min(baseRadius * 1.65 * ring3Expansion, maxRadius)
            let ring3Opacity = (Double(level) - 0.5) * 0.12

            var ring3Path = Path()
            ring3Path.addEllipse(in: CGRect(
                x: center.x - ring3Radius,
                y: center.y - ring3Radius,
                width: ring3Radius * 2,
                height: ring3Radius * 2
            ))
            context.fill(ring3Path, with: .color(color.opacity(ring3Opacity)))
        }
    }

    private func drawMainOrb(
        context: GraphicsContext,
        center: CGPoint,
        baseRadius: CGFloat,
        maxRadius: CGFloat,
        time: Double,
        level: Float
    ) {
        let levelCG = CGFloat(level)

        // Audio-reactive deformation: more audio = more wobble
        let deformAmount = 0.015 + levelCG * audioDeformIntensity
        let numPoints = 72  // Smooth curve

        var path = Path()
        for i in 0...numPoints {
            let angle = (Double(i) / Double(numPoints)) * 2 * .pi

            // Multi-harmonic deformation for organic blob shape
            // Audio level modulates the amplitude of each harmonic
            var totalDeform: CGFloat = 0
            for h in 1...deformHarmonics {
                let freq = Double(h * 2 + 1)  // Odd harmonics: 3, 5, 7, 9, 11
                let speed = deformSpeed * (1.0 - Double(h) * 0.12)  // Slower for higher harmonics
                let amplitude = deformAmount / CGFloat(h)  // Diminishing amplitude
                let phase = Double(h) * 0.7  // Phase offset per harmonic
                totalDeform += sin(angle * freq + time * speed + phase) * amplitude
            }

            // Clamp radius to prevent overflow
            let radius = min(baseRadius * (1.0 + totalDeform), maxRadius * 0.85)

            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()

        // Audio-reactive gradient: brighter at higher levels
        let brightnessBoost = 1.0 + Double(level) * 0.15
        let baseColor = stateColor
        let brightColor = baseColor.opacity(min(1.0, 0.85 * brightnessBoost))
        let dimColor = baseColor.opacity(min(1.0, 0.55 * brightnessBoost))

        let gradient = Gradient(colors: [brightColor, dimColor])
        context.fill(
            path,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: center.x - baseRadius, y: center.y - baseRadius),
                endPoint: CGPoint(x: center.x + baseRadius, y: center.y + baseRadius)
            )
        )

        // Audio-reactive edge glow: thicker and brighter with audio
        let glowWidth = 8.0 + Double(level) * 16.0
        let glowOpacity = 0.1 + Double(level) * 0.2
        context.stroke(
            path,
            with: .color(stateColor.opacity(glowOpacity)),
            lineWidth: glowWidth
        )
    }

    // MARK: - State-Based Properties

    private var stateColor: Color {
        switch config.state.orbColor {
        case .inactive:
            return Color(UIColor.systemGray3)
        case .connecting:
            return Color.orange
        case .ready:
            return Color.blue.opacity(0.85)
        case .userSpeaking:
            return Color.green
        case .thinking:
            return Color.purple
        case .aiSpeaking:
            return Color.blue
        case .interrupted:
            return Color.yellow
        case .muted:
            return Color(UIColor.systemGray4)
        case .reconnecting:
            return Color.orange
        case .error:
            return Color.red
        }
    }

    private var stateGradient: LinearGradient {
        let base = stateColor
        return LinearGradient(
            colors: [base, base.opacity(0.65)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Ambient breathing speed (slow, background animation)
    private var ambientBreathingSpeed: Double {
        switch config.state {
        case .idle, .ready:
            return 1.2   // Very slow when idle
        case .listening:
            return 1.5
        case .thinking, .processing:
            return 2.5   // Faster pulse when thinking
        case .speaking:
            return 1.8
        default:
            return 1.5
        }
    }

    /// Deformation animation speed (how fast the blob wobbles)
    private var deformSpeed: Double {
        switch config.state {
        case .userSpeaking:
            return 5.0   // Fast wobble when user speaks
        case .speaking:
            return 4.0   // Medium-fast for AI speaking
        case .thinking:
            return 3.0   // Swirling when thinking
        case .listening:
            return 2.0   // Gentle movement when listening
        default:
            return 1.5   // Slow drift otherwise
        }
    }

    /// Effective audio level based on current state
    private var effectiveLevel: Float {
        switch config.state {
        case .userSpeaking:
            // Direct mic level mapping for immediate response
            return config.micLevel
        case .speaking:
            // Direct playback level for AI speech visualization
            return config.playbackLevel
        case .thinking, .processing:
            // Animated activity level (simulated audio-like pulse)
            return 0.4
        case .listening:
            // Show subtle mic reactivity even when not speaking
            return config.micLevel * 0.7
        case .ready:
            // Very subtle ambient reactivity
            return config.micLevel * 0.3
        default:
            return 0
        }
    }

    private var orbOpacity: Double {
        switch config.state {
        case .muted:
            return 0.5
        case .error:
            return 0.8
        default:
            return 1.0
        }
    }

    private var accessibilityLabel: String {
        "Voice orb, \(config.state.statusText)"
    }

    private var accessibilityHint: String {
        switch config.state {
        case .speaking, .thinking:
            return "Speak to interrupt"
        case .idle:
            return "Tap to start voice mode"
        default:
            return ""
        }
    }
}

// MARK: - Orb Container View

/// Container view that adds the icon symbol for Canvas resolution
struct OrbContainerView: View {

    let config: OrbView.Configuration
    let size: CGFloat
    let onTap: (() -> Void)?

    init(config: OrbView.Configuration, size: CGFloat = 200, onTap: (() -> Void)? = nil) {
        self.config = config
        self.size = size
        self.onTap = onTap
    }

    var body: some View {
        ZStack {
            OrbView(config: config, size: size, onTap: onTap)

            // Overlay icon (since Canvas can't directly draw SF Symbols)
            Image(systemName: config.state.orbIcon)
                .font(.system(size: size * 0.24, weight: .medium))
                .foregroundStyle(.white)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Preview

#Preview("Orb States") {
    VStack(spacing: 40) {
        HStack(spacing: 30) {
            VStack {
                OrbContainerView(
                    config: OrbView.Configuration(
                        state: .listening,
                        micLevel: 0.3,
                        playbackLevel: 0,
                        reducedMotion: false
                    ),
                    size: 120
                )
                Text("Listening")
                    .font(.caption)
            }

            VStack {
                OrbContainerView(
                    config: OrbView.Configuration(
                        state: .userSpeaking,
                        micLevel: 0.7,
                        playbackLevel: 0,
                        reducedMotion: false
                    ),
                    size: 120
                )
                Text("User Speaking")
                    .font(.caption)
            }
        }

        HStack(spacing: 30) {
            VStack {
                OrbContainerView(
                    config: OrbView.Configuration(
                        state: .thinking,
                        micLevel: 0,
                        playbackLevel: 0,
                        reducedMotion: false
                    ),
                    size: 120
                )
                Text("Thinking")
                    .font(.caption)
            }

            VStack {
                OrbContainerView(
                    config: OrbView.Configuration(
                        state: .speaking,
                        micLevel: 0,
                        playbackLevel: 0.6,
                        reducedMotion: false
                    ),
                    size: 120
                )
                Text("Speaking")
                    .font(.caption)
            }
        }
    }
    .padding()
}
