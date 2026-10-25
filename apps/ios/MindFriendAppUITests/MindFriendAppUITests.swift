import XCTest
import StoreKitTest

final class MindFriendAppUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
    }

    override func tearDownWithError() throws {
        app = nil
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

        // Check feature descriptions are visible
        let features = [
            "Daily wellness quests",
            "AI-powered chat support",
            "Track your mood journey",
            "Connect with friends"
        ]

        for feature in features {
            let featureText = app.staticTexts[feature]
            XCTAssertTrue(featureText.exists, "Feature '\(feature)' should be visible")
        }
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

    // MARK: - Navigation Tests

    #if DEBUG
    func testDevSkipSignIn() throws {
        app.launch()

        // Look for dev-only skip button
        let skipButton = app.buttons["Skip Sign In (Dev Only)"]

        if skipButton.waitForExistence(timeout: 3) {
            skipButton.tap()

            // Should navigate to main tab view
            let tabBar = app.tabBars.firstMatch
            XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        }
    }
    #endif
}

// MARK: - Launch Performance Tests

final class MindFriendAppLaunchTests: XCTestCase {

    func testLaunchPerformance() throws {
        if #available(iOS 17.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
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
        XCTAssertTrue(app.staticTexts["Last Night"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Last Night"].isHittable)
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
