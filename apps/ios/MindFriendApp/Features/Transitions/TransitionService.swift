import Foundation
import Supabase

@MainActor
final class TransitionService: TransitionServiceProtocol {
    private let supabase: SupabaseClient
    private let networkRetry: NetworkRetryService
    private let cacheService: PathwayCacheService  // ✅ Made private - use delegation methods instead
    private let encryptionService: PathwayEncryptionService

    init(
        supabase: SupabaseClient,
        networkRetry: NetworkRetryService = NetworkRetryService(),
        cacheService: PathwayCacheService = PathwayCacheService(),
        encryptionService: PathwayEncryptionService = PathwayEncryptionService()
    ) {
        self.supabase = supabase
        self.networkRetry = networkRetry
        self.cacheService = cacheService
        self.encryptionService = encryptionService
    }

    // MARK: - Browse Pathways

    /// Fetch all available transition pathways (calls database directly since it's public data)
    func fetchAvailablePathways(category: PathwayCategory? = nil) async throws -> [TransitionPathway] {
        // For MVP, return all pathways - filtering can be done client-side
        let pathways: [TransitionPathway] = try await supabase
            .from("transition_pathways")
            .select()
            .execute()
            .value

        if let category = category {
            return pathways.filter { $0.category == category }
        }
        return pathways
    }

    // MARK: - Enrollment

    /// Enroll user in a pathway with personalization
    func enrollPathway(key: String, personalization: PathwayPersonalization) async throws -> EnrollPathwayResponse {
        struct EnrollRequest: Codable {
            let pathwayKey: String
            let personalization: PersonalizationData
        }

        struct PersonalizationData: Codable {
            let transitionDate: String?
            let specificContext: String?
            let supportPeople: [String]?
            let goals: [String]?
        }

        let request = EnrollRequest(
            pathwayKey: key,
            personalization: PersonalizationData(
                transitionDate: personalization.transitionDate?.ISO8601Format(),
                specificContext: personalization.specificContext,
                supportPeople: personalization.supportPeople,
                goals: personalization.goals
            )
        )

        let response: EnrollPathwayResponse = try await supabase.functions.invoke(
            "enroll-pathway",
            options: FunctionInvokeOptions(body: request)
        )

        return response
    }

    // MARK: - Active Pathways

    /// Fetch user's active pathways
    func fetchActivePathways() async throws -> [UserPathway] {
        let pathways: [UserPathway] = try await supabase
            .from("user_pathways")
            .select("*, pathway:transition_pathways(*)")
            .execute()
            .value

        return pathways.filter { $0.status == .active }
    }

    // MARK: - Daily Content

    /// Get today's pathway content
    func getDailyContent(userPathwayId: UUID) async throws -> DailyPathwayContent {
        // Check cache first (now throws)
        if let cached = try? cacheService.getCachedDailyContent(for: userPathwayId) {
            return cached
        }
        
        // Fetch with retry
        struct ContentRequest: Codable {
            let userPathwayId: String
        }

        let request = ContentRequest(userPathwayId: userPathwayId.uuidString)

        let content: DailyPathwayContent = try await networkRetry.execute(
            {
                try await self.supabase.functions.invoke(
                    "get-pathway-content",
                    options: FunctionInvokeOptions(body: request)
                )
            },
            shouldRetry: NetworkRetryService.isRetryableError
        )
        
        // Cache the result (now throws - log but don't fail the request)
        Task.detached(priority: .utility) { [weak self] in
            do {
                try self?.cacheService.cacheDailyContent(content, for: userPathwayId)
            } catch {
                // ✅ SECURITY FIX: Don't log error details (may contain PHI)
                print("⚠️ Failed to cache daily content for pathway \(userPathwayId.uuidString)")
            }
        }

        return content
    }

    /// Submit daily check-in
    func completeCheckIn(
        userPathwayId: UUID,
        checkInData: CheckInData,
        exercisesCompleted: [String] = [],
        journalEntry: String? = nil
    ) async throws -> CheckInResponse {
        // Save draft (optimistic)
        let draft = PathwayCacheService.CheckInDraft(
            id: UUID(),
            userPathwayId: userPathwayId,
            checkInData: checkInData,
            exercisesCompleted: exercisesCompleted,
            journalEntry: journalEntry,
            timestamp: Date(),
            retryCount: 0
        )

        do {
            try cacheService.saveCheckInDraft(draft)
        } catch {
            // ✅ SECURITY FIX: Don't log error details (may contain PHI)
            print("⚠️ Failed to save check-in draft for pathway \(userPathwayId.uuidString)")
        }
        
        // ✅ PERFORMANCE FIX: Offload encryption to background thread (prevents 100-350ms UI freeze)
        let (encryptedNotes, encryptedJournalEntry) = try await Task.detached(priority: .userInitiated) { [encryptionService] in
            let notes = try encryptionService.encryptString(checkInData.notes)
            let journal = try encryptionService.encryptString(journalEntry)
            return (notes, journal)
        }.value

        struct EncryptedCheckInData: Codable {
            let mood: Int
            let energy: Int
            let encryptedNotes: String?  // ✅ ADDED: Encrypted notes
            let responses: [String: String]?
        }
        
        struct CheckInRequest: Codable {
            let userPathwayId: String
            let checkInData: EncryptedCheckInData
            let exercisesCompleted: [String]
            let encryptedJournalEntry: String?  // ✅ ADDED: Encrypted journal entry
        }

        let request = CheckInRequest(
            userPathwayId: userPathwayId.uuidString,
            checkInData: EncryptedCheckInData(
                mood: checkInData.mood,
                energy: checkInData.energy,
                encryptedNotes: encryptedNotes,
                responses: checkInData.responses
            ),
            exercisesCompleted: exercisesCompleted,
            encryptedJournalEntry: encryptedJournalEntry
        )

        do {
            let response: CheckInResponse = try await networkRetry.execute(
                {
                    try await self.supabase.functions.invoke(
                        "submit-pathway-checkin",
                        options: FunctionInvokeOptions(body: request)
                    )
                },
                shouldRetry: NetworkRetryService.isRetryableError
            )
            
            // Clear draft on success
            cacheService.clearCheckInDraft(for: userPathwayId)
            
            return response
        } catch {
            // Queue for retry if network error
            if NetworkRetryService.isRetryableError(error) {
                let pending = PathwayCacheService.PendingCheckIn(
                    userPathwayId: userPathwayId,
                    checkInData: checkInData,
                    exercisesCompleted: exercisesCompleted,
                    journalEntry: journalEntry
                )
                cacheService.queuePendingCheckIn(pending)
            }
            throw error
        }
    }
    
