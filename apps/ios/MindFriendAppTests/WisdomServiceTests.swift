import XCTest
@testable import MindFriendApp

/// Tests for Community Wisdom Engine
final class WisdomServiceTests: XCTestCase {

    // MARK: - WisdomModels Tests

    func testWisdomConsentCodingKeys() throws {
        // Test that CodingKeys map correctly to snake_case
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "user_id": "660e8400-e29b-41d4-a716-446655440001",
            "contribute_anonymous_data": true,
            "receive_recommendations": false,
            "created_at": "2026-01-25T06:00:00Z",
            "updated_at": "2026-01-25T06:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let consent = try decoder.decode(WisdomConsent.self, from: json)

        XCTAssertEqual(consent.id.uuidString.lowercased(), "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(consent.userId.uuidString.lowercased(), "660e8400-e29b-41d4-a716-446655440001")
        XCTAssertTrue(consent.contributeAnonymousData)
        XCTAssertFalse(consent.receiveRecommendations)
    }

    func testStrategyVoteCodingKeys() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "strategy_id": "660e8400-e29b-41d4-a716-446655440001",
            "user_id": "770e8400-e29b-41d4-a716-446655440002",
            "vote_type": "helpful",
            "created_at": "2026-01-25T06:00:00Z",
            "updated_at": "2026-01-25T06:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let vote = try decoder.decode(StrategyVote.self, from: json)

        XCTAssertEqual(vote.strategyId.uuidString.lowercased(), "660e8400-e29b-41d4-a716-446655440001")
        XCTAssertEqual(vote.voteType, .helpful)
    }

    func testCommunityStrategyCodingKeys() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "category": "anxiety",
            "subcategory": null,
            "strategy_text": "Take 5 deep breaths when feeling anxious",
            "context": "When in a meeting",
            "contributor_demographic": null,
            "transition_context": null,
            "helpful_count": 42,
            "not_helpful_count": 5,
            "view_count": 150,
            "status": "approved",
            "created_at": "2026-01-25T06:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let strategy = try decoder.decode(CommunityStrategy.self, from: json)

