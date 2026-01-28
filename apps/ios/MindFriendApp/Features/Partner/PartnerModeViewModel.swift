import SwiftUI
import Combine

/// ViewModel for Partner Mode feature
/// Manages partner state, invite codes, sharing settings, and encouragement
@MainActor
final class PartnerModeViewModel: ObservableObject {
    // MARK: - Dependencies

    private let dataService: SupabaseDataService

    // MARK: - Published State

    @Published var partnerState: PartnerState = .noPartner
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

    init(dataService: SupabaseDataService) {
        self.dataService = dataService
    }
    
    // PERF-CRIT-002: Clean up timer on deallocation
    deinit {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Data Loading

    /// Load all partner data
    func loadPartnerData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Add timeout protection (15 seconds)
            try await partnerWithTimeout(seconds: 15) {
                try await self._loadPartnerDataInternal()
            }
        } catch is TimeoutError {
            partnerState = .noPartner
            showError(message: "Connection timed out. Please check your network and try again.")
        } catch {
            // CRITICAL FIX: Update state so UI doesn't hang forever
            partnerState = .noPartner
            handleError(error)
        }
    }
    
    /// Internal implementation of partner data loading
    private func _loadPartnerDataInternal() async throws {
        // Check for active partner
        if let partnerInfo = try await dataService.getPartnerInfo() {
            partnerState = .hasPartner(partnerInfo)

            // Load partner's shared data
            await loadPartnerSharedData(partnerInfo: partnerInfo)

            // Load my sharing settings (use cached link from getPartnerInfo)
            if let link = try await dataService.getActivePartnerLink(),
               let currentUserId = dataService.currentUserId {
                mySharingSettings = link.mySharingSettings(for: currentUserId)
            }
        } else {
            // Check for pending invite
            if let (code, expiresAt) = try? await getPendingInvite() {
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
        if partnerInfo.isSharingMood {
            do {
                partnerMoods = try await dataService.getPartnerMoodHistory(partnerId: partnerInfo.partnerId)
            } catch {
                Log.data.warning("[PartnerMode] Failed to load partner moods: \(error)")
            }
        } else {
            partnerMoods = []
        }

        // Load quest if shared
        if partnerInfo.isSharingExercises {
            do {
                partnerQuest = try await dataService.getPartnerQuestStatus(partnerId: partnerInfo.partnerId)
            } catch {
                Log.data.warning("[PartnerMode] Failed to load partner quest: \(error)")
            }
        } else {
            partnerQuest = nil
        }
    }

    /// Get existing pending invite if any
    private func getPendingInvite() async throws -> (String, Date)? {
        let invites = try await dataService.getPendingBuddyInvites()
        guard let invite = invites.first else { return nil }
        return (invite.inviteCode, invite.expiresAt)
    }

    // MARK: - Invite Code Actions

    /// Generate or retrieve existing invite code
    func generateInviteCode() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let (code, expiresAt) = try await dataService.getOrCreatePartnerInviteCode()
            inviteCode = code
            inviteExpiresAt = expiresAt
            partnerState = .pendingInvite(code: code, expiresAt: expiresAt)

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
        let code = codeInput.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6 else {
            showError(message: "Please enter a 6-character code")
            return
        }

        isValidatingCode = true
        defer { isValidatingCode = false }

        do {
            _ = try await dataService.acceptBuddyInvite(code: code)
            codeInput = ""

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
        if let couplesModeError = error as? CouplesModeError {
            showError(message: couplesModeError.localizedDescription)
        } else if let dataError = error as? DataError {
            showError(message: dataError.localizedDescription)
        } else {
            showError(message: "Something went wrong. Please try again.")
        }
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
        codeInput.count == 6
    }

    /// Formatted invite code (with spaces)
    var formattedInviteCode: String {
        guard let code = inviteCode else { return "" }
        let chars = Array(code)
        if chars.count == 6 {
            return "\(chars[0])\(chars[1])\(chars[2]) \(chars[3])\(chars[4])\(chars[5])"
        }
        return code
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
