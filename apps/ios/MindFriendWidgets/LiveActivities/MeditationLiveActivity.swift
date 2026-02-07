import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Meditation Activity Attributes

public struct MeditationActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var elapsedSeconds: Int
        public var totalSeconds: Int
        public var isPaused: Bool
        public var currentPhase: String

        public init(elapsedSeconds: Int, totalSeconds: Int, isPaused: Bool, currentPhase: String) {
            self.elapsedSeconds = elapsedSeconds
            self.totalSeconds = totalSeconds
            self.isPaused = isPaused
            self.currentPhase = currentPhase
        }

        public var progress: Double {
            guard totalSeconds > 0 else { return 0 }
            return Double(elapsedSeconds) / Double(totalSeconds)
        }

        public var timeRemaining: String {
            let remaining = max(0, totalSeconds - elapsedSeconds)
            let minutes = remaining / 60
            let seconds = remaining % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    public var sessionTitle: String
    public var sessionType: String // meditation, breathing, focus

    public init(sessionTitle: String, sessionType: String) {
        self.sessionTitle = sessionTitle
        self.sessionType = sessionType
    }
}

// MARK: - Meditation Live Activity Widget

struct MeditationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MeditationActivityAttributes.self) { context in
            // Lock Screen view
            MeditationLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        Image(systemName: activityIcon(context.attributes.sessionType))
                            .foregroundStyle(.blue)
                        Text(context.attributes.sessionTitle)
                            .font(.caption)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.timeRemaining)
                        .font(.caption)
                        .monospacedDigit()
                }

                DynamicIslandExpandedRegion(.center) {
                    ProgressView(value: context.state.progress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 20) {
                        Button(intent: PauseMeditationIntent()) {
                            Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                        }

                        Button(intent: StopMeditationIntent()) {
                            Image(systemName: "stop.fill")
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: activityIcon(context.attributes.sessionType))
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text(context.state.timeRemaining)
                    .monospacedDigit()
                    .font(.caption)
            } minimal: {
                // Breathing animation for minimal view
                BreathingCircleView(isPaused: context.state.isPaused)
            }
        }
    }

    private func activityIcon(_ type: String) -> String {
        switch type {
        case "meditation":
            return "brain.head.profile"
        case "breathing":
            return "wind"
        case "focus":
            return "circle.dotted"
        default:
            return "sparkles"
        }
    }
}

// MARK: - Lock Screen View

struct MeditationLockScreenView: View {
    let context: ActivityViewContext<MeditationActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 4)
                    .frame(width: 50, height: 50)

                Circle()
                    .trim(from: 0, to: context.state.progress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))

                Image(systemName: context.state.isPaused ? "pause.fill" : "sparkles")
                    .foregroundStyle(.blue)
                    .font(.caption)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.sessionTitle)
                    .font(.headline)

                Text(context.state.timeRemaining + " remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(intent: PauseMeditationIntent()) {
                    Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)

                Button(intent: StopMeditationIntent()) {
                    Image(systemName: "xmark")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
}

// MARK: - Breathing Circle Animation

struct BreathingCircleView: View {
    let isPaused: Bool
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(.blue)
            .scaleEffect(scale)
            .animation(
                isPaused ? nil : .easeInOut(duration: 4).repeatForever(autoreverses: true),
                value: scale
            )
            .onAppear {
                if !isPaused {
                    scale = 1.3
                }
            }
            .onChange(of: isPaused) { oldValue, newValue in
                if newValue {
                    // Paused: stop animation
                    scale = 1.0
                } else {
                    // Resumed: restart animation
                    scale = 1.3
                }
            }
    }
}

// MARK: - App Intents for Activity Controls

struct PauseMeditationIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Meditation"

    func perform() async throws -> some IntentResult {
        // Toggle pause state in activity manager
        await MeditationActivityManager.shared.togglePause()
        return .result()
    }
}

struct StopMeditationIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Meditation"

    func perform() async throws -> some IntentResult {
        await MeditationActivityManager.shared.stopActivity()
        return .result()
    }
}

// MARK: - Activity Manager

@MainActor
public final class MeditationActivityManager {
    public static let shared = MeditationActivityManager()

    private var currentActivity: Activity<MeditationActivityAttributes>?
    private var timer: Timer?

    deinit {
        timer?.invalidate()
    }

    public func startActivity(title: String, type: String, durationSeconds: Int) async {
        let attributes = MeditationActivityAttributes(
            sessionTitle: title,
            sessionType: type
        )

        let initialState = MeditationActivityAttributes.ContentState(
            elapsedSeconds: 0,
            totalSeconds: durationSeconds,
            isPaused: false,
            currentPhase: "Starting"
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )

            startTimer(total: durationSeconds)
        } catch {
            print("Failed to start meditation activity: \(error)")
        }
    }

    public func togglePause() async {
        guard let activity = currentActivity else { return }

        let newState = MeditationActivityAttributes.ContentState(
            elapsedSeconds: activity.content.state.elapsedSeconds,
            totalSeconds: activity.content.state.totalSeconds,
            isPaused: !activity.content.state.isPaused,
            currentPhase: activity.content.state.isPaused ? "Resuming" : "Paused"
        )

        await activity.update(
            ActivityContent(state: newState, staleDate: nil)
        )

        if newState.isPaused {
            timer?.invalidate()
            timer = nil
        } else {
            startTimer(total: newState.totalSeconds, elapsed: newState.elapsedSeconds)
        }
    }

    public func stopActivity() async {
        timer?.invalidate()
        timer = nil

        guard let activity = currentActivity else { return }

        await activity.end(
            ActivityContent(state: activity.content.state, staleDate: nil),
            dismissalPolicy: .immediate
        )

        currentActivity = nil
    }

    private func startTimer(total: Int, elapsed: Int = 0) {
        var currentElapsed = elapsed

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                currentElapsed += 1

                if currentElapsed >= total {
                    await self?.completeActivity()
                } else {
                    await self?.updateProgress(elapsed: currentElapsed, total: total)
                }
            }
        }
    }

    private func updateProgress(elapsed: Int, total: Int) async {
        guard let activity = currentActivity else { return }

        let newState = MeditationActivityAttributes.ContentState(
            elapsedSeconds: elapsed,
            totalSeconds: total,
            isPaused: false,
            currentPhase: getPhase(elapsed: elapsed, total: total)
        )

        await activity.update(
            ActivityContent(state: newState, staleDate: nil)
        )
    }

    private func completeActivity() async {
        timer?.invalidate()
        timer = nil

        guard let activity = currentActivity else { return }

        let finalState = MeditationActivityAttributes.ContentState(
            elapsedSeconds: activity.content.state.totalSeconds,
            totalSeconds: activity.content.state.totalSeconds,
            isPaused: false,
            currentPhase: "Complete"
        )

        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .default
        )

        currentActivity = nil
    }

    private func getPhase(elapsed: Int, total: Int) -> String {
        let progress = Double(elapsed) / Double(total)
        if progress < 0.25 { return "Settling in" }
        if progress < 0.5 { return "Deepening" }
        if progress < 0.75 { return "Present" }
        return "Emerging"
    }
}
