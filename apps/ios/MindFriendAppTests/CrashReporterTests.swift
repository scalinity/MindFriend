import XCTest
import Sentry
@testable import MindFriendApp

/// Exercises the same callbacks installed by initialize(), without starting Sentry.
final class CrashReporterTests: XCTestCase {
    func testEventScrubsSensitiveKeysInNestedDictionariesAndArrays() throws {
        let event = Event()
        event.extra = [
            "email": "person@example.invalid",
            "nested": ["display_name": "Synthetic Person", "status": "retrying"],
            "items": [["refresh_token": "synthetic-secret", "attempt": 2], "contact person@example.invalid"],
            "retry_count": 3,
            "operation": "load_profile"
        ]

        let result = try XCTUnwrap(CrashReporter.scrubPII(from: event))
        let extra = try XCTUnwrap(result.extra)
        XCTAssertEqual(extra["email"] as? String, "[redacted]")
        let nested = try XCTUnwrap(extra["nested"] as? [String: Any])
        XCTAssertEqual(nested["display_name"] as? String, "[redacted]")
        XCTAssertEqual(nested["status"] as? String, "retrying")
        let items = try XCTUnwrap(extra["items"] as? [Any])
        let first = try XCTUnwrap(items.first as? [String: Any])
        XCTAssertEqual(first["refresh_token"] as? String, "[redacted]")
        XCTAssertEqual(first["attempt"] as? Int, 2)
        XCTAssertEqual(items[1] as? String, "contact [email]")
        XCTAssertEqual(extra["retry_count"] as? Int, 3)
        XCTAssertEqual(extra["operation"] as? String, "load_profile")
    }

    func testEventScrubsMessageExceptionsBreadcrumbsAndTokenURLs() throws {
        let event = Event()
        event.message = SentryMessage(formatted: "Contact person@example.invalid or (212) 555-0123")
        event.message?.message = "Contact %@ at person@example.invalid"
        event.message?.params = ["person@example.invalid"]
        event.exceptions = [Exception(value: "Contact person@example.invalid", type: "SyntheticFailure")]
        let breadcrumb = Breadcrumb(level: .info, category: "network")
        breadcrumb.message = "Opening /invite/ABC123"
        breadcrumb.setData(value: "https://example.invalid/callback?access_token=synthetic-secret&screen=home", key: "url")
        event.breadcrumbs = [breadcrumb]

        let result = try XCTUnwrap(CrashReporter.scrubPII(from: event))
        let message = try XCTUnwrap(result.message?.formatted)
        XCTAssertTrue(message.contains("[email]"))
        XCTAssertTrue(message.contains("[phone]"))
        XCTAssertFalse(message.contains("person@example.invalid"))
        XCTAssertFalse(message.contains("555-0123"))
        XCTAssertEqual(result.message?.message, "Contact %@ at [email]")
        XCTAssertEqual(result.message?.params, ["[email]"])
        XCTAssertEqual(result.exceptions?.first?.value, "Contact [email]")
        XCTAssertEqual(result.breadcrumbs?.first?.message, "Opening /invite/[redacted]")
        XCTAssertEqual(result.breadcrumbs?.first?.data?["url"] as? String,
                       "https://example.invalid/callback?access_token=[redacted]&screen=home")
    }

    func testEventRemovesContactIdentityButKeepsCorrelationAndSafeTags() throws {
        let event = Event()
        let owner = "11111111-1111-4111-8111-111111111111"
        event.user = Sentry.User(userId: owner)
        event.user?.email = "person@example.invalid"
        event.user?.username = "synthetic-person"
        event.tags = ["email": "person@example.invalid", "feature": "sleep", "status": "retrying"]

        let result = try XCTUnwrap(CrashReporter.scrubPII(from: event))
        XCTAssertNil(result.user?.email)
        XCTAssertNil(result.user?.username)
        XCTAssertEqual(result.user?.userId, owner)
        XCTAssertEqual(result.tags?["email"], "[redacted]")
        XCTAssertEqual(result.tags?["feature"], "sleep")
        XCTAssertEqual(result.tags?["status"], "retrying")
    }

