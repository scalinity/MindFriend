import XCTest
@testable import MindFriendApp

final class RitualModelsTests: XCTestCase {

    // MARK: - RitualPromptSequence.currentStep() Tests

    func testGratitudeCurrentStep_firstStep() {
        let sequence = RitualPromptSequence.gratitude

        let result = sequence.currentStep(elapsedSeconds: 0)

        XCTAssertEqual(result?.stepIndex, 0)
        XCTAssertEqual(result?.timeRemaining, 60)
        XCTAssertFalse(result?.completed ?? true)
    }

    func testGratitudeCurrentStep_midFirstStep() {
        let sequence = RitualPromptSequence.gratitude

        let result = sequence.currentStep(elapsedSeconds: 30)

        XCTAssertEqual(result?.stepIndex, 0)
        XCTAssertEqual(result?.timeRemaining, 30)
    }

    func testGratitudeCurrentStep_secondStep() {
        let sequence = RitualPromptSequence.gratitude

        let result = sequence.currentStep(elapsedSeconds: 60)

        XCTAssertEqual(result?.stepIndex, 1)
        XCTAssertEqual(result?.timeRemaining, 60)
    }

    func testGratitudeCurrentStep_lastStep() {
        let sequence = RitualPromptSequence.gratitude

        let result = sequence.currentStep(elapsedSeconds: 150)

        XCTAssertEqual(result?.stepIndex, 2)
        XCTAssertEqual(result?.timeRemaining, 30)
    }

    func testGratitudeCurrentStep_completed() {
        let sequence = RitualPromptSequence.gratitude

        let result = sequence.currentStep(elapsedSeconds: 180)

        XCTAssertEqual(result?.completed, true)
        XCTAssertEqual(result?.timeRemaining, 0)
    }

    func testGratitudeCurrentStep_afterCompletion() {
        let sequence = RitualPromptSequence.gratitude

        let result = sequence.currentStep(elapsedSeconds: 200)

        XCTAssertEqual(result?.completed, true)
    }

    func testGroundingCurrentStep_fourSteps() {
        let sequence = RitualPromptSequence.grounding

        XCTAssertEqual(sequence.steps.count, 4)

        // Step 1: 0-45s
        XCTAssertEqual(sequence.currentStep(elapsedSeconds: 0)?.stepIndex, 0)
        XCTAssertEqual(sequence.currentStep(elapsedSeconds: 44)?.stepIndex, 0)

        // Step 2: 45-90s
        XCTAssertEqual(sequence.currentStep(elapsedSeconds: 45)?.stepIndex, 1)
        XCTAssertEqual(sequence.currentStep(elapsedSeconds: 89)?.stepIndex, 1)

        // Step 3: 90-135s
        XCTAssertEqual(sequence.currentStep(elapsedSeconds: 90)?.stepIndex, 2)
        XCTAssertEqual(sequence.currentStep(elapsedSeconds: 134)?.stepIndex, 2)

        // Step 4: 135-180s
        XCTAssertEqual(sequence.currentStep(elapsedSeconds: 135)?.stepIndex, 3)
    }

    func testBreathingCurrentStep_fiveCycles() {
        let sequence = RitualPromptSequence.breathing

        XCTAssertEqual(sequence.steps.count, 5)

        // Each step is 36 seconds
        XCTAssertEqual(sequence.steps[0].duration, 36)
        XCTAssertEqual(sequence.steps[4].duration, 36)

        // Step 5 starts at 144s (4 * 36)
        XCTAssertEqual(sequence.currentStep(elapsedSeconds: 144)?.stepIndex, 4)
    }

    func testWinsCurrentStep() {
        let sequence = RitualPromptSequence.wins

        XCTAssertEqual(sequence.steps.count, 3)
        XCTAssertEqual(sequence.totalDuration, 180)

        let result = sequence.currentStep(elapsedSeconds: 0)
        XCTAssertEqual(result?.stepIndex, 0)
    }

    func testRitualPromptSequence_forType() {
        XCTAssertEqual(RitualPromptSequence.forType(.gratitude).type, .gratitude)
        XCTAssertEqual(RitualPromptSequence.forType(.grounding).type, .grounding)
        XCTAssertEqual(RitualPromptSequence.forType(.wins).type, .wins)
        XCTAssertEqual(RitualPromptSequence.forType(.breathing).type, .breathing)
    }

    func testAllRitualsHave180SecondDuration() {
        XCTAssertEqual(RitualPromptSequence.gratitude.totalDuration, 180)
        XCTAssertEqual(RitualPromptSequence.grounding.totalDuration, 180)
        XCTAssertEqual(RitualPromptSequence.wins.totalDuration, 180)
        XCTAssertEqual(RitualPromptSequence.breathing.totalDuration, 180)
    }

    func testStepDurationsSumToTotal() {
        func checkSum(_ sequence: RitualPromptSequence) {
            let sum = sequence.steps.reduce(0) { $0 + $1.duration }
            XCTAssertEqual(sum, sequence.totalDuration)
        }

        checkSum(.gratitude)
        checkSum(.grounding)
        checkSum(.wins)
        checkSum(.breathing)
    }

