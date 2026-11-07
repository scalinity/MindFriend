import XCTest
@testable import MindFriendApp

final class OutcomeTrackingServiceTests: XCTestCase {
    private func template(_ type: AssessmentType = .pss10) -> AssessmentTemplate {
        let options = type == .who5 ? 6 : type == .phq9 || type == .gad7 ? 4 : 5
        return AssessmentTemplate(id: UUID(), code: type.rawValue, name: type.shortName, description: nil,
            questions: (1...type.questionCount).map {
                AssessmentQuestion(id: String($0), number: $0, text: "Fixture question",
                    responseOptions: (0..<options).map(String.init), isCrisisIndicator: type == .phq9 && $0 == 9)
            }, scoringRanges: [
                ScoringRange(minScore: 0, maxScore: 13, severityLevel: "low", label: "Low", recommendations: []),
                ScoringRange(minScore: 14, maxScore: 26, severityLevel: "moderate", label: "Moderate", recommendations: []),
                ScoringRange(minScore: 27, maxScore: 40, severityLevel: "high", label: "High", recommendations: [])
            ], recommendedFrequencyDays: type.recommendedFrequencyDays, isActive: true,
            createdAt: nil, updatedAt: nil)
    }

    private func response(template: AssessmentTemplate, answers: [String: Int], score: Int,
                          time: Date = Date(timeIntervalSince1970: 1_000), version: Int? = nil) -> AssessmentResponse {
        AssessmentResponse(id: UUID(), userId: UUID(uuidString: "a1000000-0000-4000-8000-000000000001")!, assessmentTemplateId: template.id, answers: answers,
            totalScore: score, severityLevel: "low", isBaseline: true, notes: nil,
            completedAt: time, createdAt: time, scoringVersion: version)
    }

    func testPSSReverseScoringUsesQuestionNumbersAndRawOptionIndexes() throws {
        let template = template()
        let zeroes = Dictionary(uniqueKeysWithValues: template.questions.map { ($0.id, 0) })
        let fours = Dictionary(uniqueKeysWithValues: template.questions.map { ($0.id, 4) })
        XCTAssertEqual(try AssessmentType.pss10.score(answers: zeroes, questions: template.questions), 16)
        XCTAssertEqual(try AssessmentType.pss10.score(answers: fours, questions: template.questions.reversed()), 24)
        let minimum = Dictionary(uniqueKeysWithValues: template.questions.map { ($0.id, [4,5,7,8].contains($0.number) ? 4 : 0) })
        let maximum = minimum.mapValues { 4 - $0 }
        XCTAssertEqual(try AssessmentType.pss10.score(answers: minimum, questions: template.questions), 0)
        XCTAssertEqual(try AssessmentType.pss10.score(answers: maximum, questions: template.questions), 40)
    }

    func testScoringRejectsMissingExtraAndOutOfRangeAnswers() throws {
        let template = template()
        let valid = Dictionary(uniqueKeysWithValues: template.questions.map { ($0.id, 0) })
        var missing = valid; missing.removeValue(forKey: "1")
        var extra = valid; extra["unknown"] = 0
        var outside = valid; outside["1"] = 5
        var negative = valid; negative["1"] = -1
        for invalid in [missing, extra, outside, negative] {
            XCTAssertThrowsError(try AssessmentType.pss10.score(answers: invalid, questions: template.questions))
        }
    }

    func testHistoricalPSSRecalculatesWithoutChangingSavedAnswers() throws {
        let template = template()
        let answers = Dictionary(uniqueKeysWithValues: template.questions.map { ($0.id, 0) })
        let stored = response(template: template, answers: answers, score: 0)
        let displayed = stored.recalculatedIfNeeded(using: template)
        XCTAssertEqual(displayed.availableScore, 16)
        XCTAssertEqual(displayed.severityLevel, "moderate")
        XCTAssertEqual(displayed.scoreStatus, .recalculated)
        XCTAssertEqual(displayed.answers, answers)
        XCTAssertEqual(displayed.id, stored.id)
        XCTAssertEqual(stored.totalScore, 0)
        XCTAssertNil(stored.scoringVersion)
    }

    func testMalformedHistoricalPSSIsUnavailableInsteadOfTrusted() {
        let template = template()
        let result = response(template: template, answers: ["1":0], score: 0).recalculatedIfNeeded(using: template)
        XCTAssertNil(result.availableScore)
        XCTAssertEqual(result.scoreStatus, .unavailable)
        XCTAssertEqual(result.answers, ["1":0])
    }

    func testCorrectedPSSSubmissionIsNotMarkedAsHistorical() {
        let template = template()
        let answers = Dictionary(uniqueKeysWithValues: template.questions.map { ($0.id, [4,5,7,8].contains($0.number) ? 4 : 0) })
        let result = response(template: template, answers: answers, score: 0, version: 2).recalculatedIfNeeded(using: template)
        XCTAssertEqual(result.availableScore, 0)
        XCTAssertEqual(result.scoreStatus, .recorded)
    }

