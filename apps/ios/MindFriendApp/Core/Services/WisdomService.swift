import Foundation
import Supabase

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
        var data: [String: Any] = [
            "moodScore": moodScore,
            "timeOfDay": timeOfDay
        ]
        if let emotion = emotion, !emotion.isEmpty, emotion.count <= 30 {
            // Sanitize emotion input
            let sanitized = emotion.replacingOccurrences(of: "[^a-zA-Z]", with: "", options: .regularExpression)
            if !sanitized.isEmpty {
                data["emotion"] = sanitized.lowercased()
            }
        }
        
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
        
        let data: [String: Any] = [
            "exerciseType": exerciseType,
            "effectivenessRating": rating
        ]
        
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
        
        let data: [String: Any] = [
            "pathwayType": pathwayType,
            "phaseNumber": phaseNumber
        ]
        
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
    private func contribute(type: ContributionType, data: [String: Any]) async {
        do {
            let body: [String: Any] = [
                "contributionType": type.rawValue,
                "data": data
            ]
            
            _ = try await supabase.functions.invoke(
                "contribute-wisdom",
                options: .init(body: AnyEncodable(body))
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
        
        var body: [String: Any] = [
            "contextTags": [] as [String],
            "limit": 5
        ]
        
        if let moodScore = moodScore, moodScore >= 1, moodScore <= 5 {
            body["moodScore"] = moodScore
        }
        if let emotion = emotion, !emotion.isEmpty, emotion.count <= 30 {
            body["emotion"] = emotion
        }
        if !goals.isEmpty {
            body["goals"] = Array(goals.prefix(5))
        }
        if !challenges.isEmpty {
            body["challenges"] = Array(challenges.prefix(5))
        }
        
        do {
            let response = try await supabase.functions.invoke(
                "get-wisdom-recommendations",
                options: .init(body: AnyEncodable(body))
            )
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let result = try decoder.decode(WisdomRecommendationsResponse.self, from: response.data)
            
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
        var body: [String: Any] = [
            "category": category.rawValue,
            "strategyText": strategyText
        ]

        if let context = context {
            body["context"] = context
        }

        let response = try await supabase.functions.invoke(
            "submit-strategy",
            options: .init(body: AnyEncodable(body))
        )

        let decoder = JSONDecoder()
        let result = try decoder.decode(SubmitStrategyResponse.self, from: response.data)

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
        let body: [String: Any] = [
            "strategyId": strategyId.uuidString,
            "voteType": voteType.rawValue
        ]

        let response = try await supabase.functions.invoke(
            "vote-strategy",
            options: .init(body: AnyEncodable(body))
        )

        let decoder = JSONDecoder()
        let result = try decoder.decode(VoteStrategyResponse.self, from: response.data)

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

enum WisdomError: LocalizedError {
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
