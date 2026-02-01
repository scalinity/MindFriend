//
//  SessionView.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-20.
//  Active sensory regulation session UI
//

import SwiftUI

struct SessionView: View {
    @StateObject private var viewModel: SessionViewModel
    @ObservedObject private var visualService: VisualAnimationService
    @Environment(\.dismiss) private var dismiss
    @State private var showErrorAlert = false
    @State private var isLoading = true
    @State private var shouldDismissOnError = false

    private let modality: SensoryModality
    private let patternName: String
    private let patternId: String

    init(
        modality: SensoryModality,
        patternId: String,
        patternName: String,
        sensoryService: SensoryRegulationService,
        tactileService: TactilePatternService,
        visualService: VisualAnimationService,
        audioService: AudioSoundscapeService
    ) {
        self.modality = modality
        self.patternName = patternName
        self.patternId = patternId
        self.visualService = visualService

        _viewModel = StateObject(wrappedValue: SessionViewModel(
            modality: modality,
            patternId: patternId,
            sensoryService: sensoryService,
            tactileService: tactileService,
            visualService: visualService,
            audioService: audioService
        ))
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if isLoading {
                // Loading state
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text("Starting \(patternName)...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            } else {
                VStack(spacing: 32) {
                    // Header
                    HStack {
                        Button {
                            Task {
                                await viewModel.endSession()
                                dismiss()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(patternName)
                                .font(.headline)
                                .foregroundColor(.white)

                            Text(modality.displayName)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)

                    Spacer()

                    // Main content area - visual animation or timer
                    if modality.rawValue == "visual" {
                        // Visual animation display
                        VisualAnimationDisplay(
                            frame: visualService.currentFrame,
                            animationType: animationType,
                            colors: animationColors
                        )
                        .frame(maxWidth: .infinity, maxHeight: 300)
                        
                        // Timer below animation
                        VStack(spacing: 8) {
                            Text(viewModel.elapsedTime)
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.8))

                            ProgressView(value: viewModel.progressPercentage)
                                .tint(.white.opacity(0.6))
                                .frame(width: 150)
                        }
                    } else {
                        // Timer display for tactile/audio
                        VStack(spacing: 8) {
                            Text(viewModel.elapsedTime)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            ProgressView(value: viewModel.progressPercentage)
                                .tint(.white)
                                .frame(width: 200)
                        }
                    }

                    Spacer()

                    // Controls
                    HStack(spacing: 40) {
                        // Play/Pause button
                        Button {
                            Task {
                                await viewModel.togglePlayPause()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 80, height: 80)

                                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title)
                                    .foregroundColor(.black)
                            }
                        }

                        // Stop button
                        Button {
                            Task {
                                await viewModel.endSession()
                                dismiss()
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                    .font(.title2)
                                Text("End")
                                    .font(.caption)
                            }
                            .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await viewModel.startSession()
            isLoading = false
            
            // If there was an error during startup, mark for dismiss
            if viewModel.errorMessage != nil {
                shouldDismissOnError = true
            }
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            showErrorAlert = newValue != nil
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") {
                viewModel.errorMessage = nil
                // Dismiss if this was a startup error
                if shouldDismissOnError {
                    dismiss()
                }
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var animationType: VisualAnimation.AnimationType {
        VisualAnimation.library.first(where: { $0.id == patternId })?.type ?? .expandingCircle
    }
    
    private var animationColors: [Color] {
        guard let animation = VisualAnimation.library.first(where: { $0.id == patternId }) else {
            return [.blue, .purple]
        }
        return animation.colors.compactMap { Color(hex: $0) }
    }
}

// MARK: - Visual Animation Display

struct VisualAnimationDisplay: View {
    let frame: VisualAnimationService.AnimationFrame
    let animationType: VisualAnimation.AnimationType
    let colors: [Color]
    
    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height / 2
            let baseSize: CGFloat = min(geometry.size.width, geometry.size.height) * 0.4
            
            ZStack {
                switch animationType {
                case .expandingCircle:
                    ImmersiveBreathingOrbView(progress: frame.progress, colors: colors)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .position(x: centerX, y: centerY)

                case .pulsingSquare:
                    ImmersiveGeometricPulseView(progress: frame.progress, colors: colors)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .position(x: centerX, y: centerY)

                case .wave:
                    ImmersiveOceanWaveView(progress: frame.progress, colors: colors)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .position(x: centerX, y: centerY)

                case .bouncingDot:
                    ImmersiveFloatingOrbsView(progress: frame.progress, colors: colors)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .position(x: centerX, y: centerY)

                case .spiral:
                    ImmersiveCosmicSpiralView(progress: frame.progress, colors: colors)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .position(x: centerX, y: centerY)

                case .flowerBloom:
                    ImmersiveLotusBloomView(progress: frame.progress, colors: colors)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .position(x: centerX, y: centerY)

                case .dotGrid:
                    ImmersiveBreathingGridView(progress: frame.progress, colors: colors)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .position(x: centerX, y: centerY)

                case .ribbonFlow:
                    ImmersiveSilkRibbonView(progress: frame.progress, colors: colors)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .position(x: centerX, y: centerY)
                }
            }
        }
    }
}

// MARK: - Custom Shapes

struct SensoryWaveShape: Shape {
    var progress: Double
    
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let amplitude: CGFloat = rect.height * 0.3
        let wavelength = rect.width / 2
        
        // Start at bottom left
        path.move(to: CGPoint(x: 0, y: rect.height))
        
        // Draw bottom left to start of wave
        path.addLine(to: CGPoint(x: 0, y: midY))
        
        // Draw the wave curve
        for x in stride(from: 0, through: rect.width, by: 2) {
            let relativeX = x / wavelength
            let phase = progress * 2 * .pi
            let y = midY + amplitude * sin((relativeX * 2 * .pi) + phase)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        // Close the shape by going down to bottom right, then back to start
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        
        return path
    }
}

struct SpiralShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = min(rect.width, rect.height) / 2
        
        var angle: CGFloat = 0
        let turns: CGFloat = 3
        let pointCount = 100
        
        for i in 0..<pointCount {
            let progress = CGFloat(i) / CGFloat(pointCount - 1)
            let radius = maxRadius * progress
            angle = progress * turns * 2 * .pi
            
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        return path
    }
}

struct FlowerShape: Shape {
    let petalCount: Int
    var bloomProgress: CGFloat
    
