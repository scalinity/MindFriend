import XCTest
import struct Supabase.Session
import struct Supabase.User
import class Supabase.SupabaseClient
import protocol Supabase.AuthLocalStorage
import UserNotifications
@testable import MindFriendApp

final class DurablePathwayKeyTests: XCTestCase {
    private var keychainService: String!
    private let firstOwner = UUID()
    private let secondOwner = UUID()

    override func setUp() {
        super.setUp()
        keychainService = "app.mindfriend.tests.pathway.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        for identifier in ["legacy", firstOwner.uuidString, secondOwner.uuidString] {
            try SecureStorage(keychainService: keychainService, keyIdentifier: identifier).deleteEncryptionKey()
        }
        try super.tearDownWithError()
    }

    private func makeService(owner: UUID?) -> PathwayEncryptionService {
        let namespace = keychainService!
        return PathwayEncryptionService(
            secureStorage: SecureStorage(keychainService: namespace, keyIdentifier: "legacy"),
            userId: owner,
            storageForUser: { SecureStorage(keychainService: namespace, keyIdentifier: $0.uuidString) }
        )
    }

    func testJournalSurvivesLogoutAndServiceRecreation() throws {
        let service = makeService(owner: firstOwner)
        let ciphertext = try service.encryptString("Retained pathway journal")
        service.setCurrentUser(nil)
        XCTAssertThrowsError(try service.decryptString(ciphertext))

        let restored = makeService(owner: firstOwner)
        XCTAssertEqual(try restored.decryptString(ciphertext), "Retained pathway journal")
    }

    func testAnotherAccountCannotDecryptNewJournal() throws {
        let service = makeService(owner: firstOwner)
        let ciphertext = try service.encryptString("First account journal")
        service.setCurrentUser(secondOwner)
        XCTAssertThrowsError(try service.decryptString(ciphertext))
        let secondCiphertext = try service.encryptString("Second account journal")
        service.setCurrentUser(firstOwner)
        XCTAssertEqual(try service.decryptString(ciphertext), "First account journal")
        XCTAssertThrowsError(try service.decryptString(secondCiphertext))
    }

    func testLegacyJournalStillDecryptsAfterMemoryKeyEviction() throws {
        let legacy = SecureStorage(keychainService: keychainService, keyIdentifier: "legacy")
        let ciphertext = try legacy.encrypt("Legacy retained journal").base64EncodedString()
        legacy.clearCachedKey()
        XCTAssertEqual(try makeService(owner: firstOwner).decryptString(ciphertext), "Legacy retained journal")
    }
}

@MainActor
final class AccountBriefingIsolationTests: XCTestCase {
    func testAccountSwitchClearsBriefingAndIgnoresLatePriorAccountResult() async {
        let firstOwner = UUID(), secondOwner = UUID()
        var owner: UUID? = firstOwner
        let provider = SuspendedBriefingProvider()
        let model = DailyBriefingViewModel(briefingService: provider, calendarService: CalendarService(), currentUserId: { owner })
        let firstRequest = expectation(description: "First account request started")
        await provider.onRequest { firstRequest.fulfill() }
        let firstLoad = Task { await model.loadTodaysBriefing() }
        await fulfillment(of: [firstRequest], timeout: 2)

        owner = secondOwner
        model.resetForAccountChange(to: secondOwner)
        XCTAssertNil(model.briefing)
        XCTAssertNil(model.preferences)
        XCTAssertFalse(model.isLoading)
        let secondRequest = expectation(description: "Second account request started")
        await provider.onRequest { secondRequest.fulfill() }
        let secondLoad = Task { await model.loadTodaysBriefing() }
        await fulfillment(of: [secondRequest], timeout: 2)
        await provider.complete(1, with: Self.briefing(owner: secondOwner))
        await secondLoad.value
        await provider.complete(0, with: Self.briefing(owner: firstOwner))
        await firstLoad.value
        XCTAssertEqual(model.briefing?.userId, secondOwner)
        XCTAssertFalse(model.isLoading)
        await model.loadTodaysBriefing()
        let count = await provider.requestCount
        XCTAssertEqual(count, 2, "Only this account's same-day successful result may be reused")
    }

