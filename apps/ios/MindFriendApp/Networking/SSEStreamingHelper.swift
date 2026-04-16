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
    // Cap unbounded accumulators so a misbehaving/hostile server that never
    // emits the "\n\n" event terminator can't grow memory without limit.
    // 8 MiB comfortably fits a single base64 image event from our edge
    // function; anything larger is treated as a protocol error.
    private static let maxBufferBytes = 8 * 1024 * 1024
    private static let maxErrorBodyBytes = 64 * 1024

    private var buffer = ""
    private var eventHandler: ((String) -> Void)?
    private var completionHandler: ((Error?) -> Void)?
    private var httpStatusCode: Int?
    private var errorBody = ""
    private var overflowed = false

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
            #if DEBUG
            print("[SSE-Delegate] Received response status: \(httpResponse.statusCode)")
            print("[SSE-Delegate] Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "nil")")
            #endif
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            #if DEBUG
            print("[SSE-Delegate] Failed to decode data chunk")
            #endif
            return
        }

        #if DEBUG
        print("[SSE-Delegate] Received data chunk: \(data.count) bytes")
        #endif

        // Check if this is an error response (non-200)
        if let statusCode = httpStatusCode, statusCode != 200 {
            if errorBody.utf8.count < Self.maxErrorBodyBytes {
                errorBody += text
            }
            return
        }

        if overflowed { return }
        buffer += text

        // Check for complete SSE events (ends with double newline)
        while let eventEnd = buffer.range(of: "\n\n") {
            let eventData = String(buffer[..<eventEnd.lowerBound])
            buffer.removeSubrange(..<eventEnd.upperBound)

            if !eventData.isEmpty {
                #if DEBUG
                print("[SSE-Delegate] Complete event received")
                #endif
                eventHandler?(eventData)
            }
        }

        // Bound the buffer: if we've accumulated more than maxBufferBytes
        // without hitting an event terminator, the peer is either broken
        // or hostile. Surface a decoding error and stop accumulating.
        if buffer.utf8.count > Self.maxBufferBytes {
            overflowed = true
            buffer = ""
            completionHandler?(SSEStreamError.decodingError("SSE event exceeded \(Self.maxBufferBytes) bytes without terminator"))
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        #if DEBUG
        print("[SSE-Delegate] Session completed, error: \(error?.localizedDescription ?? "none")")
        #endif

        if let error = error {
            completionHandler?(error)
        } else if let statusCode = httpStatusCode, statusCode != 200 {
            completionHandler?(SSEStreamError.httpError(statusCode, errorBody.isEmpty ? nil : errorBody))
        } else {
            // Process any remaining buffered data
            if !buffer.isEmpty {
                #if DEBUG
                print("[SSE-Delegate] Processing remaining buffer: \(buffer.count) chars")
                #endif
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
                    #if DEBUG
                    print("[SSE] URL: \(url.absoluteString)")
                    #endif

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
                    #if DEBUG
                    print("[SSE] Request body: \(String(data: request.httpBody!, encoding: .utf8) ?? "nil")")
                    #endif

                    // Use delegate-based approach for reliable streaming
                    let delegate = SSESessionDelegate()
                    let sessionConfig = URLSessionConfiguration.default
                    sessionConfig.timeoutIntervalForRequest = 120
                    sessionConfig.timeoutIntervalForResource = 180
                    sessionConfig.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                    sessionConfig.urlCache = nil

                    // Create session with delegate
                    let urlSession = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)

                    #if DEBUG
                    print("[SSE] Sending request with delegate-based streaming...")
                    #endif

                    // Configure delegate to handle events
                    await withCheckedContinuation { (eventContinuation: CheckedContinuation<Void, Never>) in
                        delegate.configure(
                            onEvent: { eventData in
                                #if DEBUG
                                print("[SSE] Event received via delegate")
                                #endif
                                if let event = self.parseSSEEvent(eventData) {
                                    #if DEBUG
                                    print("[SSE] Parsed event type: \(event)")
                                    #endif
                                    continuation.yield(event)

                                    #if DEBUG
                                    if case .complete = event {
                                        print("[SSE] Complete event - will finish after session completes")
                                    }
                                    #endif
                                }
                            },
                            onComplete: { error in
                                #if DEBUG
                                print("[SSE] Delegate completed, error: \(error?.localizedDescription ?? "none")")
                                #endif
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
                        #if DEBUG
                        print("[SSE] Data task started")
                        #endif
                    }

                    // Invalidate session to prevent URLSession leak
                    urlSession.finishTasksAndInvalidate()

                    #if DEBUG
                    print("[SSE] Stream completed")
                    #endif
                } catch {
                    #if DEBUG
                    print("[SSE] ERROR: \(error)")
                    #endif
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
                // Create URLSession outside do/catch so cleanup is reachable from both branches
                let sessionConfig = URLSessionConfiguration.default
                sessionConfig.timeoutIntervalForRequest = 120
                sessionConfig.timeoutIntervalForResource = 180
                // Disable caching for SSE
                sessionConfig.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                sessionConfig.urlCache = nil
                let urlSession = URLSession(configuration: sessionConfig)

                do {
                    #if DEBUG
                    print("[SSE-Bytes] Starting stream for function: \(functionName)")
                    #endif

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
                    #if DEBUG
                    print("[SSE-Bytes] URL: \(url.absoluteString)")
                    #endif

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
                    #if DEBUG
                    print("[SSE-Bytes] Request body: \(String(data: request.httpBody!, encoding: .utf8) ?? "nil")")
                    #endif

                    #if DEBUG
                    print("[SSE-Bytes] Sending request...")
                    #endif

                    // Use bytes for streaming
                    let (bytes, response) = try await urlSession.bytes(for: request)
                    #if DEBUG
                    print("[SSE-Bytes] Got response")
                    #endif

                    // Check response
                    guard let httpResponse = response as? HTTPURLResponse else {
                        #if DEBUG
                        print("[SSE-Bytes] ERROR: Response is not HTTPURLResponse")
                        #endif
                        urlSession.finishTasksAndInvalidate()
                        continuation.finish(throwing: SSEStreamError.invalidURL)
                        return
                    }

                    #if DEBUG
                    print("[SSE-Bytes] HTTP status: \(httpResponse.statusCode)")
                    print("[SSE-Bytes] Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "nil")")
                    print("[SSE-Bytes] All headers: \(httpResponse.allHeaderFields)")
                    #endif

                    if httpResponse.statusCode != 200 {
                        #if DEBUG
                        print("[SSE-Bytes] ERROR: Non-200 status code")
                        #endif
                        // Try to read error body for better error messages
                        var errorBody = ""
                        for try await byte in bytes {
                            errorBody.append(Character(UnicodeScalar(byte)))
                            if errorBody.count > 1024 { break } // Limit read
                        }
                        #if DEBUG
                        print("[SSE-Bytes] Error body: \(errorBody)")
                        #endif
                        // Extract error message from JSON if possible
                        var errorMessage: String?
                        if let data = errorBody.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            errorMessage = json["error"] as? String ?? json["message"] as? String
                        }
                        urlSession.finishTasksAndInvalidate()
                        continuation.finish(throwing: SSEStreamError.httpError(httpResponse.statusCode, errorMessage))
                        return
                    }

                    // Parse SSE stream
                    #if DEBUG
                    print("[SSE-Bytes] Starting to read bytes...")
                    #endif
                    var buffer = ""
                    var byteCount = 0
                    var eventCount = 0
                    // Match the delegate path's bound on unterminated events.
                    let maxBufferBytes = 8 * 1024 * 1024

                    for try await byte in bytes {
                        byteCount += 1
                        buffer.append(Character(UnicodeScalar(byte)))

                        if buffer.utf8.count > maxBufferBytes {
                            continuation.finish(throwing: SSEStreamError.decodingError("SSE event exceeded \(maxBufferBytes) bytes without terminator"))
                            urlSession.finishTasksAndInvalidate()
                            return
                        }

                        // Log progress every 1000 bytes
                        #if DEBUG
                        if byteCount % 1000 == 0 {
                            print("[SSE-Bytes] Received \(byteCount) bytes so far...")
                        }
                        #endif

                        // Check for complete SSE event (ends with double newline)
                        while let eventEnd = buffer.range(of: "\n\n") {
                            let eventData = String(buffer[..<eventEnd.lowerBound])
                            buffer.removeSubrange(..<eventEnd.upperBound)

                            eventCount += 1
                            #if DEBUG
                            print("[SSE-Bytes] Event #\(eventCount) raw data (first 200 chars): \(String(eventData.prefix(200)))")
                            #endif

                            // Parse the event
                            if let event = parseSSEEvent(eventData) {
                                #if DEBUG
                                print("[SSE-Bytes] Parsed event: \(event)")
                                #endif
                                continuation.yield(event)

                                // Check for completion
                                if case .complete = event {
                                    #if DEBUG
                                    print("[SSE-Bytes] Complete event received, finishing stream")
                                    #endif
                                    continuation.finish()
                                    return
                                }
                                if case .error(let error) = event {
                                    #if DEBUG
                                    print("[SSE-Bytes] Error event received: \(error)")
                                    #endif
                                    continuation.finish()
                                    return
                                }
                            } else {
                                #if DEBUG
                                print("[SSE-Bytes] WARNING: Failed to parse event data")
                                #endif
                            }
                        }
                    }

                    #if DEBUG
                    print("[SSE-Bytes] Byte stream ended. Total bytes: \(byteCount), events: \(eventCount)")
                    print("[SSE-Bytes] Remaining buffer: \(buffer)")
                    #endif
                    urlSession.finishTasksAndInvalidate()
                    continuation.finish()
                } catch {
                    #if DEBUG
                    print("[SSE-Bytes] ERROR: \(error)")
                    #endif
                    urlSession.finishTasksAndInvalidate()
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Parse an SSE event string into an ImageStreamEvent
    private static func parseSSEEvent(_ eventString: String) -> ImageStreamEvent? {
        #if DEBUG
        print("[SSE-Parse] Parsing event string (length: \(eventString.count))")
        #endif

        // Extract data from "data: {...}" format
        let lines = eventString.split(separator: "\n")
        #if DEBUG
        print("[SSE-Parse] Lines count: \(lines.count)")
        #endif

        for line in lines {
            #if DEBUG
            print("[SSE-Parse] Line: \(String(line.prefix(100)))")
            #endif
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                #if DEBUG
                print("[SSE-Parse] JSON string (first 100): \(String(jsonString.prefix(100)))")
                #endif

                guard let data = jsonString.data(using: .utf8) else {
                    #if DEBUG
                    print("[SSE-Parse] ERROR: Failed to convert to Data")
                    #endif
                    continue
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    #if DEBUG
                    print("[SSE-Parse] ERROR: Failed to parse JSON")
                    #endif
                    continue
                }

                guard let type = json["type"] as? String else {
                    #if DEBUG
                    print("[SSE-Parse] ERROR: No 'type' field in JSON. Keys: \(json.keys)")
                    #endif
                    continue
                }

                #if DEBUG
                print("[SSE-Parse] Event type: \(type)")
                #endif

                switch type {
                case "partial":
                    #if DEBUG
                    print("[SSE-Parse] Handling partial event")
                    #endif
                    if let imageBase64 = json["imageBase64"] as? String,
                       let imageData = Data(base64Encoded: imageBase64),
                       let index = json["index"] as? Int {
                        #if DEBUG
                        print("[SSE-Parse] Partial image decoded, size: \(imageData.count), index: \(index)")
                        #endif
                        return .partial(index: index, imageData: imageData)
                    } else {
                        #if DEBUG
                        print("[SSE-Parse] ERROR: Failed to decode partial image. Has imageBase64: \(json["imageBase64"] != nil), has index: \(json["index"] != nil)")
                        #endif
                    }

                case "complete":
                    #if DEBUG
                    print("[SSE-Parse] Handling complete event")
                    #endif
                    if let imageBase64 = json["imageBase64"] as? String {
                        #if DEBUG
                        print("[SSE-Parse] imageBase64 length: \(imageBase64.count)")
                        #endif
                        if let imageData = Data(base64Encoded: imageBase64) {
                            #if DEBUG
                            print("[SSE-Parse] Image decoded, size: \(imageData.count)")
                            #endif
                            // Extract metadata
                            var metadata: [String: Any] = [:]
                            if let success = json["success"] as? Bool {
                                metadata["success"] = success
                            }
                            if let creativeWorkId = json["creativeWorkId"] as? String {
                                metadata["creativeWorkId"] = creativeWorkId
                                #if DEBUG
                                print("[SSE-Parse] creativeWorkId: \(creativeWorkId)")
                                #endif
                            }
                            if let imageUrl = json["imageUrl"] as? String {
                                metadata["imageUrl"] = imageUrl
                            }
                            if let generationId = json["generationId"] as? String {
                                metadata["generationId"] = generationId
                            }
                            #if DEBUG
                            print("[SSE-Parse] Metadata keys: \(metadata.keys)")
                            #endif
                            return .complete(imageData: imageData, metadata: metadata.isEmpty ? nil : metadata)
                        } else {
                            #if DEBUG
                            print("[SSE-Parse] ERROR: Failed to decode base64 image")
                            #endif
                        }
                    } else {
                        #if DEBUG
                        print("[SSE-Parse] ERROR: No imageBase64 in complete event. Keys: \(json.keys)")
                        #endif
                    }

                case "error":
                    let errorMessage = json["error"] as? String ?? "Unknown error"
                    #if DEBUG
                    print("[SSE-Parse] Error event: \(errorMessage)")
                    #endif
                    return .error(SSEStreamError.decodingError(errorMessage))

                case "done":
                    // Stream complete without explicit complete event
                    #if DEBUG
                    print("[SSE-Parse] Done event (no data)")
                    #endif
                    return nil

                default:
                    #if DEBUG
                    print("[SSE-Parse] Unknown event type: \(type)")
                    #endif
                    break
                }
            }
        }
        #if DEBUG
        print("[SSE-Parse] No valid event found")
        #endif
        return nil
    }
}
