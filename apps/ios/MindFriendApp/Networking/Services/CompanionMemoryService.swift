import Foundation
import Supabase

/// Service for managing companion memories and daily intents
@MainActor
final class CompanionMemoryService: ObservableObject {
    private let authService: SupabaseAuthService
    private let supabase: SupabaseClient
    private var binding: OfflineOwnerProof?
    private var isCurrent: (() -> Bool)?
    private let requestSession: URLSession

    @Published private(set) var memories: [CompanionMemory] = []
    @Published private(set) var dailyIntent: DailyIntent?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var totalCount = 0
    @Published private(set) var maxLimit = 20

    init(authService: SupabaseAuthService, supabase: SupabaseClient, requestSession: URLSession? = nil) {
        self.authService = authService
        self.supabase = supabase
        self.requestSession = requestSession ?? URLSession(configuration: .ephemeral, delegate: MemoryRequestRedirectDelegate(), delegateQueue: nil)
    }

    func bind(_ binding: OfflineOwnerProof, isCurrent: @escaping () -> Bool) {
        if self.binding != binding { unbind() }
        self.binding = binding
        self.isCurrent = isCurrent
    }

    func unbind() {
        binding = nil; isCurrent = nil
        memories = []; dailyIntent = nil; totalCount = 0; isLoading = false; error = nil
    }

    private struct EmptyBody: Encodable {}