    var animatableData: CGFloat {
        get { bloomProgress }
        set { bloomProgress = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = min(rect.width, rect.height) / 2 * bloomProgress
        
        for i in 0..<petalCount {
            let angle = (CGFloat(i) / CGFloat(petalCount)) * 2 * .pi
            let petalPath = petalPath(center: center, angle: angle, maxRadius: maxRadius)
            path.addPath(petalPath)
        }
        
        // Add center circle
        let centerRadius = maxRadius * 0.2
        path.addEllipse(in: CGRect(
            x: center.x - centerRadius,
            y: center.y - centerRadius,
            width: centerRadius * 2,
            height: centerRadius * 2
        ))
        
        return path
    }
    
    private func petalPath(center: CGPoint, angle: CGFloat, maxRadius: CGFloat) -> Path {
        var path = Path()
        let petalLength = maxRadius * 0.8
        let petalWidth = maxRadius * 0.3
        
        let tipX = center.x + petalLength * cos(angle)
        let tipY = center.y + petalLength * sin(angle)
        
        let control1Angle = angle - .pi / 6
        let control2Angle = angle + .pi / 6
        
        let control1X = center.x + petalWidth * cos(control1Angle)
        let control1Y = center.y + petalWidth * sin(control1Angle)
        
        let control2X = center.x + petalWidth * cos(control2Angle)
        let control2Y = center.y + petalWidth * sin(control2Angle)
        
        path.move(to: center)
        path.addQuadCurve(to: CGPoint(x: tipX, y: tipY), control: CGPoint(x: control1X, y: control1Y))
        path.addQuadCurve(to: center, control: CGPoint(x: control2X, y: control2Y))
        
        return path
    }
}

struct DotGridView: View {
    let rows: Int
    let columns: Int
    let scale: CGFloat
    let colors: [Color]
    
    var body: some View {
        GeometryReader { geometry in
            let dotSize: CGFloat = 12 * scale
            let spacingX = geometry.size.width / CGFloat(columns + 1)
            let spacingY = geometry.size.height / CGFloat(rows + 1)
            
            ForEach(0..<rows, id: \.self) { row in
                ForEach(0..<columns, id: \.self) { col in
                    let x = spacingX * CGFloat(col + 1)
                    let y = spacingY * CGFloat(row + 1)
                    
                    Circle()
                        .fill(colors.first ?? .blue)
                        .frame(width: dotSize, height: dotSize)
                        .position(x: x, y: y)
                }
            }
        }
    }
}

struct RibbonFlowView: View {
    let offset: CGSize
    let rotation: Angle
    let scale: CGFloat
    let colors: [Color]
    
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                RibbonShape()
                    .fill(
                        LinearGradient(
                            colors: colors.map { $0.opacity(0.6 - Double(index) * 0.15) },
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: offset.width + CGFloat(index) * 10,
                            y: offset.height + CGFloat(index) * 5)
                    .rotationEffect(rotation + .degrees(Double(index) * 5))
                    .scaleEffect(scale - CGFloat(index) * 0.1)
            }
        }
    }
}

struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.midY),
            control1: CGPoint(x: rect.width * 0.3, y: 0),
            control2: CGPoint(x: rect.width * 0.7, y: rect.height)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY + 10))
        path.addCurve(
            to: CGPoint(x: 0, y: rect.midY + 10),
            control1: CGPoint(x: rect.width * 0.7, y: rect.height + 10),
            control2: CGPoint(x: rect.width * 0.3, y: 10)
        )
        path.closeSubpath()

        return path
    }
}

// MARK: - Immersive Ocean Wave View

