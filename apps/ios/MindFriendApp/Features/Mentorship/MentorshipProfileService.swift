import Foundation
import Combine

/// Manages user's mentorship profile
@MainActor
final class MentorshipProfileService: ObservableObject {
    @Published var profile: MentorshipProfile?
    @Published var isLoading = false
    @Published var error: Error?

    private let dataService: MentorshipDataService

    init(dataService: MentorshipDataService) {
        self.dataService = dataService
    }

    // MARK: - Reset

    func reset() {
        profile = nil
        isLoading = false
        error = nil
    }

    // MARK: - Public Methods

    /// Load user's mentorship profile
    func loadProfile() async {
        isLoading = true
        error = nil

        do {
            profile = try await dataService.fetchOrCreateProfile()
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Toggle mentor availability
    func toggleMentorAvailability(_ available: Bool) async {
        isLoading = true
        error = nil

        do {
            _ = try await dataService.updateProfile(isMentorAvailable: available)
            if var currentProfile = profile {
                currentProfile.isMentorAvailable = available
                profile = currentProfile
            }
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Update expertise areas
    func updateExpertiseAreas(_ areas: [String]) async {
        isLoading = true
        error = nil

        do {
            profile = try await dataService.updateProfile(expertiseAreas: areas)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Update seeking areas
    func updateSeekingAreas(_ areas: [String]) async {
        isLoading = true
        error = nil

        do {
            profile = try await dataService.updateProfile(seekingAreas: areas)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Update mentor bio
    func updateBio(_ bio: String) async {
        isLoading = true
        error = nil

        do {
            profile = try await dataService.updateProfile(bio: bio)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Update availability hours per week
    func updateAvailabilityHours(_ hours: Int) async {
        isLoading = true
        error = nil

        do {
            profile = try await dataService.updateProfile(availabilityHoursWeek: hours)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Update languages
    func updateLanguages(_ languages: [String]) async {
        isLoading = true
        error = nil

        do {
            profile = try await dataService.updateProfile(languages: languages)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Update multiple profile fields at once
    func updateProfile(
        isMentorAvailable: Bool? = nil,
        expertiseAreas: [String]? = nil,
        seekingAreas: [String]? = nil,
        bio: String? = nil,
        availabilityHoursWeek: Int? = nil,
        languages: [String]? = nil
    ) async {
        isLoading = true
        error = nil

        do {
            profile = try await dataService.updateProfile(
                isMentorAvailable: isMentorAvailable,
                expertiseAreas: expertiseAreas,
                seekingAreas: seekingAreas,
                bio: bio,
                availabilityHoursWeek: availabilityHoursWeek,
                languages: languages
            )
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Computed Properties

    var isMentorAvailable: Bool {
        profile?.isMentorAvailable ?? false
    }

    var expertiseAreas: [String] {
        profile?.expertiseAreas ?? []
    }

    var seekingAreas: [String] {
        profile?.seekingAreas ?? []
    }

    var bio: String {
        profile?.bio ?? ""
    }

    var availabilityHoursWeek: Int {
        profile?.availabilityHoursWeek ?? 0
    }

    var languages: [String] {
        profile?.languages ?? ["en"]
    }

    var timezone: String {
        profile?.timezone ?? TimeZone.current.identifier
    }

    var isVerified: Bool {
        profile?.isVerified ?? false
    }

    var mentorAlias: String? {
        profile?.mentorAlias
    }

    var hasCompleteProfile: Bool {
        guard let profile = profile else { return false }
        
        if profile.isMentorAvailable {
            // Mentor profile must have expertise and availability
            return !profile.expertiseAreas.isEmpty &&
                   profile.availabilityHoursWeek > 0 &&
                   profile.bio?.isEmpty == false
        } else {
            // Mentee profile can be minimal
            return true
        }
    }

    var canBecomeMentor: Bool {
        guard let profile = profile else { return false }
        return !profile.expertiseAreas.isEmpty &&
               profile.availabilityHoursWeek > 0 &&
               profile.bio?.isEmpty == false
    }

    // MARK: - Validation

    /// Validate expertise areas
    func isValidExpertiseAreas(_ areas: [String]) -> Bool {
        let validAreas = [
            "anxiety",
            "depression",
            "stress",
            "sleep",
            "relationships",
            "work-life-balance",
            "self-esteem",
            "grief",
            "mindfulness",
            "coping-skills",
            "emotional-regulation",
            "career-guidance",
            "personal-growth",
            "trauma-recovery",
            "wellness",
        ]

        return areas.allSatisfy { validAreas.contains($0) }
    }

    /// Validate bio length
    func isValidBio(_ bio: String) -> Bool {
        let trimmed = bio.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 20 && trimmed.count <= 500
    }

    /// Validate availability hours
    func isValidAvailabilityHours(_ hours: Int) -> Bool {
        hours >= 1 && hours <= 168  // 24 * 7 hours per week
    }

    /// Validate languages
    func isValidLanguages(_ languages: [String]) -> Bool {
        let validLanguages = ["en", "es", "fr", "de", "it", "pt", "ja", "ko", "zh", "ru", "ar", "hi"]
        return !languages.isEmpty && languages.allSatisfy { validLanguages.contains($0) }
    }
}
