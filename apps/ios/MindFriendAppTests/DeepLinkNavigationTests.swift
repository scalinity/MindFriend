import XCTest
#if canImport(MindFriendApp)
@testable import MindFriendApp
import Supabase
#endif

@MainActor
final class DeepLinkNavigationTests: XCTestCase {
    private let id = "B4498A22-4674-4DC1-B874-D00B7F8D14A1"

    func testEveryRouteRoundTripsThroughURLParser() throws {
        let router = DeepLinkRouter()
        let routes: [DeepLinkRoute] = [
            .home, .chat(), .chat(conversationId: id), .circles(), .circles(circleId: id),
            .profile, .settings, .mood, .moodHistory, .quest(), .quest(questId: id),
            .streak, .progress, .breathing, .meditation, .exercise(exerciseId: id),
            .exerciseLibrary, .programs, .therapeuticPrograms, .program(programId: id),
            .journal, .microMoments(), .microMoments(templateId: id), .sleep(),
            .sleep(contentId: id), .quote, .assessment(), .assessment(code: "PHQ9"),
            .buddy(code: "VALID123"), .insights, .achievements
        ]
        for route in routes {
            XCTAssertEqual(router.parseURL(try XCTUnwrap(route.url)), route)
        }
        XCTAssertNil(DeepLinkRoute.unknown.url)
        XCTAssertNil(router.parseURL(try XCTUnwrap(URL(string: "https://example.invalid/chat/\(id)"))))
    }

    func testMalformedIdentifiersAreRejectedWithoutOpeningACollection() throws {
        let router = DeepLinkRouter()
        for host in ["chat", "circle", "quest", "exercise", "program", "micro", "sleep", "assessment", "buddy"] {
            let url = try XCTUnwrap(URL(string: "mindfriend://\(host)/bad%20identifier"))
            XCTAssertEqual(router.parseURL(url), .unknown, host)
        }
        XCTAssertEqual(router.parseURL(try XCTUnwrap(URL(string: "mindfriend://chat/\(id)/extra"))), .unknown)
        XCTAssertEqual(router.parseURL(try XCTUnwrap(URL(string: "mindfriend://assessment/phq9"))), .assessment(code: "PHQ9"))
        XCTAssertEqual(router.parseURL(try XCTUnwrap(URL(string: "mindfriend://breathe"))), .breathing)
        XCTAssertEqual(router.parseURL(try XCTUnwrap(URL(string: "mindfriend://exercise/meditation"))), .meditation)
    }

    func testNotificationMappingUsesTheSameIdentifierValidation() {
        let router = DeepLinkRouter()
        let mappings: [(NotificationDeepLink, DeepLinkRoute)] = [
            (.quest(id: id), .quest(questId: id)), (.quest(), .quest()),
            (.chat(conversationId: id), .chat(conversationId: id)),
            (.circle(id: id), .circles(circleId: id)), (.mood, .mood),
            (.settings, .settings), (.insights, .insights),
            (.buddy(code: "VALID123"), .buddy(code: "VALID123")),
            (.micro(templateId: id), .microMoments(templateId: id)),
            (.sleep(contentId: id), .sleep(contentId: id)), (.sleep(), .sleep())
        ]
        for (notification, expected) in mappings {
            XCTAssertEqual(router.route(for: notification), expected)
        }
        XCTAssertNil(router.route(for: .none))
        XCTAssertEqual(router.route(for: .chat(conversationId: "invalid")), .unknown)
        XCTAssertEqual(router.route(for: .chat(conversationId: "")), .unknown)
        XCTAssertEqual(router.route(for: .sleep(contentId: "")), .unknown)
        XCTAssertEqual(router.route(for: .micro(templateId: "invalid")), .unknown)
        XCTAssertEqual(router.route(for: .sleep(contentId: "invalid")), .unknown)
    }

    func testPendingAuthenticatedRouteReplaysAfterLogin() throws {
        let router = DeepLinkRouter()
        let appState = AppState()
        appState.authState = .unauthenticated
        let route = DeepLinkRoute.chat(conversationId: id)
        router.handleRoute(route, appState: appState)
        XCTAssertNil(router.requestForPresentation(isAuthenticated: false))
        XCTAssertEqual(router.pendingRoute, route)
        appState.authState = .authenticated
        let request = try XCTUnwrap(router.requestForPresentation(isAuthenticated: appState.authState == .authenticated))
        XCTAssertEqual(request.route, route)
        XCTAssertTrue(router.consume(request))
        XCTAssertNil(router.pendingRoute)
    }

