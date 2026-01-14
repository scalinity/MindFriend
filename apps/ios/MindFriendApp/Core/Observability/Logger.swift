import Foundation
import OSLog

/// Centralized logging utility using OSLog
/// All log messages go through here for consistent formatting and privacy handling
///
/// Usage:
///   Log.debug("Debug message")
///   Log.info("User signed in")
///   Log.warning("Quota low")
///   Log.error("API call failed", error: error)
///
/// Categories available:
///   Log.auth.info("Auth message")
///   Log.network.debug("Network message")
///   Log.chat.info("Chat message")
enum Log {
    // MARK: - Category-Specific Loggers
    
    /// Authentication-related logs
    static let auth = Logger(subsystem: subsystem, category: "Auth")
    
    /// Network and API-related logs
    static let network = Logger(subsystem: subsystem, category: "Network")
    
    /// Chat and conversation logs
    static let chat = Logger(subsystem: subsystem, category: "Chat")
    
    /// Data service operations
    static let data = Logger(subsystem: subsystem, category: "Data")
    
    /// Billing and subscription logs
    static let billing = Logger(subsystem: subsystem, category: "Billing")
    
    /// Voice mode logs
    static let voice = Logger(subsystem: subsystem, category: "Voice")
    
    /// Notification logs
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    
    /// UI and view logs
    static let ui = Logger(subsystem: subsystem, category: "UI")
    
    /// Quest and exercise logs
    static let quests = Logger(subsystem: subsystem, category: "Quests")
    
    /// General app logs
    static let general = Logger(subsystem: subsystem, category: "General")
    
    // MARK: - Private
    
    private static let subsystem = Bundle.main.bundleIdentifier ?? "app.mindfriend"
    
    // MARK: - Convenience Methods (use general category)
    
    /// Log a debug message (only visible in Console.app with debug filter)
    static func debug(_ message: String) {
        general.debug("\(message, privacy: .public)")
    }
    
    /// Log an informational message
    static func info(_ message: String) {
        general.info("\(message, privacy: .public)")
    }
    
    /// Log a warning message
    static func warning(_ message: String) {
        general.warning("⚠️ \(message, privacy: .public)")
    }
    
    /// Log an error message
    static func error(_ message: String, error: Error? = nil) {
        if let error = error {
            general.error("❌ \(message, privacy: .public): \(error.localizedDescription, privacy: .public)")
        } else {
            general.error("❌ \(message, privacy: .public)")
        }
    }
    
    /// Log a fault (critical error)
    static func fault(_ message: String) {
        general.fault("🔥 \(message, privacy: .public)")
    }
}

// MARK: - Logger Extension for Privacy-Safe User IDs

extension Logger {
    /// Log a message with a private user ID (redacted in logs by default)
    func userAction(_ message: String, userId: String) {
        self.info("\(message, privacy: .public) [user: \(userId, privacy: .private(mask: .hash))]")
    }
    
    /// Log a message with a private token (always redacted)
    func withToken(_ message: String, tokenPrefix: String) {
        self.debug("\(message, privacy: .public) [token: \(tokenPrefix, privacy: .private)...]")
    }
}
