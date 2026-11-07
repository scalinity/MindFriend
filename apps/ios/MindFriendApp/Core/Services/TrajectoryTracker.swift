//
//  TrajectoryTracker.swift
//  MindFriendApp
//

import Foundation
import Combine
import Supabase

@MainActor
final class TrajectoryTracker: ObservableObject {
    @Published private(set) var isTracking = false
    @Published private(set) var currentTrajectory: [TrajectoryPoint] = []

    // Kept for the existing dependency container. No measurement source is connected.
    init(supabase: SupabaseClient) {}

    /// Session duration and completion do not establish emotional or physiological change.
    func startTracking(sessionId: UUID, exerciseId: UUID, userId: UUID) {
        currentTrajectory = []
        isTracking = true
    }

    /// No supported observations are currently collected. Returning an empty trajectory
    /// makes efficacy unavailable without preventing exercise completion or writing data.
    func stopTracking() async throws -> [TrajectoryPoint] {
        isTracking = false
        currentTrajectory = []
        return []
    }
}
