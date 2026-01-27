import Foundation
import Combine

/// Manages mentor matching and mentorship requests
@MainActor
final class MentorshipMatchingService: ObservableObject {
    @Published var mentorMatches: [FindMentorMatchesResponse.MentorMatch] = []
    @Published var matches: [MentorshipMatch] = []  // Alias for facade compatibility
    @Published var userMatches: [MentorshipMatch] = []
    @Published var pendingRequests: [MentorshipMatch] = []
    @Published var activeMatches: [MentorshipMatch] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let dataService: MentorshipDataService

    nonisolated init(dataService: MentorshipDataService) {
        self.dataService = dataService
    }

    // MARK: - Reset

    func reset() {
        mentorMatches = []
        matches = []
        userMatches = []
        pendingRequests = []
        activeMatches = []
        isLoading = false
        error = nil
    }

    // MARK: - Finding Mentors

    /// Search for mentor matches
    func findMentors(limit: Int = 5, offset: Int = 0) async {
        isLoading = true
        error = nil

        do {
            let response = try await dataService.findMentorMatches(limit: limit, offset: offset)
            mentorMatches = response.matches
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Load more mentor matches (pagination)
    func loadMoreMentors(limit: Int = 5, offset: Int) async {
        isLoading = true
        error = nil

        do {
            let response = try await dataService.findMentorMatches(limit: limit, offset: offset)
            mentorMatches.append(contentsOf: response.matches)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Requesting Mentorship

    /// Request mentorship from a mentor
    func requestMentorship(
        mentorId: UUID,
        introductionMessage: String
    ) async {
        isLoading = true
        error = nil

        do {
            let response = try await dataService.requestMentorship(
                mentorId: mentorId,
                introductionMessage: introductionMessage
            )

            if response.success, let matchId = response.matchId {
                // Add to pending requests
                let match = MentorshipMatch(
                    id: matchId,
                    mentorId: mentorId,
                    menteeId: UUID(),
                    status: .pending,
                    introductionMessage: introductionMessage
                )
                pendingRequests.append(match)
            }
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Loading Matches

    /// Load all user's mentorship matches
    func loadMatches() async {
        isLoading = true
        error = nil

        do {
            let matches = try await dataService.fetchMatches(role: .both)
            userMatches = matches

            // Separate by status
            pendingRequests = matches.filter { $0.status == .pending }
            activeMatches = matches.filter { $0.status == .active }
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Load pending mentorship requests (as mentor)
    func loadPendingRequests() async {
        isLoading = true
        error = nil

        do {
            let matches = try await dataService.fetchMatches(role: .mentor)
            pendingRequests = matches.filter { $0.status == .pending }
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Load active mentorship relationships
    func loadActiveMatches() async {
        isLoading = true
        error = nil

        do {
            let matches = try await dataService.fetchMatches(role: .both)
            activeMatches = matches.filter { $0.status == .active }
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Managing Matches

    /// Accept pending mentorship request (as mentor)
    func acceptRequest(_ matchId: UUID) async {
        isLoading = true
        error = nil

        do {
            let updated = try await dataService.acceptMentorshipRequest(matchId: matchId)
            
            // Move from pending to active
            if let index = pendingRequests.firstIndex(where: { $0.id == matchId }) {
                pendingRequests.remove(at: index)
            }
            activeMatches.append(updated)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Reject pending mentorship request (as mentor)
    func rejectRequest(_ matchId: UUID) async {
        isLoading = true
        error = nil

        do {
            _ = try await dataService.rejectMentorshipRequest(matchId: matchId)
            
            // Remove from pending
            if let index = pendingRequests.firstIndex(where: { $0.id == matchId }) {
                pendingRequests.remove(at: index)
            }
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// End mentorship relationship
    func endMatch(_ matchId: UUID, reason: String? = nil) async {
        isLoading = true
        error = nil

        do {
            _ = try await dataService.endMentorship(matchId: matchId, reason: reason)
            
            // Remove from active matches
            if let index = activeMatches.firstIndex(where: { $0.id == matchId }) {
                activeMatches.remove(at: index)
            }
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Computed Properties

    var hasPendingRequests: Bool {
        !pendingRequests.isEmpty
    }

    var hasActiveMatches: Bool {
        !activeMatches.isEmpty
    }

    var totalMatches: Int {
        userMatches.count
    }

    var mentorMatchCount: Int {
        mentorMatches.count
    }

    /// Get best matching mentor (highest compatibility score)
    var bestMatch: FindMentorMatchesResponse.MentorMatch? {
        mentorMatches.max { $0.compatibilityScore < $1.compatibilityScore }
    }

    /// Get average compatibility score
    var averageCompatibilityScore: Double {
        guard !mentorMatches.isEmpty else { return 0 }
        let total = mentorMatches.reduce(0) { $0 + $1.compatibilityScore }
        return total / Double(mentorMatches.count)
    }

    // MARK: - Filtering

    /// Filter matches by status
    func matchesByStatus(_ status: MentorshipStatus) -> [MentorshipMatch] {
        userMatches.filter { $0.status == status }
    }

    /// Filter mentor matches by expertise area
    func mentorsByExpertise(_ expertise: String) -> [FindMentorMatchesResponse.MentorMatch] {
        mentorMatches.filter { $0.expertiseAreas.contains(expertise) }
    }

    /// Filter mentor matches by language
    func mentorsByLanguage(_ language: String) -> [FindMentorMatchesResponse.MentorMatch] {
        mentorMatches.filter { $0.languages.contains(language) }
    }

    /// Filter mentor matches by minimum compatibility score
    func mentorsByMinimumScore(_ minimumScore: Double) -> [FindMentorMatchesResponse.MentorMatch] {
        mentorMatches.filter { $0.compatibilityScore >= minimumScore }
    }

    /// Filter mentor matches by availability
    func mentorsByAvailability(minimumHours: Int) -> [FindMentorMatchesResponse.MentorMatch] {
        mentorMatches.filter { $0.availabilityHoursWeek >= minimumHours }
    }

    /// Sort matches by compatibility score (highest first)
    func sortedByCompatibility() -> [FindMentorMatchesResponse.MentorMatch] {
        mentorMatches.sorted { $0.compatibilityScore > $1.compatibilityScore }
    }
}
