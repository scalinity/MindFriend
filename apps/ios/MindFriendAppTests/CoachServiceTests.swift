import XCTest
@testable import MindFriendApp

final class CoachServiceTests: XCTestCase {
    var sut: MockCoachService!

    override func setUp() {
        super.setUp()
        sut = MockCoachService()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Get Settings Tests

    func testGetSettingsSuccess() async throws {
        let expectedSettings = CoachSettings(
            isEnabled: true,
            sensitivityLevel: .balanced,
            silentHoursStart: Date(timeIntervalSince1970: 82800),
            silentHoursEnd: Date(timeIntervalSince1970: 21600),
            disabledDistortions: nil,
            showPatterns: true
        )

        sut.mockSettings = expectedSettings

        let settings = try await sut.getSettings()

        XCTAssertEqual(settings.isEnabled, expectedSettings.isEnabled)
        XCTAssertEqual(settings.sensitivityLevel, expectedSettings.sensitivityLevel)
        XCTAssertEqual(settings.showPatterns, expectedSettings.showPatterns)
    }

    func testGetSettingsNetworkError() async {
        sut.shouldThrowError = true
        sut.mockError = "Network error"

        do {
            _ = try await sut.getSettings()
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertTrue(error is CoachError)
        }
    }

    // MARK: - Update Settings Tests

    func testUpdateSettingsSuccess() async throws {
        let updatedSettings = CoachSettings(
            isEnabled: false,
            sensitivityLevel: .minimal,
            silentHoursStart: Date(timeIntervalSince1970: 79200),
            silentHoursEnd: Date(timeIntervalSince1970: 28800),
            disabledDistortions: ["AON", "CAT"],
            showPatterns: false
        )

        try await sut.updateSettings(updatedSettings)

        XCTAssertEqual(sut.lastUpdatedSettings?.isEnabled, false)
        XCTAssertEqual(sut.lastUpdatedSettings?.sensitivityLevel, .minimal)
        XCTAssertEqual(sut.lastUpdatedSettings?.disabledDistortions?.count, 2)
    }

    // MARK: - Record Interaction Tests

    func testRecordInteractionHelpful() async throws {
        let encounterId = UUID()
        let distortionCode = "AON"

        try await sut.recordInteraction(
            encounterId: encounterId,
            distortionCode: distortionCode,
            action: .helpful,
            confidence: 0.85
        )

        XCTAssertEqual(sut.lastRecordedInteraction?.action, .helpful)
        XCTAssertEqual(sut.lastRecordedInteraction?.distortionCode, distortionCode)
    }

    func testRecordInteractionDismissed() async throws {
        let distortionCode = "CAT"

        try await sut.recordInteraction(
            encounterId: nil,
            distortionCode: distortionCode,
            action: .dismissed,
            confidence: 0.72
        )

        XCTAssertEqual(sut.lastRecordedInteraction?.action, .dismissed)
    }

    // MARK: - Get Patterns Tests

    func testGetPatternsSuccess() async throws {
        let expectedAnalytics = PatternAnalytics(
            totalEncounters: 15,
            last7Days: 8,
            last30Days: 15,
            mostCommon: [
                DistortionStat(code: "AON", name: "All-or-Nothing", count: 5, percentage: 33.3, trend: "stable", helpfulRate: 0.8),
                DistortionStat(code: "CAT", name: "Catastrophizing", count: 3, percentage: 20.0, trend: "decreasing", helpfulRate: 0.67),
            ],
            byDistortionType: []
        )

        sut.mockAnalytics = expectedAnalytics

        let patterns = try await sut.getMyPatterns()

        XCTAssertEqual(patterns.totalEncounters, 15)
        XCTAssertEqual(patterns.last7Days, 8)
        XCTAssertEqual(patterns.mostCommon.count, 2)
        XCTAssertEqual(patterns.mostCommon[0].count, 5)
    }

    func testGetPatternsEmpty() async throws {
        let emptyAnalytics = PatternAnalytics(
            totalEncounters: 0,
            last7Days: 0,
            last30Days: 0,
            mostCommon: [],
            byDistortionType: []
        )

        sut.mockAnalytics = emptyAnalytics

        let patterns = try await sut.getMyPatterns()

        XCTAssertEqual(patterns.totalEncounters, 0)
        XCTAssertTrue(patterns.mostCommon.isEmpty)
    }

    // MARK: - Get Distortion Library Tests

    func testGetDistortionLibrary() async throws {
        let mockLibrary = [
            CognitiveDistortionDefinition(
                code: "AON",
                name: "All-or-Nothing Thinking",
                shortDescription: "Black and white thinking",
                fullDescription: "Viewing situations as completely good or bad",
                examples: ["If I'm not perfect, I'm a failure"],
                questionsToChallenge: ["What evidence contradicts this?"],
                reframeTemplates: ["Perfection isn't possible"],
                displayOrder: 1
            ),
        ]

        sut.mockLibrary = mockLibrary

        let library = try await sut.getDistortionLibrary()

        XCTAssertEqual(library.count, 1)
        XCTAssertEqual(library[0].code, "AON")
        XCTAssertEqual(library[0].name, "All-or-Nothing Thinking")
    }

    // MARK: - Get Specific Distortion Tests

    func testGetDistortionByCode() async throws {
        let distortion = CognitiveDistortionDefinition(
            code: "CAT",
            name: "Catastrophizing",
            shortDescription: "Expecting the worst",
            fullDescription: "Assuming terrible outcomes",
            examples: ["One mistake means everything fails"],
            questionsToChallenge: ["How likely is this?"],
            reframeTemplates: ["What's actually most likely?"],
            displayOrder: 2
        )

        sut.mockDistortion = distortion

        let result = try await sut.getDistortion(code: "CAT")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.code, "CAT")
    }