struct ImmersiveOceanWaveView: View {
    let progress: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Sky/horizon gradient background
                LinearGradient(
                    colors: [
                        colors.first?.opacity(0.3) ?? Color.blue.opacity(0.3),
                        colors.first?.opacity(0.1) ?? Color.blue.opacity(0.1),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )

                // Back wave layer (slowest, most subtle)
                // Uses 1 full cycle, offset by 0.0
                OceanWaveLayer(
                    progress: progress,
                    phaseOffset: 0.0,
                    amplitude: 25,
                    wavelength: geometry.size.width * 1.2,
                    verticalOffset: geometry.size.height * 0.35
                )
                .fill(
                    LinearGradient(
                        colors: [
                            colors.first?.opacity(0.2) ?? Color.teal.opacity(0.2),
                            colors.first?.opacity(0.3) ?? Color.teal.opacity(0.3)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Middle-back wave layer
                // Uses 1 full cycle, offset by 0.25 (quarter phase)
                OceanWaveLayer(
                    progress: progress,
                    phaseOffset: 0.25,
                    amplitude: 35,
                    wavelength: geometry.size.width * 0.9,
                    verticalOffset: geometry.size.height * 0.42
                )
                .fill(
                    LinearGradient(
                        colors: [
                            colors.first?.opacity(0.3) ?? Color.teal.opacity(0.3),
                            (colors.count > 1 ? colors[1] : colors.first)?.opacity(0.4) ?? Color.cyan.opacity(0.4)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Middle wave layer
                // Uses 1 full cycle, offset by 0.5 (half phase)
                OceanWaveLayer(
                    progress: progress,
                    phaseOffset: 0.5,
                    amplitude: 45,
                    wavelength: geometry.size.width * 0.7,
                    verticalOffset: geometry.size.height * 0.5
                )
                .fill(
                    LinearGradient(
                        colors: [
                            colors.first?.opacity(0.5) ?? Color.teal.opacity(0.5),
                            (colors.count > 1 ? colors[1] : colors.first)?.opacity(0.6) ?? Color.cyan.opacity(0.6)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Front-middle wave layer
                // Uses 1 full cycle, offset by 0.75
                OceanWaveLayer(
                    progress: progress,
                    phaseOffset: 0.75,
                    amplitude: 55,
                    wavelength: geometry.size.width * 0.55,
                    verticalOffset: geometry.size.height * 0.58
                )
                .fill(
                    LinearGradient(
                        colors: [
                            colors.first?.opacity(0.7) ?? Color.teal.opacity(0.7),
                            (colors.count > 1 ? colors[1] : colors.first)?.opacity(0.8) ?? Color.cyan.opacity(0.8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Front wave layer (fastest, most prominent)
                // Uses 2 full cycles for faster movement, offset by 0.33
                OceanWaveLayer(
                    progress: progress,
                    phaseOffset: 0.33,
                    speedMultiplier: 2,
                    amplitude: 65,
                    wavelength: geometry.size.width * 0.45,
                    verticalOffset: geometry.size.height * 0.68
                )
                .fill(
                    LinearGradient(
                        colors: [
                            colors.first ?? Color.teal,
                            colors.count > 1 ? colors[1] : (colors.first ?? Color.cyan)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Closest wave layer (foam/shore effect)
                // Uses 2 full cycles, offset by 0.66
                OceanWaveLayer(
                    progress: progress,
                    phaseOffset: 0.66,
                    speedMultiplier: 2,
                    amplitude: 40,
                    wavelength: geometry.size.width * 0.35,
                    verticalOffset: geometry.size.height * 0.82
                )
                .fill(
                    LinearGradient(
                        colors: [
                            (colors.count > 1 ? colors[1] : colors.first)?.opacity(0.9) ?? Color.cyan.opacity(0.9),
                            Color.white.opacity(0.3)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }
}

// MARK: - Ocean Wave Layer Shape

struct OceanWaveLayer: Shape {
    var progress: Double
    var phaseOffset: Double
    var speedMultiplier: Int
    var amplitude: CGFloat
    var wavelength: CGFloat
    var verticalOffset: CGFloat

    init(
        progress: Double,
        phaseOffset: Double = 0,
        speedMultiplier: Int = 1,
        amplitude: CGFloat,
        wavelength: CGFloat,
        verticalOffset: CGFloat
    ) {
        self.progress = progress
        self.phaseOffset = phaseOffset
        self.speedMultiplier = speedMultiplier
        self.amplitude = amplitude
        self.wavelength = wavelength
        self.verticalOffset = verticalOffset
    }

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let startY = verticalOffset

        // Start at bottom left
        path.move(to: CGPoint(x: 0, y: rect.height))

        // Go up to the wave start
        path.addLine(to: CGPoint(x: 0, y: startY))

        // Perfect loop: use integer multiples of 2π so wave returns to exact start
        // speedMultiplier ensures we complete N full cycles per animation loop
        let phase = (progress + phaseOffset) * Double(speedMultiplier) * 2.0 * .pi

        for x in stride(from: 0, through: rect.width, by: 2) {
            let relativeX = x / wavelength
            // Primary wave
            let primaryWave = sin((relativeX * 2.0 * .pi) + phase)
            // Secondary wave uses 2x frequency but same phase progression for perfect loop
            let secondaryWave = sin((relativeX * 4.0 * .pi) + phase * 2.0) * 0.3
            let y = startY + amplitude * (primaryWave + secondaryWave)
            path.addLine(to: CGPoint(x: x, y: y))
        }

        // Close the shape
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()

        return path
    }
}

// MARK: - Immersive Breathing Orb View (Expanding Circle)

struct ImmersiveBreathingOrbView: View {
    let progress: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height / 2
            let maxRadius = min(geometry.size.width, geometry.size.height) * 0.4

            ZStack {
                // Ambient background glow
                RadialGradient(
                    colors: [
                        colors.first?.opacity(0.15) ?? Color.blue.opacity(0.15),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: maxRadius * 2
                )

                // Outer aura ring (75% phase offset, slowest)
                BreathingRing(
                    progress: progress,
                    phaseOffset: 0.75,
                    baseRadius: maxRadius * 1.6,
                    ringWidth: maxRadius * 0.15,
                    color: colors.first ?? .blue,
                    opacity: 0.15
                )
                .position(x: centerX, y: centerY)

                // Middle ring (50% phase offset)
                BreathingRing(
                    progress: progress,
                    phaseOffset: 0.5,
                    baseRadius: maxRadius * 1.3,
                    ringWidth: maxRadius * 0.12,
                    color: colors.first ?? .blue,
                    opacity: 0.25
                )
                .position(x: centerX, y: centerY)

                // Inner glow ring (25% phase offset)
                BreathingRing(
                    progress: progress,
                    phaseOffset: 0.25,
                    baseRadius: maxRadius * 1.0,
                    ringWidth: maxRadius * 0.1,
                    color: colors.count > 1 ? colors[1] : (colors.first ?? .cyan),
                    opacity: 0.4
                )
                .position(x: centerX, y: centerY)

                // Core orb with glow
                CoreOrb(
                    progress: progress,
                    maxRadius: maxRadius * 0.7,
                    colors: colors
                )
                .position(x: centerX, y: centerY)

                // Floating particles
                ForEach(0..<10, id: \.self) { index in
                    FloatingParticle(
                        progress: progress,
                        index: index,
                        centerX: centerX,
                        centerY: centerY,
                        maxRadius: maxRadius,
                        color: colors.count > 1 ? colors[1] : (colors.first ?? .white)
                    )
                }
            }
        }
    }
}

struct BreathingRing: View {
    let progress: Double
    let phaseOffset: Double
    let baseRadius: CGFloat
    let ringWidth: CGFloat
    let color: Color
    let opacity: Double

    var body: some View {
        let phase = (progress + phaseOffset).truncatingRemainder(dividingBy: 1.0)
        let scale = 0.7 + 0.3 * sin(phase * 2 * .pi)

        Circle()
            .stroke(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(opacity * 0.3)],
                    center: .center,
                    startRadius: baseRadius * scale - ringWidth,
                    endRadius: baseRadius * scale
                ),
                lineWidth: ringWidth
            )
            .frame(width: baseRadius * 2 * scale, height: baseRadius * 2 * scale)
            .blur(radius: 3)
    }
}

struct CoreOrb: View {
    let progress: Double
    let maxRadius: CGFloat
    let colors: [Color]

    var body: some View {
        let scale = 0.5 + 0.5 * sin(progress * 2 * .pi)
        let glowOpacity = 0.6 + 0.4 * sin(progress * 2 * .pi)

        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            (colors.first ?? .blue).opacity(0.5),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: maxRadius * scale * 0.5,
                        endRadius: maxRadius * scale * 1.5
                    )
                )
                .frame(width: maxRadius * 3 * scale, height: maxRadius * 3 * scale)
                .blur(radius: 10)

            // Main orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            colors.count > 1 ? colors[1] : .white,
                            colors.first ?? .blue
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: maxRadius * scale
                    )
                )
                .frame(width: maxRadius * 2 * scale, height: maxRadius * 2 * scale)
                .opacity(glowOpacity)
        }
    }
}

struct FloatingParticle: View {
    let progress: Double
    let index: Int
    let centerX: CGFloat
    let centerY: CGFloat
    let maxRadius: CGFloat
    let color: Color

    var body: some View {
        let angle = Double(index) * (2 * .pi / 10) + progress * 2 * .pi
        let radiusOffset = 0.8 + 0.2 * sin(progress * 4 * .pi + Double(index))
        let distance = maxRadius * radiusOffset * (0.9 + 0.4 * CGFloat(index % 3) / 3)
        let x = centerX + distance * cos(angle)
        let y = centerY + distance * sin(angle)
        let particleOpacity = 0.3 + 0.4 * sin(progress * 2 * .pi + Double(index) * 0.5)

        Circle()
            .fill(color.opacity(particleOpacity))
            .frame(width: 6 + CGFloat(index % 3) * 2, height: 6 + CGFloat(index % 3) * 2)
            .blur(radius: 2)
            .position(x: x, y: y)
    }
}

// MARK: - Immersive Geometric Pulse View (Pulsing Square)

struct ImmersiveGeometricPulseView: View {
    let progress: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height / 2
            let baseSize = min(geometry.size.width, geometry.size.height) * 0.35

            ZStack {
                // Background glow
                RoundedRectangle(cornerRadius: 30)
                    .fill(
                        RadialGradient(
                            colors: [colors.first?.opacity(0.1) ?? Color.purple.opacity(0.1), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: baseSize * 2
                        )
                    )
                    .frame(width: baseSize * 4, height: baseSize * 4)
                    .position(x: centerX, y: centerY)

                // Outer frame (very slow counter-rotation)
                GeometricFrame(
                    progress: progress,
                    phaseOffset: 0.75,
                    rotationDirection: -1,
                    rotationSpeed: 0.5,
                    size: baseSize * 2.2,
                    cornerRadius: 40,
                    color: colors.first ?? .purple,
                    opacity: 0.15
                )
                .position(x: centerX, y: centerY)

                // Middle frame (slower rotation)
                GeometricFrame(
                    progress: progress,
                    phaseOffset: 0.5,
                    rotationDirection: 1,
                    rotationSpeed: 0.75,
                    size: baseSize * 1.7,
                    cornerRadius: 30,
                    color: colors.first ?? .purple,
                    opacity: 0.25
                )
                .position(x: centerX, y: centerY)

                // Inner frame (45° offset, opposite rotation)
                GeometricFrame(
                    progress: progress,
                    phaseOffset: 0.25,
                    rotationDirection: -1,
                    rotationSpeed: 1.0,
                    size: baseSize * 1.3,
                    cornerRadius: 24,
                    color: colors.count > 1 ? colors[1] : (colors.first ?? .purple),
                    opacity: 0.4,
                    baseRotation: 45
                )
                .position(x: centerX, y: centerY)

                // Center square (main focus)
                GeometricFrame(
                    progress: progress,
                    phaseOffset: 0.0,
                    rotationDirection: 1,
                    rotationSpeed: 1.0,
                    size: baseSize,
                    cornerRadius: 20,
                    color: colors.count > 1 ? colors[1] : (colors.first ?? .purple),
                    opacity: 0.8
                )
                .position(x: centerX, y: centerY)

                // Corner accents
                ForEach(0..<4, id: \.self) { corner in
                    CornerAccent(
                        progress: progress,
                        corner: corner,
                        centerX: centerX,
                        centerY: centerY,
                        distance: baseSize * 1.1,
                        color: colors.first ?? .purple
                    )
                }
            }
        }
    }
}

struct GeometricFrame: View {
    let progress: Double
    let phaseOffset: Double
    let rotationDirection: Double
    let rotationSpeed: Double
    let size: CGFloat
    let cornerRadius: CGFloat
    let color: Color
    let opacity: Double
    var baseRotation: Double = 0

    var body: some View {
        let phase = (progress + phaseOffset).truncatingRemainder(dividingBy: 1.0)
        let scale = 0.9 + 0.1 * sin(phase * 2 * .pi)
        let rotation = baseRotation + rotationDirection * 15 * sin(phase * 2 * .pi) * rotationSpeed

        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(
                LinearGradient(
                    colors: [color.opacity(opacity), color.opacity(opacity * 0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 3
            )
            .frame(width: size * scale, height: size * scale)
            .rotationEffect(.degrees(rotation))
    }
}

struct CornerAccent: View {
    let progress: Double
    let corner: Int
    let centerX: CGFloat
    let centerY: CGFloat
    let distance: CGFloat
    let color: Color

    var body: some View {
        let angle = Double(corner) * (.pi / 2) + .pi / 4
        let pulsePhase = (progress + Double(corner) * 0.25).truncatingRemainder(dividingBy: 1.0)
        let scale = 0.6 + 0.4 * sin(pulsePhase * 2 * .pi)
        let x = centerX + distance * cos(angle)
        let y = centerY + distance * sin(angle)

        Circle()
            .fill(color.opacity(0.5 * scale))
            .frame(width: 12 * scale, height: 12 * scale)
            .blur(radius: 2)
            .position(x: x, y: y)
    }
}

// MARK: - Immersive Floating Orbs View (Bouncing Dot)

struct ImmersiveFloatingOrbsView: View {
    let progress: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height / 2
            let maxBounce: CGFloat = geometry.size.height * 0.2

            ZStack {
                // Background stars
                ForEach(0..<20, id: \.self) { index in
                    BackgroundStar(index: index, geometry: geometry, color: colors.first ?? .red)
                }

                // Ambient glow following primary orb
                let primaryY = centerY + maxBounce * sin(progress * 2 * .pi)
                RadialGradient(
                    colors: [colors.first?.opacity(0.2) ?? Color.red.opacity(0.2), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 150
                )
                .frame(width: 300, height: 300)
                .position(x: centerX, y: primaryY)

                // Trail particles
                ForEach(0..<6, id: \.self) { index in
                    TrailParticle(
                        progress: progress,
                        index: index,
                        centerX: centerX,
                        centerY: centerY,
                        maxBounce: maxBounce,
                        color: colors.count > 1 ? colors[1] : (colors.first ?? .red)
                    )
                }

                // Companion orb B (60% phase delay)
                CompanionOrb(
                    progress: progress,
                    phaseOffset: 0.6,
                    centerX: centerX - 80,
                    centerY: centerY,
                    maxBounce: maxBounce * 0.7,
                    size: 35,
                    colors: colors
                )

                // Companion orb A (30% phase delay)
                CompanionOrb(
                    progress: progress,
                    phaseOffset: 0.3,
                    centerX: centerX + 70,
                    centerY: centerY,
                    maxBounce: maxBounce * 0.8,
                    size: 45,
                    colors: colors
                )

                // Primary orb
                PrimaryOrb(
                    progress: progress,
                    centerX: centerX,
                    centerY: centerY,
                    maxBounce: maxBounce,
                    colors: colors
                )
            }
        }
    }
}

struct BackgroundStar: View {
    let index: Int
    let geometry: GeometryProxy
    let color: Color

    var body: some View {
        let random = Double(index * 7 + 3)
        let x = CGFloat((Int(random * 17) % Int(geometry.size.width)))
        let y = CGFloat((Int(random * 23) % Int(geometry.size.height)))
        let size: CGFloat = CGFloat(2 + index % 3)
        let opacity = 0.2 + Double(index % 5) * 0.1

        Circle()
            .fill(color.opacity(opacity))
            .frame(width: size, height: size)
            .position(x: x, y: y)
    }
}

struct TrailParticle: View {
    let progress: Double
    let index: Int
    let centerX: CGFloat
    let centerY: CGFloat
    let maxBounce: CGFloat
    let color: Color

    var body: some View {
        let delay = Double(index) * 0.08
        let trailProgress = (progress - delay).truncatingRemainder(dividingBy: 1.0)
        let adjustedProgress = trailProgress < 0 ? trailProgress + 1 : trailProgress
        let y = centerY + maxBounce * sin(adjustedProgress * 2 * .pi)
        let opacity = 0.6 - Double(index) * 0.1
        let size: CGFloat = CGFloat(20 - index * 2)

        Circle()
            .fill(color.opacity(opacity))
            .frame(width: size, height: size)
            .blur(radius: CGFloat(index + 1))
            .position(x: centerX, y: y)
    }
}

struct CompanionOrb: View {
    let progress: Double
    let phaseOffset: Double
    let centerX: CGFloat
    let centerY: CGFloat
    let maxBounce: CGFloat
    let size: CGFloat
    let colors: [Color]

    var body: some View {
        let phase = (progress + phaseOffset).truncatingRemainder(dividingBy: 1.0)
        let y = centerY + maxBounce * sin(phase * 2 * .pi)
        let squash = 1.0 + 0.1 * cos(phase * 2 * .pi)

        ZStack {
            // Glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [colors.first?.opacity(0.4) ?? Color.red.opacity(0.4), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size
                    )
                )
                .frame(width: size * 2, height: size * 2)
                .blur(radius: 5)

            // Orb
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            colors.count > 1 ? colors[1] : .white,
                            colors.first ?? .red
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .frame(width: size, height: size * squash)
        }
        .position(x: centerX, y: y)
    }
}

struct PrimaryOrb: View {
    let progress: Double
    let centerX: CGFloat
    let centerY: CGFloat
    let maxBounce: CGFloat
    let colors: [Color]

    var body: some View {
        let y = centerY + maxBounce * sin(progress * 2 * .pi)
        let squash = 1.0 + 0.15 * cos(progress * 2 * .pi)

        ZStack {
            // Large glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [colors.first?.opacity(0.5) ?? Color.red.opacity(0.5), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .blur(radius: 15)

            // Main orb
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            .white,
                            colors.count > 1 ? colors[1] : (colors.first ?? .red),
                            colors.first ?? .red
                        ],
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: 40
                    )
                )
                .frame(width: 70, height: 70 * squash)
        }
        .position(x: centerX, y: y)
    }
}

// MARK: - Immersive Cosmic Spiral View (Premium)

struct ImmersiveCosmicSpiralView: View {
    let progress: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height / 2
            let maxRadius = min(geometry.size.width, geometry.size.height) * 0.45

            ZStack {
                // Star field (background layer)
                ForEach(0..<40, id: \.self) { index in
                    CosmicStar(
                        index: index,
                        progress: progress,
                        centerX: centerX,
                        centerY: centerY,
                        maxRadius: maxRadius,
                        color: colors.first ?? .purple
                    )
                }

                // Dust clouds
                ForEach(0..<3, id: \.self) { index in
                    DustCloud(
                        index: index,
                        progress: progress,
                        centerX: centerX,
                        centerY: centerY,
                        maxRadius: maxRadius,
                        color: colors.first ?? .purple
                    )
                }

                // Outer spiral arms (slower, wider)
                SpiralArm(
                    progress: progress,
                    armIndex: 0,
                    speedMultiplier: 1,
                    maxRadius: maxRadius,
                    color: colors.first ?? .purple,
                    opacity: 0.3
                )
                .position(x: centerX, y: centerY)

                SpiralArm(
                    progress: progress,
                    armIndex: 1,
                    speedMultiplier: 1,
                    maxRadius: maxRadius,
                    color: colors.first ?? .purple,
                    opacity: 0.3
                )
                .position(x: centerX, y: centerY)

                // Inner spiral arms (gradual rotation)
                SpiralArm(
                    progress: progress,
                    armIndex: 0,
                    speedMultiplier: 2,
                    maxRadius: maxRadius * 0.7,
                    color: colors.count > 1 ? colors[1] : (colors.first ?? .purple),
                    opacity: 0.5
                )
                .position(x: centerX, y: centerY)

                SpiralArm(
                    progress: progress,
                    armIndex: 1,
                    speedMultiplier: 2,
                    maxRadius: maxRadius * 0.7,
                    color: colors.count > 1 ? colors[1] : (colors.first ?? .purple),
                    opacity: 0.5
                )
                .position(x: centerX, y: centerY)

                // Core nebula
                CosmicCore(
                    progress: progress,
                    maxRadius: maxRadius * 0.25,
                    colors: colors
                )
                .position(x: centerX, y: centerY)
            }
        }
    }
}

struct CosmicStar: View {
    let index: Int
    let progress: Double
    let centerX: CGFloat
    let centerY: CGFloat
    let maxRadius: CGFloat
    let color: Color

    var body: some View {
        let seed = Double(index * 7 + 13)
        let baseAngle = seed.truncatingRemainder(dividingBy: 2 * .pi)
        let distance = maxRadius * (0.3 + CGFloat(seed.truncatingRemainder(dividingBy: 0.7)))
        let rotationSpeed = 0.2 + (seed.truncatingRemainder(dividingBy: 0.3))
        let angle = baseAngle + progress * 2 * .pi * rotationSpeed

        let x = centerX + distance * cos(angle)
        let y = centerY + distance * sin(angle)
        let size: CGFloat = 1 + CGFloat(index % 4)
        let twinkle = 0.3 + 0.7 * sin(progress * 4 * .pi + seed)

        Circle()
            .fill(color.opacity(twinkle * 0.8))
            .frame(width: size, height: size)
            .position(x: x, y: y)
    }
}

struct DustCloud: View {
    let index: Int
    let progress: Double
    let centerX: CGFloat
    let centerY: CGFloat
    let maxRadius: CGFloat
    let color: Color

    var body: some View {
        let angle = Double(index) * (2 * .pi / 3) + progress * 0.5 * .pi
        let distance = maxRadius * (0.5 + CGFloat(index) * 0.15)
        let x = centerX + distance * cos(angle)
        let y = centerY + distance * sin(angle)
        let opacity = 0.1 + 0.05 * sin(progress * 2 * .pi + Double(index))

        Ellipse()
            .fill(color.opacity(opacity))
            .frame(width: 80 + CGFloat(index) * 20, height: 40 + CGFloat(index) * 10)
            .rotationEffect(.radians(angle))
            .blur(radius: 20)
            .position(x: x, y: y)
    }
}

struct SpiralArm: View {
    let progress: Double
    let armIndex: Int
    let speedMultiplier: Int
    let maxRadius: CGFloat
    let color: Color
    let opacity: Double

    var body: some View {
        let rotation = progress * Double(speedMultiplier) * 2 * .pi

        SpiralArmShape(armOffset: Double(armIndex) * .pi, turns: 2)
            .stroke(
                AngularGradient(
                    colors: [color.opacity(0), color.opacity(opacity), color.opacity(0)],
                    center: .center
                ),
                lineWidth: 15
            )
            .frame(width: maxRadius * 2, height: maxRadius * 2)
            .rotationEffect(.radians(rotation))
            .blur(radius: 5)
    }
}

struct SpiralArmShape: Shape {
    let armOffset: Double
    let turns: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = min(rect.width, rect.height) / 2

        for i in 0..<100 {
            let t = Double(i) / 100
            let angle = armOffset + t * turns * 2 * .pi
            let radius = maxRadius * t
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }
}

struct CosmicCore: View {
    let progress: Double
    let maxRadius: CGFloat
    let colors: [Color]

    var body: some View {
        let pulse = 0.8 + 0.2 * sin(progress * 2 * .pi)
        let innerPulse = 0.7 + 0.3 * sin(progress * 4 * .pi)

        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [colors.first?.opacity(0.6) ?? Color.purple.opacity(0.6), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: maxRadius * 2 * pulse
                    )
                )
                .frame(width: maxRadius * 4 * pulse, height: maxRadius * 4 * pulse)
                .blur(radius: 15)

            // Inner core
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white,
                            colors.count > 1 ? colors[1] : .white,
                            colors.first ?? .purple
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: maxRadius * innerPulse
                    )
                )
                .frame(width: maxRadius * 2 * innerPulse, height: maxRadius * 2 * innerPulse)
        }
    }
}

