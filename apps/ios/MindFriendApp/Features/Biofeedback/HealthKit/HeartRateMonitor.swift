// HeartRateMonitor.swift
// MindFriendApp
// Real-time heart rate monitoring using HealthKit

import Foundation
import HealthKit
import Combine
import WatchConnectivity

@MainActor
final class HeartRateMonitor: ObservableObject, HeartRateMonitoring {
    // MARK: - Constants

    private enum Constants {
        /// Maximum readings to keep for trend calculation
        static let maxReadingsForTrend = 10
        /// Time window for heart rate query (5 minutes in seconds)
        static let queryTimeWindowSeconds: TimeInterval = -300
        /// Minimum readings required for trend calculation
        static let minimumReadingsForTrend = 3
        /// Slope threshold for increasing trend (BPM per reading)
        static let increasingTrendThreshold: Double = 1.0
        /// Slope threshold for decreasing trend (BPM per reading)
        static let decreasingTrendThreshold: Double = -1.0
        /// Minimum valid heart rate (BPM)
        static let minValidHeartRate: Double = 30.0
        /// Maximum valid heart rate (BPM)
        static let maxValidHeartRate: Double = 220.0
        /// Maximum retry attempts for HealthKit queries
        static let maxRetryAttempts = 3
        /// Base delay for exponential backoff (seconds)
        static let retryBaseDelaySeconds: UInt64 = 1
    }

    // MARK: - Published State

    @Published private(set) var currentHeartRate: Double?
    @Published private(set) var heartRateTrend: Trend = .stable
    @Published private(set) var isMonitoring = false
    @Published private(set) var isAuthorized = false
    @Published private(set) var error: BiofeedbackError?

    // MARK: - Private Properties

    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var recentReadings: [Double] = []

    // Workout session for continuous monitoring (iOS 26+)
    // Note: HKWorkoutSession/HKLiveWorkoutBuilder require iOS 26.0+ on iPhone
    // Using Any? for type erasure since stored properties can't use @available
    private var _workoutSession: Any?
    private var _builder: Any?

    // Callback for new readings
    var onHeartRateUpdate: ((Double, Date) -> Void)?

    // MARK: - Types

    enum Trend: String {
        case increasing
        case decreasing
        case stable

        var icon: String {
            switch self {
            case .increasing: return "arrow.up"
            case .decreasing: return "arrow.down"
            case .stable: return "minus"
            }
        }

        var color: String {
            switch self {
            case .increasing: return "orange"
            case .decreasing: return "green"
            case .stable: return "blue"
            }
        }
    }

    // MARK: - Authorization

    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isHealthKitAvailable else {
            throw BiofeedbackError.healthKitUnavailable
        }

        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let workoutType = HKWorkoutType.workoutType()

        let readTypes: Set<HKObjectType> = [heartRateType, hrvType]
        let shareTypes: Set<HKSampleType> = [workoutType]

