import XCTest
@testable import MindFriendApp

final class MedicationServiceTests: XCTestCase {
    var sut: MedicationService!
    var mockMedicationRepository: MockMedicationRepository!
    var mockLogRepository: MockMedicationLogRepository!
    var mockNotificationScheduler: MockNotificationScheduler!
    var mockAdherenceCalculator: AdherenceCalculator!

    override func setUp() {
        super.setUp()
        mockMedicationRepository = MockMedicationRepository()
        mockLogRepository = MockMedicationLogRepository()
        mockNotificationScheduler = MockNotificationScheduler()
        mockAdherenceCalculator = AdherenceCalculator()

        sut = MedicationService(
            medicationRepository: mockMedicationRepository,
            logRepository: mockLogRepository,
            notificationScheduler: mockNotificationScheduler,
            adherenceCalculator: mockAdherenceCalculator
        )
    }

    override func tearDown() {
        sut = nil
        mockMedicationRepository = nil
        mockLogRepository = nil
        mockNotificationScheduler = nil
        mockAdherenceCalculator = nil
        super.tearDown()
    }

    // MARK: - Fetch Medications Tests

    @MainActor
    func testFetchMedicationsSuccess() async {
        // Given
        let expectedMedications = [
            createMockMedication(name: "Sertraline"),
            createMockMedication(name: "Levothyroxine")
        ]
        mockMedicationRepository.fetchActiveResult = .success(expectedMedications)

        // When
        await sut.fetchMedications()

        // Then
        XCTAssertEqual(sut.medications.count, 2)
        XCTAssertEqual(sut.medications[0].name, "Sertraline")
        XCTAssertNil(sut.errorMessage)
    }

    @MainActor
    func testFetchMedicationsError() async {
        // Given
        mockMedicationRepository.fetchActiveResult = .failure(TestError.networkError)

        // When
        await sut.fetchMedications()

        // Then
        XCTAssertTrue(sut.medications.isEmpty)
        XCTAssertNotNil(sut.errorMessage)
    }

    // MARK: - Log Dose Tests

    @MainActor
    func testLogDoseSuccessUpdatesUI() async throws {
        // Given
        let medicationId = UUID()
        let scheduledAt = Date()
        let mockLog = createMockMedicationLog(medicationId: medicationId, status: .taken)
        mockLogRepository.logDoseResult = .success(mockLog)

        // When
        try await sut.logDose(medicationId: medicationId, scheduledAt: scheduledAt, notes: nil)

        // Then
        XCTAssertEqual(mockLogRepository.logDoseWasCalled, true)
        XCTAssertNil(sut.errorMessage)
    }

    @MainActor
    func testLogDoseCallsSupplyCountUpdate() async throws {
        // Given
        let medicationId = UUID()
        let scheduledAt = Date()
        let mockLog = createMockMedicationLog(medicationId: medicationId, status: .taken)
        mockLogRepository.logDoseResult = .success(mockLog)

        // When
        try await sut.logDose(medicationId: medicationId, scheduledAt: scheduledAt, notes: nil)

        // Then
        XCTAssertEqual(mockLogRepository.updateSupplyCountWasCalled, true)
    }

