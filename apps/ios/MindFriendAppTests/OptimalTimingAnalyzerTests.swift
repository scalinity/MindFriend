//  OptimalTimingAnalyzerTests.swift
//  MindFriendAppTests
//
//  Tests for OptimalTimingAnalyzer: ML pattern analysis, caching, data requirements

import XCTest
@testable import MindFriendApp

@MainActor
final class OptimalTimingAnalyzerTests: XCTestCase {
    var analyzer: OptimalTimingAnalyzer!
    var mockSupabase: MockSupabaseClient!

    override func setUp() async throws {
        mockSupabase = MockSupabaseClient()
        analyzer = OptimalTimingAnalyzer(supabase: mockSupabase)
    }

    override func tearDown() async throws {
        analyzer.stopPeriodicRefresh()
        analyzer = nil
        mockSupabase = nil
    }

    // MARK: - Data Requirement Tests

    func testHasMinimumDataReturnsFalseWithInsufficientData() async throws {
        // Mock Edge Function to return insufficient_data error
        mockSupabase.mockFunctionResponse = """
        {
            "error": "insufficient_data",
            "message": "Need at least 14 days of data",
            "sampleCount": 5,
            "daysSinceFirst": 3
        }
        """
        mockSupabase.shouldFailFunctionCall = true

        let hasData = try await analyzer.hasMinimumData()

        XCTAssertFalse(hasData)
    }

    func testHasMinimumDataReturnsTrueWithSufficientData() async throws {
        // Mock successful response
        mockSupabase.mockFunctionResponse = """
        {
            "hourlyConfidence": {
                "9": {"completionRate": 0.8, "avgRating": 4.2, "dismissRate": 0.1, "confidence": 0.35, "sampleCount": 12}
            },
            "sampleCount": 150,
            "minimumDataMet": true,
            "windowDays": 90
        }
        """

        let hasData = try await analyzer.hasMinimumData()

        XCTAssertTrue(hasData)
    }

    // MARK: - Pattern Analysis Tests

    func testAnalyzePatternsCaching() async throws {
        mockSupabase.mockFunctionResponse = """
        {
            "hourlyConfidence": {
                "9": {"completionRate": 0.8, "avgRating": 4.2, "dismissRate": 0.1, "confidence": 0.35, "sampleCount": 12},
                "14": {"completionRate": 0.6, "avgRating": 3.5, "dismissRate": 0.3, "confidence": 0.05, "sampleCount": 10}
            },
            "sampleCount": 150,
            "minimumDataMet": true,
            "windowDays": 90
        }
        """

        // First call - should fetch from network
        let preferences1 = try await analyzer.analyzePatterns()
        XCTAssertEqual(mockSupabase.functionCallCount, 1)

        // Second call - should use cache
        let preferences2 = try await analyzer.analyzePatterns()
        XCTAssertEqual(mockSupabase.functionCallCount, 1) // Still 1, not 2

        XCTAssertEqual(preferences1.sampleCount, preferences2.sampleCount)
    }

    func testRefreshPatternsInvalidatesCache() async throws {
        mockSupabase.mockFunctionResponse = """
        {
            "hourlyConfidence": {},
            "sampleCount": 100,
            "minimumDataMet": true,
            "windowDays": 90
        }
        """

        // First call
        _ = try await analyzer.analyzePatterns()
        XCTAssertEqual(mockSupabase.functionCallCount, 1)

        // Refresh should invalidate cache
        try await analyzer.refreshPatterns()
        XCTAssertEqual(mockSupabase.functionCallCount, 2)
    }

    // MARK: - Confidence Boost Tests

    func testGetConfidenceBoostWithNoData() {
        let boost = analyzer.getConfidenceBoost(for: 9)

        XCTAssertEqual(boost, 0.0) // Neutral when no data
    }

    func testGetConfidenceBoostWithCachedData() async throws {
        mockSupabase.mockFunctionResponse = """
        {
            "hourlyConfidence": {
                "9": {"completionRate": 0.9, "avgRating": 4.5, "dismissRate": 0.05, "confidence": 0.4, "sampleCount": 15},
                "14": {"completionRate": 0.4, "avgRating": 2.8, "dismissRate": 0.5, "confidence": -0.3, "sampleCount": 12}
            },
            "sampleCount": 150,
            "minimumDataMet": true,
            "windowDays": 90
        }
        """

        _ = try await analyzer.analyzePatterns()

        let boost9AM = analyzer.getConfidenceBoost(for: 9)
        let boost2PM = analyzer.getConfidenceBoost(for: 14)

        XCTAssertEqual(boost9AM, 0.4, accuracy: 0.01) // High completion = positive boost
        XCTAssertEqual(boost2PM, -0.3, accuracy: 0.01) // Low completion = negative boost
    }

