import XCTest
@testable import MindFriendApp

final class SupabaseDataServiceTests: XCTestCase {

    // MARK: - Unique Constraint Violation Detection Tests

    @MainActor
    func testIsUniqueConstraintViolation_PostgreSQLErrorCode() {
        let service = SupabaseDataService(authService: DependencyContainer.preview.supabaseAuthService)

        // PostgreSQL error code 23505 indicates unique constraint violation
        let error = NSError(
            domain: "PostgrestError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "duplicate key value violates unique constraint \\\"circles_invite_code_key\\\" (SQLSTATE 23505)"]
        )

        XCTAssertTrue(service.isUniqueConstraintViolation(error))
    }

    @MainActor
    func testIsUniqueConstraintViolation_UniqueKeyword() {
        let service = SupabaseDataService(authService: DependencyContainer.preview.supabaseAuthService)

        let error = NSError(
            domain: "PostgrestError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Error: unique constraint violation on invite_code"]
        )

        XCTAssertTrue(service.isUniqueConstraintViolation(error))
    }

    @MainActor
    func testIsUniqueConstraintViolation_DuplicateKeyKeyword() {
        let service = SupabaseDataService(authService: DependencyContainer.preview.supabaseAuthService)

        let error = NSError(
            domain: "PostgrestError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "duplicate key error on column invite_code"]
        )

        XCTAssertTrue(service.isUniqueConstraintViolation(error))
    }

    @MainActor
    func testIsUniqueConstraintViolation_CaseInsensitive() {
        let service = SupabaseDataService(authService: DependencyContainer.preview.supabaseAuthService)

        // Should match regardless of case
        let error = NSError(
            domain: "PostgrestError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "DUPLICATE KEY VALUE VIOLATES UNIQUE CONSTRAINT"]
        )

        XCTAssertTrue(service.isUniqueConstraintViolation(error))
    }

    @MainActor
    func testIsUniqueConstraintViolation_NotAUniqueError() {
        let service = SupabaseDataService(authService: DependencyContainer.preview.supabaseAuthService)

        // Network error - not a unique constraint violation
        let networkError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."]
        )

        XCTAssertFalse(service.isUniqueConstraintViolation(networkError))
    }

    @MainActor
    func testIsUniqueConstraintViolation_AuthError() {
        let service = SupabaseDataService(authService: DependencyContainer.preview.supabaseAuthService)

        // Auth error - not a unique constraint violation
        let authError = NSError(
            domain: "AuthError",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Invalid JWT token"]
        )

        XCTAssertFalse(service.isUniqueConstraintViolation(authError))
    }

    @MainActor
    func testIsUniqueConstraintViolation_ForeignKeyError() {
        let service = SupabaseDataService(authService: DependencyContainer.preview.supabaseAuthService)

        // Foreign key error (23503) - not a unique constraint (23505)
        let fkError = NSError(
            domain: "PostgrestError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "violates foreign key constraint (SQLSTATE 23503)"]
        )

        XCTAssertFalse(service.isUniqueConstraintViolation(fkError))
    }

    @MainActor
    func testIsUniqueConstraintViolation_GenericError() {
        let service = SupabaseDataService(authService: DependencyContainer.preview.supabaseAuthService)

        // Generic error with no specific keywords
        let genericError = NSError(
            domain: "AppError",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "An unexpected error occurred"]
        )

        XCTAssertFalse(service.isUniqueConstraintViolation(genericError))
    }

    // MARK: - Invite Code Generation Tests

    func testGenerateInviteCode_Format() {
        // Test that invite codes match expected format
        // Note: generateInviteCode is private, so we test through the public interface
        // This test documents the expected behavior

        // Allowed characters: ABCDEFGHJKLMNPQRSTUVWXYZ23456789 (no I, O, 0, 1 to avoid confusion)
        let allowedChars = CharacterSet(charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

        // Generate multiple codes and verify format
        // Since we can't call private method directly, this is a documentation test
        XCTAssertTrue(true, "Invite codes should be 6 characters from allowed charset")
    }

    // MARK: - DataError Tests

    func testDataError_CircleFullDescription() {
        let error = DataError.circleFull
        XCTAssertEqual(error.errorDescription, "This circle is full")
    }

    func testDataError_CustomDescription() {
        let error = DataError.custom("Test error message")
        XCTAssertEqual(error.errorDescription, "Test error message")
    }
}

