import Foundation
import ImageIO
import Supabase

/// A partial preview is never a completed generation.
enum ImageStreamEvent {
    case partial(index: Int, imageData: Data)
    case complete(imageData: Data, metadata: [String: Any]?)
    case error(Error)
}

enum SSEStreamError: LocalizedError {
    case noSession
    case invalidURL
    case httpError(Int, String?, code: String? = nil)
    case noData
    case decodingError(String)
    case serverError(String, code: String? = nil)
    case timeout

    var errorDescription: String? {
        switch self {
        case .noSession: return "Sign in again before generating an image."
        case .invalidURL: return "The image service is unavailable. Try again later."
        case .httpError(let code, let message, _): return message ?? "Image request failed (\(code)). Try again later."
        case .noData: return "The stream ended before a complete image arrived. Your prompt is saved. Try again when you’re ready."
        case .decodingError: return "The image response was incomplete or invalid. Your prompt is saved. Try again when you’re ready."
        case .serverError(let message, _): return message
        case .timeout: return "Image generation timed out. Your prompt is saved. Try again when you’re ready."
        }
    }
}

/// Decode UTF-8 only after a whole line arrives. CR, LF and split CRLF all end lines.
struct ImageSSEDecoder {
    static let maxEventBytes = 8 * 1024 * 1024
    private var line = Data()
    private var dataLines: [String] = []
    private var eventBytes = 0
    private var skipLF = false
    private var firstLine = true

    mutating func consume(_ data: Data) throws -> [String] {
        var events: [String] = []
        try consume(data) { events.append($0); return true }
        return events
    }

    mutating func consume(_ data: Data, onEvent: (String) throws -> Bool) throws {
        for byte in data {
            if skipLF {
                skipLF = false
                if byte == 10 { continue }
            }
            eventBytes += 1
            guard eventBytes <= Self.maxEventBytes else {
                throw SSEStreamError.decodingError("Oversized image event")
            }
            if byte == 10 || byte == 13 {
                guard var text = String(data: line, encoding: .utf8) else {
                    throw SSEStreamError.decodingError("Invalid UTF-8")
                }
                line.removeAll(keepingCapacity: true)
                if firstLine { text = text.replacingOccurrences(of: "\u{FEFF}", with: "", options: .anchored); firstLine = false }
                if text.isEmpty {
                    let payload = dataLines.isEmpty ? nil : dataLines.joined(separator: "\n")
                    dataLines.removeAll(keepingCapacity: true)
                    eventBytes = 0
                    if let payload, try !onEvent(payload) { return }
                } else if text == "data" {
                    dataLines.append("")
                } else if text.hasPrefix("data:") {
                    var value = String(text.dropFirst(5))
                    if value.first == " " { value.removeFirst() }
                    dataLines.append(value)
                }
                skipLF = byte == 13
            } else {
                line.append(byte)
            }
        }
    }
    // An event without its blank-line terminator is incomplete, including at EOF.
}

private final class SSESessionDelegate: NSObject, URLSessionDataDelegate {
    private var decoder = ImageSSEDecoder()
    private var onEvent: ((ImageStreamEvent) -> Void)?
    private var onComplete: ((Error?) -> Void)?
    private var status: Int?
    private var errorBody = Data()
    private var completed = false

