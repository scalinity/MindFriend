import XCTest
import StoreKitTest

final class MindFriendAppUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--auth-ui-test"]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testInvalidEmailShowsFixtureCredentialsError() throws {
        app.launch()
        let emailLogin = app.buttons["Continue with Email"]
        XCTAssertTrue(emailLogin.waitForExistence(timeout: 15))
        emailLogin.tap()
        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("restoration-probe@example.invalid")
        let password = app.secureTextFields["Password"]
        password.tap()
        password.typeText("Synthetic-invalid-" + UUID().uuidString)
        let keyboardDone = app.buttons["Done"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5))
        keyboardDone.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let signIn = app.buttons["Sign In"]
        XCTAssertTrue(signIn.isEnabled)
        XCTAssertTrue(signIn.isHittable)
        signIn.tap()
        let alert = app.alerts["Sign In Error"]
        let alertAppeared = alert.waitForExistence(timeout: 10)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Offline sign-in rejection"
        evidence.lifetime = .keepAlways
        add(evidence)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Offline sign-in rejection hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTAssertTrue(alertAppeared, "The deterministic authentication rejection must reach the production alert")
        XCTAssertTrue(alert.staticTexts["Incorrect email or password. Please try again."].exists)
    }

    // MARK: - Launch Tests

    func testAppLaunches() throws {
        app.launch()

        // App should launch without crashing
        XCTAssertTrue(app.exists)
    }

    // MARK: - Sign In Screen Tests

    func testSignInScreenElements() throws {
        app.launch()

        // Wait for sign in screen to appear
        let signInWithAppleButton = app.buttons["Sign in with Apple"]
        let signInWithGoogleButton = app.buttons["Continue with Google"]

        // Check that sign-in buttons exist
        XCTAssertTrue(signInWithAppleButton.waitForExistence(timeout: 5))
        XCTAssertTrue(signInWithGoogleButton.exists)

        // Check app branding
        let appTitle = app.staticTexts["MindFriend"]
        XCTAssertTrue(appTitle.exists)

        // Check tagline
        let tagline = app.staticTexts["Your AI wellness companion"]
        XCTAssertTrue(tagline.exists)
    }

    func testFeatureListOnSignInScreen() throws {
        app.launch()

        // Wait for screen to load
        let signInWithAppleButton = app.buttons["Sign in with Apple"]
        XCTAssertTrue(signInWithAppleButton.waitForExistence(timeout: 5))

        // One calm line says what the app is, in place of a feature list.
        let description = app.staticTexts["A quiet place to reflect, find support and care for your wellbeing."]
        XCTAssertTrue(description.exists, "The sign-in description should be visible")
    }

    // MARK: - Accessibility Tests

    func testSignInButtonsAccessibility() throws {
        app.launch()

        // Check Apple sign-in button is accessible (exists with accessibility label)
        let signInWithAppleButton = app.buttons["Sign in with Apple"]
        XCTAssertTrue(signInWithAppleButton.waitForExistence(timeout: 5), "Apple sign-in button should exist")
        XCTAssertTrue(signInWithAppleButton.isHittable, "Apple sign-in button should be hittable")

        // Check Google sign-in button is accessible
        let signInWithGoogleButton = app.buttons["Continue with Google"]
        XCTAssertTrue(signInWithGoogleButton.exists, "Google sign-in button should exist")
        XCTAssertTrue(signInWithGoogleButton.isHittable, "Google sign-in button should be hittable")

        // Check Email sign-in button is accessible
        let signInWithEmailButton = app.buttons["Continue with Email"]
        XCTAssertTrue(signInWithEmailButton.exists, "Email sign-in button should exist")
        XCTAssertTrue(signInWithEmailButton.isHittable, "Email sign-in button should be hittable")
    }

    func testRelaunchStartsAtSignedOutFixture() {
        app.launch()
        XCTAssertTrue(app.buttons["Continue with Email"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Continue with Email"].waitForExistence(timeout: 5))
    }

}

/// Explicit opt-in probe of a configured backend; excluded from deterministic UI CI.
final class AuthBackendIntegrationTests: XCTestCase {
    func testConfiguredBackendRejectsSyntheticInvalidCredentials() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MINDFRIEND_RUN_LIVE_AUTH_TESTS"] == "1" else {
            throw XCTSkip("Set MINDFRIEND_RUN_LIVE_AUTH_TESTS=1 for the live authentication probe")
        }
        let urlString = try XCTUnwrap(environment["MINDFRIEND_LIVE_AUTH_URL"], "Explicit backend URL required")
        let key = try XCTUnwrap(environment["MINDFRIEND_LIVE_AUTH_ANON_KEY"], "Explicit public anon key required")
        let baseURL = try XCTUnwrap(URL(string: urlString))
        XCTAssertEqual(baseURL.scheme, "https")
        XCTAssertNotNil(baseURL.host)
        XCTAssertFalse(urlString.contains("YOUR_SUPABASE_PROJECT"))
        XCTAssertFalse(key.isEmpty)
        guard baseURL.scheme == "https", baseURL.host != nil,
              !urlString.contains("YOUR_SUPABASE_PROJECT"), !key.isEmpty else { return }
        var components = URLComponents(url: baseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": "restoration-probe@example.invalid",
            "password": "Synthetic-invalid-" + UUID().uuidString
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 400)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["error_code"] as? String, "invalid_credentials")
    }
}

