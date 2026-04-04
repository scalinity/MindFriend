import SwiftUI

/// 4-7-8 Breathing Pattern ViewModel with Haptic Feedback
@MainActor
final class WatchBreathingViewModel: ObservableObject {
    // MARK: - Published State

    @Published var instruction = "Ready?"
    @Published var secondsRemaining = 4
    @Published var circleSize: CGFloat = 50
    @Published var isActive = false
    @Published var isComplete = false
    @Published var currentCycle = 1
    @Published var currentPhase: BreathPhase = .ready

    // MARK: - Configuration

    let totalCycles = 4
    let inhaleDuration = 4   // 4 seconds
    let holdDuration = 7     // 7 seconds
    let exhaleDuration = 8   // 8 seconds

    private let minCircleSize: CGFloat = 50
    private let maxCircleSize: CGFloat = 110

    // MARK: - Timer

    private var timer: Timer?
    private let haptics: HapticProviding
    private let connectivity: ConnectivityProviding

    // Timer cleanup handled by stop() in onDisappear.
    // The [weak self] in the timer callback prevents retain cycles,
    // so the timer fires harmlessly if the view model is deallocated.

    // MARK: - Breath Phase

    enum BreathPhase {
        case ready
        case inhale
        case hold
        case exhale
        case complete
    }

    // MARK: - Initialization

    init(haptics: HapticProviding = HapticManager.shared,
         connectivity: ConnectivityProviding = WatchConnectivityManager.shared) {
        self.haptics = haptics
        self.connectivity = connectivity
    }

    // MARK: - Computed Properties

    var phaseColor: Color {
        switch currentPhase {
        case .ready: return .gray
        case .inhale: return .blue
        case .hold: return .purple
        case .exhale: return .teal
        case .complete: return .green
        }
    }

    var currentPhaseDuration: Double {
        switch currentPhase {
        case .inhale: return Double(inhaleDuration)
        case .hold: return Double(holdDuration)
        case .exhale: return Double(exhaleDuration)
        default: return 1.0
        }
    }

    // MARK: - Public Methods

    func startBreathing() {
        isActive = true
        isComplete = false
        currentCycle = 1
        startInhale()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isActive = false
        currentPhase = .ready
        instruction = "Ready?"
        circleSize = minCircleSize
    }

    // MARK: - Phase Management

    private func startInhale() {
        currentPhase = .inhale
        instruction = "Breathe In"
        secondsRemaining = inhaleDuration
        circleSize = maxCircleSize

        haptics.playInhaleStart()
        // Invalidate existing timer before starting new one
        timer?.invalidate()
        startTimer()
    }

    private func startHold() {
        currentPhase = .hold
        instruction = "Hold"
        secondsRemaining = holdDuration
        // Circle stays at max size during hold

        haptics.playHoldStart()
    }

    private func startExhale() {
        currentPhase = .exhale
        instruction = "Breathe Out"
        secondsRemaining = exhaleDuration
        circleSize = minCircleSize

        haptics.playExhaleStart()
    }

    private func completeCycle() {
        haptics.playExhaleComplete()

        if currentCycle >= totalCycles {
            completeSession()
        } else {
            currentCycle += 1
            startInhale()
        }
    }

    private func completeSession() {
        timer?.invalidate()
        timer = nil
        isActive = false
        isComplete = true
        currentPhase = .complete
        instruction = "Complete!"
        circleSize = maxCircleSize

        haptics.playSessionComplete()

        // Sync breathing completion to iOS app
        connectivity.sendBreathingCompletedToPhone(cycles: totalCycles)
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.current.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func tick() {
        secondsRemaining -= 1

        // Phase transitions first (prevents "0" from displaying)
        if secondsRemaining <= 0 {
            switch currentPhase {
            case .inhale:
                startHold()
            case .hold:
                startExhale()
            case .exhale:
                completeCycle()
            default:
                break
            }
            return
        }

        // Play progress haptic at certain intervals (only when secondsRemaining > 0)
        switch currentPhase {
        case .inhale:
            haptics.playInhaleProgress()
        case .hold:
            let midpoint = holdDuration / 2
            if midpoint > 0 && secondsRemaining == midpoint {
                haptics.playHoldProgress()
            }
        case .exhale:
            if secondsRemaining % 2 == 0 {
                haptics.playClick()
            }
        default:
            break
        }
    }
}
