import SwiftUI
import UIKit

// MARK: - Breathing Phase

/// Phase of a breathing exercise for library players
enum LibraryBreathingPhase: String, CaseIterable, Equatable {
    case inhale
    case holdIn
    case exhale
    case holdOut

    var displayText: String {
        switch self {
        case .inhale: return "Inhale"
        case .holdIn: return "Hold"
        case .exhale: return "Exhale"
        case .holdOut: return "Hold"
        }
    }

    var color: Color {
        switch self {
        case .inhale: return SupportTheme.accent
        case .holdIn: return SupportTheme.accent
        case .exhale: return SupportTheme.accent
        case .holdOut: return SupportTheme.accent
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .inhale: return "Breathe in"
        case .holdIn: return "Hold your breath"
        case .exhale: return "Breathe out"
        case .holdOut: return "Hold"
        }
    }
}

// MARK: - Breathing Circle

/// Animated breathing circle component
struct BreathingCircle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let scale: CGFloat
    let phase: LibraryBreathingPhase

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    SupportTheme.surface
                )
                .scaleEffect(reduceMotion ? 1 : (scale * 1.2))

            // Main circle
            Circle()
                .fill(
                    SupportTheme.surface
                )
                .scaleEffect(reduceMotion ? 1 : (scale))

            // Inner glow
            Circle()
                .fill(phase.color.opacity(0.6))
                .scaleEffect(reduceMotion ? 1 : (scale * 0.3))
                .blur(radius: 10)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: phase)
    }
}

// MARK: - Progress Dots

/// Horizontal dots showing progress through steps
struct ProgressDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let total: Int
    let current: Int
    let activeColor: Color

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xs) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index <= current ? activeColor : SupportTheme.textSecondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: current)
            }
        }
    }
}

// MARK: - Step Progress Bar

/// Horizontal progress bar for step-based exercises
struct StepProgressBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                    .fill(SupportTheme.separator)

                // Progress fill
                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                    .fill(SupportTheme.accent)
                    .frame(width: max(0, geometry.size.width * progress))
                    .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: progress)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Cycle Counter

/// Display for breathing cycle count
struct CycleCounter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let current: Int
    let total: Int

    var body: some View {
        Text("Cycle \(current) of \(total)")
            .font(.subheadline)
            .foregroundStyle(SupportTheme.textSecondary)
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(reduceMotion ? nil : .easeInOut, value: current)
    }
}

// MARK: - Phase Label

/// Large animated phase label
struct PhaseLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.title.weight(.semibold))
            .foregroundStyle(color)
            .contentTransition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: text)
    }
}

// MARK: - Timer Display

/// Formatted timer display
struct TimerDisplay: View {
    let seconds: Int
    let style: TimerStyle

    enum TimerStyle {
        case large
        case medium
        case small
    }

    var body: some View {
        Text(formattedTime)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(style == .small ? .secondary : SupportTheme.textPrimary)
            .contentTransition(.numericText())
    }

    private var formattedTime: String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private var font: Font {
        switch style {
        case .large: return .system(size: 48, weight: .light, design: .rounded)
        case .medium: return .system(size: 32, weight: .regular, design: .rounded)
        case .small: return .system(size: 20, weight: .regular, design: .rounded)
        }
    }
}

// MARK: - Player Controls

/// Standard play/pause/reset controls
struct PlayerControls: View {
    let isPlaying: Bool
    let canReset: Bool
    let onPlayPause: () -> Void
    let onReset: () -> Void
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xl) {
            // Reset button
            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title)
                    .foregroundStyle(canReset ? .primary : SupportTheme.textSecondary)
            }
            .disabled(!canReset)

            // Play/Pause button
            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(.largeTitle))
                    .foregroundStyle(SupportTheme.accent)
            }

            // Complete button
            Button(action: onComplete) {
                Image(systemName: "checkmark.circle")
                    .font(.title)
            }
        }
    }
}

// MARK: - Segment View