// MARK: - Launch Performance Tests

final class MindFriendAppLaunchTests: XCTestCase {

    func testLaunchPerformance() throws {
        if #available(iOS 17.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                let app = XCUIApplication()
                app.launchArguments = ["--auth-ui-test"]
                app.launch()
            }
        }
    }
}

@MainActor
final class SubscriptionCatalogUITests: XCTestCase {
    func testUnavailableCatalogReloadsAfterNetworkFailure() throws {
        continueAfterFailure = false
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MindFriend-UI-\(UUID()).storekit")
        defer { try? FileManager.default.removeItem(at: url) }
        let ids = ["com.mindfriend.premium.monthly", "com.mindfriend.premium.yearly",
                   "com.mindfriend.couples.monthly", "com.mindfriend.couples.annual",
                   "com.mindfriend.family.monthly", "com.mindfriend.family.annual"]
        let group = "10000017"
        let subscriptions: [[String: Any]] = ids.enumerated().map { index, id in
            ["adHocOffers": [], "codeOffers": [], "displayPrice": "12.99",
             "familyShareable": false, "groupNumber": index + 1, "internalID": UUID().uuidString,
             "localizations": [["description": "Synthetic StoreKit UI test", "displayName": id, "locale": "en_US"]],
             "productID": id, "recurringSubscriptionPeriod": index % 2 == 0 ? "P1M" : "P1Y",
             "referenceName": id, "subscriptionGroupID": group, "type": "RecurringSubscription", "winBackOffers": []]
        }
        let configuration: [String: Any] = ["identifier": UUID().uuidString, "nonRenewingSubscriptions": [], "products": [],
            "settings": ["_applicationInternalID": "6758198271", "_failTransactionsEnabled": false,
                         "_locale": "en_US", "_storefront": "USA", "_storeKitErrors": []],
            "subscriptionGroups": [["id": group, "name": "MindFriend UI Test", "localizations": [], "subscriptions": subscriptions]],
            "version": ["major": 3, "minor": 0]]
        try JSONSerialization.data(withJSONObject: configuration).write(to: url)
        let store = try SKTestSession(contentsOf: url)
        store.resetToDefaultState()
        store.disableDialogs = true
        store.clearTransactions()

        let app = XCUIApplication()
        app.launchArguments = ["--subscription-ui-test"]
        app.launch()
        defer { app.terminate() }
        let subscribe = app.buttons["subscription.subscribe"]
        let reload = app.buttons["subscription.reload"]
        let error = app.staticTexts["subscription.catalogError"]
        XCTAssertTrue(reload.waitForExistence(timeout: 15))
        XCTAssertTrue(subscribe.exists)
        XCTAssertFalse(subscribe.isEnabled)
        for _ in 0..<5 {
            if reload.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(reload.isHittable)
        reload.tap()
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("Check your connection"))
        XCTAssertFalse(subscribe.isEnabled)
        XCTAssertTrue(reload.isEnabled)
        let unavailable = XCTAttachment(screenshot: app.screenshot())
        unavailable.name = "Issue17-subscription-network-failure"
        unavailable.lifetime = .keepAlways
        add(unavailable)

        reload.tap()
        XCTAssertTrue(reload.waitForNonExistence(timeout: 15))
        XCTAssertTrue(subscribe.isEnabled)
        XCTAssertEqual(subscribe.label, "Subscribe Now")
        let available = XCTAttachment(screenshot: app.screenshot())
        available.name = "Issue17-subscription-recovered"
        available.lifetime = .keepAlways
        add(available)
        XCTAssertTrue(store.allTransactions().isEmpty, "Catalog recovery must not purchase anything")
    }
}

