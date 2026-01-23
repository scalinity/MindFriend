import Foundation

/// Classifies nervous system state from polyvagal features
final class PolyvagalClassifier {
    // MARK: - Configuration

    private let minimumConfidenceThreshold = 0.4

    // Weights for multi-modal fusion (decisions.md)
    private struct Weights {
        static let voice = 0.35
        static let hrv = 0.50
        static let behavioral = 0.15
    }

    // MARK: - Public Interface

    /// Classify nervous system state from available features
    func classify(
        voice: PolyvagalVoiceFeatures?,
        hrv: PolyvagalHRVFeatures?,
        behavioral: PolyvagalBehavioralFeatures?
    ) -> NervousSystemStateResult {
        let startTime = Date()

        // Calculate state scores for each signal source
        let voiceScores = voice.map { calculateVoiceScores($0) }
        let hrvScores = hrv.map { calculateHRVScores($0) }
        let behavioralScores = behavioral.map { calculateBehavioralScores($0) }

        // Combine scores with weighted fusion
        let combinedScores = combineScores(
            voice: voiceScores,
            hrv: hrvScores,
            behavioral: behavioralScores
        )

        // Determine state from combined scores
        let (state, confidence) = determineState(from: combinedScores)

        // Calculate latency
        let latency = Date().timeIntervalSince(startTime)

        // Build contributing factors
        var contributingFactors: [String: Double] = [:]
        if let voiceScores = voiceScores {
            contributingFactors["voice"] = voiceScores[state] ?? 0
        }
        if let hrvScores = hrvScores {
            contributingFactors["hrv"] = hrvScores[state] ?? 0
        }
        if let behavioralScores = behavioralScores {
            contributingFactors["behavioral"] = behavioralScores[state] ?? 0
        }

        return NervousSystemStateResult(
            state: state,
            confidence: confidence,
            contributingFactors: contributingFactors,
            latency: latency
        )
    }

    // MARK: - Private Methods - Voice Scoring

    private func calculateVoiceScores(_ features: PolyvagalVoiceFeatures) -> [NervousSystemState: Double] {
        var scores: [NervousSystemState: Double] = [:]

        // Ventral score (safe & social)
        // High social engagement, moderate arousal, positive emotions
        let ventralScore = (
            features.socialEngagementScore * 0.5 +
            features.positiveEmotionRatio * 0.3 +
            (1.0 - abs(features.arousalLevel - 0.5) * 2) * 0.2 // Moderate arousal
        )
        scores[.ventral] = ventralScore

        // Sympathetic score (fight/flight)
        // High threat, high arousal, rapid speech
        let sympatheticScore = (
            features.threatActivationScore * 0.5 +
            features.arousalLevel * 0.3 +
            min(1.0, features.speechRate / 200.0) * 0.2 // >200 wpm = activated
        )
        scores[.sympathetic] = sympatheticScore

        // Dorsal score (shutdown)
        // High shutdown risk, low arousal, monotone
        let dorsalScore = (
            features.shutdownRiskScore * 0.5 +
            (1.0 - features.arousalLevel) * 0.3 +
            (1.0 - min(1.0, features.pitchVariability / 15.0)) * 0.2 // Low variability
        )
        scores[.dorsal] = dorsalScore

        return scores
    }

    // MARK: - Private Methods - HRV Scoring

    private func calculateHRVScores(_ features: PolyvagalHRVFeatures) -> [NervousSystemState: Double] {
        var scores: [NervousSystemState: Double] = [:]

        // Ventral score (high HRV = high vagal tone)
        let ventralScore = features.vagalToneScore
        scores[.ventral] = ventralScore

        // Sympathetic score (low HRV, high sympathetic activation)
        let sympatheticScore = features.sympatheticActivationScore
        scores[.sympathetic] = sympatheticScore

        // Dorsal score (very low HRV = shutdown)
        // RMSSD < 20ms indicates dorsal shutdown
        let dorsalScore = features.rmssd < 20 ? 1.0 : max(0, (25 - features.rmssd) / 25.0)
        scores[.dorsal] = dorsalScore

        return scores
    }

    // MARK: - Private Methods - Behavioral Scoring

