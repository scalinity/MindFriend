import Foundation
import Supabase

// MARK: - Request Types for Edge Functions

private struct ContributeWisdomRequest: Encodable {
    let contributionType: String
    let data: ContributionData

    struct ContributionData: Encodable {
        var moodScore: Int?
        var timeOfDay: String?
        var emotion: String?
        var exerciseType: String?
        var effectivenessRating: Int?
        var pathwayType: String?
        var phaseNumber: Int?
    }
}

private struct WisdomRecommendationsRequest: Encodable {
    let contextTags: [String]
    let limit: Int
    var moodScore: Int?
    var emotion: String?
    var goals: [String]?
    var challenges: [String]?
}

private struct SubmitStrategyRequest: Encodable {
    let category: String
    let strategyText: String
    var context: String?
}

private struct VoteStrategyRequest: Encodable {
    let strategyId: String
    let voteType: String
}

/// Service for Community Wisdom Engine features
/// Handles consent management, contributions, recommendations, and strategies
@MainActor
final class WisdomService: ObservableObject {
    private let supabase: SupabaseClient
    
    // MARK: - Published State
    
    @Published var consent: WisdomConsent?
    @Published var recommendations: [InsightResponse] = []
    @Published var strategies: [CommunityStrategy] = []
    @Published var notAloneInsight: InsightResponse?
    @Published var isLoading = false
    @Published private(set) var error: WisdomError?
    
    // MARK: - Private State
    
    private var consentFetchTask: Task<Void, Never>?
    private var lastContributionTime: Date?
    private let minContributionInterval: TimeInterval = 60 // 1 minute cooldown
    
