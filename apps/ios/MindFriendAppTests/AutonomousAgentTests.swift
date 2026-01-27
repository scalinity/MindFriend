import XCTest
@testable import MindFriendApp

// MARK: - Agent Models Tests

final class AgentModelsTests: XCTestCase {

    // MARK: - AutonomyLevel Tests

    func testAutonomyLevelDisplayNames() {
        XCTAssertEqual(AutonomyLevel.minimal.displayName, "Minimal")
        XCTAssertEqual(AutonomyLevel.balanced.displayName, "Balanced")
        XCTAssertEqual(AutonomyLevel.proactive.displayName, "Proactive")
        XCTAssertEqual(AutonomyLevel.guardian.displayName, "Guardian")
    }

    func testAutonomyLevelMaxDailyActions() {
        XCTAssertEqual(AutonomyLevel.minimal.maxDailyActions, 1)
        XCTAssertEqual(AutonomyLevel.balanced.maxDailyActions, 3)
        XCTAssertEqual(AutonomyLevel.proactive.maxDailyActions, 6)
        XCTAssertEqual(AutonomyLevel.guardian.maxDailyActions, 10)
    }

    func testAutonomyLevelConfidenceThreshold() {
        XCTAssertEqual(AutonomyLevel.minimal.confidenceThreshold, 0.85)
        XCTAssertEqual(AutonomyLevel.balanced.confidenceThreshold, 0.70)
        XCTAssertEqual(AutonomyLevel.proactive.confidenceThreshold, 0.50)
        XCTAssertEqual(AutonomyLevel.guardian.confidenceThreshold, 0.30)
    }

    // MARK: - SignalType Tests

    func testSignalTypeDisplayNames() {
        XCTAssertEqual(SignalType.moodDecline.displayName, "Mood Decline")
        XCTAssertEqual(SignalType.activityDrop.displayName, "Activity Drop")
        XCTAssertEqual(SignalType.streakRisk.displayName, "Streak at Risk")
        XCTAssertEqual(SignalType.inactivity.displayName, "Extended Inactivity")
        XCTAssertEqual(SignalType.positiveMomentum.displayName, "Positive Momentum")
    }

    func testSignalTypeIcons() {
        XCTAssertEqual(SignalType.moodDecline.iconName, "arrow.down.circle")
        XCTAssertEqual(SignalType.activityDrop.iconName, "figure.walk.motion")
        XCTAssertEqual(SignalType.streakRisk.iconName, "flame")
        XCTAssertEqual(SignalType.inactivity.iconName, "moon.zzz")
        XCTAssertEqual(SignalType.positiveMomentum.iconName, "star.fill")
    }

    // MARK: - Severity Tests

    func testSeverityDisplayNames() {
        XCTAssertEqual(Severity.low.displayName, "Low")
        XCTAssertEqual(Severity.medium.displayName, "Medium")
        XCTAssertEqual(Severity.high.displayName, "High")
        XCTAssertEqual(Severity.critical.displayName, "Critical")
    }

    // MARK: - ActionType Tests

    func testActionTypeDisplayNames() {
        XCTAssertEqual(ActionType.checkIn.displayName, "Check-In")
        XCTAssertEqual(ActionType.suggestExercise.displayName, "Exercise Suggestion")
        XCTAssertEqual(ActionType.morningBriefing.displayName, "Morning Briefing")
        XCTAssertEqual(ActionType.encouragement.displayName, "Encouragement")
        XCTAssertEqual(ActionType.streakReminder.displayName, "Streak Reminder")
        XCTAssertEqual(ActionType.moodPrompt.displayName, "Mood Prompt")
        XCTAssertEqual(ActionType.contentRecommendation.displayName, "Content Recommendation")
        XCTAssertEqual(ActionType.concernAlert.displayName, "Concern Alert")
    }

    // MARK: - ActionStatus Tests

    func testActionStatusTerminalStates() {
        XCTAssertFalse(ActionStatus.planned.isTerminal)
        XCTAssertFalse(ActionStatus.scheduled.isTerminal)
        XCTAssertFalse(ActionStatus.delivered.isTerminal)
        XCTAssertFalse(ActionStatus.opened.isTerminal)
        XCTAssertTrue(ActionStatus.responded.isTerminal)
        XCTAssertTrue(ActionStatus.dismissed.isTerminal)
        XCTAssertTrue(ActionStatus.cancelled.isTerminal)
    }

    // MARK: - AgentSettings Tests

    func testAgentSettingsDecoding() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "user_id": "550e8400-e29b-41d4-a716-446655440001",
            "is_enabled": true,
            "autonomy_level": "balanced",
            "enabled_signals": ["mood_decline", "activity_drop"],
            "preferred_channels": ["push", "in_app"],
            "quiet_hours_start": "22:00",
            "quiet_hours_end": "08:00",
            "max_daily_outreach": 3,
            "explain_reasoning": true,
            "timezone": "America/Los_Angeles",
            "created_at": "2026-01-25T00:00:00Z",
            "updated_at": "2026-01-25T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let settings = try decoder.decode(AgentSettings.self, from: json)

