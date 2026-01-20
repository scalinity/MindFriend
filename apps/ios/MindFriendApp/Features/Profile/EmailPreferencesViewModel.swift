import Foundation
import Combine

@MainActor
final class EmailPreferencesViewModel: ObservableObject {
  @Published var emailPreferences: EmailPreferences?
  @Published var timezone: String = TimeZone.current.identifier
  @Published var preferredSendHour: Int = 9
  @Published var weeklySummary: Bool = true
  @Published var streakCelebration: Bool = true
  @Published var achievementUnlock: Bool = true
  @Published var lapsedNudge: Bool = true
  @Published var monthlyReport: Bool = true
  @Published var isLoading: Bool = false
  @Published var errorMessage: String?
  @Published var successMessage: String?

  private let supabaseDataService: SupabaseDataService
  private var cancellables = Set<AnyCancellable>()

  init(supabaseDataService: SupabaseDataService) {
    self.supabaseDataService = supabaseDataService
  }

  // MARK: - Public Methods

  func loadEmailPreferences() async {
    isLoading = true
    errorMessage = nil

    do {
      let currentUser = try await supabaseDataService.getCurrentUser()
      guard let userId = currentUser?.id else {
        errorMessage = "User not found"
        isLoading = false
        return
      }

      let prefs: EmailPreferences = try await supabaseDataService.fetchSingle(
        from: "email_preferences",
        filters: [("user_id", "eq", userId)]
      )

      await MainActor.run {
        self.emailPreferences = prefs
        self.timezone = prefs.timezone
        self.preferredSendHour = prefs.preferredSendHour
        self.weeklySummary = prefs.weeklySummary
        self.streakCelebration = prefs.streakCelebration
        self.achievementUnlock = prefs.achievementUnlock
        self.lapsedNudge = prefs.lapsedNudge
        self.monthlyReport = prefs.monthlyReport
        self.isLoading = false
      }
    } catch {
      errorMessage = "Failed to load email preferences: \(error.localizedDescription)"
      isLoading = false
    }
  }

  func saveEmailPreferences() async {
    isLoading = true
    errorMessage = nil
    successMessage = nil

    do {
      let currentUser = try await supabaseDataService.getCurrentUser()
      guard let userId = currentUser?.id else {
        errorMessage = "User not found"
        isLoading = false
        return
      }

      let updateRequest = UpdateEmailPreferencesRequest(
        timezone: timezone,
        preferredSendHour: preferredSendHour,
        weeklySummary: weeklySummary,
        streakCelebration: streakCelebration,
        achievementUnlock: achievementUnlock,
        lapsedNudge: lapsedNudge,
        monthlyReport: monthlyReport
      )

      try await supabaseDataService.update(
        table: "email_preferences",
        filters: [("user_id", "eq", userId)],
        values: updateRequest
      )

      successMessage = "Email preferences saved"
      await loadEmailPreferences()
    } catch {
      errorMessage = "Failed to save email preferences: \(error.localizedDescription)"
      isLoading = false
    }
  }

  func unsubscribeFromAllEmails() async {
    isLoading = true
    errorMessage = nil

    do {
      let currentUser = try await supabaseDataService.getCurrentUser()
      guard let userId = currentUser?.id else {
        errorMessage = "User not found"
        isLoading = false
        return
      }

      let updateData: [String: Any] = [
        "unsubscribed_at": ISO8601DateFormatter().string(from: Date()),
        "unsubscribe_reason": "User requested unsubscribe",
      ]

      try await supabaseDataService.updateRaw(
        table: "email_preferences",
        filters: [("user_id", "eq", userId)],
        values: updateData
      )

      successMessage = "You have been unsubscribed from all emails"
      await loadEmailPreferences()
    } catch {
      errorMessage = "Failed to unsubscribe: \(error.localizedDescription)"
      isLoading = false
    }
  }

  func resubscribe() async {
    isLoading = true
    errorMessage = nil

    do {
      let currentUser = try await supabaseDataService.getCurrentUser()
      guard let userId = currentUser?.id else {
        errorMessage = "User not found"
        isLoading = false
        return
      }

      let updateData: [String: Any] = [
        "unsubscribed_at": NSNull(),
        "unsubscribe_reason": NSNull(),
      ]

      try await supabaseDataService.updateRaw(
        table: "email_preferences",
        filters: [("user_id", "eq", userId)],
        values: updateData
      )

      successMessage = "You have been resubscribed"
      await loadEmailPreferences()
    } catch {
      errorMessage = "Failed to resubscribe: \(error.localizedDescription)"
      isLoading = false
    }
  }

  func clearMessages() {
    errorMessage = nil
    successMessage = nil
  }
}
