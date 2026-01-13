import SwiftUI
import Combine

/// Dependency injection container for all app services
@MainActor
final class DependencyContainer: ObservableObject {
    // MARK: - Core Services
    let apiClient: APIClient
    let keychainManager: KeychainManager
    let sessionManager: SessionManager

    // MARK: - Feature Services
    lazy var authService: AuthService = {
        AuthService(apiClient: apiClient, keychainManager: keychainManager)
    }()

    lazy var userService: UserService = {
        UserService(apiClient: apiClient)
    }()

    lazy var questService: QuestService = {
        QuestService(apiClient: apiClient)
    }()

    lazy var moodService: MoodService = {
        MoodService(apiClient: apiClient)
    }()

    lazy var chatService: ChatService = {
        ChatService(apiClient: apiClient)
    }()

    lazy var circleService: CircleService = {
        CircleService(apiClient: apiClient)
    }()

    lazy var exerciseService: ExerciseService = {
        ExerciseService(apiClient: apiClient)
    }()

    lazy var billingService: BillingService = {
        BillingService(apiClient: apiClient)
    }()

    // MARK: - Supabase Services
    lazy var supabaseAuthService: SupabaseAuthService = {
        SupabaseAuthService()
    }()

    lazy var supabaseDataService: SupabaseDataService = {
        SupabaseDataService(authService: supabaseAuthService)
    }()

    // MARK: - Configuration
    private let baseURL: URL

    // MARK: - Initialization

    init() {
        // Load configuration
        #if DEBUG
        self.baseURL = URL(string: "http://localhost:3000")!
        #else
        self.baseURL = URL(string: "https://api.mindfriend.app")!
        #endif

        // Initialize core services
        self.keychainManager = KeychainManager()
        self.apiClient = APIClient(baseURL: baseURL)
        self.sessionManager = SessionManager(
            apiClient: apiClient,
            keychainManager: keychainManager
        )

        // Configure API client with session manager for token refresh
        Task { await self.apiClient.setSessionManager(sessionManager) }
    }
}

