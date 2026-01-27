import Foundation
import Supabase

/// Errors specific to mentorship operations
enum MentorshipError: Error {
    case validationError(String)
    case notFound(String)
    case networkError(String)
    case encryptionError(String)
    case unauthorized
    case notAuthenticated
}

// MARK: - Facade Service

/// Facade service for mentorship features - delegates to focused sub-services
/// Maintains backward-compatible API while internally using Single Responsibility services
///
/// Architecture:
/// - MentorshipDataService: Core database operations
/// - MentorshipProfileService: Profile CRUD
/// - MentorshipMatchingService: Finding and managing matches
/// - MentorshipMessagingService: Messages with incremental polling
/// - MentorshipSafetyService: Reporting and flagging
/// - MentorshipEncryptionService: Key management
/// - MentorshipLifecycleService: Start/end mentorship tracking
@MainActor
final class MentorshipService: ObservableObject {

    // MARK: - Published Properties (Facade)

    /// Current user's profile (proxied from profileService)
    @Published private(set) var profile: MentorshipProfile?

    /// User's mentorship matches (proxied from matchingService)
    @Published private(set) var matches: [MentorshipMatch] = []

    /// Current conversation messages (proxied from messagingService)
    @Published var currentMessages: [MentorshipMessage] = []

    /// Loading state
    @Published var isLoading = false

    /// Last error message
    @Published var error: String?

    // MARK: - Sub-Services (Exposed for View Layer)

    private let dataService: MentorshipDataService
    let profileService: MentorshipProfileService
    let matchingService: MentorshipMatchingService
    let messagingService: MentorshipMessagingService
    let safetyService: MentorshipSafetyService
    let encryptionService: MentorshipEncryptionService
    private let lifecycleService: MentorshipLifecycleService

    // MARK: - Observation

    private var observationTask: Task<Void, Never>?
    private var matchesObservationTask: Task<Void, Never>?  // ✅ ADDED: Store matches observation
    private var messagesObservationTask: Task<Void, Never>?  // ✅ ADDED: Store messages observation

    // MARK: - Initialization

    init(supabase: SupabaseClient, userId: UUID) {
        // Build dependency graph with authenticated user ID
        let data = MentorshipDataService(supabase: supabase, userId: userId)
        let encryption = MentorshipEncryptionService(dataService: data)
        let profile = MentorshipProfileService(dataService: data)
        let matching = MentorshipMatchingService(dataService: data)
        let messaging = MentorshipMessagingService(dataService: data, encryptionService: encryption)
        let safety = MentorshipSafetyService(dataService: data)
        let lifecycle = MentorshipLifecycleService(dataService: data, matchingService: matching)

        self.dataService = data
        self.encryptionService = encryption
        self.profileService = profile
        self.matchingService = matching
        self.messagingService = messaging
        self.safetyService = safety
        self.lifecycleService = lifecycle

        // Observe sub-service state changes
        setupObservation()
    }

    private func setupObservation() {
        observationTask = Task { [weak self] in
            guard let self = self else { return }

            // Sync profile changes
            for await profile in self.profileService.$profile.values {
                self.profile = profile
            }
        }

        // Additional observation tasks for other services
        matchesObservationTask = Task { [weak self] in  // ✅ CHANGED: Store task
            guard let self = self else { return }
            for await matches in self.matchingService.$matches.values {
                self.matches = matches
            }
        }

        messagesObservationTask = Task { [weak self] in  // ✅ CHANGED: Store task
            guard let self = self else { return }
            for await messages in self.messagingService.$messages.values {
                self.currentMessages = messages
            }
        }
    }

    // MARK: - Cleanup

    func cleanup() async {
        observationTask?.cancel()
        matchesObservationTask?.cancel()  // ✅ ADDED: Cancel matches observation
        messagesObservationTask?.cancel()  // ✅ ADDED: Cancel messages observation
        await messagingService.cleanup()
        profileService.reset()
        matchingService.reset()
        safetyService.reset()
        lifecycleService.reset()
        currentMessages = []
        error = nil
    }