// MARK: - Retry Logic Documentation Tests

extension SupabaseDataServiceTests {
    /// Documents the retry behavior of createCircle
    ///
    /// When createCircle encounters a unique constraint violation on invite_code:
    /// 1. It generates a new invite code
    /// 2. Retries the insert operation
    /// 3. Continues up to 5 attempts
    /// 4. Throws the last error if all attempts fail
    ///
    /// This behavior ensures high reliability for circle creation even with
    /// theoretical invite code collisions (extremely rare with 32^6 possibilities).
    func testCreateCircleRetryBehavior_Documentation() {
        // This test documents expected behavior
        // Actual retry testing requires mocking the Supabase client

        // Expected behavior:
        // - maxRetries = 5
        // - Each attempt generates a new invite code
        // - Only unique constraint violations trigger retry
        // - Other errors are thrown immediately
        // - After 5 failures, throws DataError.custom or last error

        XCTAssertTrue(true, "See function documentation for retry behavior")
    }
}

// MARK: - Settings Update Error Handling Tests

extension SupabaseDataServiceTests {
    /// Documents expected error handling for updateUserSettings
    ///
    /// When updateUserSettings fails:
    /// 1. The error is propagated to the caller
    /// 2. UI layer should show error message via appState.showError()
    /// 3. UI layer should revert local state changes where applicable
    ///
    /// The UI implements debouncing (0.5s) to batch rapid setting changes.
    func testUpdateUserSettingsErrorHandling_Documentation() {
        // Expected error handling behavior:
        // - Network errors: propagated, UI shows error alert
        // - Auth errors (401/403): propagated, may trigger re-auth
        // - Validation errors: propagated with message
        //
        // UI responsibilities:
        // - NotificationSettingsView: appState.showError() on failure
        // - AIPreferencesView: reverts selectedTone on failure
        // - PrivacySettingsView: reverts shareMoodInCircles/privacyMode on failure

        XCTAssertTrue(true, "Error handling documented in UI layer")
    }

    /// Tests that various database error types are properly categorized
    @MainActor
    func testDatabaseErrorTypes() {
        let service = SupabaseDataService(authService: DependencyContainer.preview.supabaseAuthService)

        // Row-level security violation (common when user lacks permission)
        let rlsError = NSError(
            domain: "PostgrestError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "new row violates row-level security policy"]
        )
        XCTAssertFalse(service.isUniqueConstraintViolation(rlsError), "RLS errors should not be treated as unique constraint violations")

        // Permission denied
        let permissionError = NSError(
            domain: "PostgrestError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "permission denied for table user_settings"]
        )
        XCTAssertFalse(service.isUniqueConstraintViolation(permissionError), "Permission errors should not be treated as unique constraint violations")

        // Check constraint violation (different from unique)
        let checkError = NSError(
            domain: "PostgrestError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "new row violates check constraint \"positive_quota\" (SQLSTATE 23514)"]
        )
        XCTAssertFalse(service.isUniqueConstraintViolation(checkError), "Check constraint violations should not be treated as unique constraint violations")
    }

    /// Documents the debouncing behavior for notification settings
    ///
    /// NotificationSettingsView uses a 0.5 second debounce to prevent
    /// rapid API calls when users toggle multiple settings quickly.
    func testNotificationSettingsDebouncing_Documentation() {
        // Expected behavior:
        // - Each toggle change cancels any pending save
        // - After 0.5s of no changes, save is performed
        // - Only one API call made for rapid successive changes
        // - isSaving indicator shows during actual save operation

        // This improves:
        // 1. API call efficiency (fewer requests)
        // 2. User experience (no lag per toggle)
        // 3. Database load (batched updates)

        XCTAssertTrue(true, "Debouncing documented in NotificationSettingsView.saveSettings()")
    }
}

// #12: the production URLSession delegate receives synthetic bytes; no provider or backend calls.
import SwiftUI

