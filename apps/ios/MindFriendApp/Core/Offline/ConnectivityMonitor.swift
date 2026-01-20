//
//  ConnectivityMonitor.swift
//  MindFriendApp
//
//  Monitors network connectivity using NWPathMonitor
//

import Foundation
import Network
import Combine

/// Monitors network connectivity and publishes connection state changes
@MainActor
final class ConnectivityMonitor: ObservableObject {

    // MARK: - Published Properties

    /// Whether the device currently has network connectivity
    @Published private(set) var isConnected: Bool = true

    /// The current type of network connection
    @Published private(set) var connectionType: ConnectionType = .unknown

    /// Whether the current connection is expensive (cellular data)
    @Published private(set) var isExpensive: Bool = false

    /// Whether the current connection is constrained (Low Data Mode)
    @Published private(set) var isConstrained: Bool = false

    /// Human-readable status message
    @Published private(set) var statusMessage: String = "Checking connection..."

    // MARK: - Callbacks

    /// Called when connectivity is restored after being offline
    var onConnectivityRestored: (() async -> Void)?

    /// Called when connectivity is lost
    var onConnectivityLost: (() -> Void)?

    // MARK: - Private Properties

    private var monitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.mindfriend.connectivity", qos: .utility)
    private var wasConnected: Bool = true
    private var isMonitoring: Bool = false

    // MARK: - Singleton

    static let shared = ConnectivityMonitor()

    // MARK: - Initialization

    init() {
        // Monitor is created on-demand in startMonitoring()
    }

    // MARK: - Public Methods

    /// Start monitoring network connectivity
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Create a new NWPathMonitor instance each time
        // NWPathMonitor cannot be restarted after cancel() - must create new instance
        let newMonitor = NWPathMonitor()
        self.monitor = newMonitor

        newMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(path)
            }
        }

        newMonitor.start(queue: monitorQueue)
    }

    /// Stop monitoring network connectivity
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        monitor?.cancel()
        monitor = nil // Release the monitor so a new one can be created on restart
    }

    /// Check if current connection allows downloads (respects WiFi-only setting)
    func canDownload(wifiOnly: Bool) -> Bool {
        guard isConnected else { return false }

        if wifiOnly {
            return connectionType == .wifi || connectionType == .ethernet
        }

        return true
    }

    /// Force a connectivity check
    func checkConnectivity() {
        guard let monitor = monitor else {
            // If monitor is not started, start it now
            startMonitoring()
            return
        }
        let currentPath = monitor.currentPath
        handlePathUpdate(currentPath)
    }

    // MARK: - Private Methods

    private func handlePathUpdate(_ path: NWPath) {
        let newIsConnected = path.status == .satisfied
        let newConnectionType = determineConnectionType(from: path)
        let newIsExpensive = path.isExpensive
        let newIsConstrained = path.isConstrained

        // Update published properties
        isConnected = newIsConnected
        connectionType = newConnectionType
        isExpensive = newIsExpensive
        isConstrained = newIsConstrained
        statusMessage = generateStatusMessage()

        // Handle connectivity changes
        if newIsConnected && !wasConnected {
            // Connectivity restored
            Task {
                await onConnectivityRestored?()
            }
        } else if !newIsConnected && wasConnected {
            // Connectivity lost
            onConnectivityLost?()
        }

        wasConnected = newIsConnected
    }

    private func determineConnectionType(from path: NWPath) -> ConnectionType {
        guard path.status == .satisfied else {
            return .none
        }

        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else {
            return .unknown
        }
    }

    private func generateStatusMessage() -> String {
        if !isConnected {
            return "You're offline"
        }

        var message = connectionType.displayName

        if isConstrained {
            message += " (Low Data Mode)"
        } else if isExpensive && connectionType == .cellular {
            message += " (using cellular data)"
        }

        return message
    }
}

// MARK: - Connectivity State

/// Represents the current connectivity state with additional context
struct ConnectivityState: Equatable {
    let isConnected: Bool
    let connectionType: ConnectionType
    let isExpensive: Bool
    let isConstrained: Bool
    let timestamp: Date

    @MainActor
    init(from monitor: ConnectivityMonitor) {
        self.isConnected = monitor.isConnected
        self.connectionType = monitor.connectionType
        self.isExpensive = monitor.isExpensive
        self.isConstrained = monitor.isConstrained
        self.timestamp = Date()
    }

    init(
        isConnected: Bool,
        connectionType: ConnectionType,
        isExpensive: Bool,
        isConstrained: Bool,
        timestamp: Date = Date()
    ) {
        self.isConnected = isConnected
        self.connectionType = connectionType
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.timestamp = timestamp
    }

    /// Whether downloads should proceed automatically
    var shouldAutoDownload: Bool {
        isConnected && !isConstrained && connectionType == .wifi
    }

    /// Whether sync should proceed automatically
    var shouldAutoSync: Bool {
        isConnected && !isConstrained
    }
}

// MARK: - Connectivity Event

/// Events that occur during connectivity monitoring
enum ConnectivityEvent {
    case connected(ConnectionType)
    case disconnected
    case connectionTypeChanged(from: ConnectionType, to: ConnectionType)
    case constraintsChanged(isExpensive: Bool, isConstrained: Bool)
}

// MARK: - Preview Support

#if DEBUG
extension ConnectivityMonitor {
    /// Create a mock monitor for previews
    static var preview: ConnectivityMonitor {
        let monitor = ConnectivityMonitor()
        return monitor
    }

    /// Create an offline mock monitor for previews
    static var offlinePreview: ConnectivityMonitor {
        let monitor = ConnectivityMonitor()
        return monitor
    }
}
#endif
