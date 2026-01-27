import Foundation
import Combine
import HealthKit

/// Service for monitoring real-time signals from various data sources
@MainActor
final class SignalMonitor: ObservableObject {
    private let supabaseDataService: SupabaseDataService
    private let healthStore = HKHealthStore()

    @Published private(set) var currentSignals: [String: Double] = [:]
    @Published private(set) var isMonitoring = false
    @Published private(set) var lastUpdateTime: Date?

    private var signalHandlers: [(SignalUpdate) -> Void] = []
    private var monitoringTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // HealthKit authorization state (cache to avoid repeated prompts)
    private var healthKitAuthorizationRequested = false
    private var healthKitAuthorizationGranted = false
    private var healthKitSleepAuthorized = false
    private var healthKitActivityAuthorized = false

    // Integration services (injected)
    weak var nervousSystemEngine: SignatureNervousSystemStateEngine?
    weak var cognitiveDetector: SignatureCognitiveDistortionDetector?
    weak var socialVitalityService: SignatureSocialVitalityService?

    // N006 Wellbeing Debt integration (actor-based, polled during measurement)
    var wellbeingDebtService: WellbeingDebtService?

    init(supabaseDataService: SupabaseDataService) {
        self.supabaseDataService = supabaseDataService
    }

    deinit {
        monitoringTask?.cancel()
    }

    /// Start observing signals from all integrated sources
    func startObserving() {
        guard !isMonitoring else { return }
        isMonitoring = true

        setupIntegrationObservers()
        schedulePeriodicMeasurement()
    }

