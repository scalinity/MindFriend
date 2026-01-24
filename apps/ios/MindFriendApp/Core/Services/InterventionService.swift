//  InterventionService.swift
//  MindFriendApp
//
//  Created by Context-Aware Interventions Feature
//  Service for monitoring intervention triggers and coordinating delivery

import Foundation
import Supabase
import HealthKit

@MainActor
final class InterventionService: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var preferences: InterventionPreferences?
    @Published private(set) var pendingIntervention: MicroMomentTemplate?
    @Published private(set) var contextMessage: String?
    @Published private(set) var recentDeliveries: [InterventionDelivery] = []
    @Published private(set) var isMonitoring = false

    // MARK: - Private Properties

    private let supabase: SupabaseClient
    private let healthStore: HKHealthStore?
    private var monitoringTimer: Timer?
    private let monitoringInterval: TimeInterval = 5 * 60 // 5 minutes

    // MARK: - Initialization

    init(supabase: SupabaseClient) {
        self.supabase = supabase

        // Initialize HealthKit if available
        if HKHealthStore.isHealthDataAvailable() {
            self.healthStore = HKHealthStore()
        } else {
            self.healthStore = nil
        }
    }

    // MARK: - Public Methods

    /// Start monitoring for trigger conditions (respects preferences)
    func startMonitoring() async throws {
        guard !isMonitoring else { return }

        // Load preferences first
        try await loadPreferences()

        // Only monitor if enabled
        guard preferences?.enabled == true else {
            print("Interventions disabled in preferences")
            return
        }

        isMonitoring = true

        // Start timer for periodic checks
        monitoringTimer = Timer.scheduledTimer(
            withTimeInterval: monitoringInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkTriggersAutomatically()
            }
        }

        print("Started intervention monitoring (checking every \(Int(monitoringInterval / 60)) minutes)")

        // Perform initial check
        await checkTriggersAutomatically()
    }

    /// Stop monitoring
    func stopMonitoring() {
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        print("Stopped intervention monitoring")
    }

    /// Manually check if an intervention should be triggered
    func checkTriggers(context: TriggerContext? = nil) async throws -> CheckTriggersResponse {
        let contextToSend = context ?? await gatherCurrentContext()

        let request = CheckTriggersRequest(context: contextToSend)

        let response: CheckTriggersResponse = try await supabase.functions.invoke(
            "check-intervention-triggers",
            options: FunctionInvokeOptions(body: request)
        )

        // If intervention should trigger, store it
        if response.shouldTrigger, let intervention = response.intervention {
            pendingIntervention = intervention
            contextMessage = response.contextMessage
        }

        return response
    }

    /// Track that an intervention was delivered
    func trackDelivery(
        interventionId: String,
        triggerType: TriggerType?,
        context: [String: Any]?
    ) async throws -> UUID {
        guard let userId = try await supabase.auth.session.user.id else {
            throw NSError(domain: "InterventionService", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "User not authenticated"
            ])
        }

        let contextSnapshot = context.map { dict in
            dict.mapValues { AnyCodableValue($0) }
        }

        let delivery: [String: Any] = [
            "user_id": userId.uuidString,
            "intervention_id": interventionId,
            "trigger_type": triggerType?.rawValue as Any,
            "context_snapshot": contextSnapshot as Any,
            "delivered_at": ISO8601DateFormatter().string(from: Date()),
            "completed": false
        ]

        let response: [String: Any] = try await supabase
            .from("intervention_deliveries")
            .insert(delivery)
            .select()
            .single()
            .execute()
            .value

        guard let id = response["id"] as? String, let deliveryId = UUID(uuidString: id) else {
            throw NSError(domain: "InterventionService", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Failed to parse delivery ID"
            ])
        }

        // Refresh recent deliveries
        try await loadRecentDeliveries()

        return deliveryId
    }

    /// Update delivery with completion status and rating
    func updateDelivery(
        deliveryId: UUID,
        completed: Bool,
        rating: Int? = nil,
        feedback: String? = nil
    ) async throws {
        var updates: [String: Any] = [
            "completed": completed
        ]

        if completed {
            updates["completed_at"] = ISO8601DateFormatter().string(from: Date())
        } else {
            updates["dismissed_at"] = ISO8601DateFormatter().string(from: Date())
        }

        if let rating = rating {
            updates["rating"] = rating
        }

        if let feedback = feedback {
            updates["feedback"] = feedback
        }

        try await supabase
            .from("intervention_deliveries")
            .update(updates)
            .eq("id", value: deliveryId.uuidString)
            .execute()

        // Refresh recent deliveries
        try await loadRecentDeliveries()
    }

    /// Update user preferences
    func updatePreferences(_ preferences: InterventionPreferences) async throws {
        guard let userId = try await supabase.auth.session.user.id else {
            throw NSError(domain: "InterventionService", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "User not authenticated"
            ])
        }

        let prefsData: [String: Any] = [
            "user_id": userId.uuidString,
            "enabled": preferences.enabled,
            "max_daily": preferences.maxDaily,
            "quiet_hours_start": preferences.quietHoursStart as Any,
            "quiet_hours_end": preferences.quietHoursEnd as Any,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]

        try await supabase
            .from("intervention_preferences")
            .upsert(prefsData)
            .execute()

        self.preferences = preferences

        // Restart monitoring if enabled changed
        if preferences.enabled && !isMonitoring {
            try await startMonitoring()
        } else if !preferences.enabled && isMonitoring {
            stopMonitoring()
        }
    }

    /// Load user preferences from database
    func loadPreferences() async throws {
        guard let userId = try await supabase.auth.session.user.id else {
            self.preferences = nil
            return
        }

        do {
            let response: InterventionPreferences = try await supabase
                .from("intervention_preferences")
                .select()
                .eq("user_id", value: userId.uuidString)
                .single()
                .execute()
                .value

            self.preferences = response
        } catch {
            // No preferences exist - use defaults
            self.preferences = InterventionPreferences.default
        }
    }

    /// Load recent delivery history
    func loadRecentDeliveries() async throws {
        guard let userId = try await supabase.auth.session.user.id else {
            self.recentDeliveries = []
            return
        }

        let response: [InterventionDelivery] = try await supabase
            .from("intervention_deliveries")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("delivered_at", ascending: false)
            .limit(20)
            .execute()
            .value

        self.recentDeliveries = response
    }

    // MARK: - Private Methods

    private func checkTriggersAutomatically() async {
        do {
            let response = try await checkTriggers()
            if !response.shouldTrigger {
                print("Trigger check: suppressed (\(response.suppressionReason ?? "unknown"))")
            }
        } catch {
            print("Error checking triggers: \(error)")
        }
    }

    private func gatherCurrentContext() async -> TriggerContext {
        let timeOfDay = getTimeOfDay()

        // Gather biometrics if HealthKit available and authorized
        var biometrics: TriggerContext.Biometrics?
        if let healthStore = healthStore {
            biometrics = await gatherBiometrics(from: healthStore)
        }

        // TODO: Get recent mood from mood service
        let recentMood: Int? = nil

        return TriggerContext(
            biometrics: biometrics,
            timeOfDay: timeOfDay,
            recentMood: recentMood
        )
    }

    private func getTimeOfDay() -> String? {
        let hour = Calendar.current.component(.hour, from: Date())

        if hour >= 6 && hour < 12 {
            return "morning"
        } else if hour >= 12 && hour < 17 {
            return "afternoon"
        } else if hour >= 17 && hour < 22 {
            return "evening"
        }

        return nil
    }

    private func gatherBiometrics(from healthStore: HKHealthStore) async -> TriggerContext.Biometrics? {
        // Request HealthKit authorization if not already granted
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        else {
            return nil
        }

        let typesToRead: Set<HKSampleType> = [heartRateType, hrvType]

        // Check if already authorized
        let heartRateStatus = healthStore.authorizationStatus(for: heartRateType)
        if heartRateStatus == .notDetermined {
            do {
                try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            } catch {
                print("HealthKit authorization denied: \(error)")
                return nil
            }
        } else if heartRateStatus == .sharingDenied {
            return nil
        }

        // Query recent heart rate
        let heartRate = await queryRecentHeartRate(from: healthStore)
        let hrv = await queryRecentHRV(from: healthStore)

        if heartRate == nil && hrv == nil {
            return nil
        }

        return TriggerContext.Biometrics(heartRate: heartRate, hrv: hrv)
    }

    private func queryRecentHeartRate(from healthStore: HKHealthStore) async -> Double? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-15 * 60), // Last 15 minutes
            end: Date(),
            options: .strictEndDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: 10,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let avgHR = samples.reduce(0.0) { sum, sample in
                    sum + sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
                } / Double(samples.count)

                continuation.resume(returning: avgHR)
            }

            healthStore.execute(query)
        }
    }

    private func queryRecentHRV(from healthStore: HKHealthStore) async -> Double? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-60 * 60), // Last 1 hour
            end: Date(),
            options: .strictEndDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: 10,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let avgHRV = samples.reduce(0.0) { sum, sample in
                    sum + sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                } / Double(samples.count)

                continuation.resume(returning: avgHRV)
            }

            healthStore.execute(query)
        }
    }
}