    func testConfidenceBoostClamped() async throws {
        mockSupabase.mockFunctionResponse = """
        {
            "hourlyConfidence": {
                "9": {"completionRate": 1.0, "avgRating": 5.0, "dismissRate": 0.0, "confidence": 0.5, "sampleCount": 20}
            },
            "sampleCount": 150,
            "minimumDataMet": true,
            "windowDays": 90
        }
        """

        _ = try await analyzer.analyzePatterns()

        let boost = analyzer.getConfidenceBoost(for: 9)

        // Confidence should be clamped to max 0.5
        XCTAssertLessThanOrEqual(boost, 0.5)
        XCTAssertGreaterThanOrEqual(boost, -0.5)
    }

    // MARK: - Best/Worst Hours Tests

    func testGetBestHours() async throws {
        mockSupabase.mockFunctionResponse = """
        {
            "hourlyConfidence": {
                "9": {"completionRate": 0.85, "avgRating": 4.5, "dismissRate": 0.1, "confidence": 0.4, "sampleCount": 15},
                "14": {"completionRate": 0.75, "avgRating": 4.0, "dismissRate": 0.2, "confidence": 0.2, "sampleCount": 12},
                "19": {"completionRate": 0.45, "avgRating": 3.0, "dismissRate": 0.45, "confidence": -0.2, "sampleCount": 10}
            },
            "sampleCount": 150,
            "minimumDataMet": true,
            "windowDays": 90
        }
        """

        _ = try await analyzer.analyzePatterns()

        let bestHours = analyzer.getBestHours()

        XCTAssertTrue(bestHours.contains(9)) // 0.85 completion rate
        XCTAssertTrue(bestHours.contains(14)) // 0.75 completion rate
        XCTAssertFalse(bestHours.contains(19)) // 0.45 completion rate (below 0.7 threshold)
    }

    func testGetWorstHours() async throws {
        mockSupabase.mockFunctionResponse = """
        {
            "hourlyConfidence": {
                "9": {"completionRate": 0.85, "avgRating": 4.5, "dismissRate": 0.1, "confidence": 0.4, "sampleCount": 15},
                "21": {"completionRate": 0.3, "avgRating": 2.5, "dismissRate": 0.65, "confidence": -0.4, "sampleCount": 10},
                "22": {"completionRate": 0.25, "avgRating": 2.2, "dismissRate": 0.7, "confidence": -0.45, "sampleCount": 8}
            },
            "sampleCount": 150,
            "minimumDataMet": true,
            "windowDays": 90
        }
        """

        _ = try await analyzer.analyzePatterns()

        let worstHours = analyzer.getWorstHours()

        XCTAssertTrue(worstHours.contains(21)) // 0.65 dismiss rate
        XCTAssertTrue(worstHours.contains(22)) // 0.7 dismiss rate
        XCTAssertFalse(worstHours.contains(9)) // 0.1 dismiss rate
    }

    // MARK: - Periodic Refresh Tests

    func testPeriodicRefreshScheduling() async throws {
        mockSupabase.mockFunctionResponse = """
        {
            "hourlyConfidence": {},
            "sampleCount": 100,
            "minimumDataMet": true,
            "windowDays": 90
        }
        """

        analyzer.startPeriodicRefresh()

        // Wait briefly to allow initial refresh
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Should have called function for initial refresh
        XCTAssertGreaterThanOrEqual(mockSupabase.functionCallCount, 1)

        analyzer.stopPeriodicRefresh()
    }

    // MARK: - Hour Formatting Tests

    func testFormatHour() {
        XCTAssertEqual(OptimalTimingAnalyzer.formatHour(0), "12 AM")
        XCTAssertEqual(OptimalTimingAnalyzer.formatHour(9), "9 AM")
        XCTAssertEqual(OptimalTimingAnalyzer.formatHour(12), "12 PM")
        XCTAssertEqual(OptimalTimingAnalyzer.formatHour(14), "2 PM")
        XCTAssertEqual(OptimalTimingAnalyzer.formatHour(23), "11 PM")
    }
}