        try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)

        let hrAuthStatus = healthStore.authorizationStatus(for: heartRateType)
        isAuthorized = hrAuthStatus == .sharingAuthorized || hrAuthStatus == .notDetermined

        if !isAuthorized {
            throw BiofeedbackError.authorizationDenied
        }
    }

    // MARK: - Watch Connectivity Check

    var isWatchConnected: Bool {
        #if os(iOS)
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.isPaired && session.isWatchAppInstalled && session.isReachable
        #else
        return true
        #endif
    }

    // MARK: - Monitoring

    func startMonitoring() async throws {
        guard isHealthKitAvailable else {
            throw BiofeedbackError.healthKitUnavailable
        }

        // Check Watch connectivity for real-time heart rate
        #if os(iOS)
        if !isWatchConnected {
            throw BiofeedbackError.watchNotConnected
        }
        #endif

        if !isAuthorized {
            try await requestAuthorization()
        }

        // On iOS 26+, use workout session for better continuous monitoring
        // On older iOS versions, use anchored query only
        if #available(iOS 26.0, *) {
            try await startWorkoutSession()
        }

        startHeartRateQuery()
        isMonitoring = true
        error = nil
    }

    @available(iOS 26.0, *)
    private func startWorkoutSession() async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .mindAndBody
        configuration.locationType = .indoor

        do {
            let workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            _workoutSession = workoutSession
            let builder = workoutSession.associatedWorkoutBuilder()
            _builder = builder

            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            workoutSession.startActivity(with: Date())
            try await builder.beginCollection(at: Date())
        } catch {
            self.error = .healthKitUnavailable
            throw error
        }
    }

    func stopMonitoring() {
        if let query = heartRateQuery {
            healthStore.stop(query)
        }
        heartRateQuery = nil
        onHeartRateUpdate = nil  // Clear callback to prevent memory leaks

        if #available(iOS 26.0, *) {
            stopWorkoutSession()
        }

        isMonitoring = false
        recentReadings.removeAll()
        currentHeartRate = nil
        heartRateTrend = .stable
    }

    @available(iOS 26.0, *)
    private func stopWorkoutSession() {
        let builder = _builder as? HKLiveWorkoutBuilder
        let workoutSession = _workoutSession as? HKWorkoutSession

        // Clear references first to prevent retention during async task
        _workoutSession = nil
        _builder = nil

        // Use detached task with captured local references to avoid retention cycle
        Task.detached { [builder, workoutSession] in
            do {
                try await builder?.endCollection(at: Date())
            } catch {
                // Log error code only - no PHI in error description
                print("Failed to end workout collection: WK-END-001")
            }
            workoutSession?.end()
        }
    }

    // MARK: - Heart Rate Query

    private func startHeartRateQuery() {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!

        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(Constants.queryTimeWindowSeconds),
            end: nil,
            options: .strictStartDate
        )

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, error in
            if error != nil {
                // Don't log error details - may contain PHI context
                print("Heart rate query failed")
                return
            }
            self?.processHeartRateSamples(samples as? [HKQuantitySample])
        }

        query.updateHandler = { [weak self] _, samples, _, _, error in
            if error != nil {
                // Don't log error details - may contain PHI context
                print("Heart rate update failed")
                return
            }
            self?.processHeartRateSamples(samples as? [HKQuantitySample])
        }

        healthStore.execute(query)
        heartRateQuery = query
    }

    private nonisolated func processHeartRateSamples(_ samples: [HKQuantitySample]?) {
        guard let samples = samples, !samples.isEmpty else { return }

        // Get the most recent sample
        let sortedSamples = samples.sorted { $0.endDate > $1.endDate }
        guard let latestSample = sortedSamples.first else { return }

        let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
        let bpm = latestSample.quantity.doubleValue(for: heartRateUnit)
        let endDate = latestSample.endDate

        // Validate heart rate is within physiological range
        guard bpm >= Constants.minValidHeartRate, bpm <= Constants.maxValidHeartRate else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            // Check isMonitoring to prevent race condition with stopMonitoring
            guard self.isMonitoring else { return }

            self.currentHeartRate = bpm
            self.updateTrend(with: bpm)
            self.onHeartRateUpdate?(bpm, endDate)
        }
    }

    private func updateTrend(with newReading: Double) {
        recentReadings.append(newReading)
        if recentReadings.count > Constants.maxReadingsForTrend {
            recentReadings.removeFirst()
        }

        guard recentReadings.count >= Constants.minimumReadingsForTrend else {
            heartRateTrend = .stable
            return
        }

        // Calculate trend using simple linear regression
        let n = Double(recentReadings.count)
        let indices = (0..<recentReadings.count).map { Double($0) }
        let sumX = indices.reduce(0, +)
        let sumY = recentReadings.reduce(0, +)
        let sumXY = zip(indices, recentReadings).map { $0 * $1 }.reduce(0, +)
        let sumX2 = indices.map { $0 * $0 }.reduce(0, +)

        let denominator = n * sumX2 - sumX * sumX
        guard denominator != 0 else {
            heartRateTrend = .stable
            return
        }

        let slope = (n * sumXY - sumX * sumY) / denominator

        if slope > Constants.increasingTrendThreshold {
            heartRateTrend = .increasing
        } else if slope < Constants.decreasingTrendThreshold {
            heartRateTrend = .decreasing
        } else {
            heartRateTrend = .stable
        }
    }

    // MARK: - Historical Data

    func fetchRecentHeartRateData(hours: Int = 24) async throws -> [HKQuantitySample] {
        guard isHealthKitAvailable else {
            throw BiofeedbackError.healthKitUnavailable
        }

        var lastError: BiofeedbackError = .fetchFailed("HK-HR-001")

        for attempt in 1...Constants.maxRetryAttempts {
            // Check for task cancellation before each attempt
            try Task.checkCancellation()

            do {
                return try await performHeartRateFetch(hours: hours)
            } catch {
                lastError = error as? BiofeedbackError ?? .fetchFailed("HK-HR-001")

                // Don't retry on last attempt
                if attempt < Constants.maxRetryAttempts {
                    // Exponential backoff: 1s, 2s, 4s
                    let delay = Constants.retryBaseDelaySeconds * UInt64(1 << (attempt - 1))
                    try await Task.sleep(nanoseconds: delay * 1_000_000_000)
                    try Task.checkCancellation()
                }
            }
        }

        throw lastError
    }

    private func performHeartRateFetch(hours: Int) async throws -> [HKQuantitySample] {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let startDate = Calendar.current.date(byAdding: .hour, value: -hours, to: Date())!

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if error != nil {
                    // Wrap HealthKit error to prevent PHI leak from error description
                    continuation.resume(throwing: BiofeedbackError.fetchFailed("HK-HR-001"))
                    return
                }

                let quantitySamples = (samples as? [HKQuantitySample]) ?? []
                continuation.resume(returning: quantitySamples)
            }

            self.healthStore.execute(query)
        }
    }

    func fetchHRVData(days: Int = 7) async throws -> [HKQuantitySample] {
        guard isHealthKitAvailable else {
            throw BiofeedbackError.healthKitUnavailable
        }

        var lastError: BiofeedbackError = .fetchFailed("HK-HRV-001")

        for attempt in 1...Constants.maxRetryAttempts {
            // Check for task cancellation before each attempt
            try Task.checkCancellation()

            do {
                return try await performHRVFetch(days: days)
            } catch {
                lastError = error as? BiofeedbackError ?? .fetchFailed("HK-HRV-001")

                // Don't retry on last attempt
                if attempt < Constants.maxRetryAttempts {
                    // Exponential backoff: 1s, 2s, 4s
                    let delay = Constants.retryBaseDelaySeconds * UInt64(1 << (attempt - 1))
                    try await Task.sleep(nanoseconds: delay * 1_000_000_000)
                    try Task.checkCancellation()
                }
            }
        }

        throw lastError
    }

    private func performHRVFetch(days: Int) async throws -> [HKQuantitySample] {
        let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if error != nil {
                    // Wrap HealthKit error to prevent PHI leak from error description
                    continuation.resume(throwing: BiofeedbackError.fetchFailed("HK-HRV-001"))
                    return
                }

                let quantitySamples = (samples as? [HKQuantitySample]) ?? []
                continuation.resume(returning: quantitySamples)
            }

            self.healthStore.execute(query)
        }
    }

    // MARK: - Data Conversion

    nonisolated func convertToStorageSamples(
        heartRateSamples: [HKQuantitySample],
        userId: UUID
    ) -> [HealthKitHeartRateSample] {
        let heartRateUnit = HKUnit.count().unitDivided(by: .minute())

        return heartRateSamples.map { sample in
            let context = determineHeartRateContext(for: sample)
            let sourceDevice = sample.sourceRevision.source.name

            return HealthKitHeartRateSample(
                userId: userId,
                value: sample.quantity.doubleValue(for: heartRateUnit),
                timestamp: sample.endDate,
                context: context,
                sourceDevice: sourceDevice
            )
        }
    }

    nonisolated func convertToStorageSamples(
        hrvSamples: [HKQuantitySample],
        userId: UUID
    ) -> [HealthKitHRVSample] {
        let msUnit = HKUnit.secondUnit(with: .milli)

        return hrvSamples.map { sample in
            let sourceDevice = sample.sourceRevision.source.name

            return HealthKitHRVSample(
                userId: userId,
                value: sample.quantity.doubleValue(for: msUnit),
                timestamp: sample.endDate,
                measurementType: .sdnn,
                sourceDevice: sourceDevice
            )
        }
    }

    private nonisolated func determineHeartRateContext(for sample: HKQuantitySample) -> HeartRateContext {
        // Check metadata for context hints
        if let metadata = sample.metadata {
            if let motionContext = metadata[HKMetadataKeyHeartRateMotionContext] as? Int {
                switch motionContext {
                case 0: return .unknown
                case 1: return .resting
                case 2: return .active
                default: return .unknown
                }
            }
        }

        // Use time of day as fallback
        let hour = Calendar.current.component(.hour, from: sample.endDate)
        if hour >= 23 || hour < 6 {
            return .sleep
        }

        return .unknown
    }
}
