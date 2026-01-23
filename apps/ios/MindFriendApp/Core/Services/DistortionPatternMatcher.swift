//
//  DistortionPatternMatcher.swift
//  MindFriendApp
//
//  Created by dev-pipeline
//  Client-side cognitive distortion pattern matching
//

import Foundation

/// Pattern matcher for detecting cognitive distortions using keyword matching
/// Optimized with cached regex patterns and LRU cache for recent detections
final class DistortionPatternMatcher {

    // MARK: - Configuration

    /// Minimum confidence threshold (0.0 - 1.0)
    private let confidenceThreshold: Double = 0.50

    // MARK: - Cached Regex Patterns
    
    /// Pre-compiled regex patterns for efficient matching (computed once at initialization)
    private let regexPatterns: [DistortionType: [(regex: NSRegularExpression, weight: Double)]]
    
    // MARK: - LRU Cache
    
    /// Simple LRU cache for recent detections (max 50 entries)
    private var detectionCache: [String: (type: DistortionType, confidence: Double)?] = [:]
    private var cacheKeys: [String] = []
    private let maxCacheSize = 50
    
    // MARK: - Initialization
    
    init() {
        // Pre-compile all regex patterns at initialization for performance
        var compiledPatterns: [DistortionType: [(regex: NSRegularExpression, weight: Double)]] = [:]
        
        for (distortionType, keywords) in Self.patterns {
            var regexList: [(regex: NSRegularExpression, weight: Double)] = []
            
            for (keyword, weight) in keywords {
                // Create word boundary regex for more accurate matching
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    regexList.append((regex: regex, weight: weight))
                }
            }
            
            compiledPatterns[distortionType] = regexList
        }
        
        self.regexPatterns = compiledPatterns
    }

    // MARK: - Pattern Definitions (Static)

    /// Keyword patterns for each distortion type with confidence weights
    private static let patterns: [DistortionType: [String: Double]] = [
        .allOrNothing: [
            "always": 1.0,
            "never": 1.0,
            "every time": 0.9,
            "completely": 0.8,
            "totally": 0.8,
            "absolutely": 0.7,
            "perfect": 0.7,
            "impossible": 0.9,
            "everything": 0.8,
            "nothing": 0.8
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

    // MARK: - Public Interface

    /// Detects cognitive distortion in text using optimized regex matching
    /// - Parameter text: Input text to analyze
    /// - Returns: Tuple of distortion type and confidence, or nil if no distortion detected
    func detectDistortion(in text: String) -> (type: DistortionType, confidence: Double)? {
        // Normalize text for cache key
        let normalizedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check cache first (O(1) lookup)
        if let cached = detectionCache[normalizedText] {
            return cached
        }
        
        // Perform detection
        let result = detectDistortionUncached(in: text)
        
        // Update cache (LRU eviction)
        updateCache(key: normalizedText, value: result)
        
        return result
    }
    
    // MARK: - Private Helpers
    
    /// Performs uncached detection using pre-compiled regex patterns
    private func detectDistortionUncached(in text: String) -> (type: DistortionType, confidence: Double)? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        
        var matches: [(type: DistortionType, confidence: Double)] = []

        // Use pre-compiled regex patterns for O(n×m) instead of O(n×m×k) complexity
        for (distortionType, regexList) in regexPatterns {
            var totalScore: Double = 0
            var totalMatches = 0

            for (regex, weight) in regexList {
                let count = regex.numberOfMatches(in: text, range: range)
                if count > 0 {
                    totalScore += weight * Double(count)
                    totalMatches += count
                }
            }

            if totalMatches > 0 {
                // Confidence formula: normalized score + bonus for multiple matches
                let normalizedScore = totalScore / Double(regexList.count)
                let matchBonus = min(0.3, Double(totalMatches) * 0.1)
                let confidence = min(0.95, normalizedScore + matchBonus)

                matches.append((type: distortionType, confidence: confidence))
            }
        }

        // Return highest confidence match above threshold
        guard let bestMatch = matches.max(by: { $0.confidence < $1.confidence }),
              bestMatch.confidence >= confidenceThreshold else {
            return nil
        }

        return bestMatch
    }
    
    /// Updates LRU cache with new detection result
    private func updateCache(key: String, value: (type: DistortionType, confidence: Double)?) {
        // Add to cache
        detectionCache[key] = value
        cacheKeys.append(key)
        
        // Evict oldest entry if cache is full
        if cacheKeys.count > maxCacheSize {
            let oldestKey = cacheKeys.removeFirst()
            detectionCache.removeValue(forKey: oldestKey)
        }
    }
    
    /// Clears the detection cache (useful for testing or memory pressure)
    func clearCache() {
        detectionCache.removeAll()
        cacheKeys.removeAll()
    }
}
