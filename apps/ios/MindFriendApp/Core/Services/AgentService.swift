import Foundation
import Supabase
import Realtime

// MARK: - AgentService Protocol

protocol AgentServiceProtocol {
    func fetchSettings() async throws -> AgentSettings
    func updateSettings(_ settings: AgentSettings) async throws
    func fetchActiveSignals() async throws -> [AgentSignal]
    func fetchRecentActions(limit: Int) async throws -> [AgentAction]
    func recordResponse(actionId: UUID, response: UserResponse) async throws -> AgentLearnResponse
    func dismissAction(actionId: UUID) async throws
    func markActionAsHelpful(actionId: UUID, isHelpful: Bool) async throws
    func fetchLearnings() async throws -> [AgentLearning]
    func fetchDecisions(limit: Int) async throws -> [AgentDecision]
    func getActionsCountToday() async throws -> Int
}

// MARK: - AgentService Implementation

@MainActor
final class AgentService: ObservableObject, AgentServiceProtocol {
    private let supabase: SupabaseClient

    @Published private(set) var settings: AgentSettings?
    @Published private(set) var activeSignals: [AgentSignal] = []
    @Published private(set) var recentActions: [AgentAction] = []
    @Published private(set) var learnings: [AgentLearning] = []
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Settings

    func fetchSettings() async throws -> AgentSettings {
        isLoading = true
        defer { isLoading = false }

        guard let userId = supabase.auth.currentUser?.id else {
            throw AgentServiceError.notAuthenticated
        }

        // Try to fetch existing settings
        let existingSettings: [AgentSettings] = try await supabase
            .from("agent_settings")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value

        if let settings = existingSettings.first {
            self.settings = settings
            return settings
        }

        // No settings exist - create default settings for this user
        struct NewSettings: Encodable {
            let user_id: UUID
            let autonomy_level: String
            let enabled_signals: [String]
            let quiet_hours_start: String
            let quiet_hours_end: String
            let max_daily_outreach: Int
            let preferred_channels: [String]
            let explain_reasoning: Bool
            let is_enabled: Bool
            let timezone: String
        }

        let newSettings = NewSettings(
            user_id: userId,
            autonomy_level: "balanced",
            enabled_signals: SignalType.allCases.map { $0.rawValue },
            quiet_hours_start: "22:00",
            quiet_hours_end: "08:00",
            max_daily_outreach: 3,
            preferred_channels: ["push", "in_app"],
            explain_reasoning: true,
            is_enabled: false,
            timezone: TimeZone.current.identifier
        )

        let response: AgentSettings = try await supabase
            .from("agent_settings")
            .insert(newSettings)
            .select()
            .single()
            .execute()
            .value

        self.settings = response
        return response
    }

    func updateSettings(_ settings: AgentSettings) async throws {
        isLoading = true
        defer { isLoading = false }

        guard let userId = supabase.auth.currentUser?.id else {
            throw AgentServiceError.notAuthenticated
        }

        struct SettingsUpdate: Encodable {
            let autonomy_level: String
            let enabled_signals: [String]
            let quiet_hours_start: String
            let quiet_hours_end: String
            let max_daily_outreach: Int
            let preferred_channels: [String]
            let explain_reasoning: Bool
            let is_enabled: Bool
            let timezone: String
        }

        let update = SettingsUpdate(
            autonomy_level: settings.autonomyLevel.rawValue,
            enabled_signals: settings.enabledSignals,
            quiet_hours_start: settings.quietHoursStart,
            quiet_hours_end: settings.quietHoursEnd,
            max_daily_outreach: settings.maxDailyOutreach,
            preferred_channels: settings.preferredChannels,
            explain_reasoning: settings.explainReasoning,
            is_enabled: settings.isEnabled,
            timezone: settings.timezone
        )

        try await supabase
            .from("agent_settings")
            .update(update)
            .eq("user_id", value: userId)
            .execute()

        self.settings = settings
    }

    // MARK: - Signals

    func fetchActiveSignals() async throws -> [AgentSignal] {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AgentServiceError.notAuthenticated
        }

        let response: [AgentSignal] = try await supabase
            .from("agent_signals")
            .select()
            .eq("user_id", value: userId)
            .eq("is_resolved", value: false)
            .order("detected_at", ascending: false)
            .limit(20)
            .execute()
            .value

