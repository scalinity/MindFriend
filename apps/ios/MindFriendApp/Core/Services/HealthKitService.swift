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

// MARK: - Sync status, opt-out and dependencies

/// Daily summaries count as observed only when HealthKit actually returned a value:
/// a genuine zero is data, nil is not.
extension BiometricSyncPayload.DailySummaryPayload {
    var hasObservedValue: Bool {
        sleepDurationMinutes != nil || sleepQualityScore != nil || sleepStartTime != nil || sleepEndTime != nil
            || timeInBedMinutes != nil || hrvAverageMs != nil || hrvMinMs != nil || hrvMaxMs != nil
            || restingHeartRate != nil || stepsCount != nil || activeEnergyKcal != nil || exerciseMinutes != nil
            || standHours != nil || distanceMeters != nil || mindfulMinutes != nil
    }
}

/// Everything one HealthKit query pass returned.
struct HealthCollection {
    var summaries: [BiometricSyncPayload.DailySummaryPayload]
    var workouts: [BiometricSyncPayload.WorkoutPayload]
}

/// What the last query actually found. It says nothing about private read permission:
/// "no recent data" is never reported as a denial, and a failed query is never "empty".
struct HealthQueryOutcome: Equatable {
    enum Status: Equatable { case samplesAvailable, noRecentData, queryFailed }

    static let sourceName = "Apple Health (HealthKit)"

    let status: Status
    let interval: DateInterval
    let checkedAt: Date
    let daysWithSamples: Int
    let workoutCount: Int
    let failureDescription: String?

    var statusText: String {
        switch status {
        case .samplesAvailable: return "Samples available"
        case .noRecentData: return "No recent data available"
        case .queryFailed: return "Couldn't read Health data"
        }
    }

    /// Availability comes only from non-nil results (including genuine zeros) and workouts.
    static func evaluate(_ collection: HealthCollection, interval: DateInterval, checkedAt: Date) -> HealthQueryOutcome {
        let days = collection.summaries.filter(\.hasObservedValue).count
        let status: Status = (days > 0 || !collection.workouts.isEmpty) ? .samplesAvailable : .noRecentData
        return HealthQueryOutcome(status: status, interval: interval, checkedAt: checkedAt,
                                  daysWithSamples: days, workoutCount: collection.workouts.count, failureDescription: nil)
    }

    static func failed(_ error: Error, interval: DateInterval, checkedAt: Date) -> HealthQueryOutcome {
        HealthQueryOutcome(status: .queryFailed, interval: interval, checkedAt: checkedAt,
                           daysWithSamples: 0, workoutCount: 0, failureDescription: error.localizedDescription)
    }

    /// Only observed days are uploaded; blank summaries are never sent as if they were data.
    static func uploadPayload(_ collection: HealthCollection) -> BiometricSyncPayload? {
        let observed = collection.summaries.filter(\.hasObservedValue)
        guard !observed.isEmpty || !collection.workouts.isEmpty else { return nil }
        return BiometricSyncPayload(dailySummaries: observed, workouts: collection.workouts)
    }
}

/// Per-account local sync opt-out, separate from Apple's permission request. nil = no local decision.
struct HealthSyncOptOut {
    let defaults: UserDefaults

    private func key(_ owner: UUID) -> String { "healthkit.syncPaused.\(owner.uuidString.lowercased())" }

    func isPaused(for owner: UUID) -> Bool? {
        defaults.object(forKey: key(owner)) as? Bool
    }

    func setPaused(_ paused: Bool, for owner: UUID) {
        defaults.set(paused, forKey: key(owner))
    }
}

enum HealthSyncError: Error, LocalizedError, Equatable {
    case paused
    case signedOut
    /// The account has no active connection yet: only an explicit Connect enables syncing.
    case notConnected
    /// The deliberate account setting could not be read, so syncing fails closed.
    case connectionUnknown

    var errorDescription: String? {
        switch self {
        case .paused: return "Apple Health sync is paused. Reconnect to resume."
        case .signedOut: return "Sign in to sync Apple Health."
        case .notConnected: return "Connect Apple Health to start syncing."
        case .connectionUnknown: return "Couldn't confirm your Apple Health sync setting. Try again when you're online."
        }
    }
}

/// Bounded categories for health connection/upload failures. Raw remote error bodies never reach
/// logs or the UI.
enum HealthOperationError: Error, LocalizedError, Equatable {
    case network, auth, rejected, server, unknown

