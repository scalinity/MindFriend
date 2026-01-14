import SwiftUI
import Combine
import Supabase

/// Dependency injection container for all app services
@MainActor
final class DependencyContainer: ObservableObject {
    let supabaseClient: SupabaseClient = supabase

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

    // MARK: - Initialization

    init() {
        // All services are lazy-initialized using Supabase
    }

    // MARK: - Preview Support

    /// Preview instance for SwiftUI previews
    static var preview: DependencyContainer {
        DependencyContainer()
    }
}