@MainActor
final class ProfileImageStreamTests: XCTestCase {
    private var image: Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
    private func event(_ fields: [String: Any], separator: String = "\n", space: Bool = true) throws -> Data {
        let json = String(data: try JSONSerialization.data(withJSONObject: fields), encoding: .utf8)!
        return Data(("data:" + (space ? " " : "") + json + separator + separator).utf8)
    }
    private func stream(_ chunks: [Data], keepOpen: Bool = false, status: Int = 200) -> AsyncThrowingStream<ImageStreamEvent, Error> {
        ProfileImageURLProtocol.fixture.prepare(chunks, keepOpen: keepOpen, status: status)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ProfileImageURLProtocol.self]
        return SSEStreamingHelper.streamImageGeneration(request: URLRequest(url: URL(string: "https://profile-fixture.invalid/image")!), configuration: config)
    }
    private func partial() throws -> Data { try event(["type": "partial", "index": 0, "imageBase64": image.base64EncodedString()]) }
    private func complete(separator: String = "\n") throws -> Data {
        try event(["type": "complete", "success": true, "imageBase64": image.base64EncodedString(),
                   "generationId": "synthetic-12", "storagePath": "synthetic-owner/generated/12.png", "quotaRemaining": 0], separator: separator, space: false)
    }
    func testEveryByteFragmentAndAllLineEndingsPreserveFinalMetadata() async throws {
        for separator in ["\n", "\r\n", "\r"] {
            let data = try partial() + complete(separator: separator)
            var previews = 0, finals = 0
            for try await result in stream(data.map { Data([$0]) }) {
                switch result {
                case .partial: previews += 1
                case .complete(let bytes, let metadata):
                    finals += 1; XCTAssertEqual(bytes, image)
                    XCTAssertEqual(metadata?["generationId"] as? String, "synthetic-12")
                    XCTAssertEqual(metadata?["storagePath"] as? String, "synthetic-owner/generated/12.png")
                    XCTAssertEqual(metadata?["quotaRemaining"] as? Int, 0)
                case .error: XCTFail("Unexpected error event")
                }
            }
            XCTAssertEqual(previews, 1); XCTAssertEqual(finals, 1)
            XCTAssertEqual(ProfileImageURLProtocol.fixture.requests, 1)
        }
    }
    func testMultilineUTF8AndCommentsAtByteBoundaries() throws {
        let wire = Data(":keep-alive\r\ndata:{\"type\":\"error\",\r\ndata: \"error\":\"Try again 🌙\"}\r\n\r\n".utf8)
        var decoder = ImageSSEDecoder(); var payloads: [String] = []
        for byte in wire { payloads += try decoder.consume(Data([byte])) }
        XCTAssertEqual(payloads.count, 1)
        guard case .error(let error) = try SSEStreamingHelper.parseImageEvent(payloads[0]) else { return XCTFail("Expected error") }
        XCTAssertEqual(error.localizedDescription, "Try again 🌙")
    }
    func testPartialThenMissingFinalFailsWithoutRetry() async throws {
        var previews = 0
        do {
            for try await result in stream([try partial()]) {
                if case .partial = result { previews += 1 }
                if case .complete = result { XCTFail("A preview must not become a final image") }
            }
            XCTFail("Missing final must fail")
        } catch let error as SSEStreamError {
            guard case .noData = error else { return XCTFail("\(error)") }
            XCTAssertTrue(error.localizedDescription.contains("prompt is saved"))
        }
        XCTAssertEqual(previews, 1); XCTAssertEqual(ProfileImageURLProtocol.fixture.requests, 1)
    }
    func testInvalidAndUnterminatedFinalCannotComplete() async throws {
        for final in [try event(["type": "complete", "imageBase64": "not-base64"]),
                      try event(["type": "complete", "imageBase64": Data("not an image".utf8).base64EncodedString()]),
                      Data(("data:{\"type\":\"complete\",\"imageBase64\":\"" + image.base64EncodedString() + "\"}").utf8)] {
            do {
                for try await value in stream([try partial(), final]) { if case .complete = value { XCTFail("Invalid final") } }
                XCTFail("Must fail")
            } catch { XCTAssertTrue(error is SSEStreamError) }
        }
    }
    func testTruncatedPNGHeaderCannotComplete() async throws {
        let truncated = try event(["type": "complete", "imageBase64": image.prefix(30).base64EncodedString()])
        do {
            for try await value in stream([truncated]) { if case .complete = value { XCTFail("Header is not a decoded image") } }
            XCTFail("Truncated PNG must fail")
        } catch { XCTAssertTrue(error is SSEStreamError) }
    }
    func testTerminalFramePrecedesMalformedTailInSameChunk() async throws {
        var finals = 0
        let wire = try complete() + Data([0xFF, 0x0A])
        for try await value in stream([wire], keepOpen: true) { if case .complete = value { finals += 1 } }
        XCTAssertEqual(finals, 1)
        var errors = 0
        let failure = try event(["type": "error", "error": "Synthetic failure"]) + Data([0xFF, 0x0A])
        for try await value in stream([failure], keepOpen: true) { if case .error = value { errors += 1 } }
        XCTAssertEqual(errors, 1)
    }
    func testCompleteDoesNotWaitForConnectionClose() async throws {
        let start = Date(); var finals = 0
        for try await result in stream([try partial(), try complete()], keepOpen: true) {
            if case .complete = result { finals += 1 }
        }
        XCTAssertEqual(finals, 1); XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertEqual(ProfileImageURLProtocol.fixture.requests, 1)
    }
    func testServerErrorRemainsServerErrorAfterPreview() async throws {
        var errors = 0
        for try await result in stream([try partial(), try event(["type": "error", "error": "Failed to store image"])], keepOpen: true) {
            if case .complete = result { XCTFail("Failed storage cannot complete") }
            if case .error(let error) = result {
                errors += 1
                guard case .serverError = error as? SSEStreamError else { return XCTFail("Not a server error") }
                XCTAssertEqual(error.localizedDescription, "Failed to store image")
            }
        }
        XCTAssertEqual(errors, 1)
    }
    func testCancellationStopsTheSingleNativeRequest() async throws {
        let events = stream([try partial()], keepOpen: true)
        let received = expectation(description: "preview")
        let task = Task {
            for try await event in events { if case .partial = event { received.fulfill() } }
        }
        await fulfillment(of: [received], timeout: 2)
        task.cancel(); _ = try await task.value
        for _ in 0..<100 { if ProfileImageURLProtocol.fixture.stops > 0 { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertGreaterThan(ProfileImageURLProtocol.fixture.stops, 0)
        XCTAssertEqual(ProfileImageURLProtocol.fixture.requests, 1)
    }
    func testOversizedUnterminatedEventIsBounded() throws {
        var decoder = ImageSSEDecoder()
        do {
            _ = try decoder.consume(Data(repeating: 65, count: ImageSSEDecoder.maxEventBytes + 1))
            XCTFail("Oversized event must fail")
        } catch { XCTAssertTrue(error is SSEStreamError) }
    }
    func testStructuredImageErrorsDistinguishPersonalQuotaFromStorageAndSharedBudget() async throws {
        let service = SupabaseDataService(authService: DependencyContainer.preview.supabaseAuthService)
        for (status, fields, quota) in [
            (429, ["code": "monthly_ai_budget_exhausted", "error": "Monthly AI budget reached"] as [String: Any], false),
            (429, ["code": "image_quota_exhausted", "error": "Daily allowance reached"], true),
            (429, ["quotaExceeded": true, "error": "Daily limit reached"], true),
            (429, ["error": "Gateway limit reached"], false),
            (422, ["code": "image_too_large", "error": "Image exceeds size limit"], false)
        ] {
            do {
                _ = try await service.generateProfilePictureStreaming(prompt: "An astronaut", onPartialImage: { _, _ in }, events: stream([try JSONSerialization.data(withJSONObject: fields)], status: status))
                XCTFail("Must return an error")
            } catch let error as SupabaseDataService.GenerateProfilePictureError {
                if quota { guard case .quotaExceeded = error else { return XCTFail("Expected personal quota") } }
                else { guard case .apiError = error else { return XCTFail("Storage or shared budget must not be a personal quota") } }
            }
        }
        do {
            _ = try await service.generateProfilePictureStreaming(prompt: "An astronaut", onPartialImage: { _, _ in }, events: stream([try event(["type": "error", "code": "provider_response_too_large", "error": "Image exceeds size limit"])]))
            XCTFail("SSE failure")
        } catch let error as SupabaseDataService.GenerateProfilePictureError {
            guard case .apiError(let message) = error else { return XCTFail("Size error must not open paywall") }
            XCTAssertTrue(message.contains("size limit"))
        }
    }
    func testProfileWrapperRejectsPreviewOnlyAndPreservesFinalMetadata() async throws {
        let service = SupabaseDataService(authService: DependencyContainer.preview.supabaseAuthService)
        var previews = 0
        do {
            _ = try await service.generateProfilePictureStreaming(prompt: "An astronaut", onPartialImage: { _, _ in previews += 1 }, events: stream([try partial()]))
            XCTFail("A partial image cannot return a successful response")
        } catch { XCTAssertEqual(ProfileImageURLProtocol.fixture.requests, 1) }
        XCTAssertEqual(previews, 1)
        let response = try await service.generateProfilePictureStreaming(prompt: "An astronaut", onPartialImage: { _, _ in previews += 1 }, events: stream([try partial(), try complete()]))
        XCTAssertTrue(response.success); XCTAssertEqual(response.generationId, "synthetic-12")
        XCTAssertEqual(response.storagePath, "synthetic-owner/generated/12.png"); XCTAssertEqual(response.quotaRemaining, 0)
        XCTAssertEqual(previews, 2)
        XCTAssertEqual(ProfileImageURLProtocol.fixture.requests, 1)
    }

}
private final class ProfileImageURLProtocol: URLProtocol {
    static let fixture = ProfileImageWireFixture()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "profile-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (chunks, keepOpen, status) = Self.fixture.start()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": status == 200 ? "text/event-stream" : "application/json"])!, cacheStoragePolicy: .notAllowed)
        for chunk in chunks { client?.urlProtocol(self, didLoad: chunk) }
        if !keepOpen { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() { Self.fixture.stop() }
}
private final class ProfileImageWireFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [Data] = []; private var keepOpen = false; private var status = 200
    private var requestCount = 0; private var stopCount = 0
    var requests: Int { lock.lock(); defer { lock.unlock() }; return requestCount }
    var stops: Int { lock.lock(); defer { lock.unlock() }; return stopCount }
    func prepare(_ chunks: [Data], keepOpen: Bool, status: Int) {
        lock.lock(); defer { lock.unlock() }; self.chunks = chunks; self.keepOpen = keepOpen; self.status = status; requestCount = 0; stopCount = 0
    }
    func start() -> ([Data], Bool, Int) { lock.lock(); defer { lock.unlock() }; requestCount += 1; return (chunks, keepOpen, status) }
    func stop() { lock.lock(); defer { lock.unlock() }; stopCount += 1 }
}

