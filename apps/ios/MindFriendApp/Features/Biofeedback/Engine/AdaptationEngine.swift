// AdaptationEngine.swift
// MindFriendApp
// Engine for calculating real-time exercise adaptations based on biometrics

import Foundation
import Combine

@MainActor
final class AdaptationEngine: ObservableObject, AdaptationEngineProtocol {
    // MARK: - Published State

    @Published private(set) var currentParameters: AdaptationParameters = .default
    @Published private(set) var adaptationsApplied: [AdaptationType] = []
    @Published private(set) var currentStressLevel: BiofeedbackStressLevel = .unknown
    @Published private(set) var currentTrend: BiofeedbackTrendDirection = .stable

    // MARK: - Constants

    private enum Constants {
        static let minimumAdaptationIntervalSeconds: TimeInterval = 15
        static let maxHeartRateBufferSize = 20
        static let minimumReadingsForTrend = 8  // Need at least 8 readings to compare 5 recent vs 3+ older
        static let recentReadingsWindow = 5
        static let trendThresholdBPM: Double = 3.0
        static let hrvMinValid: Double = 5.0
        static let hrvMaxValid: Double = 250.0
        static let estimatedTargetHRNoBaseline: Double = 70.0
        static let extensionHighThresholdBPM: Double = 15.0
        static let extensionMediumThresholdBPM: Double = 8.0
        static let extensionLongSeconds = 180
        static let extensionShortSeconds = 120
        static let minimumSessionForExtensionSeconds: TimeInterval = 180
        /// Maximum adaptations to keep in history to prevent unbounded memory growth
        static let maxAdaptationsHistorySize = 100
        /// Minimum valid average heart rate for extension check (BPM)
        static let minValidAverageHR: Double = 30.0
        /// Maximum valid average heart rate for extension check (BPM)
        static let maxValidAverageHR: Double = 220.0

        /// Estimated stress thresholds when no baseline available (adult averages, BPM)
        enum EstimatedStressThreshold {
            static let relaxedMax: Double = 65.0
            static let calmMax: Double = 75.0
            static let moderateMax: Double = 85.0
            static let elevatedMax: Double = 100.0
        }

        /// Visual intensity by stress level (0.0 = minimal animation, 1.0 = maximum animation)
        enum VisualIntensity {
            static let high: Double = 0.4
            static let elevated: Double = 0.5
            static let moderate: Double = 0.6
            static let calm: Double = 0.7
            static let relaxed: Double = 0.8
            static let unknown: Double = 0.6
        }

        /// Tolerance for breathing pattern comparison (seconds) to prevent floating-point adaptation loops
        static let breathingPatternComparisonTolerance: Double = 0.1
        /// Minimum change in visual intensity (0.0-1.0) to trigger adaptation
        static let visualIntensityChangeThreshold: Double = 0.1
    }

    // MARK: - Configuration

    private let baseline: BiofeedbackBaseline?
    private let mode: AdaptationMode
    private var lastAdaptationTime: Date?

    // MARK: - Readings Buffer

    private var recentHeartRates: [Double] = []

    // MARK: - Initialization

    init(baseline: BiofeedbackBaseline?, mode: AdaptationMode) {
        self.baseline = baseline
        self.mode = mode
    }

    // MARK: - Processing