    /// Stop observing signals
    func stopObserving() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
        cancellables.removeAll()
    }

    /// Add a handler for signal updates
    func onSignalUpdate(_ handler: @escaping (SignalUpdate) -> Void) {
        signalHandlers.append(handler)
    }

    /// Get current signals as a dictionary
    func getCurrentSignals() -> [String: Double] {
        currentSignals
    }

    /// Manually measure all signals now
    func measureSignalsNow() async throws {
        await measureAllSignals()
    }

    // MARK: - Private Methods

    private func setupIntegrationObservers() {
        // Observe Nervous System State Engine (N001)
        if let nervousSystemEngine = nervousSystemEngine {
            nervousSystemEngine.$currentState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.processNervousSystemState(state)
                }
                .store(in: &cancellables)
        }

        // Observe Cognitive Distortion Detector (N006)
        if let cognitiveDetector = cognitiveDetector {
            cognitiveDetector.$recentDistortions
                .receive(on: DispatchQueue.main)
                .sink { [weak self] distortions in
                    self?.processCognitiveDistortions(distortions)
                }
                .store(in: &cancellables)
        }

        // Observe Social Vitality Service (N007)
        if let socialVitalityService = socialVitalityService {
            socialVitalityService.$currentVitalityScore
                .receive(on: DispatchQueue.main)
                .sink { [weak self] score in
                    self?.processSocialVitality(score)
                }
                .store(in: &cancellables)
        }
    }

    private func schedulePeriodicMeasurement() {
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.measureAllSignals()

                // Wait 1 hour between measurements
                try? await Task.sleep(nanoseconds: 60 * 60 * 1_000_000_000)
            }
        }
    }

    private func measureAllSignals() async {
        // Measure HealthKit signals
        await measureHealthKitSignals()

        // Measure Wellbeing Debt signals (N006 integration)
        await measureWellbeingDebtSignals()

        // Update timestamp
        lastUpdateTime = Date()

        // Persist signals to database
        await persistCurrentSignals()
    }

    // MARK: - Wellbeing Debt (N006)

    private func measureWellbeingDebtSignals() async {
        guard let debtService = wellbeingDebtService else { return }

        do {
            guard let score = try await debtService.fetchLatestDebtScore() else { return }

            // Emit high_debt signal when severity is warning or danger
            // This integrates with F026 Stress Signature for compound signal detection
            let severity = score.thresholdStatus.severity

            if severity == .warning || severity == .danger {
                // Convert threshold severity to signal value (0.6-1.0 range)
                let signalValue: Double = severity == .danger ? 0.9 : 0.7

                let signal = SignalUpdate(
                    signalType: "high_debt",
                    value: signalValue,
                    source: .wellbeingDebt
                )
                emitSignal(signal)
            }

            // Emit declining_wellness signal when trend is worsening
            if score.trend.direction == .worsening {
                let velocityValue = NSDecimalNumber(decimal: score.trend.velocity).doubleValue
                // Convert velocity (-10 to 0) to signal value (0.5-1.0)
                let normalizedVelocity = min(1.0, max(0.5, 0.5 - (velocityValue / 20.0)))

                let signal = SignalUpdate(
                    signalType: "declining_wellness",
                    value: normalizedVelocity,
                    source: .wellbeingDebt
                )
                emitSignal(signal)
            }
        } catch {
            // Log without sensitive data
            print("[SignalMonitor] Wellbeing debt query error occurred")
        }
    }

    // MARK: - Integration Processing

    private func processNervousSystemState(_ state: SignatureNervousSystemState?) {
        guard let state = state else { return }

        // Dorsal vagal state indicates numbness/shutdown
        if state == .dorsalVagal {
            let signal = SignalUpdate(
                signalType: "numbness",
                value: 0.8,
                source: .nervousSystem
            )
            emitSignal(signal)
        }

        // Sympathetic state indicates anxiety/tension
        if state == .sympathetic {
            let signal = SignalUpdate(
                signalType: "tension",
                value: 0.7,
                source: .nervousSystem
            )
            emitSignal(signal)
        }
    }

    private func processCognitiveDistortions(_ distortions: [SignatureCognitiveDistortion]) {
        let today = Calendar.current.startOfDay(for: Date())
        let todayDistortions = distortions.filter {
            Calendar.current.isDate($0.detectedAt, inSameDayAs: today)
        }

        // Count catastrophizing
        let catastrophizingCount = todayDistortions.filter {
            $0.type == .catastrophizing
        }.count

        if catastrophizingCount >= 3 {
            let value = min(Double(catastrophizingCount) / 5.0, 1.0)
            let signal = SignalUpdate(
                signalType: "catastrophizing",
                value: value,
                source: .cognitiveDetection
            )
            emitSignal(signal)
        }

        // Count rumination
        let ruminationCount = todayDistortions.filter {
            $0.type == .rumination || $0.type == .mindReading
        }.count

        if ruminationCount >= 3 {
            let value = min(Double(ruminationCount) / 5.0, 1.0)
            let signal = SignalUpdate(
                signalType: "rumination",
                value: value,
                source: .cognitiveDetection
            )
            emitSignal(signal)
        }
    }

    private func processSocialVitality(_ score: Double?) {
        guard let score = score else { return }

        // Low social vitality indicates isolation
        // Score is 0-100, lower is worse
        if score < 30 {
            let value = 1.0 - (score / 100.0)
            let signal = SignalUpdate(
                signalType: "isolation",
                value: value,
                source: .socialVitality
            )
            emitSignal(signal)
        }
    }

    // MARK: - HealthKit

    private func measureHealthKitSignals() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!

        // Only request authorization once per session
        if !healthKitAuthorizationRequested {
            do {
                try await healthStore.requestAuthorization(
                    toShare: [],
                    read: [sleepType, stepType]
                )
                healthKitAuthorizationRequested = true
                
                // Check if access was actually granted for each type
                // Note: .sharingAuthorized means read access is granted (confusing Apple naming)
                let sleepStatus = healthStore.authorizationStatus(for: sleepType)
                let stepStatus = healthStore.authorizationStatus(for: stepType)
                
                // Store individual authorization states for granular query control
                healthKitSleepAuthorized = (sleepStatus == .sharingAuthorized)
                healthKitActivityAuthorized = (stepStatus == .sharingAuthorized)
                
                // Grant access if either type is authorized (partial access still useful)
                healthKitAuthorizationGranted = (healthKitSleepAuthorized || healthKitActivityAuthorized)
                
                if !healthKitAuthorizationGranted {
                    print("[SignalMonitor] HealthKit access not granted by user")
                    return
                }
            } catch {
                // Log without sensitive data
                print("[SignalMonitor] HealthKit authorization failed")
                return
            }
        }
        
        // Skip all queries if no HealthKit access at all
        guard healthKitAuthorizationGranted else { return }

        // Measure sleep only if authorized (avoids unnecessary error logging)
        if healthKitSleepAuthorized {
            await measureSleepSignals()
        }

        // Measure activity only if authorized (avoids unnecessary error logging)
        if healthKitActivityAuthorized {
            await measureActivitySignals()
        }
    }

    private func measureSleepSignals() async {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

        // Get last night's sleep
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!

        let predicate = HKQuery.predicateForSamples(
            withStart: startOfYesterday,
            end: startOfToday,
            options: .strictStartDate
        )

        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
                let query = HKSampleQuery(
                    sampleType: sleepType,
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

            // Calculate total sleep duration
            var totalSleep: TimeInterval = 0
            for sample in samples {
                let value = sample.value
                // Only count asleep states (not inBed)
                if value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                   value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                   value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                   value == HKCategoryValueSleepAnalysis.asleepREM.rawValue {
                    totalSleep += sample.endDate.timeIntervalSince(sample.startDate)
                }
            }

            let sleepHours = totalSleep / 3600

            // Insomnia: less than 5 hours
            if sleepHours < 5 && sleepHours > 0 {
                let value = 1.0 - (sleepHours / 5.0)
                let signal = SignalUpdate(
                    signalType: "insomnia_wired",
                    value: value,
                    source: .healthkit
                )
                emitSignal(signal)
            }

            // Oversleeping: more than 10 hours
            if sleepHours > 10 {
                let value = min((sleepHours - 10) / 4.0, 1.0)
                let signal = SignalUpdate(
                    signalType: "oversleeping",
                    value: value,
                    source: .healthkit
                )
                emitSignal(signal)
            }

        } catch {
            // Log without exposing user health data
            print("[SignalMonitor] Sleep query error occurred")
        }
    }

    private func measureActivitySignals() async {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: now,
            options: .strictStartDate
        )

        do {
            let statistics = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKStatistics, Error>) in
                let query = HKStatisticsQuery(
                    quantityType: stepType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, stats, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let stats = stats {
                        continuation.resume(returning: stats)
                    } else {
                        continuation.resume(throwing: StressSignatureError.detectionFailed)
                    }
                }
                healthStore.execute(query)
            }

            let steps = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0

            // Low energy: less than 1000 steps
            if steps < 1000 {
                let value = 1.0 - (steps / 1000.0)
                let signal = SignalUpdate(
                    signalType: "low_energy",
                    value: max(value, 0),
                    source: .healthkit
                )
                emitSignal(signal)
            }

        } catch {
            // Log without exposing user health data
            print("[SignalMonitor] Activity query error occurred")
        }
    }

    // MARK: - Signal Emission

    private func emitSignal(_ signal: SignalUpdate) {
        // Validate signal value is in expected range [0.0, 1.0]
        let clampedValue = max(0.0, min(1.0, signal.value))
        
        // Validate signal type is not empty
        guard !signal.signalType.isEmpty else {
            print("[SignalMonitor] Invalid empty signal type")
            return
        }
        
        currentSignals[signal.signalType] = clampedValue

        // Create validated signal
        let validatedSignal = SignalUpdate(
            signalType: signal.signalType,
            value: clampedValue,
            source: signal.source
        )
        
        for handler in signalHandlers {
            handler(validatedSignal)
        }
    }

    private func persistCurrentSignals() async {
        let today = Date()

        for (signalType, value) in currentSignals {
            do {
                try await supabaseDataService.upsertSignatureSignal(
                    signalType: signalType,
                    value: value,
                    source: "app_activity",
                    date: today
                )
            } catch {
                // Log without exposing signal types or values
                print("[SignalMonitor] Failed to persist signal data")
            }
        }
    }
}