    func testSubmissionEncodesExplicitIdentityAndRawAnswers() throws {
        let request = OutcomeAssessmentSubmission(expectedUserID: UUID(), responseID: UUID(), templateID: UUID(), answers: ["9":1],
            notes: "Fixture", timeZone: "America/New_York")
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any])
        XCTAssertEqual(object["p_expected_user_id"] as? String, request.expectedUserID.uuidString)
        XCTAssertEqual(object["p_response_id"] as? String, request.responseID.uuidString)
        XCTAssertEqual(object["p_template_id"] as? String, request.templateID.uuidString)
        XCTAssertEqual(object["p_answers"] as? [String:Int], ["9":1])
        XCTAssertEqual(object["p_time_zone"] as? String, "America/New_York")
    }
    func testImprovementDirectionDiffersBetweenPHQAndWHO() {
        XCTAssertEqual(AssessmentType.phq9.improvement(from: 10, to: 20), -10)
        XCTAssertEqual(AssessmentType.who5.improvement(from: 10, to: 20), 10)
        XCTAssertEqual(AssessmentType.phq9.improvement(from: 20, to: 10), 10)
        XCTAssertEqual(AssessmentType.who5.improvement(from: 20, to: 10), -10)
    }

    func testRecommendedTargetsRespectInstrumentDirectionAndBounds() {
        XCTAssertEqual(AssessmentType.phq9.suggestedTargetScore(from: 20), 15)
        XCTAssertEqual(AssessmentType.who5.suggestedTargetScore(from: 10), 15)
        XCTAssertEqual(AssessmentType.who5.suggestedTargetScore(from: 24), 25)
        XCTAssertEqual(AssessmentType.phq9.suggestedTargetScore(from: 2), 0)
    }

    private func goal(baseline: Int, target: Int, linked: Bool = true) -> OutcomeGoal {
        OutcomeGoal(id: UUID(), userId: UUID(), assessmentTemplateId: UUID(), targetScore: target,
            targetDate: nil, baselineScore: baseline, baselineDate: Date(timeIntervalSince1970: 0),
            achieved: false, achievedAt: nil, createdAt: nil, updatedAt: nil,
            baselineResponseId: linked ? UUID() : nil)
    }

    func testGoalProgressRequiresReachingTheTargetInTheInstrumentDirection() throws {
        let depression = goal(baseline: 20, target: 10)
        XCTAssertEqual(depression.remainingPoints(currentScore: 15, type: .phq9), 5)
        XCTAssertEqual(depression.progress(currentScore: 15, type: .phq9), 0.5)
        XCTAssertEqual(depression.remainingPoints(currentScore: 10, type: .phq9), 0)
        XCTAssertEqual(depression.remainingPoints(currentScore: 5, type: .phq9), 0)
        XCTAssertEqual(depression.progress(currentScore: 25, type: .phq9), 0)
        let wellbeing = goal(baseline: 10, target: 20)
        XCTAssertEqual(wellbeing.remainingPoints(currentScore: 15, type: .who5), 5)
        XCTAssertEqual(wellbeing.progress(currentScore: 15, type: .who5), 0.5)
        XCTAssertEqual(wellbeing.remainingPoints(currentScore: 20, type: .who5), 0)
        XCTAssertEqual(wellbeing.remainingPoints(currentScore: 25, type: .who5), 0)
    }

    func testGoalProgressDistinguishesMissingScoreFromZero() {
        let goal = goal(baseline: 15, target: 10)
        XCTAssertNil(goal.progress(currentScore: nil, type: .phq9))
        XCTAssertNil(goal.remainingPoints(currentScore: nil, type: .phq9))
        XCTAssertEqual(goal.progress(currentScore: 0, type: .phq9), 1)
        XCTAssertEqual(goal.remainingPoints(currentScore: 0, type: .phq9), 0)
    }

    func testHistoricalGoalsRequireReviewWhenScoringOrDirectionChanged() {
        let unlinkedStress = goal(baseline: 20, target: 15, linked: false)
        XCTAssertTrue(unlinkedStress.requiresScoreReview(for: .pss10))
        XCTAssertNil(unlinkedStress.progress(currentScore: 15, type: .pss10))
        XCTAssertNil(unlinkedStress.remainingPoints(currentScore: 15, type: .pss10))
        let decreasingWellbeing = goal(baseline: 20, target: 15)
        XCTAssertTrue(decreasingWellbeing.requiresScoreReview(for: .who5))
        XCTAssertNil(decreasingWellbeing.progress(currentScore: 15, type: .who5))
    }

    func testHistoricalResultsCompareWithTheirOwnImmediatelyPreviousResponse() {
        let template = template(.phq9)
        let oldest = response(template: template, answers: [:], score: 20, time: Date(timeIntervalSince1970: 1_000))
        let middle = response(template: template, answers: [:], score: 10, time: Date(timeIntervalSince1970: 2_000))
        let newest = response(template: template, answers: [:], score: 15, time: Date(timeIntervalSince1970: 3_000))
        let history = [middle, newest, oldest]
        XCTAssertEqual(newest.previousResponse(in: history)?.id, middle.id)
        XCTAssertEqual(middle.previousResponse(in: history)?.id, oldest.id)
        XCTAssertNil(oldest.previousResponse(in: history))
        XCTAssertEqual(AssessmentType.phq9.improvement(from: middle.previousResponse(in: history)!.totalScore,
            to: middle.totalScore), 10)
    }

    func testPreviousResponseRejectsUnrelatedAndSimultaneousResults() {
        let phq = template(.phq9)
        let shown = response(template: phq, answers: [:], score: 10)
        let simultaneous = response(template: phq, answers: [:], score: 20)
        let unrelated = response(template: template(.who5), answers: [:], score: 5,
            time: shown.completedAt.addingTimeInterval(-1))
        XCTAssertNil(shown.previousResponse(in: [shown, simultaneous, unrelated]))
    }

}