    func testGetDistortionNotFound() async throws {
        sut.mockDistortion = nil

        let result = try await sut.getDistortion(code: "INVALID")

        XCTAssertNil(result)
    }

    // MARK: - Get Encounters Tests

    func testGetEncountersLimit() async throws {
        let mockEncounters = [
            DistortionEncounter(
                id: UUID(),
                userId: UUID(),
                distortionCode: "AON",
                originalMessagePreview: "I always mess up",
                reframeOffered: true,
                reframeAccepted: false,
                encounterType: "chat",
                occurredAt: Date(),
                clientGeneratedId: "1"
            ),
            DistortionEncounter(
                id: UUID(),
                userId: UUID(),
                distortionCode: "CAT",
                originalMessagePreview: "Everything will go wrong",
                reframeOffered: true,
                reframeAccepted: true,
                encounterType: "chat",
                occurredAt: Date(timeIntervalSinceNow: -3600),
                clientGeneratedId: "2"
            ),
        ]

        sut.mockEncounters = mockEncounters

        let encounters = try await sut.getEncounters(limit: 10)

        XCTAssertEqual(encounters.count, 2)
        XCTAssertEqual(encounters[0].distortionCode, "AON")
        XCTAssertEqual(encounters[1].distortionCode, "CAT")
    }
}

// MARK: - Mock Coach Service

@MainActor
class MockCoachService: CoachServiceProtocol {
    var mockSettings: CoachSettings?
    var mockAnalytics: PatternAnalytics?
    var mockLibrary: [CognitiveDistortionDefinition] = []
    var mockDistortion: CognitiveDistortionDefinition?
    var mockEncounters: [DistortionEncounter] = []
    var mockWeeklySummary: WeeklyPatternSummary?
    var shouldThrowError = false
    var mockError: String?

    var lastUpdatedSettings: CoachSettings?
    var lastRecordedInteraction: CoachInteraction?

    func getSettings() async throws -> CoachSettings {
        if shouldThrowError {
            throw CoachError.networkError
        }
        return mockSettings ?? CoachSettings(
            isEnabled: true,
            sensitivityLevel: .balanced,
            silentHoursStart: nil,
            silentHoursEnd: nil,
            disabledDistortions: nil,
            showPatterns: true
        )
    }

    func updateSettings(_ settings: CoachSettings) async throws {
        if shouldThrowError {
            throw CoachError.networkError
        }
        lastUpdatedSettings = settings
    }

    func recordInteraction(encounterId: UUID?, distortionCode: String, action: CoachInteraction.Action, confidence: Double?) async throws {
        if shouldThrowError {
            throw CoachError.networkError
        }
        lastRecordedInteraction = CoachInteraction(
            id: UUID(),
            userId: UUID(),
            encounterId: encounterId,
            distortionCode: distortionCode,
            action: action,
            confidence: confidence,
            occurredAt: Date()
        )
    }

    func getMyPatterns() async throws -> PatternAnalytics {
        if shouldThrowError {
            throw CoachError.networkError
        }
        return mockAnalytics ?? PatternAnalytics(
            totalEncounters: 0,
            last7Days: 0,
            last30Days: 0,
            mostCommon: [],
            byDistortionType: []
        )
    }

    func getWeeklySummary() async throws -> WeeklyPatternSummary? {
        if shouldThrowError {
            throw CoachError.networkError
        }
        return mockWeeklySummary
    }

    func getDistortionLibrary() async throws -> [CognitiveDistortionDefinition] {
        if shouldThrowError {
            throw CoachError.networkError
        }
        return mockLibrary
    }

    func getDistortion(code: String) async throws -> CognitiveDistortionDefinition? {
        if shouldThrowError {
            throw CoachError.networkError
        }
        return mockDistortion
    }

    func getEncounters(limit: Int) async throws -> [DistortionEncounter] {
        if shouldThrowError {
            throw CoachError.networkError
        }
        return mockEncounters.prefix(limit).map { $0 }
    }
}

// MARK: - Coach Error Enum

enum CoachError: Error {
    case networkError(String)
    case decodingError
    case notFound
}