    func testPendingRouteDoesNotExpireBeforeAViewConsumesIt() async throws {
        let router = DeepLinkRouter()
        router.handleRoute(.mood, appState: AppState())
        let request = try XCTUnwrap(router.pendingRequest)
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(router.pendingRequest, request)
    }

    func testNewerPendingRouteSurvivesAnOlderConsumer() throws {
        let router = DeepLinkRouter()
        let appState = AppState()
        router.handleRoute(.mood, appState: appState)
        let older = try XCTUnwrap(router.pendingRequest)
        router.handleRoute(.sleep(contentId: id), appState: appState)
        let newer = try XCTUnwrap(router.pendingRequest)
        XCTAssertFalse(router.consume(older))
        router.dismiss(older)
        XCTAssertEqual(router.pendingRequest, newer)
        XCTAssertTrue(router.consume(newer))
    }

    func testRepeatedRoutesHaveSeparateConsumptionAndDismissal() throws {
        let router = DeepLinkRouter()
        let appState = AppState()
        router.handleRoute(.mood, appState: appState)
        let first = try XCTUnwrap(router.pendingRequest)
        XCTAssertTrue(router.consume(first))
        XCTAssertFalse(router.consume(first))
        router.handleRoute(.mood, appState: appState)
        let second = try XCTUnwrap(router.pendingRequest)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(router.consume(first))
        router.dismiss(first)
        XCTAssertEqual(router.pendingRequest, second)
        XCTAssertTrue(router.consume(second))
        router.dismiss(second)
        XCTAssertNil(router.pendingRequest)
        XCTAssertNotEqual(router.requestID, second.id)
    }

    func testUnavailableItemNeverFallsBackToAnotherUsersRecord() throws {
        struct Item: Identifiable { let id: String }
        let accessible = Item(id: id)
        let inaccessibleID = "9A456A48-6334-4DF7-B413-656163705C0F"
        XCTAssertEqual(try DeepLinkRouter.linkedItem(id: id.lowercased(), in: [accessible]).id, id)
        for (identifier, items) in [(inaccessibleID, [accessible]), (id, [Item]()), ("invalid", [accessible])] {
            do {
                _ = try DeepLinkRouter.linkedItem(id: identifier, in: items)
                XCTFail("Inaccessible destination was accepted")
            } catch {
                XCTAssertEqual(error as? DeepLinkRouter.DestinationError, .unavailable)
            }
        }
    }

    func testLogoutClearsPendingAndInvalidatesInFlightDestinations() throws {
        let router = DeepLinkRouter()
        let appState = AppState()
        router.handleRoute(.chat(conversationId: id), appState: appState)
        let request = try XCTUnwrap(router.pendingRequest)
        appState.setUnauthenticated()
        router.clearNavigationState()
        XCTAssertNil(router.pendingRoute)
        XCTAssertNotEqual(router.requestID, request.id)
        XCTAssertFalse(router.consume(request))
        XCTAssertNil(router.requestForPresentation(isAuthenticated: true))
    }

    func testEnqueueDoesNotSelectAnAbsentProgressiveDisclosureTab() {
        let router = DeepLinkRouter()
        let appState = AppState()
        appState.selectedTab = .home
        for route: DeepLinkRoute in [.programs, .program(programId: id), .progress, .assessment(code: "PHQ9")] {
            router.handleRoute(route, appState: appState)
            XCTAssertEqual(appState.selectedTab, .home)
            XCTAssertEqual(router.pendingRoute, route)
        }
        XCTAssertEqual(router.tabForRoute(.exerciseLibrary), .home)
        XCTAssertEqual(router.tabForRoute(.progress), .outcomes)
        XCTAssertEqual(router.tabForRoute(.assessment()), .outcomes)
    }

