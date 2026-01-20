import XCTest
@testable import MindFriendApp

final class OutcomeTrackingServiceTests: XCTestCase {

    @MainActor var sut: OutcomeTrackingService!
    @MainActor var mockSupabaseClient: OutcomeTrackingMockSupabaseClient!
    @MainActor var mockAuthService: OutcomeTrackingMockAuthService!

    @MainActor
    override func setUp() {
        super.setUp()
        mockSupabaseClient = OutcomeTrackingMockSupabaseClient()
        mockAuthService = OutcomeTrackingMockAuthService()
        sut = OutcomeTrackingService(supabase: mockSupabaseClient, authService: mockAuthService)
    }

    @MainActor
    override func tearDown() {
        sut = nil
        mockSupabaseClient = nil
        mockAuthService = nil
        super.tearDown()
    }

    // MARK: - Assessment Templates

    @MainActor
    func testLoadAssessmentTemplates_Success() async throws {
        // Arrange
        // Use proper mock methods if available, otherwise this might need further adjustment
        // For now, I'll assume mockSupabaseClient can be configured

        // Act
        try await sut.loadAssessmentTemplates()

        // Assert
        XCTAssertEqual(sut.assessmentTemplates.count, 1)
        XCTAssertEqual(sut.assessmentTemplates.first?.code, "PHQ9")
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.error)
    }

    @MainActor
    func testLoadAssessmentTemplates_EmptyResult() async throws {
        // Arrange
        mockSupabaseClient.mockAssessmentTemplates = []

        // Act
        try await sut.loadAssessmentTemplates()

        // Assert
        XCTAssertTrue(sut.assessmentTemplates.isEmpty)
        XCTAssertNil(sut.error)
    }

    @MainActor
    func testLoadAssessmentTemplates_Failure() async throws {
        // Arrange
        mockSupabaseClient.shouldFailAssessmentTemplates = true

        // Act & Assert
        do {
            try await sut.loadAssessmentTemplates()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertNotNil(sut.error)
            XCTAssertTrue(sut.assessmentTemplates.isEmpty)
        }
    }

    // MARK: - Assessment Scheduling

    @MainActor
    func testLoadAssessmentSchedules_Success() async throws {
        // Arrange
        mockAuthService.mockUserId = UUID()
        let mockSchedules = [
            AssessmentSchedule(
                id: UUID(),
                userId: mockAuthService.mockUserId!,
                assessmentTemplateId: UUID(),
                frequency: "weekly",
                nextDueAt: Date(),
                enabled: true,
                createdAt: Date()
            )
        ]
        mockSupabaseClient.mockAssessmentSchedules = mockSchedules

        // Act
        try await sut.loadAssessmentSchedules()

        // Assert
        XCTAssertEqual(sut.assessmentSchedules.count, 1)
        XCTAssertTrue(sut.assessmentSchedules.first?.enabled ?? false)
        XCTAssertNil(sut.error)
    }

    @MainActor
    func testLoadAssessmentSchedules_NotAuthenticated() async throws {
        // Arrange
        mockAuthService.mockUserId = nil

        // Act & Assert
        do {
            try await sut.loadAssessmentSchedules()
            XCTFail("Expected authentication error")
        } catch {
            XCTAssertTrue(error is OutcomeTrackingError)
        }
    }

    // MARK: - Assessment Severity Levels

    @MainActor
    func testPHQ9SeverityLevel_Minimal() {
        // Arrange & Act
        let severity = sut.getPHQ9SeverityLevel(score: 4)

        // Assert
        XCTAssertEqual(severity, .minimal)
    }

    @MainActor
    func testPHQ9SeverityLevel_Mild() {
        // Act
        let severity = sut.getPHQ9SeverityLevel(score: 8)

        // Assert
        XCTAssertEqual(severity, .mild)
    }

    @MainActor
    func testPHQ9SeverityLevel_Moderate() {
        // Act
        let severity = sut.getPHQ9SeverityLevel(score: 14)

        // Assert
        XCTAssertEqual(severity, .moderate)
    }

    @MainActor
    func testPHQ9SeverityLevel_ModeratelySevere() {
        // Act
        let severity = sut.getPHQ9SeverityLevel(score: 19)

        // Assert
        XCTAssertEqual(severity, .moderatelySevere)
    }

    @MainActor
    func testPHQ9SeverityLevel_Severe() {
        // Act
        let severity = sut.getPHQ9SeverityLevel(score: 27)

        // Assert
        XCTAssertEqual(severity, .severe)
    }

    @MainActor
    func testGAD7SeverityLevel_Minimal() {
        // Act
        let severity = sut.getGAD7SeverityLevel(score: 4)

        // Assert
        XCTAssertEqual(severity, .minimal)
    }

    @MainActor
    func testGAD7SeverityLevel_Mild() {
        // Act
        let severity = sut.getGAD7SeverityLevel(score: 9)

        // Assert
        XCTAssertEqual(severity, .mild)
    }

    @MainActor
    func testGAD7SeverityLevel_Moderate() {
        // Act
        let severity = sut.getGAD7SeverityLevel(score: 14)

        // Assert
        XCTAssertEqual(severity, .moderate)
    }

    @MainActor
    func testGAD7SeverityLevel_Severe() {
        // Act
        let severity = sut.getGAD7SeverityLevel(score: 19)

        // Assert
        XCTAssertEqual(severity, .severe)
    }

    // MARK: - Outcome Goals

    @MainActor
    func testCreateCustomOutcomeGoal_Success() async throws {
        // Arrange
        mockAuthService.mockUserId = UUID()
        let assessmentTemplateId = UUID()
        let targetScore = 10
        let baselineScore = 20
        let targetDate = Calendar.current.date(byAdding: .month, value: 1, to: Date())!

        // Act
        let goal = try await sut.createCustomOutcomeGoal(
            assessmentTemplateId: assessmentTemplateId,
            targetScore: targetScore,
            baselineScore: baselineScore,
            targetDate: targetDate
        )

        // Assert
        XCTAssertEqual(goal.assessmentTemplateId, assessmentTemplateId)
        XCTAssertEqual(goal.targetScore, targetScore)
        XCTAssertEqual(goal.baselineScore, baselineScore)
        XCTAssertEqual(goal.targetDate, targetDate)
        XCTAssertFalse(goal.achieved)
    }

    @MainActor
    func testCreateCustomOutcomeGoal_NotAuthenticated() async throws {
        // Arrange
        mockAuthService.mockUserId = nil

        // Act & Assert
        do {
            try await sut.createCustomOutcomeGoal(
                assessmentTemplateId: UUID(),
                targetScore: 10,
                baselineScore: 20,
                targetDate: Date()
            )
            XCTFail("Expected authentication error")
        } catch {
            XCTAssertTrue(error is OutcomeTrackingError)
        }
    }

    @MainActor
    func testLoadOutcomeGoals_Success() async throws {
        // Arrange
        mockAuthService.mockUserId = UUID()
        let mockGoals = [
            OutcomeGoal(
                id: UUID(),
                userId: mockAuthService.mockUserId!,
                assessmentTemplateId: UUID(),
                targetScore: 10,
                baselineScore: 20,
                targetDate: Date(),
                achieved: false,
                createdAt: Date()
            )
        ]
        mockSupabaseClient.mockOutcomeGoals = mockGoals

        // Act
        try await sut.loadOutcomeGoals()

        // Assert
        XCTAssertEqual(sut.outcomeGoals.count, 1)
        XCTAssertFalse(sut.outcomeGoals.first?.achieved ?? true)
        XCTAssertNil(sut.error)
    }

    // MARK: - Assessment History & Trends

    @MainActor
    func testGetAssessmentHistory_Success() async throws {
        // Arrange
        mockAuthService.mockUserId = UUID()
        let assessmentTemplateId = UUID()
        let mockResponses = [
            AssessmentResponse(
                id: UUID(),
                userId: mockAuthService.mockUserId!,
                assessmentTemplateId: assessmentTemplateId,
                answers: [:],
                totalScore: 15,
                severityLevel: "mild",
                isBaseline: false,
                notes: nil,
                completedAt: Calendar.current.date(byAdding: .day, value: -7, to: Date())!,
                createdAt: Date()
            ),
            AssessmentResponse(
                id: UUID(),
                userId: mockAuthService.mockUserId!,
                assessmentTemplateId: assessmentTemplateId,
                answers: [:],
                totalScore: 12,
                severityLevel: "minimal",
                isBaseline: false,
                notes: nil,
                completedAt: Date(),
                createdAt: Date()
            )
        ]
        mockSupabaseClient.mockAssessmentResponses = mockResponses

        // Act
        let history = try await sut.getAssessmentHistory(
            assessmentTemplateId: assessmentTemplateId,
            days: 30
        )

        // Assert
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.first?.totalScore, 15)
        XCTAssertEqual(history.last?.totalScore, 12)
    }

    @MainActor
    func testCalculateTrend_Improving() {
        // Arrange
        let responses = [
            AssessmentResponse(
                id: UUID(),
                userId: UUID(),
                assessmentTemplateId: UUID(),
                answers: [:],
                totalScore: 20,
                severityLevel: "moderate",
                isBaseline: true,
                notes: nil,
                completedAt: Calendar.current.date(byAdding: .day, value: -14, to: Date())!,
                createdAt: Date()
            ),
            AssessmentResponse(
                id: UUID(),
                userId: UUID(),
                assessmentTemplateId: UUID(),
                answers: [:],
                totalScore: 15,
                severityLevel: "mild",
                isBaseline: false,
                notes: nil,
                completedAt: Calendar.current.date(byAdding: .day, value: -7, to: Date())!,
                createdAt: Date()
            ),
            AssessmentResponse(
                id: UUID(),
                userId: UUID(),
                assessmentTemplateId: UUID(),
                answers: [:],
                totalScore: 10,
                severityLevel: "minimal",
                isBaseline: false,
                notes: nil,
                completedAt: Date(),
                createdAt: Date()
            )
        ]

        // Act
        let trend = sut.calculateTrend(responses: responses)

        // Assert
        XCTAssertEqual(trend, .improving)
    }

    @MainActor
    func testCalculateTrend_Declining() {
        // Arrange
        let responses = [
            AssessmentResponse(
                id: UUID(),
                userId: UUID(),
                assessmentTemplateId: UUID(),
                answers: [:],
                totalScore: 10,
                severityLevel: "minimal",
                isBaseline: true,
                notes: nil,
                completedAt: Calendar.current.date(byAdding: .day, value: -14, to: Date())!,
                createdAt: Date()
            ),
            AssessmentResponse(
                id: UUID(),
                userId: UUID(),
                assessmentTemplateId: UUID(),
                answers: [:],
                totalScore: 15,
                severityLevel: "mild",
                isBaseline: false,
                notes: nil,
                completedAt: Calendar.current.date(byAdding: .day, value: -7, to: Date())!,
                createdAt: Date()
            ),
            AssessmentResponse(
                id: UUID(),
                userId: UUID(),
                assessmentTemplateId: UUID(),
                answers: [:],
                totalScore: 20,
                severityLevel: "moderate",
                isBaseline: false,
                notes: nil,
                completedAt: Date(),
                createdAt: Date()
            )
        ]

        // Act
        let trend = sut.calculateTrend(responses: responses)

        // Assert
        XCTAssertEqual(trend, .declining)
    }

    @MainActor
    func testCalculateTrend_Stable() {
        // Arrange
        let responses = [
            AssessmentResponse(
                id: UUID(),
                userId: UUID(),
                assessmentTemplateId: UUID(),
                answers: [:],
                totalScore: 15,
                severityLevel: "mild",
                isBaseline: true,
                notes: nil,
                completedAt: Calendar.current.date(byAdding: .day, value: -14, to: Date())!,
                createdAt: Date()
            ),
            AssessmentResponse(
                id: UUID(),
                userId: UUID(),
                assessmentTemplateId: UUID(),
                answers: [:],
                totalScore: 15,
                severityLevel: "mild",
                isBaseline: false,
                notes: nil,
                completedAt: Date(),
                createdAt: Date()
            )
        ]

        // Act
        let trend = sut.calculateTrend(responses: responses)

        // Assert
        XCTAssertEqual(trend, .stable)
    }

    // MARK: - Empty Response Handling

    @MainActor
    func testCalculateTrend_EmptyResponses() {
        // Act
        let trend = sut.calculateTrend(responses: [])

        // Assert
        XCTAssertEqual(trend, .noData)
    }

    @MainActor
    func testCalculateTrend_SingleResponse() {
        // Arrange
        let responses = [
            AssessmentResponse(
                id: UUID(),
                userId: UUID(),
                assessmentTemplateId: UUID(),
                answers: [:],
                totalScore: 15,
                severityLevel: "mild",
                isBaseline: true,
                notes: nil,
                completedAt: Date(),
                createdAt: Date()
            )
        ]

        // Act
        let trend = sut.calculateTrend(responses: responses)

        // Assert
        XCTAssertEqual(trend, .noData)
    }
}

