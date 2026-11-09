import XCTest
#if canImport(MindFriendApp)
@testable import MindFriendApp
#endif

/// Pure routing/registry checks for the stable Today / Chat / Explore / You shell. Synthetic values only.
@MainActor
final class SupportNavigationTests: XCTestCase {
    private let id = "B4498A22-4674-4DC1-B874-D00B7F8D14A1"

    func testRenamedRecordPinKeepsStableIdentityAndDoesNotDuplicate() {
        let pins = SupportPinStore(accountID: nil)
        let original = SupportPin(.programs, record: .init(kind: .enrollment, id: id,
            relatedProgramID: "original-program", title: "Earlier title"))
        var renamed = original
        renamed.record?.title = "Current title"
        XCTAssertTrue(pins.pin(original))
        XCTAssertTrue(pins.isPinned(renamed))
        XCTAssertTrue(pins.pin(renamed))
        XCTAssertEqual(pins.pins.count, 1)
        XCTAssertEqual(pins.pins[0].title, "Current title")
        pins.unpin(original)
        XCTAssertTrue(pins.pins.isEmpty)
    }

    /// All 26 `DeepLinkRoute` cases (identifier-bearing ones with and without identifiers).
    private var allRoutes: [DeepLinkRoute] {
        [.home, .chat(), .chat(conversationId: id), .circles(), .circles(circleId: id), .profile, .settings,
         .mood, .moodHistory, .quest(), .quest(questId: id), .streak, .progress,
         .breathing, .meditation, .exercise(exerciseId: id), .exerciseLibrary,
         .programs, .therapeuticPrograms, .program(programId: id),
         .journal, .microMoments(), .microMoments(templateId: id), .sleep(), .sleep(contentId: id),
         .quote, .assessment(), .assessment(code: "PHQ9"), .buddy(code: "ABCD1234"),
         .insights, .achievements, .unknown]
    }

    func testFourFixedTabsKeepLegacyTags() {
        XCTAssertEqual(SupportShellTab.allCases.map(\.mainTab), [.home, .chat, .circles, .profile])
        XCTAssertEqual(SupportShellTab.allCases.map(\.title), ["Today", "Chat", "Explore", "You"])
        for tab in SupportShellTab.allCases {
            XCTAssertEqual(SupportShellTab(mainTab: tab.mainTab), tab)
        }
    }

    func testEveryRouteHasAHomeAndNeverWaitsForActivation() {
        for route in allRoutes {
            switch route.supportPlacement {
            case .externalFlow: XCTAssertEqual(route, .buddy(code: "ABCD1234"))
            case .unavailable: XCTAssertEqual(route, .unknown)
            default: XCTAssertNotNil(DeepLinkRouter.supportShellTab(for: route), "\(route)")
            }
            if let tab = DeepLinkRouter.supportShellTab(for: route) {
                XCTAssertNotNil(SupportShellTab(mainTab: tab), "\(route) must land on one of the four tabs")
            }
        }
    }

    func testFormerlyGatedRoutesOpenDirectly() {
        XCTAssertEqual(DeepLinkRoute.programs.supportPlacement, .destination(.programs))
        XCTAssertEqual(DeepLinkRoute.therapeuticPrograms.supportPlacement, .destination(.therapeuticPrograms))
        XCTAssertEqual(DeepLinkRoute.progress.supportPlacement, .destination(.outcomes))
        XCTAssertEqual(DeepLinkRoute.assessment().supportPlacement, .destination(.outcomes))
    }

    func testIdentifierRoutesStillResolveThroughGuardedSheet() {
        let guarded: [DeepLinkRoute] = [
            .circles(circleId: id), .exercise(exerciseId: id), .program(programId: id), .quest(questId: id),
            .microMoments(templateId: id), .sleep(contentId: id), .assessment(code: "PHQ9"), .quest(), .mood
        ]
        for route in guarded {
            guard case .presented = route.supportPlacement else { return XCTFail("\(route)") }
        }
    }

    func testCirclesIsDirectExploreRow() {
        XCTAssertEqual(DeepLinkRoute.circles().supportPlacement, .destination(.circles))
        XCTAssertEqual(SupportDestination.circles.tab, .explore)
        XCTAssertTrue(SupportDestination.destinations(in: .peopleAndCircles).contains(.circles))
    }

