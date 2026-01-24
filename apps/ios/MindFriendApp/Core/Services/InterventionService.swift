//  InterventionService.swift
//  MindFriendApp
//
//  Created by Context-Aware Interventions Feature
//  Service for monitoring intervention triggers and coordinating delivery

import Foundation
import Supabase
import HealthKit

// MARK: - Configuration Constants

private enum InterventionConstants {
    static let monitoringIntervalSeconds: TimeInterval = 5 * 60 // 5 minutes
    static let preferencesSaveDebounceNanoseconds: UInt64 = 500_000_000 // 500ms
    static let healthKitQueryTimeoutSeconds: UInt64 = 10 // 10 seconds
    static let recentHeartRateWindowMinutes: TimeInterval = 15 // Last 15 minutes
    static let recentHRVWindowMinutes: TimeInterval = 60 // Last 1 hour
    static let heartRateSampleLimit = 10
    static let hrvSampleLimit = 10
    static let heartRateMin = 40.0 // BPM
    static let heartRateMax = 220.0 // BPM
    static let hrvMin = 10.0 // Milliseconds
    static let hrvMax = 200.0 // Milliseconds
    static let preferencesCacheExpirationSeconds: TimeInterval = 5 * 60 // 5 minutes
}

// MARK: - AnyCodableValue Extension