    func testLogCallbackDropsSensitiveBodiesAndKeepsSafeDiagnostics() {
        for body in ["person@example.invalid", "Call (212) 555-0123", "/invite/ABC123",
                     "https://example.invalid/callback?token=synthetic-secret"] {
            XCTAssertNil(CrashReporter.scrubPIIFromLog(SentryLog(level: .info, body: body)), body)
        }
        let safe = SentryLog(level: .info, body: "Profile request failed after 3 attempts")
        XCTAssertTrue(CrashReporter.scrubPIIFromLog(safe) === safe)
    }

    func testURLSanitizerKeepsSafeQueryAndRedactsEncodedSecrets() throws {
        let url = try XCTUnwrap(URL(string: "https://example.invalid/callback?ACCESS_TOKEN=secret%2Bvalue&screen=home"))
        let components = try XCTUnwrap(URLComponents(string: CrashReporter.sanitizeURL(url)))
        XCTAssertEqual(components.queryItems?.first?.value, "[redacted]")
        XCTAssertEqual(components.queryItems?.last?.value, "home")
    }
}

final class CrashReportingEnvironmentTests: XCTestCase {
    func testDebugBuildIsDevelopment() {
        XCTAssertEqual(
            CrashReportingEnvironment.resolve(isDebugBuild: true, hasEmbeddedProvisioningProfile: false, receiptFileName: "receipt"),
            CrashReportingEnvironment.development
        )
    }

    func testSelfInstalledReleaseBuildIsDevelopment() {
        XCTAssertEqual(
            CrashReportingEnvironment.resolve(isDebugBuild: false, hasEmbeddedProvisioningProfile: true, receiptFileName: nil),
            CrashReportingEnvironment.development
        )
        XCTAssertEqual(
            CrashReportingEnvironment.resolve(isDebugBuild: false, hasEmbeddedProvisioningProfile: true, receiptFileName: "receipt"),
            CrashReportingEnvironment.development
        )
    }

    func testTestFlightInstallIsTestFlight() {
        XCTAssertEqual(
            CrashReportingEnvironment.resolve(isDebugBuild: false, hasEmbeddedProvisioningProfile: false, receiptFileName: "sandboxReceipt"),
            CrashReportingEnvironment.testFlight
        )
    }

    func testAppStoreInstallIsProduction() {
        XCTAssertEqual(
            CrashReportingEnvironment.resolve(isDebugBuild: false, hasEmbeddedProvisioningProfile: false, receiptFileName: "receipt"),
            CrashReportingEnvironment.production
        )
        XCTAssertEqual(
            CrashReportingEnvironment.resolve(isDebugBuild: false, hasEmbeddedProvisioningProfile: false, receiptFileName: nil),
            CrashReportingEnvironment.production
        )
    }
}

final class TestRunDetectorTests: XCTestCase {
    func testUnitTestHostIsATestRun() {
        XCTAssertTrue(TestRunDetector.resolve(
            isDebugBuild: true,
            environment: ["XCTestConfigurationFilePath": "/tmp/synthetic.xctestconfiguration"],
            arguments: []
        ))
        XCTAssertTrue(TestRunDetector.resolve(
            isDebugBuild: true,
            environment: ["XCTestBundlePath": "/tmp/MindFriendAppTests.xctest"],
            arguments: []
        ))
    }

    func testUITestFixtureLaunchIsATestRun() {
        for argument in ["--auth-ui-test", "--subscription-ui-test", "--sleep-ui-test", "--debt-calendar-ui-test", "--support-session-ui-test"] {
            XCTAssertTrue(
                TestRunDetector.resolve(isDebugBuild: true, environment: [:], arguments: ["MindFriendApp", argument]),
                argument
            )
        }
    }

    func testNormalLaunchIsNotATestRun() {
        XCTAssertFalse(TestRunDetector.resolve(
            isDebugBuild: true,
            environment: ["HOME": "/tmp"],
            arguments: ["MindFriendApp", "--sleep-auto-sync"]
        ))
    }

    func testReleaseBuildIsNeverATestRun() {
        XCTAssertFalse(TestRunDetector.resolve(
            isDebugBuild: false,
            environment: ["XCTestConfigurationFilePath": "/tmp/synthetic.xctestconfiguration"],
            arguments: ["--auth-ui-test"]
        ))
    }

    /// The process running this test is the unit-test host, so Sentry must be off.
    func testSentryIsOffWhileHostingUnitTests() {
        XCTAssertTrue(TestRunDetector.isTestRun)
        XCTAssertFalse(CrashReporter.shared.isEnabled)
    }
}
