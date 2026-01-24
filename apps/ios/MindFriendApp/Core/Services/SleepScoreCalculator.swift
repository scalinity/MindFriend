import Foundation

/// Calculator for sleep quality scores (0-100) with component breakdown
///
/// Score Components:
/// - Duration: 0-25 points (vs target duration)
/// - Efficiency: 0-25 points (time asleep / time in bed)
/// - Timing: 0-20 points (consistency with target bedtime)
/// - Stages: 0-20 points (deep/REM sleep quality)
/// - Restfulness: 0-10 points (wake events)
struct SleepScoreCalculator {

    // MARK: - Public Interface

    /// Calculate comprehensive sleep score with breakdown
    func calculateScore(entry: SleepEntry, goals: SleepGoals) -> SleepScoreBreakdown {
        let duration = calculateDurationScore(entry: entry, goals: goals)
        let efficiency = calculateEfficiencyScore(entry: entry)
        let timing = calculateTimingScore(entry: entry, goals: goals)
        let stages = calculateStagesScore(entry: entry)
        let restfulness = calculateRestfulnessScore(entry: entry)

        return SleepScoreBreakdown(
            duration: duration,
            efficiency: efficiency,
            timing: timing,
            stages: stages,
            restfulness: restfulness
        )
    }

    // MARK: - Duration Score (0-25 points)

    /// Score based on how close sleep duration is to target
    ///
    /// - Optimal: 90-110% of target = 25 points
    /// - Good: 80-90% or 110-120% = 20 points
    /// - Acceptable: 70-80% or 120-130% = 15 points
    /// - Poor: <70% or >130% = scaled 5-15 points
    private func calculateDurationScore(entry: SleepEntry, goals: SleepGoals) -> Int {
        let target = Double(goals.targetDurationMinutes)
        let actual = Double(entry.timeAsleepMinutes ?? entry.timeInBedMinutes)
        let ratio = actual / target

        // Optimal range: 90-110% of target
        if ratio >= 0.9 && ratio <= 1.1 {
            return 25
        }

        // Good range: 80-90% or 110-120%
        if (ratio >= 0.8 && ratio < 0.9) || (ratio > 1.1 && ratio <= 1.2) {
            return 20
        }

        // Acceptable range: 70-80% or 120-130%
        if (ratio >= 0.7 && ratio < 0.8) || (ratio > 1.2 && ratio <= 1.3) {
            return 15
        }

        // Poor: <70% or >130%
        // Scale based on how far from optimal
        return max(5, Int(25 * min(ratio, 2 - ratio)))
    }

    // MARK: - Efficiency Score (0-25 points)

    /// Score based on percentage of time in bed actually asleep
    ///
    /// - 85%+ = 25 points
    /// - 80-84% = 20 points
    /// - 75-79% = 15 points
    /// - 70-74% = 10 points
    /// - <70% = 5 points
    private func calculateEfficiencyScore(entry: SleepEntry) -> Int {
        let efficiency: Double

        if let providedEfficiency = entry.sleepEfficiency {
            // Normalize: if value is <= 1.0, treat as decimal (0-1); otherwise treat as percentage (0-100)
            efficiency = providedEfficiency <= 1.0 ? providedEfficiency * 100 : providedEfficiency
        } else if let asleep = entry.timeAsleepMinutes {
            // Calculate: (time asleep / time in bed) * 100
            efficiency = (Double(asleep) / Double(entry.timeInBedMinutes)) * 100
        } else {
            // No data available, return default
            return 15
        }

        if efficiency >= 85 { return 25 }
        if efficiency >= 80 { return 20 }
        if efficiency >= 75 { return 15 }
        if efficiency >= 70 { return 10 }
        return 5
    }

    // MARK: - Timing Score (0-20 points)

