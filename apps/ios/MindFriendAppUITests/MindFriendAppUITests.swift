import XCTest

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
        let signInWithGoogleButton = app.buttons["Sign in with Google"]

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

        let signInWithAppleButton = app.buttons["Sign in with Apple"]
        XCTAssertTrue(signInWithAppleButton.waitForExistence(timeout: 5))

        // Check accessibility
        XCTAssertTrue(signInWithAppleButton.isAccessibilityElement)

        let signInWithGoogleButton = app.buttons["Sign in with Google"]
        XCTAssertTrue(signInWithGoogleButton.isAccessibilityElement)
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