    func testSignOutInvalidatesInFlightBriefing() async {
        let firstOwner = UUID()
        var owner: UUID? = firstOwner
        let provider = SuspendedBriefingProvider()
        let model = DailyBriefingViewModel(briefingService: provider, calendarService: CalendarService(), currentUserId: { owner })
        let requested = expectation(description: "Request started")
        await provider.onRequest { requested.fulfill() }
        let load = Task { await model.loadTodaysBriefing() }
        await fulfillment(of: [requested], timeout: 2)
        owner = nil
        model.resetForAccountChange(to: nil)
        await provider.complete(0, with: Self.briefing(owner: firstOwner))
        await load.value
        XCTAssertNil(model.briefing)
        XCTAssertNil(model.preferences)
        XCTAssertFalse(model.isLoading)
    }

    private static func briefing(owner: UUID) -> DailyBriefing {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return DailyBriefing(id: UUID(), userId: owner, localDate: formatter.string(from: Date()),
                             greeting: "Fixture", predictedMood: nil, moodContext: nil, questId: nil,
                             questTitle: nil, calendarEvents: [], suggestion: "Fixture", generatedAt: Date(),
                             lastViewedAt: nil, wellnessScore: nil, importantDates: nil, audioText: nil,
                             audioUrl: nil, voicePlayed: nil)
    }
}

private actor SuspendedBriefingProvider: DailyBriefingProviding {
    private var pending: [Int: CheckedContinuation<DailyBriefing?, Error>] = [:]
    private var didRequest: (() -> Void)?
    private(set) var requestCount = 0

    func onRequest(_ action: @escaping () -> Void) { didRequest = action }
    func fetchTodaysBriefing() async throws -> DailyBriefing? {
        let request = requestCount
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[request] = continuation
            didRequest?()
        }
    }
    func complete(_ request: Int, with briefing: DailyBriefing) {
        pending.removeValue(forKey: request)?.resume(returning: briefing)
    }
    func generateBriefing(localDate: String, timezone: String, calendarEvents: [BriefingCalendarEvent]) async throws -> DailyBriefing {
        throw CancellationError()
    }
    func markViewed(briefingId: UUID) async throws { }
    func fetchPreferences() async throws -> BriefingPreferences { .default }
    func updatePreferences(_ preferences: BriefingPreferences) async throws { }
}

@MainActor
final class LocalLogoutCompletionTests: XCTestCase {
    private enum FixtureError: Error { case remoteUnavailable, localRemovalFailed }

    func testRemoteFailureStillRemovesCredentialsAndAwaitsCleanup() async throws {
        var events: [String] = []
        let remoteFailed = try await SupabaseAuthService.finishLogout(
            revokeRemote: { events.append("remote"); throw FixtureError.remoteUnavailable },
            removeLocalCredentials: { events.append("credentials") },
            cleanup: { await Task.yield(); events.append("cleanup") }
        )
        XCTAssertTrue(remoteFailed)
        XCTAssertEqual(events, ["remote", "credentials", "cleanup"])
    }

