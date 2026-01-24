//
//  EfficacyCalculator.swift
//  MindFriendApp
//
//  Intervention Efficacy Engine - Efficacy Calculation Service
//

import Foundation

struct EfficacyCalculator {
    
    /// Calculates efficacy from emotional trajectory
    /// Returns nil if insufficient data (< 3 samples)
    func calculateEfficacy(trajectory: [TrajectoryPoint], sessionDuration: TimeInterval) -> InterventionEfficacy? {
        guard trajectory.count >= 3 else { return nil }
        
        // Extract phases (pre: first 20%, mid: 20-80%, post: last 20%)
        let totalPoints = trajectory.count
        let preEndIndex = max(1, Int(Double(totalPoints) * 0.2))
        let midStartIndex = preEndIndex
        let midEndIndex = Int(Double(totalPoints) * 0.8)
        let postStartIndex = midEndIndex
        
        let prePhase = Array(trajectory[0..<preEndIndex])
        let midPhase = Array(trajectory[midStartIndex..<midEndIndex])
        let postPhase = Array(trajectory[postStartIndex..<totalPoints])
        
        // Calculate metrics
        let startingScore = prePhase.first?.compositeScore ?? 0
        let endingScore = postPhase.last?.compositeScore ?? 0
        let netEmotionalChange = max(-1, min(1, endingScore - startingScore))
        
        // Regulation quality: 1 - std_dev of middle 60%
        let midScores = midPhase.map { $0.compositeScore }
        let midMean = midScores.reduce(0, +) / Double(midScores.count)
        let midVariance = midScores.reduce(0) { $0 + pow($1 - midMean, 2) } / Double(midScores.count)
        let midStdDev = sqrt(midVariance)
        let regulationQuality = max(0, min(1, 1 - midStdDev))
        
        // Sustained improvement
        let preAvg = prePhase.map { $0.compositeScore }.reduce(0, +) / Double(prePhase.count)
        let postAvg = postPhase.map { $0.compositeScore }.reduce(0, +) / Double(postPhase.count)
        let sustainedImprovement = max(-1, min(1, postAvg - preAvg))
        
        // Composite score using CORRECTED FORMULA: 2 * (weighted_sum) - 1
        let weights: (Double, Double, Double) = (0.4, 0.35, 0.25)
        let weightedSum = weights.0 * (netEmotionalChange + 1) / 2 +
                         weights.1 * regulationQuality +
                         weights.2 * (sustainedImprovement + 1) / 2
        let compositeScore = max(-1, min(1, 2 * weightedSum - 1))
        
        // Convert to 0-100 efficacy score
        var efficacyScore = 50 + (compositeScore * 40)
        
        // Sustained improvement bonus
        if sustainedImprovement > 0 && postAvg >= endingScore - 0.1 {
            efficacyScore += 10
        }
        
        // Breakthrough detection
        let breakthrough = detectBreakthrough(trajectory: trajectory)
        if breakthrough.detected {
            efficacyScore += 10
        }
        
        // Starting state penalty (if already in good state)
        if startingScore > 0.5 {
            efficacyScore *= 0.9
        }
        
        efficacyScore = max(0, min(100, efficacyScore))
        
        // Determine trajectory shape
        let trajectoryShape = determineTrajectoryShape(trajectory: trajectory, netChange: netEmotionalChange)
        
        return InterventionEfficacy(
            id: UUID(),
            userId: UUID(), // Will be set by caller
            exerciseId: UUID(), // Will be set by caller
            sessionId: UUID(), // Will be set by caller
            completedAt: Date(),
            efficacyScore: efficacyScore,
            netEmotionalChange: netEmotionalChange,
            trajectoryShape: trajectoryShape,
            breakthroughDetected: breakthrough.detected,
            breakthroughSecond: breakthrough.second,
            startingState: InterventionEfficacy.InterventionContext(
                nervousSystemState: trajectory.first?.nervousSystemState ?? "unknown",
                primaryEmotion: trajectory.first?.emotionClassification?.primary ?? "neutral",
                stressLevel: startingScore < -0.5 ? 0.8 : startingScore < 0 ? 0.5 : 0.2
            ),
            timeOfDay: determineTimeOfDay(date: Date()),
            dayOfWeek: Calendar.current.component(.weekday, from: Date()),
            priorSleepQuality: nil,
            stressLevel: nil,
            createdAt: Date()
        )
    }
    
    private func detectBreakthrough(trajectory: [TrajectoryPoint]) -> (detected: Bool, second: Int?) {
        for i in 0..<(trajectory.count - 1) {
            let current = trajectory[i]
            let next = trajectory[i + 1]
            let change = next.compositeScore - current.compositeScore
            let duration = next.secondsFromStart - current.secondsFromStart
            
            if change > 0.4 && duration <= 60 {
                return (true, next.secondsFromStart)
            }
        }
        
        return (false, nil)
    }
    
    private func determineTrajectoryShape(trajectory: [TrajectoryPoint], netChange: Double) -> TrajectoryShape {
        guard trajectory.count >= 3 else { return .flat }
        
        let startingScore = trajectory.first?.compositeScore ?? 0
        let endingScore = trajectory.last?.compositeScore ?? 0
        let midpoint = trajectory[trajectory.count / 2].compositeScore
        
        if netChange > 0.3 {
            if midpoint > startingScore {
                return .steadyImprovement
            } else {
                return .lateBreakthrough
            }
        } else if netChange > 0.3 && midpoint > endingScore {
            return .earlyPeak
        } else if netChange < -0.1 {
            return .deterioration
        } else {
            return .flat
        }
    }
    
    private func determineTimeOfDay(date: Date) -> InterventionEfficacy.TimeOfDay {
        let hour = Calendar.current.component(.hour, from: date)
        
        if hour >= 5 && hour < 12 {
            return .morning
        } else if hour >= 12 && hour < 17 {
            return .afternoon
        } else if hour >= 17 && hour < 21 {
            return .evening
        } else {
            return .night
        }
    }
}
