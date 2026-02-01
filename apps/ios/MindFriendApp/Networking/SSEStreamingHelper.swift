import Foundation
import Supabase

/// Events emitted during streaming image generation
enum ImageStreamEvent {
    case partial(index: Int, imageData: Data)
    case complete(imageData: Data, metadata: [String: Any]?)
    case error(Error)
}

/// Errors that can occur during SSE streaming
enum SSEStreamError: LocalizedError {
    case noSession
    case invalidURL
    case httpError(Int, String?)
    case noData
    case decodingError(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .noSession:
            return "Not authenticated"
        case .invalidURL:
            return "Invalid URL"
        case .httpError(let code, let message):
            return "HTTP error \(code): \(message ?? "Unknown")"
        case .noData:
            return "No data received"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        case .timeout:
            return "Request timed out"
        }
    }
}

/// Delegate-based SSE handler for more reliable streaming
private final class SSESessionDelegate: NSObject, URLSessionDataDelegate {
    private var buffer = ""
    private var eventHandler: ((String) -> Void)?
    private var completionHandler: ((Error?) -> Void)?
    private var httpStatusCode: Int?
    private var errorBody = ""

    func configure(
        onEvent: @escaping (String) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        self.eventHandler = onEvent
        self.completionHandler = onComplete
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse {
            httpStatusCode = httpResponse.statusCode
            print("[SSE-Delegate] Received response status: \(httpResponse.statusCode)")
            print("[SSE-Delegate] Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "nil")")
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            print("[SSE-Delegate] Failed to decode data chunk")
            return
        }

        print("[SSE-Delegate] Received data chunk: \(data.count) bytes")

        // Check if this is an error response (non-200)
        if let statusCode = httpStatusCode, statusCode != 200 {
            errorBody += text
            return
        }

        buffer += text

        // Check for complete SSE events (ends with double newline)
        while let eventEnd = buffer.range(of: "\n\n") {
            let eventData = String(buffer[..<eventEnd.lowerBound])
            buffer.removeSubrange(..<eventEnd.upperBound)

            if !eventData.isEmpty {
                print("[SSE-Delegate] Complete event received")
                eventHandler?(eventData)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        print("[SSE-Delegate] Session completed, error: \(error?.localizedDescription ?? "none")")

        if let error = error {
            completionHandler?(error)
        } else if let statusCode = httpStatusCode, statusCode != 200 {
            completionHandler?(SSEStreamError.httpError(statusCode, errorBody.isEmpty ? nil : errorBody))
        } else {
            // Process any remaining buffered data
            if !buffer.isEmpty {
                print("[SSE-Delegate] Processing remaining buffer: \(buffer.count) chars")
                eventHandler?(buffer)
            }
            completionHandler?(nil)
        }
    }
}

/// Helper class for streaming image generation from Edge Functions
@MainActor
final class SSEStreamingHelper {

    /// Stream image generation with partial image updates using delegate-based approach
    /// This is more reliable than the async bytes approach for SSE streams
    /// - Parameters:
    ///   - functionName: The Edge Function name (e.g., "generate-profile-picture")
    ///   - body: The request body dictionary
    /// - Returns: AsyncThrowingStream of ImageStreamEvent
    static func streamImageGeneration(
        functionName: String,
        body: [String: Any]
    ) -> AsyncThrowingStream<ImageStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    Log.network.debug("[SSE] Starting stream for function: \(functionName)")

                    // Get auth session
                    guard let session = try? await supabase.auth.session else {
                        Log.network.error("[SSE] No auth session")
                        continuation.finish(throwing: SSEStreamError.noSession)
                        return
                    }
                    Log.network.debug("[SSE] Session acquired")

                    // Build URL
                    let url = SupabaseConfig.projectURL
                        .appendingPathComponent("functions")
                        .appendingPathComponent("v1")
                        .appendingPathComponent(functionName)
                    print("[SSE] URL: \(url.absoluteString)")

                    // Create request
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
                    request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 120

                    // Add stream: true to body
                    var bodyWithStream = body
                    bodyWithStream["stream"] = true
                    request.httpBody = try JSONSerialization.data(withJSONObject: bodyWithStream)
                    print("[SSE] Request body: \(String(data: request.httpBody!, encoding: .utf8) ?? "nil")")

                    // Use delegate-based approach for reliable streaming
                    let delegate = SSESessionDelegate()
                    let sessionConfig = URLSessionConfiguration.default
                    sessionConfig.timeoutIntervalForRequest = 120
                    sessionConfig.timeoutIntervalForResource = 180
                    sessionConfig.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                    sessionConfig.urlCache = nil

                    // Create session with delegate
                    let urlSession = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)

                    print("[SSE] Sending request with delegate-based streaming...")

                    // Configure delegate to handle events
                    await withCheckedContinuation { (eventContinuation: CheckedContinuation<Void, Never>) in
                        delegate.configure(
                            onEvent: { eventData in
                                print("[SSE] Event received via delegate")
                                if let event = self.parseSSEEvent(eventData) {
                                    print("[SSE] Parsed event type: \(event)")
                                    continuation.yield(event)

                                    if case .complete = event {
                                        print("[SSE] Complete event - will finish after session completes")
                                    }
                                }
                            },
                            onComplete: { error in
                                print("[SSE] Delegate completed, error: \(error?.localizedDescription ?? "none")")
                                if let error = error {
                                    continuation.finish(throwing: error)
                                } else {
                                    continuation.finish()
                                }
                                eventContinuation.resume()
                            }
                        )

                        // Start the data task
                        let task = urlSession.dataTask(with: request)
                        task.resume()
                        print("[SSE] Data task started")
                    }

                    print("[SSE] Stream completed")
                } catch {
                    print("[SSE] ERROR: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Alternative: Stream using async bytes (kept for reference/fallback)
    static func streamImageGenerationAsyncBytes(
        functionName: String,
        body: [String: Any]
    ) -> AsyncThrowingStream<ImageStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    print("[SSE-Bytes] Starting stream for function: \(functionName)")

                    // Get auth session
                    guard let session = try? await supabase.auth.session else {
                        Log.network.error("[SSE-Bytes] No auth session")
                        continuation.finish(throwing: SSEStreamError.noSession)
                        return
                    }
                    Log.network.debug("[SSE-Bytes] Session acquired")

                    // Build URL
                    let url = SupabaseConfig.projectURL
                        .appendingPathComponent("functions")
                        .appendingPathComponent("v1")
                        .appendingPathComponent(functionName)
                    print("[SSE-Bytes] URL: \(url.absoluteString)")

                    // Create request
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
                    request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    // Add stream: true to body
                    var bodyWithStream = body
                    bodyWithStream["stream"] = true
                    request.httpBody = try JSONSerialization.data(withJSONObject: bodyWithStream)
                    print("[SSE-Bytes] Request body: \(String(data: request.httpBody!, encoding: .utf8) ?? "nil")")

                    // Create URLSession for streaming with delegate for better SSE handling
                    let sessionConfig = URLSessionConfiguration.default
                    sessionConfig.timeoutIntervalForRequest = 120
                    sessionConfig.timeoutIntervalForResource = 180
                    // Disable caching for SSE
                    sessionConfig.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                    sessionConfig.urlCache = nil
                    let urlSession = URLSession(configuration: sessionConfig)

                    print("[SSE-Bytes] Sending request...")

                    // Use bytes for streaming
                    let (bytes, response) = try await urlSession.bytes(for: request)
                    print("[SSE-Bytes] Got response")

                    // Check response
                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("[SSE-Bytes] ERROR: Response is not HTTPURLResponse")
                        continuation.finish(throwing: SSEStreamError.invalidURL)
                        return
                    }

                    print("[SSE-Bytes] HTTP status: \(httpResponse.statusCode)")
                    print("[SSE-Bytes] Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "nil")")
                    print("[SSE-Bytes] All headers: \(httpResponse.allHeaderFields)")

                    if httpResponse.statusCode != 200 {
                        print("[SSE-Bytes] ERROR: Non-200 status code")
                        // Try to read error body for better error messages
                        var errorBody = ""
                        for try await byte in bytes {
                            errorBody.append(Character(UnicodeScalar(byte)))
                            if errorBody.count > 1024 { break } // Limit read
                        }
                        print("[SSE-Bytes] Error body: \(errorBody)")
                        // Extract error message from JSON if possible
                        var errorMessage: String?
                        if let data = errorBody.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            errorMessage = json["error"] as? String ?? json["message"] as? String
                        }
                        continuation.finish(throwing: SSEStreamError.httpError(httpResponse.statusCode, errorMessage))
                        return
                    }

