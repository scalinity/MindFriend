//
//  EfficacyBasedRecommender.swift
//  MindFriendApp
//
//  Intervention Efficacy Engine - Recommendation Service
//  Provides context-aware exercise recommendations based on efficacy profiles
//

import Foundation
import Supabase

@MainActor
final class EfficacyBasedRecommender {
    private let supabase: SupabaseClient
    
    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }
    
    /// Get personalized exercise recommendations based on current context
    func getRecommendations(
        currentState: String,
        currentEmotion: String,
        timeOfDay: String,
        limit: Int = 5
    ) async throws -> [ExerciseRecommendation] {
        
        // Response type
        struct RecommendationsResponse: Decodable {
            let recommendations: [RecommendationDTO]
            
            struct RecommendationDTO: Decodable {
                let exerciseId: String
                let exerciseName: String
                let exerciseType: String
                let duration: Int
                let predictedEfficacy: Double
                let confidence: Double
                let completionCount: Int
                let reason: String
                let trend: String?
            }
        }
        
        // Request type
        struct RecommendationRequest: Encodable {
            let state: String
            let emotion: String
            let timeOfDay: String
            let limit: Int
        }
        
        let requestBody = RecommendationRequest(
            state: currentState,
            emotion: currentEmotion,
            timeOfDay: timeOfDay,
            limit: limit
        )
        
        let response: RecommendationsResponse = try await supabase.functions.invoke(
            "get-recommendations",
            options: FunctionInvokeOptions(
                body: requestBody
            )
        )
        
        return response.recommendations.compactMap { dto in
            return ExerciseRecommendation(
                exerciseId: UUID(uuidString: dto.exerciseId) ?? UUID(),
                exerciseName: dto.exerciseName,
                exerciseType: dto.exerciseType,
                duration: dto.duration,
                predictedEfficacy: dto.predictedEfficacy,
                confidence: dto.confidence,
                completionCount: dto.completionCount,
                reason: dto.reason,
                trend: dto.trend.flatMap { UserEfficacyProfile.EfficacyTrend(rawValue: $0) }
            )
        }
    }
}