        self.activeSignals = response
        return response
    }

    // MARK: - Actions

    func fetchRecentActions(limit: Int = 30) async throws -> [AgentAction] {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AgentServiceError.notAuthenticated
        }

        let response: [AgentAction] = try await supabase
            .from("agent_actions")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        self.recentActions = response
        return response
    }

    func getActionsCountToday() async throws -> Int {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AgentServiceError.notAuthenticated
        }

        let today = Calendar.current.startOfDay(for: Date())

        let response: [AgentAction] = try await supabase
            .from("agent_actions")
            .select()
            .eq("user_id", value: userId)
            .gte("created_at", value: ISO8601DateFormatter().string(from: today))
            .in("status", values: ["delivered", "opened", "responded"])
            .execute()
            .value

        return response.count
    }

    func recordResponse(actionId: UUID, response: UserResponse) async throws -> AgentLearnResponse {
        let request = AgentLearnRequest(
            actionId: actionId.uuidString,
            userResponse: response
        )

        let result: AgentLearnResponse = try await supabase.functions
            .invoke("agent-learn", options: .init(body: request))

        // Refresh actions to show updated status
        _ = try? await fetchRecentActions()

        return result
    }

    func dismissAction(actionId: UUID) async throws {
        let response = UserResponse(
            responseType: "dismissed",
            selectedAction: nil,
            timestamp: Date(),
            sentiment: nil
        )

        _ = try await recordResponse(actionId: actionId, response: response)
    }

    func markActionAsHelpful(actionId: UUID, isHelpful: Bool) async throws {
        let response = UserResponse(
            responseType: isHelpful ? "feedback_positive" : "feedback_negative",
            selectedAction: nil,
            timestamp: Date(),
            sentiment: isHelpful ? "positive" : "negative"
        )

        _ = try await recordResponse(actionId: actionId, response: response)
    }

    // MARK: - Learnings

    func fetchLearnings() async throws -> [AgentLearning] {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AgentServiceError.notAuthenticated
        }

        let response: [AgentLearning] = try await supabase
            .from("agent_learnings")
            .select()
            .eq("user_id", value: userId)
            .order("last_updated", ascending: false)
            .execute()
            .value

        self.learnings = response
        return response
    }

    // MARK: - Decisions

    func fetchDecisions(limit: Int = 50) async throws -> [AgentDecision] {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AgentServiceError.notAuthenticated
        }

        let response: [AgentDecision] = try await supabase
            .from("agent_decisions")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return response
    }

    // MARK: - Dashboard Data

    func loadDashboardData() async throws -> AgentDashboardData {
        isLoading = true
        defer { isLoading = false }

        async let settingsTask = fetchSettings()
        async let signalsTask = fetchActiveSignals()
        async let actionsTask = fetchRecentActions(limit: 10)
        async let countTask = getActionsCountToday()

        let (settings, signals, actions, count) = try await (
            settingsTask,
            signalsTask,
            actionsTask,
            countTask
        )

        return AgentDashboardData(
            settings: settings,
            activeSignals: signals,
            recentActions: actions,
            actionsToday: count
        )
    }

    // MARK: - Real-time Subscriptions

    func subscribeToActions() async {
        guard let userId = supabase.auth.currentUser?.id else { return }

        // Validate UUID format for filter safety with strict segment validation
        // UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx (8-4-4-4-12 hex chars)
        let userIdString = userId.uuidString
        let strictUUIDPattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        guard userIdString.range(of: strictUUIDPattern, options: .regularExpression) != nil else {
            return
        }

        let channel = supabase.channel("agent_actions_\(userIdString)")

        // Listen for new actions
        _ = channel
            .onPostgresChange(
                InsertAction.self,
                table: "agent_actions",
                filter: "user_id=eq.\(userIdString)"
            ) { [weak self] _ in
                Task { @MainActor in
                    _ = try? await self?.fetchRecentActions()
                }
            }

        // Listen for action updates
        _ = channel
            .onPostgresChange(
                UpdateAction.self,
                table: "agent_actions",
                filter: "user_id=eq.\(userIdString)"
            ) { [weak self] _ in
                Task { @MainActor in
                    _ = try? await self?.fetchRecentActions()
                }
            }

        await channel.subscribe()
    }
}

// MARK: - Errors

enum AgentServiceError: LocalizedError {
    case notAuthenticated
    case settingsNotFound
    case updateFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to access agent features"
        case .settingsNotFound:
            return "Agent settings not found"
        case .updateFailed(let message):
            return "Failed to update settings: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