    var category: String {
        switch self {
        case .network: return "network"
        case .auth: return "auth"
        case .rejected: return "rejected"
        case .server: return "server"
        case .unknown: return "unknown"
        }
    }

    var errorDescription: String? {
        switch self {
        case .network: return "You appear to be offline."
        case .auth: return "Your session needs to be refreshed. Sign in again."
        case .rejected: return "The request was not accepted."
        case .server: return "The service is temporarily unavailable."
        case .unknown: return "Something went wrong."
        }
    }

    static func classify(_ error: Error) -> HealthOperationError {
        if let known = error as? HealthOperationError { return known }
        if error is URLError { return .network }
        if let http = error as? HealthHTTPStatusError {
            switch http.status {
            case 401, 403: return .auth
            case 500...599: return .server
            default: return .rejected
            }
        }
        return .unknown
    }
}

struct HealthHTTPStatusError: Error, Equatable { let status: Int }

/// The account (and its access token) an operation was started for. The pair is captured together
/// from one session value and then travels with the operation, so a later account switch can never
/// attach another account's token to old data. The token is never logged.
struct HealthCredential: Equatable, CustomStringConvertible {
    let owner: UUID
    let accessToken: String
    var description: String { "HealthCredential(owner: \(owner), token: <redacted>)" }
}

/// What the account itself says about the deliberate connection. `unknown` = could not be read.
enum HealthRemoteConnection: Equatable { case connected, disconnected, noRecord, unknown }

/// Health writes bound to ONE captured credential. The Supabase SDK replaces the Authorization
/// header of every request with whatever session is current at send time (SupabaseClient.adaptRequest,
/// supabase-swift 2.55.4), so an SDK call cannot be pinned to a captured owner. These two fixed
/// existing endpoints are therefore sent as plain URLRequests carrying the captured token.
struct HealthBoundWrites {
    var baseURL: URL
    var apiKey: String
    var send: (URLRequest) async throws -> (Data, URLResponse)

    static func live(baseURL: URL, apiKey: String) -> HealthBoundWrites {
        let session = URLSession(configuration: .ephemeral)
        return HealthBoundWrites(baseURL: baseURL, apiKey: apiKey, send: { try await session.data(for: $0) })
    }

    private func request(_ url: URL, credential: HealthCredential, body: Data, extra: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        for (key, value) in extra { request.setValue(value, forHTTPHeaderField: key) }
        return request
    }

    /// POST {project}/functions/v1/sync-biometrics (the endpoint the SDK call used).
    func uploadRequest(_ payload: BiometricSyncPayload, credential: HealthCredential) throws -> URLRequest {
        request(baseURL.appendingPathComponent("functions/v1/sync-biometrics"),
                credential: credential, body: try JSONEncoder().encode(payload))
    }

    /// Upsert of the caller's healthkit_connections row (legacy wire shape, on_conflict=user_id).
    func connectionRequest(connected: Bool, credential: HealthCredential) throws -> URLRequest {
        struct Row: Encodable {
            let userId: String
            let isConnected: Bool
            let authorizedTypes: [String]
            enum CodingKeys: String, CodingKey {
                case userId = "user_id", isConnected = "is_connected", authorizedTypes = "authorized_types"
            }
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/healthkit_connections"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id")]
        guard let url = components?.url else { throw HealthOperationError.unknown }
        let body = try JSONEncoder().encode(Row(userId: credential.owner.uuidString, isConnected: connected, authorizedTypes: []))
        return request(url, credential: credential, body: body, extra: ["Prefer": "resolution=merge-duplicates,return=minimal"])
    }

    func perform(_ request: URLRequest) async throws {
        let (_, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw HealthOperationError.unknown }
        guard (200..<300).contains(http.statusCode) else { throw HealthHTTPStatusError(status: http.statusCode) }
    }

    func upload(_ payload: BiometricSyncPayload, credential: HealthCredential) async throws {
        try await perform(try uploadRequest(payload, credential: credential))
    }

    func writeConnection(connected: Bool, credential: HealthCredential) async throws {
        try await perform(try connectionRequest(connected: connected, credential: credential))
    }
}

