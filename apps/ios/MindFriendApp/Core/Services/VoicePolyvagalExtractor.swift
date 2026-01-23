import Foundation

/// Extracts polyvagal features from voice emotion predictions
final class VoicePolyvagalExtractor {
    // MARK: - Emotion to Polyvagal State Mapping
    // Based on decisions.md and clinical Polyvagal Theory literature

    private struct EmotionWeights {
        // Ventral Vagal (safe & social)
        static let ventral: [EmotionLabel: Double] = [
            .calm: 0.9,
            .happy: 0.8,
            .surprised: 0.2,
            .neutral: 0.3,
            .angry: 0.0,
            .fearful: 0.0,
            .sad: 0.0,
            .disgust: 0.0
        ]

        // Sympathetic (fight/flight)
        static let sympathetic: [EmotionLabel: Double] = [
            .fearful: 0.7,
            .angry: 0.6,
            .surprised: 0.3,
            .disgust: 0.4,
            .happy: 0.0,
            .calm: 0.0,
            .sad: 0.0,
            .neutral: 0.0
        ]

        // Dorsal Vagal (shutdown)
        static let dorsal: [EmotionLabel: Double] = [
            .sad: 0.8,
            .neutral: 0.4,
            .disgust: 0.2,
            .calm: 0.0,
            .happy: 0.0,
            .fearful: 0.1,
            .angry: 0.0,
            .surprised: 0.0
        ]
    }

    // MARK: - Public Interface

    /// Extract polyvagal features from emotion predictions
    /// - Parameter emotions: Recent emotion predictions from EmotionAnalyzer
    /// - Returns: Polyvagal voice features for classification
    func extractFeatures(from emotions: [EmotionPrediction]) -> PolyvagalVoiceFeatures {
        guard !emotions.isEmpty else {
            return defaultFeatures()
        }

        // Calculate emotion distribution
        let emotionScores = calculateEmotionScores(from: emotions)

        // Calculate polyvagal state scores
        let socialEngagementScore = calculateStateScore(emotionScores, weights: EmotionWeights.ventral)
        let threatActivationScore = calculateStateScore(emotionScores, weights: EmotionWeights.sympathetic)
        let shutdownRiskScore = calculateStateScore(emotionScores, weights: EmotionWeights.dorsal)

        // Calculate prosodic features
        let pitchVariability = estimatePitchVariability(from: emotions)
        let speechRate = estimateSpeechRate(from: emotions)
        let voiceIntensity = estimateVoiceIntensity(from: emotions)

        // Calculate emotional ratios
        let positiveEmotionRatio = calculatePositiveRatio(emotionScores)
        let negativeEmotionRatio = calculateNegativeRatio(emotionScores)
        let arousalLevel = calculateArousalLevel(emotionScores)

        return PolyvagalVoiceFeatures(
            pitchVariability: pitchVariability,
            speechRate: speechRate,
            voiceIntensity: voiceIntensity,
            positiveEmotionRatio: positiveEmotionRatio,
            negativeEmotionRatio: negativeEmotionRatio,
            arousalLevel: arousalLevel,
            socialEngagementScore: socialEngagementScore,
            threatActivationScore: threatActivationScore,
            shutdownRiskScore: shutdownRiskScore
        )
    }

    // MARK: - Private Methods - Emotion Scoring

    private func calculateEmotionScores(from emotions: [EmotionPrediction]) -> [EmotionLabel: Double] {
        var scores: [EmotionLabel: Double] = [:]

        // Sum confidence scores for each emotion label
        for prediction in emotions {
            guard let label = EmotionLabel(rawValue: prediction.emotion.lowercased()) else {
                continue
            }
            scores[label, default: 0] += prediction.confidence
        }

        // Normalize by count
        guard !emotions.isEmpty else { return scores }
        let count = Double(emotions.count)
        for label in scores.keys {
            scores[label]! /= count
        }

        return scores
    }

    private func calculateStateScore(_ emotionScores: [EmotionLabel: Double], weights: [EmotionLabel: Double]) -> Double {
        var score = 0.0
        for (label, weight) in weights {
            score += (emotionScores[label] ?? 0) * weight
        }
        return min(1.0, score)
    }

    // MARK: - Private Methods - Prosodic Estimation