// MARK: - SupabaseDataService Extension

extension SupabaseDataService {
    func upsertSignatureSignal(
        signalType: String,
        value: Double,
        source: String,
        date: Date
    ) async throws {
        struct UpsertParams: Encodable {
            let pUserId: String
            let pSignalType: String
            let pValue: Double
            let pSource: String
            let pDate: String

            enum CodingKeys: String, CodingKey {
                case pUserId = "p_user_id"
                case pSignalType = "p_signal_type"
                case pValue = "p_value"
                case pSource = "p_source"
                case pDate = "p_date"
            }
        }

        let dateString = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: date))

        let params = UpsertParams(
            pUserId: supabase.auth.currentUser?.id.uuidString ?? "",
            pSignalType: signalType,
            pValue: value,
            pSource: source,
            pDate: String(dateString.prefix(10))
        )

        _ = try await supabase.rpc(
            "upsert_signature_signal",
            params: params
        ).execute()
    }
}

// MARK: - Placeholder Types for SignalMonitor Integration

// These placeholder types allow SignalMonitor to compile standalone.
// Prefixed with "Signature" to avoid conflicts with real implementations.

enum SignatureNervousSystemState: String, Codable {
    case ventral
    case sympathetic
    case dorsalVagal = "dorsal_vagal"
}

struct SignatureCognitiveDistortion: Identifiable, Codable {
    let id: UUID
    let type: SignatureDistortionType
    let detectedAt: Date

    enum SignatureDistortionType: String, Codable {
        case catastrophizing
        case rumination
        case mindReading
        case allOrNothing
        case overgeneralization
        case filtering
        case personalization
        case shouldStatements
        case emotionalReasoning
        case labeling
    }
}

// Placeholder classes for optional service integration
@MainActor
class SignatureNervousSystemStateEngine: ObservableObject {
    @Published var currentState: SignatureNervousSystemState?
}

@MainActor
class SignatureCognitiveDistortionDetector: ObservableObject {
    @Published var recentDistortions: [SignatureCognitiveDistortion] = []
}

@MainActor
class SignatureSocialVitalityService: ObservableObject {
    @Published var currentVitalityScore: Double?
}