extension AnyCodableValue {
    init(_ value: Any) {
        if let int = value as? Int {
            self = .int(int)
        } else if let double = value as? Double {
            self = .double(double)
        } else if let string = value as? String {
            self = .string(string)
        } else if let bool = value as? Bool {
            self = .bool(bool)
        } else if let array = value as? [Any] {
            self = .array(array.map { AnyCodableValue($0) })
        } else if let dict = value as? [String: Any] {
            self = .dictionary(dict.mapValues { AnyCodableValue($0) })
        } else {
            self = .null
        }
    }
}

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
    private let monitoringInterval: TimeInterval = InterventionConstants.monitoringIntervalSeconds
    
    // Debouncing for preference updates
    private var preferencesSaveTask: Task<Void, Error>?
    
    // Preferences caching
    private var cachedPreferences: InterventionPreferences?
    private var preferencesCacheTimestamp: Date?

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
    
    // MARK: - Deinitialization
    
    deinit {
        // Clean up timer to prevent memory leak
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        preferencesSaveTask?.cancel()
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
        let contextToSend: TriggerContext
        if let context = context {
            contextToSend = context
        } else {
            contextToSend = await gatherCurrentContext()
        }

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
        let session = try await supabase.auth.session
        let userId = session.user.id

        // Create delivery record (let database generate ID)
        let deliveryId = UUID()

        let delivery = InterventionDelivery(
            id: deliveryId,
            userId: userId,
            interventionId: UUID(uuidString: interventionId) ?? UUID(),
            triggerId: nil,
            triggerType: triggerType,
            contextSnapshot: context?.mapValues { AnyCodableValue($0) },
            deliveredAt: Date(),
            completed: false,
            completedAt: nil,
            dismissedAt: nil,
            rating: nil,
            feedback: nil
        )

        try await supabase
            .from("intervention_deliveries")
            .insert(delivery)
            .execute()

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
        // Build update struct
        struct DeliveryUpdate: Encodable {
            let completed: Bool
            let completedAt: String?
            let dismissedAt: String?
            let rating: Int?
            let feedback: String?

            enum CodingKeys: String, CodingKey {
                case completed
                case completedAt = "completed_at"
                case dismissedAt = "dismissed_at"
                case rating
                case feedback
            }
        }

        let update = DeliveryUpdate(
            completed: completed,
            completedAt: completed ? ISO8601DateFormatter().string(from: Date()) : nil,
            dismissedAt: completed ? nil : ISO8601DateFormatter().string(from: Date()),
            rating: rating,
            feedback: feedback
        )

        try await supabase
            .from("intervention_deliveries")
            .update(update)
            .eq("id", value: deliveryId.uuidString)
            .execute()

        // Refresh recent deliveries
        try await loadRecentDeliveries()
    }

    /// Update user preferences with debouncing
    func updatePreferences(_ preferences: InterventionPreferences) async throws {
        // Cancel any pending save
        preferencesSaveTask?.cancel()
        
        // Debounce: wait 500ms before saving
        let saveTask = Task { @MainActor in
            try await Task.sleep(nanoseconds: InterventionConstants.preferencesSaveDebounceNanoseconds)
            
            guard !Task.isCancelled else { return }
            
            try await supabase
                .from("intervention_preferences")
                .upsert(preferences)
                .execute()

            self.preferences = preferences
            
            // Invalidate cache on update
            self.cachedPreferences = preferences
            self.preferencesCacheTimestamp = Date()

            // Restart monitoring if enabled changed
            if preferences.enabled && !isMonitoring {
                try await startMonitoring()
            } else if !preferences.enabled && isMonitoring {
                stopMonitoring()
            }
        }
        
        preferencesSaveTask = saveTask
        
        do {
            try await saveTask.value
        } catch is CancellationError {
            // Ignore cancellation
            return
        } catch {
            // Log sanitized error (no PHI)
            print("Failed to update intervention preferences: \(error.localizedDescription)")
            throw error
        }
    }

    /// Load user preferences from database (with caching)
    func loadPreferences() async throws {
        // Check cache first
        if let cached = cachedPreferences,
           let timestamp = preferencesCacheTimestamp,
           Date().timeIntervalSince(timestamp) < InterventionConstants.preferencesCacheExpirationSeconds {
            self.preferences = cached
            return
        }
        
        let session = try await supabase.auth.session
        let userId = session.user.id

        do {
            let response: InterventionPreferences = try await supabase
                .from("intervention_preferences")
                .select()
                .eq("user_id", value: userId.uuidString)
                .single()
                .execute()
                .value

            self.preferences = response
            self.cachedPreferences = response
            self.preferencesCacheTimestamp = Date()
        } catch {
            // No preferences exist - use defaults
            let defaults = InterventionPreferences.default
            self.preferences = defaults
            self.cachedPreferences = defaults
            self.preferencesCacheTimestamp = Date()
        }
    }

    /// Load recent delivery history
    func loadRecentDeliveries() async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id

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
            // Sanitized error logging (no PHI)
            print("Error checking triggers: \(error.localizedDescription)")
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
                print("HealthKit authorization denied")
                return nil
            }
        } else if heartRateStatus == .sharingDenied {
            return nil
        }

        // Query biometrics on background thread with timeout
        return await Task.detached {
            do {
                return try await withThrowingTaskGroup(of: TriggerContext.Biometrics?.self) { group in
                    // Add query task
                    group.addTask {
                        async let heartRate = self.queryRecentHeartRate(from: healthStore)
                        async let hrv = self.queryRecentHRV(from: healthStore)
                        
                        let (hr, hrvValue) = await (heartRate, hrv)
                        
                        if hr == nil && hrvValue == nil {
                            return nil
                        }
                        
                        // Validate biometric values
                        let validatedHR = hr.flatMap { value in
                            (InterventionConstants.heartRateMin...InterventionConstants.heartRateMax).contains(value) ? value : nil
                        }
                        let validatedHRV = hrvValue.flatMap { value in
                            (InterventionConstants.hrvMin...InterventionConstants.hrvMax).contains(value) ? value : nil
                        }
                        
                        guard validatedHR != nil || validatedHRV != nil else {
                            return nil
                        }

                        return TriggerContext.Biometrics(heartRate: validatedHR, hrv: validatedHRV)
                    }
                    
                    // Add timeout task
                    group.addTask {
                        try await Task.sleep(nanoseconds: InterventionConstants.healthKitQueryTimeoutSeconds * 1_000_000_000)
                        return nil // Timeout returns nil
                    }
                    
                    // Return first result (query or timeout)
                    let result = try await group.next()
                    group.cancelAll()
                    return result ?? nil
                }
            } catch {
                print("HealthKit query error: \(error.localizedDescription)")
                return nil
            }
        }.value
    }

    private func queryRecentHeartRate(from healthStore: HKHealthStore) async -> Double? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-InterventionConstants.recentHeartRateWindowMinutes * 60),
            end: Date(),
            options: .strictEndDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: InterventionConstants.heartRateSampleLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                // Handle on background thread
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
            withStart: Date().addingTimeInterval(-InterventionConstants.recentHRVWindowMinutes * 60),
            end: Date(),
            options: .strictEndDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: InterventionConstants.hrvSampleLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                // Handle on background thread
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