                    // Parse SSE stream
                    print("[SSE-Bytes] Starting to read bytes...")
                    var buffer = ""
                    var byteCount = 0
                    var eventCount = 0

                    for try await byte in bytes {
                        byteCount += 1
                        buffer.append(Character(UnicodeScalar(byte)))

                        // Log progress every 1000 bytes
                        if byteCount % 1000 == 0 {
                            print("[SSE-Bytes] Received \(byteCount) bytes so far...")
                        }

                        // Check for complete SSE event (ends with double newline)
                        while let eventEnd = buffer.range(of: "\n\n") {
                            let eventData = String(buffer[..<eventEnd.lowerBound])
                            buffer.removeSubrange(..<eventEnd.upperBound)

                            eventCount += 1
                            print("[SSE-Bytes] Event #\(eventCount) raw data (first 200 chars): \(String(eventData.prefix(200)))")

                            // Parse the event
                            if let event = parseSSEEvent(eventData) {
                                print("[SSE-Bytes] Parsed event: \(event)")
                                continuation.yield(event)

                                // Check for completion
                                if case .complete = event {
                                    print("[SSE-Bytes] Complete event received, finishing stream")
                                    continuation.finish()
                                    return
                                }
                                if case .error(let error) = event {
                                    print("[SSE-Bytes] Error event received: \(error)")
                                    continuation.finish()
                                    return
                                }
                            } else {
                                print("[SSE-Bytes] WARNING: Failed to parse event data")
                            }
                        }
                    }

