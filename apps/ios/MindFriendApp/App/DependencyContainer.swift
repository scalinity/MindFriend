import SwiftUI
import Combine

/// Dependency injection container for all app services
@MainActor
final class DependencyContainer: ObservableObject {
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

    // MARK: - Initialization

    init() {
        // All services are lazy-initialized using Supabase
    }
}