/// A single meditation/grounding segment
struct SegmentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    let isActive: Bool
    let segmentType: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            if let type = segmentType {
                Text(type.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isActive ? SupportTheme.accent : SupportTheme.textSecondary)
                    .textCase(.uppercase)
            }

            Text(text)
                .font(isActive ? .title3 : .body)
                .fontWeight(isActive ? .medium : .regular)
                .foregroundStyle(isActive ? .primary : SupportTheme.textSecondary)
                .multilineTextAlignment(.leading)
        }
        .padding(SupportTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                .fill(isActive ? SupportTheme.accent.opacity(0.1) : Color.clear)
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isActive)
    }
}

// MARK: - Sense Icon

/// Icon for a grounding sense
struct SenseIcon: View {
    let sense: String
    let isCompleted: Bool
    let color: Color

    var icon: String {
        switch sense.lowercased() {
        case "sight": return "eye.fill"
        case "touch": return "hand.raised.fill"
        case "hearing": return "ear.fill"
        case "smell": return "nose.fill"
        case "taste": return "mouth.fill"
        default: return "sparkles"
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(isCompleted ? color : SupportTheme.separator)
                .frame(width: 56, height: 56)

            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isCompleted ? SupportTheme.onAccent : SupportTheme.textSecondary)

            if isCompleted {
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 3)
                    .frame(width: 64, height: 64)
            }
        }
    }
}

// MARK: - Journal Prompt Card

/// A card for journaling prompts with text input
struct JournalPromptCard: View {
    let prompt: String
    let category: String?
    @Binding var response: String

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            if let category = category {
                Text(category.capitalized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(SupportTheme.accent)
                    .padding(.horizontal, SupportTheme.Spacing.xs)
                    .padding(.vertical, SupportTheme.Spacing.xxs)
                    .background(SupportTheme.surface)
                    .clipShape(Capsule())
            }

            Text(prompt)
                .font(.headline)
                .foregroundStyle(SupportTheme.textPrimary)

            TextEditor(text: $response)
                .frame(minHeight: 120)
                .padding(SupportTheme.Spacing.xs)
                .background(SupportTheme.separator)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
        }
        .supportCard()
    }
}

// MARK: - Movement Step Card

/// A card showing a movement step
struct MovementStepCard: View {
    let step: MovementStep
    let isActive: Bool
    let timeRemaining: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Text(step.name)
                    .font(.headline)

                Spacer()

                if step.isRestPeriod == true {
                    Label("Rest", systemImage: "pause.circle")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            Text(step.description)
                .font(.body)
                .foregroundStyle(SupportTheme.textSecondary)

            if isActive, let time = timeRemaining {
                HStack {
                    ProgressView(value: Double(time), total: Double(step.durationSeconds))
                        .tint(step.isRestPeriod == true ? .green : SupportTheme.accent)

                    Text("\(time)s")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            } else {
                Text("\(step.durationSeconds)s")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .padding(SupportTheme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                .fill(isActive ? SupportTheme.accent.opacity(0.1) : SupportTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                .stroke(isActive ? SupportTheme.accent : .clear, lineWidth: 2)
        )
    }
}

// MARK: - Immersive Background

/// Full-screen gradient background for immersive mode
struct ImmersiveBackground: View {
    let colors: [Color]

    var body: some View {
        SupportTheme.canvas
        .ignoresSafeArea()
    }
}

// MARK: - Preview

#Preview("Breathing Circle") {
    VStack(spacing: SupportTheme.Spacing.xl) {
        BreathingCircle(scale: 0.5, phase: .inhale)
            .frame(width: 200, height: 200)

        BreathingCircle(scale: 1.0, phase: .exhale)
            .frame(width: 200, height: 200)
    }
    .padding(SupportTheme.Spacing.m)
    .background(SupportTheme.canvas)
}

#Preview("Progress Components") {
    VStack(spacing: SupportTheme.Spacing.l) {
        ProgressDots(total: 5, current: 2, activeColor: SupportTheme.accent)

        StepProgressBar(progress: 0.6, color: SupportTheme.accent)
            .padding(.horizontal, SupportTheme.Spacing.m)

        CycleCounter(current: 3, total: 8)

        TimerDisplay(seconds: 125, style: .large)
    }
    .padding(SupportTheme.Spacing.m)
}
