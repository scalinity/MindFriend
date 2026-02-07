// BiofeedbackService.swift
// MindFriendApp
// Service for managing biofeedback sessions and data

import Foundation
import Combine
import Supabase

// MARK: - Request/Response Types for Supabase

private struct NewSessionRequest: Codable {
    let userId: String
    let exerciseSessionId: String?
    let adaptationMode: String
    let wasExtended: Bool
    let extensionSeconds: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case exerciseSessionId = "exercise_session_id"
        case adaptationMode = "adaptation_mode"
        case wasExtended = "was_extended"
        case extensionSeconds = "extension_seconds"
    }
}

private struct SessionUpdateRequest: Codable {
    let completedAt: String?
    let durationSeconds: Int?
    let wasExtended: Bool?
    let extensionSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case completedAt = "completed_at"
        case durationSeconds = "duration_seconds"
        case wasExtended = "was_extended"
        case extensionSeconds = "extension_seconds"
    }
}

private struct ReadingInsertRequest: Codable {
    let sessionId: String
    let heartRate: Double
    let hrvSdnn: Double?
    let hrvRmssd: Double?
    let relativeStressLevel: Double?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case heartRate = "heart_rate"
        case hrvSdnn = "hrv_sdnn"
        case hrvRmssd = "hrv_rmssd"
        case relativeStressLevel = "relative_stress_level"
    }
}

private struct HeartRateInsertRequest: Codable {
    let userId: String
    let value: Double
    let timestamp: String
    let context: String
    let sourceDevice: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case value, timestamp, context
        case sourceDevice = "source_device"
    }
}

private struct HRVInsertRequest: Codable {
    let userId: String
    let value: Double
    let timestamp: String
    let measurementType: String
    let sourceDevice: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case value, timestamp
        case measurementType = "measurement_type"
        case sourceDevice = "source_device"
    }
}

@MainActor
final class BiofeedbackService: ObservableObject, BiofeedbackServicing {
    // MARK: - Constants

    private enum Constants {
        static let maxRetryAttempts = 3
        static let retryDelayBaseSeconds: UInt64 = 1_000_000_000  // 1 second in nanoseconds
        static let maxHealthKitBatchSize = 1000  // Prevent unbounded memory growth
        /// Minimum valid heart rate (BPM) per physiological spec
        static let minHeartRate: Double = 30.0
        /// Maximum valid heart rate (BPM) per physiological spec
        static let maxHeartRate: Double = 220.0
        /// Minimum valid HRV (ms)
        static let minHRV: Double = 5.0
        /// Maximum valid HRV (ms)
        static let maxHRV: Double = 250.0

        // Relative stress level mappings (0.0 = completely relaxed, 1.0 = maximum stress)
        enum RelativeStressMapping {
            static let relaxed: Double = 0.1
            static let calm: Double = 0.3
            static let moderate: Double = 0.5
            static let elevated: Double = 0.7
            static let high: Double = 0.9
            static let unknown: Double = 0.5  // Default fallback
        }
    }

    // MARK: - Cached Formatters

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    // MARK: - Published State

    @Published private(set) var currentSession: BiofeedbackSession?
    @Published private(set) var baseline: BiofeedbackBaseline?
    @Published private(set) var isLoading = false
    @Published private(set) var error: BiofeedbackError?

    // MARK: - Dependencies

    private let userId: UUID

    // MARK: - Initialization

    init(userId: UUID) {
        self.userId = userId
    }

    // MARK: - Retry Helper

    private func withRetry<T>(
        maxAttempts: Int = Constants.maxRetryAttempts,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            // Check for task cancellation before each attempt
            try Task.checkCancellation()

            do {
                return try await operation()
            } catch {
                lastError = error

                // Don't retry on auth errors or not found
                if case BiofeedbackError.sessionNotFound = error { throw error }
                if case BiofeedbackError.summaryNotFound = error { throw error }
                if case BiofeedbackError.authorizationDenied = error { throw error }

                // Check for network-related errors that are retryable
                let nsError = error as NSError
                let isRetryable = nsError.domain == NSURLErrorDomain ||
                    nsError.code == NSURLErrorTimedOut ||
                    nsError.code == NSURLErrorNetworkConnectionLost

                guard isRetryable, attempt < maxAttempts else {
                    throw error
                }

                // Exponential backoff with cancellation check (1s, 2s, 4s, ...)
                let delay = Constants.retryDelayBaseSeconds * UInt64(1 << (attempt - 1))
                try await Task.sleep(nanoseconds: delay)
                try Task.checkCancellation()
            }
        }