    func processReading(_ reading: LiveBiometricData) -> AdaptationResult {
        // Input validation - reject invalid biometric data
        guard reading.isValid else {
            return AdaptationResult(adapted: false, parameters: currentParameters)
        }

        // Additional HRV validation if present
        if let hrv = reading.hrvRMSSD {
            // HRV RMSSD should be between 5-250ms for physiologically plausible values
            guard hrv >= Constants.hrvMinValid, hrv <= Constants.hrvMaxValid else {
                return AdaptationResult(adapted: false, parameters: currentParameters)
            }
        }

        // Update stress level
        if let baseline = baseline {
            currentStressLevel = baseline.stressLevel(forHeartRate: reading.heartRate)
        } else {
            currentStressLevel = estimateStressLevel(heartRate: reading.heartRate)
        }

        // Update trend
        updateTrend(with: reading.heartRate)

        // Return early if adaptations are off
        guard mode != .off else {
            return AdaptationResult(adapted: false, parameters: currentParameters)
        }

        // Check if enough time has passed since last adaptation
        if let lastTime = lastAdaptationTime,
           Date().timeIntervalSince(lastTime) < Constants.minimumAdaptationIntervalSeconds {
            return AdaptationResult(adapted: false, parameters: currentParameters)
        }

        var adaptations: [AdaptationChange] = []

        // Breathing pace adaptation
        if shouldAdaptBreathingPace() {
            let newPace = calculateBreathingPace(
                currentHR: reading.heartRate,
                hrv: reading.hrvRMSSD
            )
            let currentPattern = currentParameters.breathingPattern
            // Use tolerance-based comparison to prevent infinite adaptation loop from floating point differences
            let isSignificantChange = !newPace.isApproximatelyEqual(to: currentPattern, tolerance: Constants.breathingPatternComparisonTolerance)
            if isSignificantChange {
                adaptations.append(.breathingPace(old: currentPattern, new: newPace))
                currentParameters.breathingInhaleSeconds = newPace.inhale
                currentParameters.breathingHoldSeconds = newPace.hold
                currentParameters.breathingExhaleSeconds = newPace.exhale
                currentParameters.breathingPauseSeconds = newPace.pause
            }
        }

        // Visual intensity adaptation
        if shouldAdaptVisuals() {
            let newIntensity = calculateVisualIntensity()
            if abs(newIntensity - currentParameters.visualIntensity) > Constants.visualIntensityChangeThreshold {
                adaptations.append(.visualIntensity(old: currentParameters.visualIntensity, new: newIntensity))
                currentParameters.visualIntensity = newIntensity
            }
        }

        // Guidance verbosity adaptation
        if shouldAdaptGuidance(hrv: reading.hrvRMSSD) {
            let newVerbosity = calculateGuidanceVerbosity()
            if newVerbosity != currentParameters.guidanceVerbosity {
                adaptations.append(.guidanceVerbosity(old: currentParameters.guidanceVerbosity, new: newVerbosity))
                currentParameters.guidanceVerbosity = newVerbosity
            }
        }

        if !adaptations.isEmpty {
            lastAdaptationTime = Date()
            adaptationsApplied.append(contentsOf: adaptations.map { $0.type })
            // Bound adaptations history to prevent unbounded memory growth
            if adaptationsApplied.count > Constants.maxAdaptationsHistorySize {
                adaptationsApplied.removeFirst(adaptationsApplied.count - Constants.maxAdaptationsHistorySize)
            }
        }

        return AdaptationResult(
            adapted: !adaptations.isEmpty,
            parameters: currentParameters,
            changes: adaptations
        )
    }

    // MARK: - Stress Level Estimation (No Baseline)

    private func estimateStressLevel(heartRate: Double) -> BiofeedbackStressLevel {
        // Age-based estimation (assuming adult)
        if heartRate < Constants.EstimatedStressThreshold.relaxedMax { return .relaxed }
        if heartRate < Constants.EstimatedStressThreshold.calmMax { return .calm }
        if heartRate < Constants.EstimatedStressThreshold.moderateMax { return .moderate }
        if heartRate < Constants.EstimatedStressThreshold.elevatedMax { return .elevated }
        return .high
    }

    // MARK: - Trend Calculation

    private func updateTrend(with heartRate: Double) {
        recentHeartRates.append(heartRate)
        if recentHeartRates.count > Constants.maxHeartRateBufferSize {
            recentHeartRates.removeFirst()
        }

        // Need at least minimumReadingsForTrend to have meaningful comparison groups
        // With 8 readings: 5 recent vs 3 older (prevents empty prefix edge case)
        guard recentHeartRates.count >= Constants.minimumReadingsForTrend else {
            currentTrend = .stable
            return
        }

        let olderCount = recentHeartRates.count - Constants.recentReadingsWindow
        guard olderCount >= 1 else {
            currentTrend = .stable
            return
        }

        let recentReadings = Array(recentHeartRates.suffix(Constants.recentReadingsWindow))
        let olderReadings = Array(recentHeartRates.prefix(olderCount))

        let recentAvg = recentReadings.reduce(0, +) / Double(recentReadings.count)
        let olderAvg = olderReadings.reduce(0, +) / Double(olderReadings.count)

        let diff = recentAvg - olderAvg
        if diff < -Constants.trendThresholdBPM {
            currentTrend = .improving
        } else if diff > Constants.trendThresholdBPM {
            currentTrend = .worsening
        } else {
            currentTrend = .stable
        }
    }

    // MARK: - Breathing Pace Calculation

    private func calculateBreathingPace(currentHR: Double, hrv: Double?) -> BiofeedbackBreathingPattern {
        switch currentStressLevel {
        case .high:
            // Start with shorter cycles, emphasis on exhale for calming
            return .stressed
        case .elevated:
            return .elevated
        case .moderate:
            return .moderate
        case .calm:
            return .calm
        case .relaxed:
            return .relaxed
        case .unknown:
            return .moderate
        }
    }