    // MARK: - Background Sync

    /// Process pending check-ins (call on app launch or network recovery)
    func processPendingCheckIns() async {
        // ✅ FIX: Create immutable snapshot to avoid concurrent modification during iteration
        let pendingSnapshot = cacheService.getPendingCheckIns()

        for checkIn in pendingSnapshot {
            // Skip if too many retries
            guard checkIn.retryCount < 5 else {
                cacheService.removePendingCheckIn(checkIn.id)
                continue
            }

            do {
                _ = try await completeCheckIn(
                    userPathwayId: checkIn.userPathwayId,
                    checkInData: checkIn.checkInData,
                    exercisesCompleted: checkIn.exercisesCompleted,
                    journalEntry: checkIn.journalEntry
                )

                // Success - remove from queue
                cacheService.removePendingCheckIn(checkIn.id)
            } catch {
                // Update retry count
                cacheService.updateRetryCount(for: checkIn.id)
            }
        }
    }

    // MARK: - Phase Progression

    /// Fetch phase details for a specific phase
    func fetchPhaseDetails(pathwayId: UUID, phaseNumber: Int) async throws -> PathwayPhase? {
        let phases: [PathwayPhase] = try await supabase
            .from("pathway_phases")
            .select()
            .eq("pathway_id", value: pathwayId.uuidString)
            .eq("phase_number", value: phaseNumber)
            .execute()
            .value
        
        return phases.first
    }
    
    /// Fetch milestones for a specific user pathway phase
    func fetchPhaseMilestones(userPathwayId: UUID, phaseNumber: Int) async throws -> [PathwayMilestone] {
        let milestones: [PathwayMilestone] = try await supabase
            .from("pathway_milestones")
            .select()
            .eq("user_pathway_id", value: userPathwayId.uuidString)
            .eq("phase_number", value: phaseNumber)
            .execute()
            .value
        
        return milestones
    }

    /// Advance to next phase
    func advancePhase(userPathwayId: UUID) async throws -> AdvancePhaseResponse {
        struct AdvanceRequest: Codable {
            let userPathwayId: String
        }

        let request = AdvanceRequest(userPathwayId: userPathwayId.uuidString)

        let response: AdvancePhaseResponse = try await supabase.functions.invoke(
            "advance-pathway-phase",
            options: FunctionInvokeOptions(body: request)
        )

        return response
    }

    // MARK: - Pathway State Management

    /// Pause active pathway
    func pausePathway(userPathwayId: UUID, reason: String? = nil) async throws {
        struct PauseRequest: Codable {
            let userPathwayId: String
            let reason: String?
        }

        let request = PauseRequest(userPathwayId: userPathwayId.uuidString, reason: reason)

        // ✅ FIX: Pass Codable struct directly - FunctionInvokeOptions will encode it
        _ = try await supabase.functions.invoke(
            "pause-pathway",
            options: FunctionInvokeOptions(body: request)
        )
    }

    /// Resume paused pathway
    func resumePathway(userPathwayId: UUID) async throws {
        struct ResumeRequest: Codable {
            let userPathwayId: String
        }

        let request = ResumeRequest(userPathwayId: userPathwayId.uuidString)

        // ✅ FIX: Pass Codable struct directly - FunctionInvokeOptions will encode it
        _ = try await supabase.functions.invoke(
            "resume-pathway",
            options: FunctionInvokeOptions(body: request)
        )
    }

    /// Abandon pathway
    func abandonPathway(userPathwayId: UUID, feedback: String? = nil) async throws {
        struct AbandonRequest: Codable {
            let userPathwayId: String
            let feedback: String?
        }

        let request = AbandonRequest(userPathwayId: userPathwayId.uuidString, feedback: feedback)

        // ✅ FIX: Pass Codable struct directly - FunctionInvokeOptions will encode it
        _ = try await supabase.functions.invoke(
            "abandon-pathway",
            options: FunctionInvokeOptions(body: request)
        )
    }

    // MARK: - Journal Draft Management (Delegation to Cache Service)

    /// Get journal draft for a pathway
    /// - Throws: SecureStorageError if decryption fails
    func getJournalDraft(for pathwayId: UUID) throws -> String? {
        try cacheService.getJournalDraft(for: pathwayId)
    }

    /// Save journal draft for a pathway
    /// - Throws: SecureStorageError if encryption fails
    func saveJournalDraft(_ text: String, for pathwayId: UUID) throws {
        try cacheService.saveJournalDraft(text, for: pathwayId)
    }

    /// Clear journal draft for a pathway
    func clearJournalDraft(for pathwayId: UUID) {
        cacheService.clearJournalDraft(for: pathwayId)
    }
}
