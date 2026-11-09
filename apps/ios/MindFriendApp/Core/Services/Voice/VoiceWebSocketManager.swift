import Foundation
import OSLog

/// Manages WebSocket connection lifecycle for voice service
@MainActor
final class VoiceWebSocketManager {

    // MARK: - Properties

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private(set) var isConnected = false

    // Current receive loop
    private var acceptsMessages = false
    private var receiveTask: Task<Void, Never>?

    // Callbacks
    var onMessage: ((URLSessionWebSocketTask.Message) -> Void)?
    var onConnectionLost: ((_ sessionLimitReached: Bool) -> Void)?

    // MARK: - Initialization

    init() {}

    // MARK: - Connection Management

    /// Builds the upgrade only from the configured project, never a response-provided host.
    ///
    /// Bound sessions MUST claim the voice-context contract: the query carries `voice_context=1`, and
    /// the server refuses a legacy claim that lacks it. `requiresVoiceContext` is `true` unless a
    /// caller deliberately opts out, which no production path does.
    static func relayRequest(
        sessionId: String,
        userToken: String,
        requiresVoiceContext: Bool = true,
        projectURL: URL = SupabaseConfig.projectURL,
        anonKey: String = SupabaseConfig.anonKey
    ) throws -> URLRequest {
        guard UUID(uuidString: sessionId) != nil, !userToken.isEmpty,
              var components = URLComponents(
                url: projectURL.appendingPathComponent("functions/v1/test-auth-diagnostic"),
                resolvingAgainstBaseURL: false
              ), components.scheme == "https", components.host != nil else {
            throw VoiceError.connectionFailed("Invalid secure voice relay session")
        }
        components.scheme = "wss"
        var query = [URLQueryItem(name: "session_id", value: sessionId)]
        if requiresVoiceContext {
            query.append(URLQueryItem(name: "voice_context", value: "1"))
        }
        components.queryItems = query
        guard let url = components.url else {
            throw VoiceError.connectionFailed("Invalid secure voice relay URL")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 30
        return request
    }

    func connect(sessionId: String, userToken: String) async throws {
        let request = try Self.relayRequest(sessionId: sessionId, userToken: userToken)

        #if DEBUG
        Log.voice.debug("[WebSocket] Connecting...")
        #endif

        disconnect()
        // A failed socket is reported to the owner, which closes capture and its session.
        acceptsMessages = true

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
        acceptsMessages = false
        receiveTask?.cancel()
        receiveTask = nil

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

    private func receiveMessages() {
        guard let socket = webSocket else { return }
        receiveTask?.cancel()
        receiveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    guard let self, self.webSocket === socket, self.acceptsMessages else { return }
                    self.onMessage?(message)
                } catch {
                    guard let self, self.webSocket === socket, self.acceptsMessages, !Task.isCancelled else { return }
                    self.isConnected = false
                    let reason = socket.closeReason.flatMap { String(data: $0, encoding: .utf8) }
                    let reachedLimit = socket.closeCode == .normalClosure ||
                        reason?.lowercased() == "session limit reached"
                    self.onConnectionLost?(reachedLimit)
                    return
                }
            }
        }
    }
}