    func testProfileSettingsAndChatMapping() {
        XCTAssertEqual(DeepLinkRoute.profile.supportPlacement, .tabRoot(.profile))
        XCTAssertEqual(DeepLinkRoute.settings.supportPlacement, .destination(.settings))
        XCTAssertEqual(DeepLinkRoute.chat(conversationId: id).supportPlacement, .tabRoot(.chat))
        XCTAssertEqual(DeepLinkRoute.home.supportPlacement, .tabRoot(.home))
        // SR-02: no quote UI exists; the old link opens an honest unavailable screen under Explore → Practices.
        XCTAssertEqual(DeepLinkRoute.quote.supportPlacement, .destination(.quote))
        XCTAssertEqual(SupportDestination.quote.tab, .explore)
        XCTAssertEqual(SupportDestination.quote.section, .practices)
        XCTAssertFalse(SupportDestination.quote.isPinnable)
    }

    func testLegacyTabsMapToStableTabs() {
        for tab in MainTab.allCases {
            XCTAssertNotNil(SupportShellTab(mainTab: tab.supportShellTag), "\(tab)")
        }
        XCTAssertEqual(MainTab.programs.supportShellTag, .circles)
        XCTAssertEqual(MainTab.outcomes.supportShellTag, .profile)
        XCTAssertEqual(SupportDestination.replacingLegacyTab(.programs), .programs)
        XCTAssertEqual(SupportDestination.replacingLegacyTab(.outcomes), .outcomes)
        XCTAssertNil(SupportDestination.replacingLegacyTab(.home))
    }

    func testRegistryIsCompleteAndPrivateJournalStaysOutOfExplore() {
        for destination in SupportDestination.allCases {
            XCTAssertFalse(destination.title.isEmpty)
            XCTAssertFalse(destination.legacyOrigin.isEmpty)
        }
        XCTAssertEqual(SupportDestination.privateVault.tab, .you)
        XCTAssertFalse(SupportDestination.privateVault.isPinnable)
        XCTAssertFalse(SupportDestination.settings.isPinnable)
    }

    func testPinStoreCapsAtThreeAndReplacesOnlyExplicitly() {
        let suite = UserDefaults(suiteName: "SupportNavigationTests.\(UUID().uuidString)")!
        let account = UUID()
        let store = SupportPinStore(accountID: account, defaults: suite)
        XCTAssertTrue(store.pin(.programs))
        XCTAssertTrue(store.pin(.circles))
        XCTAssertTrue(store.pin(.journal))
        XCTAssertFalse(store.pin(.habits), "full: caller must offer Replace, nothing is evicted")
        XCTAssertEqual(store.pins.map(\.destination), [.programs, .circles, .journal])
        XCTAssertFalse(store.pin(.settings))
        store.replace(SupportPin(.circles), with: .habits)
        XCTAssertEqual(store.pins.map(\.destination), [.programs, .habits, .journal])
        store.moveUp(SupportPin(.journal))
        XCTAssertEqual(store.pins.map(\.destination), [.programs, .journal, .habits])
        XCTAssertEqual(SupportPinStore(accountID: account, defaults: suite).pins, store.pins)
        XCTAssertTrue(SupportPinStore(accountID: UUID(), defaults: suite).pins.isEmpty)
        XCTAssertTrue(SupportPinStore(accountID: nil, defaults: suite).pins.isEmpty)
    }

    func testActiveProgramPinIsDistinctFromLibraryPin() {
        let suite = UserDefaults(suiteName: "SupportNavigationTests.\(UUID().uuidString)")!
        let account = UUID()
        let store = SupportPinStore(accountID: account, defaults: suite)
        let enrollment = SupportPin(.programs, record: .init(kind: .enrollment, id: "E1", relatedProgramID: "P1", title: "Sleep"))
        XCTAssertTrue(store.pin(.programs))
        XCTAssertTrue(store.pin(enrollment))
        XCTAssertEqual(store.pins.count, 2)
        XCTAssertNotEqual(SupportPin(.programs).id, enrollment.id)
        XCTAssertTrue(SupportPinStore(accountID: account, defaults: suite).isPinned(enrollment))
        store.unpin(enrollment)
        XCTAssertTrue(store.isPinned(.programs))
        XCTAssertFalse(store.isPinned(enrollment))
    }