#if canImport(Supabase)
import Supabase

@MainActor
final class OutcomeSubmissionOwnerTests: XCTestCase {
    func testRetainedSubmissionRejectsDifferentOwnerBeforeSending() async throws {
        let fixture = try await makeFixture()
        let request = try fixture.service.makeAssessmentSubmission(type: .phq9,
            answers: fixture.answers, notes: "Synthetic private note")
        fixture.owner.id = fixture.otherOwner
        do {
            _ = try await fixture.service.submitAssessment(request)
            XCTFail("The retained payload must not acquire the new account")
        } catch {
            XCTAssertTrue(error is OutcomeTrackingError)
        }
        XCTAssertEqual(request.expectedUserID, fixture.firstOwner)
        XCTAssertEqual(AssessmentOwnerURLProtocol.fixture.submissions.count, 0)
        XCTAssertEqual(AssessmentOwnerURLProtocol.fixture.savedCount, 0)
    }

    func testDelayedSDKAuthenticationKeepsOriginalOwnerAndRetryIdentity() async throws {
        let fixture = try await makeFixture()
        let request = try fixture.service.makeAssessmentSubmission(type: .phq9,
            answers: fixture.answers, notes: "Synthetic private note")
        await fixture.gate.pauseNextRequest()
        let task = Task { try await fixture.service.submitAssessment(request) }
        await fixture.gate.waitForRequest()
        fixture.owner.id = fixture.otherOwner
        await fixture.gate.release(token: fixture.otherOwner.uuidString)
        do {
            _ = try await task.value
            XCTFail("The server must reject the old payload with the new bearer")
        } catch let error as PostgrestError {
            XCTAssertEqual(error.code, "42501")
        }
        var sent = AssessmentOwnerURLProtocol.fixture.submissions
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].owner, fixture.firstOwner)
        XCTAssertEqual(sent[0].bearer, fixture.otherOwner.uuidString)
        XCTAssertEqual(AssessmentOwnerURLProtocol.fixture.savedCount, 0)

        do {
            _ = try await fixture.service.submitAssessment(request)
            XCTFail("A retry under the new owner must fail before sending")
        } catch {
            XCTAssertTrue(error is OutcomeTrackingError)
        }
        XCTAssertEqual(AssessmentOwnerURLProtocol.fixture.submissions.count, 1)

        fixture.owner.id = fixture.firstOwner
        await fixture.gate.release(token: fixture.firstOwner.uuidString)
        let saved = try await fixture.service.submitAssessment(request)
        let retried = try await fixture.service.submitAssessment(request)
        XCTAssertEqual(saved.id, request.responseID)
        XCTAssertEqual(retried.id, saved.id)
        XCTAssertEqual(saved.userId, fixture.firstOwner)
        XCTAssertEqual(AssessmentOwnerURLProtocol.fixture.savedCount, 1)
        sent = AssessmentOwnerURLProtocol.fixture.submissions
        XCTAssertEqual(sent.map(\.id), [request.responseID, request.responseID, request.responseID])
        XCTAssertEqual(sent.map(\.owner), [fixture.firstOwner, fixture.firstOwner, fixture.firstOwner])
        XCTAssertEqual(sent.map(\.answers), [fixture.answers, fixture.answers, fixture.answers])
    }

    private func makeFixture() async throws -> Fixture {
        let a = UUID(), b = UUID(), owner = Owner()
        owner.id = a
        let gate = AssessmentOwnerTokenGate(token: a.uuidString)
        let template = AssessmentTemplate(id: UUID(), code: "PHQ9", name: "Synthetic PHQ", description: nil,
            questions: (1...9).map { AssessmentQuestion(id: String($0), number: $0, text: "Synthetic",
                responseOptions: ["0", "1", "2", "3"], isCrisisIndicator: $0 == 9) },
            scoringRanges: [ScoringRange(minScore: 0, maxScore: 27, severityLevel: "minimal", label: "Minimal", recommendations: [])],
            recommendedFrequencyDays: 14, isActive: true, createdAt: nil, updatedAt: nil)
        AssessmentOwnerURLProtocol.fixture.reset(template: template)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AssessmentOwnerURLProtocol.self]
        let client = SupabaseClient(supabaseURL: URL(string: "https://assessment-owner-fixture.invalid")!,
            supabaseKey: "synthetic-anon", options: .init(
                auth: .init(storage: AssessmentOwnerStorage(), autoRefreshToken: false,
                            accessToken: { await gate.nextToken() }),
                global: .init(session: URLSession(configuration: config))))
        let service = OutcomeTrackingService(supabase: client, currentUserID: { owner.id })
        try await service.loadAssessmentTemplates()
        XCTAssertEqual(service.assessmentTemplates.count, 1)
        return Fixture(service: service, owner: owner, firstOwner: a, otherOwner: b, gate: gate,
            answers: Dictionary(uniqueKeysWithValues: (1...9).map { (String($0), $0 == 9 ? 1 : 0) }))
    }

    private final class Owner { var id: UUID? }
    private struct Fixture {
        let service: OutcomeTrackingService
        let owner: Owner
        let firstOwner: UUID
        let otherOwner: UUID
        let gate: AssessmentOwnerTokenGate
        let answers: [String: Int]
    }
}