    /// Score based on consistency with target bedtime
    ///
    /// - Within ±15 min = 20 points
    /// - Within ±30 min = 17 points
    /// - Within ±45 min = 14 points
    /// - Within ±60 min = 11 points
    /// - Within ±90 min = 8 points
    /// - >90 min diff = 5 points
    private func calculateTimingScore(entry: SleepEntry, goals: SleepGoals) -> Int {
        guard let targetBedtime = goals.targetBedtime else {
            // No target set, give default score
            return 15
        }

        let calendar = Calendar.current

        // Extract hour and minute components for comparison
        let bedtimeComponents = calendar.dateComponents([.hour, .minute], from: entry.bedtime)
        let targetComponents = calendar.dateComponents([.hour, .minute], from: targetBedtime)

        // Convert to minutes since midnight for easier comparison
        let bedtimeMinutes = (bedtimeComponents.hour ?? 0) * 60 + (bedtimeComponents.minute ?? 0)
        let targetMinutes = (targetComponents.hour ?? 0) * 60 + (targetComponents.minute ?? 0)

        // Calculate absolute difference
        let diff = abs(bedtimeMinutes - targetMinutes)

        // Score based on proximity to target
        if diff <= 15 { return 20 }
        if diff <= 30 { return 17 }
        if diff <= 45 { return 14 }
        if diff <= 60 { return 11 }
        if diff <= 90 { return 8 }
        return 5
    }

    // MARK: - Stages Score (0-20 points)

    /// Score based on sleep stage distribution (requires wearable data)
    ///
    /// Deep Sleep (10 points):
    /// - 15-25% of total sleep = 10 points
    /// - 10-15% or 25-30% = 7 points
    /// - Otherwise = 4 points
    ///
    /// REM Sleep (10 points):
    /// - 20-25% of total sleep = 10 points
    /// - 15-20% or 25-30% = 7 points
    /// - Otherwise = 4 points
    private func calculateStagesScore(entry: SleepEntry) -> Int {
        guard let deep = entry.deepSleepMinutes,
              let rem = entry.remSleepMinutes,
              let totalAsleep = entry.timeAsleepMinutes else {
            // No stage data available (manual entry or older device)
            return 0 // Return 0 when data is missing
        }

        var score = 0

        // Deep sleep score (0-10 points)
        let deepPercent = (Double(deep) / Double(totalAsleep)) * 100

        if deepPercent >= 15 && deepPercent <= 25 {
            score += 10 // Optimal deep sleep
        } else if (deepPercent >= 10 && deepPercent < 15) || (deepPercent > 25 && deepPercent <= 30) {
            score += 7 // Good deep sleep
        } else {
            score += 4 // Suboptimal deep sleep
        }

        // REM sleep score (0-10 points)
        let remPercent = (Double(rem) / Double(totalAsleep)) * 100

        if remPercent >= 20 && remPercent <= 25 {
            score += 10 // Optimal REM sleep
        } else if (remPercent >= 15 && remPercent < 20) || (remPercent > 25 && remPercent <= 30) {
            score += 7 // Good REM sleep
        } else {
            score += 4 // Suboptimal REM sleep
        }

        return score
    }

    // MARK: - Restfulness Score (0-10 points)

    /// Score based on wake events during the night
    ///
    /// - <5% awake time = 10 points
    /// - 5-10% = 8 points
    /// - 10-15% = 6 points
    /// - 15-20% = 4 points
    /// - >20% = 2 points
    private func calculateRestfulnessScore(entry: SleepEntry) -> Int {
        guard let awake = entry.awakeMinutes else {
            // No wake data available, give default
            return 5
        }

        let awakePercent = (Double(awake) / Double(entry.timeInBedMinutes)) * 100

        if awakePercent < 5 { return 10 }
        if awakePercent < 10 { return 8 }
        if awakePercent < 15 { return 6 }
        if awakePercent < 20 { return 4 }
        return 2
    }

    // MARK: - Validation

    /// Validate that a sleep entry has valid data for scoring
    func isValidForScoring(entry: SleepEntry) -> Bool {
        // Must have basic timing data
        guard entry.timeInBedMinutes >= 60, entry.timeInBedMinutes <= 1440 else {
            return false
        }

        // Wake time must be after bedtime
        guard entry.wakeTime > entry.bedtime else {
            return false
        }

        // If sleep time is provided, it must be <= time in bed
        if let asleep = entry.timeAsleepMinutes {
            guard asleep <= entry.timeInBedMinutes else {
                return false
            }
        }

        return true
    }
}