    /// Fixed-host raw requests retain the token captured with their owner. The SDK may replace supplied auth headers.
    private func invoke<Response: Decodable, Body: Encodable>(_ endpoint: String, body: Body) async throws -> Response {
        guard let captured = binding, isCurrent?() == true, authService.userId == captured.userId else { throw CancellationError() }
        try await authService.ensureValidSession()
        guard binding == captured, isCurrent?() == true, let session = authService.session,
              session.user.id == captured.userId else { throw CancellationError() }
        let url = SupabaseConfig.projectURL.appendingPathComponent("functions/v1/" + endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await requestSession.data(for: request) }
        catch {
            guard binding == captured, isCurrent?() == true else { throw CancellationError() }
            throw error
        }
        guard binding == captured, isCurrent?() == true, authService.userId == captured.userId, !Task.isCancelled else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.url?.host == url.host, data.count <= 1_048_576 else {
            throw CompanionMemoryError.serverError("Account context could not be confirmed. Refresh it before trying again.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = SupportChatTimestamp.date(value) else { throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid account date") }
            return date
        }
        return try decoder.decode(Response.self, from: data)
    }

    /// Whether the memory limit has been reached
    var isLimitReached: Bool {
        totalCount >= maxLimit
    }

    /// Number of remaining memory slots
    var remainingSlots: Int {
        max(0, maxLimit - totalCount)
    }

    // MARK: - Fetch Memories

    /// Fetches all companion memories and the current daily intent
    func fetchMemories() async {
        guard let captured = binding, isCurrent?() == true else { return }
        isLoading = true
        error = nil

        do {
            let response: GetMemoryResponse = try await invoke("get-companion-memory", body: EmptyBody())

            memories = response.memories
            dailyIntent = response.dailyIntent
            totalCount = response.totalCount
            maxLimit = response.maxLimit
        } catch {
            guard binding == captured, isCurrent?() == true else { return }
            self.error = "Account context could not be loaded. Try again when ready."
        }

        if binding == captured { isLoading = false }
    }

    // MARK: - Create Memory

    /// Creates a new companion memory
    /// - Parameters:
    ///   - category: The category for the memory
    ///   - content: The memory content (max 500 characters)
    /// - Returns: The created memory
    @discardableResult
    func createMemory(category: MemoryCategory, content: String) async throws -> CompanionMemory {
        guard !isLimitReached else {
            throw CompanionMemoryError.limitReached
        }

        guard content.count <= 500 else {
            throw CompanionMemoryError.contentTooLong
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CompanionMemoryError.emptyContent
        }

        let request = UpdateMemoryRequest.memory(category: category, content: content)

        let response: UpdateMemoryResponse = try await invoke("update-companion-memory", body: request)

        guard response.success, let memory = response.memory else {
            throw CompanionMemoryError.serverError(response.error ?? "Unknown error")
        }

        // Update local state
        memories.insert(memory, at: 0)
        totalCount += 1

        return memory
    }

    // MARK: - Update Memory

    /// Updates an existing companion memory
    /// - Parameters:
    ///   - id: The memory ID to update
    ///   - category: The new category
    ///   - content: The new content
    /// - Returns: The updated memory
    @discardableResult
    func updateMemory(id: String, category: MemoryCategory, content: String) async throws -> CompanionMemory {
        guard content.count <= 500 else {
            throw CompanionMemoryError.contentTooLong
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CompanionMemoryError.emptyContent
        }

        let request = UpdateMemoryRequest.memory(id: id, category: category, content: content)

        let response: UpdateMemoryResponse = try await invoke("update-companion-memory", body: request)

        guard response.success, let memory = response.memory else {
            throw CompanionMemoryError.serverError(response.error ?? "Unknown error")
        }

        // Update local state
        if let index = memories.firstIndex(where: { $0.id == id }) {
            memories[index] = memory
        }

        return memory
    }

    // MARK: - Delete Memory

    /// Deletes a companion memory
    /// - Parameter id: The memory ID to delete
    func deleteMemory(id: String) async throws {
        let request = DeleteMemoryRequest.memory(id: id)

        let response: DeleteMemoryResponse = try await invoke("delete-companion-memory", body: request)

        guard response.success else {
            throw CompanionMemoryError.serverError(response.error ?? "Unknown error")
        }

        // Update local state
        memories.removeAll { $0.id == id }
        totalCount = max(0, totalCount - 1)
    }

    // MARK: - Daily Intent

    /// Sets a new daily intent
    /// - Parameter text: The intent text (max 140 characters)
    /// - Returns: The created intent
    @discardableResult
    func setDailyIntent(_ text: String) async throws -> DailyIntent {
        guard text.count <= 140 else {
            throw CompanionMemoryError.intentTooLong
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CompanionMemoryError.emptyIntent
        }

        let request = UpdateMemoryRequest.intent(text)

        let response: UpdateMemoryResponse = try await invoke("update-companion-memory", body: request)

        guard response.success, let intent = response.dailyIntent else {
            throw CompanionMemoryError.serverError(response.error ?? "Unknown error")
        }

        // Update local state
        dailyIntent = intent

        return intent
    }

    /// Clears the current daily intent
    func clearDailyIntent() async throws {
        let request = DeleteMemoryRequest.intent()

        let response: DeleteMemoryResponse = try await invoke("delete-companion-memory", body: request)

        guard response.success else {
            throw CompanionMemoryError.serverError(response.error ?? "Unknown error")
        }

        // Update local state
        dailyIntent = nil
    }

    // MARK: - Helpers

    /// Get memories grouped by category
    func memoriesByCategory() -> [MemoryCategory: [CompanionMemory]] {
        Dictionary(grouping: memories, by: { $0.category })
    }

    /// Get memories filtered by category
    func memories(for category: MemoryCategory) -> [CompanionMemory] {
        memories.filter { $0.category == category }
    }
}

// MARK: - Errors

enum CompanionMemoryError: LocalizedError {
    case limitReached
    case contentTooLong
    case emptyContent
    case intentTooLong
    case emptyIntent
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .limitReached:
            return "Memory limit reached (20/20). Delete a memory before adding a new one."
        case .contentTooLong:
            return "Memory content must be 500 characters or less."
        case .emptyContent:
            return "Memory content cannot be empty."
        case .intentTooLong:
            return "Daily intent must be 140 characters or less."
        case .emptyIntent:
            return "Daily intent cannot be empty."
        case .serverError(let message):
            return message
        }
    }
}

private final class MemoryRequestRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
