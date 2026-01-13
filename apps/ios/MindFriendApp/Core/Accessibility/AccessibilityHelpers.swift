import SwiftUI

// MARK: - Dynamic Type Support

/// Scaled metric for consistent sizing with Dynamic Type
extension View {
    /// Apply scaled font that respects Dynamic Type settings
    func scaledFont(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        self.font(.system(style, weight: weight))
    }
}

// MARK: - Reduced Motion

/// Environment value for checking reduced motion preference
struct ReducedMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var prefersReducedMotion: Bool {
        get { self[ReducedMotionKey.self] }
        set { self[ReducedMotionKey.self] = newValue }
    }
}

extension View {
    /// Apply animation only if reduced motion is not preferred
    func accessibleAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(AccessibleAnimationModifier(animation: animation, value: value))
    }
}

struct AccessibleAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.animation(animation, value: value)
        }
    }
}

// MARK: - Accessibility Announcements

extension View {
    /// Post an accessibility announcement
    func accessibilityAnnounce(_ message: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }
}

// MARK: - Focus State Management

/// Focus state wrapper for accessibility
@available(iOS 17.0, *)
struct AccessibleFocusModifier: ViewModifier {
    @AccessibilityFocusState var isFocused: Bool
    let shouldFocus: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityFocused($isFocused)
            .onChange(of: shouldFocus) { _, newValue in
                isFocused = newValue
            }
    }
}

// MARK: - Accessibility Traits

extension View {
    /// Mark view as a header for screen readers
    func accessibilityHeader() -> some View {
        self.accessibilityAddTraits(.isHeader)
    }

    /// Mark view as a button for screen readers
    func accessibilityButton() -> some View {
        self.accessibilityAddTraits(.isButton)
    }

    /// Mark view as an image for screen readers
    func accessibilityImage() -> some View {
        self.accessibilityAddTraits(.isImage)
    }

    /// Mark view as a link for screen readers
    func accessibilityLink() -> some View {
        self.accessibilityAddTraits(.isLink)
    }

    /// Mark view as selected
    func accessibilitySelected(_ isSelected: Bool) -> some View {
        self.accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Custom Accessibility Actions

extension View {
    /// Add a custom accessibility action
    func accessibilityCustomAction(
        _ name: String,
        action: @escaping () -> Bool
    ) -> some View {
        self.accessibilityAction(named: name) {
            _ = action()
        }
    }

    /// Add increment/decrement actions for adjustable elements
    func accessibilityAdjustable(
        onIncrement: @escaping () -> Void,
        onDecrement: @escaping () -> Void
    ) -> some View {
        self
            .accessibilityAddTraits(.isButton)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    onIncrement()
                case .decrement:
                    onDecrement()
                @unknown default:
                    break
                }
            }
    }
}

// MARK: - Accessibility Value Formatting

struct AccessibilityValueFormatter {
    /// Format a mood score for accessibility
    static func formatMoodScore(_ score: Int) -> String {
        switch score {
        case 1...3:
            return "\(score) out of 10, feeling low"
        case 4...6:
            return "\(score) out of 10, feeling moderate"
        case 7...10:
            return "\(score) out of 10, feeling good"
        default:
            return "\(score) out of 10"
        }
    }

    /// Format a streak count for accessibility
    static func formatStreak(_ days: Int) -> String {
        if days == 0 {
            return "No current streak"
        } else if days == 1 {
            return "1 day streak"
        } else {
            return "\(days) day streak"
        }
    }

    /// Format a percentage for accessibility
    static func formatPercentage(_ value: Double) -> String {
        let formatted = Int(value * 100)
        return "\(formatted) percent"
    }

    /// Format time duration for accessibility
    static func formatDuration(minutes: Int) -> String {
        if minutes < 60 {
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return hours == 1 ? "1 hour" : "\(hours) hours"
            } else {
                return "\(hours) hour\(hours > 1 ? "s" : "") and \(remainingMinutes) minute\(remainingMinutes > 1 ? "s" : "")"
            }
        }
    }
}

// MARK: - High Contrast Support

struct HighContrastModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) var contrast

    let normalColor: Color
    let highContrastColor: Color

    func body(content: Content) -> some View {
        content
            .foregroundStyle(contrast == .increased ? highContrastColor : normalColor)
    }
}

extension View {
    func highContrastForeground(normal: Color, highContrast: Color) -> some View {
        modifier(HighContrastModifier(normalColor: normal, highContrastColor: highContrast))
    }
}

// MARK: - Accessibility Container

/// Container that groups related accessibility elements
struct AccessibilityContainer<Content: View>: View {
    let label: String
    let hint: String?
    let content: () -> Content

    init(
        label: String,
        hint: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.hint = hint
        self.content = content
    }

    var body: some View {
        content()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
    }
}

// MARK: - Loading State Accessibility

struct AccessibleLoadingView: View {
    let message: String

    var body: some View {
        ProgressView()
            .accessibilityLabel(message)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Error State Accessibility

struct AccessibleErrorView: View {
    let error: Error
    let retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text("Error")
                .font(.headline)
                .accessibilityHeader()

            Text(error.localizedDescription)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let retryAction = retryAction {
                Button("Retry", action: retryAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error: \(error.localizedDescription)")
    }
}

// MARK: - Haptic Feedback

enum HapticType {
    case success
    case warning
    case error
    case light
    case medium
    case heavy
    case selection
}

struct HapticManager {
    static func trigger(_ type: HapticType) {
        switch type {
        case .success:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        case .warning:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        case .error:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        case .light:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        case .medium:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        case .heavy:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
        case .selection:
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()
        }
    }
}

extension View {
    /// Add haptic feedback on tap
    func hapticOnTap(_ type: HapticType) -> some View {
        self.onTapGesture {
            HapticManager.trigger(type)
        }
    }
}