    func testOnboardingCompletionMakesPendingLinkReadyAndInitializesEntitlements() throws {
        let router = DeepLinkRouter()
        let state = AppState()
        state.requireOnboarding()
        router.handleRoute(.sleep(contentId: id), appState: state)
        let request = try XCTUnwrap(router.pendingRequest)
        XCTAssertFalse(state.sessionRestored)

        state.completeOnboarding(user: profile(tier: "premium"))

        XCTAssertEqual(state.authState, .authenticated)
        XCTAssertTrue(state.sessionRestored)
        XCTAssertTrue(state.hasCompletedInitialAuth)
        XCTAssertFalse(state.isUsingCachedData)
        XCTAssertEqual(state.entitlements.tier, .premium)
        XCTAssertEqual(router.requestForPresentation(isAuthenticated: state.authState == .authenticated && state.sessionRestored), request)
        XCTAssertTrue(router.consume(request))
    }

    func testVerifiedProfileReplacesDefaultAndPreviousAccountEntitlements() {
        let state = AppState()
        XCTAssertEqual(state.entitlements.tier, .free)
        state.setAuthenticated(user: profile(tier: "premium"))
        XCTAssertEqual(state.entitlements.tier, .premium)
        state.setAuthenticated(user: profile(tier: "free", userID: UUID()))
        XCTAssertEqual(state.entitlements.tier, .free)
        state.setUnauthenticated()
        XCTAssertFalse(state.sessionRestored)
        XCTAssertEqual(state.entitlements.tier, .free)
    }

    func testSponsoredVerifiedProfileUsesPremiumMapping() throws {
        let userID = try XCTUnwrap(UUID(uuidString: id))
        let row = DBProfileRow(
            id: userID, handle: "synthetic", displayName: "Synthetic", email: nil,
            avatarUrl: nil, timezone: "America/New_York", subscriptionTier: "free",
            dailyAiQuota: 30, dailyAiUsed: 0, quotaResetAt: nil, premiumBadge: nil,
            wellnessFocus: nil, onboardingCompletedAt: Date(), createdAt: Date(), updatedAt: Date()
        )
        let settings = DBUserSettingsRow(
            userId: userID, dailyQuestTimeLocal: "09:00", quietHoursStartLocal: nil,
            quietHoursEndLocal: nil, remindersEnabled: false, nudgeAfterDaysInactive: 3,
            shareMoodInCircles: false, aiTone: "friendly", privacyMode: "standard"
        )
        let stats = DBUserStatsRow(
            userId: userID, currentStreakDays: 0, longestStreakDays: 0,
            totalQuestsCompleted: 0, totalExercisesCompleted: 0, lastQuestDate: nil,
            xpTotal: 0, xpThisWeek: 0, level: 1, levelTitle: "Beginning", lastXpResetWeek: nil
        )
        let state = AppState()
        state.setAuthenticated(user: row.toUserProfile(settings: settings, stats: stats, hasSponsoredAccess: true))
        XCTAssertEqual(state.entitlements.tier, .premium)
        state.setAuthenticated(user: row.toUserProfile(settings: settings, stats: stats, hasSponsoredAccess: false))
        XCTAssertEqual(state.entitlements.tier, .free)
    }

    func testURLRoleAndTierCannotGrantPremium() throws {
        let state = AppState()
        state.setAuthenticated(user: profile(tier: "free"))
        let router = DeepLinkRouter()
        router.handleURL(try XCTUnwrap(URL(string: "mindfriend://sleep/\(id)?role=owner&tier=premium")), appState: state)
        XCTAssertEqual(router.pendingRoute, .sleep(contentId: id))
        XCTAssertEqual(state.entitlements.tier, .free)
    }

    func testMissingAndDeniedRowsAreUnavailableWhileNetworkFailuresRemainRetryable() {
        for code in ["PGRST116", "42501"] {
            let error = PostgrestError(code: code, message: "Synthetic unavailable row")
            XCTAssertEqual(DeepLinkRouter.destinationError(for: error), .unavailable)
        }
        XCTAssertNil(DeepLinkRouter.destinationError(for: URLError(.notConnectedToInternet)))
        XCTAssertNil(DeepLinkRouter.destinationError(for: URLError(.timedOut)))
        XCTAssertNil(DeepLinkRouter.destinationError(for: PostgrestError(code: "08006", message: "Connection failure")))
        XCTAssertEqual(DeepLinkRouter.destinationError(for: DeepLinkRouter.DestinationError.premium), .premium)
    }

