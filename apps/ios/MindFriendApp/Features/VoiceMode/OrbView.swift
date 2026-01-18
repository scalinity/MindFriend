import SwiftUI
import UIKit

// MARK: - Orb View

/// A dynamic, audio-reactive orb visualization for Voice Mode
/// Uses Canvas + TimelineView for 60fps smooth animations
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
            return 15.0  // Low frame rate when idle
        case .listening:
            return config.micLevel > 0.1 ? 60.0 : 15.0  // High FPS only when detecting audio
        case .userSpeaking, .thinking, .processing, .speaking:
            return 60.0  // High frame rate when active
        default:
            return 30.0  // Medium frame rate for other states
        }
    }

    // MARK: - Reduced Motion Orb

    private var reducedMotionOrb: some View {
        ZStack {
            // Simple circle with opacity changes
            Circle()
                .fill(stateGradient)
                .frame(width: size, height: size)
                .opacity(orbOpacity)

            // State icon
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
        .animation(.easeInOut(duration: 0.3), value: config.state)
    }

    // MARK: - Canvas Drawing

    private func drawOrb(context: GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let baseRadius = min(size.width, size.height) / 2 * 0.7

        // Calculate animation parameters based on state
        let breathingPhase = sin(time * breathingSpeed) * 0.5 + 0.5
        let level = effectiveLevel

        // Draw outer glow rings (state-dependent)
        if config.state.isActive {
            drawGlowRings(
                context: context,
                center: center,
                baseRadius: baseRadius,
                maxRadius: min(size.width, size.height) / 2 * 0.98,
                time: time,
                level: level
            )
        }

        // Draw main orb with deformation
        drawMainOrb(
            context: context,
            center: center,
            baseRadius: baseRadius,
            time: time,
            level: level,
            breathingPhase: breathingPhase
        )

        // Note: Icon is drawn as overlay in OrbContainerView, not in Canvas
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

        // Outer ring 1
        let ring1Phase = sin(time * 2.0) * 0.5 + 0.5
        let ring1Scale = 1.0 + ring1Phase * 0.1
        let ring1BaseRadius = baseRadius * (1.3 + CGFloat(level) * 0.2)
        let ring1Radius = min(ring1BaseRadius, maxRadius / ring1Scale)
        let ring1Opacity = 0.15 + Double(level) * 0.1

        var ring1Path = Path()
        ring1Path.addEllipse(in: CGRect(
            x: center.x - ring1Radius * ring1Scale,
            y: center.y - ring1Radius * ring1Scale,
            width: ring1Radius * 2 * ring1Scale,
            height: ring1Radius * 2 * ring1Scale
        ))
        context.fill(ring1Path, with: .color(color.opacity(ring1Opacity)))

        // Outer ring 2 (if high activity)
        if level > 0.3 {
            let ring2Phase = sin(time * 1.5 + 0.5) * 0.5 + 0.5
            let ring2Scale = 1.0 + ring2Phase * 0.15
            let ring2BaseRadius = baseRadius * (1.5 + CGFloat(level) * 0.3)
            let ring2Radius = min(ring2BaseRadius, maxRadius / ring2Scale)
            let ring2Opacity = 0.08 + Double(level) * 0.05

            var ring2Path = Path()
            ring2Path.addEllipse(in: CGRect(
                x: center.x - ring2Radius * ring2Scale,
                y: center.y - ring2Radius * ring2Scale,
                width: ring2Radius * 2 * ring2Scale,
                height: ring2Radius * 2 * ring2Scale
            ))
            context.fill(ring2Path, with: .color(color.opacity(ring2Opacity)))
        }
    }

    private func drawMainOrb(
        context: GraphicsContext,
        center: CGPoint,
        baseRadius: CGFloat,
        time: Double,
        level: Float,
        breathingPhase: Double
    ) {
        // Create blob-like deformation using multiple sine waves
        let deformAmount = CGFloat(level) * 0.15 + 0.02 // Base deformation + level-based
        let numPoints = 64

        var path = Path()
        for i in 0...numPoints {
            let angle = (Double(i) / Double(numPoints)) * 2 * .pi

            // Combine multiple frequencies for organic look
            let deform1 = sin(angle * 3 + time * deformSpeed * 1.0) * deformAmount
            let deform2 = sin(angle * 5 + time * deformSpeed * 0.7) * deformAmount * 0.5
            let deform3 = sin(angle * 7 + time * deformSpeed * 1.3) * deformAmount * 0.3

            // Add breathing effect
            let breathing = breathingPhase * 0.03

            let totalDeform = deform1 + deform2 + deform3 + breathing
            let radius = baseRadius * (1.0 + totalDeform)

            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()

        // Fill with gradient
        let gradient = Gradient(colors: gradientColors)
        context.fill(
            path,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: center.x - baseRadius, y: center.y - baseRadius),
                endPoint: CGPoint(x: center.x + baseRadius, y: center.y + baseRadius)
            )
        )

        // Apply shadow/glow effect using opacity blend
        context.stroke(
            path,
            with: .color(stateColor.opacity(0.15)),
            lineWidth: 20
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
            return Color.blue.opacity(0.8)
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

    private var gradientColors: [Color] {
        let base = stateColor
        return [base, base.opacity(0.7)]
    }

    private var stateGradient: LinearGradient {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var breathingSpeed: Double {
        switch config.state {
        case .idle, .ready, .listening:
            return 1.5  // Slow breathing when idle
        case .thinking, .processing:
            return 3.0  // Faster when thinking
        case .speaking:
            return 2.0  // Medium when speaking
        default:
            return 1.5
        }
    }

    private var deformSpeed: Double {
        switch config.state {
        case .userSpeaking:
            return 4.0  // Fast deformation when user speaks
        case .speaking:
            return 3.0  // Medium for AI speaking
        case .thinking:
            return 2.5  // Swirling when thinking
        default:
            return 1.5  // Slow drift otherwise
        }
    }

    private var effectiveLevel: Float {
        switch config.state {
        case .userSpeaking:
            return config.micLevel
        case .speaking:
            return config.playbackLevel
        case .thinking, .processing:
            return 0.5  // Constant medium activity
        case .listening, .ready:
            return max(0.1, config.micLevel * 0.5)  // Subtle mic reactivity
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
            return "Tap to interrupt"
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
