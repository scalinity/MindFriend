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
        // Single pass to compute mean and variance simultaneously
        guard !midPhase.isEmpty else {
            // Return nil if midPhase is empty (cannot assess regulation quality without middle phase)
            return nil
        }

        var midSum = 0.0
        var midSumSq = 0.0
        for point in midPhase {
            let s = point.compositeScore
            midSum += s
            midSumSq += s * s
        }
        let midMean = midSum / Double(midPhase.count)
        let midVariance = midSumSq / Double(midPhase.count) - midMean * midMean
        let midStdDev = sqrt(max(0, midVariance))
        let regulationQuality = max(0, min(1, 1 - midStdDev))
        
        // Sustained improvement (single pass for each phase average)
        let preAvg = prePhase.reduce(0.0) { $0 + $1.compositeScore } / Double(prePhase.count)
        let postAvg = postPhase.reduce(0.0) { $0 + $1.compositeScore } / Double(postPhase.count)
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
        
        // Trajectory shape classification (fixed unreachable code bug)
        let trajectoryShape: TrajectoryShape
        if netChange > 0.3 {
            // Check earlyPeak first (peak in middle but decline at end)
            if midpoint > endingScore && midpoint > startingScore {
                trajectoryShape = .earlyPeak
            } else if midpoint > startingScore {
                trajectoryShape = .steadyImprovement
            } else {
                trajectoryShape = .lateBreakthrough
            }
        } else if netChange < -0.2 {
            trajectoryShape = .deterioration
        } else {
            trajectoryShape = .flat
        }
        
        return trajectoryShape
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