    func testFirstRunCannotBypassOnboardingViaSignInOrCachedProfile() throws {
        let data = Data("{\"id\":\"B4498A22-4674-4DC1-B874-D00B7F8D14A1\"}".utf8)
        let firstRun = try JSONDecoder().decode(UserProfile.self, from: data)
        let state = AppState()
        state.setAuthenticated(user: firstRun)
        XCTAssertEqual(state.authState, .onboarding)
        state.setAuthenticatedFromCache(user: firstRun)
        XCTAssertEqual(state.authState, .onboarding)
    }

    func testProfileAndTierRefreshCannotResetConfirmedUsage() {
        let state = AppState()
        let user = profile(tier: "free")
        state.setAuthenticated(user: user)
        XCTAssertNil(state.entitlementSnapshot?.usage)
        state.recordChatQuota(ownerID: user.id, used: 4, limit: 30, countedOn: nil)
        state.setAuthenticated(user: user)
        XCTAssertEqual(state.entitlementSnapshot?.usage, 4)
        state.updateEntitlements(.premium)
        XCTAssertEqual(state.entitlements.tier, .premium)
        XCTAssertEqual(state.entitlementSnapshot?.usage, 4)
        XCTAssertFalse(state.entitlementSnapshot?.isUnlimited ?? true)
        state.recordChatQuota(ownerID: UUID(), used: 0, limit: 30, countedOn: nil)
        XCTAssertEqual(state.entitlementSnapshot?.usage, 4)
        state.setAuthenticated(user: profile(tier: "free", userID: UUID()))
        XCTAssertNil(state.entitlementSnapshot?.usage)
    }

    func testOnlyNewServerQuotaPeriodCanLowerUsage() {
        let now = Date()
        var snapshot = EntitlementSnapshot(ownerID: UUID(), tier: .free, source: .chatReceipt,
            verifiedAt: now, usage: 4, quota: 5, quotaPeriodStartedAt: nil)
        snapshot.merge(tier: .free, usage: 0, quota: 5, period: now.addingTimeInterval(-3600),
                       verifiedAt: now, source: .serverProfile)
        XCTAssertEqual(snapshot.usage, 4)
        snapshot.merge(tier: .free, usage: 0, quota: 5, period: now.addingTimeInterval(86400),
                       verifiedAt: now.addingTimeInterval(86400), source: .serverProfile)
        XCTAssertEqual(snapshot.usage, 0)
        snapshot.merge(tier: .premium, usage: 1, quota: -1, period: nil,
                       verifiedAt: now.addingTimeInterval(86401), source: .chatReceipt)
        XCTAssertTrue(snapshot.isUnlimited)
        snapshot.merge(tier: .free, usage: nil, quota: nil, period: nil,
                       verifiedAt: nil, source: .serverBilling)
        XCTAssertFalse(snapshot.isUnlimited)
    }

    func testChatReceiptFromANewServerDayReplacesEarlierUsage() throws {
        let state = AppState()
        let user = profile(tier: "free")
        state.setAuthenticated(user: user)
        state.recordChatQuota(ownerID: user.id, used: 30, limit: 30, countedOn: "2026-11-08")
        state.recordChatQuota(ownerID: user.id, used: 1, limit: 30, countedOn: "2026-11-09")
        XCTAssertEqual(state.entitlementSnapshot?.usage, 1)
        XCTAssertEqual(state.entitlementSnapshot?.quotaPeriodStartedAt,
                       ISO8601DateFormatter().date(from: "2026-11-09T00:00:00Z"))
    }

    func testUsageFromAnEarlierServerDayNoLongerCounts() {
        let state = AppState()
        let user = profile(tier: "free")
        state.setAuthenticated(user: user)
        state.recordChatQuota(ownerID: user.id, used: 30, limit: 30, countedOn: serverDay(offset: -2))
        XCTAssertEqual(state.entitlementSnapshot?.remaining, 30)
        XCTAssertFalse(state.isOutOfFreeMessages)
        state.recordChatQuota(ownerID: user.id, used: 30, limit: 30, countedOn: serverDay(offset: 0))
        XCTAssertEqual(state.entitlementSnapshot?.remaining, 0)
        XCTAssertTrue(state.isOutOfFreeMessages)
        state.updateEntitlements(.premium)
        XCTAssertFalse(state.isOutOfFreeMessages)
    }

