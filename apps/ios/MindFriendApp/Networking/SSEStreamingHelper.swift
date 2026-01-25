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
        }
    }
}

/// Helper class for streaming image generation from Edge Functions
@MainActor
final class SSEStreamingHelper {

    /// Stream image generation with partial image updates
    /// - Parameters:
    ///   - functionName: The Edge Function name (e.g., "generate-profile-picture")
    ///   - body: The request body dictionary
    ///   - onEvent: Callback for each streaming event
    /// - Returns: AsyncThrowingStream of ImageStreamEvent
    static func streamImageGeneration(
        functionName: String,
        body: [String: Any]
    ) -> AsyncThrowingStream<ImageStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Get auth session
                    guard let session = try? await supabase.auth.session else {
                        continuation.finish(throwing: SSEStreamError.noSession)
                        return
                    }

                    // Build URL
                    let url = SupabaseConfig.projectURL
                        .appendingPathComponent("functions")
                        .appendingPathComponent("v1")
                        .appendingPathComponent(functionName)

                    // Create request
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    // Add stream: true to body
                    var bodyWithStream = body
                    bodyWithStream["stream"] = true
                    request.httpBody = try JSONSerialization.data(withJSONObject: bodyWithStream)

                    // Create URLSession for streaming
                    let sessionConfig = URLSessionConfiguration.default
                    sessionConfig.timeoutIntervalForRequest = 120
                    sessionConfig.timeoutIntervalForResource = 180
                    let urlSession = URLSession(configuration: sessionConfig)

                    // Use bytes for streaming
                    let (bytes, response) = try await urlSession.bytes(for: request)

                    // Check response
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: SSEStreamError.invalidURL)
                        return
                    }

                    if httpResponse.statusCode != 200 {
                        continuation.finish(throwing: SSEStreamError.httpError(httpResponse.statusCode, nil))
                        return
                    }

                    // Parse SSE stream
                    var buffer = ""
                    for try await byte in bytes {
                        buffer.append(Character(UnicodeScalar(byte)))

                        // Check for complete SSE event (ends with double newline)
                        while let eventEnd = buffer.range(of: "\n\n") {
                            let eventData = String(buffer[..<eventEnd.lowerBound])
                            buffer.removeSubrange(..<eventEnd.upperBound)

                            // Parse the event
                            if let event = parseSSEEvent(eventData) {
                                continuation.yield(event)

                                // Check for completion
                                if case .complete = event {
                                    continuation.finish()
                                    return
                                }
                                if case .error = event {
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Parse an SSE event string into an ImageStreamEvent
    private static func parseSSEEvent(_ eventString: String) -> ImageStreamEvent? {
        // Extract data from "data: {...}" format
        let lines = eventString.split(separator: "\n")
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))

                guard let data = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String else {
                    continue
                }

                switch type {
                case "partial":
                    if let imageBase64 = json["imageBase64"] as? String,
                       let imageData = Data(base64Encoded: imageBase64),
                       let index = json["index"] as? Int {
                        return .partial(index: index, imageData: imageData)
                    }

                case "complete":
                    if let imageBase64 = json["imageBase64"] as? String,
                       let imageData = Data(base64Encoded: imageBase64) {
                        // Extract metadata
                        var metadata: [String: Any] = [:]
                        if let success = json["success"] as? Bool {
                            metadata["success"] = success
                        }
                        if let creativeWorkId = json["creativeWorkId"] as? String {
                            metadata["creativeWorkId"] = creativeWorkId
                        }
                        if let imageUrl = json["imageUrl"] as? String {
                            metadata["imageUrl"] = imageUrl
                        }
                        if let generationId = json["generationId"] as? String {
                            metadata["generationId"] = generationId
                        }
                        return .complete(imageData: imageData, metadata: metadata.isEmpty ? nil : metadata)
                    }

                case "error":
                    let errorMessage = json["error"] as? String ?? "Unknown error"
                    return .error(SSEStreamError.decodingError(errorMessage))

                case "done":
                    // Stream complete without explicit complete event
                    return nil

                default:
                    break
                }
            }
        }
        return nil
    }
}