private actor AssessmentOwnerTokenGate {
    private var token: String
    private var paused = false
    private var requested = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var request: CheckedContinuation<String?, Never>?
    init(token: String) { self.token = token }
    func pauseNextRequest() { paused = true; requested = false }
    func waitForRequest() async {
        if requested { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func nextToken() async -> String? {
        guard paused else { return token }
        requested = true
        waiter?.resume(); waiter = nil
        return await withCheckedContinuation { request = $0 }
    }
    func release(token: String) {
        self.token = token; paused = false
        request?.resume(returning: token); request = nil
    }
}

private struct AssessmentOwnerStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
}

private final class AssessmentOwnerHTTP: @unchecked Sendable {
    struct Submission {
        let owner: UUID
        let id: UUID
        let bearer: String
        let answers: [String: Int]
    }
    private let lock = NSLock()
    private var template: AssessmentTemplate?
    private var attempts: [Submission] = []
    private var saved: [UUID: AssessmentResponse] = [:]
    var submissions: [Submission] { lock.withLock { attempts } }
    var savedCount: Int { lock.withLock { saved.count } }
    func reset(template: AssessmentTemplate) {
        lock.withLock { self.template = template; attempts = []; saved = [:] }
    }
    func response(for request: URLRequest) throws -> (Int, Data) {
        try lock.withLock {
            guard let template else { throw URLError(.badServerResponse) }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            if request.url?.path == "/rest/v1/assessment_templates" {
                return (200, try encoder.encode([template]))
            }
            guard request.url?.path == "/rest/v1/rpc/submit_outcome_assessment" else {
                throw URLError(.unsupportedURL)
            }
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    guard read >= 0 else { throw URLError(.cannotDecodeRawData) }
                    if read == 0 { break }; body.append(contentsOf: buffer.prefix(read))
                }
            }
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let owner = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(object["p_expected_user_id"] as? String)))
            let id = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(object["p_response_id"] as? String)))
            let answers = try XCTUnwrap(object["p_answers"] as? [String: Int])
            let bearer = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
            attempts.append(Submission(owner: owner, id: id, bearer: bearer, answers: answers))
            guard bearer == owner.uuidString else {
                return (403, Data(#"{"code":"42501","message":"Assessment owner changed","details":null,"hint":null}"#.utf8))
            }
            let response = saved[id] ?? AssessmentResponse(id: id, userId: owner,
                assessmentTemplateId: template.id, answers: answers, totalScore: 1,
                severityLevel: "minimal", isBaseline: true, notes: object["p_notes"] as? String,
                completedAt: Date(timeIntervalSince1970: 1000), createdAt: nil, scoringVersion: 2)
            saved[id] = response
            let json = try JSONSerialization.jsonObject(with: encoder.encode(response))
            return (200, try JSONSerialization.data(withJSONObject: ["response": json, "schedule": NSNull(), "goal": NSNull()]))
        }
    }
}

private final class AssessmentOwnerURLProtocol: URLProtocol, @unchecked Sendable {
    static let fixture = AssessmentOwnerHTTP()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.fixture.response(for: request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
#endif
