//
//  DistortionPatternMatcher.swift
//  MindFriendApp
//
//  Created by dev-pipeline
//  Client-side cognitive distortion pattern matching
//

import Foundation

/// Client-side pattern matcher for cognitive distortions
/// Uses keyword-based detection with confidence scoring
@MainActor
final class DistortionPatternMatcher {

    // MARK: - Pattern Definitions

    /// Keyword patterns for each distortion type
    /// Confidence weights: 1.0 = strong indicator, 0.5 = weak indicator
    private let patterns: [DistortionType: [String: Double]] = [
        .allOrNothing: [
            "always": 1.0,
            "never": 1.0,
            "every time": 0.9,
            "completely": 0.7,
            "totally": 0.7,
            "perfect": 0.6,
            "failure": 0.6,
            "either": 0.5,
            "all or nothing": 1.0
        ],
        .overgeneralization: [
            "always happens": 1.0,
            "never works": 1.0,
            "everyone": 0.8,
            "nobody": 0.8,
            "typical": 0.6,
            "same old": 0.7,
            "story of my life": 0.9
        ],
        .mentalFilter: [
            "only negative": 0.9,
            "just bad": 0.8,
            "nothing good": 1.0,
            "everything wrong": 1.0,
            "can't see": 0.6
        ],
        .disqualifyingPositive: [
            "doesn't count": 1.0,
            "doesn't matter": 0.9,
            "just luck": 0.9,
            "anyone could": 0.8,
            "not a big deal": 0.7,
            "yeah but": 0.8
        ],
        .jumpingToConclusions: [
            "probably thinks": 1.0,
            "must think": 1.0,
            "going to fail": 0.9,
            "will never": 0.9,
            "they hate": 0.8,
            "know what they're thinking": 0.9
        ],
        .magnificationMinimization: [
            "catastrophic": 1.0,
            "disaster": 1.0,
            "terrible": 0.8,
            "awful": 0.8,
            "not that good": 0.7,
            "just small": 0.6,
            "worst thing": 0.9
        ],
        .emotionalReasoning: [
            "feel like": 0.7,
            "feeling means": 0.9,
            "feel stupid so": 1.0,
            "feel therefore": 1.0,
            "must be true because": 0.8
        ],
        .shouldStatements: [
            "should": 0.8,
            "must": 0.8,
            "have to": 0.7,
            "ought to": 0.8,
            "need to": 0.6,
            "supposed to": 0.7
        ],
        .labeling: [
            "i am a loser": 1.0,
            "i am a failure": 1.0,
            "such a": 0.7,
            "total idiot": 1.0,
            "i'm stupid": 0.9,
            "i'm worthless": 1.0
        ],
        .personalization: [
            "my fault": 1.0,
            "because of me": 1.0,
            "i caused": 0.9,
            "i'm responsible": 0.8,
            "if only i": 0.8,
            "i should have": 0.7
        ]
    ]

    // MARK: - Detection

    /// Detects cognitive distortions in transcript text
    /// - Parameter text: Transcript text to analyze
    /// - Returns: Detected distortion with confidence score, or nil if none found
    func detectDistortion(in text: String) -> (type: DistortionType, confidence: Double)? {
        let lowerText = text.lowercased()
        var matches: [(type: DistortionType, score: Double)] = []

        // Check each distortion type
        for (distortionType, keywords) in patterns {
            var totalScore: Double = 0
            var matchCount = 0

            for (keyword, weight) in keywords {
                if lowerText.contains(keyword) {
                    totalScore += weight
                    matchCount += 1
                }
            }

            if matchCount > 0 {
                // Calculate confidence based on total score and match count
                // More matches and higher weights = higher confidence
                let confidence = min(0.95, (totalScore / Double(keywords.count)) + (Double(matchCount) * 0.1))
                matches.append((type: distortionType, score: confidence))
            }
        }

        // Return highest confidence match
        guard let topMatch = matches.max(by: { $0.score < $1.score }) else {
            return nil
        }

        return (type: topMatch.type, confidence: topMatch.score)
    }

    /// Batch detection for multiple text segments
    /// - Parameter segments: Array of text segments to analyze
    /// - Returns: Array of detected distortions
    func detectDistortions(in segments: [String]) -> [(type: DistortionType, confidence: Double)] {
        return segments.compactMap { detectDistortion(in: $0) }
    }

    /// Validates if a detected distortion meets the minimum confidence threshold
    /// - Parameters:
    ///   - confidence: Confidence score from detection
    ///   - threshold: Minimum threshold (default: 0.70)
    /// - Returns: True if confidence meets threshold
    func meetsThreshold(_ confidence: Double, threshold: Double = 0.70) -> Bool {
        return confidence >= threshold
    }
}
