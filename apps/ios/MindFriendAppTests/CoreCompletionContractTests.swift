import XCTest
#if !CORE_COMPLETION_STANDALONE
@testable import MindFriendApp
#endif

final class CoreCompletionContractTests: XCTestCase {
    private func response(_ settings: String = #"{"allow_ai_reference":true,"pinned_to_quick_actions":false}"#) -> Data {
        Data("""
        {"success":true,"data":{"id":"synthetic-plan","version":3,
        "created_at":"2026-10-22T12:00:00Z","updated_at":"2026-10-22T12:01:00Z",
        "payload":{"warningSigns":[{"id":"warning","text":"Synthetic warning"}],
        "coping":[{"id":"coping","type":"exercise","label":"Synthetic exercise","category":"breathing","exercise_id":"exercise","is_favorite":true}],
        "contacts":[{"id":"contact","name":"Synthetic contact","phone":"+12025550123","relationship":"friend","preferred_method":"text","what_to_say":"Synthetic message","notes":"Synthetic notes","is_primary":true}],
        "resources":[{"id":"resource","type":"custom","name":"Synthetic resource","url":"https://example.invalid/resource","notes":"Synthetic description"}],
        "environmentSteps":[],"anchors":[{"id":"anchor","text":"Synthetic anchor"}]},
        "settings":\(settings)},"error":null}
        """.utf8)
    }

    func testHandlerResponsePreservesAllContent() throws {
        let result = try JSONDecoder().decode(SafetyPlanResponse.self, from: response())
        let data = try XCTUnwrap(result.data)
        XCTAssertTrue(result.success)
        XCTAssertEqual(data.version, 3)
        XCTAssertTrue(data.settings.allowAiReference)
        XCTAssertFalse(data.settings.pinnedToQuickActions)
        XCTAssertEqual(data.payload.warningSigns.first?.text, "Synthetic warning")
        XCTAssertEqual(data.payload.warningSigns.first?.order, 0)
        XCTAssertEqual(data.payload.contacts.first?.whatToSay, "Synthetic message")
        XCTAssertEqual(data.payload.contacts.first?.notes, "Synthetic notes")
        XCTAssertEqual(data.payload.contacts.first?.preferredMethod, .text)
        XCTAssertEqual(data.payload.contacts.first?.isPrimary, true)
        XCTAssertEqual(data.payload.coping.first?.exerciseId, "exercise")
        XCTAssertEqual(data.payload.coping.first?.isFavorite, true)
        XCTAssertEqual(data.payload.resources.first?.website, "https://example.invalid/resource")
        XCTAssertEqual(data.payload.resources.first?.description, "Synthetic description")
        XCTAssertEqual(data.payload.anchors.first?.text, "Synthetic anchor")
        let roundTrip = try JSONDecoder().decode(SafetyPlanPayload.self, from: JSONEncoder().encode(data.payload))
        XCTAssertEqual(roundTrip, data.payload)
    }