        XCTAssertEqual(settings.isEnabled, true)
        XCTAssertEqual(settings.autonomyLevel, .balanced)
        XCTAssertEqual(settings.enabledSignals, ["mood_decline", "activity_drop"])
        XCTAssertEqual(settings.preferredChannels, ["push", "in_app"])
        XCTAssertEqual(settings.quietHoursStart, "22:00")
        XCTAssertEqual(settings.quietHoursEnd, "08:00")
        XCTAssertEqual(settings.maxDailyOutreach, 3)
        XCTAssertEqual(settings.explainReasoning, true)
        XCTAssertEqual(settings.timezone, "America/Los_Angeles")
    }

    // MARK: - AgentSignal Tests

    func testAgentSignalDecoding() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "user_id": "550e8400-e29b-41d4-a716-446655440001",
            "signal_type": "mood_decline",
            "severity": "medium",
            "confidence": 0.85,
            "evidence": {
                "dataPoints": [
                    {"metric": "mood", "value": 3.0, "timestamp": "2026-01-20T00:00:00Z"}
                ],
                "trend": {"direction": "down", "magnitude": 0.5, "durationDays": 3},
                "comparison": {"baseline": 4.0, "current": 3.0, "percentChange": -25.0}
            },
            "detected_at": "2026-01-25T10:00:00Z",
            "is_resolved": false,
            "created_at": "2026-01-25T10:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let signal = try decoder.decode(AgentSignal.self, from: json)

        XCTAssertEqual(signal.signalType, .moodDecline)
        XCTAssertEqual(signal.severity, .medium)
        XCTAssertEqual(signal.confidence, 0.85)
        XCTAssertEqual(signal.isResolved, false)
        XCTAssertNotNil(signal.evidence.trend)
        XCTAssertEqual(signal.evidence.trend?.direction, "down")
        XCTAssertEqual(signal.evidence.trend?.durationDays, 3)
    }

    // MARK: - AgentAction Tests

    func testAgentActionDecoding() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "user_id": "550e8400-e29b-41d4-a716-446655440001",
            "action_type": "check_in",
            "status": "delivered",
            "scheduled_for": "2026-01-25T14:00:00Z",
            "delivered_at": "2026-01-25T14:00:00Z",
            "content": {
                "title": "How are you doing?",
                "body": "I noticed you might be feeling down. Want to talk about it?"
            },
            "channel": "push",
            "reasoning": "Mood decline detected over 3 days",
            "created_at": "2026-01-25T10:00:00Z",
            "updated_at": "2026-01-25T14:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let action = try decoder.decode(AgentAction.self, from: json)

        XCTAssertEqual(action.actionType, .checkIn)
        XCTAssertEqual(action.status, .delivered)
        XCTAssertEqual(action.content.title, "How are you doing?")
        XCTAssertEqual(action.content.body, "I noticed you might be feeling down. Want to talk about it?")
        XCTAssertEqual(action.channel, "push")
        XCTAssertEqual(action.reasoning, "Mood decline detected over 3 days")
    }

    // MARK: - AgentLearning Tests

    func testAgentLearningDecoding() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "user_id": "550e8400-e29b-41d4-a716-446655440001",
            "learning_type": "optimal_time",
            "learned_value": {"preferred_hours": [9, 10, 18]},
            "confidence": 0.75,
            "sample_count": 10,
            "last_updated": "2026-01-25T00:00:00Z",
            "created_at": "2026-01-25T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let learning = try decoder.decode(AgentLearning.self, from: json)

        XCTAssertEqual(learning.learningType, .optimalTime)
        XCTAssertEqual(learning.confidence, 0.75)
        XCTAssertEqual(learning.sampleCount, 10)
    }
}

// MARK: - Mock Agent Service

class MockAgentService: AgentServiceProtocol {
    var settingsToReturn: AgentSettings?
    var signalsToReturn: [AgentSignal] = []
    var actionsToReturn: [AgentAction] = []
    var learningsToReturn: [AgentLearning] = []
    var decisionsToReturn: [AgentDecision] = []
    var shouldThrowError = false

    // Track method calls
    var fetchSettingsCalled = false
    var updateSettingsCalled = false
    var updateSettingsInput: AgentSettings?
    var fetchActiveSignalsCalled = false
    var fetchRecentActionsCalled = false
    var recordResponseCalled = false
    var recordResponseInput: (actionId: UUID, response: UserResponse)?
    var dismissActionCalled = false
    var dismissActionInput: UUID?
    var markHelpfulCalled = false
    var markHelpfulInput: (actionId: UUID, isHelpful: Bool)?
    var fetchLearningsCalled = false
    var fetchDecisionsCalled = false
    var getActionsCountTodayCalled = false

