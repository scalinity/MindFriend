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
        case .inhale: return "INHALE"
        case .holdIn: return "HOLD"
        case .exhale: return "EXHALE"
        case .holdOut: return "HOLD"
        }
    }

    var color: Color {
        switch self {
        case .inhale: return .blue
        case .holdIn: return .purple
        case .exhale: return .green
        case .holdOut: return .purple
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
    let scale: CGFloat
    let phase: LibraryBreathingPhase

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [phase.color.opacity(0.3), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .scaleEffect(scale * 1.2)

            // Main circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [phase.color.opacity(0.8), phase.color.opacity(0.4)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 100
                    )
                )
                .scaleEffect(scale)

            // Inner glow
            Circle()
                .fill(phase.color.opacity(0.6))
                .scaleEffect(scale * 0.3)
                .blur(radius: 10)
        }
        .animation(.easeInOut(duration: 0.3), value: phase)
    }
}

// MARK: - Progress Dots

/// Horizontal dots showing progress through steps
struct ProgressDots: View {
    let total: Int
    let current: Int
    let activeColor: Color

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index <= current ? activeColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: current)
            }
        }
    }
}

// MARK: - Step Progress Bar

/// Horizontal progress bar for step-based exercises
struct StepProgressBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))

                // Progress fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geometry.size.width * progress))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Cycle Counter

/// Display for breathing cycle count
struct CycleCounter: View {
    let current: Int
    let total: Int

    var body: some View {
        Text("Cycle \(current) of \(total)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
            .animation(.easeInOut, value: current)
    }
}

// MARK: - Phase Label

/// Large animated phase label
struct PhaseLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.title.weight(.semibold))
            .foregroundStyle(color)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: text)
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
            .foregroundStyle(style == .small ? .secondary : .primary)
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
        HStack(spacing: 32) {
            // Reset button
            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title)
                    .foregroundStyle(canReset ? .primary : .secondary)
            }
            .disabled(!canReset)

            // Play/Pause button
            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.accentColor)
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
    let text: String
    let isActive: Bool
    let segmentType: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let type = segmentType {
                Text(type.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .textCase(.uppercase)
            }

            Text(text)
                .font(isActive ? .title3 : .body)
                .fontWeight(isActive ? .medium : .regular)
                .foregroundStyle(isActive ? .primary : .secondary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.3), value: isActive)
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
                .fill(isCompleted ? color : Color(.systemGray5))
                .frame(width: 56, height: 56)

            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isCompleted ? .white : .secondary)

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
        VStack(alignment: .leading, spacing: 12) {
            if let category = category {
                Text(category.capitalized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
            }

            Text(prompt)
                .font(.headline)
                .foregroundStyle(.primary)

            TextEditor(text: $response)
                .frame(minHeight: 120)
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Movement Step Card

/// A card showing a movement step
struct MovementStepCard: View {
    let step: MovementStep
    let isActive: Bool
    let timeRemaining: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(step.name)
                    .font(.headline)

                Spacer()

                if step.isRestPeriod == true {
                    Label("Rest", systemImage: "pause.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(step.description)
                .font(.body)
                .foregroundStyle(.secondary)

            if isActive, let time = timeRemaining {
                HStack {
                    ProgressView(value: Double(time), total: Double(step.durationSeconds))
                        .tint(step.isRestPeriod == true ? .green : .accentColor)

                    Text("\(time)s")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("\(step.durationSeconds)s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.accentColor : .clear, lineWidth: 2)
        )
    }
}

// MARK: - Immersive Background

/// Full-screen gradient background for immersive mode
struct ImmersiveBackground: View {
    let colors: [Color]

    var body: some View {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - Preview

#Preview("Breathing Circle") {
    VStack(spacing: 40) {
        BreathingCircle(scale: 0.5, phase: .inhale)
            .frame(width: 200, height: 200)

        BreathingCircle(scale: 1.0, phase: .exhale)
            .frame(width: 200, height: 200)
    }
    .padding()
    .background(Color.black)
}

#Preview("Progress Components") {
    VStack(spacing: 24) {
        ProgressDots(total: 5, current: 2, activeColor: .blue)

        StepProgressBar(progress: 0.6, color: .green)
            .padding(.horizontal)

        CycleCounter(current: 3, total: 8)

        TimerDisplay(seconds: 125, style: .large)
    }
    .padding()
}
