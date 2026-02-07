// HeartRateStreamer.swift
// MindFriendWatch
// Real-time heart rate streaming from Apple Watch to iPhone

import Foundation
import HealthKit
import WatchConnectivity

/// Service for streaming real-time heart rate data from Apple Watch
final class HeartRateStreamer: NSObject, ObservableObject {
    // MARK: - Published State

    @Published var currentHeartRate: Double?
    @Published var isStreaming = false
    @Published var error: String?

    // MARK: - Private Properties

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var heartRateQuery: HKAnchoredObjectQuery?

    // Streaming configuration
    private let streamingInterval: TimeInterval = 5.0 // seconds — 5s balances biofeedback responsiveness with data minimization
    private var lastSentTime: Date = .distantPast
    private let throttleLock = NSLock()

    // Cached HealthKit types (avoid repeated allocation on hot path)
    private static let heartRateQuantityType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private static let heartRateUnit = HKUnit.count().unitDivided(by: .minute())

    // MARK: - Singleton

    static let shared = HeartRateStreamer()

    override private init() {
        super.init()
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HeartRateStreamerError.healthKitUnavailable
        }

        let workoutType = HKWorkoutType.workoutType()

        let readTypes: Set<HKObjectType> = [Self.heartRateQuantityType]
        let shareTypes: Set<HKSampleType> = [workoutType]

        try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    // MARK: - Streaming Control

    func startStreaming() async throws {
        // Guard against double-start race condition
        guard !isStreaming, workoutSession == nil else { return }

        // Check existing authorization status first
        // Only check workout write status since HealthKit does not expose read authorization status for privacy.
        let workoutType = HKWorkoutType.workoutType()
        let workoutStatus = healthStore.authorizationStatus(for: workoutType)
        if workoutStatus == .notDetermined {
            try await requestAuthorization()
        } else if workoutStatus == .sharingDenied {
            throw HeartRateStreamerError.authorizationDenied
        }

        // Configure workout session for continuous heart rate
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .mindAndBody
        configuration.locationType = .indoor

        do {
            workoutSession = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
            builder = workoutSession?.associatedWorkoutBuilder()

            workoutSession?.delegate = self
            builder?.delegate = self

            builder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            // Start the session
            let startDate = Date()
            workoutSession?.startActivity(with: startDate)
            try await builder?.beginCollection(at: startDate)

            // Start heart rate query
            startHeartRateQuery()

            await MainActor.run {
                self.isStreaming = true
                self.error = nil
            }

        } catch {
            // Clean up on failure
            workoutSession = nil
            builder = nil
            await MainActor.run {
                self.error = error.localizedDescription
            }
            throw error
        }
    }

    func stopStreaming() {
        // Capture references before nil-ing to avoid race condition
        let currentQuery = heartRateQuery
        let currentBuilder = builder
        let currentSession = workoutSession

        heartRateQuery = nil

        // Nil delegates before releasing to prevent callbacks after cleanup
        currentSession?.delegate = nil
        currentBuilder?.delegate = nil

        workoutSession = nil
        builder = nil

        // Stop query
        if let query = currentQuery {
            healthStore.stop(query)
        }

        // End session asynchronously using captured references
        Task {
            try? await currentBuilder?.endCollection(at: Date())
            currentSession?.end()
        }

        // Reset throttle state
        throttleLock.lock()
        lastSentTime = .distantPast
        throttleLock.unlock()

        Task { @MainActor in
            self.isStreaming = false
            self.currentHeartRate = nil
        }
    }

    // MARK: - Heart Rate Query

    private func startHeartRateQuery() {
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-60),
            end: nil,
            options: .strictStartDate
        )

        let query = HKAnchoredObjectQuery(
            type: Self.heartRateQuantityType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, error in
            if let error = error {
                print("[HeartRateStreamer] Query error: \(error)")
                return
            }
            self?.processHeartRateSamples(samples as? [HKQuantitySample])
        }

        query.updateHandler = { [weak self] _, samples, _, _, error in
            if let error = error {
                print("[HeartRateStreamer] Update error: \(error)")
                return
            }
            self?.processHeartRateSamples(samples as? [HKQuantitySample])
        }

        healthStore.execute(query)
        heartRateQuery = query
    }

    private func processHeartRateSamples(_ samples: [HKQuantitySample]?) {
        guard let samples = samples, !samples.isEmpty else { return }

        // Get the most recent sample (O(n) vs O(n log n) sort, zero allocation)
        guard let latestSample = samples.max(by: { $0.endDate < $1.endDate }) else { return }

        let bpm = latestSample.quantity.doubleValue(for: Self.heartRateUnit)

        // Validate heart rate is in physiological range
        guard bpm > 20 && bpm < 300 else { return }

        // Update local state
        Task { @MainActor in
            self.currentHeartRate = bpm
        }

        // Send to iPhone (throttled with lock for thread safety)
        throttleLock.lock()
        let now = Date()
        let shouldSend = now.timeIntervalSince(lastSentTime) >= streamingInterval
        if shouldSend {
            lastSentTime = now
        }
        throttleLock.unlock()

        if shouldSend {
            sendHeartRateToPhone(bpm: bpm, timestamp: latestSample.endDate)
        }
    }

    // MARK: - Phone Communication

    private func sendHeartRateToPhone(bpm: Double, timestamp: Date) {
        guard WCSession.isSupported(), WCSession.default.isReachable else { return }

        let message: [String: Any] = [
            "actionType": "heartRateUpdate",
            "heartRate": bpm,
            "timestamp": timestamp.timeIntervalSince1970
        ]

        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("[HeartRateStreamer] Failed to send heart rate: \(error)")
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension HeartRateStreamer: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        print("[HeartRateStreamer] Session state: \(fromState.rawValue) -> \(toState.rawValue)")

        if toState == .ended {
            Task { @MainActor in
                self.isStreaming = false
            }
        }
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        print("[HeartRateStreamer] Session error: \(error)")

        Task { @MainActor in
            self.error = error.localizedDescription
            self.isStreaming = false
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension HeartRateStreamer: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        // Heart rate updates come through the anchored query
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events if needed
    }
}

// MARK: - Error Types

enum HeartRateStreamerError: Error, LocalizedError {
    case healthKitUnavailable
    case authorizationDenied
    case sessionFailed

    var errorDescription: String? {
        switch self {
        case .healthKitUnavailable:
            return "HealthKit is not available on this device"
        case .authorizationDenied:
            return "Health data access was denied"
        case .sessionFailed:
            return "Failed to start workout session"
        }
    }
}
