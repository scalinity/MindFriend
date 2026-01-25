// MARK: - Dynamic Background View
// Gradient backgrounds with optional particle effects for ambient wellness

import SwiftUI

/// A view that renders ambient gradient backgrounds with optional dynamic effects.
/// Supports static gradients, time-shifting gradients, and particle animations.
struct DynamicBackgroundView: View {
    // MARK: - Properties

    let theme: AmbientTheme
    let backgroundType: BackgroundType

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hueRotation: Angle = .zero
    @State private var gradientPhase: CGFloat = 0
    @State private var dynamicShiftTask: Task<Void, Never>?

    /// Timer interval for dynamic gradient updates (5 minutes)
    private let dynamicUpdateInterval: TimeInterval = 300

    // MARK: - Body

    var body: some View {
        ZStack {
            // Base gradient layer
            gradientLayer

            // Particle overlay (if animated and reduce motion is off)
            if shouldShowParticles {
                ParticleView(
                    theme: theme,
                    particleCount: theme.particleCount
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ambient background with \(theme.displayName) theme")
        .onAppear {
            if backgroundType == .dynamic && !reduceMotion {
                startDynamicShift()
            }
        }
        .onDisappear {
            // Cancel task to prevent memory leak
            dynamicShiftTask?.cancel()
            dynamicShiftTask = nil
        }
        .onChange(of: backgroundType) { _, newType in
            // Cancel dynamic task when switching away from dynamic mode
            if newType != .dynamic {
                dynamicShiftTask?.cancel()
                dynamicShiftTask = nil
                // Reset hue rotation for static mode
                if newType == .static {
                    hueRotation = .zero
                }
            } else if !reduceMotion {
                // Start dynamic shift when switching to dynamic mode
                startDynamicShift()
            }
        }
        .onChange(of: reduceMotion) { _, newValue in
            // Respect reduce motion changes
            if newValue {
                dynamicShiftTask?.cancel()
                dynamicShiftTask = nil
                hueRotation = .zero
            } else if backgroundType == .dynamic {
                startDynamicShift()
            }
        }
    }

    // MARK: - Gradient Layer

    @ViewBuilder
    private var gradientLayer: some View {
        LinearGradient.forTheme(theme)
            .hueRotation(effectiveHueRotation)
            .animation(.easeInOut(duration: 1.5), value: theme)
    }

    // MARK: - Computed Properties

    /// Whether to show particles based on background type and accessibility settings
    private var shouldShowParticles: Bool {
        backgroundType == .animated && !reduceMotion
    }

    /// The effective hue rotation based on background type
    private var effectiveHueRotation: Angle {
        switch backgroundType {
        case .static:
            return .zero
        case .dynamic:
            return reduceMotion ? .zero : hueRotation
        case .animated:
            return reduceMotion ? .zero : hueRotation
        }
    }

    // MARK: - Dynamic Gradient

    /// Start the time-based gradient shifting
    private func startDynamicShift() {
        // Cancel any existing task first
        dynamicShiftTask?.cancel()

        // Calculate initial phase based on time of day
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let minutesSinceMidnight = Double(hour * 60 + minute)

        // Map to a ±15 degree range over the day
        let dayProgress = minutesSinceMidnight / 1440.0 // 0-1 over 24 hours
        hueRotation = .degrees(sin(dayProgress * .pi * 2) * 15)

        // Set up timer for updates - store task reference to cancel on disappear
        dynamicShiftTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(dynamicUpdateInterval) * 1_000_000_000)

                guard !Task.isCancelled else { break }

                await MainActor.run {
                    updateDynamicGradient()
                }
            }
        }
    }

    /// Update gradient based on current time
    private func updateDynamicGradient() {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let minutesSinceMidnight = Double(hour * 60 + minute)

        // Smooth sinusoidal variation ±15 degrees
        let dayProgress = minutesSinceMidnight / 1440.0
        withAnimation(.easeInOut(duration: 3.0)) {
            hueRotation = .degrees(sin(dayProgress * .pi * 2) * 15)
        }
    }
}

// MARK: - Convenience Initializers

extension DynamicBackgroundView {
    /// Create a background view with just a theme (uses static background)
    init(theme: AmbientTheme) {
        self.theme = theme
        self.backgroundType = .static
    }
}

// MARK: - View Modifier

extension View {
    /// Apply an ambient background to this view
    func ambientBackground(theme: AmbientTheme, type: BackgroundType) -> some View {
        self.background(
            DynamicBackgroundView(theme: theme, backgroundType: type)
        )
    }

    /// Apply an ambient background using the theme service
    func ambientBackground(service: AmbientThemeService) -> some View {
        self.background(
            DynamicBackgroundView(
                theme: service.currentTheme,
                backgroundType: service.backgroundType
            )
        )
    }
}

// MARK: - Preview

#if DEBUG
struct DynamicBackgroundView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Static background
            DynamicBackgroundView(theme: .dawn, backgroundType: .static)
                .previewDisplayName("Dawn - Static")

            // Dynamic background
            DynamicBackgroundView(theme: .day, backgroundType: .dynamic)
                .previewDisplayName("Day - Dynamic")

            // Animated background
            DynamicBackgroundView(theme: .ocean, backgroundType: .animated)
                .previewDisplayName("Ocean - Animated")

            // Night theme
            DynamicBackgroundView(theme: .night, backgroundType: .animated)
                .previewDisplayName("Night - Animated")
        }
    }
}
#endif