    // MARK: - Visual Intensity Calculation

    private func calculateVisualIntensity() -> Double {
        switch currentStressLevel {
        case .high: return Constants.VisualIntensity.high
        case .elevated: return Constants.VisualIntensity.elevated
        case .moderate: return Constants.VisualIntensity.moderate
        case .calm: return Constants.VisualIntensity.calm
        case .relaxed: return Constants.VisualIntensity.relaxed
        case .unknown: return Constants.VisualIntensity.unknown
        }
    }

    // MARK: - Guidance Verbosity

    private func calculateGuidanceVerbosity() -> AdaptationParameters.GuidanceVerbosity {
        switch currentStressLevel {
        case .high, .elevated: return .detailed
        case .moderate: return .moderate
        case .calm, .relaxed: return .minimal
        case .unknown: return .moderate
        }
    }

    // MARK: - Adaptation Conditions

    private func shouldAdaptBreathingPace() -> Bool {
        switch mode {
        case .aggressive: return true
        case .auto: return currentStressLevel != .calm && currentStressLevel != .unknown
        case .gentle: return currentStressLevel == .high || currentStressLevel == .elevated
        case .off: return false
        }
    }

    private func shouldAdaptVisuals() -> Bool {
        mode == .aggressive || mode == .auto
    }

    private func shouldAdaptGuidance(hrv: Double?) -> Bool {
        mode == .aggressive || (mode == .auto && (currentStressLevel == .high || currentStressLevel == .elevated))
    }

    // MARK: - Extension Recommendation

    func checkShouldExtend(averageHR: Double, elapsedTime: TimeInterval) -> ExtensionRecommendation {
        // Validate averageHR is within physiological range
        guard averageHR >= Constants.minValidAverageHR,
              averageHR <= Constants.maxValidAverageHR else {
            return .notNeeded
        }

        guard elapsedTime >= Constants.minimumSessionForExtensionSeconds else {
            return .notNeeded
        }

        guard let baseline = baseline,
              let targetHR = baseline.relaxedHRThreshold else {
            // No baseline - use estimated target
            return checkExtensionWithTarget(averageHR: averageHR, targetHR: Constants.estimatedTargetHRNoBaseline)
        }

        return checkExtensionWithTarget(averageHR: averageHR, targetHR: targetHR)
    }

    private func checkExtensionWithTarget(averageHR: Double, targetHR: Double) -> ExtensionRecommendation {
        let hrDelta = averageHR - targetHR

        if currentStressLevel == .relaxed || currentStressLevel == .calm {
            return .notNeeded
        }

        if hrDelta > Constants.extensionHighThresholdBPM {
            return .recommended(
                additionalSeconds: Constants.extensionLongSeconds,
                reason: "Your heart rate is still elevated. A few more minutes may help you reach a calmer state."
            )
        } else if hrDelta > Constants.extensionMediumThresholdBPM {
            return .optional(
                additionalSeconds: Constants.extensionShortSeconds,
                reason: "You're making progress! A bit more time could deepen your relaxation."
            )
        }

        return .notNeeded
    }

    // MARK: - Reset

    func reset() {
        currentParameters = .default
        adaptationsApplied.removeAll()
        recentHeartRates.removeAll()
        currentStressLevel = .unknown
        currentTrend = .stable
        lastAdaptationTime = nil
    }
}

// MARK: - Adaptation Result

struct AdaptationResult {
    let adapted: Bool
    let parameters: AdaptationParameters
    var changes: [AdaptationChange] = []
}

// MARK: - Adaptation Change

enum AdaptationChange {
    case breathingPace(old: BiofeedbackBreathingPattern, new: BiofeedbackBreathingPattern)
    case visualIntensity(old: Double, new: Double)
    case guidanceVerbosity(old: AdaptationParameters.GuidanceVerbosity, new: AdaptationParameters.GuidanceVerbosity)
    case audioTempo(old: Double, new: Double)

    var type: AdaptationType {
        switch self {
        case .breathingPace: return .breathingPace
        case .visualIntensity: return .visualFeedback
        case .guidanceVerbosity: return .guidanceFrequency
        case .audioTempo: return .audioTempo
        }
    }

    var description: String {
        switch self {
        case .breathingPace(_, let new):
            return "Breathing pace adjusted to \(new.displayName)"
        case .visualIntensity(_, let new):
            return "Visual intensity set to \(Int(new * 100))%"
        case .guidanceVerbosity(_, let new):
            return "Guidance changed to \(new.rawValue)"
        case .audioTempo(_, let new):
            return "Audio tempo set to \(Int(new)) BPM"
        }
    }
}
