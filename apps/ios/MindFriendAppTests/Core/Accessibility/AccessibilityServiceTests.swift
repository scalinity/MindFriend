// Exercises the real Supabase client through an isolated, in-memory transport.
import Combine
import XCTest
@testable import MindFriendApp
import Supabase

@MainActor
final class AccessibilityServiceTests: XCTestCase {
    private var service: AccessibilityService!
    private var fixture: AccessibilityHTTPFixture!
    private let userID = UUID()

    override func setUp() {
        super.setUp()
        fixture = AccessibilityHTTPFixture()
        service = AccessibilityService(supabase: fixture.client)
    }

    override func tearDown() {
        service = nil
        fixture.close()
        fixture = nil
        super.tearDown()
    }

    func testLoadPreferencesDecodesResponseAndScopesQueryToCurrentUser() async throws {
        try await fixture.signIn(userID: userID)
        var expected = AccessibilityPreferences.default
        expected.userId = userID
        expected.hapticFeedbackEnabled = false
        expected.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        expected.updatedAt = expected.createdAt
        try fixture.respond("GET", "/rest/v1/accessibility_preferences", value: expected)
        service.error = AccessibilityError.invalidPreferences
        var loadingStates: [Bool] = []
        let observation = service.$isLoading.sink { loadingStates.append($0) }
        defer { observation.cancel() }

        try await service.loadPreferences()

        XCTAssertEqual(service.preferences, expected)
        XCTAssertNil(service.error)
        XCTAssertEqual(loadingStates, [false, true, false])
        let request = try XCTUnwrap(fixture.requests.last)
        XCTAssertEqual(query(request, "user_id"), "eq.\(userID.uuidString)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.pgrst.object+json")
    }