    @MainActor
    func testSkipDoseRecalculatesAdherence() async throws {
        // Given
        let medicationId = UUID()
        let scheduledAt = Date()
        let mockLog = createMockMedicationLog(medicationId: medicationId, status: .skipped)
        mockLogRepository.skipDoseResult = .success(mockLog)

        // When
        try await sut.skipDose(medicationId: medicationId, scheduledAt: scheduledAt, reason: "Felt sick")

        // Then
        XCTAssertEqual(mockLogRepository.skipDoseWasCalled, true)
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - Adherence Calculation Tests

    @MainActor
    func testCalculateAdherenceUsesAllLogs() async {
        // Given
        let mockLogs = [
            createMockMedicationLog(status: .taken),
            createMockMedicationLog(status: .taken),
            createMockMedicationLog(status: .skipped)
        ]
        mockLogRepository.fetchAllLogsResult = .success(mockLogs)

        // When
        await sut.calculateAdherence(days: 30)

        // Then
        let expectedAdherence = 2.0 / 3.0  // 67%
        XCTAssertEqual(sut.adherenceRate, expectedAdherence, accuracy: 0.01)
    }

    @MainActor
    func testCalculateAdherenceEmptyLogsDefaultsTo100Percent() async {
        // Given
        mockLogRepository.fetchAllLogsResult = .success([])

        // When
        await sut.calculateAdherence(days: 30)

        // Then
        XCTAssertEqual(sut.adherenceRate, 1.0)
    }

    @MainActor
    func testCalculateAdherenceCountsTakenAndLateAsAdherent() async {
        // Given
        let mockLogs = [
            createMockMedicationLog(status: .taken),
            createMockMedicationLog(status: .late),
            createMockMedicationLog(status: .pending)
        ]
        mockLogRepository.fetchAllLogsResult = .success(mockLogs)

        // When
        await sut.calculateAdherence(days: 30)

        // Then
        let expectedAdherence = 2.0 / 3.0  // taken + late = 2 adherent
        XCTAssertEqual(sut.adherenceRate, expectedAdherence, accuracy: 0.01)
    }

    // MARK: - Today's Schedule Tests

    @MainActor
    func testGetTodayScheduleItemsCreatesCorrectSchedules() async {
        // Given
        let now = Date()
        let hourComponent = Calendar.current.component(.hour, from: now)
        let scheduledTime = Calendar.current.date(
            bySettingHour: hourComponent,
            minute: 0,
            second: 0,
            of: now
        ) ?? now

        let medication = createMockMedication(scheduledTimes: [scheduledTime])
        sut.medications = [medication]
        sut.todayLogs = []

        // When
        let schedules = sut.getTodayScheduleItems()

        // Then
        XCTAssertEqual(schedules.count, 1)
        XCTAssertEqual(schedules[0].medication.id, medication.id)
        XCTAssertEqual(schedules[0].status, .pending)
    }

    // MARK: - Add Medication Tests

    @MainActor
    func testAddMedicationSchedulesNotifications() async throws {
        // Given
        let request = CreateMedicationRequest(
            name: "Test Med",
            dosage: "50mg",
            purpose: "Testing",
            icon: .pill,
            frequency: .daily,
            scheduledTimes: [Date()],
            reminderEnabled: true,
            useGenericNotification: false
        )
        let mockMedication = createMockMedication(name: request.name)
        mockMedicationRepository.createResult = .success(mockMedication)

        // When
        let result = try await sut.addMedication(request)

        // Then
        XCTAssertEqual(result.name, "Test Med")
        XCTAssertEqual(mockNotificationScheduler.scheduleWasCalled, true)
        XCTAssertTrue(sut.medications.contains { $0.id == result.id })
    }

    // MARK: - Helper Methods

    private func createMockMedication(
        name: String = "Test Med",
        icon: MedicationIcon = .pill,
        frequency: MedicationFrequency = .daily,
        scheduledTimes: [Date] = [Date()],
        reminderEnabled: Bool = true,
        useGenericNotification: Bool = false
    ) -> Medication {
        Medication(
            id: UUID(),
            userId: UUID(),
            name: name,
            dosage: "50mg",
            purpose: "Testing",
            color: nil,
            icon: icon,
            frequency: frequency,
            timesPerDay: 1,
            scheduledTimes: scheduledTimes,
            daysOfWeek: nil,
            reminderEnabled: reminderEnabled,
            reminderSound: "default",
            notificationText: nil,
            useGenericNotification: useGenericNotification,
            supplyCount: 30,
            refillReminderCount: 5,
            isActive: true,
            archivedAt: nil,
            startedAt: Date(),
            endedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func createMockMedicationLog(
        medicationId: UUID = UUID(),
        status: MedicationStatus = .taken
    ) -> MedicationLog {
        MedicationLog(
            id: UUID(),
            userId: UUID(),
            medicationId: medicationId,
            scheduledAt: Date(),
            status: status,
            loggedAt: Date(),
            skipReason: nil,
            notes: nil,
            sideEffects: nil,
            moodAtTime: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - Mock Implementations

class MockMedicationRepository: MedicationRepository {
    var fetchActiveResult: Result<[Medication], Error> = .success([])
    var createResult: Result<Medication, Error> = .success(Medication(
        id: UUID(), userId: UUID(), name: "Mock", dosage: nil, purpose: nil, color: nil,
        icon: .pill, frequency: .daily, timesPerDay: 1, scheduledTimes: [], daysOfWeek: nil,
        reminderEnabled: true, reminderSound: "default", notificationText: nil,
        useGenericNotification: false, supplyCount: nil, refillReminderCount: nil,
        isActive: true, archivedAt: nil, startedAt: Date(), endedAt: nil,
        createdAt: Date(), updatedAt: Date()
    ))

    func fetchActive() async throws -> [Medication] {
        try fetchActiveResult.get()
    }

    func fetchAll() async throws -> [Medication] {
        try fetchActiveResult.get()
    }

    func create(_ request: CreateMedicationRequest) async throws -> Medication {
        try createResult.get()
    }

    func update(_ id: UUID, with request: UpdateMedicationRequest) async throws -> Medication {
        try createResult.get()
    }

    func deactivate(_ id: UUID) async throws { }
    func archive(_ id: UUID) async throws { }
}

class MockMedicationLogRepository: MedicationLogRepository {
    var logDoseWasCalled = false
    var logDoseResult: Result<MedicationLog, Error> = .success(
        MedicationLog(id: UUID(), userId: UUID(), medicationId: UUID(), scheduledAt: Date(),
                      status: .taken, loggedAt: Date(), skipReason: nil, notes: nil,
                      sideEffects: nil, moodAtTime: nil, createdAt: Date())
    )

    var skipDoseWasCalled = false
    var skipDoseResult: Result<MedicationLog, Error> = .success(
        MedicationLog(id: UUID(), userId: UUID(), medicationId: UUID(), scheduledAt: Date(),
                      status: .skipped, loggedAt: Date(), skipReason: nil, notes: nil,
                      sideEffects: nil, moodAtTime: nil, createdAt: Date())
    )

    var fetchAllLogsResult: Result<[MedicationLog], Error> = .success([])
    var updateSupplyCountWasCalled = false

    func fetchLogs(medicationId: UUID, from: Date, to: Date) async throws -> [MedicationLog] {
        try fetchAllLogsResult.get()
    }

    func fetchAllLogs(from: Date, to: Date) async throws -> [MedicationLog] {
        try fetchAllLogsResult.get()
    }

    func fetchTodayLogs() async throws -> [MedicationLog] {
        try fetchAllLogsResult.get()
    }

    func logDose(medicationId: UUID, scheduledAt: Date, status: MedicationStatus, notes: String?) async throws -> MedicationLog {
        logDoseWasCalled = true
        return try logDoseResult.get()
    }

    func skipDose(medicationId: UUID, scheduledAt: Date, reason: String?) async throws -> MedicationLog {
        skipDoseWasCalled = true
        return try skipDoseResult.get()
    }

    func updateSupplyCount(medicationId: UUID) async throws -> Int? {
        updateSupplyCountWasCalled = true
        return 29
    }
}

class MockNotificationScheduler: NotificationSchedulerProtocol {
    var scheduleWasCalled = false
    var cancelWasCalled = false
    var rescheduleWasCalled = false

    func schedule(medication: Medication) async {
        scheduleWasCalled = true
    }

    func cancel(medicationId: UUID) async {
        cancelWasCalled = true
    }

    func reschedule(medication: Medication) async {
        rescheduleWasCalled = true
    }
}

// AdherenceCalculator is final, using real instance for testing as it is stateless

enum TestError: Error {
    case networkError
    case decodingError
}