    // MARK: - Profile Operations (Delegated)

    func fetchProfile() async throws -> MentorshipProfile? {
        await profileService.loadProfile()
        return profileService.profile
    }

    func upsertProfile(
        isMentorAvailable: Bool? = nil,
        expertiseAreas: [String]? = nil,
        seekingAreas: [String]? = nil,
        bio: String? = nil,
        availabilityHoursWeek: Int? = nil,
        languages: [String]? = nil
    ) async throws {
        await profileService.updateProfile(
            isMentorAvailable: isMentorAvailable,
            expertiseAreas: expertiseAreas,
            seekingAreas: seekingAreas,
            bio: bio,
            availabilityHoursWeek: availabilityHoursWeek,
            languages: languages
        )
        if let error = profileService.error {
            throw error
        }
    }

    func toggleMentorAvailability(_ isAvailable: Bool) async throws {
        await profileService.toggleMentorAvailability(isAvailable)
        if let error = profileService.error {
            throw error
        }
    }

    // MARK: - Matching Operations (Delegated)

    func findMentorMatches(limit: Int = 5) async throws -> [FindMentorMatchesResponse.MentorMatch] {
        isLoading = true
        defer { isLoading = false }
        await matchingService.findMentors(limit: limit)
        if let error = matchingService.error {
            throw error
        }
        return matchingService.mentorMatches
    }

    func requestMentorship(mentorId: UUID, introductionMessage: String) async throws -> RequestMentorshipResponse {
        isLoading = true
        defer { isLoading = false }
        return try await dataService.requestMentorship(
            mentorId: mentorId,
            introductionMessage: introductionMessage
        )
    }

    func fetchMatches() async throws -> [MentorshipMatch] {
        await matchingService.loadMatches()
        if let error = matchingService.error {
            throw error
        }
        return matchingService.userMatches
    }

    func acceptMatch(_ matchId: UUID) async throws {
        await matchingService.acceptRequest(matchId)
        if let error = matchingService.error {
            throw error
        }
    }

    func declineMatch(_ matchId: UUID) async throws {
        await matchingService.rejectRequest(matchId)
        if let error = matchingService.error {
            throw error
        }
    }

    // MARK: - Messaging Operations (Delegated)

    func fetchMessages(matchId: UUID) async throws -> [MentorshipMessage] {
        await messagingService.loadMessages(matchId: matchId)
        if let error = messagingService.error {
            throw error
        }
        return messagingService.messages
    }

    func subscribeToMessages(matchId: UUID) {
        messagingService.startAutoUpdate(matchId: matchId)
    }

    func sendMessage(matchId: UUID, content: String) async throws {
        try await messagingService.sendMessage(matchId: matchId, content: content)
    }

    func deleteMessage(messageId: UUID) async throws {
        isLoading = true
        defer { isLoading = false }
        try await messagingService.deleteMessage(messageId: messageId)
    }

    func markMessagesAsRead(matchId: UUID) async throws {
        await messagingService.markAsRead(matchId: matchId)
        if let error = messagingService.error {
            throw error
        }
    }

    // MARK: - Safety Operations (Delegated)

    func reportIssue(matchId: UUID, reportedUserId: UUID, reason: String, description: String?) async throws {
        try await safetyService.reportIssue(
            matchId: matchId,
            reportedUserId: reportedUserId,
            reason: reason,
            description: description
        )
    }

    // MARK: - Lifecycle Operations (Delegated)

    func endMentorship(_ matchId: UUID, reason: String = "completed") async throws {
        try await lifecycleService.endMentorship(matchId, reason: reason)
    }
}

// MARK: - Date Extension

extension Date {
    /// Initialize Date from ISO8601 string
    init?(fromISO8601String string: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: string) {
            self = date
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: string) else { return nil }
            self = date
        }
    }
}
