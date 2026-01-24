import XCTest
@testable import MindFriendApp

final class BoundaryPlannerTests: XCTestCase {
    
    // MARK: - Assessment Model Tests
    
    func testAssessmentResponsesEncoding() {
        let responses = AssessmentResponses(
            step1DrainTriggers: ["work stress"],
            step2ImportanceRatings: ["work-life balance": .high],
            step3CurrentlyMet: ["work-life balance": .sometimes],
            step4PriorityNeeds: ["work-life balance"]
        )
        
        let encoded = try! JSONEncoder().encode(responses)
        let decoded = try! JSONDecoder().decode(AssessmentResponses.self, from: encoded)
        
        XCTAssertEqual(decoded.step1DrainTriggers, responses.step1DrainTriggers)
        XCTAssertEqual(decoded.step2ImportanceRatings, responses.step2ImportanceRatings)
    }
    
    // MARK: - Boundary Type Tests
    
    func testBoundaryTypeRawValues() {
        XCTAssertEqual(BoundaryType.time.rawValue, "time")
        XCTAssertEqual(BoundaryType.emotional.rawValue, "emotional")
        XCTAssertEqual(BoundaryType.digital.rawValue, "digital")
        XCTAssertEqual(BoundaryType.physical.rawValue, "physical")
        XCTAssertEqual(BoundaryType.financial.rawValue, "financial")
    }
    
    // MARK: - Boundary Status Tests
    
    func testBoundaryStatusTransitions() {
        var boundary = DefinedBoundary(
            id: UUID(),
            userId: UUID(),
            needsAssessmentId: nil,
            boundaryType: .time,
            statementText: "I need work-life balance",
            whyMatters: "Mental health",
            stakeholder: "Manager",
            expectedImpact: "More energy",
            status: .draft,
            scripts: [],
            practiceCount: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Valid status transitions
        XCTAssertEqual(boundary.status, .draft)
        boundary.status = .ready
        XCTAssertEqual(boundary.status, .ready)
        boundary.status = .practiced
        XCTAssertEqual(boundary.status, .practiced)
    }
    
    // MARK: - Script Variation Tests
    
    func testScriptVariationCount() {
        let variations: [ScriptVariation] = [.direct, .gentle, .assertive, .collaborative]
        XCTAssertEqual(variations.count, 4)
    }
    
    func testScriptVariationCases() {
        XCTAssertEqual(ScriptVariation.direct.rawValue, "direct")
        XCTAssertEqual(ScriptVariation.gentle.rawValue, "gentle")
        XCTAssertEqual(ScriptVariation.assertive.rawValue, "assertive")
        XCTAssertEqual(ScriptVariation.collaborative.rawValue, "collaborative")
    }
    
    // MARK: - Follow-Up Outcome Tests
    
    func testFollowUpOutcomeRawValues() {
        XCTAssertEqual(FollowUpOutcome.successful.rawValue, "successful")
        XCTAssertEqual(FollowUpOutcome.partiallySuccessful.rawValue, "partially_successful")
        XCTAssertEqual(FollowUpOutcome.challenged.rawValue, "challenged")
        XCTAssertEqual(FollowUpOutcome.ignored.rawValue, "ignored")
    }
    
    // MARK: - Assessment Type Tests
    
    func testAssessmentTypeAllCases() {
        let types: [BoundaryAssessmentType] = [.work, .relationships, .family, .friends]
        XCTAssertEqual(types.count, 4)
    }
    
    // MARK: - Importance Level Tests
    
    func testImportanceLevelRawValues() {
        XCTAssertEqual(ImportanceLevel.low.rawValue, "low")
        XCTAssertEqual(ImportanceLevel.medium.rawValue, "medium")
        XCTAssertEqual(ImportanceLevel.high.rawValue, "high")
    }
    
    // MARK: - Met Level Tests
    
    func testMetLevelRawValues() {
        XCTAssertEqual(MetLevel.no.rawValue, "no")
        XCTAssertEqual(MetLevel.sometimes.rawValue, "sometimes")
        XCTAssertEqual(MetLevel.yes.rawValue, "yes")
    }
    
    // MARK: - Boundary Script Template Tests
    
    func testScriptTemplateStructure() {
        let template = BoundaryScriptTemplate(
            id: UUID(),
            boundaryType: .time,
            relationshipType: "manager",
            templateVariation: .direct,
            templateText: "I need...",
            toneDescription: "Clear and firm",
            exampleContext: "Work hours",
            locale: "en",
            isPremium: false,
            createdAt: Date()
        )

        XCTAssertEqual(template.boundaryType, .time)
        XCTAssertEqual(template.relationshipType, "manager")
        XCTAssertEqual(template.templateVariation, .direct)
    }
    
    // MARK: - Error Handling Tests
    
    func testBoundaryPlannerErrorCases() {
        let errors: [BoundaryPlannerService.BoundaryPlannerError] = [
            .unauthorized,
            .tierLimitReached(currentCount: 3),
            .boundaryNotFound,
            .invalidTransition(current: "draft", requested: "set", allowed: ["ready"]),
            .networkError(NSError(domain: "test", code: -1)),
            .unknown("test error")
        ]

        XCTAssertEqual(errors.count, 6)
    }
    
    // MARK: - Response Models Tests
    
    func testCreateAssessmentResponseDecoding() {
        let json = """
        {
            "success": true,
            "assessmentId": "550e8400-e29b-41d4-a716-446655440000",
            "topNeeds": ["work-life balance"],
            "recommendedBoundaries": []
        }
        """.data(using: .utf8)!
        
        let response = try! JSONDecoder().decode(CreateAssessmentResponse.self, from: json)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.topNeeds.count, 1)
    }
    
    // MARK: - Needs Assessment Tests
    
    func testNeedsAssessmentInitialization() {
        let responses = AssessmentResponses(
            step1DrainTriggers: ["work stress"],
            step2ImportanceRatings: ["work-life balance": .high],
            step3CurrentlyMet: ["work-life balance": .sometimes],
            step4PriorityNeeds: ["work-life balance"]
        )

        let assessment = NeedsAssessment(
            id: UUID(),
            userId: UUID(),
            assessmentType: .work,
            responses: responses,
            topNeeds: ["work-life balance"],
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(assessment.assessmentType, .work)
        XCTAssertEqual(assessment.topNeeds.count, 1)
    }
}
