import Foundation
import Supabase

/// Service for mentorship lifecycle management
/// Single Responsibility: Starting, ending, and tracking active mentorships
@MainActor
final class MentorshipLifecycleService: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isLoading = false
    @Published var error: String?

    // MARK: - Dependencies

    private let dataService: MentorshipDataService
    private let matchingService: MentorshipMatchingService

    // MARK: - Initialization

    init(dataService: MentorshipDataService, matchingService: MentorshipMatchingService) {
        self.dataService = dataService
        self.matchingService = matchingService
    }

    // MARK: - End Mentorship

    /// End a mentorship relationship
    func endMentorship(_ matchId: UUID, reason: String = "completed") async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await dataService.endMentorship(matchId: matchId, reason: reason)
            // Refresh matches to reflect the change
            await matchingService.loadMatches()
            error = nil
        } catch {
            self.error = "Unable to end mentorship. Please try again."
            throw error
        }
    }

    // MARK: - Active Mentorships

    /// Get all currently active mentorships
    var activeMatches: [MentorshipMatch] {
        matchingService.userMatches.filter { $0.status == .active }
    }

    /// Get matches where user is mentor
    func matchesAsMentor(userId: UUID) -> [MentorshipMatch] {
        matchingService.userMatches.filter { $0.mentorId == userId }
    }

    /// Get matches where user is mentee
    func matchesAsMentee(userId: UUID) -> [MentorshipMatch] {
        matchingService.userMatches.filter { $0.menteeId == userId }
    }

    // MARK: - Match Duration

    /// Calculate duration of a mentorship in days
    func mentorshipDuration(_ match: MentorshipMatch) -> Int? {
        guard let startedAt = match.createdAt else { return nil }
        let endDate = match.endedAt ?? Date()
        return Calendar.current.dateComponents([.day], from: startedAt, to: endDate).day
    }

    /// Calculate duration in weeks
    func mentorshipDurationWeeks(_ match: MentorshipMatch) -> Int? {
        guard let days = mentorshipDuration(match) else { return nil }
        return days / 7
    }

    // MARK: - Match Statistics

    /// Count of active mentorships
    var activeMentorshipCount: Int {
        activeMatches.count
    }

    /// Count of completed mentorships
    var completedMentorshipCount: Int {
        matchingService.userMatches.filter { $0.status == .completed }.count
    }

    /// Total mentorship count (all statuses)
    var totalMentorshipCount: Int {
        matchingService.userMatches.count
    }

    // MARK: - State Reset

    /// Clear lifecycle service state
    func reset() {
        error = nil
        isLoading = false
    }
}