    private func calculateBehavioralScores(_ features: PolyvagalBehavioralFeatures) -> [NervousSystemState: Double] {
        var scores: [NervousSystemState: Double] = [:]

        // Ventral score (active, engaged, social)
        let ventralScore = (
            features.recentActivityLevel * 0.3 +
            features.socialEngagementLevel * 0.4 +
            features.selfCareLevel * 0.3
        )
        scores[.ventral] = ventralScore

        // Sympathetic score (high activity, short sessions)
        // Rapid interactions but not sustained
        let sympatheticScore = features.recentActivityLevel > 0.7 && features.sessionDuration < 300
            ? features.recentActivityLevel
            : features.recentActivityLevel * 0.5
        scores[.sympathetic] = sympatheticScore

        // Dorsal score (withdrawal, inactivity)
        let dorsalScore = (
            (1.0 - features.recentActivityLevel) * 0.4 +
            (1.0 - features.socialEngagementLevel) * 0.3 +
            (features.timeSinceLastInteraction > 600 ? 1.0 : features.timeSinceLastInteraction / 600) * 0.3
        )
        scores[.dorsal] = dorsalScore

        return scores
    }

    // MARK: - Private Methods - Score Combination

    private func combineScores(
        voice: [NervousSystemState: Double]?,
        hrv: [NervousSystemState: Double]?,
        behavioral: [NervousSystemState: Double]?
    ) -> [NervousSystemState: Double] {
        var combinedScores: [NervousSystemState: Double] = [
            .ventral: 0,
            .sympathetic: 0,
            .dorsal: 0
        ]

        // Calculate effective weights (normalize based on available signals)
        let availableSignals = [voice != nil, hrv != nil, behavioral != nil].filter { $0 }.count
        guard availableSignals > 0 else {
            return combinedScores
        }

        var effectiveWeights = EffectiveWeights(
            voice: Weights.voice,
            hrv: Weights.hrv,
            behavioral: Weights.behavioral
        )
        if voice == nil {
            // No voice: redistribute weight to HRV and behavioral
            let redistribution = Weights.voice / 2.0
            effectiveWeights = EffectiveWeights(
                voice: 0,
                hrv: Weights.hrv + redistribution,
                behavioral: Weights.behavioral + redistribution
            )
        } else if hrv == nil {
            // No HRV: redistribute weight to voice and behavioral (decisions.md: -20% confidence)
            let redistribution = Weights.hrv / 2.0
            effectiveWeights = EffectiveWeights(
                voice: Weights.voice + redistribution,
                hrv: 0,
                behavioral: Weights.behavioral + redistribution
            )
        }

        // Combine scores
        for state in [NervousSystemState.ventral, .sympathetic, .dorsal] {
            var score = 0.0
            if let voiceScores = voice {
                score += (voiceScores[state] ?? 0) * effectiveWeights.voice
            }
            if let hrvScores = hrv {
                score += (hrvScores[state] ?? 0) * effectiveWeights.hrv
            }
            if let behavioralScores = behavioral {
                score += (behavioralScores[state] ?? 0) * effectiveWeights.behavioral
            }
            combinedScores[state] = score
        }

        return combinedScores
    }

    // MARK: - Private Methods - State Determination

    private func determineState(from scores: [NervousSystemState: Double]) -> (NervousSystemState, Double) {
        // Find highest score
        let sortedStates = scores.sorted { $0.value > $1.value }

        guard let topState = sortedStates.first else {
            return (.unknown, 0.3)
        }

        let topScore = topState.value
        let state = topState.key

        // Check if score is above minimum threshold
        guard topScore >= minimumConfidenceThreshold else {
            return (.unknown, topScore)
        }

        // Check for mixed state (multiple states close together)
        if sortedStates.count >= 2 {
            let secondScore = sortedStates[1].value
            if abs(topScore - secondScore) < 0.15 {
                // Mixed activation
                return (.mixed, (topScore + secondScore) / 2.0)
            }
        }

        // Calculate confidence (map 0.4-1.0 to 0.6-1.0)
        let confidence = 0.6 + (topScore - minimumConfidenceThreshold) * 0.4 / (1.0 - minimumConfidenceThreshold)

        return (state, min(1.0, confidence))
    }

    // MARK: - Helper Types

    private struct EffectiveWeights {
        let voice: Double
        let hrv: Double
        let behavioral: Double
    }
}