        throw lastError ?? BiofeedbackError.fetchFailed("Unknown error after retries")
    }

    // MARK: - Baseline Management

    func fetchBaseline() async {
        isLoading = true
        error = nil

        do {
            let baselines: [BiofeedbackBaseline] = try await withRetry {
                try await supabase
                    .from("biometric_baselines")
                    .select()
                    .eq("user_id", value: self.userId.uuidString)
                    .execute()
                    .value
            }

            baseline = baselines.first
        } catch {
            // Use safe error code without PHI
            self.error = .fetchFailed("BL-001")
            print("Failed to fetch baseline")
        }

        isLoading = false
    }

    func calculateBaseline(lookbackDays: Int = 14) async throws -> BaselineCalculationResponse {
        isLoading = true
        error = nil

        defer { isLoading = false }

        do {
            let response: BaselineCalculationResponse = try await withRetry {
                try await supabase.functions
                    .invoke(
                        "calculate-baseline",
                        options: .init(body: ["lookback_days": lookbackDays])
                    )
            }

            // Refresh local baseline
            await fetchBaseline()

            return response
        } catch {
            // Use safe error code without PHI
            self.error = .baselineCalculationFailed("BL-002")
            print("Failed to calculate baseline")
            throw BiofeedbackError.baselineCalculationFailed("BL-002")
        }
    }

    // MARK: - Session Management

    func startSession(
        exerciseSessionId: UUID? = nil,
        adaptationMode: AdaptationMode = .auto,
        wasExtended: Bool = false,
        extensionSeconds: Int = 0
    ) async throws -> BiofeedbackSession {
        isLoading = true
        error = nil

        defer { isLoading = false }

        let newSession = NewSessionRequest(
            userId: userId.uuidString,
            exerciseSessionId: exerciseSessionId?.uuidString,
            adaptationMode: adaptationMode.rawValue,
            wasExtended: wasExtended,
            extensionSeconds: extensionSeconds
        )

        do {
            let sessions: [BiofeedbackSession] = try await withRetry {
                try await supabase
                    .from("biofeedback_sessions")
                    .insert(newSession)
                    .select()
                    .execute()
                    .value
            }

            guard let session = sessions.first else {
                throw BiofeedbackError.sessionCreationFailed("SS-001")
            }

            currentSession = session
            return session
        } catch let error as BiofeedbackError {
            self.error = error
            throw error
        } catch {
            // Use safe error code without PHI
            self.error = .sessionCreationFailed("SS-002")
            print("Failed to create session")
            throw BiofeedbackError.sessionCreationFailed("SS-002")
        }
    }

    func completeSession(sessionId: UUID) async throws -> BiofeedbackSession {
        isLoading = true
        error = nil

        defer { isLoading = false }

        let now = Date()
        let startedAt = currentSession?.startedAt ?? now
        let duration = Int(now.timeIntervalSince(startedAt))

        let updateRequest = SessionUpdateRequest(
            completedAt: Self.iso8601Formatter.string(from: now),
            durationSeconds: duration,
            wasExtended: nil,
            extensionSeconds: nil
        )

        do {
            let sessions: [BiofeedbackSession] = try await withRetry {
                try await supabase
                    .from("biofeedback_sessions")
                    .update(updateRequest)
                    .eq("id", value: sessionId.uuidString)
                    .select()
                    .execute()
                    .value
            }

            guard let session = sessions.first else {
                throw BiofeedbackError.sessionNotFound
            }

            currentSession = nil
            return session
        } catch let error as BiofeedbackError {
            self.error = error
            throw error
        } catch {
            // Use safe error code without PHI
            self.error = .sessionCompletionFailed("SC-001")
            print("Failed to complete session")
            throw BiofeedbackError.sessionCompletionFailed("SC-001")
        }
    }

    func extendSession(sessionId: UUID, additionalSeconds: Int) async throws {
        do {
            let currentExtension = currentSession?.extensionSeconds ?? 0
            let updateRequest = SessionUpdateRequest(
                completedAt: nil,
                durationSeconds: nil,
                wasExtended: true,
                extensionSeconds: currentExtension + additionalSeconds
            )

            _ = try await withRetry {
                try await supabase
                    .from("biofeedback_sessions")
                    .update(updateRequest)
                    .eq("id", value: sessionId.uuidString)
                    .execute()
            }

            // Refresh current session
            if var session = currentSession {
                session.wasExtended = true
                session.extensionSeconds = currentExtension + additionalSeconds
                currentSession = session
            }
        } catch {
            // Use safe error code without PHI
            self.error = .sessionUpdateFailed("SE-001")
            print("Failed to extend session")
            throw BiofeedbackError.sessionUpdateFailed("SE-001")
        }
    }

    // MARK: - Reading Management

    func recordReading(
        sessionId: UUID,
        heartRate: Double,
        hrvSdnn: Double? = nil,
        hrvRmssd: Double? = nil
    ) async throws {
        // Input validation - reject physiologically implausible values
        guard heartRate >= Constants.minHeartRate,
              heartRate <= Constants.maxHeartRate else {
            print("Invalid heart rate value rejected: out of bounds")
            return  // Silently reject invalid readings
        }

        // Validate HRV values if provided
        if let sdnn = hrvSdnn {
            guard sdnn >= Constants.minHRV, sdnn <= Constants.maxHRV else {
                print("Invalid HRV SDNN value rejected: out of bounds")
                return
            }
        }

        if let rmssd = hrvRmssd {
            guard rmssd >= Constants.minHRV, rmssd <= Constants.maxHRV else {
                print("Invalid HRV RMSSD value rejected: out of bounds")
                return
            }
        }

        var relativeStress: Double?

        // Calculate stress level if baseline available
        if let baseline = baseline {
            let stressLevel = baseline.stressLevel(forHeartRate: heartRate)
            switch stressLevel {
            case .relaxed: relativeStress = Constants.RelativeStressMapping.relaxed
            case .calm: relativeStress = Constants.RelativeStressMapping.calm
            case .moderate: relativeStress = Constants.RelativeStressMapping.moderate
            case .elevated: relativeStress = Constants.RelativeStressMapping.elevated
            case .high: relativeStress = Constants.RelativeStressMapping.high
            case .unknown: relativeStress = Constants.RelativeStressMapping.unknown
            }
        }

        let reading = ReadingInsertRequest(
            sessionId: sessionId.uuidString,
            heartRate: heartRate,
            hrvSdnn: hrvSdnn,
            hrvRmssd: hrvRmssd,
            relativeStressLevel: relativeStress
        )

        do {
            try await supabase
                .from("biofeedback_readings")
                .insert(reading)
                .execute()
        } catch {
            // Don't throw for reading failures - they're not critical
            // Use safe error code only (no NSError details to minimize info leakage)
            print("Failed to record biofeedback reading: RD-001")
        }
    }

    // MARK: - Real-time Analysis

    func analyzeReading(
        sessionId: UUID,
        heartRate: Double,
        hrvRmssd: Double?,
        elapsedSeconds: Int
    ) async throws -> BiometricAnalysis {
        struct AnalysisRequest: Codable {
            let sessionId: String
            let heartRate: Double
            let hrvRmssd: Double?
            let elapsedSeconds: Int

            enum CodingKeys: String, CodingKey {
                case sessionId = "session_id"
                case heartRate = "heart_rate"
                case hrvRmssd = "hrv_rmssd"
                case elapsedSeconds = "elapsed_seconds"
            }
        }

        let request = AnalysisRequest(
            sessionId: sessionId.uuidString,
            heartRate: heartRate,
            hrvRmssd: hrvRmssd,
            elapsedSeconds: elapsedSeconds
        )

        do {
            let response: BiometricAnalysisResponse = try await withRetry {
                try await supabase.functions
                    .invoke(
                        "biofeedback-analyze",
                        options: .init(body: request)
                    )
            }

            guard let analysis = response.analysis else {
                throw BiofeedbackError.analysisFailedNoData
            }

            return analysis
        } catch let error as BiofeedbackError {
            throw error
        } catch {
            // Use safe error code without PHI
            print("Failed to analyze reading")
            throw BiofeedbackError.analysisFailed("AN-001")
        }
    }

    // MARK: - Summary

    func fetchSummary(sessionId: UUID) async throws -> BiofeedbackSummary {
        do {
            let summaries: [BiofeedbackSummary] = try await withRetry {
                try await supabase
                    .from("biofeedback_summaries")
                    .select()
                    .eq("session_id", value: sessionId.uuidString)
                    .execute()
                    .value
            }

            guard let summary = summaries.first else {
                throw BiofeedbackError.summaryNotFound
            }

            return summary
        } catch let error as BiofeedbackError {
            self.error = error
            throw error
        } catch {
            // Use safe error code without PHI
            self.error = .fetchFailed("SM-001")
            print("Failed to fetch summary")
            throw BiofeedbackError.fetchFailed("SM-001")
        }
    }

    func fetchRecentSessions(limit: Int = 10) async throws -> [BiofeedbackSession] {
        do {
            let sessions: [BiofeedbackSession] = try await withRetry {
                try await supabase
                    .from("biofeedback_sessions")
                    .select()
                    .eq("user_id", value: self.userId.uuidString)
                    .not("completed_at", operator: .is, value: "null")
                    .order("started_at", ascending: false)
                    .limit(limit)
                    .execute()
                    .value
            }

            return sessions
        } catch {
            // Use safe error code without PHI
            self.error = .fetchFailed("RS-001")
            print("Failed to fetch recent sessions")
            throw BiofeedbackError.fetchFailed("RS-001")
        }
    }

    // MARK: - HealthKit Data Sync

    func syncHealthKitHeartRate(samples: [HealthKitHeartRateSample]) async throws {
        guard !samples.isEmpty else { return }

        // Bound the batch size to prevent memory issues
        let boundedSamples = Array(samples.prefix(Constants.maxHealthKitBatchSize))

        let insertData = boundedSamples.map { sample in
            HeartRateInsertRequest(
                userId: sample.userId.uuidString,
                value: sample.value,
                timestamp: Self.iso8601Formatter.string(from: sample.timestamp),
                context: sample.context.rawValue,
                sourceDevice: sample.sourceDevice
            )
        }

        do {
            _ = try await withRetry {
                try await supabase
                    .from("healthkit_heart_rate")
                    .insert(insertData)
                    .execute()
            }
        } catch {
            // Don't log error details as they may contain PHI
            print("Failed to sync heart rate samples")
            throw BiofeedbackError.fetchFailed("HK-001")
        }
    }

    func syncHealthKitHRV(samples: [HealthKitHRVSample]) async throws {
        guard !samples.isEmpty else { return }

        // Bound the batch size to prevent memory issues
        let boundedSamples = Array(samples.prefix(Constants.maxHealthKitBatchSize))

        let insertData = boundedSamples.map { sample in
            HRVInsertRequest(
                userId: sample.userId.uuidString,
                value: sample.value,
                timestamp: Self.iso8601Formatter.string(from: sample.timestamp),
                measurementType: sample.measurementType.rawValue,
                sourceDevice: sample.sourceDevice
            )
        }

        do {
            _ = try await withRetry {
                try await supabase
                    .from("healthkit_hrv")
                    .insert(insertData)
                    .execute()
            }
        } catch {
            // Don't log error details as they may contain PHI
            print("Failed to sync HRV samples")
            throw BiofeedbackError.fetchFailed("HK-002")
        }
    }
}