/// Injection seam: real HealthKit/Supabase by default, fakes in offline tests.
struct HealthKitServiceDependencies {
    var isAvailable: () -> Bool
    var permissionState: () async -> HealthKitService.PermissionRequestState
    var requestPermission: () async throws -> Void
    /// Queries one interval; `shouldContinue` turns false when the operation was cancelled or paused.
    var collect: (DateInterval, Set<HealthKitDataType>, @MainActor () -> Bool) async throws -> HealthCollection
    /// The currently authenticated account and its token, captured together (nil = signed out).
    var currentCredential: () async -> HealthCredential?
    /// What the account says about the deliberate connection.
    var fetchConnection: (UUID) async -> HealthRemoteConnection
    /// Writes are bound to the credential the operation captured, never to ambient state.
    var writeConnection: (HealthCredential, Bool) async throws -> Void
    var upload: (BiometricSyncPayload, HealthCredential) async throws -> Void
    var now: () -> Date
    var optOut: HealthSyncOptOut
}

/// Service for integrating with Apple HealthKit
/// Handles authorization, data fetching, and syncing biometrics to the backend
@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    /// Exposed for HRV queries - use via helper methods when possible
    let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "com.mindfriend", category: "HealthKit")

    enum PermissionRequestState {
        case unavailable, requestNeeded, completed, unknown
    }
    @Published private(set) var permissionRequestState: PermissionRequestState = .unknown
    /// Request completion permits queries; it says nothing about private per-type read choices.
    var hasCompletedPermissionRequest: Bool { permissionRequestState == .completed }
    private var requestedTypes: Set<HealthKitDataType> {
        hasCompletedPermissionRequest ? Set(HealthKitDataType.allCases) : []
    }
    @Published var lastSyncDate: Date?
    @Published var isSyncing = false
    @Published var syncError: Error?
    /// The user's deliberate opt-out for the current account. Independent of Apple's permission state.
    @Published private(set) var syncPaused = false
    /// Latest query result (samples / no recent data / failed) for the current account.
    @Published private(set) var lastQueryOutcome: HealthQueryOutcome?
    /// Set when the account could not be told about a connect/disconnect; the local choice still stands.
    @Published private(set) var connectionError: Error?

    /// Sync runs only when Apple setup is complete AND the user has not paused it.
    var isSyncEnabled: Bool { hasCompletedPermissionRequest && !syncPaused }

    private var deps: HealthKitServiceDependencies!

    // Immutable-token pattern: an operation captures account + credential + epochs and re-checks
    // them after every await. Only the newest deliberate choice (connect/disconnect) publishes.
    private struct OperationToken {
        let credential: HealthCredential
        let ownerEpoch: Int
        let syncGeneration: Int
        var owner: UUID { credential.owner }
    }
    private var owner: UUID?
    private var ownerEpoch = 0
    private var syncGeneration = 0
    private var choiceSequence = 0
    private var writeTail: Task<Void, Never>?

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
        deps = Self.liveDependencies(for: self)
        // Check if we already have authorization on launch
        Task {
            await checkAuthorizationStatus()
        }
    }

    /// Test/embedding seam: no automatic refresh and no real HealthKit or network access.
    init(dependencies: HealthKitServiceDependencies) {
        deps = dependencies
    }

    // MARK: - Owner tracking

    /// Resolve the current account and pin an operation to it. Account changes reset per-account state.
    private func beginOperation() async -> OperationToken? {
        let credential = await deps.currentCredential()
        adoptOwner(credential?.owner)
        guard let credential else { return nil }
        return OperationToken(credential: credential, ownerEpoch: ownerEpoch, syncGeneration: syncGeneration)
    }

    private func adoptOwner(_ newOwner: UUID?) {
        guard newOwner != owner else { return }
        owner = newOwner
        ownerEpoch += 1
        syncGeneration += 1
        choiceSequence += 1
        // Per-account state never leaks to the next account.
        lastSyncDate = nil
        lastQueryOutcome = nil
        syncError = nil
        connectionError = nil
        isSyncing = false
        syncPaused = newOwner.flatMap { deps.optOut.isPaused(for: $0) } ?? false
    }

    /// REQUIRED WIRING (owned by the authenticated app shell): call this with the authenticated
    /// user's id when an authenticated session is bound (sign-in / restoration, before any Health UI
    /// is shown) and with `nil` synchronously when it is unbound (sign-out / account switch). It
    /// invalidates every in-flight Health operation of the previous account. Operations also
    /// re-resolve the signed-in account after their awaits, so a missed call degrades to a
    /// cancelled operation rather than a cross-account write.
    func ownerDidChange(_ newOwner: UUID?) {
        adoptOwner(newOwner)
    }

    private func isCurrent(_ token: OperationToken) -> Bool {
        owner == token.owner && ownerEpoch == token.ownerEpoch
    }

    private func isSyncCurrent(_ token: OperationToken) -> Bool {
        isCurrent(token) && syncGeneration == token.syncGeneration && !syncPaused
    }

    /// Re-resolve the signed-in account after an await; an account change invalidates the token.
    private func ambientStillMatches(_ token: OperationToken) async -> Bool {
        let ambient = await deps.currentCredential()
        adoptOwner(ambient?.owner)
        return ambient?.owner == token.owner && isCurrent(token)
    }

    /// Remote connection writes run one at a time, in the order they were requested.
    private func serializedConnectionWrite(_ work: @escaping @MainActor () async throws -> Void) async throws {
        let previous = writeTail
        let job = Task { @MainActor () -> Error? in
            await previous?.value
            do { try await work(); return nil } catch { return error }
        }
        writeTail = Task { _ = await job.value }
        if let error = await job.value { throw error }
    }

    private func logFailure(_ what: String, _ error: Error) {
        logger.error("\(what, privacy: .public) failed: \(HealthOperationError.classify(error).category, privacy: .public)")
    }

    // MARK: - Authorization

    nonisolated var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Asks Apple for read access. Completion neither enables sync nor implies any grant;
    /// use `connect()` for the explicit opt-in.
    func requestAuthorization() async throws {
        guard deps.isAvailable() else {
            throw HealthKitError.notAvailable
        }

        logger.info("Requesting HealthKit authorization")
        try await deps.requestPermission()
        permissionRequestState = await deps.permissionState()
        logger.info("HealthKit permission request completed")
    }

    /// Read-only status refresh: updates the permission state and may mark the account
    /// disconnected, but it NEVER reconnects.
    func checkAuthorizationStatus() async {
        guard deps.isAvailable() else {
            self.permissionRequestState = .unavailable
            return
        }
        self.permissionRequestState = await deps.permissionState()

        guard let token = await beginOperation() else { return }
        await reconcileConnection(token)
    }

    private func reconcileConnection(_ token: OperationToken) async {
        let choice = choiceSequence
        // No local decision yet: honor a disconnect recorded on the account (another device).
        if deps.optOut.isPaused(for: token.owner) == nil {
            let remote = await deps.fetchConnection(token.owner)
            guard isCurrent(token), choiceSequence == choice else { return }
            if remote == .disconnected {
                deps.optOut.setPaused(true, for: token.owner)
                syncPaused = true
            }
        }
        guard isCurrent(token), choiceSequence == choice else { return }
        // Only ever write "not connected"; connecting is an explicit action.
        guard syncPaused || !hasCompletedPermissionRequest else { return }
        do {
            try await serializedConnectionWrite { [weak self] in
                guard let self, self.choiceSequence == choice else { throw CancellationError() }
                try await self.deps.writeConnection(token.credential, false)
            }
        } catch is CancellationError {
            // A newer deliberate choice superseded this status refresh.
        } catch {
            logFailure("HealthKit status update", error)
        }
    }

    /// Explicit Connect: the only action that enables sync. The account and its credential are captured
    /// BEFORE the Apple prompt and validated after it; the account is told (serialized, and skipped if
    /// a newer Connect/Disconnect superseded this one); only then is the local opt-out cleared, and
    /// only if this is still the newest deliberate choice.
    func connect() async throws {
        guard let token = await beginOperation() else { throw HealthSyncError.signedOut }
        choiceSequence += 1
        let choice = choiceSequence
        let isStale: @MainActor () -> Bool = { [weak self] in
            guard let self else { return true }
            return !self.isCurrent(token) || self.choiceSequence != choice
        }

        try await requestAuthorization()
        guard !isStale() else { throw CancellationError() }
        guard hasCompletedPermissionRequest else { return }
        do {
            try await serializedConnectionWrite { [weak self] in
                guard let self, !isStale() else { throw CancellationError() }
                try await self.deps.writeConnection(token.credential, true)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let bounded = HealthOperationError.classify(error)
            if !isStale() {
                connectionError = bounded
                logFailure("HealthKit connect", error)
            }
            throw bounded
        }
        guard !isStale() else { throw CancellationError() }
        deps.optOut.setPaused(false, for: token.owner)
        syncPaused = false
        syncGeneration += 1
        connectionError = nil
    }

    /// Deliberate opt-out. Takes effect locally first (stopping the running and every later sync),
    /// persists per account, then tells the account. A failed acknowledgement keeps the local pause
    /// and is exposed in `connectionError` (unless a newer choice has replaced this one).
    /// Apple's permission is untouched.
    func disconnect() async {
        guard let token = await beginOperation() else { return }
        choiceSequence += 1
        let choice = choiceSequence
        deps.optOut.setPaused(true, for: token.owner)
        syncPaused = true
        syncGeneration += 1
        isSyncing = false
        connectionError = nil
        do {
            try await serializedConnectionWrite { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.deps.writeConnection(token.credential, false)
            }
        } catch {
            guard isCurrent(token), choiceSequence == choice else { return }
            logFailure("HealthKit disconnect", error)
            connectionError = HealthOperationError.classify(error)
        }
    }

    // MARK: - Data Sync

    /// The deliberate account setting is resolved BEFORE any query. It fails closed: an unreadable or
    /// missing setting never enables syncing, and setup completion alone never does either.
    private func requireSyncAllowed(_ token: OperationToken) async throws {
        if deps.optOut.isPaused(for: token.owner) == true { throw HealthSyncError.paused }
        let remote = await deps.fetchConnection(token.owner)
        guard isCurrent(token) else { throw CancellationError() }
        if syncPaused || deps.optOut.isPaused(for: token.owner) == true { throw HealthSyncError.paused }
        switch remote {
        case .connected:
            return
        case .disconnected:
            deps.optOut.setPaused(true, for: token.owner)
            syncPaused = true
            throw HealthSyncError.paused
        case .noRecord:
            throw HealthSyncError.notConnected
        case .unknown:
            throw HealthSyncError.connectionUnknown
        }
    }

    /// Runs one sync pass. A second call while a pass is running returns without doing anything.
    func syncBiometrics(days: Int = 7) async throws {
        guard let token = await beginOperation() else { throw HealthSyncError.signedOut }
        if permissionRequestState == .unknown {
            permissionRequestState = await deps.permissionState()
            guard isCurrent(token) else { throw CancellationError() }
        }
        guard hasCompletedPermissionRequest else {
            throw HealthKitError.notAuthorized
        }
        guard !syncPaused else { throw HealthSyncError.paused }
        guard !isSyncing else { return }

        isSyncing = true
        syncError = nil
        defer { if isCurrent(token) { isSyncing = false } }

        try await requireSyncAllowed(token)
        guard isSyncCurrent(token) else { throw CancellationError() }

        logger.info("Starting biometric sync for \(days) days")

        let calendar = Calendar.current
        let endDate = deps.now()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else {
            throw HealthKitError.queryFailed(NSError(domain: "HealthKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid date range"]))
        }
        let interval = DateInterval(start: startDate, end: max(endDate, startDate))

        let collection: HealthCollection
        do {
            collection = try await deps.collect(interval, requestedTypes, { [weak self] in
                self?.isSyncCurrent(token) ?? false
            })
        } catch {
            // A query error is reported as a failure, never as "no data" (and never for a stale operation).
            if isSyncCurrent(token), !(error is CancellationError) {
                lastQueryOutcome = .failed(error, interval: interval, checkedAt: deps.now())
                syncError = error
            }
            throw error
        }
        // Re-resolve the signed-in account, then check pause/owner synchronously before publishing.
        guard await ambientStillMatches(token) else { throw CancellationError() }
        guard isSyncCurrent(token) else { throw CancellationError() }

        let outcome = HealthQueryOutcome.evaluate(collection, interval: interval, checkedAt: deps.now())
        lastQueryOutcome = outcome
        guard let payload = HealthQueryOutcome.uploadPayload(collection) else {
            logger.info("Biometric sync found no recent data; nothing uploaded")
            return
        }

        // The upload is bound to the credential captured at the start of this operation.
        do {
            try await deps.upload(payload, token.credential)
        } catch {
            let bounded = HealthOperationError.classify(error)
            if isSyncCurrent(token) { syncError = bounded }
            logFailure("Biometric sync upload", error)
            throw HealthKitError.syncFailed(bounded)
        }
        guard await ambientStillMatches(token) else { throw CancellationError() }
        guard isCurrent(token) else { throw CancellationError() }
        lastSyncDate = deps.now()

        logger.info("Biometric sync complete: \(payload.dailySummaries.count) summaries, \(payload.workouts.count) workouts")
    }

    /// Live HealthKit query pass (unchanged queries; blank days are filtered by the caller).
    fileprivate func collectFromHealthKit(
        interval: DateInterval,
        types: Set<HealthKitDataType>,
        shouldContinue: @MainActor () -> Bool
    ) async throws -> HealthCollection {
        let calendar = Calendar.current
        let startDate = interval.start
        let endDate = interval.end

        var dailySummaries: [BiometricSyncPayload.DailySummaryPayload] = []
        var workouts: [BiometricSyncPayload.WorkoutPayload] = []

        // Iterate through each day
        var currentDate = startDate
        while currentDate <= endDate {
            guard shouldContinue() else { throw CancellationError() }
            let dayStart = calendar.startOfDay(for: currentDate)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }

            let dateFormatter = DateFormatter()
            dateFormatter.calendar = Calendar(identifier: .gregorian)
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = calendar.timeZone
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: dayStart)

            var summary = BiometricSyncPayload.DailySummaryPayload(date: dateString)

            // Fetch each metric type
            if types.contains(.sleep),
               let sleepData = try await fetchSleepData(from: dayStart, to: dayEnd) {
                summary = sleepData.dailySummary(for: dateString, calendar: calendar)
            }

            if types.contains(.hrv) {
                let hrvData = try await fetchHRVData(from: dayStart, to: dayEnd)
                summary.hrvAverageMs = hrvData.average
                summary.hrvMinMs = hrvData.min
                summary.hrvMaxMs = hrvData.max

                let restingHR = try await fetchRestingHeartRate(from: dayStart, to: dayEnd)
                summary.restingHeartRate = restingHR
            }

            if types.contains(.steps) {
                summary.stepsCount = try await fetchSteps(from: dayStart, to: dayEnd)
                summary.distanceMeters = try await fetchDistance(from: dayStart, to: dayEnd)
            }

            if types.contains(.activity) {
                summary.activeEnergyKcal = try await fetchActiveEnergy(from: dayStart, to: dayEnd)
                summary.exerciseMinutes = try await fetchExerciseMinutes(from: dayStart, to: dayEnd)
            }

            if types.contains(.mindful) {
                summary.mindfulMinutes = try await fetchMindfulMinutes(from: dayStart, to: dayEnd)
            }

            dailySummaries.append(summary)

            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }

        // Fetch workouts
        if types.contains(.workouts) {
            guard shouldContinue() else { throw CancellationError() }
            workouts = try await fetchWorkouts(from: startDate, to: endDate)
        }

        return HealthCollection(summaries: dailySummaries, workouts: workouts)
    }

    private static func liveDependencies(for service: HealthKitService) -> HealthKitServiceDependencies {
        struct ConnectionRow: Decodable {
            let isConnected: Bool
            enum CodingKeys: String, CodingKey { case isConnected = "is_connected" }
        }
        let writes = HealthBoundWrites.live(baseURL: SupabaseConfig.projectURL, apiKey: SupabaseConfig.anonKey)
        return HealthKitServiceDependencies(
            isAvailable: { HKHealthStore.isHealthDataAvailable() },
            permissionState: { [weak service] in
                guard let service else { return .unknown }
                // authorizationStatus(for:) only reports write/sharing status. We request read-only
                // access, so use statusForAuthorizationRequest: Apple intentionally hides per-type
                // read decisions for privacy.
                do {
                    let status = try await service.healthStore.statusForAuthorizationRequest(toShare: [], read: service.allReadTypes)
                    switch status {
                    case .unnecessary: return .completed
                    case .shouldRequest: return .requestNeeded
                    default: return .unknown
                    }
                } catch {
                    service.logger.error("HealthKit authorization status check failed")
                    return .unknown
                }
            },
            requestPermission: { [weak service] in
                guard let service else { return }
                try await service.healthStore.requestAuthorization(toShare: [], read: service.allReadTypes)
            },
            collect: { [weak service] interval, types, shouldContinue in
                guard let service else { throw CancellationError() }
                return try await service.collectFromHealthKit(interval: interval, types: types, shouldContinue: shouldContinue)
            },
            currentCredential: {
                // Owner and token come from the same session value, so they cannot disagree.
                guard let session = try? await supabase.auth.session else { return nil }
                return HealthCredential(owner: session.user.id, accessToken: session.accessToken)
            },
            fetchConnection: { owner in
                do {
                    let rows: [ConnectionRow] = try await supabase.from("healthkit_connections")
                        .select("is_connected").eq("user_id", value: owner.uuidString).limit(1).execute().value
                    guard let row = rows.first else { return .noRecord }
                    return row.isConnected ? .connected : .disconnected
                } catch {
                    return .unknown
                }
            },
            writeConnection: { credential, connected in
                try await writes.writeConnection(connected: connected, credential: credential)
            },
            upload: { payload, credential in
                try await writes.upload(payload, credential: credential)
            },
            now: { Date() },
            optOut: HealthSyncOptOut(defaults: .standard)
        )
    }

    // MARK: - Sleep Data

    private func fetchSleepData(from start: Date, to end: Date) async throws -> MeasuredSleep? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        // Read complete sessions on either side of midnight before assigning a wake day.
        let window = SleepHealthKitManager.sampleQueryWindow(wakingFrom: start, through: end)
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end)
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

        return Self.measuredSleep(from: samples, wakingFrom: start, before: end)
    }

    /// The same measured intervals feed the daily payload and chronotype input.
    struct MeasuredSleep {
        let start: Date
        let end: Date
        let asleepSeconds: TimeInterval
        let inBedSeconds: TimeInterval

        func dailySummary(for date: String, calendar: Calendar = .current) -> BiometricSyncPayload.DailySummaryPayload {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "HH:mm"
            var summary = BiometricSyncPayload.DailySummaryPayload(date: date)
            summary.sleepDurationMinutes = Int(asleepSeconds / 60)
            summary.timeInBedMinutes = Int(inBedSeconds / 60)
            summary.sleepQualityScore = min(asleepSeconds / inBedSeconds, 1)
            summary.sleepStartTime = formatter.string(from: start)
            summary.sleepEndTime = formatter.string(from: end)
            return summary
        }

        func record(for date: Date, calendar: Calendar = .current) -> SleepRecord {
            SleepRecord(date: date, startTime: start, endTime: end, duration: asleepSeconds,
                        isWeekend: calendar.isDateInWeekend(date))
        }
    }

    static func measuredSleep(from samples: [HKCategorySample], wakingFrom start: Date, before end: Date,
                              calendar: Calendar = .current) -> MeasuredSleep? {
        let daily = SleepHealthKitManager.dailySleepSamples(from: samples, wakingFrom: start,
                                                            through: end, calendar: calendar)
        // Selecting the local day also excludes a session waking exactly at the next midnight.
        guard let samples = daily[calendar.startOfDay(for: start)] else { return nil }
        let asleepValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        let asleep = samples.filter { asleepValues.contains($0.value) }
        guard let first = asleep.map(\.startDate).min(), let last = asleep.map(\.endDate).max() else { return nil }
        let durations = SleepHealthKitManager.sleepDurations(samples)
        guard durations.asleep >= 60, durations.inBed >= durations.asleep else { return nil }
        return MeasuredSleep(start: first, end: last, asleepSeconds: durations.asleep, inBedSeconds: durations.inBed)
    }

    /// Fetch sleep records from HealthKit for chronotype analysis
    /// - Parameter days: Number of days to fetch (default 30, capped at 90)
    /// - Returns: Array of SleepRecord objects with midpoint calculations
    func fetchSleepRecords(days: Int = 30) async throws -> [SleepRecord] {
        // Cap at 90 days to prevent excessive memory usage
        let cappedDays = min(days, 90)
        let calendar = Calendar.current
        let endDate = Date()
        guard let _ = calendar.date(byAdding: .day, value: -cappedDays, to: endDate) else {
            return []
        }

        var records: [SleepRecord] = []
        
        // Process day-by-day for accurate per-day records
        for dayOffset in 0..<cappedDays {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: endDate) else {
                continue
            }
            let dayStartOfDay = calendar.startOfDay(for: dayStart)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStartOfDay) else {
                continue
            }

            guard let sleepData = try await fetchSleepData(from: dayStartOfDay, to: dayEnd) else { continue }
            records.append(sleepData.record(for: dayStartOfDay, calendar: calendar))
        }

        return records.sorted(by: { $0.date < $1.date })
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

        // Samples exist -> a genuine zero is still an observed value; no samples -> nil.
        return samples.isEmpty ? nil : totalMinutes
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

extension DateFormatter {
    static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