    // MARK: - Initialization
    
    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }
    
    // MARK: - Error Management
    
    /// Clears the current error state
    func clearError() {
        error = nil
    }
    
    // MARK: - Consent Management
    
    /// Fetches the user's wisdom consent preferences
    func fetchConsent() async throws {
        // Cancel any existing fetch
        consentFetchTask?.cancel()
        
        clearError()
        
        let session = try await supabase.auth.session
        let userId = session.user.id
        
        do {
            consent = try await supabase
                .from("wisdom_consent")
                .select()
                .eq("user_id", value: userId)
                .single()
                .execute()
                .value
        } catch {
            // No consent record yet - this is expected for new users
            consent = nil
        }
    }
    
    /// Updates user's consent preferences
    /// - Parameters:
    ///   - contribute: Whether to contribute anonymous data
    ///   - receive: Whether to receive recommendations
    func updateConsent(contribute: Bool, receive: Bool) async throws {
        clearError()
        
        let session = try await supabase.auth.session
        let userId = session.user.id
        
        let record: [String: AnyEncodable] = [
            "user_id": AnyEncodable(userId),
            "contribute_anonymous_data": AnyEncodable(contribute),
            "receive_recommendations": AnyEncodable(receive)
        ]
        
        do {
            consent = try await supabase
                .from("wisdom_consent")
                .upsert(record)
                .select()
                .single()
                .execute()
                .value
        } catch let updateError {
            self.error = .fetchFailed("Failed to update consent")
            throw updateError
        }
    }
    
    /// Check if user has consent to contribute
    var canContribute: Bool {
        consent?.contributeAnonymousData ?? false
    }
    
    /// Check if user has consent to receive recommendations
    var canReceiveRecommendations: Bool {
        consent?.receiveRecommendations ?? false
    }
    
    // MARK: - Contributions
    
    /// Contribute mood pattern data anonymously
    /// - Parameters:
    ///   - moodScore: Mood score 1-5
    ///   - emotion: Optional emotion label
    func contributeMoodPattern(moodScore: Int, emotion: String? = nil) async {
        guard canContribute else { return }
        guard shouldAllowContribution() else { return }

        // Validate inputs
        guard moodScore >= 1 && moodScore <= 5 else { return }

        let timeOfDay = getTimeOfDay()
        var sanitizedEmotion: String?
        if let emotion = emotion, !emotion.isEmpty, emotion.count <= 30 {
            // Sanitize emotion input
            let sanitized = emotion.replacingOccurrences(of: "[^a-zA-Z]", with: "", options: .regularExpression)
            if !sanitized.isEmpty {
                sanitizedEmotion = sanitized.lowercased()
            }
        }

        let data = ContributeWisdomRequest.ContributionData(
            moodScore: moodScore,
            timeOfDay: timeOfDay,
            emotion: sanitizedEmotion
        )

        await contribute(type: .moodPattern, data: data)
    }
    
    /// Contribute exercise effectiveness data anonymously
    /// - Parameters:
    ///   - exerciseType: Type of exercise
    ///   - rating: Effectiveness rating 1-5
    func contributeExerciseEffectiveness(exerciseType: String, rating: Int) async {
        guard canContribute else { return }
        guard shouldAllowContribution() else { return }

        // Validate inputs
        guard rating >= 1 && rating <= 5 else { return }
        guard !exerciseType.isEmpty && exerciseType.count <= 50 else { return }

        let data = ContributeWisdomRequest.ContributionData(
            exerciseType: exerciseType,
            effectivenessRating: rating
        )

        await contribute(type: .exerciseEffectiveness, data: data)
    }

    /// Contribute pathway progress data anonymously
    /// - Parameters:
    ///   - pathwayType: Type of pathway
    ///   - phaseNumber: Current phase number
    func contributePathwayProgress(pathwayType: String, phaseNumber: Int) async {
        guard canContribute else { return }
        guard shouldAllowContribution() else { return }

        // Validate inputs
        guard phaseNumber >= 1 && phaseNumber <= 10 else { return }
        guard !pathwayType.isEmpty && pathwayType.count <= 50 else { return }

        let data = ContributeWisdomRequest.ContributionData(
            pathwayType: pathwayType,
            phaseNumber: phaseNumber
        )

        await contribute(type: .pathwayProgress, data: data)
    }
    
    /// Check if we should allow a contribution (rate limiting)
    private func shouldAllowContribution() -> Bool {
        if let lastTime = lastContributionTime {
            guard Date().timeIntervalSince(lastTime) >= minContributionInterval else {
                return false
            }
        }
        return true
    }
    
    /// Generic contribution method
    private func contribute(type: ContributionType, data: ContributeWisdomRequest.ContributionData) async {
        do {
            let body = ContributeWisdomRequest(
                contributionType: type.rawValue,
                data: data
            )

            _ = try await supabase.functions.invoke(
                "contribute-wisdom",
                options: .init(body: body)
            )

            // Update rate limiting timestamp on success
            lastContributionTime = Date()
        } catch {
            // Log internally but don't expose to user - contributions are non-critical
            #if DEBUG
            print("Wisdom contribution failed: \(error.localizedDescription)")
            #endif
        }
    }
    
    // MARK: - Recommendations
    
    /// Fetches personalized recommendations based on context
    /// - Parameters:
    ///   - moodScore: Current mood score
    ///   - emotion: Current emotion
    ///   - goals: User's goals
    ///   - challenges: User's challenges
    func fetchRecommendations(
        moodScore: Int? = nil,
        emotion: String? = nil,
        goals: [String] = [],
        challenges: [String] = []
    ) async throws {
        guard canReceiveRecommendations else {
            recommendations = []
            notAloneInsight = nil
            return
        }

        clearError()
        isLoading = true
        defer { isLoading = false }

        var validatedMoodScore: Int?
        if let moodScore = moodScore, moodScore >= 1, moodScore <= 5 {
            validatedMoodScore = moodScore
        }

        var validatedEmotion: String?
        if let emotion = emotion, !emotion.isEmpty, emotion.count <= 30 {
            validatedEmotion = emotion
        }

        let body = WisdomRecommendationsRequest(
            contextTags: [],
            limit: 5,
            moodScore: validatedMoodScore,
            emotion: validatedEmotion,
            goals: goals.isEmpty ? nil : Array(goals.prefix(5)),
            challenges: challenges.isEmpty ? nil : Array(challenges.prefix(5))
        )

        do {
            let result: WisdomRecommendationsResponse = try await supabase.functions.invoke(
                "get-wisdom-recommendations",
                options: .init(body: body)
            )

            recommendations = result.insights
            notAloneInsight = result.notAloneInsight
        } catch {
            self.error = .fetchFailed("Unable to load recommendations")
            recommendations = []
            notAloneInsight = nil
            throw error
        }
    }
    
    /// Records feedback on a recommendation
    /// - Parameters:
    ///   - recommendationId: ID of the recommendation
    ///   - helpful: Whether it was helpful
    func recordFeedback(recommendationId: UUID, helpful: Bool) async throws {
        clearError()
        
        do {
            try await supabase
                .from("wisdom_recommendations")
                .update(["helpful": helpful])
                .eq("id", value: recommendationId)
                .execute()
        } catch {
            self.error = .fetchFailed("Unable to record feedback")
            throw error
        }
    }
    
    // MARK: - Strategies
    
    /// Fetches approved strategies for a category
    /// - Parameter category: Strategy category to fetch
    func fetchStrategies(category: StrategyCategory) async throws {
        clearError()
        isLoading = true
        defer { isLoading = false }
        
        do {
            let session = try await supabase.auth.session
            let userId = session.user.id
            
            // Fetch strategies
            strategies = try await supabase
                .from("community_strategies")
                .select()
                .eq("category", value: category.rawValue)
                .eq("status", value: "approved")
                .order("helpful_count", ascending: false)
                .limit(20)
                .execute()
                .value
            
            // Fetch user's votes for these strategies
            guard !strategies.isEmpty else { return }
            
            let strategyIds = strategies.map { $0.id }
            let votes: [StrategyVote] = try await supabase
                .from("strategy_votes")
                .select()
                .eq("user_id", value: userId)
                .in("strategy_id", values: strategyIds)
                .execute()
                .value
            
            // Apply votes to strategies (safe mutation)
            for i in strategies.indices {
                if let vote = votes.first(where: { $0.strategyId == strategies[i].id }) {
                    strategies[i].myVote = vote.voteType
                }
            }
        } catch {
            self.error = .fetchFailed("Unable to load strategies")
            strategies = []
            throw error
        }
    }

    /// Submits a new coping strategy
    /// - Parameters:
    ///   - category: Strategy category
    ///   - strategyText: The strategy content
    ///   - context: Optional context (e.g., "When feeling...")
    /// - Returns: Strategy ID if successful
    @discardableResult
    func submitStrategy(
        category: StrategyCategory,
        strategyText: String,
        context: String? = nil
    ) async throws -> UUID? {
        var body = SubmitStrategyRequest(
            category: category.rawValue,
            strategyText: strategyText
        )
        body.context = context

        let result: SubmitStrategyResponse = try await supabase.functions.invoke(
            "submit-strategy",
            options: .init(body: body)
        )

        if result.success {
            return result.strategyId
        } else {
            throw WisdomError.submissionFailed(result.message ?? "Unknown error")
        }
    }

    /// Votes on a strategy
    /// - Parameters:
    ///   - strategyId: ID of the strategy
    ///   - voteType: Vote type (helpful or not_helpful)
    func voteStrategy(strategyId: UUID, voteType: VoteType) async throws {
        let body = VoteStrategyRequest(
            strategyId: strategyId.uuidString,
            voteType: voteType.rawValue
        )

        let result: VoteStrategyResponse = try await supabase.functions.invoke(
            "vote-strategy",
            options: .init(body: body)
        )

        if result.success, let stats = result.strategy {
            // Update local strategy with new counts
            if let index = strategies.firstIndex(where: { $0.id == strategyId }) {
                strategies[index].helpfulCount = stats.helpfulCount
                strategies[index].notHelpfulCount = stats.notHelpfulCount
                strategies[index].myVote = voteType
            }
        } else {
            throw WisdomError.voteFailed(result.error ?? "Unknown error")
        }
    }

    // MARK: - Helpers

    private func getTimeOfDay() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<21: return "evening"
        default: return "night"
        }
    }
}

// MARK: - Wisdom Errors

enum WisdomError: LocalizedError, Equatable {
    case consentRequired
    case submissionFailed(String)
    case voteFailed(String)
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .consentRequired:
            return "Please enable wisdom features in Settings > Community Wisdom Privacy"
        case .submissionFailed(let message):
            return "Failed to submit strategy: \(message)"
        case .voteFailed(let message):
            return "Failed to record vote: \(message)"
        case .fetchFailed(let message):
            return "Failed to fetch data: \(message)"
        }
    }
}

// NOTE: AnyEncodable, DynamicCodingKey, and AnyEncodableValue are defined in SupabaseAuthService.swift
