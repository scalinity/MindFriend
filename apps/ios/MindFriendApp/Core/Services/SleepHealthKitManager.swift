import Foundation
import HealthKit

/// Manager for syncing sleep data from HealthKit
@MainActor
final class SleepHealthKitManager: ObservableObject {

    // MARK: - Properties

    private let healthStore = HKHealthStore()
    private let sleepTrackingService: SleepTrackingService
    private let scoreCalculator = SleepScoreCalculator()

    @Published private(set) var isAuthorized = false
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?

    // MARK: - Initialization

    init(sleepTrackingService: SleepTrackingService) {
        self.sleepTrackingService = sleepTrackingService
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    /// Request HealthKit authorization for sleep data
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw SleepHealthKitError.healthKitNotAvailable
        }

        let sleepDataTypes = getSleepDataTypes()

        try await healthStore.requestAuthorization(toShare: [], read: sleepDataTypes)

        // After requestAuthorization completes without throwing, the user has seen
        // the authorization prompt. For read-only access, we set isAuthorized = true
        // and rely on empty query results to detect denied permissions.
        // Note: authorizationStatus(for:) only tracks WRITE permissions, not read.
        isAuthorized = true
    }

    /// Check if we have authorization for sleep data
    /// Note: HealthKit does NOT provide a way to check read authorization status.
    /// We use statusForAuthorizationRequest to check if the auth dialog was already shown.
    func checkAuthorizationStatus() {
        guard HKHealthStore.isHealthDataAvailable() else {
            isAuthorized = false
            return
        }

        // Check async on a Task since this is called from init
        Task {
            await updateAuthorizationStatus()
        }
    }
    
    /// Async method to check authorization status using the proper API
    private func updateAuthorizationStatus() async {
        do {
            let status = try await healthStore.statusForAuthorizationRequest(
                toShare: [],
                read: getSleepDataTypes()
            )
            
            // .unnecessary means the auth dialog was already shown to the user
            // (regardless of whether they granted or denied permission)
            isAuthorized = (status == .unnecessary)
        } catch {
            print("Failed to check HealthKit authorization status: \(error)")
            isAuthorized = false
        }
    }

    /// Get all sleep-related data types we need to read
    private func getSleepDataTypes() -> Set<HKObjectType> {
        var types: Set<HKObjectType> = []

        // Sleep analysis (bedtime, wake time, stages)
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }

        // Heart rate
        if let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRateType)
        }

        // Heart rate variability
        if let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrvType)
        }

        // Respiratory rate
        if let respRateType = HKObjectType.quantityType(forIdentifier: .respiratoryRate) {
            types.insert(respRateType)
        }

        return types
    }

    // MARK: - Sync

    /// Sync sessions waking yesterday or today, including their complete intervals.
    func syncRecentSleep() async throws -> SleepEntry? {
        // If not authorized yet, request authorization first
        if !isAuthorized {
            try await requestAuthorization()
        }

        isSyncing = true
        defer { isSyncing = false }

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!

        let entries = try await syncSleepData(from: yesterday, latestOnly: true)
        lastSyncDate = Date()

        return entries.first
    }

    /// Sync sleep data from a specific start date
    func syncSleepData(from startDate: Date, latestOnly: Bool = false) async throws -> [SleepEntry] {
        let userId = try await sleepTrackingService.currentUserID()
        print("[SleepHealthKit] syncSleepData starting from: \(startDate)")
        
        // If not authorized yet, request authorization first
        if !isAuthorized {
            print("[SleepHealthKit] Not authorized, requesting authorization...")
            try await requestAuthorization()
        }

        isSyncing = true
        defer { isSyncing = false }

        // Query sleep analysis data
        print("[SleepHealthKit] Querying HealthKit for sleep samples...")
        // Read a full supported session before the requested wake-day range.
        // A rolling 24-hour cutoff can remove the beginning of a long sleep.
        let sleepSamples = try await querySleepAnalysis(from: startDate.addingTimeInterval(-24 * 3600))
        print("[SleepHealthKit] Found \(sleepSamples.count) sleep samples from HealthKit")

        if sleepSamples.isEmpty {
            print("[SleepHealthKit] No sleep data found in HealthKit. This could mean:")
            print("  - No sleep data recorded in Health app")
            print("  - User denied HealthKit read access")
            print("  - Running on simulator without mock data")
            return []
        }

        let groupedSamples = Self.mainSleepSessions(from: sleepSamples, wakingFrom: startDate, through: Date())
        print("[SleepHealthKit] Grouped into \(groupedSamples.count) nights")

        var entries: [SleepEntry] = []
        var syncError: Error?

        // Fetch user's sleep goals for score calculation
        print("[SleepHealthKit] Fetching sleep goals...")
        let goals = try await sleepTrackingService.fetchGoals()
        guard goals.userId == userId else { throw SleepTrackingError.invalidEntry }
        print("[SleepHealthKit] Got goals, processing sleep entries...")

        // Process each night's sleep
        for date in groupedSamples.keys.sorted(by: >).prefix(latestOnly ? 1 : groupedSamples.count) {
            let samples = groupedSamples[date]!
            guard let entry = try await processSleepSamples(samples, for: date, goals: goals) else {
                print("[SleepHealthKit] Failed to process samples for \(date)")
                continue
            }

            // Check if entry already exists (avoid duplicates)
            do {
                let existing = try await sleepTrackingService.fetchEntries(from: date, to: date)
                // Never replace a manually entered night. Refresh imported measurements in place.
                if existing.contains(where: { $0.source == .manual }) { continue }
                var canonical = try Self.matchingImport(for: entry, occupying: existing)
                if canonical == nil {
                    // Rekey an old contained import when the wake-date slot is free; keep its ID/feedback.
                    let previous = try await sleepTrackingService.fetchEntries(from: entry.bedtime, to: entry.wakeTime)
                    canonical = previous.filter {
                        $0.source != .manual && $0.userId == userId &&
                        $0.bedtime >= entry.bedtime && $0.wakeTime <= entry.wakeTime
                    }.sorted { first, second in
                        let firstHasFeedback = first.userRating != nil || first.dreamNotes != nil || first.notes != nil
                        let secondHasFeedback = second.userRating != nil || second.dreamNotes != nil || second.notes != nil
                        return firstHasFeedback == secondHasFeedback ? first.createdAt < second.createdAt : firstHasFeedback
                    }.first
                }
                let saved = try await sleepTrackingService.createEntry(entry, goals: goals, replacing: canonical)
                entries.append(saved)
            } catch {
                // Failed to check/create, skip this entry
                print("[SleepHealthKit] Failed to save a sleep session")
                syncError = syncError ?? error
            }
        }

        if let syncError { throw syncError }
        lastSyncDate = Date()

        return entries.sorted { $0.date > $1.date }
    }

    /// A legacy start-date key can belong to the following night. Never move its feedback to an unrelated session.
    static func matchingImport(for entry: SleepEntry, occupying rows: [SleepEntry]) throws -> SleepEntry? {
        guard let existing = rows.first else { return nil }
        guard existing.userId == entry.userId, existing.source != .manual,
              existing.bedtime < entry.wakeTime, existing.wakeTime > entry.bedtime else {
            throw SleepTrackingError.importDateConflict
        }
        return existing
    }

    /// Query sleep analysis samples from HealthKit
    private func querySleepAnalysis(from startDate: Date) async throws -> [HKCategorySample] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw SleepHealthKitError.invalidDataType
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: []
        )

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )

        return try await descriptor.result(for: healthStore)
    }

    /// Connected Health intervals form a session; calendar midnight is not a sleep boundary.
    static func sleepSessions(from samples: [HKCategorySample]) -> [[HKCategorySample]] {
        let ordered = samples.filter { $0.endDate > $0.startDate && $0.endDate.timeIntervalSince($0.startDate) <= 24 * 3600 }.sorted { $0.startDate < $1.startDate }
        var sessions: [[HKCategorySample]] = []
        var end: Date?
        for sample in ordered {
            // Allow at most a millisecond between Health stage handoffs for timestamp rounding.
            // Joining that boundary does not add the gap to the measured asleep duration.
            if let lastEnd = end, sample.startDate.timeIntervalSince(lastEnd) <= 0.001 {
                sessions[sessions.count - 1].append(sample)
                end = max(lastEnd, sample.endDate)
            } else {
                sessions.append([sample])
                end = sample.endDate
            }
        }
        return sessions
    }

    static func mainSleepSessions(from samples: [HKCategorySample], wakingFrom start: Date,
                                  through end: Date, calendar: Calendar = .current) -> [Date: [HKCategorySample]] {
        let sessions = sleepSessions(from: samples).filter {
            guard let bed = $0.map(\.startDate).min(), let wake = $0.map(\.endDate).max() else { return false }
            return wake >= start && wake <= end && wake.timeIntervalSince(bed) <= 24 * 3600
        }
        return Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.map(\.endDate).max()!) }
            .mapValues { candidates in
                candidates.max {
                    let first = sleepDurations($0).asleep
                    let second = sleepDurations($1).asleep
                    return first == second ? $0.map(\.endDate).max()! < $1.map(\.endDate).max()! : first < second
                }!
            }
    }

    struct SleepDurations {
        let asleep: TimeInterval
        let deep: TimeInterval
        let rem: TimeInterval
        let core: TimeInterval
        let awake: TimeInterval
        let hasCompleteStages: Bool
        let hasAwakeData: Bool
    }

    /// Merge overlapping intervals before rounding minutes; never add duplicate source durations.
    static func sleepDurations(_ samples: [HKCategorySample]) -> SleepDurations {
        let asleepValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        let asleep = samples.filter { asleepValues.contains($0.value) }
        let stages = asleep.filter { $0.value != HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue }
        let awake = samples.filter { $0.value == HKCategoryValueSleepAnalysis.awake.rawValue }
        func seconds(_ intervals: [HKCategorySample]) -> TimeInterval {
            let sorted = intervals.filter { $0.endDate > $0.startDate }.sorted { $0.startDate < $1.startDate }
            guard let first = sorted.first else { return 0 }
            var start = first.startDate
            var end = first.endDate
            var total: TimeInterval = 0
            for sample in sorted.dropFirst() {
                if sample.startDate <= end { end = max(end, sample.endDate) }
                else { total += end.timeIntervalSince(start); start = sample.startDate; end = sample.endDate }
            }
            return total + end.timeIntervalSince(start)
        }
        let total = seconds(asleep)
        let deep = seconds(stages.filter { $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue })
        let rem = seconds(stages.filter { $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue })
        let core = seconds(stages.filter { $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue })
        let awakeSeconds = seconds(awake)
        // Ambiguous or unstaged intervals cannot establish a complete component score.
        let completeStages = total > 0 && abs(seconds(stages) - total) < 0.001 &&
            abs(deep + rem + core - total) < 0.001
        let nonoverlappingAwake = abs(seconds(asleep + awake) - total - awakeSeconds) < 0.001
        return SleepDurations(asleep: total, deep: deep, rem: rem, core: core, awake: awakeSeconds,
            hasCompleteStages: completeStages, hasAwakeData: !awake.isEmpty && nonoverlappingAwake)
    }

    /// Process sleep samples for a single night
    private func processSleepSamples(
        _ samples: [HKCategorySample],
        for date: Date,
        goals: SleepGoals
    ) async throws -> SleepEntry? {
        guard !samples.isEmpty else { return nil }

        // Find overall bedtime and wake time
        guard let bedtime = samples.map({ $0.startDate }).min(),
              let wakeTime = samples.map({ $0.endDate }).max() else {
            return nil
        }

        // Query heart rate data for this sleep period
        let (avgHR, minHR, avgHRV) = try await queryHeartMetrics(from: bedtime, to: wakeTime)

        // Query respiratory rate
        let respRate = try await queryRespiratoryRate(from: bedtime, to: wakeTime)

        return Self.sleepEntry(from: samples, for: date, owner: goals.userId,
            heartRate: (avgHR, minHR, avgHRV), respiratoryRate: respRate)
    }

    static func sleepEntry(from samples: [HKCategorySample], for date: Date, owner: UUID,
                           heartRate: (Int?, Int?, Double?) = (nil, nil, nil),
                           respiratoryRate: Double? = nil) -> SleepEntry? {
        guard let bedtime = samples.map(\.startDate).min(),
              let wakeTime = samples.map(\.endDate).max() else { return nil }
        let durations = sleepDurations(samples)
        let timeInBed = Int(wakeTime.timeIntervalSince(bedtime) / 60)
        let timeAsleep = Int(durations.asleep / 60)
        guard timeAsleep > 0, timeInBed >= 60, timeInBed <= 1440,
              wakeTime.timeIntervalSince(bedtime) <= 24 * 3600,
              timeAsleep <= timeInBed else { return nil }
        let efficiency = Double(timeAsleep) / Double(timeInBed) * 100

        // Determine source (Apple Watch vs iPhone)
        let source: SleepSource = samples.first?.sourceRevision.source.bundleIdentifier.contains("watch") == true
            ? .appleWatch
            : .healthkit

        // Create sleep entry
        let entry = SleepEntry(
            id: UUID(),
            userId: owner,
            date: date,
            source: source,
            bedtime: bedtime,
            wakeTime: wakeTime,
            timeInBedMinutes: timeInBed,
            timeAsleepMinutes: timeAsleep,
            deepSleepMinutes: durations.hasCompleteStages ? Int(durations.deep / 60) : nil,
            remSleepMinutes: durations.hasCompleteStages ? Int(durations.rem / 60) : nil,
            lightSleepMinutes: durations.hasCompleteStages ? Int(durations.core / 60) : nil,
            awakeMinutes: durations.hasAwakeData ? Int(durations.awake / 60) : nil,
            sleepEfficiency: efficiency,
            heartRateAvg: heartRate.0,
            heartRateMin: heartRate.1,
            hrvAvg: heartRate.2,
            respiratoryRate: respiratoryRate,
            userRating: nil,
            dreamNotes: nil,
            notes: nil,
            sleepScore: nil, // Will be calculated by service
            scoreBreakdown: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        return entry
    }

    /// Query heart rate metrics during sleep
    private func queryHeartMetrics(from start: Date, to end: Date) async throws -> (avg: Int?, min: Int?, hrv: Double?) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return (nil, nil, nil)
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: hrType, predicate: predicate)],
            sortDescriptors: []
        )

        let samples = try await descriptor.result(for: healthStore)

        guard !samples.isEmpty else { return (nil, nil, nil) }

        let hrValues = samples.map { $0.quantity.doubleValue(for: HKUnit(from: "count/min")) }

        let avgHR = Int(hrValues.reduce(0, +) / Double(hrValues.count))
        let minHR = Int(hrValues.min() ?? 0)

        // Query HRV
        let avgHRV = try await queryHRV(from: start, to: end)

        return (avgHR, minHR, avgHRV)
    }

    /// Query heart rate variability
    private func queryHRV(from start: Date, to end: Date) async throws -> Double? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: hrvType, predicate: predicate)],
            sortDescriptors: []
        )

        let samples = try await descriptor.result(for: healthStore)

        guard !samples.isEmpty else { return nil }

        let hrvValues = samples.map { $0.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)) }

        return hrvValues.reduce(0, +) / Double(hrvValues.count)
    }

    /// Query respiratory rate during sleep
    private func queryRespiratoryRate(from start: Date, to end: Date) async throws -> Double? {
        guard let respType = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: respType, predicate: predicate)],
            sortDescriptors: []
        )

        let samples = try await descriptor.result(for: healthStore)

        guard !samples.isEmpty else { return nil }

        let respValues = samples.map { $0.quantity.doubleValue(for: HKUnit(from: "count/min")) }

        return respValues.reduce(0, +) / Double(respValues.count)
    }

    // MARK: - Background Sync

    /// Enable background observer for new sleep data
    func enableBackgroundSync() {
        guard isAuthorized else { return }

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return
        }

        let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { [weak self] _, _, error in
            if let error = error {
                print("Background sleep sync error: \(error)")
                return
            }

            Task { @MainActor [weak self] in
                do {
                    _ = try await self?.syncRecentSleep()
                } catch {
                    print("Failed to sync sleep in background: \(error)")
                }
            }
        }

        healthStore.execute(query)
    }
}

// MARK: - Errors

enum SleepHealthKitError: Error, LocalizedError {
    case healthKitNotAvailable
    case notAuthorized
    case invalidDataType
    case syncFailed

    var errorDescription: String? {
        switch self {
        case .healthKitNotAvailable:
            return "Health data is not available on this device."
        case .notAuthorized:
            return "Please enable Health app access in Settings."
        case .invalidDataType:
            return "Invalid HealthKit data type."
        case .syncFailed:
            return "Failed to sync sleep data. Please try again."
        }
    }
}