        XCTAssertEqual(strategy.category, .anxiety)
        XCTAssertEqual(strategy.strategyText, "Take 5 deep breaths when feeling anxious")
        XCTAssertEqual(strategy.helpfulCount, 42)
        XCTAssertEqual(strategy.notHelpfulCount, 5)
        XCTAssertEqual(strategy.status, .approved)
    }

    func testHelpfulPercentageCalculation() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "category": "stress",
            "subcategory": null,
            "strategy_text": "Test strategy",
            "context": null,
            "contributor_demographic": null,
            "transition_context": null,
            "helpful_count": 80,
            "not_helpful_count": 20,
            "view_count": 100,
            "status": "approved",
            "created_at": "2026-01-25T06:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let strategy = try decoder.decode(CommunityStrategy.self, from: json)

        XCTAssertEqual(strategy.helpfulPercentage, 80)
    }

    func testHelpfulPercentageZeroDivision() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "category": "general",
            "subcategory": null,
            "strategy_text": "Test strategy",
            "context": null,
            "contributor_demographic": null,
            "transition_context": null,
            "helpful_count": 0,
            "not_helpful_count": 0,
            "view_count": 0,
            "status": "pending",
            "created_at": "2026-01-25T06:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let strategy = try decoder.decode(CommunityStrategy.self, from: json)

        // Should not divide by zero
        XCTAssertEqual(strategy.helpfulPercentage, 0)
    }

    func testInsightResponseDecoding() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "insightType": "not_alone",
            "content": "42 people felt similarly this morning",
            "contextTags": ["mood:low", "time:morning"],
            "confidenceScore": 0.85,
            "sampleSize": 42,
            "relevanceScore": 0.72
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let insight = try decoder.decode(InsightResponse.self, from: json)

        XCTAssertEqual(insight.insightType, "not_alone")
        XCTAssertEqual(insight.sampleSize, 42)
        XCTAssertEqual(insight.confidenceScore, 0.85)
        XCTAssertEqual(insight.relevanceScore, 0.72)
    }

    // MARK: - Strategy Category Tests

    func testStrategyCategoryDisplayName() {
        XCTAssertEqual(StrategyCategory.anxiety.displayName, "Anxiety")
        XCTAssertEqual(StrategyCategory.depression.displayName, "Depression")
        XCTAssertEqual(StrategyCategory.stress.displayName, "Stress")
        XCTAssertEqual(StrategyCategory.general.displayName, "General")
    }

    func testStrategyCategoryIconName() {
        XCTAssertEqual(StrategyCategory.anxiety.iconName, "waveform.path.ecg")
        XCTAssertEqual(StrategyCategory.depression.iconName, "cloud.rain")
        XCTAssertEqual(StrategyCategory.sleep.iconName, "moon.zzz")
    }

    func testAllStrategyCategories() {
        // Verify all 10 categories are present
        XCTAssertEqual(StrategyCategory.allCases.count, 10)
    }

    // MARK: - Vote Type Tests

    func testVoteTypeRawValues() {
        XCTAssertEqual(VoteType.helpful.rawValue, "helpful")
        XCTAssertEqual(VoteType.notHelpful.rawValue, "not_helpful")
    }

    // MARK: - Contribution Type Tests

    func testContributionTypeRawValues() {
        XCTAssertEqual(ContributionType.moodPattern.rawValue, "mood_pattern")
        XCTAssertEqual(ContributionType.exerciseEffectiveness.rawValue, "exercise_effectiveness")
        XCTAssertEqual(ContributionType.pathwayProgress.rawValue, "pathway_progress")
        XCTAssertEqual(ContributionType.strategySuccess.rawValue, "strategy_success")
    }

    // MARK: - Insight Type Tests

    func testInsightTypeRawValues() {
        // InsightType has: pattern, milestone, suggestion, trend
        XCTAssertEqual(InsightType.pattern.rawValue, "pattern")
        XCTAssertEqual(InsightType.milestone.rawValue, "milestone")
        XCTAssertEqual(InsightType.suggestion.rawValue, "suggestion")
        XCTAssertEqual(InsightType.trend.rawValue, "trend")
    }

    // MARK: - WisdomInsight Formatted Display Tests

    func testFormattedSampleSize() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "insight_type": "not_alone",
            "context_tags": ["mood:low"],
            "insight_content": "Test insight",
            "confidence_score": 0.9,
            "sample_size": 2340,
            "aggregate_data": null,
            "created_at": "2026-01-25T06:00:00Z",
            "valid_from": "2026-01-25T06:00:00Z",
            "valid_until": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let insight = try decoder.decode(WisdomInsight.self, from: json)

        XCTAssertEqual(insight.formattedSampleSize, "2,300+")
    }

    func testConfidenceLevel() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "insight_type": "not_alone",
            "context_tags": ["mood:low"],
            "insight_content": "Test insight",
            "confidence_score": 0.92,
            "sample_size": 100,
            "aggregate_data": null,
            "created_at": "2026-01-25T06:00:00Z",
            "valid_from": "2026-01-25T06:00:00Z",
            "valid_until": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let insight = try decoder.decode(WisdomInsight.self, from: json)

        XCTAssertEqual(insight.confidenceLevel, "Very High")
    }

    // MARK: - WisdomError Tests

    func testWisdomErrorDescriptions() {
        XCTAssertEqual(
            WisdomError.consentRequired.errorDescription,
            "Please enable wisdom features in Settings > Community Wisdom Privacy"
        )

        XCTAssertEqual(
            WisdomError.submissionFailed("Test error").errorDescription,
            "Failed to submit strategy: Test error"
        )

        XCTAssertEqual(
            WisdomError.voteFailed("Vote error").errorDescription,
            "Failed to record vote: Vote error"
        )

        XCTAssertEqual(
            WisdomError.fetchFailed("Fetch error").errorDescription,
            "Failed to fetch data: Fetch error"
        )
    }

    // MARK: - API Response Tests

    func testWisdomRecommendationsResponseDecoding() throws {
        let json = """
        {
            "notAloneInsight": {
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "insightType": "not_alone",
                "content": "42 people felt similarly",
                "contextTags": ["mood:low"],
                "confidenceScore": 0.85,
                "sampleSize": 42,
                "relevanceScore": 0.72
            },
            "insights": [],
            "strategies": [],
            "trendInsight": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(WisdomRecommendationsResponse.self, from: json)

        XCTAssertNotNil(response.notAloneInsight)
        XCTAssertEqual(response.notAloneInsight?.sampleSize, 42)
        XCTAssertTrue(response.insights.isEmpty)
        XCTAssertTrue(response.strategies.isEmpty)
        XCTAssertNil(response.trendInsight)
    }

    func testSubmitStrategyResponseDecoding() throws {
        let json = """
        {
            "success": true,
            "strategyId": "550e8400-e29b-41d4-a716-446655440000",
            "status": "pending",
            "message": "Thanks for sharing!"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(SubmitStrategyResponse.self, from: json)

        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.strategyId)
        XCTAssertEqual(response.status, "pending")
    }

    func testVoteStrategyResponseDecoding() throws {
        let json = """
        {
            "success": true,
            "strategyId": "550e8400-e29b-41d4-a716-446655440000",
            "voteType": "helpful",
            "strategy": {
                "helpfulCount": 43,
                "notHelpfulCount": 5,
                "helpfulPercentage": 90
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(VoteStrategyResponse.self, from: json)

        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.strategy)
        XCTAssertEqual(response.strategy?.helpfulCount, 43)
        XCTAssertEqual(response.strategy?.helpfulPercentage, 90)
    }

    // MARK: - AnyCodableValue Tests

    func testAnyCodableValueDecoding() throws {
        let json = """
        {
            "string": "hello",
            "int": 42,
            "double": 3.14,
            "bool": true,
            "array": [1, 2, 3],
            "nested": {"key": "value"},
            "null": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let dict = try decoder.decode([String: AnyCodableValue].self, from: json)

        if case .string(let value) = dict["string"] {
            XCTAssertEqual(value, "hello")
        } else {
            XCTFail("Expected string value")
        }

        if case .int(let value) = dict["int"] {
            XCTAssertEqual(value, 42)
        } else {
            XCTFail("Expected int value")
        }

        if case .bool(let value) = dict["bool"] {
            XCTAssertTrue(value)
        } else {
            XCTFail("Expected bool value")
        }

        if case .null = dict["null"] {
            // Expected
        } else {
            XCTFail("Expected null value")
        }
    }
}
