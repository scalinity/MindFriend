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
        
        // Call get-recommendations Edge Function
        let requestBody: [String: Any] = [
            "state": currentState,
            "emotion": currentEmotion,
            "timeOfDay": timeOfDay,
            "limit": limit
        ]
        
        let response = try await supabase.functions.invoke(
            "get-recommendations",
            options: FunctionInvokeOptions(
                body: requestBody
            )
        )
        
        // Parse response
        guard let data = response.data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recommendationsArray = json["recommendations"] as? [[String: Any]] else {
            return []
        }
        
        return recommendationsArray.compactMap { dict in
            guard let exerciseId = dict["exerciseId"] as? String,
                  let exerciseName = dict["exerciseName"] as? String,
                  let exerciseType = dict["exerciseType"] as? String,
                  let duration = dict["duration"] as? Int,
                  let predictedEfficacy = dict["predictedEfficacy"] as? Double,
                  let confidence = dict["confidence"] as? Double,
                  let completionCount = dict["completionCount"] as? Int,
                  let reason = dict["reason"] as? String else {
                return nil
            }
            
            let trend: UserEfficacyProfile.EfficacyTrend? = {
                guard let trendString = dict["trend"] as? String else { return nil }
                return UserEfficacyProfile.EfficacyTrend(rawValue: trendString)
            }()
            
            return ExerciseRecommendation(
                exerciseId: UUID(uuidString: exerciseId) ?? UUID(),
                exerciseName: exerciseName,
                exerciseType: exerciseType,
                duration: duration,
                predictedEfficacy: predictedEfficacy,
                confidence: confidence,
                completionCount: completionCount,
                reason: reason,
                trend: trend
            )
        }
    }
}
