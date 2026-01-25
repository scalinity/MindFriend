//
//  ServiceProtocols.swift
//  MindFriendApp
//
//  Protocol abstractions for dependency injection and testability
//

import Foundation

// MARK: - Pathway Encryption Protocol

protocol PathwayEncryptionServiceProtocol {
    func encryptString(_ text: String?) throws -> String?
    func decryptString(_ base64Encrypted: String?) throws -> String?
    func encryptJSON<T: Codable>(_ value: T?) throws -> String?
    func decryptJSON<T: Codable>(_ base64Encrypted: String?, as type: T.Type) throws -> T?
}

// MARK: - Pathway Cache Protocol

protocol PathwayCacheServiceProtocol {
    func cacheDailyContent(_ content: DailyPathwayContent, for pathwayId: UUID) throws
    func getCachedDailyContent(for pathwayId: UUID) throws -> DailyPathwayContent?
    func clearDailyContentCache(for pathwayId: UUID)

    func saveCheckInDraft(_ draft: PathwayCacheService.CheckInDraft) throws
    func getCheckInDraft(for pathwayId: UUID) throws -> PathwayCacheService.CheckInDraft?
    func clearCheckInDraft(for pathwayId: UUID)

    func saveJournalDraft(_ text: String, for pathwayId: UUID) throws
    func getJournalDraft(for pathwayId: UUID) throws -> String?
    func clearJournalDraft(for pathwayId: UUID)

    func queuePendingCheckIn(_ checkIn: PathwayCacheService.PendingCheckIn)
    func getPendingCheckIns() -> [PathwayCacheService.PendingCheckIn]
    func removePendingCheckIn(_ id: UUID)
    func updateRetryCount(for id: UUID)

    func clearAllCaches()
}

// MARK: - Transition Service Protocol

protocol TransitionServiceProtocol {
    func fetchAvailablePathways(category: PathwayCategory?) async throws -> [TransitionPathway]
    func enrollPathway(key: String, personalization: PathwayPersonalization) async throws -> EnrollPathwayResponse
    func fetchActivePathways() async throws -> [UserPathway]
    func getDailyContent(userPathwayId: UUID) async throws -> DailyPathwayContent
    func completeCheckIn(userPathwayId: UUID, checkInData: CheckInData, exercisesCompleted: [String], journalEntry: String?) async throws -> CheckInResponse
    func fetchPhaseDetails(pathwayId: UUID, phaseNumber: Int) async throws -> PathwayPhase?
    func fetchPhaseMilestones(userPathwayId: UUID, phaseNumber: Int) async throws -> [PathwayMilestone]
    func advancePhase(userPathwayId: UUID) async throws -> AdvancePhaseResponse
    func pausePathway(userPathwayId: UUID, reason: String?) async throws
    func resumePathway(userPathwayId: UUID) async throws
    func abandonPathway(userPathwayId: UUID, feedback: String?) async throws
    func processPendingCheckIns() async

    // Journal draft management (delegates to cache service)
    func getJournalDraft(for pathwayId: UUID) throws -> String?
    func saveJournalDraft(_ text: String, for pathwayId: UUID) throws
    func clearJournalDraft(for pathwayId: UUID)
}
