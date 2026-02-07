import Foundation

/// Detects nervous system state cascades (rapid deterioration patterns)
final class CascadeDetector {
    // MARK: - Configuration

    private let windowDuration: TimeInterval = 300 // 5 minutes
    private let minTransitionsForCascade = 3

    // MARK: - Public Interface

    /// Detect cascade from recent state history
    /// - Parameter states: Ordered state records (most recent first)
    /// - Returns: CascadeEvent if cascade detected, nil otherwise
    func detectCascade(states: [NervousSystemStateRecord]) -> CascadeEvent? {
        guard states.count >= minTransitionsForCascade else {
            return nil
        }

        // Get states within window (most recent 5 minutes)
        let now = Date()
        let windowStates = states.filter {
            now.timeIntervalSince($0.classifiedAt) <= windowDuration
        }.sorted { $0.classifiedAt < $1.classifiedAt } // Oldest first for analysis

        guard windowStates.count >= minTransitionsForCascade else {
            return nil
        }

        // Check for deterioration pattern (moving toward dorsal)
        let _ = windowStates.map { $0.state.polyvagalValue }

        // Cascade = consistent movement toward lower polyvagal values (toward dorsal)
        var transitionCount = 0
        var previousValue: Int?

        for state in windowStates {
            let currentValue = state.state.polyvagalValue

            if let prev = previousValue {
                // Only count transitions that move toward dorsal (decreasing polyvagal value)
                if currentValue < prev {
                    transitionCount += 1
                }
            }

            previousValue = currentValue
        }

        guard transitionCount >= minTransitionsForCascade - 1 else {
            return nil
        }

        // Calculate severity
        let severity = calculateSeverity(transitionCount: transitionCount)

        // Create cascade event
        return CascadeEvent(
            id: UUID(),
            userId: windowStates.first!.userId,
            startedAt: windowStates.first!.classifiedAt,
            endedAt: windowStates.last!.classifiedAt,
            stateSequence: windowStates.map { $0.state },
            severity: severity,
            transitionCount: transitionCount,
            detectedAt: now,
            createdAt: now
        )
    }

    /// Check if given states show cascade pattern (for real-time detection)
    func isCascadePattern(states: [NervousSystemState]) -> Bool {
        guard states.count >= minTransitionsForCascade else {
            return false
        }

        let values = states.map { $0.polyvagalValue }

        // Check for consistent deterioration
        for i in 0..<(values.count - 1) {
            if values[i] <= values[i + 1] {
                // Not deteriorating
                return false
            }
        }

        return true
    }

    // MARK: - Private Methods

    private func calculateSeverity(transitionCount: Int) -> CascadeSeverity {
        switch transitionCount {
        case 3:
            return .mild
        case 4...5:
            return .moderate
        default:
            return .severe
        }
    }
}