    func testLoadPreferencesWithoutUserMakesNoRequest() async {
        await XCTAssertThrowsErrorAsync(try await service.loadPreferences()) {
            XCTAssertEqual($0 as? AccessibilityError, .invalidPreferences)
        }
        XCTAssertFalse(service.isLoading)
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    func testLoadPreferencesPropagatesTransportErrorAndResetsLoading() async throws {
        try await fixture.signIn(userID: userID)
        fixture.fail("GET", "/rest/v1/accessibility_preferences", code: .notConnectedToInternet)
        await XCTAssertThrowsErrorAsync(try await service.loadPreferences()) {
            XCTAssertEqual(($0 as? URLError)?.code, .notConnectedToInternet)
        }
        XCTAssertFalse(service.isLoading)
    }

    func testLoadPreferencesPropagatesMalformedResponse() async throws {
        try await fixture.signIn(userID: userID)
        fixture.respond("GET", "/rest/v1/accessibility_preferences", data: Data("{}".utf8))
        await XCTAssertThrowsErrorAsync(try await service.loadPreferences()) {
            XCTAssertTrue($0 is DecodingError)
        }
        XCTAssertFalse(service.isLoading)
    }

    func testSavePreferencesUsesCurrentOwnerAndUpdatedTimestamp() async throws {
        try await fixture.signIn(userID: userID)
        fixture.respond("POST", "/rest/v1/accessibility_preferences")
        service.preferences.userId = UUID()
        service.preferences.updatedAt = Date(timeIntervalSince1970: 0)
        service.preferences.hapticFeedbackEnabled = false
        service.error = AccessibilityError.invalidPreferences
        let beforeSave = Date().addingTimeInterval(-1)

        try await service.savePreferences()

        let body = try fixture.lastJSONBody()
        XCTAssertEqual(body["user_id"] as? String, userID.uuidString)
        XCTAssertEqual(body["haptic_feedback_enabled"] as? Bool, false)
        let timestamp = try XCTUnwrap(body["updated_at"] as? String)
        let dateData = try JSONSerialization.data(withJSONObject: timestamp, options: .fragmentsAllowed)
        let savedAt = try PostgrestClient.Configuration.jsonDecoder.decode(Date.self, from: dateData)
        XCTAssertGreaterThanOrEqual(savedAt, beforeSave)
        XCTAssertLessThanOrEqual(savedAt, Date())
        XCTAssertNil(service.error)
        XCTAssertFalse(service.isLoading)
    }

    func testSavePreferencesWithoutUserMakesNoRequest() async {
        await XCTAssertThrowsErrorAsync(try await service.savePreferences()) {
            XCTAssertEqual($0 as? AccessibilityError, .invalidPreferences)
        }
        XCTAssertFalse(service.isLoading)
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    func testSavePreferencesPropagatesDatabaseError() async throws {
        try await fixture.signIn(userID: userID)
        fixture.respond("POST", "/rest/v1/accessibility_preferences", status: 403,
                        data: Data(#"{"code":"42501","message":"fixture denied","details":null,"hint":null}"#.utf8))
        await XCTAssertThrowsErrorAsync(try await service.savePreferences()) {
            XCTAssertEqual(($0 as? PostgrestError)?.code, "42501")
        }
        XCTAssertFalse(service.isLoading)
    }

    func testUpdatePreferenceSavesLatestValuesAfterDebounce() async throws {
        try await fixture.signIn(userID: userID)
        fixture.respond("POST", "/rest/v1/accessibility_preferences")
        let saved = expectation(description: "Debounced save finished")
        let observation = service.$isLoading.dropFirst().filter { !$0 }.sink { _ in saved.fulfill() }
        defer { observation.cancel() }

        service.updatePreference(\.hapticFeedbackEnabled, to: false)
        service.updatePreference(\.preferredLanguage, to: "es")
        XCTAssertFalse(service.preferences.hapticFeedbackEnabled)
        await fulfillment(of: [saved], timeout: 3)

        let requests = fixture.requests.filter { $0.url?.path == "/rest/v1/accessibility_preferences" }
        XCTAssertEqual(requests.count, 1)
        let body = try fixture.lastJSONBody()
        XCTAssertEqual(body["haptic_feedback_enabled"] as? Bool, false)
        XCTAssertEqual(body["preferred_language"] as? String, "es")
    }

    func testDebouncedFailurePublishesError() async throws {
        try await fixture.signIn(userID: userID)
        fixture.fail("POST", "/rest/v1/accessibility_preferences", code: .notConnectedToInternet)
        let failed = expectation(description: "Debounced failure published")
        let observation = service.$error.compactMap { $0 }.sink { error in
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
            failed.fulfill()
        }
        defer { observation.cancel() }

        service.updatePreference(\.hapticFeedbackEnabled, to: false)
        await fulfillment(of: [failed], timeout: 3)
        XCTAssertFalse(service.isLoading)
    }

    func testGetCaptionsDecodesContentAndSendsPreferredLanguage() async throws {
        let contentID = UUID()
        service.preferences.preferredLanguage = "es"
        let expected = AudioCaptions(available: true, language: "es", format: .vtt,
            captionsUrl: "https://fixture.invalid/captions.vtt",
            captions: [CaptionCue(id: 1, startTime: 0, endTime: 5, text: "Hola")],
            transcript: "Hola", duration: 5)
        try fixture.respond("POST", "/functions/v1/get-captions", value: expected)

        let actual = try await service.getCaptions(for: "exercise", contentId: contentID)

        XCTAssertEqual(actual, expected)
        let body = try fixture.lastJSONBody()
        XCTAssertEqual(body["contentType"] as? String, "exercise")
        XCTAssertEqual(body["contentId"] as? String, contentID.uuidString)
        XCTAssertEqual(body["language"] as? String, "es")
    }

    func testUnavailableCaptionsReturnNoCues() async throws {
        fixture.respond("POST", "/functions/v1/get-captions", data: Data(#"{"available":false}"#.utf8))
        let captions = try await service.getCaptions(for: "exercise", contentId: UUID())
        XCTAssertFalse(captions.available)
        let cues = try await service.getCaptionCues(for: "exercise", contentId: UUID(), language: "en")
        XCTAssertTrue(cues.isEmpty)
    }

    func testCaptionCueBoundariesAreInclusiveAtStartAndExclusiveAtEnd() {
        let cues = [CaptionCue(id: 1, startTime: 0, endTime: 5, text: "Hello"),
                    CaptionCue(id: 2, startTime: 5, endTime: 10, text: "World")]
        XCTAssertNil(service.getCaptionCuesForTimestamp(-1, in: cues))
        XCTAssertEqual(service.getCaptionCuesForTimestamp(0, in: cues)?.id, 1)
        XCTAssertEqual(service.getCaptionCuesForTimestamp(5, in: cues)?.id, 2)
        XCTAssertNil(service.getCaptionCuesForTimestamp(10, in: cues))
    }

    func testLocalizedStringsDecodeISODateAndProvideFallbacksAndPlurals() async throws {
        fixture.respond("POST", "/functions/v1/get-localized-strings", data: localizedResponse())
        let bundle = try await service.getLocalizedStrings()
        XCTAssertEqual(bundle.updatedAt.timeIntervalSince1970, 1_700_000_000.123, accuracy: 0.001)
        XCTAssertEqual(service.localizedString("greeting"), "Hello")
        XCTAssertEqual(service.localizedString("missing"), "missing")
        XCTAssertEqual(service.localizedString("exercises", count: 1), "1 exercise")
        XCTAssertEqual(service.localizedString("exercises", count: 5), "%d exercises")
        XCTAssertTrue(try fixture.lastJSONBody()["region"] is NSNull)
    }

    func testLocalizedStringsCacheAndForceRefresh() async throws {
        fixture.respond("POST", "/functions/v1/get-localized-strings", data: localizedResponse())
        let initial = try await service.getLocalizedStrings()
        fixture.respond("POST", "/functions/v1/get-localized-strings", data: localizedResponse(greeting: "Updated"))
        let cached = try await service.getLocalizedStrings()
        XCTAssertEqual(cached, initial)
        XCTAssertEqual(fixture.requests.count, 1)

        let refreshed = try await service.getLocalizedStrings(forceRefresh: true)
        XCTAssertEqual(refreshed.strings["greeting"]?.value, "Updated")
        XCTAssertEqual(fixture.requests.count, 2)
    }

    func testLocalizedStringCacheSeparatesRegions() async throws {
        fixture.respond("POST", "/functions/v1/get-localized-strings", data: localizedResponse())
        _ = try await service.getLocalizedStrings()
        service.preferences.preferredRegion = "GB"
        fixture.respond("POST", "/functions/v1/get-localized-strings", data: localizedResponse(greeting: "Hello GB"))
        _ = try await service.getLocalizedStrings()
        XCTAssertEqual(try fixture.lastJSONBody()["region"] as? String, "GB")
        XCTAssertEqual(service.localizedString("greeting"), "Hello GB")
        service.preferences.preferredRegion = nil
        XCTAssertEqual(service.localizedString("greeting"), "Hello")
        XCTAssertEqual(fixture.requests.count, 2)
    }

    func testSignLanguageVideoQueryAndEmptyResult() async throws {
        let contentID = UUID()
        let video = SignLanguageVideo(id: UUID(), contentType: "exercise", contentId: contentID,
            signLanguage: .asl, videoUrl: "https://fixture.invalid/video.mp4", thumbnailUrl: nil, durationSeconds: 30)
        try fixture.respond("GET", "/rest/v1/sign_language_videos", value: [video])
        let actual = try await service.getSignLanguageVideo(for: "exercise", contentId: contentID)
        XCTAssertEqual(actual, video)
        let request = try XCTUnwrap(fixture.requests.last)
        XCTAssertEqual(query(request, "content_type"), "eq.exercise")
        XCTAssertEqual(query(request, "content_id"), "eq.\(contentID.uuidString)")
        fixture.respond("GET", "/rest/v1/sign_language_videos", data: Data("[]".utf8))
        let missing = try await service.getSignLanguageVideo(for: "exercise", contentId: contentID)
        XCTAssertNil(missing)
    }

    func testSubmitFeedbackSendsCurrentOwnerAndFields() async throws {
        try await fixture.signIn(userID: userID)
        fixture.respond("POST", "/rest/v1/accessibility_feedback")
        try await service.submitFeedback(feedback())
        let body = try fixture.lastJSONBody()
        XCTAssertEqual(body["user_id"] as? String, userID.uuidString)
        XCTAssertEqual(body["category"] as? String, "visual")
        XCTAssertEqual(body["screen_name"] as? String, "settings")
        XCTAssertEqual(body["element_identifier"] as? String, "contrast")
        XCTAssertEqual(body["issue_type"] as? String, "missing_label")
        XCTAssertEqual(body["description"] as? String, "Missing label")
        XCTAssertEqual(body["assistive_tech_used"] as? String, "voiceover")
    }

    func testSubmitFeedbackRejectsEmptyDescriptionWithoutRequest() async {
        await XCTAssertThrowsErrorAsync(try await service.submitFeedback(feedback(description: ""))) {
            XCTAssertEqual($0 as? AccessibilityError, .invalidFeedback("Description is required"))
        }
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    func testSubmitFeedbackRejectsMissingUserWithoutRequest() async {
        await XCTAssertThrowsErrorAsync(try await service.submitFeedback(feedback())) {
            XCTAssertEqual($0 as? AccessibilityError, .invalidFeedback("User not authenticated"))
        }
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    private func feedback(description: String = "Missing label") -> AccessibilityFeedback {
        AccessibilityFeedback(category: .visual, screenName: "settings", elementIdentifier: "contrast",
            issueType: .missingLabel, description: description, assistiveTechUsed: [.voiceover])
    }

    private func query(_ request: URLRequest, _ name: String) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    private func localizedResponse(greeting: String = "Hello") -> Data {
        Data("""
        {"language":"en","region":null,"strings":{"greeting":{"value":"\(greeting)"},
        "exercises":{"value":"exercises","plurals":{"one":"1 exercise","other":"%d exercises"}}},
        "updated_at":"2023-11-14T22:13:20.123Z"}
        """.utf8)
    }
}

private final class AccessibilityHTTPFixture: @unchecked Sendable {
    private struct Response {
        var status = 200
        var data = Data()
        var error: URLError?
    }
    let client: SupabaseClient
    private let session: URLSession
    private let host = "accessibility-\(UUID().uuidString.lowercased()).invalid"
    private let lock = NSLock()
    private var responses: [String: Response] = [:]
    private var capturedRequests: [URLRequest] = []

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccessibilityURLProtocol.self]
        session = URLSession(configuration: configuration)
        client = SupabaseClient(supabaseURL: URL(string: "https://\(host)")!, supabaseKey: "fixture-only",
            options: SupabaseClientOptions(auth: .init(storage: AccessibilityMemoryStorage(), autoRefreshToken: false),
                                           global: .init(session: session)))
        AccessibilityURLProtocol.register(self, host: host)
    }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return capturedRequests
    }

    func close() {
        AccessibilityURLProtocol.unregister(host: host)
        session.invalidateAndCancel()
    }

    func respond(_ method: String, _ path: String, status: Int = 200, data: Data = Data()) {
        lock.lock(); defer { lock.unlock() }
        responses["\(method) \(path)"] = Response(status: status, data: data)
    }

    func respond<T: Encodable>(_ method: String, _ path: String, value: T) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        respond(method, path, data: try encoder.encode(value))
    }

    func fail(_ method: String, _ path: String, code: URLError.Code) {
        lock.lock(); defer { lock.unlock() }
        responses["\(method) \(path)"] = Response(error: URLError(code))
    }

    func signIn(userID: UUID) async throws {
        let user = Data("""
        {"id":"\(userID)","aud":"authenticated","role":"authenticated","app_metadata":{},"user_metadata":{},
        "created_at":"2023-11-14T22:13:20Z","updated_at":"2023-11-14T22:13:20Z"}
        """.utf8)
        respond("GET", "/auth/v1/user", data: user)
        func base64URL(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let header = base64URL(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
        let payload = base64URL(try JSONSerialization.data(withJSONObject:
            ["sub": userID.uuidString, "exp": Int(Date().timeIntervalSince1970) + 3600]))
        _ = try await client.auth.setSession(accessToken: "\(header).\(payload).fixture", refreshToken: "fixture-refresh")
    }

    func lastJSONBody() throws -> [String: Any] {
        let body = try XCTUnwrap(requests.last?.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    fileprivate func handle(_ original: URLRequest) throws -> (HTTPURLResponse, Data) {
        var request = original
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                if count == 0 { break }
                data.append(buffer, count: count)
            }
            request.httpBody = data
        }
        lock.lock()
        capturedRequests.append(request)
        let response = responses["\(request.httpMethod ?? "GET") \(request.url!.path)"]
        lock.unlock()
        guard let response else { throw URLError(.unsupportedURL) }
        if let error = response.error { throw error }
        return (HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil,
                                headerFields: ["Content-Type": "application/json"])!, response.data)
    }
}

private final class AccessibilityURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var fixtures: [String: AccessibilityHTTPFixture] = [:]

    static func register(_ fixture: AccessibilityHTTPFixture, host: String) {
        lock.lock(); defer { lock.unlock() }
        fixtures[host] = fixture
    }
    static func unregister(host: String) {
        lock.lock(); defer { lock.unlock() }
        fixtures.removeValue(forKey: host)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let fixture = Self.fixtures[request.url?.host ?? ""]
        Self.lock.unlock()
        do {
            guard let fixture else { throw URLError(.unsupportedURL) }
            let (response, data) = try fixture.handle(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private final class AccessibilityMemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }
    func retrieve(key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }
    func remove(key: String) {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}

// MARK: - Test Helper

extension XCTestCase {
    func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ errorHandler: (Error) -> Void = { _ in }
    ) async {
        do {
            _ = try await expression()
            XCTFail(message(), file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}
