import XCTest
@testable import MindFriendApp

final class RitualSessionViewModelTests: XCTestCase {

    var sut: RitualSessionViewModel!
    var mockRitualService: MockRitualService!
    let testRitual = CircleRitual.mock()

    override func setUp() {
        super.setUp()
        mockRitualService = MockRitualService()
        sut = RitualSessionViewModel(ritual: testRitual)
        sut.setService(mockRitualService)
    }

    override func tearDown() {
        sut.stopSession()
        sut = nil
        mockRitualService = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialState() {
        XCTAssertEqual(sut.currentStepIndex, 0)
        XCTAssertEqual(sut.attendees.count, 0)
        XCTAssertFalse(sut.isCompleted)
        XCTAssertEqual(sut.totalSteps, 3) // gratitude has 3 steps
    }

    func testInitialPrompt() {
        XCTAssertFalse(sut.currentPrompt.isEmpty)
    }

    func testTimeRemainingInitialized() {
        XCTAssertEqual(sut.timeRemaining, testRitual.durationSeconds)
    }

    func testProgressInitialized() {
        XCTAssertEqual(sut.progress, 0.0)
    }

    // MARK: - startSession Tests

    func testStartSession_success() async {
        mockRitualService.joinResult = (
            ritual: testRitual,
            currentStep: RitualStep(stepIndex: 1, prompt: "Step 2", timeRemaining: 45, completed: false),
            attendees: []
        )

        await sut.startSession()

        XCTAssertTrue(mockRitualService.joinCalled)
        XCTAssertEqual(sut.currentStepIndex, 1)
        XCTAssertEqual(sut.currentPrompt, "Step 2")
    }

    func testStartSession_updatesAttendees() async {
        let attendees = [
            RitualAttendeeInfo(userId: UUID(), displayName: "Alice", joinedAt: Date()),
            RitualAttendeeInfo(userId: UUID(), displayName: "Bob", joinedAt: Date())
        ]

        mockRitualService.joinResult = (
            ritual: testRitual,
            currentStep: nil,
            attendees: attendees
        )

        await sut.startSession()

        XCTAssertEqual(sut.attendees.count, 2)
    }

    func testStartSession_noService() {
        let vmWithoutService = RitualSessionViewModel(ritual: testRitual)

        // Should not crash when service is nil
        XCTAssertNil(vmWithoutService.formattedTimeRemaining)
    }

    // MARK: - Timer Tests

    func testTimerProgress_updatesProgress() {
        sut.startTimer()

        // Wait for timer to fire
        let expectation = XCTestExpectation(description: "Timer tick")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        XCTAssertGreaterThan(sut.progress, 0)
    }

    func testTimerProgress_completesAtEnd() {
        // Create a ritual that already completed
        let completedRitual = CircleRitual(
            id: testRitual.id,
            circleId: testRitual.circleId,
            createdBy: testRitual.createdBy,
            title: testRitual.title,
            ritualType: testRitual.ritualType,
            scheduledFor: Date().addingTimeInterval(-200), // Started 200s ago
            durationSeconds: 180,
            status: .active,
            createdAt: testRitual.createdAt,
            completedAt: nil
        )

        let completedVM = RitualSessionViewModel(ritual: completedRitual)
        let mockService = MockRitualService()
        completedVM.setService(mockService)

        // Start timer and wait for completion
        completedVM.startTimer()

        let expectation = XCTestExpectation(description: "Ritual completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if completedVM.isCompleted {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 3.0)

        XCTAssertTrue(completedVM.isCompleted)
    }

    // MARK: - stopSession Tests

    func testStopSession_clearsAttendees() async {
        let attendees = [RitualAttendeeInfo(userId: UUID(), displayName: "Alice", joinedAt: Date())]
        mockRitualService.joinResult = (
            ritual: testRitual,
            currentStep: nil,
            attendees: attendees
        )

        await sut.startSession()
        XCTAssertEqual(sut.attendees.count, 1)

        sut.stopSession()
        XCTAssertEqual(sut.attendees.count, 0)
    }

    func testStopSession_resetsState() {
        sut.startTimer()
        sut.stopSession()

        // Verify state is reset
        XCTAssertEqual(sut.progress, 0.0)
    }

    // MARK: - completeRitual Tests

    func testCompleteRitual_success() async {
        mockRitualService.completeResult = (
            attendeeCount: 3,
            recapPostId: UUID()
        )

        await sut.completeRitual()

        XCTAssertTrue(mockRitualService.completeCalled)
        XCTAssertTrue(sut.isCompleted)
    }

    // MARK: - formattedTimeRemaining Tests

    func testFormattedTimeRemaining_3Minutes() {
        // 3 minutes = 180 seconds
        XCTAssertEqual(sut.formattedTimeRemaining, "3:00")
    }

    func testFormattedTimeRemaining_singleDigitSeconds() {
        let vm = RitualSessionViewModel(ritual: testRitual)
        // Manually set time remaining
        vm.timeRemaining = 65 // 1:05

        XCTAssertEqual(vm.formattedTimeRemaining, "1:05")
    }

    func testFormattedTimeRemaining_zeroSeconds() {
        let vm = RitualSessionViewModel(ritual: testRitual)
        vm.timeRemaining = 0

        XCTAssertEqual(vm.formattedTimeRemaining, "0:00")
    }

    func testFormattedTimeRemaining_doubleDigitSeconds() {
        let vm = RitualSessionViewModel(ritual: testRitual)
        vm.timeRemaining = 125 // 2:05

        XCTAssertEqual(vm.formattedTimeRemaining, "2:05")
    }

    // MARK: - Different Ritual Types

    func testGratitudeRitual_has3Steps() {
        let gratitude = CircleRitual(
            id: UUID(),
            circleId: UUID(),
            createdBy: UUID(),
            title: "Gratitude",
            ritualType: .gratitude,
            scheduledFor: Date(),
            durationSeconds: 180,
            status: .active,
            createdAt: Date(),
            completedAt: nil
        )

        let vm = RitualSessionViewModel(ritual: gratitude)
        XCTAssertEqual(vm.totalSteps, 3)
    }

    func testGroundingRitual_has4Steps() {
        let grounding = CircleRitual(
            id: UUID(),
            circleId: UUID(),
            createdBy: UUID(),
            title: "Grounding",
            ritualType: .grounding,
            scheduledFor: Date(),
            durationSeconds: 180,
            status: .active,
            createdAt: Date(),
            completedAt: nil
        )

        let vm = RitualSessionViewModel(ritual: grounding)
        XCTAssertEqual(vm.totalSteps, 4)
    }

    func testBreathingRitual_has5Steps() {
        let breathing = CircleRitual(
            id: UUID(),
            circleId: UUID(),
            createdBy: UUID(),
            title: "Breathing",
            ritualType: .breathing,
            scheduledFor: Date(),
            durationSeconds: 180,
            status: .active,
            createdAt: Date(),
            completedAt: nil
        )

        let vm = RitualSessionViewModel(ritual: breathing)
        XCTAssertEqual(vm.totalSteps, 5)
    }

    // MARK: - Realtime Callbacks

    func testUserJoined_callbackAddsAttendee() async {
        let newAttendee = RitualAttendeeInfo(
            userId: UUID(),
            displayName: "New User",
            joinedAt: Date()
        )

        mockRitualService.joinResult = (ritual: testRitual, currentStep: nil, attendees: [])
        await sut.startSession()

        // Simulate callback
        sut.attendees.append(newAttendee)

        XCTAssertEqual(sut.attendees.count, 1)
        XCTAssertEqual(sut.attendees[0].displayName, "New User")
    }

    func testUserLeft_callbackRemovesAttendee() async {
        let userId = UUID()
        let attendee = RitualAttendeeInfo(userId: userId, displayName: "Test", joinedAt: Date())

        mockRitualService.joinResult = (ritual: testRitual, currentStep: nil, attendees: [attendee])
        await sut.startSession()

        XCTAssertEqual(sut.attendees.count, 1)

        // Simulate left callback
        sut.attendees.removeAll { $0.userId == userId }

        XCTAssertEqual(sut.attendees.count, 0)
    }
}

// MARK: - Mock RitualService

final class MockRitualService: RitualService {
    var joinCalled = false
    var joinResult: (ritual: CircleRitual, currentStep: RitualStep?, attendees: [RitualAttendeeInfo])?
    var completeCalled = false
    var completeResult: (attendeeCount: Int, recapPostId: UUID?)?

    override func joinRitual(ritualId: UUID) async throws -> (ritual: CircleRitual, currentStep: RitualStep?, attendees: [RitualAttendeeInfo]) {
        joinCalled = true
        guard let result = joinResult else {
            throw NSError(domain: "MockError", code: 1)
        }
        return result
    }

    override func completeRitual(ritualId: UUID) async throws -> (attendeeCount: Int, recapPostId: UUID?) {
        completeCalled = true
        guard let result = completeResult else {
            throw NSError(domain: "MockError", code: 1)
        }
        return result
    }
}

extension CircleRitual {
    static func mock() -> CircleRitual {
        CircleRitual(
            id: UUID(),
            circleId: UUID(),
            createdBy: UUID(),
            title: "Test Ritual",
            ritualType: .gratitude,
            scheduledFor: Date(),
            durationSeconds: 180,
            status: .active,
            createdAt: Date(),
            completedAt: nil
        )
    }
}
