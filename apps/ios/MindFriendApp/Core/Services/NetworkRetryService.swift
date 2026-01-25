//
//  NetworkRetryService.swift
//  MindFriendApp
//
//  Automatic retry with exponential backoff for network operations
//

import Foundation

/// Errors that can occur during network retry operations
enum NetworkRetryError: LocalizedError {
    case maxRetriesExceeded
    case permanentFailure(Error)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .maxRetriesExceeded:
            return "Operation failed after multiple attempts. Please check your connection and try again."
        case .permanentFailure(let error):
            return error.localizedDescription
        case .cancelled:
            return "Operation was cancelled."
        }
    }
}

/// Service for retrying network operations with exponential backoff
final class NetworkRetryService {

    // MARK: - Configuration

    private let maxRetries: Int
    private let initialDelay: TimeInterval
    private let maxDelay: TimeInterval
    private let backoffMultiplier: Double

    // MARK: - Initialization

    init(
        maxRetries: Int = 3,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        backoffMultiplier: Double = 2.0
    ) {
        self.maxRetries = maxRetries
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.backoffMultiplier = backoffMultiplier
    }

    // MARK: - Public Methods

    /// Execute operation with automatic retry on failure
    func execute<T>(
        _ operation: @escaping () async throws -> T,
        shouldRetry: ((Error) -> Bool)? = nil
    ) async throws -> T {
        var delay = initialDelay

        for attempt in 0..<maxRetries {
            // ✅ FIX: Check for cancellation before each attempt
            try Task.checkCancellation()
            
            do {
                return try await operation()
            } catch {
                // ✅ FIX: Check cancellation before retry
                if Task.isCancelled {
                    throw CancellationError()
                }
                
                guard attempt < maxRetries - 1 else {
                    throw NetworkRetryError.maxRetriesExceeded
                }

                // Check if error is retryable
                if let shouldRetry = shouldRetry, !shouldRetry(error) {
                    throw NetworkRetryError.permanentFailure(error)
                }

                // Wait before retrying with exponential backoff
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch is CancellationError {
                    // ✅ FIX: Handle sleep cancellation
                    throw CancellationError()
                }
                
                delay = min(delay * backoffMultiplier, maxDelay)
            }
        }

        throw NetworkRetryError.maxRetriesExceeded
    }

    /// Check if error is retryable (network-related)
    static func isRetryableError(_ error: Error) -> Bool {
        // URLError cases that should be retried
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .timedOut,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .resourceUnavailable,
                 .dataNotAllowed:
                return true
            default:
                return false
            }
        }

        // Check for common HTTP status codes that should be retried
        if let response = (error as NSError).userInfo["response"] as? HTTPURLResponse {
            switch response.statusCode {
            case 408,  // Request Timeout
                 429,  // Too Many Requests
                 500,  // Internal Server Error
                 502,  // Bad Gateway
                 503,  // Service Unavailable
                 504:  // Gateway Timeout
                return true
            default:
                return false
            }
        }

        return false
    }
}