// MARK: - Immersive Lotus Bloom View (Premium)

struct ImmersiveLotusBloomView: View {
    let progress: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height / 2
            let maxRadius = min(geometry.size.width, geometry.size.height) * 0.4

            ZStack {
                // Ambient glow behind flower
                RadialGradient(
                    colors: [
                        colors.first?.opacity(0.2) ?? Color.pink.opacity(0.2),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: maxRadius * 1.5
                )
                .position(x: centerX, y: centerY)

                // Sepals/leaves (green, subtle movement)
                SepalLayer(
                    progress: progress,
                    maxRadius: maxRadius * 1.1,
                    color: .green.opacity(0.4)
                )
                .position(x: centerX, y: centerY)

                // Outer petals (10, 50% bloom delay)
                PetalRing(
                    progress: progress,
                    phaseOffset: 0.5,
                    petalCount: 10,
                    maxRadius: maxRadius,
                    color: colors.first ?? .pink,
                    opacity: 0.5
                )
                .position(x: centerX, y: centerY)

                // Middle petals (8, 25% bloom delay)
                PetalRing(
                    progress: progress,
                    phaseOffset: 0.25,
                    petalCount: 8,
                    maxRadius: maxRadius * 0.75,
                    color: colors.first ?? .pink,
                    opacity: 0.7
                )
                .position(x: centerX, y: centerY)

                // Inner petals (6, no delay)
                PetalRing(
                    progress: progress,
                    phaseOffset: 0.0,
                    petalCount: 6,
                    maxRadius: maxRadius * 0.5,
                    color: colors.count > 1 ? colors[1] : (colors.first ?? .pink),
                    opacity: 0.9
                )
                .position(x: centerX, y: centerY)

                // Center stamen
                LotusStamen(
                    progress: progress,
                    maxRadius: maxRadius * 0.15,
                    colors: colors
                )
                .position(x: centerX, y: centerY)

                // Dewdrops
                ForEach(0..<5, id: \.self) { index in
                    Dewdrop(
                        index: index,
                        progress: progress,
                        centerX: centerX,
                        centerY: centerY,
                        maxRadius: maxRadius
                    )
                }
            }
        }
    }
}