    /// Spec AC-23: crisis access never depends on the AI quota. The server checks crisis
    /// language before it counts the quota, so the client still sends at 0 remaining.
    func testSendingStaysAvailableWhenTheFreeQuotaIsSpent() {
        let state = AppState()
        let user = profile(tier: "free")
        state.setAuthenticated(user: user)
        state.recordChatQuota(ownerID: user.id, used: 30, limit: 30, countedOn: serverDay(offset: 0))
        XCTAssertTrue(state.isOutOfFreeMessages)
        XCTAssertTrue(ChatInputBar.canSend("I don't want to be here anymore", isSending: false))
        XCTAssertFalse(ChatInputBar.canSend("   ", isSending: false))
        XCTAssertFalse(ChatInputBar.canSend("hello", isSending: true))
    }

    func testFailureWithoutUsageKeepsTheQuotaPeriod() {
        let state = AppState()
        let user = profile(tier: "free")
        state.setAuthenticated(user: user)
        state.recordChatQuota(ownerID: user.id, used: 30, limit: 30, countedOn: serverDay(offset: -1))
        XCTAssertEqual(state.entitlementSnapshot?.remaining, 30)
        // A network or sign-in failure reports no usage, so it says nothing about today.
        state.recordChatQuota(ownerID: user.id, used: nil, limit: nil, countedOn: nil)
        XCTAssertEqual(state.entitlementSnapshot?.remaining, 30)
        XCTAssertFalse(state.isOutOfFreeMessages)
        state.recordChatQuota(ownerID: user.id, used: 1, limit: 30, countedOn: serverDay(offset: 0))
        XCTAssertEqual(state.entitlementSnapshot?.remaining, 29)
    }

    func testReplayedReceiptFromAnEarlierDayKeepsTodaysCount() {
        let state = AppState()
        let user = profile(tier: "free")
        state.setAuthenticated(user: user)
        state.recordChatQuota(ownerID: user.id, used: 3, limit: 30, countedOn: serverDay(offset: 0))
        // Yesterday's final message, replayed today from its stored receipt.
        state.recordChatQuota(ownerID: user.id, used: 30, limit: 30, countedOn: serverDay(offset: -1))
        XCTAssertEqual(state.entitlementSnapshot?.remaining, 27)
        XCTAssertFalse(state.isOutOfFreeMessages)
    }

    func testServerDayAcceptsOnlyItsDateFormat() {
        XCTAssertEqual(EntitlementSnapshot.serverDay(reported: "2026-11-09"),
                       ISO8601DateFormatter().date(from: "2026-11-09T00:00:00Z"))
        XCTAssertNil(EntitlementSnapshot.serverDay(reported: nil))
        XCTAssertNil(EntitlementSnapshot.serverDay(reported: "11/09/2026"))
        XCTAssertNil(EntitlementSnapshot.serverDay(reported: "2026-11-09T00:00:00Z"))
    }

