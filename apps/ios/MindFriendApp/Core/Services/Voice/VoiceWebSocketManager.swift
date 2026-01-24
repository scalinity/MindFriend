import Foundation
import OSLog

/// Manages WebSocket connection lifecycle for voice service
@MainActor
final class VoiceWebSocketManager {

    // MARK: - Properties

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private(set) var isConnected = false

    // Reconnection state
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var reconnectTask: Task<Void, Never>?
    private var shouldReconnect = false

    // Callbacks
    var onMessage: ((URLSessionWebSocketTask.Message) -> Void)?
    var onConnectionLost: (() -> Void)?

    // MARK: - Initialization

    init() {}

    // MARK: - Connection Management

    func connect(token: String) async throws {
        guard let url = URL(string: "wss://api.x.ai/v1/realtime") else {
            throw VoiceError.connectionFailed("Invalid WebSocket URL")
        }

        #if DEBUG
        Log.voice.debug("[WebSocket] Connecting...")
        #endif

        // Enable reconnection
        shouldReconnect = true
        reconnectAttempts = 0

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300

        urlSession = URLSession(configuration: configuration)
        webSocket = urlSession?.webSocketTask(with: request)
        webSocket?.resume()
        isConnected = true

        #if DEBUG
        Log.voice.debug("[WebSocket] Connected, starting message receiver")
        #endif

        receiveMessages()
    }

    func disconnect() {
        #if DEBUG
        Log.voice.debug("[WebSocket] Disconnecting")
        #endif

        // Disable reconnection
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0

        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil

        urlSession?.invalidateAndCancel()
        urlSession = nil

        isConnected = false
    }

    // MARK: - Message Sending

    func send(_ message: [String: Any]) {
        // Early exit if not connected (prevents spam after disconnect)
        guard isConnected, webSocket != nil else { return }

        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: data, encoding: .utf8) else {
            #if DEBUG
            Log.voice.error("[WebSocket] Failed to serialize message")
            #endif
            return
        }

        let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
        webSocket?.send(wsMessage) { error in
            if let error = error {
                #if DEBUG
                Log.voice.error("[WebSocket] Send error: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Private Methods

    private nonisolated func receiveMessages() {
        Task { @MainActor in
            let socket = self.webSocket
            socket?.receive { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success(let message):
                    #if DEBUG
                    switch message {
                    case .string(let text):
                        Log.voice.debug("[WebSocket] Received string message (\(text.count) chars)")
                    case .data(let data):
                        Log.voice.debug("[WebSocket] Received data message (\(data.count) bytes)")
                    @unknown default:
                        Log.voice.debug("[WebSocket] Received unknown message type")
                    }
                    #endif

                    Task { @MainActor in
                        self.onMessage?(message)
                    }
                    self.receiveMessages()

                case .failure(let error):
                    #if DEBUG
                    Log.voice.error("[WebSocket] Receive error: \(error.localizedDescription)")
                    #endif

                    Task { @MainActor in
                        self.isConnected = false
                        self.onConnectionLost?()
                        self.attemptReconnect()
                    }
                }
            }
        }
    }

    private func attemptReconnect() {
        reconnectTask?.cancel()

        guard shouldReconnect, reconnectAttempts < maxReconnectAttempts else {
            if reconnectAttempts >= maxReconnectAttempts {
                #if DEBUG
                Log.voice.error("[WebSocket] Max reconnect attempts reached")
                #endif
                shouldReconnect = false
            }
            return
        }

        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts - 1)), 30.0)

        #if DEBUG
        Log.voice.debug("[WebSocket] Reconnect attempt \(self.reconnectAttempts)/\(self.maxReconnectAttempts) in \(delay)s")
        #endif

        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard let self, !Task.isCancelled, self.shouldReconnect else { return }

            // Reconnection logic would go here
            // In practice, the parent service should handle re-connection
            // by calling connect() again with a fresh token
        }
    }
}