struct SepalLayer: View {
    let progress: Double
    let maxRadius: CGFloat
    let color: Color

    var body: some View {
        let bloomProgress = sin(progress * .pi)

        ForEach(0..<5, id: \.self) { index in
            let angle = Double(index) * (2 * .pi / 5) + .pi / 10
            let length = maxRadius * (0.6 + 0.2 * bloomProgress)

            SepalShape()
                .fill(color)
                .frame(width: 30, height: length)
                .rotationEffect(.radians(angle - .pi / 2))
                .offset(
                    x: (length / 2) * cos(angle),
                    y: (length / 2) * sin(angle)
                )
        }
    }
}

struct SepalShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: 0),
            control: CGPoint(x: rect.maxX, y: rect.midY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: 0, y: rect.midY)
        )
        return path
    }
}

struct PetalRing: View {
    let progress: Double
    let phaseOffset: Double
    let petalCount: Int
    let maxRadius: CGFloat
    let color: Color
    let opacity: Double

    var body: some View {
        let adjustedProgress = max(0, min(1, (progress - phaseOffset * 0.3) / 0.7))
        let bloomProgress = sin(adjustedProgress * .pi)
        let rotation = 20 * bloomProgress

        ForEach(0..<petalCount, id: \.self) { index in
            let angle = Double(index) * (2 * .pi / Double(petalCount))
            let petalLength = maxRadius * (0.4 + 0.6 * bloomProgress)

            PetalShape()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(opacity * 0.6), color.opacity(opacity)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: petalLength * 0.4, height: petalLength)
                .rotationEffect(.degrees(rotation))
                .rotationEffect(.radians(angle - .pi / 2))
                .offset(
                    x: (petalLength * 0.4) * cos(angle),
                    y: (petalLength * 0.4) * sin(angle)
                )
        }
    }
}

