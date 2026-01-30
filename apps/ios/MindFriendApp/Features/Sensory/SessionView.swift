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
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: colors,
                                center: .center,
                                startRadius: 0,
                                endRadius: baseSize * frame.scale
                            )
                        )
                        .frame(width: baseSize * 2 * frame.scale, height: baseSize * 2 * frame.scale)
                        .opacity(frame.opacity)
                        .position(x: centerX, y: centerY)
                    
                case .pulsingSquare:
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: colors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: baseSize * 1.5 * frame.scale, height: baseSize * 1.5 * frame.scale)
                        .rotationEffect(frame.rotation)
                        .opacity(frame.opacity)
                        .position(x: centerX, y: centerY)
                    
                case .wave:
                    SensoryWaveShape(progress: frame.progress)
                        .fill(
                            LinearGradient(
                                colors: colors,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: geometry.size.width * 0.9, height: 120 * frame.scale)
                        .offset(frame.offset)
                        .opacity(frame.opacity)
                        .position(x: centerX, y: centerY)
                    
                case .bouncingDot:
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: colors,
                                center: .center,
                                startRadius: 0,
                                endRadius: 40 * frame.scale
                            )
                        )
                        .frame(width: 80 * frame.scale, height: 80 * frame.scale)
                        .offset(frame.offset)
                        .position(x: centerX, y: centerY)
                    
                case .spiral:
                    SpiralShape()
                        .stroke(
                            LinearGradient(
                                colors: colors,
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: baseSize * 2 * frame.scale, height: baseSize * 2 * frame.scale)
                        .rotationEffect(frame.rotation)
                        .offset(frame.offset)
                        .opacity(frame.opacity)
                        .position(x: centerX, y: centerY)
                    
                case .flowerBloom:
                    FlowerShape(petalCount: 6, bloomProgress: frame.scale)
                        .fill(
                            RadialGradient(
                                colors: colors,
                                center: .center,
                                startRadius: 0,
                                endRadius: baseSize
                            )
                        )
                        .frame(width: baseSize * 2, height: baseSize * 2)
                        .rotationEffect(frame.rotation)
                        .opacity(frame.opacity)
                        .position(x: centerX, y: centerY)
                    
                case .dotGrid:
                    DotGridView(
                        rows: 5,
                        columns: 5,
                        scale: frame.scale,
                        colors: colors
                    )
                    .frame(width: baseSize * 2, height: baseSize * 2)
                    .opacity(frame.opacity)
                    .position(x: centerX, y: centerY)
                    
                case .ribbonFlow:
                    RibbonFlowView(
                        offset: frame.offset,
                        rotation: frame.rotation,
                        scale: frame.scale,
                        colors: colors
                    )
                    .frame(width: geometry.size.width * 0.8, height: 100)
                    .opacity(frame.opacity)
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