    func testLocalCredentialFailureCannotReturnLogoutSuccess() async {
        var cleanupRan = false
        do {
            _ = try await SupabaseAuthService.finishLogout(
                revokeRemote: { },
                removeLocalCredentials: { throw FixtureError.localRemovalFailed },
                cleanup: { cleanupRan = true }
            )
            XCTFail("Local credential removal failure must remain visible")
        } catch FixtureError.localRemovalFailed { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(cleanupRan, "Keep the active UI until local credentials are actually removed")
    }

    func testConfirmedRevocationWaitsForLocalCleanup() async throws {
        var cleanupRan = false
        let remoteFailed = try await SupabaseAuthService.finishLogout(
            revokeRemote: { }, removeLocalCredentials: { },
            cleanup: { await Task.yield(); cleanupRan = true }
        )
        XCTAssertFalse(remoteFailed)
        XCTAssertTrue(cleanupRan)
    }
}

@MainActor
final class AmbientAccountLifecycleTests: XCTestCase {
    func testLatePreviousAccountStartCannotReplaceNewTheme() async {
        let first = UUID(), second = UUID()
        let provider = SuspendedAmbientProvider(owner: first)
        let service = AmbientThemeService(dataProvider: provider)
        let firstRequested = expectation(description: "First preferences requested")
        provider.didRequest = { firstRequested.fulfill() }
        let firstStart = Task { await service.start() }
        await fulfillment(of: [firstRequested], timeout: 2)
        provider.currentUserId = second
        service.resetForAccountChange(to: second)
        XCTAssertFalse(service.isMonitoring)
        let secondRequested = expectation(description: "Second preferences requested")
        provider.didRequest = { secondRequested.fulfill() }
        let secondStart = Task { await service.start() }
        await fulfillment(of: [secondRequested], timeout: 2)
        provider.complete(1, owner: second, theme: .forest)
        await secondStart.value
        provider.complete(0, owner: first, theme: .ocean)
        await firstStart.value
        XCTAssertEqual(service.selectedTheme, .forest)
        XCTAssertTrue(service.isMonitoring)
        provider.currentUserId = nil
        service.resetForAccountChange(to: nil)
        XCTAssertFalse(service.isMonitoring)
        XCTAssertEqual(service.selectedTheme, .auto)
    }

    func testLateStartAfterLogoutCannotRestartMonitoring() async {
        let owner = UUID()
        let provider = SuspendedAmbientProvider(owner: owner)
        let service = AmbientThemeService(dataProvider: provider)
        let requested = expectation(description: "Preferences requested")
        provider.didRequest = { requested.fulfill() }
        let start = Task { await service.start() }
        await fulfillment(of: [requested], timeout: 2)
        provider.currentUserId = nil
        service.resetForAccountChange(to: nil)
        provider.complete(0, owner: owner, theme: .ocean)
        await start.value
        XCTAssertFalse(service.isMonitoring)
        XCTAssertEqual(service.selectedTheme, .auto)
    }
}

@MainActor
private final class SuspendedAmbientProvider: AmbientDataProviding {
    var currentUserId: UUID?
    var didRequest: (() -> Void)?
    private var nextRequest = 0
    private var pending: [Int: CheckedContinuation<AmbientPreferences?, Error>] = [:]
    init(owner: UUID) { currentUserId = owner }
    func fetchAmbientPreferences() async throws -> AmbientPreferences? {
        let request = nextRequest
        nextRequest += 1
        return try await withCheckedThrowingContinuation {
            pending[request] = $0
            didRequest?()
        }
    }
    func upsertAmbientPreferences(_ preferences: AmbientPreferences) async throws { }
    func complete(_ request: Int, owner: UUID, theme: AmbientTheme) {
        pending.removeValue(forKey: request)?.resume(returning: AmbientPreferences(
            userId: owner, activeTheme: theme, backgroundType: .dynamic,
            autoAdjustEnabled: false, createdAt: Date(), updatedAt: Date()
        ))
    }
}

/// Tests for SupabaseAuthService authentication flows
/// Session fixtures do not initialize the shared client or read device credentials.
final class SupabaseAuthServiceTests: XCTestCase {
    
    // MARK: - Session Management Tests
    
    func testValidatedSession_WhenSDKCannotReadSession_ThrowsSessionUnavailable() {
        let signedIn = makeSession()

        assertSessionUnavailable(nil, expectedUserId: signedIn.user.id)
    }

    func testValidatedSession_WhenStoredUserDiffers_ThrowsSessionUnavailable() {
        assertSessionUnavailable(makeSession(), expectedUserId: UUID())
    }

    func testValidatedSession_WhenAccessTokenIsEmpty_ThrowsSessionUnavailable() {
        let stored = makeSession(accessToken: "")
        assertSessionUnavailable(stored, expectedUserId: stored.user.id)
    }

    func testValidatedSession_WhenExpiredOrInsideSDKExpiryBuffer_ThrowsSessionUnavailable() {
        for lifetime: TimeInterval in [-60, 10] {
            let stored = makeSession(expiresIn: lifetime)
            assertSessionUnavailable(stored, expectedUserId: stored.user.id)
        }
    }