    func testPinStoreMigratesLegacyAndDropsUnknownEntries() throws {
        let suite = UserDefaults(suiteName: "SupportNavigationTests.\(UUID().uuidString)")!
        let account = UUID()
        suite.set(["programs", "no_such_destination", "settings", "circles"], forKey: "mf.support.pins.\(account.uuidString)")
        XCTAssertEqual(SupportPinStore(accountID: account, defaults: suite).pins.map(\.destination), [.programs, .circles])

        // Backward-compatible JSON: missing `record`, plus an unknown destination that must not poison the list.
        let json = #"[{"destination":"journal"},{"destination":"future_thing"},{"destination":"programs","record":{"kind":"enrollment","id":"E9"}}]"#
        let other = UUID()
        suite.set(Data(json.utf8), forKey: "mf.support.pins.v2.\(other.uuidString)")
        let loaded = SupportPinStore(accountID: other, defaults: suite).pins
        XCTAssertEqual(loaded.map(\.destination), [.journal, .programs])
        XCTAssertEqual(loaded.last?.record?.id, "E9")
    }

    func testRetainedHomesAreExact() {
        // SR-03 / SR-05 / SR-07
        XCTAssertEqual(SupportDestination.plans.section, .progress)
        XCTAssertEqual(SupportDestination.dailyBriefing.section, .progress)
        XCTAssertEqual(SupportDestination.weeklyRecap.section, .progress)
        XCTAssertEqual(SupportDestination.habits.section, .progress)
        XCTAssertEqual(SupportDestination.streaks.section, .progress)
        XCTAssertEqual(SupportDestination.seasonalEvents.tab, .explore)
        XCTAssertEqual(SupportDestination.buddy.tab, .explore)
        XCTAssertEqual(SupportDestination.sleepTracking.section, .measurements)
        XCTAssertEqual(SupportDestination.wellbeingDebt.section, .measurements)
        XCTAssertEqual(SupportDestination.capacity.section, .measurements)
        XCTAssertEqual(SupportDestination.moodPrediction.section, .measurements)
        XCTAssertEqual(SupportDestination.pathways.section, .programsAndPathways)
        XCTAssertEqual(SupportDestination.sleep.section, .practices)
        XCTAssertTrue(SupportDestination.exploreRows(in: .toolsAndExperiments).contains(.outcomes),
                      "assessments shortcut under Explore → Tools and Experiments")
        XCTAssertEqual(SupportDestination.outcomes.section, .progress)
    }

    func testOnlyViewsWithRootStacksAreMarkedEmbedded() {
        XCTAssertFalse(SupportDestination.insightLab.ownsNavigationStack)
        XCTAssertFalse(SupportDestination.liveSessions.ownsNavigationStack)
        XCTAssertFalse(SupportDestination.journal.ownsNavigationStack, "journal is a hub; its children are embedded")
        XCTAssertTrue(SupportDestination.circles.ownsNavigationStack)
        XCTAssertEqual(SupportDestination.allCases.filter(\.ownsNavigationStack).count, 16)
    }

    func testSimplerViewUsesTheImmediatelyReversiblePreference() {
        XCTAssertTrue(SupportShellFeature.simplerViewIsImmediatelyReversible)
        XCTAssertEqual(SupportDestination.recoveryMode.title, "Simpler view")
        XCTAssertTrue(SupportDestination.recoveryMode.subtitle?.contains("any time") ?? false)
    }

    func testNavigatorOpensIntoTheOwningTabStackOnly() {
        let navigator = SupportShellNavigator()
        navigator.open(.circles)
        XCTAssertEqual(navigator.explorePath, [.circles])
        XCTAssertTrue(navigator.youPath.isEmpty)
        navigator.open(.settings)
        XCTAssertEqual(navigator.youPath, [.settings])
        navigator.popToRoot()
        XCTAssertTrue(navigator.explorePath.isEmpty && navigator.youPath.isEmpty)
    }

    func testFeatureSwitchOverride() {
        let suite = UserDefaults(suiteName: "SupportNavigationTests.\(UUID().uuidString)")!
        suite.set(false, forKey: SupportShellFeature.defaultsKey)
        XCTAssertFalse(SupportShellFeature.isEnabled(defaults: suite))
        suite.set(true, forKey: SupportShellFeature.defaultsKey)
        XCTAssertTrue(SupportShellFeature.isEnabled(defaults: suite))
    }

    func testExploreSearchFindsCapabilitiesByOldNames() {
        XCTAssertTrue(SupportDestination.circles.matches("buddy"))
        XCTAssertTrue(SupportDestination.outcomes.matches("PHQ"))
        XCTAssertFalse(SupportDestination.circles.matches("zzzz"))
    }
}
