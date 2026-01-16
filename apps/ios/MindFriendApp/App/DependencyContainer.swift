import SwiftUI
import Combine
import Supabase

/// Dependency injection container for all app services
@MainActor
final class DependencyContainer: ObservableObject {
    private(set) lazy var supabaseClient: SupabaseClient = supabase

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

    lazy var grokVoiceService: GrokVoiceService = {
        GrokVoiceService(supabase: supabaseClient)
    }()

    lazy var liveService: LiveService = {
        LiveService()
    }()

    lazy var creativeExpressionService: CreativeExpressionService = {
        CreativeExpressionService()
    }()

    lazy var personalizationService: PersonalizationService = {
        PersonalizationService(supabase: supabaseClient)
    }()

    lazy var accessibilityService: AccessibilityService = {
        AccessibilityService(supabase: supabaseClient)
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
    // lazy var achievementService: AchievementService
    // lazy var audioPlayerService: AudioPlayerService
    // lazy var audioContentService: AudioContentService

    // MARK: - Initialization

    // MARK: - Shared Instance

    /// Shared singleton instance for the app
    static let shared = DependencyContainer()

    /// Convenience accessor for Supabase client
    var supabase: SupabaseClient { supabaseClient }

    // MARK: - Preview Support

    /// Preview instance for SwiftUI previews
    static var preview: DependencyContainer {
        DependencyContainer()
    }
}