    func fetchSettings() async throws -> AgentSettings {
        fetchSettingsCalled = true
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
        guard let settings = settingsToReturn else {
            throw NSError(domain: "MockError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No settings configured"])
        }
        return settings
    }

    func updateSettings(_ settings: AgentSettings) async throws {
        updateSettingsCalled = true
        updateSettingsInput = settings
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
    }

    func fetchActiveSignals() async throws -> [AgentSignal] {
        fetchActiveSignalsCalled = true
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
        return signalsToReturn
    }

    func fetchRecentActions(limit: Int) async throws -> [AgentAction] {
        fetchRecentActionsCalled = true
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
        return Array(actionsToReturn.prefix(limit))
    }

    func recordResponse(actionId: UUID, response: UserResponse) async throws -> AgentLearnResponse {
        recordResponseCalled = true
        recordResponseInput = (actionId, response)
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
        return AgentLearnResponse(learningsUpdated: 1, effectivenessScore: 1.0)
    }

    func dismissAction(actionId: UUID) async throws {
        dismissActionCalled = true
        dismissActionInput = actionId
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
    }

    func markActionAsHelpful(actionId: UUID, isHelpful: Bool) async throws {
        markHelpfulCalled = true
        markHelpfulInput = (actionId, isHelpful)
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
    }

    func fetchLearnings() async throws -> [AgentLearning] {
        fetchLearningsCalled = true
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
        return learningsToReturn
    }

    func fetchDecisions(limit: Int) async throws -> [AgentDecision] {
        fetchDecisionsCalled = true
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
        return Array(decisionsToReturn.prefix(limit))
    }

    func getActionsCountToday() async throws -> Int {
        getActionsCountTodayCalled = true
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
        return actionsToReturn.count
    }

    var loadDashboardDataCalled = false

    func loadDashboardData() async throws -> AgentDashboardData {
        loadDashboardDataCalled = true
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
        guard let settings = settingsToReturn else {
            throw NSError(domain: "MockError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No settings configured"])
        }
        return AgentDashboardData(
            settings: settings,
            activeSignals: signalsToReturn,
            recentActions: actionsToReturn,
            actionsToday: actionsToReturn.count
        )
    }
}

// MARK: - Agent Service Integration Tests

final class AgentServiceTests: XCTestCase {
    var mockService: MockAgentService!

    override func setUp() {
        super.setUp()
        mockService = MockAgentService()
    }

    override func tearDown() {
        mockService = nil
        super.tearDown()
    }

    // MARK: - Fetch Settings Tests

    func testFetchSettingsSuccess() async throws {
        let expectedSettings = createMockSettings()
        mockService.settingsToReturn = expectedSettings

        let settings = try await mockService.fetchSettings()

        XCTAssertTrue(mockService.fetchSettingsCalled)
        XCTAssertEqual(settings.isEnabled, expectedSettings.isEnabled)
        XCTAssertEqual(settings.autonomyLevel, expectedSettings.autonomyLevel)
    }

    func testFetchSettingsError() async {
        mockService.shouldThrowError = true

        do {
            _ = try await mockService.fetchSettings()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(mockService.fetchSettingsCalled)
        }
    }

    // MARK: - Update Settings Tests

    func testUpdateSettingsSuccess() async throws {
        let settings = createMockSettings()
        mockService.settingsToReturn = settings

        try await mockService.updateSettings(settings)

        XCTAssertTrue(mockService.updateSettingsCalled)
        XCTAssertEqual(mockService.updateSettingsInput?.isEnabled, settings.isEnabled)
    }

    // MARK: - Fetch Active Signals Tests

