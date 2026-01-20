import SwiftUI
import Combine
import Supabase

// MARK: - Global Supabase Client Reference
// We capture the global `supabase` constant here BEFORE defining DependencyContainer,
// which has a computed property also named `supabase`. This avoids shadowing issues.
private let _globalSupabaseClient: SupabaseClient = supabase

/// Dependency injection container for all app services
@MainActor
final class DependencyContainer: ObservableObject {
    /// Reference to the global Supabase client (defined in SupabaseClient.swift)
    /// Captured via _globalSupabaseClient to avoid circular reference issues.
    let supabaseClient: SupabaseClient = _globalSupabaseClient

    // MARK: - Supabase Services
    lazy var supabaseAuthService: SupabaseAuthService = {
        SupabaseAuthService()
    }()

    lazy var supabaseDataService: SupabaseDataService = {
        SupabaseDataService(authService: supabaseAuthService)
    }()

    // MARK: - Feature Services
    lazy var chatService: ChatService = {
        ChatService(dataService: supabaseDataService)
    }()

    lazy var billingService: BillingService = {
        BillingService(authService: supabaseAuthService)
    }()

    // TODO: Fix GrokVoiceService compilation errors (inputNode, isPlayerPlaying references)
    // lazy var grokVoiceService: GrokVoiceService = {
    //     GrokVoiceService(supabase: self.supabaseClient)
    // }()

    lazy var liveService: LiveService = {
        LiveService()
    }()

    lazy var creativeExpressionService: CreativeExpressionService = {
        CreativeExpressionService()
    }()

    lazy var personalizationService: PersonalizationService = {
        PersonalizationService(supabase: self.supabaseClient)
    }()

    lazy var accessibilityService: AccessibilityService = {
        AccessibilityService(supabase: self.supabaseClient)
    }()

    lazy var actionPlanService: ActionPlanService = {
        ActionPlanService(authService: supabaseAuthService, supabase: supabaseClient)
    }()

    lazy var privacyLockManager: PrivacyLockManager = {
        PrivacyLockManager.shared
    }()

    lazy var achievementService: AchievementService = {
        AchievementService(supabase: self.supabaseClient)
    }()

    lazy var photoMoodService: PhotoMoodService = {
        PhotoMoodService(supabase: self.supabaseClient)
    }()

    // MARK: - Medication Services
    lazy var medicationRepository: MedicationRepository = {
        SupabaseMedicationRepository(supabase: supabaseClient)
    }()

    lazy var medicationLogRepository: MedicationLogRepository = {
        SupabaseMedicationLogRepository(supabase: supabaseClient)
    }()

    lazy var notificationScheduler: NotificationScheduler = {
        NotificationScheduler()
    }()

    lazy var adherenceCalculator: AdherenceCalculator = {
        AdherenceCalculator()
    }()

    lazy var medicationService: MedicationService = {
        MedicationService(
            medicationRepository: medicationRepository,
            logRepository: medicationLogRepository,
            notificationScheduler: notificationScheduler,
            adherenceCalculator: adherenceCalculator
        )
    }()

    // TODO: Add CreatorService and FamilyService to Xcode project target
    // These services exist on disk but need to be added to the project's pbxproj file
    // lazy var creatorService: CreatorService = {
    //     CreatorService(supabase: supabaseClient)
    // }()
    //
    // lazy var familyService: FamilyService = {
    //     FamilyService(supabase: supabaseClient)
    // }()

    // MARK: - Incomplete Feature Services (TODO: Add when features are ready)
    // lazy var microMomentsService: MicroMomentsService
    // lazy var peerSupportService: PeerSupportService
    // lazy var audioPlayerService: AudioPlayerService
    // lazy var audioContentService: AudioContentService

    // MARK: - Initialization

    // MARK: - Shared Instance

    /// Shared singleton instance for the app
    static let shared = DependencyContainer()

    /// Convenience accessor for Supabase client (alias for supabaseClient)
    var supabase: SupabaseClient { supabaseClient }

    // MARK: - Preview Support


    /// Preview instance for SwiftUI previews
    static var preview: DependencyContainer {
        DependencyContainer()
    }
}