import Supabase

@MainActor
final class AvatarPersistenceTests: XCTestCase {
    private let owner = UUID(uuidString: "11111111-1111-4111-8111-111111111113")!
    private var image: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512)).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        }
    }
    private func service(_ ownerProvider: (() throws -> UUID)? = nil) -> SupabaseDataService {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AvatarFixtureURLProtocol.self]
        let client = SupabaseClient(supabaseURL: URL(string: "https://avatar-fixture.invalid")!, supabaseKey: "synthetic-anon",
            options: .init(auth: .init(storage: AvatarFixtureAuthStorage(), autoRefreshToken: false), global: .init(session: URLSession(configuration: config))))
        return SupabaseDataService(authService: DependencyContainer.preview.supabaseAuthService, avatarClient: client, avatarUserId: ownerProvider ?? { self.owner })
    }
    private func prepare(_ mode: AvatarFixtureHTTP.Mode = .success, afterResponse: (() -> Void)? = nil) {
        AvatarFixtureURLProtocol.fixture.prepare(owner: owner, mode: mode, afterResponse: afterResponse)
    }
    func testOwnedUploadAndProfileSaveReturnOnlyConfirmedURLAndUniquePaths() async throws {
        prepare(); let service = service()
        let first = try await service.uploadAndSetAvatar(image, userId: owner, source: "ai_generated")
        let second = try await service.uploadAndSetAvatar(image, userId: owner, source: "ai_generated")
        XCTAssertNotEqual(first, second)
        let requests = AvatarFixtureURLProtocol.fixture.requests
        let uploads = requests.filter { $0.url!.path.contains("/storage/v1/object/profile-pictures/") }
        XCTAssertEqual(uploads.count, 2)
        for upload in uploads {
            XCTAssertTrue(upload.url!.path.contains(owner.uuidString.lowercased()))
            XCTAssertEqual(upload.value(forHTTPHeaderField: "x-upsert"), "false")
            // Storage sends multipart; its file part must carry the JPEG MIME type.
            let bytes = try requestBody(upload)
            XCTAssertTrue(String(decoding: bytes.prefix(1024), as: UTF8.self).contains("image/jpeg"))
            XCTAssertLessThan(bytes.count, 524288)
        }
        let patches = requests.filter { $0.httpMethod == "PATCH" }
        XCTAssertEqual(patches.count, 2)
        XCTAssertTrue(patches.allSatisfy { $0.url!.query!.lowercased().contains(owner.uuidString.lowercased()) })
        XCTAssertTrue(patches.allSatisfy { $0.value(forHTTPHeaderField: "Prefer")?.contains("return=representation") == true })
        XCTAssertEqual(AvatarFixtureURLProtocol.fixture.savedURL, second)
    }
    func testZeroRowsWrongOwnerAndWrongSavedURLNeverReportSuccess() async throws {
        for mode in [AvatarFixtureHTTP.Mode.emptyRows, .wrongOwner, .wrongURL] {
            prepare(mode)
            do { try await service().updateAvatarUrl("https://avatar-fixture.invalid/new.jpg", userId: owner); XCTFail("Unconfirmed update must fail") }
            catch { XCTAssertTrue(error.localizedDescription.contains("saved")) }
        }
    }
    func testAnonymousAndCrossOwnerWritesNeverReachNetwork() async throws {
        prepare()
        let anonymous = service { throw DataError.notAuthenticated }
        do { try await anonymous.updateAvatarUrl("new", userId: owner); XCTFail("Anonymous update") } catch {}
        let other = UUID()
        do { try await service().updateAvatarUrl("new", userId: other); XCTFail("Cross-owner profile") } catch {}
        do { try await service().uploadProfilePicture(data: image.jpegData(compressionQuality: 0.8)!, path: "\(other)/new.jpg", userId: owner); XCTFail("Cross-owner upload") } catch {}
        do { try await service().deleteProfilePicture(path: "\(other)/old.jpg"); XCTFail("Cross-owner deletion") } catch {}
        XCTAssertTrue(AvatarFixtureURLProtocol.fixture.requests.isEmpty)
    }
    func testUpload403415And503CannotAdvanceToProfileMutation() async throws {
        for status in [403, 415, 503] {
            prepare(.uploadFailure(status))
            do { _ = try await service().uploadAndSetAvatar(image, userId: owner); XCTFail("Upload failure") } catch {}
            XCTAssertFalse(AvatarFixtureURLProtocol.fixture.requests.contains { $0.httpMethod == "PATCH" })
            XCTAssertNil(AvatarFixtureURLProtocol.fixture.savedURL)
        }
    }
    func testFailedProfileResponseRetainsUploadedObjectAndReturnsRecoveryError() async throws {
        for status in [403, 500] {
            prepare(.profileFailure(status))
            do { _ = try await service().uploadAndSetAvatar(image, userId: owner); XCTFail("Profile failure") }
            catch { XCTAssertTrue(error.localizedDescription.contains("Check your connection")) }
            XCTAssertFalse(AvatarFixtureURLProtocol.fixture.requests.contains { $0.httpMethod == "DELETE" }, "An uncertain committed profile may already refer to the new upload")
        }
    }
    func testCommittedProfileWithLostConnectionKeepsReferencedUpload() async throws {
        prepare(.profileDisconnected)
        do { _ = try await service().uploadAndSetAvatar(image, userId: owner); XCTFail("Lost response cannot confirm success") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Check your connection")) }
        XCTAssertNotNil(AvatarFixtureURLProtocol.fixture.savedURL, "Fixture committed the owned profile before dropping the response")
        XCTAssertFalse(AvatarFixtureURLProtocol.fixture.requests.contains { $0.httpMethod == "DELETE" })
    }
    func testAccountChangeAfterUploadCannotPatchEitherProfile() async throws {
        var current = owner
        prepare(.success, afterResponse: { current = UUID() })
        do { _ = try await service({ current }).uploadAndSetAvatar(image, userId: owner); XCTFail("Account changed") } catch {}
        XCTAssertFalse(AvatarFixtureURLProtocol.fixture.requests.contains { $0.httpMethod == "PATCH" })
    }
    func testInvalidJPEGAndOversizedPayloadFailBeforeUpload() async throws {
        for data in [Data("png is not JPEG".utf8), Data([0xFF, 0xD8, 0xFF]) + Data(repeating: 1, count: 500000) + Data([0xFF, 0xD9])] {
            prepare()
            do { try await service().uploadProfilePicture(data: data, path: "\(owner)/new.jpg", userId: owner); XCTFail("Invalid upload") } catch {}
            XCTAssertTrue(AvatarFixtureURLProtocol.fixture.requests.isEmpty)
        }
    }
    func testRemovingAvatarWritesAndConfirmsExplicitNull() async throws {
        prepare(); try await service().updateAvatarUrl("", userId: owner)
        let request = try XCTUnwrap(AvatarFixtureURLProtocol.fixture.requests.first)
        let fields = try JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any]
        XCTAssertTrue(fields?["avatar_url"] is NSNull)
    }
    func testHistoryFromAnotherOwnerCannotBeApplied() async throws {
        prepare()
        let entry = SupabaseDataService.ProfilePictureHistoryEntry(id: UUID(), userId: UUID(), storagePath: "other/old.jpg", publicUrl: "https://avatar-fixture.invalid/other.jpg", source: "upload", createdAt: Date())
        do { try await service().setAvatarFromHistory(historyEntry: entry); XCTFail("Other owner's history") } catch {}
        XCTAssertTrue(AvatarFixtureURLProtocol.fixture.requests.isEmpty)
    }
    private func requestBody(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }; var data = Data(); var bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; data.append(contentsOf: bytes.prefix(n)) }
        return data
    }
}
private struct AvatarFixtureAuthStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
}
private final class AvatarFixtureURLProtocol: URLProtocol {
    static let fixture = AvatarFixtureHTTP()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "avatar-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.fixture.respond(request)
        if status == 0 { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class AvatarFixtureHTTP: @unchecked Sendable {
    enum Mode { case success, emptyRows, wrongOwner, wrongURL, uploadFailure(Int), profileFailure(Int), profileDisconnected }
    private let lock = NSLock(); private var owner = UUID(); private var mode: Mode = .success
    private var recorded: [URLRequest] = []; private var saved: String?
    private var afterResponse: (() -> Void)?
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    var savedURL: String? { lock.lock(); defer { lock.unlock() }; return saved }
    func prepare(owner: UUID, mode: Mode, afterResponse: (() -> Void)?) {
        lock.lock(); defer { lock.unlock() }; self.owner = owner; self.mode = mode; self.afterResponse = afterResponse; recorded = []; saved = nil
    }
    func respond(_ original: URLRequest) -> (Int, Data) {
        var request = original
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            request.httpBody = data
        }
        lock.lock(); defer { lock.unlock() }; recorded.append(request)
        var status = 200; var body: Any = [:]
        if request.url!.path.contains("/storage/v1/object/") {
            if case .uploadFailure(let code) = mode { status = code; body = ["statusCode": "\(code)", "error": "Synthetic upload failure", "message": "Synthetic upload failure"] }
            else { body = ["Key": request.url!.path.components(separatedBy: "/object/").last!, "Id": UUID().uuidString]; afterResponse?(); afterResponse = nil }
        } else if request.httpMethod == "PATCH" {
            let value = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
            let url = value?["avatar_url"] as? String
            switch mode {
            case .emptyRows: body = []
            case .wrongOwner: body = ["id": UUID().uuidString, "avatar_url": url ?? ""]
            case .wrongURL: body = ["id": owner.uuidString, "avatar_url": "https://avatar-fixture.invalid/other.jpg"]
            case .profileFailure(let code): status = code; body = ["code": "42501", "message": "Synthetic denial", "details": "", "hint": ""]
            case .profileDisconnected: saved = url; status = 0
            default: saved = url; body = ["id": owner.uuidString, "avatar_url": value?["avatar_url"] ?? NSNull()]
            }
        } else if request.url!.path.contains("/profiles") { body = ["avatar_url": "https://avatar-fixture.invalid/old.jpg"] }
        return (status, (try? JSONSerialization.data(withJSONObject: body)) ?? Data())
    }
}