    // MARK: - CircleRitual Computed Properties Tests

    func testIsJoinable_scheduledWithinGracePeriod() {
        let ritual = createRitual(
            status: .scheduled,
            scheduledFor: Date().addingTimeInterval(-60) // 1 min ago
        )

        XCTAssertTrue(ritual.isJoinable)
    }

    func testIsJoinable_scheduledAfterGracePeriod() {
        let ritual = createRitual(
            status: .scheduled,
            scheduledFor: Date().addingTimeInterval(-180) // 3 mins ago
        )

        XCTAssertFalse(ritual.isJoinable)
    }

    func testIsJoinable_activeWithinGracePeriod() {
        let ritual = createRitual(
            status: .active,
            scheduledFor: Date().addingTimeInterval(-90) // 1.5 mins ago
        )

        XCTAssertTrue(ritual.isJoinable)
    }

    func testIsJoinable_activeAfterGracePeriod() {
        let ritual = createRitual(
            status: .active,
            scheduledFor: Date().addingTimeInterval(-150) // 2.5 mins ago
        )

        XCTAssertFalse(ritual.isJoinable)
    }

    func testIsJoinable_completedRitual() {
        let ritual = createRitual(status: .completed)

        XCTAssertFalse(ritual.isJoinable)
    }

    func testIsJoinable_cancelledRitual() {
        let ritual = createRitual(status: .cancelled)

        XCTAssertFalse(ritual.isJoinable)
    }

    func testHasStarted_futureRitual() {
        let ritual = createRitual(scheduledFor: Date().addingTimeInterval(60))

        XCTAssertFalse(ritual.hasStarted)
    }

    func testHasStarted_pastRitual() {
        let ritual = createRitual(scheduledFor: Date().addingTimeInterval(-60))

        XCTAssertTrue(ritual.hasStarted)
    }

    func testHasElapsed_withinDuration() {
        let ritual = createRitual(
            scheduledFor: Date().addingTimeInterval(-60),
            durationSeconds: 180
        )

        XCTAssertFalse(ritual.hasElapsed)
    }

    func testHasElapsed_exceededDuration() {
        let ritual = createRitual(
            scheduledFor: Date().addingTimeInterval(-200),
            durationSeconds: 180
        )

        XCTAssertTrue(ritual.hasElapsed)
    }

    func testFormattedTimeUntilStart_now() {
        let ritual = createRitual(scheduledFor: Date())

        XCTAssertEqual(ritual.formattedTimeUntilStart, "Starting now")
    }

    func testFormattedTimeUntilStart_seconds() {
        let ritual = createRitual(scheduledFor: Date().addingTimeInterval(30))

        XCTAssertEqual(ritual.formattedTimeUntilStart, "Starting in 30s")
    }

    func testFormattedTimeUntilStart_minutes() {
        let ritual = createRitual(scheduledFor: Date().addingTimeInterval(300))

        XCTAssertEqual(ritual.formattedTimeUntilStart, "Starting in 5m")
    }

    func testFormattedTimeUntilStart_hours() {
        let ritual = createRitual(scheduledFor: Date().addingTimeInterval(7200))

        XCTAssertEqual(ritual.formattedTimeUntilStart, "Starting in 2h")
    }

    func testFormattedTimeUntilStart_past() {
        let ritual = createRitual(scheduledFor: Date().addingTimeInterval(-30))

        XCTAssertEqual(ritual.formattedTimeUntilStart, "Starting now")
    }

    // MARK: - RitualType Tests

    func testRitualType_displayName() {
        XCTAssertEqual(RitualType.gratitude.displayName, "Gratitude")
        XCTAssertEqual(RitualType.grounding.displayName, "Grounding")
        XCTAssertEqual(RitualType.wins.displayName, "Wins")
        XCTAssertEqual(RitualType.breathing.displayName, "Breathing")
    }

    func testRitualType_icon() {
        XCTAssertEqual(RitualType.gratitude.icon, "heart.fill")
        XCTAssertEqual(RitualType.grounding.icon, "leaf.fill")
        XCTAssertEqual(RitualType.wins.icon, "star.fill")
        XCTAssertEqual(RitualType.breathing.icon, "wind")
    }

    func testRitualType_description() {
        XCTAssertFalse(RitualType.gratitude.description.isEmpty)
        XCTAssertFalse(RitualType.grounding.description.isEmpty)
        XCTAssertFalse(RitualType.wins.description.isEmpty)
        XCTAssertFalse(RitualType.breathing.description.isEmpty)
    }

    // MARK: - Helper

    private func createRitual(
        status: RitualStatus = .scheduled,
        scheduledFor: Date = Date(),
        durationSeconds: Int = 180
    ) -> CircleRitual {
        CircleRitual(
            id: UUID(),
            circleId: UUID(),
            createdBy: UUID(),
            title: "Test Ritual",
            ritualType: .gratitude,
            scheduledFor: scheduledFor,
            durationSeconds: durationSeconds,
            status: status,
            createdAt: Date(),
            completedAt: nil
        )
    }
}
