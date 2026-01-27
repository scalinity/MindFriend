import Foundation
import Supabase

// MARK: - Activation Service

/// Service to track user activation (magic moment) and manage progressive feature disclosure.
///
/// The "magic moment" is defined as completing BOTH:
/// 1. First engagement: completing a quest OR logging a mood
/// 2. First value realization: sending a chat message
///
/// Once activated, users unlock additional features (Programs, Progress tabs).
@MainActor
final class ActivationService: ObservableObject {

    // MARK: - Feature Enum

    /// Features that can be unlocked through progressive disclosure
    enum Feature: String, CaseIterable, Codable {
        case home
        case chat
        case profile
        case programs
        case outcomes

        /// Features unlocked by default for all users
        static var defaultUnlocked: Set<Feature> {
            [.home, .chat, .profile]
        }

        /// All features (unlocked after activation)
        static var allFeatures: Set<Feature> {
            Set(Feature.allCases)
        }

        /// Display name for the feature
        var displayName: String {
            switch self {
            case .home: return "Home"
            case .chat: return "Chat"
            case .profile: return "Profile"
            case .programs: return "Programs"
            case .outcomes: return "Progress"
            }
        }
    }

    // MARK: - Published State

    /// Currently unlocked features
    @Published private(set) var unlockedFeatures: Set<Feature> = Feature.defaultUnlocked

    /// Whether the user just activated (for showing celebration)
    @Published var justActivated = false

    /// Whether the user is fully activated
    @Published private(set) var isActivated = false

    /// Activation progress milestones
    @Published private(set) var hasCompletedQuest = false
    @Published private(set) var hasLoggedMood = false
    @Published private(set) var hasSentChat = false

    /// Error state for UI to display retry options
    @Published private(set) var loadError: Error?

    /// Flag to prevent concurrent activation checks (race condition protection)
    private var isCheckingActivation = false

    // MARK: - Dependencies

    private let supabase: SupabaseClient
    private let authService: SupabaseAuthService

    // MARK: - Initialization

    init(supabase: SupabaseClient, authService: SupabaseAuthService) {
        self.supabase = supabase
        self.authService = authService
    }

    // MARK: - Public Methods

    /// Check if a specific feature is unlocked
    func isUnlocked(_ feature: Feature) -> Bool {
        unlockedFeatures.contains(feature)
    }

    /// Load activation state from the server
    func loadActivationState() async {
        guard let userId = authService.currentUser?.id else { return }

        // Clear previous error on retry
        self.loadError = nil

        do {
            let response: ActivationStatusResponse = try await supabase
                .rpc("check_activation_status", params: UserIdParams(p_user_id: userId))
                .execute()
                .value

            // Already on MainActor (class is @MainActor), no need for MainActor.run
            self.isActivated = response.activated
            self.hasCompletedQuest = response.hasQuest ?? false
            self.hasLoggedMood = response.hasMood ?? false
            self.hasSentChat = response.hasChat ?? false

            if let features = response.unlockedFeatures {
                self.unlockedFeatures = Set(features.compactMap { Feature(rawValue: $0) })
            }

            if self.isActivated {
                self.unlockedFeatures = Feature.allFeatures
            }
        } catch {
            self.loadError = error
            #if DEBUG
            print("[ActivationService] Failed to load activation state: \(error.localizedDescription)")
            #endif
        }
    }

    /// Record that the user completed their first quest
    func recordQuestCompletion() async throws {
        guard !hasCompletedQuest else { return }
        guard let userId = authService.currentUser?.id else { return }

        try await supabase
            .rpc("record_first_quest_completion", params: UserIdParams(p_user_id: userId))
            .execute()

        // Already on MainActor (class is @MainActor)
        self.hasCompletedQuest = true

        // Track analytics
        Analytics.shared.track(.activationEngagementQuest)

        // Check if this completes activation
        await checkAndCompleteActivation()
    }

    /// Record that the user logged their first mood
    func recordMoodLog() async throws {
        guard !hasLoggedMood else { return }
        guard let userId = authService.currentUser?.id else { return }

        try await supabase
            .rpc("record_first_mood_log", params: UserIdParams(p_user_id: userId))
            .execute()

        // Already on MainActor (class is @MainActor)
        self.hasLoggedMood = true

        // Track analytics
        Analytics.shared.track(.activationEngagementMood)

        // Check if this completes activation
        await checkAndCompleteActivation()
    }

    /// Record that the user sent their first chat message
    func recordChatMessage() async throws {
        guard !hasSentChat else { return }
        guard let userId = authService.currentUser?.id else { return }

        try await supabase
            .rpc("record_first_chat_message", params: UserIdParams(p_user_id: userId))
            .execute()

        // Already on MainActor (class is @MainActor)
        self.hasSentChat = true

        // Track analytics
        Analytics.shared.track(.activationValueChat)

        // Check if this completes activation
        await checkAndCompleteActivation()
    }

    // MARK: - Private Methods

    /// Check if the magic moment conditions are met and complete activation
    private func checkAndCompleteActivation() async {
        // Prevent concurrent activation checks (race condition protection)
        guard !isCheckingActivation else { return }
        guard !isActivated else { return }
        guard let userId = authService.currentUser?.id else { return }

        // Magic moment: (quest OR mood) AND chat
        let hasEngagement = hasCompletedQuest || hasLoggedMood
        guard hasEngagement && hasSentChat else { return }

        isCheckingActivation = true
        defer { isCheckingActivation = false }

        do {
            let response: ActivationStatusResponse = try await supabase
                .rpc("check_activation_status", params: UserIdParams(p_user_id: userId))
                .execute()
                .value

            if response.justActivated == true {
                // Already on MainActor (class is @MainActor)
                self.isActivated = true
                self.unlockedFeatures = Feature.allFeatures
                self.justActivated = true

                // Track analytics with context
                Analytics.shared.track(.activationCompleted, properties: [
                    "quest_first": hasCompletedQuest && !hasLoggedMood
                ])

                // Track feature unlock
                Analytics.shared.track(.featureUnlocked, properties: [
                    "features": ["programs", "outcomes"].joined(separator: ","),
                    "trigger": "activation"
                ])
            }
        } catch {
            #if DEBUG
            print("[ActivationService] Failed to check activation: \(error.localizedDescription)")
            #endif
        }
    }

    /// Reset the justActivated flag (called after celebration is shown)
    func clearJustActivated() {
        justActivated = false
    }
}

// MARK: - Request/Response Models

/// Parameters for user ID-based RPC calls
private struct UserIdParams: Encodable {
    let p_user_id: UUID
}

private struct ActivationStatusResponse: Codable {
    let activated: Bool
    let alreadyActivated: Bool?
    let justActivated: Bool?
    let hasQuest: Bool?
    let hasMood: Bool?
    let hasChat: Bool?
    let unlockedFeatures: [String]?

    enum CodingKeys: String, CodingKey {
        case activated
        case alreadyActivated = "already_activated"
        case justActivated = "just_activated"
        case hasQuest = "has_quest"
        case hasMood = "has_mood"
        case hasChat = "has_chat"
        case unlockedFeatures = "unlocked_features"
    }
}