    private func estimatePitchVariability(from emotions: [EmotionPrediction]) -> Double {
        // Estimate pitch variability from emotion distribution
        // High arousal emotions (fear, anger) → high pitch variability
        // Low arousal emotions (sad, calm) → low pitch variability

        let emotionScores = calculateEmotionScores(from: emotions)

        let fearful: Double = (emotionScores[.fearful] ?? 0) * 30.0
        let angry: Double = (emotionScores[.angry] ?? 0) * 25.0
        let surprised: Double = (emotionScores[.surprised] ?? 0) * 20.0
        let highVariability = fearful + angry + surprised

        let happy: Double = (emotionScores[.happy] ?? 0) * 12.0
        let calm: Double = (emotionScores[.calm] ?? 0) * 10.0
        let moderateVariability = happy + calm

        let sad: Double = (emotionScores[.sad] ?? 0) * 3.0
        let neutral: Double = (emotionScores[.neutral] ?? 0) * 5.0
        let lowVariability = sad + neutral

        return highVariability + moderateVariability + lowVariability
    }

    private func estimateSpeechRate(from emotions: [EmotionPrediction]) -> Double {
        // Estimate speech rate from emotion activation
        // Sympathetic activation → rapid speech
        // Dorsal shutdown → slow speech

        let emotionScores = calculateEmotionScores(from: emotions)

        let fearfulRapid: Double = (emotionScores[.fearful] ?? 0) * 200.0
        let angryRapid: Double = (emotionScores[.angry] ?? 0) * 180.0
        let rapidSpeech = fearfulRapid + angryRapid

        let happyNormal: Double = (emotionScores[.happy] ?? 0) * 130.0
        let calmNormal: Double = (emotionScores[.calm] ?? 0) * 110.0
        let neutralNormal: Double = (emotionScores[.neutral] ?? 0) * 120.0
        let normalSpeech = happyNormal + calmNormal + neutralNormal

        let slowSpeech: Double = (emotionScores[.sad] ?? 0) * 80.0

        return rapidSpeech + normalSpeech + slowSpeech
    }

    private func estimateVoiceIntensity(from emotions: [EmotionPrediction]) -> Double {
        // Estimate voice intensity (dB) from emotion activation
        let emotionScores = calculateEmotionScores(from: emotions)

        let angryHigh: Double = (emotionScores[.angry] ?? 0) * 75.0
        let fearfulHigh: Double = (emotionScores[.fearful] ?? 0) * 70.0
        let highIntensity = angryHigh + fearfulHigh

        let happyMod: Double = (emotionScores[.happy] ?? 0) * 65.0
        let surprisedMod: Double = (emotionScores[.surprised] ?? 0) * 68.0
        let moderateIntensity = happyMod + surprisedMod

        let sadLow: Double = (emotionScores[.sad] ?? 0) * 55.0
        let calmLow: Double = (emotionScores[.calm] ?? 0) * 60.0
        let neutralLow: Double = (emotionScores[.neutral] ?? 0) * 58.0
        let lowIntensity = sadLow + calmLow + neutralLow

        return highIntensity + moderateIntensity + lowIntensity
    }

    // MARK: - Private Methods - Emotional Ratios

    private func calculatePositiveRatio(_ emotionScores: [EmotionLabel: Double]) -> Double {
        let positive = (emotionScores[.happy] ?? 0) + (emotionScores[.calm] ?? 0)
        let total = emotionScores.values.reduce(0, +)
        return total > 0 ? positive / total : 0
    }

    private func calculateNegativeRatio(_ emotionScores: [EmotionLabel: Double]) -> Double {
        let negative = (emotionScores[.sad] ?? 0) + (emotionScores[.fearful] ?? 0) + (emotionScores[.angry] ?? 0) + (emotionScores[.disgust] ?? 0)
        let total = emotionScores.values.reduce(0, +)
        return total > 0 ? negative / total : 0
    }

    private func calculateArousalLevel(_ emotionScores: [EmotionLabel: Double]) -> Double {
        // Arousal: High (fear, anger, surprise), Low (sad, calm, neutral)
        let highArousal = (emotionScores[.fearful] ?? 0) + (emotionScores[.angry] ?? 0) + (emotionScores[.surprised] ?? 0)
        let lowArousal = (emotionScores[.sad] ?? 0) + (emotionScores[.calm] ?? 0) + (emotionScores[.neutral] ?? 0)
        let total = emotionScores.values.reduce(0, +)

        if total == 0 { return 0.5 }

        // Map to 0-1 scale (0 = low arousal, 1 = high arousal)
        return highArousal / total
    }

    // MARK: - Default Values

    private func defaultFeatures() -> PolyvagalVoiceFeatures {
        return PolyvagalVoiceFeatures(
            pitchVariability: 10.0,
            speechRate: 120.0,
            voiceIntensity: 60.0,
            positiveEmotionRatio: 0.5,
            negativeEmotionRatio: 0.5,
            arousalLevel: 0.5,
            socialEngagementScore: 0.5,
            threatActivationScore: 0.5,
            shutdownRiskScore: 0.5
        )
    }
}
