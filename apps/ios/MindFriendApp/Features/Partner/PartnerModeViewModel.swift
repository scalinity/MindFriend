import SwiftUI
import Combine
import Supabase

/// ViewModel for Partner Mode feature
/// Manages partner state, invite codes, sharing settings, and encouragement
@MainActor
final class PartnerModeViewModel: ObservableObject {
    // MARK: - Dependencies

    private let dataService: SupabaseDataService
    private let invitationAPI: PartnerInvitationClient
    private var inviteOwnerId: UUID?

    // MARK: - Published State

    @Published var partnerState: PartnerState = .loading
    @Published var inviteCode: String?
    @Published var inviteExpiresAt: Date?
    @Published var codeInput: String = ""
    @Published var isLoading = false
    @Published var isValidatingCode = false
    @Published var isSendingEncouragement = false

    // Partner data
    @Published var partnerMoods: [MoodEntry] = []
    @Published var partnerQuest: Quest?
    @Published var couplesExercises: [CouplesExercise] = []
    @Published var activeSession: CouplesExerciseSession?

    // Sharing settings
    @Published var mySharingSettings: SharingSettings = SharingSettings(shareMood: false, shareExercises: false)
    @Published var isSavingSettings = false

    // UI state
    @Published var showEncouragementPicker = false
    @Published var showEncouragementSent = false
    @Published var showError = false
    @Published var errorMessage = ""

    // Polling
    private var pollTimer: Timer?

    // MARK: - Initialization

    init(dataService: SupabaseDataService, inviteClient: SupabaseClient? = nil) {
        self.dataService = dataService
        self.invitationAPI = PartnerInvitationClient(client: inviteClient ?? supabase)
    }
    