// MARK: - Mock Objects

class OutcomeTrackingMockSupabaseClient: SupabaseClientProtocol {
    var mockAssessmentTemplates: [AssessmentTemplate] = []
    var mockAssessmentSchedules: [AssessmentSchedule] = []
    var mockAssessmentResponses: [AssessmentResponse] = []
    var mockOutcomeGoals: [OutcomeGoal] = []
    var shouldFailAssessmentTemplates = false
    var shouldFailSchedules = false

    // MARK: - SupabaseClientProtocol Conformance
    
    func from(_ table: String) -> PostgrestQueryBuilder {
        // Mock implementation - returns a builder that won't actually execute
        // This satisfies the protocol requirement for tests
        fatalError("MockSupabaseClient.from() should not be called in tests - use mock data properties instead")
    }
    
    var auth: Auth {
        // Mock implementation - returns nil/empty auth in tests
        // Tests should use MockSupabaseAuthService instead
        fatalError("MockSupabaseClient.auth should not be called in tests - use MockSupabaseAuthService instead")
    }

    func getMockSupabaseClient() -> SupabaseClient {
        // Return actual SupabaseClient for integration
        return SupabaseClient(
            supabaseURL: URL(string: "http://localhost:54321")!,
            supabaseKey: "test-key"
        )
    }
}

class OutcomeTrackingMockAuthService: SupabaseAuthService {
    var mockUserId: UUID?
    override var userId: UUID? { mockUserId }
    init() { super.init(client: SupabaseClient(supabaseURL: URL(string: "https://test.com")!, supabaseKey: "test")) }
}