    func testLegacyCacheAndSnakeCaseSettings() throws {
        let legacy = Data(#"{"allowAiReference":true,"pinnedToQuickActions":true}"#.utf8)
        let settings = try JSONDecoder().decode(SafetyPlanSettings.self, from: legacy)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        XCTAssertEqual(encoded["allow_ai_reference"] as? Bool, true)
        XCTAssertEqual(encoded["pinned_to_quick_actions"] as? Bool, true)
        XCTAssertNil(encoded["allowAiReference"])
        let original = SafetyPlanCachePayload(payload: .empty, settings: settings)
        let cached = try JSONDecoder().decode(SafetyPlanCachePayload.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(cached.payload, original.payload)
        XCTAssertEqual(cached.settings, settings)
    }

    func testStructuredAndLegacyErrorsAndNoPlan() throws {
        for error in [#"{"code":"CONFLICT","message":"A plan already exists"}"#, #""A plan already exists""#] {
            let result = try JSONDecoder().decode(SafetyPlanResponse.self, from: Data("{\"success\":false,\"error\":\(error)}".utf8))
            XCTAssertFalse(result.success)
            XCTAssertEqual(result.error, "A plan already exists")
            XCTAssertNil(result.data)
        }
        let empty = try JSONDecoder().decode(SafetyPlanResponse.self, from: Data(#"{"success":true,"data":null,"error":null}"#.utf8))
        XCTAssertTrue(empty.success)
        XCTAssertNil(empty.data)
    }

    func testSafetyRequestsExcludeMetadataAndLocalSettings() throws {
        let payload = try XCTUnwrap(JSONDecoder().decode(SafetyPlanResponse.self, from: response()).data?.payload)
        let request = SafetyPlanRequest(operation: "update", payload: .init(payload), settings: nil)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        let content = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(Set(content.keys), Set(["warningSigns", "coping", "contacts", "resources", "environmentSteps", "anchors"]))
        XCTAssertNil(json["settings"], "Content saves must omit the separately managed preference")
        for preference in [false, true] {
            let settingsOnly = SafetyPlanRequest(operation: "update", payload: nil, settings: .init(allow_ai_reference: preference))
            let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settingsOnly)) as? [String: Any])
            XCTAssertNil(encoded["payload"])
            let settings = try XCTUnwrap(encoded["settings"] as? [String: Any])
            XCTAssertEqual(settings.count, 1)
            XCTAssertEqual(settings["allow_ai_reference"] as? Bool, preference)
        }
        for operation in ["get", "delete"] {
            let encoded = try JSONEncoder().encode(SafetyPlanRequest(operation: operation, payload: nil, settings: nil))
            let request = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            XCTAssertEqual(request["operation"] as? String, operation)
            XCTAssertNil(request["payload"])
            XCTAssertNil(request["settings"])
        }
    }

    func testMalformedContentFailsWithoutReplacingItWithEmptyPlan() {
        let malformed = Data(#"{"success":true,"data":{"version":1,"settings":{},"payload":{"warningSigns":[],"coping":[],"contacts":[],"resources":[],"anchors":[]}}}"#.utf8)
        do {
            _ = try JSONDecoder().decode(SafetyPlanResponse.self, from: malformed)
            XCTFail("Malformed safety-plan content must fail decoding")
        } catch {
            // A decoding failure preserves the existing plan instead of replacing it.
        }
    }

    func testPersistedCertificateAndRPCResultDecode() throws {
        let fixture = Data(#"{"id":"33333333-3333-4333-8333-333333333333","user_id":"11111111-1111-4111-8111-111111111111","program_id":"44444444-4444-4444-8444-444444444444","enrollment_id":"55555555-5555-4555-8555-555555555555","certificate_number":"MF-2026-000001","completion_stats":{"days_completed":2,"streak_best":2,"skips_used":0,"program_title":"Synthetic program"},"issued_at":"2026-10-22T12:00:00Z","shared_to_circle":false,"shared_externally":false}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let certificate = try decoder.decode(DBProgramCertificate.self, from: fixture).toCertificate()
        XCTAssertEqual(certificate.certificateNumber, "MF-2026-000001")
        XCTAssertEqual(certificate.completionStats.daysCompleted, 2)
        let result = try decoder.decode(CompleteProgramDayResult.self, from: Data(#"{"day_completed":2,"program_complete":true,"next_day":null,"streak":2,"certificate_number":"MF-2026-000001"}"#.utf8))
        XCTAssertTrue(result.programComplete)
        XCTAssertNil(result.nextDay)
        XCTAssertEqual(result.certificateNumber, certificate.certificateNumber)
    }

    @MainActor
    private func recoveryExercise() -> Exercise {
        Exercise(id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", type: .breathing,
                 title: "Synthetic exercise", description: "Synthetic fixture", durationSeconds: 60,
                 contentKind: .text, contentText: nil, audioUrl: nil, instructions: nil,
                 evidenceBasis: nil, therapistReviewed: nil, reviewDate: nil, methodologyNote: nil)
    }

    @MainActor
    func testLostCompletionResponseRetriesTheSameSessionAndRating() async throws {
        let service = CompletionRetryService()
        service.loseCompletionResponse = true
        let player = LibraryExercisePlayerViewModel(exercise: recoveryExercise(), dataService: service)
        await player.startSession()
        player.rating = 4
        let originalId = try XCTUnwrap(player.session?.id)
        do {
            _ = try await player.submitCompletion()
            XCTFail("Lost completion response must remain a visible failure")
        } catch {}
        XCTAssertNotNil(player.completionError)
        XCTAssertFalse(player.isSubmittingCompletion)
        XCTAssertEqual(player.session?.id, originalId)
        XCTAssertEqual(player.rating, 4)
        XCTAssertEqual(service.completedIds.count, 1)
        XCTAssertEqual(service.totalXP, 0)
        await player.startSession()
        XCTAssertEqual(service.createdIds.count, 1, "View/task reappearance must retain recovery state")
        let confirmed = try await player.submitCompletion()
        XCTAssertEqual(confirmed, originalId)
        XCTAssertNil(player.completionError)
        XCTAssertEqual(service.completionAttempts, [originalId, originalId])
        XCTAssertEqual(service.ratings, [4, 4])
        XCTAssertEqual(service.completedIds.count, 1)
        XCTAssertEqual(service.totalXP, 30)
        _ = try await player.submitCompletion()
        XCTAssertEqual(service.rewardAttempts.count, 1, "Confirmed UI resubmission must not replay side effects")
    }

    @MainActor
    func testLostXPResponseRequiresConfirmationAndRetriesTheSameUUID() async throws {
        let service = CompletionRetryService()
        service.loseXPResponse = true
        let player = LibraryExercisePlayerViewModel(exercise: recoveryExercise(), dataService: service)
        await player.startSession()
        let originalId = try XCTUnwrap(player.session?.id)
        var confirmed: String?
        do {
            confirmed = try await player.submitCompletion()
            XCTFail("Lost XP response must not confirm program practice")
        } catch {}
        XCTAssertNil(confirmed)
        XCTAssertNotNil(player.completionError)
        XCTAssertEqual(service.completedIds.count, 1)
        XCTAssertEqual(service.totalXP, 30, "The mock server committed before the response was lost")
        await player.startSession()
        confirmed = try await player.submitCompletion()
        XCTAssertEqual(confirmed, originalId)
        XCTAssertEqual(service.createdIds.count, 1)
        XCTAssertEqual(service.completionAttempts, [originalId, originalId])
        XCTAssertEqual(service.rewardAttempts, [originalId, originalId])
        XCTAssertEqual(service.completedIds.count, 1)
        XCTAssertEqual(service.totalXP, 30)
    }

    @MainActor
    func testConcurrentStartIsGuardedButAnIntentionalNewPlayerStartsANewSession() async throws {
        let service = CompletionRetryService()
        let player = LibraryExercisePlayerViewModel(exercise: recoveryExercise(), dataService: service)
        async let first: Void = player.startSession()
        async let second: Void = player.startSession()
        _ = await (first, second)
        XCTAssertEqual(service.createdIds.count, 1)
        _ = try await player.submitCompletion()
        let nextPlayer = LibraryExercisePlayerViewModel(exercise: recoveryExercise(), dataService: service)
        await nextPlayer.startSession()
        XCTAssertEqual(service.createdIds.count, 2)
        XCTAssertNotEqual(player.session?.id, nextPlayer.session?.id)
    }

}


@MainActor
private final class CompletionRetryService: LibraryExerciseSessionService {
    var loseCompletionResponse = false
    var loseXPResponse = false
    var createdIds: [String] = []
    var completionAttempts: [String] = []
    var rewardAttempts: [String] = []
    var ratings: [Int?] = []
    var completedIds: Set<String> = []
    var rewardedIds: Set<String> = []
    var totalXP: Int { rewardedIds.count * 30 }

    func startExerciseSession(exerciseId: String) async throws -> String {
        let id = UUID().uuidString
        createdIds.append(id)
        await Task.yield()
        return id
    }

    func completeExerciseSession(sessionId: String, rating: Int?, note: String?) async throws {
        completionAttempts.append(sessionId)
        ratings.append(rating)
        completedIds.insert(sessionId)
        if loseCompletionResponse {
            loseCompletionResponse = false
            throw URLError(.networkConnectionLost)
        }
    }

    func awardXP(activity: XPActivity, exerciseSessionId: String?) async throws -> XPAward {
        let id = try XCTUnwrap(exerciseSessionId)
        XCTAssertTrue(completedIds.contains(id))
        rewardAttempts.append(id)
        let inserted = rewardedIds.insert(id).inserted
        if loseXPResponse {
            loseXPResponse = false
            throw URLError(.networkConnectionLost)
        }
        return XPAward(amount: inserted ? 30 : 0, newTotal: totalXP, newLevel: 1,
                       newTitle: "Synthetic beginner", leveledUp: false)
    }
}