    func testValidatedSession_WhenReadableAndValid_ReturnsStoredSession() throws {
        let stored = makeSession()

        let validated = try SupabaseAuthService.validatedSession(stored, expectedUserId: stored.user.id)

        XCTAssertEqual(validated, stored)
    }

    func testValidatedSession_WhenSameUserTokenRotates_AcceptsCurrentSDKSession() throws {
        let signedIn = makeSession()
        var refreshed = signedIn
        refreshed.accessToken = "synthetic-refreshed-access-token"
        refreshed.refreshToken = "synthetic-refreshed-refresh-token"
        refreshed.expiresAt += 3600

        let validated = try SupabaseAuthService.validatedSession(refreshed, expectedUserId: signedIn.user.id)

        XCTAssertEqual(validated, refreshed)
    }
    
    // MARK: - Input Validation Tests
    
    func testHandleValidation_ValidHandle_Passes() async {
        // Valid handles: lowercase letters, numbers, underscores, 3-30 chars
        let validHandles = ["user_123", "john_doe", "a1b2c3", "abc", "a".padding(toLength: 30, withPad: "b", startingAt: 0)]
        
        for handle in validHandles {
            let isValid = isValidHandle(handle)
            XCTAssertTrue(isValid, "Handle '\(handle)' should be valid")
        }
    }
    
    func testHandleValidation_InvalidHandle_Fails() async {
        // Invalid handles: too short, too long, uppercase, special chars
        let invalidHandles = [
            "ab",           // Too short
            "AB_CD",        // Uppercase
            "user-name",    // Hyphen not allowed
            "user.name",    // Period not allowed
            "user name",    // Space not allowed
            "user@name",    // Special char
            String(repeating: "a", count: 31)  // Too long
        ]
        
        for handle in invalidHandles {
            let isValid = isValidHandle(handle)
            XCTAssertFalse(isValid, "Handle '\(handle)' should be invalid")
        }
    }
    
    // MARK: - Error Type Tests
    
    func testAuthError_ErrorDescriptions_AreUserFriendly() {
        // Verify all auth errors have user-friendly descriptions
        let errors: [AuthError] = [
            .invalidCredentials,
            .missingIdToken,
            .emailConfirmationRequired,
            .userNotFound,
            .accountNotFound,
            .sessionExpired,
            .sessionUnavailable,
            .profileUnavailable,
            .handleTaken,
            .invalidHandle,
            .unknown("Test error")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
        }
    }
    
    func testAuthError_InvalidCredentials_HasCorrectMessage() {
        let error = AuthError.invalidCredentials
        XCTAssertEqual(error.errorDescription, "Incorrect email or password. Please try again.")
    }
    
    func testAuthError_EmailConfirmationRequired_HasCorrectMessage() {
        let error = AuthError.emailConfirmationRequired
        XCTAssertEqual(error.errorDescription, "Please check your email to confirm your account")
    }
    
    func testAuthError_SessionExpired_HasCorrectMessage() {
        let error = AuthError.sessionExpired
        XCTAssertEqual(error.errorDescription, "Your session has expired. Please sign in again")
    }
    
    func testAuthError_SessionUnavailable_DoesNotClaimAccountIsMissing() {
        XCTAssertEqual(
            AuthError.sessionUnavailable.errorDescription,
            "Unable to keep you signed in. Please try signing in again."
        )
    }

    func testAuthError_ProfileUnavailableOffersRetryWithoutAccountClaim() {
        XCTAssertEqual(AuthError.profileUnavailable.errorDescription,
                       "We couldn't load your profile. Check your connection and try again.")
    }
    
    // MARK: - Helper Functions

    private func assertSessionUnavailable(_ stored: Session?, expectedUserId: UUID) {
        do {
            _ = try SupabaseAuthService.validatedSession(stored, expectedUserId: expectedUserId)
            XCTFail("Expected session unavailable")
        } catch AuthError.sessionUnavailable {
        } catch {
            XCTFail("Expected session unavailable, got \(error)")
        }
    }

