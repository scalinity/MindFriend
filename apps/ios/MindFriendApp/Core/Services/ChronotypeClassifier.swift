//
//  ChronotypeClassifier.swift
//  MindFriendApp
//
//  Created: 2026-01-22
//  Spec: N002 - Circadian Vulnerability Shield
//  Purpose: Determines user's chronotype from sleep patterns using MSFsc algorithm
//

import Foundation

// Note: CircadianModels types (SleepRecord, Chronotype, etc.) are defined in CircadianModels.swift
// and will be available when both files are compiled together in the Xcode project

/// Classifies user's chronotype from sleep pattern analysis
final class ChronotypeClassifier {

    // MARK: - Constants

    private let minimumDataDays = 5
    private let recommendedDataDays = 7

    // MARK: - Public API

    /// Determines chronotype from sleep patterns
    /// Uses MSFsc (mid-sleep on free days, corrected for sleep debt) algorithm
    /// - Parameter sleepRecords: Array of sleep records (minimum 5 days)
    /// - Returns: Tuple of (Chronotype, confidence score 0-1)
    /// - Throws: CircadianError.insufficientSleepData if < 5 days
    func classify(sleepRecords: [SleepRecord]) throws -> (Chronotype, confidence: Double) {
        // Validate minimum data requirement
        guard sleepRecords.count >= minimumDataDays else {
            throw CircadianError.insufficientSleepData(
                daysAvailable: sleepRecords.count,
                required: minimumDataDays
            )
        }

        // Separate weekdays and weekends
        let weekdaySleep = sleepRecords.filter { !$0.isWeekend }
        let weekendSleep = sleepRecords.filter { $0.isWeekend }

        // If no weekend data, use weekday late nights as proxy
        let freeDaySleep = weekendSleep.isEmpty ? weekdaySleep.filter { record in
            let hour = Calendar.current.component(.hour, from: record.startTime)
            return hour >= 23 || hour <= 2  // Late bedtime suggests natural preference
        } : weekendSleep

        guard !freeDaySleep.isEmpty else {
            // Insufficient data - return default
            return (.intermediate, 0.3)
        }

        // Calculate MSF (mid-sleep on free days)
        let freeDayMidpoints = freeDaySleep.map { $0.midpointOfSleep }
        let averageMSF = freeDayMidpoints.average()

        // Calculate sleep debt (weekend vs weekday difference)
        let weekdayDuration = weekdaySleep.isEmpty ? 0 : weekdaySleep.map { $0.duration }.average()
        let freeDayDuration = freeDaySleep.map { $0.duration }.average()
        let sleepDebt = max(0, freeDayDuration - weekdayDuration)

        // Correct for sleep debt → MSFsc
        let msfCorrected = averageMSF + (sleepDebt / 2)

        // Map MSFsc to chronotype (based on Roenneberg 2003)
        let chronotype = mapToChronotype(msfCorrected: msfCorrected)

        // Calculate confidence based on data consistency
        let variance = freeDayMidpoints.standardDeviation()
        let dataQuality = Double(sleepRecords.count) / Double(recommendedDataDays)
        let consistencyScore = max(0.5, 1.0 - (variance / TimeInterval.hours(2)))
        let confidence = min(consistencyScore * dataQuality, 1.0)

        return (chronotype, confidence)
    }

    /// Check if we have minimum data for classification
    func hasMinimumData(_ records: [SleepRecord]) -> Bool {
        return records.count >= minimumDataDays
    }

    /// Calculate social jet lag (weekday vs weekend difference)
    func calculateSocialJetLag(sleepRecords: [SleepRecord]) -> Int {
        let weekdaySleep = sleepRecords.filter { !$0.isWeekend }
        let weekendSleep = sleepRecords.filter { $0.isWeekend }

        guard !weekdaySleep.isEmpty, !weekendSleep.isEmpty else {
            return 0
        }

        let weekdayMidpoint = weekdaySleep.map { $0.midpointOfSleep }.average()
        let weekendMidpoint = weekendSleep.map { $0.midpointOfSleep }.average()

        let difference = abs(weekendMidpoint - weekdayMidpoint)
        return Int(difference / 60)  // Convert to minutes
    }

    // MARK: - Private Helpers

    /// Map MSFsc value to chronotype category
    /// Based on research by Roenneberg et al. (2003, 2012)
    private func mapToChronotype(msfCorrected: TimeInterval) -> Chronotype {
        let hours = msfCorrected / 3600

        switch hours {
        case ..<2.5:
            return .extremeMorning      // Wake ~4-5am
        case 2.5..<3.5:
            return .moderateMorning     // Wake ~5-6:30am
        case 3.5..<4.5:
            return .intermediate        // Wake ~6:30-8am
        case 4.5..<5.5:
            return .moderateEvening     // Wake ~8-9:30am
        default:
            return .extremeEvening      // Wake ~10am+
        }
    }

    /// Calculate natural wake time from chronotype
    func estimateNaturalWakeTime(from records: [SleepRecord]) -> TimeInterval {
        let weekendRecords = records.filter { $0.isWeekend }
        let relevantRecords = weekendRecords.isEmpty ? records : weekendRecords

        guard !relevantRecords.isEmpty else {
            return TimeInterval.hours(7)  // Default 7am
        }

        // Average wake time (end of sleep)
        let wakeTimes = relevantRecords.map { record -> TimeInterval in
            let calendar = Calendar.current
            let midnight = calendar.startOfDay(for: record.date)
            return record.endTime.timeIntervalSince(midnight)
        }

        return wakeTimes.average()
    }

    /// Calculate natural sleep time from chronotype
    func estimateNaturalSleepTime(from records: [SleepRecord]) -> TimeInterval {
        let weekendRecords = records.filter { $0.isWeekend }
        let relevantRecords = weekendRecords.isEmpty ? records : weekendRecords

        guard !relevantRecords.isEmpty else {
            return TimeInterval.hours(23)  // Default 11pm
        }

        // Average sleep time (start of sleep, adjusted for midnight crossing)
        let sleepTimes = relevantRecords.map { record -> TimeInterval in
            let calendar = Calendar.current
            let midnight = calendar.startOfDay(for: record.date)
            let secondsSinceMidnight = record.startTime.timeIntervalSince(midnight)

            // If negative (previous day), add 24 hours
            if secondsSinceMidnight < 0 {
                return TimeInterval.hours(24) + secondsSinceMidnight
            }

            // If very early (0-6am), assume it's late previous night
            if secondsSinceMidnight < TimeInterval.hours(6) {
                return TimeInterval.hours(24) + secondsSinceMidnight
            }

            return secondsSinceMidnight
        }

        let avgSleepTime = sleepTimes.average()

        // Normalize to 0-86400 range
        return avgSleepTime.truncatingRemainder(dividingBy: 86400)
    }
}