struct PetalShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: 0),
            control1: CGPoint(x: rect.maxX + width * 0.2, y: rect.maxY - height * 0.3),
            control2: CGPoint(x: rect.maxX, y: height * 0.2)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: 0, y: height * 0.2),
            control2: CGPoint(x: -width * 0.2, y: rect.maxY - height * 0.3)
        )
        return path
    }
}

struct LotusStamen: View {
    let progress: Double
    let maxRadius: CGFloat
    let colors: [Color]

    var body: some View {
        let pulse = 0.8 + 0.2 * sin(progress * 4 * .pi)

        ZStack {
            // Glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.yellow.opacity(0.6), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: maxRadius * 2
                    )
                )
                .frame(width: maxRadius * 4, height: maxRadius * 4)
                .blur(radius: 8)

            // Stamen dots
            ForEach(0..<8, id: \.self) { index in
                let angle = Double(index) * (2 * .pi / 8)
                let x = maxRadius * 0.6 * cos(angle)
                let y = maxRadius * 0.6 * sin(angle)

                Circle()
                    .fill(Color.orange)
                    .frame(width: 6 * pulse, height: 6 * pulse)
                    .offset(x: x, y: y)
            }

            // Center
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.yellow, .orange],
                        center: .center,
                        startRadius: 0,
                        endRadius: maxRadius * pulse
                    )
                )
                .frame(width: maxRadius * 2 * pulse, height: maxRadius * 2 * pulse)
        }
    }
}