// MARK: - Biofeedback Error

enum BiofeedbackError: Error, LocalizedError {
    case fetchFailed(String)
    case baselineCalculationFailed(String)
    case sessionCreationFailed(String)
    case sessionNotFound
    case sessionCompletionFailed(String)
    case sessionUpdateFailed(String)
    case analysisFailed(String)
    case analysisFailedNoData
    case summaryNotFound
    case healthKitUnavailable
    case authorizationDenied
    case noHeartRateData
    case watchNotConnected

    /// Error code for logging/debugging (safe, no PHI)
    var errorCode: String {
        switch self {
        case .fetchFailed(let code): return code
        case .baselineCalculationFailed(let code): return code
        case .sessionCreationFailed(let code): return code
        case .sessionNotFound: return "SNF-001"
        case .sessionCompletionFailed(let code): return code
        case .sessionUpdateFailed(let code): return code
        case .analysisFailed(let code): return code
        case .analysisFailedNoData: return "AND-001"
        case .summaryNotFound: return "SMN-001"
        case .healthKitUnavailable: return "HKU-001"
        case .authorizationDenied: return "AUD-001"
        case .noHeartRateData: return "NHR-001"
        case .watchNotConnected: return "WNC-001"
        }
    }

    /// User-facing description (safe, no PHI)
    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Unable to load data. Please try again."
        case .baselineCalculationFailed:
            return "Unable to calculate your baseline. Please try again later."
        case .sessionCreationFailed:
            return "Unable to start session. Please try again."
        case .sessionNotFound:
            return "Session not found."
        case .sessionCompletionFailed:
            return "Unable to save session. Your progress may not be recorded."
        case .sessionUpdateFailed:
            return "Unable to update session."
        case .analysisFailed:
            return "Unable to analyze your biometrics."
        case .analysisFailedNoData:
            return "No analysis data available."
        case .summaryNotFound:
            return "Session summary not available yet."
        case .healthKitUnavailable:
            return "HealthKit is not available on this device."
        case .authorizationDenied:
            return "Please allow access to heart rate data in Settings."
        case .noHeartRateData:
            return "No heart rate data available. Please ensure Apple Watch is worn."
        case .watchNotConnected:
            return "Apple Watch not connected. Please check your connection."
        }
    }
}
