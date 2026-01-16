import SwiftUI
import Supabase

/// ViewModel for the Family Hub view
@MainActor
final class FamilyHubViewModel: ObservableObject {
    @Published var familyGroup: FamilyWellnessGroup?
    @Published var familyMembers: [FamilyWellnessMember] = []
    @Published var activeChallenges: [FamilyChallenge] = []
    @Published var recentSessions: [TogetherSession] = []
    @Published var userRole: FamilyRole = .child

    @Published var isLoading = false
    @Published var error: String?

    func loadData(familyService: FamilyService, supabase: SupabaseClient) async {
        isLoading = true
        error = nil

        defer { isLoading = false }

        do {
            // Load family group
            if let family = try await familyService.fetchFamilyGroup() {
                await MainActor.run {
                    self.familyGroup = family
                }
            }

            // Load family members
            let members = try await familyService.fetchFamilyMembers()
            await MainActor.run {
                self.familyMembers = members
            }

            // Determine user role
            if let userId = supabase.auth.currentUser?.id,
               let currentMember = members.first(where: { $0.userId == userId }) {
                await MainActor.run {
                    self.userRole = currentMember.role
                }
            }

            // Load active challenges
            let challenges = try await familyService.fetchChallenges()
            let active = challenges.filter { $0.status == .active }
            await MainActor.run {
                self.activeChallenges = active
            }

            // Load recent sessions
            let sessions = try await familyService.fetchTogetherSessions()
            await MainActor.run {
                self.recentSessions = Array(sessions.prefix(10))
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }
}