    func testFetchActiveSignalsSuccess() async throws {
        let signals = [createMockSignal()]
        mockService.signalsToReturn = signals

        let result = try await mockService.fetchActiveSignals()

        XCTAssertTrue(mockService.fetchActiveSignalsCalled)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.signalType, .moodDecline)
    }

    func testFetchActiveSignalsEmpty() async throws {
        mockService.signalsToReturn = []

        let result = try await mockService.fetchActiveSignals()

        XCTAssertTrue(mockService.fetchActiveSignalsCalled)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Fetch Recent Actions Tests

    func testFetchRecentActionsWithLimit() async throws {
        mockService.actionsToReturn = [createMockAction(), createMockAction(), createMockAction()]

        let result = try await mockService.fetchRecentActions(limit: 2)

        XCTAssertTrue(mockService.fetchRecentActionsCalled)
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - Record Response Tests

    func testRecordResponseSuccess() async throws {
        let actionId = UUID()
        let response = UserResponse(
            responseType: "responded",
            selectedAction: nil,
            timestamp: Date(),
            sentiment: "positive"
        )

        let result = try await mockService.recordResponse(actionId: actionId, response: response)

        XCTAssertTrue(mockService.recordResponseCalled)
        XCTAssertEqual(mockService.recordResponseInput?.actionId, actionId)
        XCTAssertEqual(mockService.recordResponseInput?.response.responseType, "responded")
        XCTAssertEqual(result.learningsUpdated, 1)
    }

    // MARK: - Dismiss Action Tests

    func testDismissActionSuccess() async throws {
        let actionId = UUID()

        try await mockService.dismissAction(actionId: actionId)

        XCTAssertTrue(mockService.dismissActionCalled)
        XCTAssertEqual(mockService.dismissActionInput, actionId)
    }

    // MARK: - Mark Helpful Tests

    func testMarkHelpfulTrue() async throws {
        let actionId = UUID()

        try await mockService.markActionAsHelpful(actionId: actionId, isHelpful: true)

        XCTAssertTrue(mockService.markHelpfulCalled)
        XCTAssertEqual(mockService.markHelpfulInput?.actionId, actionId)
        XCTAssertEqual(mockService.markHelpfulInput?.isHelpful, true)
    }

    func testMarkHelpfulFalse() async throws {
        let actionId = UUID()

        try await mockService.markActionAsHelpful(actionId: actionId, isHelpful: false)

        XCTAssertTrue(mockService.markHelpfulCalled)
        XCTAssertEqual(mockService.markHelpfulInput?.actionId, actionId)
        XCTAssertEqual(mockService.markHelpfulInput?.isHelpful, false)
    }

    // MARK: - Fetch Learnings Tests

    func testFetchLearningsSuccess() async throws {
        mockService.learningsToReturn = [createMockLearning()]

        let result = try await mockService.fetchLearnings()

        XCTAssertTrue(mockService.fetchLearningsCalled)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.learningType, .optimalTime)
    }

    // MARK: - Load Dashboard Data Tests

    func testLoadDashboardDataSuccess() async throws {
        let settings = createMockSettings()
        let signals = [createMockSignal()]
        let actions = [createMockAction()]

        mockService.settingsToReturn = settings
        mockService.signalsToReturn = signals
        mockService.actionsToReturn = actions

        let data = try await mockService.loadDashboardData()

        XCTAssertTrue(mockService.loadDashboardDataCalled)
        XCTAssertEqual(data.isAgentActive, settings.isEnabled)
        XCTAssertEqual(data.activeSignals.count, 1)
        XCTAssertEqual(data.recentActions.count, 1)
        XCTAssertEqual(data.actionsToday, 1)
    }

    // MARK: - Helper Methods

    private func createMockSettings() -> AgentSettings {
        AgentSettings(
            id: UUID(),
            userId: UUID(),
            autonomyLevel: .balanced,
            enabledSignals: ["mood_decline", "activity_drop"],
            quietHoursStart: "22:00",
            quietHoursEnd: "08:00",
            maxDailyOutreach: 3,
            preferredChannels: ["push"],
            explainReasoning: true,
            isEnabled: true,
            timezone: "America/Los_Angeles",
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func createMockSignal() -> AgentSignal {
        AgentSignal(
            id: UUID(),
            userId: UUID(),
            signalType: .moodDecline,
            severity: .medium,
            confidence: 0.85,
            evidence: SignalEvidence(
                dataPoints: nil,
                trend: TrendInfo(direction: "down", magnitude: 0.5, durationDays: 3),
                comparison: nil
            ),
            detectedAt: Date(),
            expiresAt: nil,
            isResolved: false,
            resolvedAt: nil,
            resolutionType: nil,
            createdAt: Date()
        )
    }

    private func createMockAction() -> AgentAction {
        AgentAction(
            id: UUID(),
            userId: UUID(),
            signalId: nil,
            actionType: .checkIn,
            status: .delivered,
            scheduledFor: Date(),
            deliveredAt: Date(),
            content: ActionContent(
                title: "How are you?",
                body: "Just checking in on you.",
                quickActions: nil,
                deepLink: nil,
                metadata: nil
            ),
            channel: "push",
            reasoning: "Test reasoning",
            userResponse: nil,
            effectivenessScore: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func createMockLearning() -> AgentLearning {
        AgentLearning(
            id: UUID(),
            userId: UUID(),
            learningType: .optimalTime,
            learnedValue: ["preferred_hours": AnyCodableValue.array([AnyCodableValue.int(9), AnyCodableValue.int(10)])],
            confidence: 0.75,
            sampleCount: 10,
            lastUpdated: Date(),
            createdAt: Date()
        )
    }
}