                    print("[SSE-Bytes] Byte stream ended. Total bytes: \(byteCount), events: \(eventCount)")
                    print("[SSE-Bytes] Remaining buffer: \(buffer)")
                    continuation.finish()
                } catch {
                    print("[SSE-Bytes] ERROR: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Parse an SSE event string into an ImageStreamEvent
    private static func parseSSEEvent(_ eventString: String) -> ImageStreamEvent? {
        print("[SSE-Parse] Parsing event string (length: \(eventString.count))")

        // Extract data from "data: {...}" format
        let lines = eventString.split(separator: "\n")
        print("[SSE-Parse] Lines count: \(lines.count)")

        for line in lines {
            print("[SSE-Parse] Line: \(String(line.prefix(100)))")
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                print("[SSE-Parse] JSON string (first 100): \(String(jsonString.prefix(100)))")

                guard let data = jsonString.data(using: .utf8) else {
                    print("[SSE-Parse] ERROR: Failed to convert to Data")
                    continue
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("[SSE-Parse] ERROR: Failed to parse JSON")
                    continue
                }

                guard let type = json["type"] as? String else {
                    print("[SSE-Parse] ERROR: No 'type' field in JSON. Keys: \(json.keys)")
                    continue
                }

                print("[SSE-Parse] Event type: \(type)")

                switch type {
                case "partial":
                    print("[SSE-Parse] Handling partial event")
                    if let imageBase64 = json["imageBase64"] as? String,
                       let imageData = Data(base64Encoded: imageBase64),
                       let index = json["index"] as? Int {
                        print("[SSE-Parse] Partial image decoded, size: \(imageData.count), index: \(index)")
                        return .partial(index: index, imageData: imageData)
                    } else {
                        print("[SSE-Parse] ERROR: Failed to decode partial image. Has imageBase64: \(json["imageBase64"] != nil), has index: \(json["index"] != nil)")
                    }

                case "complete":
                    print("[SSE-Parse] Handling complete event")
                    if let imageBase64 = json["imageBase64"] as? String {
                        print("[SSE-Parse] imageBase64 length: \(imageBase64.count)")
                        if let imageData = Data(base64Encoded: imageBase64) {
                            print("[SSE-Parse] Image decoded, size: \(imageData.count)")
                            // Extract metadata
                            var metadata: [String: Any] = [:]
                            if let success = json["success"] as? Bool {
                                metadata["success"] = success
                            }
                            if let creativeWorkId = json["creativeWorkId"] as? String {
                                metadata["creativeWorkId"] = creativeWorkId
                                print("[SSE-Parse] creativeWorkId: \(creativeWorkId)")
                            }
                            if let imageUrl = json["imageUrl"] as? String {
                                metadata["imageUrl"] = imageUrl
                            }
                            if let generationId = json["generationId"] as? String {
                                metadata["generationId"] = generationId
                            }
                            print("[SSE-Parse] Metadata keys: \(metadata.keys)")
                            return .complete(imageData: imageData, metadata: metadata.isEmpty ? nil : metadata)
                        } else {
                            print("[SSE-Parse] ERROR: Failed to decode base64 image")
                        }
                    } else {
                        print("[SSE-Parse] ERROR: No imageBase64 in complete event. Keys: \(json.keys)")
                    }

                case "error":
                    let errorMessage = json["error"] as? String ?? "Unknown error"
                    print("[SSE-Parse] Error event: \(errorMessage)")
                    return .error(SSEStreamError.decodingError(errorMessage))

                case "done":
                    // Stream complete without explicit complete event
                    print("[SSE-Parse] Done event (no data)")
                    return nil

                default:
                    print("[SSE-Parse] Unknown event type: \(type)")
                    break
                }
            }
        }
        print("[SSE-Parse] No valid event found")
        return nil
    }
}
