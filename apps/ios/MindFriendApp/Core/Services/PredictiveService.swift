import Foundation
import Supabase
import OSLog

/// Service for predictive intervention features
/// Handles risk assessments, interventions, and prediction settings
@MainActor
final class PredictiveService: ObservableObject {

    private let authService: SupabaseAuthService
    private let logger = Logger(subsystem: "com.mindfriend", category: "PredictiveService")

    // MARK: - Published State

    @Published private(set) var latestAssessment: RiskAssessment?
    @Published private(set) var pendingInterventions: [Intervention] = []
    @Published private(set) var settings: PredictionSettings = .defaults
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    // MARK: - Initialization

    init(authService: SupabaseAuthService) {
        self.authService = authService
    }

    private var userId: UUID {
        get throws {
            guard let id = authService.userId else {
                throw PredictiveError.notAuthenticated
            }
            return id
        }
    }

    // MARK: - Settings Management

    /// Fetch user's prediction settings
    func fetchSettings() async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            let uid = try userId
            let result: PredictionSettings? = try await supabase
                .from("prediction_settings")
                .select()
                .eq("user_id", value: uid)
                .single()
                .execute()
                .value

            settings = result ?? .defaults
            logger.info("Fetched prediction settings: enabled=\(self.settings.predictionsEnabled)")
        } catch {
            // If no settings exist, use defaults
            if (error as? PostgrestError)?.code == "PGRST116" {
                settings = .defaults
            } else {
                self.error = error
                throw error
            }
        }
    }

    /// Update user's prediction settings
    func updateSettings(_ newSettings: PredictionSettings) async throws {
        isLoading = true
        defer { isLoading = false }

        let uid = try userId

        // Prepare database record
        struct SettingsUpdate: Encodable {
            let userId: UUID
            let predictionsEnabled: Bool
            let useMoodData: Bool
            let useChatSentiment: Bool
            let useBiometrics: Bool
            let useAppUsage: Bool
            let useSleepData: Bool
            let allowGentleNudges: Bool
            let allowActiveCheckins: Bool
            let preferredInterventionTime: String?
            let allowFamilyAlerts: Bool
            let familyAlertThreshold: String

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case predictionsEnabled = "predictions_enabled"
                case useMoodData = "use_mood_data"
                case useChatSentiment = "use_chat_sentiment"
                case useBiometrics = "use_biometrics"
                case useAppUsage = "use_app_usage"
                case useSleepData = "use_sleep_data"
                case allowGentleNudges = "allow_gentle_nudges"
                case allowActiveCheckins = "allow_active_checkins"
                case preferredInterventionTime = "preferred_intervention_time"
                case allowFamilyAlerts = "allow_family_alerts"
                case familyAlertThreshold = "family_alert_threshold"
            }
        }

        let update = SettingsUpdate(
            userId: uid,
            predictionsEnabled: newSettings.predictionsEnabled,
            useMoodData: newSettings.useMoodData,
            useChatSentiment: newSettings.useChatSentiment,
            useBiometrics: newSettings.useBiometrics,
            useAppUsage: newSettings.useAppUsage,
            useSleepData: newSettings.useSleepData,
            allowGentleNudges: newSettings.allowGentleNudges,
            allowActiveCheckins: newSettings.allowActiveCheckins,
            preferredInterventionTime: newSettings.preferredInterventionTimeString,
            allowFamilyAlerts: newSettings.allowFamilyAlerts,
            familyAlertThreshold: newSettings.familyAlertThreshold.rawValue
        )

        try await supabase
            .from("prediction_settings")
            .upsert(update)
            .execute()

        settings = newSettings

        // Track analytics
        Analytics.shared.track(.settingsChanged, properties: [
            "feature": "predictions",
            "enabled": newSettings.predictionsEnabled
        ])

        logger.info("Updated prediction settings: enabled=\(newSettings.predictionsEnabled)")
    }

    /// Enable predictions (opt-in)
    func enablePredictions() async throws {
        var newSettings = settings
        newSettings.predictionsEnabled = true
        try await updateSettings(newSettings)

        // Trigger initial assessment
        try await triggerAssessment()
    }

    /// Disable predictions (opt-out)
    func disablePredictions() async throws {
        var newSettings = settings
        newSettings.predictionsEnabled = false
        try await updateSettings(newSettings)
    }

    // MARK: - Risk Assessments

    /// Fetch the latest risk assessment
    func fetchLatestAssessment() async throws {
        guard settings.predictionsEnabled else {
            latestAssessment = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        let uid = try userId
        let results: [RiskAssessment] = try await supabase
            .from("risk_assessments")
            .select()
            .eq("user_id", value: uid)
            .order("assessed_at", ascending: false)
            .limit(1)
            .execute()
            .value

        latestAssessment = results.first
        logger.info("Fetched latest assessment: score=\(results.first?.riskScore ?? -1)")
    }

    /// Fetch assessment history
    func fetchAssessmentHistory(limit: Int = 30) async throws -> [RiskAssessment] {
        guard settings.predictionsEnabled else {
            return []
        }

        let uid = try userId
        let results: [RiskAssessment] = try await supabase
            .from("risk_assessments")
            .select()
            .eq("user_id", value: uid)
            .order("assessed_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return results
    }

    /// Trigger a new risk assessment via Edge Function
    func triggerAssessment() async throws {
        guard settings.predictionsEnabled else {
            throw PredictiveError.predictionsDisabled
        }

        isLoading = true
        defer { isLoading = false }

        let uid = try userId

        struct AssessmentRequest: Encodable {
            let userId: UUID

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
            }
        }

        struct AssessmentResponse: Decodable {
            let success: Bool
            let results: AssessmentResult?

            struct AssessmentResult: Decodable {
                let userId: String
                let score: Int
                let riskLevel: String
                let interventionTriggered: Bool

                enum CodingKeys: String, CodingKey {
                    case userId = "userId"
                    case score
                    case riskLevel
                    case interventionTriggered
                }
            }
        }

        let result: AssessmentResponse = try await supabase.functions
            .invoke(
                "run-risk-assessment",
                options: FunctionInvokeOptions(
                    body: AssessmentRequest(userId: uid)
                )
            )

        if result.success {
            // Refresh latest assessment
            try await fetchLatestAssessment()

            // Refresh interventions if one was triggered
            if result.results?.interventionTriggered == true {
                try await fetchPendingInterventions()
            }

            logger.info("Assessment triggered: score=\(result.results?.score ?? -1)")
        }
    }

    // MARK: - Interventions

    /// Fetch pending interventions for the user
    func fetchPendingInterventions() async throws {
        let uid = try userId
        let results: [Intervention] = try await supabase
            .from("interventions")
            .select()
            .eq("user_id", value: uid)
            .eq("response", value: "pending")
            .order("scheduled_at", ascending: false)
            .execute()
            .value

        pendingInterventions = results.filter { !$0.isExpired }
        logger.info("Fetched \(self.pendingInterventions.count) pending interventions")
    }

    /// Respond to an intervention
    func respondToIntervention(
        _ intervention: Intervention,
        response: InterventionResponse,
        actionTaken: String? = nil,
        currentMood: Int? = nil
    ) async throws {
        struct InterventionUpdate: Encodable {
            let response: String
            let respondedAt: Date
            let actionTaken: String?
            let moodBefore: Int?

            enum CodingKeys: String, CodingKey {
                case response
                case respondedAt = "responded_at"
                case actionTaken = "action_taken"
                case moodBefore = "mood_before"
            }
        }

        let update = InterventionUpdate(
            response: response.rawValue,
            respondedAt: Date(),
            actionTaken: actionTaken,
            moodBefore: currentMood
        )

        try await supabase
            .from("interventions")
            .update(update)
            .eq("id", value: intervention.id)
            .execute()

        // Remove from pending list
        pendingInterventions.removeAll { $0.id == intervention.id }

        // Track analytics
        Analytics.shared.track(.interventionResponse, properties: [
            "type": intervention.interventionType.rawValue,
            "response": response.rawValue,
            "action_taken": actionTaken ?? "none"
        ])

        logger.info("Responded to intervention \(intervention.id): \(response.rawValue)")
    }

    /// Rate an intervention as helpful or not
    func rateIntervention(_ interventionId: UUID, rating: Int, feedback: String? = nil) async throws {
        struct RatingUpdate: Encodable {
            let helpfulRating: Int
            let userFeedback: String?

            enum CodingKeys: String, CodingKey {
                case helpfulRating = "helpful_rating"
                case userFeedback = "user_feedback"
            }
        }

        let update = RatingUpdate(
            helpfulRating: rating,
            userFeedback: feedback
        )

        try await supabase
            .from("interventions")
            .update(update)
            .eq("id", value: interventionId)
            .execute()

        Analytics.shared.track(.interventionRated, properties: [
            "rating": rating,
            "has_feedback": feedback != nil
        ])

        logger.info("Rated intervention \(interventionId): \(rating)/5")
    }

    /// Record 24-hour follow-up mood
    func record24hMood(_ interventionId: UUID, mood: Int) async throws {
        struct MoodUpdate: Encodable {
            let mood24hAfter: Int

            enum CodingKeys: String, CodingKey {
                case mood24hAfter = "mood_24h_after"
            }
        }

        try await supabase
            .from("interventions")
            .update(MoodUpdate(mood24hAfter: mood))
            .eq("id", value: interventionId)
            .execute()

        logger.info("Recorded 24h follow-up mood for intervention \(interventionId): \(mood)")
    }

    // MARK: - Daily Signals

    /// Fetch recent daily signals for visualization
    func fetchDailySignals(days: Int = 7) async throws -> [DailySignals] {
        guard settings.predictionsEnabled else {
            return []
        }

        let uid = try userId
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let cutoff = formatter.string(from: cutoffDate)

        let results: [DailySignals] = try await supabase
            .from("daily_signals")
            .select()
            .eq("user_id", value: uid)
            .gte("signal_date", value: cutoff)
            .order("signal_date", ascending: true)
            .execute()
            .value

        return results
    }

    // MARK: - Data Deletion

    /// Delete all prediction data for user (privacy feature)
    func deleteAllPredictionData() async throws {
        let uid = try userId

        // Delete in order: interventions, risk_assessments, daily_signals, prediction_settings
        try await supabase
            .from("interventions")
            .delete()
            .eq("user_id", value: uid)
            .execute()

        try await supabase
            .from("risk_assessments")
            .delete()
            .eq("user_id", value: uid)
            .execute()

        try await supabase
            .from("daily_signals")
            .delete()
            .eq("user_id", value: uid)
            .execute()

        try await supabase
            .from("prediction_settings")
            .delete()
            .eq("user_id", value: uid)
            .execute()

        // Reset local state
        latestAssessment = nil
        pendingInterventions = []
        settings = .defaults

        Analytics.shared.track(.dataDeletionRequested, properties: [
            "feature": "predictions"
        ])

        logger.info("Deleted all prediction data for user")
    }

    // MARK: - Helpers

    /// Check if user has enough data for predictions
    func hasEnoughDataForPredictions() async throws -> Bool {
        let uid = try userId
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let cutoff = formatter.string(from: cutoffDate)

        // Simple struct for counting query results
        struct MoodId: Decodable {
            let id: UUID
        }

        // Query mood entries and count results
        let results: [MoodId] = try await supabase
            .from("moods")
            .select("id")
            .eq("user_id", value: uid)
            .gte("local_date", value: cutoff)
            .execute()
            .value

        let moodCount = results.count
        return moodCount >= 5 // Need at least 5 mood entries in past week
    }
}

// MARK: - Errors

enum PredictiveError: LocalizedError {
    case notAuthenticated
    case predictionsDisabled
    case insufficientData
    case assessmentFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to use predictions."
        case .predictionsDisabled:
            return "Predictions are not enabled. Enable them in settings."
        case .insufficientData:
            return "Not enough data for predictions. Keep using the app!"
        case .assessmentFailed(let reason):
            return "Assessment failed: \(reason)"
        }
    }
}

