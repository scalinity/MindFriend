//
//  VisualAnimationService.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-20.
//  SwiftUI Canvas rendering engine for visual animations
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class VisualAnimationService: ObservableObject {
    // MARK: - Published Properties

    @Published var isPlaying: Bool = false
    @Published var currentFrame: AnimationFrame = .initial
    @Published var error: SensoryError?

    // MARK: - Private Properties

    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var currentAnimation: VisualAnimation?
    private var currentSpeed: SpeedPreset = .medium

    // MARK: - Animation Frame Data

    struct AnimationFrame {
        var progress: Double = 0.0  // 0.0 - 1.0 breathing cycle
        var timestamp: CFTimeInterval = 0.0
        var isInhale: Bool = true
        var scale: CGFloat = 1.0
        var rotation: Angle = .zero
        var offset: CGSize = .zero
        var opacity: Double = 1.0

        static let initial = AnimationFrame()
    }

    // MARK: - Public Methods

    /// Load animation from library
    func loadAnimation(id: String) async throws -> VisualAnimation {
        guard let animation = VisualAnimation.library.first(where: { $0.id == id }) else {
            throw SensoryError.animationNotFound
        }
        return animation
    }

    /// Start animation playback
    func startAnimation(id: String, speed: SpeedPreset) async throws {
        // Load animation config
        let animation = try await loadAnimation(id: id)

        // Stop any current animation
        await stopAnimation()

        currentAnimation = animation
        currentSpeed = speed
        startTime = CACurrentMediaTime()

        // Start frame loop
        startDisplayLink()
        isPlaying = true
    }

    /// Stop animation playback
    func stopAnimation() async {
        // Cancel frame timer
        displayLink?.invalidate()
        displayLink = nil

        currentAnimation = nil
        currentFrame = .initial
        isPlaying = false
    }

    /// Change animation speed during playback
    func changeSpeed(_ speed: SpeedPreset) {
        guard isPlaying else { return }
        currentSpeed = speed
    }

    // MARK: - Private Methods

    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(renderFrame))
        displayLink?.preferredFramesPerSecond = 60  // Target 60fps
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func renderFrame() {
        guard let animation = currentAnimation else { return }

        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - startTime

        // Calculate breathing cycle progress based on speed
        let breathsPerMinute = currentSpeed.breathsPerMinute
        let cycleDuration = 60.0 / breathsPerMinute  // Seconds per breath
        let cycleProgress = (elapsed.truncatingRemainder(dividingBy: cycleDuration)) / cycleDuration

        // Determine inhale/exhale phase (inhale = 0.0-0.4, hold = 0.4-0.5, exhale = 0.5-1.0)
        let isInhale = cycleProgress < 0.4
        let isHold = cycleProgress >= 0.4 && cycleProgress < 0.5

        // Render frame for animation type
        var frame = AnimationFrame()
        frame.progress = cycleProgress
        frame.timestamp = currentTime
        frame.isInhale = isInhale

        switch animation.type {
        case .expandingCircle:
            renderExpandingCircle(&frame, progress: cycleProgress, isInhale: isInhale, isHold: isHold)

        case .pulsingSquare:
            renderPulsingSquare(&frame, progress: cycleProgress, isInhale: isInhale)

        case .wave:
            renderWave(&frame, elapsed: elapsed)

        case .bouncingDot:
            renderBouncingDot(&frame, elapsed: elapsed)

        case .spiral:
            renderSpiral(&frame, elapsed: elapsed)

        case .flowerBloom:
            renderFlowerBloom(&frame, progress: cycleProgress, isInhale: isInhale)

        case .dotGrid:
            renderDotGrid(&frame, progress: cycleProgress, isInhale: isInhale)

        case .ribbonFlow:
            renderRibbonFlow(&frame, elapsed: elapsed)
        }

        currentFrame = frame
    }

    // MARK: - Animation Rendering

    private func renderExpandingCircle(_ frame: inout AnimationFrame, progress: Double, isInhale: Bool, isHold: Bool) {
        // Circle expands on inhale (0.0-0.4), holds (0.4-0.5), contracts on exhale (0.5-1.0)
        let scale: CGFloat

        if isHold {
            scale = 1.5  // Hold at max size
        } else if isInhale {
            // Smooth ease-in expansion from 0.5 to 1.5
            let inhaleProgress = progress / 0.4
            scale = 0.5 + (1.0 * easeInOut(inhaleProgress))
        } else {
            // Smooth ease-out contraction from 1.5 to 0.5
            let exhaleProgress = (progress - 0.5) / 0.5
            scale = 1.5 - (1.0 * easeInOut(exhaleProgress))
        }

        frame.scale = scale
        frame.opacity = 0.8 + (0.2 * sin(progress * .pi * 2))
    }

    private func renderPulsingSquare(_ frame: inout AnimationFrame, progress: Double, isInhale: Bool) {
        // Square pulses gently - smaller scale range
        let scale: CGFloat = isInhale
            ? 0.9 + (0.2 * easeInOut(progress / 0.4))
            : 1.1 - (0.2 * easeInOut((progress - 0.5) / 0.5))

        frame.scale = scale
        frame.rotation = .degrees(sin(progress * .pi * 2) * 5)  // Subtle rotation
    }

    private func renderWave(_ frame: inout AnimationFrame, elapsed: TimeInterval) {
        // Flowing wave motion
        let waveSpeed = currentSpeed.speedMultiplier
        let waveProgress = elapsed * waveSpeed

        frame.offset = CGSize(
            width: sin(waveProgress) * 50,
            height: cos(waveProgress * 0.5) * 30
        )
        frame.scale = 1.0 + (0.3 * sin(waveProgress * 2))
        frame.opacity = 0.7 + (0.3 * cos(waveProgress))
    }

    private func renderBouncingDot(_ frame: inout AnimationFrame, elapsed: TimeInterval) {
        // Dot bounces rhythmically
        let bounceSpeed = currentSpeed.breathsPerMinute / 60.0  // Bounces per second
        let bounceProgress = (elapsed * bounceSpeed).truncatingRemainder(dividingBy: 1.0)

        // Parabolic bounce (peaks at 0.5)
        let bounceHeight = -4 * pow(bounceProgress - 0.5, 2) + 1
        frame.offset = CGSize(width: 0, height: -bounceHeight * 80)
        frame.scale = 1.0 + (bounceHeight * 0.2)  // Squash and stretch
    }

    private func renderSpiral(_ frame: inout AnimationFrame, elapsed: TimeInterval) {
        // Hypnotic spiral motion (premium)
        let spiralSpeed = currentSpeed.speedMultiplier * 0.5  // Slower for hypnotic effect
        let angle = elapsed * spiralSpeed * .pi
        let radius = 20.0 + (30.0 * sin(elapsed * spiralSpeed))

        frame.offset = CGSize(
            width: cos(angle) * radius,
            height: sin(angle) * radius
        )
        frame.rotation = .radians(angle)
        frame.scale = 1.0 + (0.5 * sin(elapsed * spiralSpeed * 2))
    }

    private func renderFlowerBloom(_ frame: inout AnimationFrame, progress: Double, isInhale: Bool) {
        // Petals bloom and close gently (premium)
        let bloomProgress = isInhale ? progress / 0.4 : 1.0 - ((progress - 0.5) / 0.5)

        frame.scale = 0.3 + (0.7 * easeInOut(bloomProgress))
        frame.rotation = .degrees(bloomProgress * 45)  // Petals rotate as they bloom
        frame.opacity = 0.5 + (0.5 * bloomProgress)
    }

    private func renderDotGrid(_ frame: inout AnimationFrame, progress: Double, isInhale: Bool) {
        // Grid of dots expands in sync (premium)
        let gridScale = isInhale
            ? 0.8 + (0.4 * easeInOut(progress / 0.4))
            : 1.2 - (0.4 * easeInOut((progress - 0.5) / 0.5))

        frame.scale = gridScale
        frame.opacity = 0.6 + (0.4 * sin(progress * .pi * 2))
    }

    private func renderRibbonFlow(_ frame: inout AnimationFrame, elapsed: TimeInterval) {
        // Flowing ribbons move gracefully
        let flowSpeed = currentSpeed.speedMultiplier * 0.7
        let flowProgress = elapsed * flowSpeed

        frame.offset = CGSize(
            width: sin(flowProgress) * 60,
            height: cos(flowProgress * 1.3) * 40
        )
        frame.rotation = .degrees(sin(flowProgress * 0.5) * 20)
        frame.scale = 1.0 + (0.3 * sin(flowProgress * 1.5))
        frame.opacity = 0.7 + (0.3 * cos(flowProgress * 0.8))
    }

    // MARK: - Easing Functions

    private func easeInOut(_ t: Double) -> Double {
        // Smooth ease-in-out curve
        return t < 0.5
            ? 2 * t * t
            : 1 - pow(-2 * t + 2, 2) / 2
    }
}
