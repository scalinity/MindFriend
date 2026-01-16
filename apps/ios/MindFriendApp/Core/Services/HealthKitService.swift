import Foundation
import HealthKit
import Supabase
import OSLog

// MARK: - Update Payload Structs

/// Payload for marking items as read
private struct MarkReadPayload: Encodable {
    let isRead: Bool
    let readAt: String

    enum CodingKeys: String, CodingKey {
        case isRead = "is_read"
        case readAt = "read_at"
    }
}

/// Payload for dismissing items
private struct DismissPayload: Encodable {
    let isDismissed: Bool

    enum CodingKeys: String, CodingKey {
        case isDismissed = "is_dismissed"
    }
}

/// Payload for upserting HealthKit connection status
private struct ConnectionStatusPayload: Encodable {
    let userId: String
    let isConnected: Bool
    let authorizedTypes: [String]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case isConnected = "is_connected"
        case authorizedTypes = "authorized_types"
    }
}

/// Service for integrating with Apple HealthKit
/// Handles authorization, data fetching, and syncing biometrics to the backend
@MainActor
final class HealthKitService: ObservableObject {
    private let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "com.mindfriend", category: "HealthKit")

    @Published var isAuthorized = false
    @Published var authorizedTypes: Set<HealthKitDataType> = []
    @Published var lastSyncDate: Date?
    @Published var isSyncing = false
    @Published var syncError: Error?

    // All types we want to read
    private var allReadTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        for dataType in HealthKitDataType.allCases {
            types.formUnion(dataType.healthKitTypes)
        }
        // Additional types
        if let restingHR = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(restingHR)
        }
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.insert(distance)
        }
        if let exerciseTime = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
            types.insert(exerciseTime)
        }
        return types
    }

    // MARK: - Initialization

    init() {
        // Check if we already have authorization on launch
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }

        logger.info("Requesting HealthKit authorization")

        try await healthStore.requestAuthorization(toShare: [], read: allReadTypes)

        // Check which types are actually authorized
        await checkAuthorizationStatus()

        logger.info("HealthKit authorization complete. Authorized: \(self.authorizedTypes.map(\.rawValue).joined(separator: ", "))")
    }

    func checkAuthorizationStatus() async {
        var authorized: Set<HealthKitDataType> = []

        for dataType in HealthKitDataType.allCases {
            let types = dataType.healthKitTypes
            // Note: authorizationStatus only tells us if we asked, not if granted
            // We need to actually try to query to see if we have access
            let allAsked = types.allSatisfy { type in
                let status = healthStore.authorizationStatus(for: type)
                return status == .sharingAuthorized || status == .sharingDenied
            }
            // For read-only access, we treat any status other than notDetermined as "asked"
            // The actual data availability will be determined when we query
            if allAsked {
                authorized.insert(dataType)
            }
        }

        // If we've asked for any types, consider ourselves authorized
        self.isAuthorized = !authorized.isEmpty
        self.authorizedTypes = authorized

        // Update connection status in database
        await updateConnectionStatus()
    }

    private func updateConnectionStatus() async {
        struct HealthKitConnectionUpsert: Encodable {
            let userId: String
            let isConnected: Bool
            let authorizedTypes: [String]

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case isConnected = "is_connected"
                case authorizedTypes = "authorized_types"
            }
        }

        do {
            let session = try await supabase.auth.session
            let authorizedTypeStrings = authorizedTypes.map { $0.rawValue }

            let upsertData = HealthKitConnectionUpsert(
                userId: session.user.id.uuidString,
                isConnected: isAuthorized,
                authorizedTypes: authorizedTypeStrings
            )

            try await supabase
                .from("healthkit_connections")
                .upsert(upsertData, onConflict: "user_id")
                .execute()
        } catch {
            logger.error("Failed to update HealthKit connection status: \(error.localizedDescription)")
        }
    }

    // MARK: - Data Sync

    func syncBiometrics(days: Int = 7) async throws {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        logger.info("Starting biometric sync for \(days) days")

        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else {
            throw HealthKitError.queryFailed(NSError(domain: "HealthKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid date range"]))
        }

        var dailySummaries: [BiometricSyncPayload.DailySummaryPayload] = []
        var workouts: [BiometricSyncPayload.WorkoutPayload] = []

        // Iterate through each day
        var currentDate = startDate
        while currentDate <= endDate {
            let dayStart = calendar.startOfDay(for: currentDate)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: dayStart)

            var summary = BiometricSyncPayload.DailySummaryPayload(date: dateString)

            // Fetch each metric type
            if authorizedTypes.contains(.sleep) {
                let sleepData = try await fetchSleepData(from: dayStart, to: dayEnd)
                summary.sleepDurationMinutes = sleepData.durationMinutes
                summary.sleepQualityScore = sleepData.qualityScore
                summary.sleepStartTime = sleepData.startTime
                summary.sleepEndTime = sleepData.endTime
                summary.timeInBedMinutes = sleepData.timeInBed
            }

            if authorizedTypes.contains(.hrv) {
                let hrvData = try await fetchHRVData(from: dayStart, to: dayEnd)
                summary.hrvAverageMs = hrvData.average
                summary.hrvMinMs = hrvData.min
                summary.hrvMaxMs = hrvData.max

                let restingHR = try await fetchRestingHeartRate(from: dayStart, to: dayEnd)
                summary.restingHeartRate = restingHR
            }

            if authorizedTypes.contains(.steps) {
                summary.stepsCount = try await fetchSteps(from: dayStart, to: dayEnd)
                summary.distanceMeters = try await fetchDistance(from: dayStart, to: dayEnd)
            }

            if authorizedTypes.contains(.activity) {
                summary.activeEnergyKcal = try await fetchActiveEnergy(from: dayStart, to: dayEnd)
                summary.exerciseMinutes = try await fetchExerciseMinutes(from: dayStart, to: dayEnd)
            }

            if authorizedTypes.contains(.mindful) {
                summary.mindfulMinutes = try await fetchMindfulMinutes(from: dayStart, to: dayEnd)
            }

            dailySummaries.append(summary)

            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }

        // Fetch workouts
        if authorizedTypes.contains(.workouts) {
            workouts = try await fetchWorkouts(from: startDate, to: endDate)
        }

        // Send to backend
        let payload = BiometricSyncPayload(
            dailySummaries: dailySummaries,
            workouts: workouts
        )

        try await syncToBackend(payload)
        lastSyncDate = Date()

        logger.info("Biometric sync complete: \(dailySummaries.count) summaries, \(workouts.count) workouts")
    }

    private func syncToBackend(_ payload: BiometricSyncPayload) async throws {
        do {
            try await supabase.functions.invoke(
                "sync-biometrics",
                options: .init(body: payload)
            )
        } catch {
            logger.error("Failed to sync biometrics: \(error.localizedDescription)")
            syncError = error
            throw HealthKitError.syncFailed(error)
        }
    }

    // MARK: - Sleep Data

    private func fetchSleepData(from start: Date, to end: Date) async throws -> (durationMinutes: Int?, qualityScore: Double?, startTime: String?, endTime: String?, timeInBed: Int?) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return (nil, nil, nil, nil, nil)
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKCategorySample] ?? [])
                }
            }
            healthStore.execute(query)
        }

        // Filter for actual sleep (not in bed)
        let sleepSamples = samples.filter { sample in
            if #available(iOS 16.0, *) {
                let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                return value == .asleepCore || value == .asleepDeep || value == .asleepREM || value == .asleepUnspecified
            } else {
                return sample.value == HKCategoryValueSleepAnalysis.asleep.rawValue
            }
        }

        guard !sleepSamples.isEmpty else {
            return (nil, nil, nil, nil, nil)
        }

        // Calculate total sleep duration
        let totalSleep = sleepSamples.reduce(0.0) { sum, sample in
            sum + sample.endDate.timeIntervalSince(sample.startDate)
        }
        let durationMinutes = Int(totalSleep / 60)

        // Get sleep window
        guard let firstSleep = sleepSamples.first,
              let lastSleep = sleepSamples.last else {
            return (durationMinutes, nil, nil, nil, nil)
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let startTime = timeFormatter.string(from: firstSleep.startDate)
        let endTime = timeFormatter.string(from: lastSleep.endDate)

        // Time in bed
        let timeInBed = Int(lastSleep.endDate.timeIntervalSince(firstSleep.startDate) / 60)

        // Quality score (simplified: based on efficiency)
        let efficiency = timeInBed > 0 ? Double(durationMinutes) / Double(timeInBed) : 0
        let qualityScore = min(efficiency, 1.0)

        return (durationMinutes, qualityScore, startTime, endTime, timeInBed)
    }

    // MARK: - HRV Data

    private func fetchHRVData(from start: Date, to end: Date) async throws -> (average: Double?, min: Double?, max: Double?) {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return (nil, nil, nil)
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples = try await queryQuantitySamples(type: hrvType, predicate: predicate)

        guard !samples.isEmpty else {
            return (nil, nil, nil)
        }

        let values = samples.map { $0.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)) }
        let average = values.reduce(0, +) / Double(values.count)
        let minVal = values.min()
        let maxVal = values.max()

        return (average, minVal, maxVal)
    }

    private func fetchRestingHeartRate(from start: Date, to end: Date) async throws -> Int? {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .restingHeartRate) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples = try await queryQuantitySamples(type: hrType, predicate: predicate)

        guard let lastSample = samples.last else { return nil }
        return Int(lastSample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
    }

    // MARK: - Activity Data

    private func fetchSteps(from start: Date, to end: Date) async throws -> Int? {
        guard let stepsType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            return nil
        }

        return try await queryStatistics(type: stepsType, from: start, to: end, unit: .count())
    }

    private func fetchDistance(from start: Date, to end: Date) async throws -> Int? {
        guard let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else {
            return nil
        }

        return try await queryStatistics(type: distanceType, from: start, to: end, unit: .meter())
    }

    private func fetchActiveEnergy(from start: Date, to end: Date) async throws -> Int? {
        guard let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return nil
        }

        return try await queryStatistics(type: energyType, from: start, to: end, unit: .kilocalorie())
    }

    private func fetchExerciseMinutes(from start: Date, to end: Date) async throws -> Int? {
        guard let exerciseType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) else {
            return nil
        }

        return try await queryStatistics(type: exerciseType, from: start, to: end, unit: .minute())
    }

    // MARK: - Mindful Minutes

    private func fetchMindfulMinutes(from start: Date, to end: Date) async throws -> Int? {
        guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
            let query = HKSampleQuery(
                sampleType: mindfulType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKCategorySample] ?? [])
                }
            }
            healthStore.execute(query)
        }

        let totalMinutes = samples.reduce(0) { sum, sample in
            sum + Int(sample.endDate.timeIntervalSince(sample.startDate) / 60)
        }

        return totalMinutes > 0 ? totalMinutes : nil
    }

    // MARK: - Workouts

    private func fetchWorkouts(from start: Date, to end: Date) async throws -> [BiometricSyncPayload.WorkoutPayload] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let workouts = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKWorkout], Error>) in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKWorkout] ?? [])
                }
            }
            healthStore.execute(query)
        }

        let formatter = ISO8601DateFormatter()

        return workouts.map { workout in
            BiometricSyncPayload.WorkoutPayload(
                healthkitUuid: workout.uuid.uuidString,
                workoutType: mapWorkoutType(workout.workoutActivityType),
                startTime: formatter.string(from: workout.startDate),
                endTime: formatter.string(from: workout.endDate),
                durationMinutes: Int(workout.duration / 60),
                activeEnergyKcal: workout.totalEnergyBurned.map { Int($0.doubleValue(for: .kilocalorie())) },
                distanceMeters: workout.totalDistance.map { Int($0.doubleValue(for: .meter())) },
                averageHeartRate: nil // Would need separate query
            )
        }
    }

    // MARK: - Helpers

    private func queryQuantitySamples(type: HKQuantityType, predicate: NSPredicate) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func queryStatistics(type: HKQuantityType, from start: Date, to end: Date, unit: HKUnit) async throws -> Int? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let sum = statistics?.sumQuantity() {
                    continuation.resume(returning: Int(sum.doubleValue(for: unit)))
                } else {
                    continuation.resume(returning: nil)
                }
            }
            healthStore.execute(query)
        }
    }

    private func mapWorkoutType(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .yoga: return "yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "strength"
        case .highIntensityIntervalTraining: return "hiit"
        case .swimming: return "swimming"
        case .hiking: return "hiking"
        case .dance: return "dance"
        case .pilates: return "pilates"
        case .elliptical: return "elliptical"
        case .rowing: return "rowing"
        default: return "other"
        }
    }

    // MARK: - Recent Data (for display)

    /// Get the most recent daily summary for display
    func getTodaySummary() async throws -> BiometricDailySummary? {
        let today = DateFormatter.dateOnly.string(from: Date())

        let response: [BiometricDailySummary] = try await supabase
            .from("biometric_daily_summaries")
            .select()
            .eq("date", value: today)
            .limit(1)
            .execute()
            .value

        return response.first
    }

    /// Get recent daily summaries for trends
    func getRecentSummaries(days: Int = 7) async throws -> [BiometricDailySummary] {
        let formatter = DateFormatter.dateOnly
        let endDate = formatter.string(from: Date())
        guard let startDateObj = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return []
        }
        let startDate = formatter.string(from: startDateObj)

        let response: [BiometricDailySummary] = try await supabase
            .from("biometric_daily_summaries")
            .select()
            .gte("date", value: startDate)
            .lte("date", value: endDate)
            .order("date", ascending: false)
            .execute()
            .value

        return response
    }

    /// Get unread insights
    func getInsights(limit: Int = 10) async throws -> [BiometricInsight] {
        let response: [BiometricInsight] = try await supabase
            .from("biometric_insights")
            .select()
            .eq("is_dismissed", value: false)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return response
    }

    /// Get unread alerts
    func getAlerts(limit: Int = 5) async throws -> [BiometricAlert] {
        let response: [BiometricAlert] = try await supabase
            .from("biometric_alerts")
            .select()
            .eq("is_read", value: false)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return response
    }

    /// Get mood-biometric correlations
    func getCorrelations(periodDays: Int = 30) async throws -> [MoodBiometricCorrelation] {
        let response: [MoodBiometricCorrelation] = try await supabase
            .from("mood_biometric_correlations")
            .select()
            .eq("period_days", value: periodDays)
            .execute()
            .value

        return response.filter { abs($0.correlationCoefficient) > 0.2 }
    }

    /// Mark an insight as read
    func markInsightRead(_ insightId: UUID) async throws {
        let payload = MarkReadPayload(isRead: true, readAt: Date().ISO8601Format())
        try await supabase
            .from("biometric_insights")
            .update(payload)
            .eq("id", value: insightId)
            .execute()
    }

    /// Mark an alert as read
    func markAlertRead(_ alertId: UUID) async throws {
        let payload = MarkReadPayload(isRead: true, readAt: Date().ISO8601Format())
        try await supabase
            .from("biometric_alerts")
            .update(payload)
            .eq("id", value: alertId)
            .execute()
    }

    /// Dismiss an insight
    func dismissInsight(_ insightId: UUID) async throws {
        let payload = DismissPayload(isDismissed: true)
        try await supabase
            .from("biometric_insights")
            .update(payload)
            .eq("id", value: insightId)
            .execute()
    }

    /// Trigger analysis on backend
    func triggerAnalysis() async throws {
        try await supabase.functions.invoke(
            "analyze-biometrics",
            options: .init()
        )
    }
}

// MARK: - DateFormatter Extension

private extension DateFormatter {
    static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