    private func makeSession(accessToken: String = "synthetic-access-token", expiresIn: TimeInterval = 3600) -> Session {
        let now = Date()
        let user = User(
            id: UUID(),
            appMetadata: [:],
            userMetadata: [:],
            aud: "authenticated",
            createdAt: now,
            role: "authenticated",
            updatedAt: now
        )
        return Session(
            accessToken: accessToken,
            tokenType: "bearer",
            expiresIn: expiresIn,
            expiresAt: now.timeIntervalSince1970 + expiresIn,
            refreshToken: "synthetic-refresh-token",
            user: user
        )
    }
    
    private func isValidHandle(_ handle: String) -> Bool {
        let normalizedHandle = handle.lowercased().trimmingCharacters(in: .whitespaces)
        let handleRegex = /^[a-z0-9_]{3,30}$/
        return normalizedHandle.wholeMatch(of: handleRegex) != nil
    }
}

// MARK: - Mock Helpers (for future expansion)

/// Mock profile for testing
extension SupabaseAuthServiceTests {
    struct MockProfile {
        let id: String
        let handle: String
        let displayName: String
        let email: String?
        
        static let testUser = MockProfile(
            id: "test-user-id",
            handle: "test_user",
            displayName: "Test User",
            email: "test@example.com"
        )
    }
}

// These account-switch regressions use isolated in-memory credentials and intercepted
// requests. No real session, calendar permission, or notification center is touched.
@MainActor
final class AccountMonitoringLifecycleTests: XCTestCase {
    private let ownerA = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let ownerB = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    private func client(owner: UUID) throws -> (SupabaseClient, MonitoringFixtureStorage) {
        let storage = MonitoringFixtureStorage()
        try storage.setOwner(owner)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MonitoringFixtureURLProtocol.self]
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://monitoring-fixture.invalid")!, supabaseKey: "synthetic-anon",
            options: .init(auth: .init(storage: storage, storageKey: "monitoring-fixture-auth", autoRefreshToken: false),
                           global: .init(session: URLSession(configuration: configuration))))
        return (client, storage)
    }

    private func preferences(owner: UUID, enabled: Bool) -> String {
        """
        [{"id":"33333333-3333-4333-8333-333333333333","user_id":"\(owner)","enabled":\(enabled),"max_daily":5,"quiet_hours_start":null,"quiet_hours_end":null,"created_at":"2026-11-06T12:00:00Z","updated_at":"2026-11-06T12:00:00Z"}]
        """
    }

    private func interventionService(_ client: SupabaseClient) -> InterventionService {
        InterventionService(supabase: client, calendarMonitor: CalendarTriggerMonitor(supabase: client),
                            timingAnalyzer: OptimalTimingAnalyzer(supabase: client),
                            notificationManager: InterventionNotificationManager(notificationCenter: MonitoringFixtureNotificationCenter()))
    }

    func testLateEnabledAccountCannotRestartMonitoringForDisabledAccount() async throws {
        let (client, storage) = try client(owner: ownerA)
        let service = interventionService(client)
        let requested = expectation(description: "A preferences request")
        MonitoringFixtureURLProtocol.fixture.prepare(body: preferences(owner: ownerA, enabled: true), hold: true) { requested.fulfill() }
        let pending = Task { try await service.startMonitoring() }
        await fulfillment(of: [requested], timeout: 2)
        try storage.setOwner(ownerB)
        service.resetForAccountChange(to: ownerB)
        MonitoringFixtureURLProtocol.fixture.release()
        do { try await pending.value; XCTFail("Old account load must be cancelled") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(service.preferences)
        XCTAssertFalse(service.isMonitoring)

        MonitoringFixtureURLProtocol.fixture.prepare(body: preferences(owner: ownerB, enabled: false))
        try await service.startMonitoring()
        XCTAssertEqual(service.preferences?.userId, ownerB)
        XCTAssertEqual(service.preferences?.enabled, false)
        XCTAssertFalse(service.isMonitoring)
        service.resetForAccountChange(to: nil)
        XCTAssertNil(service.preferences)
        XCTAssertTrue(service.recentDeliveries.isEmpty)
        XCTAssertNil(service.pendingIntervention)
    }

    func testFailedPreferenceReadDoesNotEnableDefaultMonitoring() async throws {
        let (client, _) = try client(owner: ownerA)
        let service = interventionService(client)
        MonitoringFixtureURLProtocol.fixture.prepare(body: "{\"message\":\"Synthetic unavailable\"}", status: 500)
        do { try await service.startMonitoring(); XCTFail("Read failure must remain a failure") }
        catch { }
        XCTAssertNil(service.preferences)
        XCTAssertFalse(service.isMonitoring)
    }

    func testCalendarCacheLoadsNewAccountSelectionBeforeReturningCachedValue() async throws {
        let (client, storage) = try client(owner: ownerA)
        let monitor = CalendarTriggerMonitor(supabase: client)
        func configuration(owner: UUID, calendar: String) -> String {
            """
            [{"id":"33333333-3333-4333-8333-333333333333","user_id":"\(owner)","trigger_type":"calendar","trigger_config":{"enabled_calendar_ids":["\(calendar)"],"needs_armor_event_ids":[],"lead_time_minutes":45,"min_stress_score":0.7},"is_active":true,"priority":100,"created_at":"2026-11-06T12:00:00Z","updated_at":"2026-11-06T12:00:00Z"}]
            """
        }
        MonitoringFixtureURLProtocol.fixture.prepare(body: configuration(owner: ownerA, calendar: "calendar-a"))
        let first = try await monitor.getTriggerConfig()
        XCTAssertEqual(first.enabledCalendarIds, ["calendar-a"])
        try storage.setOwner(ownerB)
        // Deliberately omit explicit reset: the read must validate owner before cache access.
        MonitoringFixtureURLProtocol.fixture.prepare(body: configuration(owner: ownerB, calendar: "calendar-b"))
        let second = try await monitor.getTriggerConfig()
        XCTAssertEqual(second.enabledCalendarIds, ["calendar-b"])
        XCTAssertEqual(MonitoringFixtureURLProtocol.fixture.requestCount, 1)
        try storage.setOwner(nil)
        do { _ = try await monitor.getTriggerConfig(); XCTFail("Signed out cache must not be returned") }
        catch { XCTAssertTrue(error is AuthError) }
    }

    // Captured from the actual analyze-intervention-patterns handler with two
    // synthetic completed deliveries. The endpoint supplies no timestamp.
    private var timingAnalysisResponseJSON: String {
        #"{"hourlyConfidence":{"9":{"completionRate":1,"avgRating":5,"dismissRate":0,"confidence":0.47,"sampleCount":2}},"sampleCount":2,"minimumDataMet":true,"windowDays":90}"#
    }

    func testTimingAnalysisUsesEndpointPayloadAndPersistsForCurrentOwner() async throws {
        let (client, _) = try client(owner: ownerA)
        let analyzer = OptimalTimingAnalyzer(supabase: client)
        MonitoringFixtureURLProtocol.fixture.prepare(body: timingAnalysisResponseJSON)
        let beforeReceipt = Date()
        let result = try await analyzer.analyzePatterns()
        let afterReceipt = Date()
        XCTAssertEqual(result.sampleCount, 2)
        XCTAssertTrue(result.minimumDataMet)
        XCTAssertEqual(result.hourlyConfidence[9]?.completionRate, 1)
        XCTAssertEqual(result.hourlyConfidence[9]?.avgRating, 5)
        XCTAssertEqual(result.hourlyConfidence[9]?.dismissRate, 0)
        XCTAssertEqual(result.hourlyConfidence[9]?.sampleCount, 2)
        XCTAssertEqual(analyzer.getConfidenceBoost(for: 9), 0.47, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(result.lastUpdated, beforeReceipt)
        XCTAssertLessThanOrEqual(result.lastUpdated, afterReceipt)

        let requests = MonitoringFixtureURLProtocol.fixture.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.first?.url?.path, "/functions/v1/analyze-intervention-patterns")
        let persisted = try XCTUnwrap(requests.last)
        XCTAssertEqual(persisted.httpMethod, "PATCH")
        XCTAssertEqual(persisted.url?.path, "/rest/v1/intervention_preferences")
        let query = URLComponents(url: try XCTUnwrap(persisted.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "user_id" }?.value?.lowercased(), "eq.\(ownerA.uuidString.lowercased())")
        _ = try await analyzer.analyzePatterns()
        XCTAssertEqual(MonitoringFixtureURLProtocol.fixture.requestCount, 2, "Current-owner cache should avoid another request")
    }

    func testLateTimingAnalysisCannotPopulateOrPersistAfterAccountSwitch() async throws {
        let (client, storage) = try client(owner: ownerA)
        let analyzer = OptimalTimingAnalyzer(supabase: client)
        let requested = expectation(description: "A timing analysis request")
        MonitoringFixtureURLProtocol.fixture.prepare(body: timingAnalysisResponseJSON, hold: true) { requested.fulfill() }
        let pending = Task { try await analyzer.analyzePatterns() }
        await fulfillment(of: [requested], timeout: 2)
        try storage.setOwner(ownerB)
        analyzer.resetForAccountChange(to: ownerB)
        MonitoringFixtureURLProtocol.fixture.release()
        do { _ = try await pending.value; XCTFail("Old timing result must be cancelled") }
        catch { XCTAssertTrue(error is CancellationError, "Expected stale-owner cancellation, received \(String(reflecting: error))") }
        XCTAssertEqual(analyzer.getConfidenceBoost(for: 9), 0)
        XCTAssertTrue(analyzer.getBestHours().isEmpty)
        XCTAssertEqual(MonitoringFixtureURLProtocol.fixture.requestCount, 1, "Old analysis must not be persisted")
    }
}