    private func serverDay(offset days: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date().addingTimeInterval(Double(days) * 86_400))
    }

    func testUsageFromAnEarlierPeriodNeverRaisesTheCurrentCount() {
        let now = Date()
        let today = EntitlementSnapshot.serverDay(containing: now)
        var snapshot = EntitlementSnapshot(ownerID: UUID(), tier: .free, source: .chatReceipt,
            verifiedAt: now, usage: 3, quota: 30, quotaPeriodStartedAt: today)
        snapshot.merge(tier: .free, usage: 30, quota: 30, period: today.addingTimeInterval(-86_400),
                       verifiedAt: now, source: .chatReceipt)
        XCTAssertEqual(snapshot.usage, 3)
        XCTAssertEqual(snapshot.quotaPeriodStartedAt, today)
    }

    func testCelebrationsStayWithTheirAccount() {
        let state = AppState()
        let first = profile(tier: "free")
        let second = profile(tier: "free", userID: UUID())
        func event(for owner: UUID) -> CelebrationEvent {
            CelebrationEvent(id: UUID(), userId: owner, celebrationType: .levelUp, value: 2, badgeId: nil,
                             shownAt: nil, sharedToCircle: false, sharedExternally: false,
                             circlePostId: nil, createdAt: Date())
        }
        state.setAuthenticated(user: first)
        state.addCelebrations([event(for: first.id), event(for: second.id)])
        XCTAssertEqual(state.pendingCelebrations.map(\.userId), [first.id])
        state.setAuthenticated(user: second)
        XCTAssertTrue(state.pendingCelebrations.isEmpty)
        // A response requested by the previous account arrives late.
        state.addCelebrations([event(for: first.id)])
        XCTAssertTrue(state.pendingCelebrations.isEmpty)
        state.addCelebrations([event(for: second.id)])
        XCTAssertEqual(state.pendingCelebrations.count, 1)
        state.setUnauthenticated()
        XCTAssertTrue(state.pendingCelebrations.isEmpty)
    }

    func testOnlyRecentUnseenCelebrationsAreQueuedOnce() {
        let state = AppState()
        let user = profile(tier: "free")
        state.setAuthenticated(user: user)
        let now = Date()
        func event(id: UUID = UUID(), age: TimeInterval) -> CelebrationEvent {
            CelebrationEvent(id: id, userId: user.id, celebrationType: .levelUp, value: 2, badgeId: nil,
                             shownAt: nil, sharedToCircle: false, sharedExternally: false,
                             circlePostId: nil, createdAt: now.addingTimeInterval(-age))
        }
        let recent = event(age: 60)
        // A backlog row from before 2.0 and the same event reported by the shell and a trigger.
        state.addCelebrations([event(age: 30 * 24 * 60 * 60), recent, recent], now: now)
        state.addCelebrations([recent], now: now)
        XCTAssertEqual(state.pendingCelebrations.map(\.id), [recent.id])
    }

    func testServerQuotaDayResetsAtUTCMidnight() throws {
        let formatter = ISO8601DateFormatter()
        let evening = try XCTUnwrap(formatter.date(from: "2026-11-09T18:30:00-05:00"))
        XCTAssertEqual(EntitlementSnapshot.nextServerReset(after: evening),
                       formatter.date(from: "2026-11-10T00:00:00Z"))
    }

    func testCompletedCachedProfileRetainsOfflineAccess() {
        let state = AppState()
        state.setAuthenticatedFromCache(user: profile(tier: "free"))
        XCTAssertEqual(state.authState, .authenticated)
    }

    func testConsentUsesServerYearAcrossTimeZones() throws {
        let formatter = ISO8601DateFormatter()
        let date = try XCTUnwrap(formatter.date(from: "2027-01-01T00:30:00+14:00"))
        XCTAssertEqual(OnboardingConsent.referenceYear(at: date), 2026)
    }

    func testBirthYearAndUnselectedConsentFailClosed() {
        var consent = OnboardingConsent()
        XCTAssertFalse(consent.isEligible(currentYear: 2026))
        consent.birthYear = 2014
        consent.confirmsThirteen = true
        consent.acceptsTerms = true
        XCTAssertFalse(consent.isEligible(currentYear: 2026))
        consent.birthYear = 2013
        consent.confirmsThirteen = false
        XCTAssertFalse(consent.isEligible(currentYear: 2026))
        consent.confirmsThirteen = true
        XCTAssertTrue(consent.isEligible(currentYear: 2026))
        consent.acceptsTerms = false
        XCTAssertFalse(consent.isEligible(currentYear: 2026))
    }

    private func profile(tier: String, userID: UUID? = nil) -> UserProfile {
        UserProfile(
            id: userID ?? UUID(uuidString: id)!, handle: "synthetic", displayName: "Synthetic",
            email: nil, avatarUrl: nil, timezone: "America/New_York", createdAt: nil,
            onboardingCompletedAt: Date(), stats: nil, settings: nil,
            entitlements: UserEntitlements(subscriptionTier: tier, premiumExpiresAt: nil, features: [:]), badges: nil
        )
    }
}