    // PERF-CRIT-002: Clean up timer on deallocation
    deinit {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Data Loading

    /// Load all partner data
    func loadPartnerData() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            // Add timeout protection (15 seconds)
            try await partnerWithTimeout(seconds: 15) {
                try await self._loadPartnerDataInternal()
            }
        } catch is TimeoutError {
            partnerState = .noPartner
            partnerMoods = []
            partnerQuest = nil
            showError(message: "Connection timed out. Please check your network and try again.")
        } catch {
            // CRITICAL FIX: Update state so UI doesn't hang forever
            partnerState = .noPartner
            partnerMoods = []
            partnerQuest = nil
            handleError(error)
        }
    }
    
    /// Internal implementation of partner data loading
    private func _loadPartnerDataInternal() async throws {
        let owner = dataService.currentUserId
        // Check for active partner
        if let partnerInfo = try await dataService.getPartnerInfo() {
            guard owner == dataService.currentUserId else { throw CancellationError() }
            if case .hasPartner(let previous) = partnerState, previous.partnerId == partnerInfo.partnerId {
                // The same partner can retain data only while each sharing read succeeds.
            } else {
                partnerMoods = []
                partnerQuest = nil
            }
            inviteCode = nil
            inviteExpiresAt = nil
            partnerState = .hasPartner(partnerInfo)

            // Load partner's shared data
            await loadPartnerSharedData(partnerInfo: partnerInfo)

            // Load my sharing settings (use cached link from getPartnerInfo)
            if let link = try await dataService.getActivePartnerLink(),
               let currentUserId = dataService.currentUserId {
                mySharingSettings = link.mySharingSettings(for: currentUserId)
            }
        } else {
            partnerMoods = []
            partnerQuest = nil
            // The server retains only a hash; reuse the current view's unexpired code.
            if let (code, expiresAt) = getPendingInvite() {
                partnerState = .pendingInvite(code: code, expiresAt: expiresAt)
                inviteCode = code
                inviteExpiresAt = expiresAt
            } else {
                partnerState = .noPartner
            }
        }
    }

    /// Load partner's shared mood and quest data
    private func loadPartnerSharedData(partnerInfo: PartnerInfo) async {
        // Load moods if shared
        let owner = dataService.currentUserId
        if partnerInfo.isSharingMood {
            do {
                let moods = try await dataService.getPartnerMoodHistory(partnerId: partnerInfo.partnerId)
                guard owner == dataService.currentUserId else { partnerMoods = []; partnerQuest = nil; return }
                partnerMoods = moods
            } catch {
                partnerMoods = []
                Log.data.warning("[PartnerMode] Failed to load partner moods: \(error)")
            }
        } else {
            partnerMoods = []
        }

        // Load quest if shared
        if partnerInfo.isSharingExercises {
            do {
                let quest = try await dataService.getPartnerQuestStatus(partnerId: partnerInfo.partnerId)
                guard owner == dataService.currentUserId else { partnerMoods = []; partnerQuest = nil; return }
                partnerQuest = quest
            } catch {
                partnerQuest = nil
                Log.data.warning("[PartnerMode] Failed to load partner quest: \(error)")
            }
        } else {
            partnerQuest = nil
        }
    }

    /// Get existing pending invite if any
    private func getPendingInvite() -> (String, Date)? {
        guard inviteOwnerId == dataService.currentUserId,
              let inviteCode, let inviteExpiresAt, inviteExpiresAt > Date() else { return nil }
        return (inviteCode, inviteExpiresAt)
    }

    // MARK: - Invite Code Actions

    /// Generate or retrieve existing invite code
    func generateInviteCode() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if let (code, expiresAt) = getPendingInvite() {
                partnerState = .pendingInvite(code: code, expiresAt: expiresAt)
                return
            }
            let owner = dataService.currentUserId
            let invitation = try await invitationAPI.create()
            guard owner == dataService.currentUserId else { throw CancellationError() }
            inviteOwnerId = owner
            inviteCode = invitation.code
            inviteExpiresAt = invitation.expiresAt
            partnerState = .pendingInvite(code: invitation.code, expiresAt: invitation.expiresAt)

            Analytics.shared.track(.buddyInviteSent, properties: [
                "method": "link",
                "source": "partner_mode"
            ])
        } catch {
            handleError(error)
        }
    }

    /// Accept an invite code
    func acceptInviteCode() async {
        guard !isValidatingCode else { return }
        let code = codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidInviteCode(code) else {
            showError(message: "Please enter the 8-character code exactly as shared")
            return
        }

        isValidatingCode = true
        defer { isValidatingCode = false }

        do {
            try await invitationAPI.accept(code: code)
            codeInput = ""
            inviteCode = nil
            inviteExpiresAt = nil

            // Reload partner data
            await loadPartnerData()

            Analytics.shared.track(.buddyInviteAccepted, properties: [
                "source": "partner_mode"
            ])
        } catch {
            handleError(error)
        }
    }

    /// Accept code from deep link
    func acceptCodeFromDeepLink(_ code: String) async {
        codeInput = code
        await acceptInviteCode()
    }

    // MARK: - Sharing Settings

    /// Update sharing settings
    func updateSharingSettings(shareMood: Bool? = nil, shareExercises: Bool? = nil) async {
        let newShareMood = shareMood ?? mySharingSettings.shareMood
        let newShareExercises = shareExercises ?? mySharingSettings.shareExercises

        // Optimistic update
        let previousSettings = mySharingSettings
        mySharingSettings = SharingSettings(shareMood: newShareMood, shareExercises: newShareExercises)
        isSavingSettings = true

        do {
            try await dataService.updatePartnerSharingSettings(
                shareMood: newShareMood,
                shareExercises: newShareExercises
            )
            isSavingSettings = false
        } catch {
            // Revert on failure
            mySharingSettings = previousSettings
            isSavingSettings = false
            handleError(error)
        }
    }

    // MARK: - Encouragement

    /// Send encouragement to partner
    func sendEncouragement(_ type: BuddyEncouragement.MessageType) async {
        isSendingEncouragement = true
        defer { isSendingEncouragement = false }

        do {
            try await dataService.sendPartnerEncouragement(type: type)
            showEncouragementSent = true
            showEncouragementPicker = false

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Hide confirmation after delay
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    showEncouragementSent = false
                }
            }
        } catch let error as CouplesModeError {
            if case .rateLimited(let seconds) = error {
                let minutes = seconds / 60
                showError(message: "You can send another encouragement in \(minutes) minutes")
            } else {
                handleError(error)
            }
        } catch {
            handleError(error)
        }
    }

    // MARK: - Exercises

    /// Load couples exercises
    func loadCouplesExercises() async {
        do {
            couplesExercises = try await dataService.getCouplesExercises()
        } catch {
            Log.data.warning("[PartnerMode] Failed to load couples exercises: \(error)")
        }
    }

    /// Start an exercise session
    func startExerciseSession(_ exerciseId: UUID) async throws -> CouplesExerciseSession {
        let session = try await dataService.startCouplesSession(exerciseId: exerciseId)
        activeSession = session
        return session
    }

    // MARK: - Partnership Management

    /// End the current partnership
    func endPartnership() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await dataService.endPartnership()
            partnerState = .noPartner
            inviteCode = nil
            inviteExpiresAt = nil
            partnerMoods = []
            partnerQuest = nil
            mySharingSettings = SharingSettings(shareMood: false, shareExercises: false)
        } catch {
            handleError(error)
        }
    }

    // MARK: - Polling

    /// Start polling for partner updates
    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.loadPartnerData()
            }
        }
    }

    /// Stop polling
    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error) {
        let message: String
        if let couplesModeError = error as? CouplesModeError {
            message = couplesModeError.localizedDescription
        } else if let dataError = error as? DataError {
            message = dataError.localizedDescription
        } else {
            // Show more details in debug builds
            #if DEBUG
            message = "Error: \(error.localizedDescription)"
            #else
            message = "Something went wrong. Please try again."
            #endif
        }
        showError(message: message)
        error.report(context: ["feature": "partner_mode"])
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Computed Properties

extension PartnerModeViewModel {
    /// Whether the code input is valid
    var isCodeInputValid: Bool {
        Self.isValidInviteCode(codeInput.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Formatted invite code (with spaces)
    var formattedInviteCode: String {
        guard let code = inviteCode else { return "" }
        return code
    }

    nonisolated static func isValidInviteCode(_ code: String) -> Bool {
        PartnerInvitationClient.isValidCode(code)
    }

    /// Days until invite expires
    var daysUntilExpiry: Int {
        guard let expiresAt = inviteExpiresAt else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
        return max(0, days)
    }

    /// Whether partner has shared any data
    var partnerHasSharedData: Bool {
        guard case .hasPartner(let info) = partnerState else { return false }
        return info.isSharingMood || info.isSharingExercises
    }
}

/// The existing couples endpoints store hashed, case-sensitive partner codes.
struct PartnerInvitationClient {
    let client: SupabaseClient

    func create() async throws -> (code: String, expiresAt: Date) {
        struct Invite: Decodable { let inviteCode: String; let expiresAt: String }
        let response: Invite = try await client.functions.invoke("couples-partner-links", options: .init(body: [:] as [String: String]))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard Self.isValidCode(response.inviteCode), let expiresAt = formatter.date(from: response.expiresAt) else {
            throw CouplesModeError.internalError
        }
        return (response.inviteCode, expiresAt)
    }

    func accept(code: String) async throws {
        guard Self.isValidCode(code) else { throw CouplesModeError.inviteInvalid }
        struct Accepted: Decodable { let status: String }
        let result: Accepted = try await client.functions.invoke(
            "couples-partner-links-accept", options: .init(body: ["inviteCode": code])
        )
        guard result.status == "active" else { throw CouplesModeError.inviteInvalid }
    }

    static func isValidCode(_ code: String) -> Bool {
        let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        return code.count == 8 && code.allSatisfy { alphabet.contains($0) }
    }
}

// MARK: - Timeout Helper

/// Custom error for timeout
struct TimeoutError: Error {}

/// Execute an async operation with a timeout (partner-specific version)
fileprivate func partnerWithTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Start the actual operation
        group.addTask {
            try await operation()
        }

        // Start the timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }

        // Return the first result (either success or timeout)
        guard let result = try await group.next() else {
            throw TimeoutError()
        }
        group.cancelAll()
        return result
    }
}