private final class MonitoringFixtureStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.lock(); defer { lock.unlock() }; values[key] = value }
    func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func remove(key: String) throws { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: key) }
    func setOwner(_ owner: UUID?) throws {
        guard let owner else { try remove(key: "monitoring-fixture-auth"); return }
        let now = Date()
        let user = User(id: owner, appMetadata: [:], userMetadata: [:], aud: "authenticated", createdAt: now, role: "authenticated", updatedAt: now)
        let session = Session(accessToken: "synthetic-access-\(owner)", tokenType: "bearer", expiresIn: 3600,
                              expiresAt: now.timeIntervalSince1970 + 3600, refreshToken: "synthetic-refresh-\(owner)", user: user)
        try store(key: "monitoring-fixture-auth", value: JSONEncoder().encode(session))
    }
}

private final class MonitoringHTTPFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var body = "[]"
    private var status = 200
    private var holding = false
    private var pending: (() -> Void)?
    private var onRequest: (() -> Void)?
    private var count = 0
    private var observedRequests: [URLRequest] = []
    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return observedRequests }
    func prepare(body: String, status: Int = 200, hold: Bool = false, onRequest: (() -> Void)? = nil) {
        lock.lock(); defer { lock.unlock() }
        self.body = body; self.status = status; holding = hold; self.onRequest = onRequest; count = 0
        observedRequests = []
    }
    func receive(_ connection: MonitoringFixtureURLProtocol) {
        lock.lock()
        let body = body, status = status, callback = onRequest
        count += 1
        observedRequests.append(connection.request)
        let reply = {
            let response = HTTPURLResponse(url: connection.request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            connection.client?.urlProtocol(connection, didReceive: response, cacheStoragePolicy: .notAllowed)
            connection.client?.urlProtocol(connection, didLoad: Data(body.utf8))
            connection.client?.urlProtocolDidFinishLoading(connection)
        }
        let hold = holding
        if hold { pending = reply }
        lock.unlock()
        callback?()
        if !hold { reply() }
    }
    func release() {
        lock.lock(); let reply = pending; pending = nil; holding = false; lock.unlock()
        reply?()
    }
}

private final class MonitoringFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    static let fixture = MonitoringHTTPFixture()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.fixture.receive(self) }
    override func stopLoading() { }
}

@MainActor
private final class MonitoringFixtureNotificationCenter: InterventionNotificationCenter {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { false }
    func authorizationStatus() async -> UNAuthorizationStatus { .denied }
    func add(_ request: UNNotificationRequest) async throws { XCTFail("No real notification should be scheduled") }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { [] }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) { }
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) { }
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) { }
    func setBadgeCount(_ newBadgeCount: Int) async throws { }
}