@MainActor
final class SleepDashboardUITests: XCTestCase {
    func testConnectedSleepSyncsOnEntryAndForegroundWithoutManualAction() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sleep-ui-test", "--sleep-auto-sync"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Loading sleep…"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No Sleep Data Yet"].exists)
        XCTAssertTrue(app.staticTexts["18h 0m"].waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["19h 0m"].waitForExistence(timeout: 15), "Returning to the visible screen must sync newer records")
        XCTAssertFalse(app.staticTexts["Sleep Records Unavailable"].exists)
    }

    func testForegroundPreservesAnOpenSleepRatingDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sleep-ui-test", "--sleep-checkin-skip", "--sleep-auto-sync",
            "--sleep-test-suite", "sleep.ui." + UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 15))
        let notes = app.textViews.firstMatch
        XCTAssertTrue(notes.exists)
        notes.tap()
        notes.typeText("Synthetic unfinished sleep note")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        XCTAssertTrue((notes.value as? String)?.contains("Synthetic unfinished sleep note") == true)
        app.buttons["Skip"].tap()
    }

    func testSwipeDismissalIsRememberedBeforeDeferredRefresh() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sleep-ui-test", "--sleep-checkin-skip", "--sleep-test-suite", "sleep.ui." + UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 15))
        let bar = app.navigationBars["Morning Check-In"]
        XCTAssertTrue(bar.exists)
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(app.buttons["Skip"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Rate Sleep"].isHittable)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Rate Sleep"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Skip"].exists)
    }

    func testSkipDoesNotReopenOnRefreshOrRelaunchAndManualRatingRemainsAvailable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sleep-ui-test", "--sleep-checkin-skip", "--sleep-test-suite", "sleep.ui." + UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 15))
        app.buttons["Skip"].tap()
        let rate = app.buttons["Rate Sleep"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        let scroll = app.scrollViews.firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(forDuration: 0.1,
            thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(rate.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Skip"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(rate.isHittable)
        app.terminate()
        app.launch()
        XCTAssertTrue(rate.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Skip"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(rate.isHittable)
        rate.tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
    }

    func testPullToRefreshActuallySyncsBeforeReloadingSavedSleep() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sleep-ui-test", "--sleep-pull-sync"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["7h 30m"].waitForExistence(timeout: 15))
        let scroll = app.scrollViews.firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(forDuration: 0.1,
            thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(app.staticTexts["18h 0m"].waitForExistence(timeout: 10), "A pull must invoke Health sync, then show its updated entry")
        XCTAssertFalse(app.staticTexts["Sleep Records Unavailable"].exists)
    }
    func testFullImportedSessionDisplaysDurationAndRetainsEarlierFeedback() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sleep-ui-test", "--sleep-session-accuracy"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["sleep.retry"].waitForExistence(timeout: 15))
        app.buttons["sleep.retry"].tap()
        XCTAssertTrue(app.staticTexts["18h 0m"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["4h 0m"].exists)
        XCTAssertTrue(app.staticTexts["Score unavailable — missing measurements"].exists)
        let feedback = app.buttons["Saved feedback from earlier imports"]
        XCTAssertTrue(feedback.exists)
        feedback.tap()
        XCTAssertTrue(app.staticTexts["Synthetic earlier feedback"].waitForExistence(timeout: 3))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Issue19-full-synthetic-session-and-retained-feedback"
        capture.lifetime = .keepAlways
        add(capture)
    }
    func testDailySleepShowsTheMeasuredPeriodsWithoutUTCLabels() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sleep-ui-test", "--sleep-daily-periods"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Today's Sleep"].waitForExistence(timeout: 15))
        let periods = app.buttons["Recorded periods"]
        XCTAssertTrue(periods.isHittable)
        periods.tap()
        let rows = app.descendants(matching: .any).matching(identifier: "sleep.recordedPeriod")
        XCTAssertEqual(rows.count, 2)
        XCTAssertFalse(rows.element(boundBy: 0).label.contains("UTC"))
        XCTAssertFalse(rows.element(boundBy: 1).label.contains("UTC"))
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Issue19-synthetic-daily-periods-local-dates"
        image.lifetime = .keepAlways
        add(image)
    }
    func testLoadFailureRetriesAndDisplaysDecodedHealthKitNight() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sleep-ui-test"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Sleep Records Unavailable"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["No Sleep Data Yet"].exists)
        let retry = app.buttons["sleep.retry"]
        XCTAssertTrue(retry.isHittable)
        retry.tap()
        XCTAssertTrue(app.staticTexts["Today's Sleep"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Today's Sleep"].isHittable)
        XCTAssertTrue(app.staticTexts["sleep.source"].label.contains("Health App"))
        XCTAssertFalse(app.staticTexts["Sleep Records Unavailable"].exists)
        XCTAssertFalse(retry.exists)
        XCTAssertTrue(app.staticTexts["Score unavailable — missing measurements"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Issue19-decoded-HealthKit-night"
        capture.lifetime = .keepAlways
        add(capture)
    }
}


@MainActor
final class DebtLocalCalendarUITests: XCTestCase {
    func testHomeDashboardAndBreakdownShowDatesWithoutTimeZoneText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--debt-calendar-ui-test", "-wellbeing_debt_tutorial_completed", "YES"]
        app.launch()
        defer { app.terminate() }
        let homeDate = app.staticTexts["debt.home.date"]
        XCTAssertTrue(homeDate.waitForExistence(timeout: 15))
        let date = homeDate.label
        XCTAssertTrue(date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'UTC'")).firstMatch.exists)
        app.buttons["Open Debt Dashboard"].tap()
        let dashboardDate = app.staticTexts["debt.dashboard.date"]
        XCTAssertTrue(dashboardDate.waitForExistence(timeout: 5)); XCTAssertEqual(dashboardDate.label, date)
        let breakdown = app.buttons["View Transaction Breakdown"]
        for _ in 0..<5 { if breakdown.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(breakdown.isHittable); breakdown.tap()
        let range = app.staticTexts["debt.breakdown.window"]
        XCTAssertTrue(range.waitForExistence(timeout: 5)); XCTAssertTrue(range.label.hasSuffix(date))
        XCTAssertTrue(app.staticTexts["Synthetic recorded event"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Error Loading Transactions"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'UTC'")).firstMatch.exists)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Issue23-date-only-local-window-breakdown"
        capture.lifetime = .keepAlways; add(capture)
    }
}

final class SupportSessionFlowUITests: XCTestCase {
    private func launch(run: String = UUID().uuidString, size: String = "large", appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--support-session-ui-test", "--support-fixture-run", run,
                               "--support-text-size", size, "--support-appearance", appearance]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(app.descendants(matching: .any)["support-fixture-appearance"].firstMatch.value as? String, appearance,
            "The rendered color scheme must match the requested appearance")
        return app
    }
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<16 {
            if element.isHittable { return true }
            let viewport = app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch.frame : app.frame
            let above = element.exists && element.frame.maxY < viewport.minY + 80
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            let end = start.withOffset(CGVector(dx: 0, dy: above ? 60 : -60))
            start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        return element.isHittable
    }
    private func tap(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label].firstMatch
        _ = button.waitForExistence(timeout: 2)
        XCTAssertTrue(reveal(button, in: app), label + "\n" + app.debugDescription)
        button.tap()
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertFourDestinations(in app: XCUIApplication) {
        if app.tabBars.firstMatch.exists {
            for tab in ["Today", "Chat", "Explore", "You"] { XCTAssertTrue(app.tabBars.buttons[tab].exists) }
            XCTAssertEqual(app.tabBars.buttons.count, 4)
        } else {
            for tab in ["Today", "Chat", "Explore", "You"] {
                XCTAssertTrue(app.descendants(matching: .any)["support-root-\(tab)"].exists, app.debugDescription)
            }
        }
    }

    func testQuietShellAndCompleteLocalGroundingLoop() throws {
        continueAfterFailure = false
        let app = launch()
        defer { app.terminate() }
        assertFourDestinations(in: app)
        XCTAssertTrue(app.buttons["Start a conversation"].isHittable)
        capture("Support-Today-light", app: app)
        tap("Settle for a moment", in: app)
        XCTAssertTrue(app.staticTexts["Step 1 of 5"].waitForExistence(timeout: 5))
        for _ in 0..<4 { tap("Next", in: app) }
        tap("Finish", in: app)
        XCTAssertTrue(app.staticTexts["Finished on this device"].waitForExistence(timeout: 5))
        let share = app.switches["Include my written answers in the conversation"]
        XCTAssertEqual(share.value as? String, "0", "Written answers are excluded by default")
        tap("Not sure", in: app)
        tap("Done for now", in: app)
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["XP awarded"].exists)
    }

    func testPausedUntangleSurvivesTerminationAndRelaunch() throws {
        continueAfterFailure = false
        let run = UUID().uuidString, app = launch(run: run)
        defer { app.terminate() }
        tap("Untangle a thought", in: app)
        XCTAssertTrue(app.staticTexts["Step 1 of 3"].waitForExistence(timeout: 5))
        let response = app.textFields["Optional response"]
        XCTAssertTrue(response.waitForExistence(timeout: 5))
        response.tap()
        response.typeText("Synthetic interruption checkpoint")
        tap("Pause", in: app)
        tap("Save and leave", in: app)
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 20))
        tap("Continue", in: app)
        XCTAssertEqual(app.textFields["Optional response"].value as? String, "Synthetic interruption checkpoint")
        tap("Pause", in: app)
        tap("Discard this reflection", in: app)
        XCTAssertFalse(app.staticTexts["Synthetic interruption checkpoint"].exists)
    }

    func testActivitySharingPreviewCreatesAnEditableDraftBeforeAnySend() throws {
        continueAfterFailure = false
        let app = launch()
        defer { app.terminate() }
        tap("Untangle a thought", in: app)
        let response = app.textFields["Optional response"]
        XCTAssertTrue(response.waitForExistence(timeout: 5))
        response.tap(); response.typeText("Synthetic chosen sharing answer")
        tap("Ask for help", in: app)
        XCTAssertTrue(app.navigationBars["Choose what to share"].waitForExistence(timeout: 5))
        let include = app.switches["support-share-on_mind"]
        XCTAssertTrue(include.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(include.value as? String, "0")
        let control = include.switches.firstMatch
        XCTAssertTrue(control.isHittable, app.debugDescription)
        control.tap()
        XCTAssertEqual(include.value as? String, "1", app.debugDescription)
        tap("Review message in Chat", in: app)
        XCTAssertTrue(app.staticTexts["Draft saved on this device. Reconnecting does not send it."].waitForExistence(timeout: 5), app.debugDescription)
        let composer = app.textFields["Message input"]
        XCTAssertTrue(composer.exists, app.debugDescription)
        XCTAssertTrue((composer.value as? String ?? "").contains("Synthetic chosen sharing answer"), String(describing: composer.value) + "\n" + app.debugDescription)
        XCTAssertFalse(app.staticTexts["Reply in progress · not yet saved"].exists)
        capture("Support-Activity-chosen-answer-draft", app: app)
    }

    func testSavedStepCompletionAndUnifiedHistoryRenameCloseDelete() throws {
        continueAfterFailure = false
        let app = launch()
        defer { app.terminate() }
        tap("Choose a next step", in: app)
        let step = app.textFields["Your next step"]
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        step.tap(); step.typeText("Synthetic small step")
        XCTAssertEqual(step.value as? String, "Synthetic small step", app.debugDescription)
        // The step choices return once typing ends, so they never sit under the keyboard.
        XCTAssertFalse(app.buttons["Save for later"].exists)
        tap("Done", in: app)
        tap("Save for later", in: app)
        XCTAssertTrue(app.staticTexts["A next step is saved"].waitForExistence(timeout: 5))
        tap("View session", in: app)
        let saved = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Saved for later")).firstMatch
        XCTAssertTrue(reveal(saved, in: app), app.debugDescription)
        XCTAssertTrue(saved.label.contains("Synthetic small step"))
        XCTAssertFalse(app.staticTexts["Done · self-reported"].exists)
        tap("Continue activity", in: app)
        tap("I did it", in: app)
        tap("Helpful", in: app)
        tap("Done for now", in: app)
        let completed = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Done · self-reported")).firstMatch
        XCTAssertTrue(reveal(completed, in: app), app.debugDescription)
        let reflected = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Your reflection: Helpful")).firstMatch
        XCTAssertTrue(reveal(reflected, in: app), app.debugDescription)
        tap("Rename", in: app)
        let title = app.alerts.textFields.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let oldTitle = title.value as? String ?? ""
        title.tap(); title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldTitle.count) + "Synthetic history step")
        XCTAssertEqual(title.value as? String, "Synthetic history step")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Synthetic history step"].waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<3 where !app.staticTexts["Closed session"].exists { app.collectionViews.firstMatch.swipeDown() }
        XCTAssertTrue(app.staticTexts["Closed session"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Continue as a new session"].exists)
        capture("Support-History-closed-step", app: app)
        // On iPad the first navigation-bar button is the sidebar toggle, not Back.
        let back = app.navigationBars.buttons["Today"]
        if back.exists { back.tap() } else { app.navigationBars.buttons.element(boundBy: 0).tap() }
        tap("View your history", in: app)
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5), app.debugDescription)
        if app.buttons["Search"].exists { app.buttons["Search"].tap() }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        search.tap(); search.typeText("Synthetic history")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic history step")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.tap()
        XCTAssertTrue(app.staticTexts["Closed session"].waitForExistence(timeout: 5))
        tap("Delete", in: app)
        tap("Delete session", in: app)
        XCTAssertTrue(app.staticTexts["Session unavailable"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic history step")).firstMatch.exists)
    }

    func testFirstRunConsentControlsAndOptionalWelcomeActions() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--support-session-ui-test", "--support-fixture-screen", "onboarding",
            "--support-text-size", "large", "--support-appearance", "light"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Welcome to MindFriend"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Terms of Service")).firstMatch.exists, app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Privacy Policy")).firstMatch.exists, app.debugDescription)
        let birthYear = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Birth year")).firstMatch
        XCTAssertTrue(birthYear.exists, app.debugDescription)
        birthYear.tap()
        let year = String(Calendar(identifier: .gregorian).component(.year, from: Date()) - 13)
        XCTAssertTrue(app.buttons[year].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons[year].tap()
        app.switches["My thirteenth birthday has already occurred"].tap()
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        let terms = app.switches["I agree to the Terms of Service and Privacy Policy"]
        XCTAssertTrue(reveal(terms, in: app)); terms.tap()
        tap("Continue", in: app)
        XCTAssertTrue(app.staticTexts["What would be useful right now?"].waitForExistence(timeout: 5))
        for action in ["Talk about something", "Try a short practice", "Explore first", "Review consent"] {
            XCTAssertTrue(app.buttons[action].exists)
        }
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription])
        tap("Support and crisis resources", in: app)
        XCTAssertTrue(app.navigationBars["Crisis Resources"].waitForExistence(timeout: 5), app.debugDescription)
        capture("Support-Onboarding-consent-help", app: app)
    }

    func testMemorySuggestionPreviewShowsTheFullSourceAndStartsWithNothingSelected() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--support-session-ui-test", "--support-fixture-screen", "memory-suggestions",
            "--support-text-size", "large", "--support-appearance", "dark"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Suggest memories"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(app.descendants(matching: .any)["support-fixture-appearance"].firstMatch.value as? String, "dark")
        let row = app.switches["memory-source-f0000000-0000-4000-8000-000000000004"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(row.label.contains("END OF SYNTHETIC PREVIEW"))
        XCTAssertEqual(row.value as? String, "0")
        let generate = app.buttons["Generate suggestions"]
        // A full, selectable source can be taller than one screen; walk the actual Form to its end.
        for _ in 0..<40 {
            if generate.exists && generate.frame.minY > 80 && generate.frame.maxY < app.frame.maxY - 5 { break }
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(generate.exists && generate.frame.minY > 80 && generate.frame.maxY < app.frame.maxY - 5, app.debugDescription)
        XCTAssertFalse(generate.isEnabled, "Opening the preview never selects a source or starts generation")
        capture("Support-Memory-read-only-preview-dark", app: app)
        try app.performAccessibilityAudit(for: [.textClipped, .sufficientElementDescription, .hitRegion])
    }

    func testTodayAuditAndLargestTextActions() throws {
        continueAfterFailure = false
        let app = launch(size: "accessibility5", appearance: "dark")
        defer { app.terminate() }
        tap("Start a conversation", in: app)
        XCTAssertTrue(app.staticTexts["What would be useful right now?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Context"].exists)
        capture("Support-Chat-draft-accessibility5-dark", app: app)
        try app.performAccessibilityAudit(for: [.textClipped, .sufficientElementDescription, .hitRegion])
    }

    private func open(_ destination: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[destination]
        if tab.exists {
            tab.tap()
        } else {
            let root = app.descendants(matching: .any)["support-root-\(destination)"].firstMatch
            XCTAssertTrue(root.waitForExistence(timeout: 5), destination + "\n" + app.debugDescription)
            root.tap()
        }
        XCTAssertTrue(app.navigationBars[destination].waitForExistence(timeout: 5)
                      || app.staticTexts[destination].firstMatch.exists, destination + "\n" + app.debugDescription)
    }

    /// Every destination at every text size: the four destinations stay reachable and each screen is captured.
    func testEveryDestinationAtEveryTextSize() throws {
        continueAfterFailure = false
        let appearance = ProcessInfo.processInfo.environment["SUPPORT_APPEARANCE"] ?? "light"
        let sizes = ["xSmall", "small", "medium", "large", "xLarge", "xxLarge", "xxxLarge",
                     "accessibility1", "accessibility2", "accessibility3", "accessibility4", "accessibility5"]
        for size in sizes {
            let app = launch(size: size, appearance: appearance)
            assertFourDestinations(in: app)
            for destination in ["Today", "Chat", "Explore", "You"] {
                open(destination, in: app)
                capture("Support-\(destination)-\(appearance)-\(size)", app: app)
            }
            app.terminate()
        }
    }

    /// The full system audit on every destination, under whatever accessibility settings the simulator has.
    func testEveryDestinationPassesTheFullAccessibilityAudit() throws {
        continueAfterFailure = true
        let environment = ProcessInfo.processInfo.environment
        let appearance = environment["SUPPORT_APPEARANCE"] ?? "light"
        let size = environment["SUPPORT_TEXT_SIZE"] ?? "system"
        let label = environment["SUPPORT_SETTINGS_LABEL"] ?? "default"
        let app = launch(size: size, appearance: appearance)
        defer { app.terminate() }
        for destination in ["Today", "Chat", "Explore", "You"] {
            open(destination, in: app)
            capture("Audit-\(destination)-\(label)-\(appearance)-\(size)", app: app)
            try app.performAccessibilityAudit(for: .all) { issue in
                // The DEBUG fixture's appearance overlay is test scaffolding, not app UI.
                if issue.element?.identifier == "support-fixture-appearance" { return true }
                XCTFail("\(destination) [\(label) \(appearance) \(size)]: \(issue.auditType) \(issue.compactDescription) — \(issue.element?.debugDescription ?? "no element")")
                return true
            }
        }
    }

    func testAllTextSizesInBothAppearances() throws {
        continueAfterFailure = false
        let sizes = ["xSmall", "small", "medium", "large", "xLarge", "xxLarge", "xxxLarge",
                     "accessibility1", "accessibility2", "accessibility3", "accessibility4", "accessibility5"]
        for appearance in ["light", "dark"] {
            for size in sizes {
                let app = launch(size: size, appearance: appearance)
                let primary = app.buttons["Start a conversation"]
                XCTAssertTrue(reveal(primary, in: app), "\(appearance) \(size)\n" + app.debugDescription)
                XCTAssertTrue(app.buttons["Support and crisis resources"].exists)
                capture("Support-Today-\(appearance)-\(size)", app: app)
                app.terminate()
            }
        }
    }

    func testLandscapeKeepsTheFourDestinationsAndPrimaryActionReachable() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(size: "accessibility3", appearance: "dark")
        defer { app.terminate() }
        XCTAssertGreaterThan(app.frame.width, app.frame.height, "The application must actually render in landscape.")
        assertFourDestinations(in: app)
        XCTAssertTrue(reveal(app.buttons["Start a conversation"], in: app))
        capture("Support-Today-landscape-accessibility3-dark", app: app)
    }

    func testLongPartialVoiceCaptionKeepsExitControlsVisibleInLandscape() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--support-session-ui-test", "--support-fixture-screen", "voice-layout",
            "--support-text-size", "accessibility5", "--support-appearance", "dark"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Illustrative voice layout · microphone off"].waitForExistence(timeout: 20))
        XCTAssertGreaterThan(app.frame.width, app.frame.height, "The application must actually render in landscape.")
        XCTAssertTrue(app.buttons["End voice session"].isHittable)
        XCTAssertTrue(app.buttons["Switch to text"].isHittable)
        XCTAssertTrue(app.buttons["Unmute microphone"].isHittable)
        let caption = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Assistant caption, live, not final")).firstMatch
        XCTAssertTrue(caption.exists, app.debugDescription)
        XCTAssertEqual(caption.value as? String, String(repeating: "Synthetic partial speech for a layout check. ", count: 30))
        capture("Support-Voice-layout-only-landscape-accessibility5", app: app)
        app.buttons["Switch to text"].tap()
        XCTAssertTrue(app.buttons["End voice session"].isHittable)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion])
    }
}
