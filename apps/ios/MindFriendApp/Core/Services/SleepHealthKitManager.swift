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

    /// Sync recent sleep data (last 24 hours)
    func syncRecentSleep() async throws -> SleepEntry? {
        // If not authorized yet, request authorization first
        if !isAuthorized {
            try await requestAuthorization()
        }

        isSyncing = true
        defer { isSyncing = false }

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        let entries = try await syncSleepData(from: yesterday)
        lastSyncDate = Date()

        return entries.first
    }

    /// Sync sleep data from a specific start date
    func syncSleepData(from startDate: Date) async throws -> [SleepEntry] {
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
        let sleepSamples = try await querySleepAnalysis(from: startDate)
        print("[SleepHealthKit] Found \(sleepSamples.count) sleep samples from HealthKit")

        if sleepSamples.isEmpty {
            print("[SleepHealthKit] No sleep data found in HealthKit. This could mean:")
            print("  - No sleep data recorded in Health app")
            print("  - User denied HealthKit read access")
            print("  - Running on simulator without mock data")
            return []
        }

        // Group by date (each night is a separate entry)
        let groupedSamples = Dictionary(grouping: sleepSamples) { sample in
            Calendar.current.startOfDay(for: sample.startDate)
        }
        print("[SleepHealthKit] Grouped into \(groupedSamples.count) nights")

        var entries: [SleepEntry] = []

        // Fetch user's sleep goals for score calculation
        print("[SleepHealthKit] Fetching sleep goals...")
        let goals = try await sleepTrackingService.fetchGoals()
        print("[SleepHealthKit] Got goals, processing sleep entries...")

        // Process each night's sleep
        for (date, samples) in groupedSamples {
            guard let entry = try await processSleepSamples(samples, for: date, goals: goals) else {
                print("[SleepHealthKit] Failed to process samples for \(date)")
                continue
            }

            // Check if entry already exists (avoid duplicates)
            do {
                let existing = try await sleepTrackingService.fetchEntries(from: date, to: date)
                if existing.isEmpty {
                    // Create new entry
                    print("[SleepHealthKit] Creating new entry for \(date)...")
                    let created = try await sleepTrackingService.createEntry(entry, goals: goals)
                    entries.append(created)
                    print("[SleepHealthKit] Entry created successfully")
                } else {
                    print("[SleepHealthKit] Entry already exists for \(date), skipping")
                }
            } catch {
                // Failed to check/create, skip this entry
                print("[SleepHealthKit] Failed to create sleep entry for \(date): \(error)")
            }
        }

        lastSyncDate = Date()

        return entries.sorted { $0.date > $1.date }
    }

    /// Query sleep analysis samples from HealthKit
    private func querySleepAnalysis(from startDate: Date) async throws -> [HKCategorySample] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw SleepHealthKitError.invalidDataType
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: .strictStartDate
        )

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )

        return try await descriptor.result(for: healthStore)
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

        // Calculate time in bed (minutes)
        let timeInBed = Int(wakeTime.timeIntervalSince(bedtime) / 60)

        // Calculate sleep stages
        var deepSleep = 0
        var remSleep = 0
        var lightSleep = 0
        var awakeTime = 0

        for sample in samples {
            let duration = Int(sample.endDate.timeIntervalSince(sample.startDate) / 60)

            switch sample.value {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                deepSleep += duration
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                remSleep += duration
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                 HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                lightSleep += duration
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                awakeTime += duration
            default:
                break
            }
        }

        // Total asleep time
        let timeAsleep = deepSleep + remSleep + lightSleep

        // Calculate efficiency
        let efficiency = timeAsleep > 0 ? (Double(timeAsleep) / Double(timeInBed)) * 100 : nil

        // Query heart rate data for this sleep period
        let (avgHR, minHR, avgHRV) = try await queryHeartMetrics(from: bedtime, to: wakeTime)

        // Query respiratory rate
        let respRate = try await queryRespiratoryRate(from: bedtime, to: wakeTime)

        // Determine source (Apple Watch vs iPhone)
        let source: SleepSource = samples.first?.sourceRevision.source.bundleIdentifier.contains("watch") == true
            ? .appleWatch
            : .healthkit

        // Create sleep entry
        let entry = SleepEntry(
            id: UUID(),
            userId: UUID(), // Will be set by service/RLS
            date: date,
            source: source,
            bedtime: bedtime,
            wakeTime: wakeTime,
            timeInBedMinutes: timeInBed,
            timeAsleepMinutes: timeAsleep,
            deepSleepMinutes: deepSleep > 0 ? deepSleep : nil,
            remSleepMinutes: remSleep > 0 ? remSleep : nil,
            lightSleepMinutes: lightSleep > 0 ? lightSleep : nil,
            awakeMinutes: awakeTime > 0 ? awakeTime : nil,
            sleepEfficiency: efficiency,
            heartRateAvg: avgHR,
            heartRateMin: minHR,
            hrvAvg: avgHRV,
            respiratoryRate: respRate,
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
