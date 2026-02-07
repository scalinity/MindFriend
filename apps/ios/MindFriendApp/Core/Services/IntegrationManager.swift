import Foundation
import Combine
import OSLog
import Supabase
import UIKit

// MARK: - Supporting Types

struct IntegrationConnection {
    let type: IntegrationType
    var status: Status
    var lastSync: Date?
    var error: String?

    enum Status: String, Codable {
        case disconnected
        case connecting
        case connected
        case error
        case syncing
    }
}

enum IntegrationSyncStatus {
    case idle
    case syncing(IntegrationType?)
    case completed(IntegrationType)
    case failed(IntegrationType, Error)
}

enum IntegrationError: LocalizedError {
    case notConnected
    case syncFailed(String)
    case unauthorized
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Integration not connected"
        case .syncFailed(let message):
            return "Sync failed: \(message)"
        case .unauthorized:
            return "Authorization required"
        case .rateLimited:
            return "Rate limit exceeded"
        }
    }
}

/// Main orchestrator for all third-party integrations
/// Manages connection lifecycle, sync scheduling, and unified error handling
@MainActor
final class IntegrationManager: ObservableObject {
    static let shared = IntegrationManager()

    private let logger = Logger(subsystem: "com.mindfriend", category: "IntegrationManager")
    private let oauthHandler: OAuthHandler
    private let supabaseClient: SupabaseClient

    // MARK: - Published State

    @Published private(set) var connections: [IntegrationType: IntegrationConnection] = [:]
    @Published private(set) var syncStatus: IntegrationSyncStatus = .idle
    @Published private(set) var lastSyncError: Error?
    @Published var isSyncing = false

    // MARK: - Child Services

    lazy var calendarService: CalendarIntegrationService = {
        CalendarIntegrationService(oauthHandler: oauthHandler)
    }()

    lazy var smartHomeService: SmartHomeIntegrationService = {
        SmartHomeIntegrationService()
    }()

    lazy var travelService: TravelIntegrationService = {
        TravelIntegrationService(oauthHandler: oauthHandler)
    }()

    lazy var noteService: NoteTakingIntegrationService = {
        NoteTakingIntegrationService(oauthHandler: oauthHandler)
    }()

    // MARK: - Initialization

    @available(*, deprecated, message: "Use init(supabaseClient:) instead")
    convenience init() {
        self.init(supabaseClient: supabase)
    }

    init(oauthHandler: OAuthHandler = OAuthHandler(), supabaseClient: SupabaseClient) {
        self.oauthHandler = oauthHandler
        self.supabaseClient = supabaseClient
        Task {
            await loadConnections()
        }
        setupBackgroundSync()
    }

    // MARK: - Connection Management

    /// Integrations available for connection (excludes unavailable ones like TripIt)
    var availableIntegrations: [IntegrationType] {
        IntegrationType.allCases.filter { type in
            switch type {
            case .tripIt:
                return false // TripIt developer program discontinued
            default:
                return true
            }
        }
    }

    /// Checks if an integration is connected
    func isConnected(_ type: IntegrationType) async -> Bool {
        switch type {
        case .googleCalendar:
            return await oauthHandler.isGoogleConnected()
        case .notion:
            return oauthHandler.isNotionConnected()
        case .bear, .joplin:
            // Bear and Joplin use API keys, not OAuth
            return false
        default:
            return false
        }
    }

    /// Gets connection status for an integration
    func connectionStatus(_ type: IntegrationType) async -> IntegrationConnection.Status {
        guard let connection = connections[type] else {
            return .disconnected
        }
        return connection.status
    }

    /// Initiates OAuth connection for an integration
    func connect(
        _ type: IntegrationType,
        from viewController: UIViewController
    ) async throws {
        logger.info("Initiating connection for \(type.rawValue)")

        // Update status to connecting
        updateConnection(type, status: .connecting)

        do {
            switch type {
            case .notion:
                try await oauthHandler.connectNotion(from: viewController)
                // OAuth flow will complete via callback
                updateConnection(type, status: .connected, lastSync: Date())
                logger.info("Successfully connected Notion")

            case .googleCalendar:
                // Calendar integration uses Supabase Auth - user must sign in with Google
                // The connection status will be updated on next loadConnections call
                let isNowConnected = await oauthHandler.isGoogleConnected()
                if isNowConnected {
                    updateConnection(type, status: .connected, lastSync: Date())
                    logger.info("Calendar integration available via Supabase Auth")
                } else {
                    updateConnection(type, status: .error, error: "Please sign in with Google first")
                    throw OAuthError.notConnected
                }

            default:
                updateConnection(type, status: .error, error: "Unsupported integration")
                throw OAuthError.unsupportedIntegration
            }
        } catch let error as OAuthError {
            updateConnection(type, status: .error, error: error.localizedDescription)
            throw error
        } catch {
            updateConnection(type, status: .error, error: error.localizedDescription)
            throw error
        }
    }

    /// Handles OAuth callback with authorization code (for Notion)
    func handleOAuthCallback(code: String, state: String, integrationType: IntegrationType) async throws {
        logger.info("Processing OAuth callback for \(integrationType.rawValue)")

        do {
            switch integrationType {
            case .notion:
                let _ = try await oauthHandler.exchangeNotionCode(code)
                updateConnection(integrationType, status: .connected, lastSync: Date())
                logger.info("Successfully connected Notion")

            default:
                throw OAuthError.unsupportedIntegration
            }
        } catch {
            updateConnection(integrationType, status: .error, error: error.localizedDescription)
            throw error
        }
    }

