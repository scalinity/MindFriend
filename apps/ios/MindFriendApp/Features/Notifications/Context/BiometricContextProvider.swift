import Foundation
import HealthKit

/// Protocol for biometric context provision (enables testing)
protocol BiometricContextProviding {
    func getContext() async -> BiometricContext
    func requestAccess() async -> Bool
}

/// Provides biometric context using HealthKit
/// Reads heart rate, HRV, and sleep data
@MainActor
final class BiometricContextProvider: BiometricContextProviding {
    private let healthStore = HKHealthStore()
    private var hasAccess = false

    // HRV baseline (rolling average over 30 days)
    private var hrvBaseline: Double?
    private var lastBaselineUpdate: Date?

    // Required data types
    private let heartRateType = HKQuantityType(.heartRate)
    private let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    private let sleepType = HKCategoryType(.sleepAnalysis)

    init() {}

    /// Request HealthKit access for biometric data
    func requestAccess() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }

        let typesToRead: Set<HKObjectType> = [
            heartRateType,
            hrvType,
            sleepType
        ]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            hasAccess = true
            return true
        } catch {
            Log.notifications.debug("[BiometricContext] Access request failed: \(error)")
            return false
        }
    }

    /// Get current biometric context
    /// Returns default context if permission denied or data unavailable
    func getContext() async -> BiometricContext {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .default
        }

        // Fetch data in parallel
        async let heartRateResult = fetchLatestHeartRate()
        async let hrvResult = fetchLatestHRV()
        async let sleepResult = fetchLastNightSleep()

        let heartRate = await heartRateResult
        let hrvCurrent = await hrvResult
        let sleepHours = await sleepResult

        // Update HRV baseline periodically
        await updateHRVBaselineIfNeeded()

        // Calculate stress indicator
        let isStressed = BiometricContext.calculateStress(
            hrvCurrent: hrvCurrent,
            hrvBaseline: hrvBaseline
        )

        // Calculate low energy indicator
        let isLowEnergy = calculateLowEnergy(
            heartRate: heartRate,
            sleepHours: sleepHours
        )

        return BiometricContext(
            heartRate: heartRate,
            hrvBaseline: hrvBaseline,
            hrvCurrent: hrvCurrent,
            sleepHoursLastNight: sleepHours,
            isStressed: isStressed,
            isLowEnergy: isLowEnergy
        )
    }

    // MARK: - Heart Rate

    private func fetchLatestHeartRate() async -> Double? {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.date(byAdding: .hour, value: -1, to: Date()),
            end: Date()
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: bpm)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - HRV

    private func fetchLatestHRV() async -> Double? {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.date(byAdding: .hour, value: -24, to: Date()),
            end: Date()
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let ms = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                continuation.resume(returning: ms)
            }
            healthStore.execute(query)
        }
    }

    private func updateHRVBaselineIfNeeded() async {
        // Update baseline once per day
        if let lastUpdate = lastBaselineUpdate,
           Date().timeIntervalSince(lastUpdate) < 86400 { // 24 hours
            return
        }

        hrvBaseline = await calculateHRVBaseline()
        lastBaselineUpdate = Date()
    }

    private func calculateHRVBaseline() async -> Double? {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: Date())

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: hrvType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                guard let average = statistics?.averageQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let ms = average.doubleValue(for: HKUnit.secondUnit(with: .milli))
                continuation.resume(returning: ms)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Sleep

    private func fetchLastNightSleep() async -> Double? {
        let calendar = Calendar.current
        let now = Date()

        // Define "last night" as 6pm yesterday to 12pm today
        var yesterdayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        yesterdayComponents.day! -= 1
        yesterdayComponents.hour = 18
        let startDate = calendar.date(from: yesterdayComponents)!

        var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        todayComponents.hour = 12
        let endDate = calendar.date(from: todayComponents)!

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }

                // Sum up asleep time (excluding in bed but awake)
                var totalSleepSeconds: TimeInterval = 0
                for sample in samples {
                    // Only count actual sleep, not "in bed"
                    if sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue {
                        totalSleepSeconds += sample.endDate.timeIntervalSince(sample.startDate)
                    }
                }

                let hours = totalSleepSeconds / 3600
                continuation.resume(returning: hours > 0 ? hours : nil)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Energy Calculation

    private func calculateLowEnergy(heartRate: Double?, sleepHours: Double?) -> Bool {
        // Low energy if:
        // 1. Poor sleep (< 6 hours)
        // 2. OR low heart rate during waking hours (possible fatigue)

        if let sleep = sleepHours, sleep < 6 {
            return true
        }

        // Check if resting heart rate is unusually low (might indicate fatigue)
        // Note: This is a simple heuristic; real implementation would be more sophisticated
        if let hr = heartRate, hr < 55 {
            // Only flag during waking hours (9am-9pm)
            let hour = Calendar.current.component(.hour, from: Date())
            if hour >= 9 && hour < 21 {
                return true
            }
        }

        return false
    }
}

// MARK: - Mock for Testing

/// Mock biometric context provider for testing and development
/// Returns default context without requiring HealthKit permissions
@MainActor
final class BiometricContextProvidingMock: BiometricContextProviding {
    func getContext() async -> BiometricContext {
        return .default
    }

    func requestAccess() async -> Bool {
        return true
    }
}