    func configure(onEvent: @escaping (ImageStreamEvent) -> Void, onComplete: @escaping (Error?) -> Void) {
        self.onEvent = onEvent; self.onComplete = onComplete
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        status = (response as? HTTPURLResponse)?.statusCode
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !completed else { return }
        if status != 200 {
            errorBody.append(data.prefix(max(0, 64 * 1024 - errorBody.count)))
            return
        }
        do {
            try decoder.consume(data) { payload in
                guard let event = try SSEStreamingHelper.parseImageEvent(payload) else { return true }
                onEvent?(event)
                switch event {
                case .complete, .error:
                    // A complete frame is authoritative; don't wait for a keep-alive close,
                    // or let a later transport failure erase the final result.
                    finish(nil); dataTask.cancel(); return false
                case .partial: return true
                }
            }
        } catch {
            finish(error); dataTask.cancel()
        }
    }
    private func finish(_ error: Error?) {
        guard !completed else { return }
        completed = true
        let callback = onComplete
        onEvent = nil; onComplete = nil
        callback?(error)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !completed else { return }
        if let error {
            finish((error as? URLError)?.code == .timedOut ? SSEStreamError.timeout : error)
        } else if let status, status != 200 {
            let body = (try? JSONSerialization.jsonObject(with: errorBody)) as? [String: Any]
            let code = body?["code"] as? String ?? ((body?["quotaExceeded"] as? Bool) == true ? "image_quota_exhausted" : nil)
            finish(SSEStreamError.httpError(status, body?["message"] as? String ?? body?["error"] as? String, code: code))
        } else {
            finish(SSEStreamError.noData)
        }
    }
}

@MainActor
final class SSEStreamingHelper {
    static func streamImageGeneration(functionName: String, body: [String: Any]) -> AsyncThrowingStream<ImageStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let session = try? await supabase.auth.session else { throw SSEStreamError.noSession }
                    try Task.checkCancellation()
                    let url = SupabaseConfig.projectURL.appendingPathComponent("functions/v1").appendingPathComponent(functionName)
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
                    request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 120
                    var streamedBody = body; streamedBody["stream"] = true
                    request.httpBody = try JSONSerialization.data(withJSONObject: streamedBody)
                    for try await event in streamImageGeneration(request: request) {
                        try Task.checkCancellation()
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The same URLSession delegate transport is used by production and bounded URLProtocol tests.
    static func streamImageGeneration(request: URLRequest, configuration: URLSessionConfiguration? = nil) -> AsyncThrowingStream<ImageStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let config = configuration ?? .default
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 180
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            config.urlCache = nil
            let delegate = SSESessionDelegate()
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            delegate.configure(onEvent: { continuation.yield($0) }, onComplete: { error in
                if let error { continuation.finish(throwing: error) }
                else { continuation.finish() }
                session.finishTasksAndInvalidate()
            })
            let task = session.dataTask(with: request)
            continuation.onTermination = { _ in task.cancel(); session.invalidateAndCancel() }
            task.resume()
        }
    }

    /// Retained entry point; both callers share framing, terminal handling and cancellation.
    static func streamImageGenerationAsyncBytes(functionName: String, body: [String: Any]) -> AsyncThrowingStream<ImageStreamEvent, Error> {
        streamImageGeneration(functionName: functionName, body: body)
    }

    nonisolated static func parseImageEvent(_ payload: String) throws -> ImageStreamEvent? {
        if payload == "[DONE]" { return nil }
        guard let data = payload.data(using: .utf8),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = json["type"] as? String else {
            throw SSEStreamError.decodingError("Invalid image event")
        }
        switch type {
        case "partial":
            guard let base64 = json["imageBase64"] as? String, let image = Data(base64Encoded: base64), !image.isEmpty,
                  let index = json["index"] as? Int, index >= 0 else {
                throw SSEStreamError.decodingError("Invalid preview")
            }
            return .partial(index: index, imageData: image)
        case "complete":
            guard json["success"] as? Bool != false,
                  let base64 = json.removeValue(forKey: "imageBase64") as? String,
                  let image = Data(base64Encoded: base64), !image.isEmpty,
                  let source = CGImageSourceCreateWithData(image as CFData, nil),
                  CGImageSourceGetStatus(source) == .statusComplete, CGImageSourceGetCount(source) > 0,
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                throw SSEStreamError.decodingError("Invalid final image")
            }
            return .complete(imageData: image, metadata: json)
        case "error": return .error(SSEStreamError.serverError(json["message"] as? String ?? json["error"] as? String ?? "Image generation failed. Try again later.", code: json["code"] as? String))
        default: return nil
        }
    }
}