    /// Disconnects an integration
    func disconnect(_ type: IntegrationType) {
        logger.info("Disconnecting \(type.rawValue)")

        switch type {
        case .notion:
            oauthHandler.disconnectNotion()
        default:
            break // Calendar integrations disconnect via Supabase Auth sign out
        }

        connections.removeValue(forKey: type)

        // Notify backend
        Task {
            try? await supabaseClient.from("integrations")
                .update(["status": "revoked"])
                .eq("user_id", value: supabaseClient.auth.currentUser?.id ?? "")
                .eq("integration_type", value: type.rawValue)
                .execute()
        }
    }

    // MARK: - Sync Operations

    /// Triggers sync for a specific integration
    func sync(_ type: IntegrationType) async throws {
        guard await isConnected(type) else {
            throw IntegrationError.notConnected
        }

        logger.info("Starting sync for \(type.rawValue)")

        isSyncing = true
        lastSyncError = nil
        syncStatus = .syncing(type)

        do {
            switch type {
            case .googleCalendar:
                try await calendarService.sync()

            case .flightAware:
                try await travelService.sync()

            case .bear, .notion, .joplin:
                try await noteService.sync()

            case .homeKit, .ecobee, .nest:
                try await smartHomeService.sync()

            default:
                break
            }

            updateConnection(type, status: .connected, lastSync: Date())
            syncStatus = .completed(type)
            logger.info("Sync completed for \(type.rawValue)")
        } catch {
            lastSyncError = error
            syncStatus = .failed(type, error)
            throw error
        }

        isSyncing = false
    }

    /// Triggers sync for all connected integrations
    func syncAll() async {
        logger.info("Starting sync for all connected integrations")

        syncStatus = .syncing(nil)
        isSyncing = true

        for (type, connection) in connections where connection.status == .connected {
            do {
                try await sync(type)
            } catch {
                logger.error("Sync failed for \(type.rawValue): \(error.localizedDescription)")
            }
        }

        isSyncing = false
        syncStatus = .idle
    }

    // MARK: - Data Access

    /// Gets calendar events for stress prediction
    func getCalendarEvents(days: Int = 7) async throws -> [CalendarEvent] {
        guard await isConnected(.googleCalendar) else {
            throw IntegrationError.notConnected
        }
        return try await calendarService.getEvents(days: days)
    }

    // MARK: - Private Helpers

    private func loadConnections() async {
        // Load connection status from local storage and backend
        // Check calendar integrations via Supabase Auth
        if await oauthHandler.isGoogleConnected() {
            connections[.googleCalendar] = IntegrationConnection(
                type: .googleCalendar,
                status: .connected,
                lastSync: nil,
                error: nil
            )
        }

        // Check Notion via stored token
        if oauthHandler.isNotionConnected() {
            connections[.notion] = IntegrationConnection(
                type: .notion,
                status: .connected,
                lastSync: nil,
                error: nil
            )
        }
    }

    private func updateConnection(
        _ type: IntegrationType,
        status: IntegrationConnection.Status,
        lastSync: Date? = nil,
        error: String? = nil
    ) {
        let connection = IntegrationConnection(
            type: type,
            status: status,
            lastSync: lastSync,
            error: error
        )
        connections[type] = connection
    }

    private var syncTimer: Timer?

    private func setupBackgroundSync() {
        // Set up periodic sync for connected integrations
        // This would typically use BGTaskScheduler in production
        syncTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.syncAll()
            }
        }
    }
}

// MARK: - Placeholder Services (to be implemented)

/// Service for smart home integration (HomeKit)
final class SmartHomeIntegrationService {
    private let logger = Logger(subsystem: "com.mindfriend", category: "SmartHome")

    func sync() async throws {
        logger.info("Syncing smart home devices")
    }

    func triggerScene(_ sceneId: String) async throws {
        logger.info("Triggering smart home scene: \(sceneId)")
    }
}

/// Service for travel app integration
final class TravelIntegrationService {
    private let oauthHandler: OAuthHandler
    private let logger = Logger(subsystem: "com.mindfriend", category: "Travel")

    init(oauthHandler: OAuthHandler) {
        self.oauthHandler = oauthHandler
    }

    func sync() async throws {
        logger.info("Syncing travel data")
    }

    func getItineraries() async throws -> [TravelItinerary] {
        return []
    }
}

/// Service for note-taking app integration
final class NoteTakingIntegrationService {
    private let oauthHandler: OAuthHandler
    private let logger = Logger(subsystem: "com.mindfriend", category: "Notes")

    init(oauthHandler: OAuthHandler) {
        self.oauthHandler = oauthHandler
    }

    func sync() async throws {
        logger.info("Syncing notes")
    }

    func exportJournalEntry(_ entry: IntegrationJournalEntry) async throws -> String {
        // Export to Bear/Notion/Joplin
        return ""
    }
}

// Placeholder for ExportedJournalEntry
struct IntegrationJournalEntry {
    let id: UUID
    let content: String
    let moodScore: Double?
    let createdAt: Date
}