struct Dewdrop: View {
    let index: Int
    let progress: Double
    let centerX: CGFloat
    let centerY: CGFloat
    let maxRadius: CGFloat

    var body: some View {
        let seed = Double(index * 17 + 7)
        let angle = seed.truncatingRemainder(dividingBy: 2 * .pi)
        let distance = maxRadius * (0.5 + CGFloat(index) * 0.1)
        let x = centerX + distance * cos(angle)
        let y = centerY + distance * sin(angle)
        let shimmer = 0.4 + 0.6 * sin(progress * 4 * .pi + seed)

        Circle()
            .fill(
                RadialGradient(
                    colors: [.white.opacity(shimmer), .white.opacity(shimmer * 0.3)],
                    center: UnitPoint(x: 0.3, y: 0.3),
                    startRadius: 0,
                    endRadius: 8
                )
            )
            .frame(width: 10, height: 10)
            .position(x: x, y: y)
    }
}

// MARK: - Immersive Breathing Grid View (Premium)

struct ImmersiveBreathingGridView: View {
    let progress: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height / 2
            let gridSize: CGFloat = min(geometry.size.width, geometry.size.height) * 0.8
            let dotSpacing = gridSize / 8

            ZStack {
                // Background nebula gradient
                RadialGradient(
                    colors: [
                        colors.first?.opacity(0.15) ?? Color.blue.opacity(0.15),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: gridSize * 0.7
                )
                .position(x: centerX, y: centerY)

                // Connection lines
                GridConnectionLines(
                    progress: progress,
                    gridSize: 7,
                    dotSpacing: dotSpacing,
                    centerX: centerX,
                    centerY: centerY,
                    color: colors.first ?? .blue
                )

                // Main grid of dots
                ForEach(0..<7, id: \.self) { row in
                    ForEach(0..<7, id: \.self) { col in
                        GridDot(
                            row: row,
                            col: col,
                            progress: progress,
                            dotSpacing: dotSpacing,
                            centerX: centerX,
                            centerY: centerY,
                            colors: colors
                        )
                    }
                }

                // Highlight pulse wave
                HighlightPulse(
                    progress: progress,
                    gridSize: gridSize,
                    centerX: centerX,
                    centerY: centerY,
                    color: colors.count > 1 ? colors[1] : (colors.first ?? .blue)
                )
            }
        }
    }
}

struct GridConnectionLines: View {
    let progress: Double
    let gridSize: Int
    let dotSpacing: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat
    let color: Color

    var body: some View {
        Canvas { context, size in
            let gridCenter = CGFloat(gridSize - 1) / 2
            let baseOpacity = 0.1 + 0.1 * sin(progress * 2 * .pi)

            for row in 0..<gridSize {
                for col in 0..<gridSize {
                    let x = centerX + (CGFloat(col) - gridCenter) * dotSpacing
                    let y = centerY + (CGFloat(row) - gridCenter) * dotSpacing

                    // Draw horizontal line to next dot
                    if col < gridSize - 1 {
                        let nextX = x + dotSpacing
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: y))
                        path.addLine(to: CGPoint(x: nextX, y: y))
                        context.stroke(path, with: .color(color.opacity(baseOpacity)), lineWidth: 1)
                    }

                    // Draw vertical line to next dot
                    if row < gridSize - 1 {
                        let nextY = y + dotSpacing
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: y))
                        path.addLine(to: CGPoint(x: x, y: nextY))
                        context.stroke(path, with: .color(color.opacity(baseOpacity)), lineWidth: 1)
                    }
                }
            }
        }
    }
}

struct GridDot: View {
    let row: Int
    let col: Int
    let progress: Double
    let dotSpacing: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat
    let colors: [Color]

