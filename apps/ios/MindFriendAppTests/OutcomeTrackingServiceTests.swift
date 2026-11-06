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
        AssessmentResponse(id: UUID(), userId: UUID(), assessmentTemplateId: template.id, answers: answers,
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
        let request = OutcomeAssessmentSubmission(responseID: UUID(), templateID: UUID(), answers: ["9":1],
            notes: "Fixture", timeZone: "America/New_York")
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any])
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

}
