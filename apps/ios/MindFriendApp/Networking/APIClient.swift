import Foundation

/// HTTP client for API requests
actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private weak var sessionManager: SessionManager?

    init(baseURL: URL) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func setSessionManager(_ manager: SessionManager) {
        self.sessionManager = manager
    }

    // MARK: - Public Methods

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        let data = try await performRequest(endpoint)
        return try decoder.decode(T.self, from: data)
    }

    func requestVoid(_ endpoint: APIEndpoint) async throws {
        _ = try await performRequest(endpoint)
    }

    // MARK: - Private Methods

    private func performRequest(_ endpoint: APIEndpoint, isRetry: Bool = false) async throws -> Data {
        var request = try buildRequest(for: endpoint)

        // Add auth token if required
        if endpoint.requiresAuth {
            guard let token = await sessionManager?.getAccessToken() else {
                throw APIError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Handle 401 - try token refresh
        if httpResponse.statusCode == 401 && endpoint.requiresAuth && !isRetry {
            do {
                try await sessionManager?.refreshAccessToken()
                return try await performRequest(endpoint, isRetry: true)
            } catch {
                throw APIError.unauthorized
            }
        }

        // Handle errors
        if !(200...299).contains(httpResponse.statusCode) {
            throw try parseError(from: data, statusCode: httpResponse.statusCode)
        }

        return data
    }

    private func buildRequest(for endpoint: APIEndpoint) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: true)!
        components.queryItems = endpoint.queryItems

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = endpoint.body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        return request
    }

    private func parseError(from data: Data, statusCode: Int) throws -> APIError {
        if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
            switch errorResponse.code {
            case "AI_QUOTA_EXCEEDED":
                return .quotaExceeded(upgradeUrl: errorResponse.upgradeUrl)
            default:
                return .serverError(message: errorResponse.message, code: errorResponse.code)
            }
        }

        switch statusCode {
        case 400: return .badRequest
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 429: return .rateLimited
        case 500...599: return .serverError(message: "Server error", code: nil)
        default: return .unknown(statusCode: statusCode)
        }
    }
}

// MARK: - API Error

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case badRequest
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case quotaExceeded(upgradeUrl: String?)
    case serverError(message: String, code: String?)
    case networkError(Error)
    case decodingError(Error)
    case unknown(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .badRequest:
            return "Invalid request"
        case .unauthorized:
            return "Please sign in again"
        case .forbidden:
            return "Access denied"
        case .notFound:
            return "Not found"
        case .rateLimited:
            return "Too many requests. Please wait a moment."
        case .quotaExceeded:
            return "Daily message limit reached"
        case .serverError(let message, _):
            return message
        case .networkError:
            return "Network connection error"
        case .decodingError:
            return "Unable to process response"
        case .unknown(let code):
            return "Unknown error (code: \(code))"
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .networkError, .rateLimited, .serverError:
            return true
        default:
            return false
        }
    }
}

// MARK: - API Error Response

struct APIErrorResponse: Decodable {
    let message: String
    let code: String?
    let upgradeUrl: String?
}