    var body: some View {
        let gridCenter: CGFloat = 3.0
        let x = centerX + (CGFloat(col) - gridCenter) * dotSpacing
        let y = centerY + (CGFloat(row) - gridCenter) * dotSpacing

        // Calculate distance from center for ripple effect
        let distanceFromCenter = hypot(CGFloat(col) - gridCenter, CGFloat(row) - gridCenter)
        let maxDistance: CGFloat = hypot(gridCenter, gridCenter)
        let normalizedDistance = distanceFromCenter / maxDistance

        // Ripple phase - dots further from center have delayed phase
        let rippleDelay = normalizedDistance * 0.4
        let dotPhase = (progress - rippleDelay).truncatingRemainder(dividingBy: 1.0)
        let adjustedPhase = dotPhase < 0 ? dotPhase + 1 : dotPhase

        let scale = 0.6 + 0.4 * sin(adjustedPhase * 2 * .pi)
        let opacity = 0.4 + 0.6 * sin(adjustedPhase * 2 * .pi)
        let dotSize: CGFloat = 10 * scale

        // Dots closer to center are brighter
        let brightnessBoost = 1.0 - normalizedDistance * 0.5

        ZStack {
            // Glow
            Circle()
                .fill(colors.first?.opacity(0.3 * opacity * brightnessBoost) ?? Color.blue.opacity(0.3))
                .frame(width: dotSize * 2, height: dotSize * 2)
                .blur(radius: 4)

            // Dot
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            (colors.count > 1 ? colors[1] : .white).opacity(opacity * brightnessBoost),
                            (colors.first ?? .blue).opacity(opacity * brightnessBoost * 0.7)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: dotSize / 2
                    )
                )
                .frame(width: dotSize, height: dotSize)
        }
        .position(x: x, y: y)
    }
}

struct HighlightPulse: View {
    let progress: Double
    let gridSize: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat
    let color: Color

    var body: some View {
        let pulseRadius = gridSize * 0.5 * progress

        Circle()
            .stroke(color.opacity(0.3 * (1 - progress)), lineWidth: 3)
            .frame(width: pulseRadius * 2, height: pulseRadius * 2)
            .blur(radius: 2)
            .position(x: centerX, y: centerY)
    }
}

// MARK: - Immersive Silk Ribbon View (Ribbon Flow)

struct ImmersiveSilkRibbonView: View {
    let progress: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                // Back ribbon (widest, slowest, lowest opacity)
                SilkRibbon(
                    progress: progress,
                    phaseOffset: 0.0,
                    speedMultiplier: 1,
                    amplitude: height * 0.15,
                    ribbonWidth: 100,
                    yPosition: height * 0.3,
                    color: colors.first ?? .mint,
                    opacity: 0.2
                )
                .frame(width: width, height: height)

                // Middle-back ribbon
                SilkRibbon(
                    progress: progress,
                    phaseOffset: 0.2,
                    speedMultiplier: 1,
                    amplitude: height * 0.12,
                    ribbonWidth: 80,
                    yPosition: height * 0.4,
                    color: colors.first ?? .mint,
                    opacity: 0.35
                )
                .frame(width: width, height: height)

                // Middle ribbon (primary focus)
                SilkRibbon(
                    progress: progress,
                    phaseOffset: 0.4,
                    speedMultiplier: 1,
                    amplitude: height * 0.1,
                    ribbonWidth: 60,
                    yPosition: height * 0.5,
                    color: colors.count > 1 ? colors[1] : (colors.first ?? .mint),
                    opacity: 0.5
                )
                .frame(width: width, height: height)

                // Middle-front ribbon
                SilkRibbon(
                    progress: progress,
                    phaseOffset: 0.6,
                    speedMultiplier: 2,
                    amplitude: height * 0.08,
                    ribbonWidth: 45,
                    yPosition: height * 0.6,
                    color: colors.count > 1 ? colors[1] : (colors.first ?? .mint),
                    opacity: 0.65
                )
                .frame(width: width, height: height)

                // Front ribbon (thinnest, fastest, highest opacity)
                SilkRibbon(
                    progress: progress,
                    phaseOffset: 0.8,
                    speedMultiplier: 2,
                    amplitude: height * 0.06,
                    ribbonWidth: 30,
                    yPosition: height * 0.7,
                    color: colors.count > 1 ? colors[1] : (colors.first ?? .mint),
                    opacity: 0.8
                )
                .frame(width: width, height: height)

                // Sparkle particles along ribbons
                ForEach(0..<8, id: \.self) { index in
                    RibbonSparkle(
                        index: index,
                        progress: progress,
                        width: width,
                        height: height,
                        color: .white
                    )
                }
            }
        }
    }
}

struct SilkRibbon: View {
    let progress: Double
    let phaseOffset: Double
    let speedMultiplier: Int
    let amplitude: CGFloat
    let ribbonWidth: CGFloat
    let yPosition: CGFloat
    let color: Color
    let opacity: Double

    var body: some View {
        SilkRibbonShape(
            progress: progress,
            phaseOffset: phaseOffset,
            speedMultiplier: speedMultiplier,
            amplitude: amplitude,
            yPosition: yPosition
        )
        .fill(
            LinearGradient(
                colors: [
                    color.opacity(opacity * 0.5),
                    color.opacity(opacity),
                    color.opacity(opacity * 0.5)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .blur(radius: 2)
    }
}

struct SilkRibbonShape: Shape {
    var progress: Double
    let phaseOffset: Double
    let speedMultiplier: Int
    let amplitude: CGFloat
    let yPosition: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let phase = (progress + phaseOffset) * Double(speedMultiplier) * 2 * .pi

        // Top edge of ribbon
        path.move(to: CGPoint(x: 0, y: yPosition + amplitude * sin(phase)))

        for x in stride(from: 0, through: rect.width, by: 4) {
            let relativeX = x / rect.width
            let y = yPosition + amplitude * sin(relativeX * 4 * .pi + phase)
            path.addLine(to: CGPoint(x: x, y: y))
        }

        // Bottom edge of ribbon (offset by ribbon width)
        for x in stride(from: rect.width, through: 0, by: -4) {
            let relativeX = x / rect.width
            let y = yPosition + amplitude * sin(relativeX * 4 * .pi + phase) + 30
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.closeSubpath()
        return path
    }
}

struct RibbonSparkle: View {
    let index: Int
    let progress: Double
    let width: CGFloat
    let height: CGFloat
    let color: Color

    var body: some View {
        let seed = Double(index * 13 + 7)
        let xProgress = (progress * 2 + seed / 10).truncatingRemainder(dividingBy: 1.0)
        let x = width * xProgress
        let baseY = height * (0.3 + CGFloat(index % 5) * 0.1)
        let waveY = height * 0.1 * sin(xProgress * 4 * .pi + seed)
        let y = baseY + waveY
        let sparkleOpacity = 0.3 + 0.7 * sin(progress * 8 * .pi + seed)

        Circle()
            .fill(color.opacity(sparkleOpacity))
            .frame(width: 4, height: 4)
            .blur(radius: 1)
            .position(x: x, y: y)
    }
}
