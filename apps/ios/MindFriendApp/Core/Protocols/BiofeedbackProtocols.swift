//
//  BiofeedbackProtocols.swift
//  MindFriendApp
//
//  Protocol abstractions for biofeedback services and heart rate monitoring.
//  Enables dependency injection and testability.
//

import Foundation
import Combine
import HealthKit

// MARK: - Biofeedback Service Protocol

/// Protocol for biofeedback session management and data operations.
/// Provides abstraction for dependency injection and testing.
@MainActor
protocol BiofeedbackServicing: ObservableObject {
    // MARK: - Published State
    var currentSession: BiofeedbackSession? { get }
    var baseline: BiofeedbackBaseline? { get }
    var isLoading: Bool { get }
    var error: BiofeedbackError? { get }

    // MARK: - Baseline Operations
    func fetchBaseline() async
    func calculateBaseline(lookbackDays: Int) async throws -> BaselineCalculationResponse

    // MARK: - Session Management
    func startSession(
        exerciseSessionId: UUID?,
        adaptationMode: AdaptationMode,
        wasExtended: Bool,
        extensionSeconds: Int
    ) async throws -> BiofeedbackSession

    func completeSession(sessionId: UUID) async throws -> BiofeedbackSession
    func extendSession(sessionId: UUID, additionalSeconds: Int) async throws

    // MARK: - Biometric Data
    func recordReading(
        sessionId: UUID,
        heartRate: Double,
        hrvSdnn: Double?,
        hrvRmssd: Double?
    ) async throws

    func analyzeReading(
        sessionId: UUID,
        heartRate: Double,
        hrvRmssd: Double?,
        elapsedSeconds: Int
    ) async throws -> BiometricAnalysis

    // MARK: - Data Retrieval
    func fetchSummary(sessionId: UUID) async throws -> BiofeedbackSummary
    func fetchRecentSessions(limit: Int) async throws -> [BiofeedbackSession]

    // MARK: - HealthKit Sync
    func syncHealthKitHeartRate(samples: [HealthKitHeartRateSample]) async throws
    func syncHealthKitHRV(samples: [HealthKitHRVSample]) async throws
}

// MARK: - Default Parameter Values Extension

extension BiofeedbackServicing {
    func calculateBaseline() async throws -> BaselineCalculationResponse {
        try await calculateBaseline(lookbackDays: 14)
    }

    func fetchRecentSessions() async throws -> [BiofeedbackSession] {
        try await fetchRecentSessions(limit: 10)
    }
}

// MARK: - Heart Rate Monitoring Protocol

/// Protocol for real-time heart rate monitoring via HealthKit.
/// Provides abstraction for dependency injection and testing.
@MainActor
protocol HeartRateMonitoring: ObservableObject {
    // MARK: - Published State
    var currentHeartRate: Double? { get }
    var heartRateTrend: HeartRateMonitor.Trend { get }
    var isMonitoring: Bool { get }
    var isAuthorized: Bool { get }
    var error: BiofeedbackError? { get }

    // MARK: - Availability
    var isHealthKitAvailable: Bool { get }
    var isWatchConnected: Bool { get }

    // MARK: - Callback
    var onHeartRateUpdate: ((Double, Date) -> Void)? { get set }

    // MARK: - Authorization
    func requestAuthorization() async throws

    // MARK: - Monitoring
    func startMonitoring() async throws
    func stopMonitoring()

    // MARK: - Historical Data
    func fetchRecentHeartRateData(hours: Int) async throws -> [HKQuantitySample]
    func fetchHRVData(days: Int) async throws -> [HKQuantitySample]

    // MARK: - Data Conversion
    nonisolated func convertToStorageSamples(
        heartRateSamples: [HKQuantitySample],
        userId: UUID
    ) -> [HealthKitHeartRateSample]

    nonisolated func convertToStorageSamples(
        hrvSamples: [HKQuantitySample],
        userId: UUID
    ) -> [HealthKitHRVSample]
}

// MARK: - Default Parameter Values Extension

extension HeartRateMonitoring {
    func fetchRecentHeartRateData() async throws -> [HKQuantitySample] {
        try await fetchRecentHeartRateData(hours: 24)
    }

    func fetchHRVData() async throws -> [HKQuantitySample] {
        try await fetchHRVData(days: 7)
    }
}

// MARK: - Adaptation Engine Protocol

/// Protocol for biometric-based exercise adaptation calculations.
/// Provides abstraction for dependency injection and testing.
@MainActor
protocol AdaptationEngineProtocol: ObservableObject {
    // MARK: - Published State
    var currentParameters: AdaptationParameters { get }
    var adaptationsApplied: [AdaptationType] { get }
    var currentStressLevel: BiofeedbackStressLevel { get }
    var currentTrend: BiofeedbackTrendDirection { get }

    // MARK: - Processing
    func processReading(_ reading: LiveBiometricData) -> AdaptationResult
    func checkShouldExtend(averageHR: Double, elapsedTime: TimeInterval) -> ExtensionRecommendation
    func reset()
}
