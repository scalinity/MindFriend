import Foundation
import Supabase

/// Service for managing companion memories and daily intents
@MainActor
final class CompanionMemoryService: ObservableObject {
    private let authService: SupabaseAuthService
    private let supabase: SupabaseClient

    @Published private(set) var memories: [CompanionMemory] = []
    @Published private(set) var dailyIntent: DailyIntent?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var totalCount = 0
    @Published private(set) var maxLimit = 20

    init(authService: SupabaseAuthService, supabase: SupabaseClient) {
        self.authService = authService
        self.supabase = supabase
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
        isLoading = true
        error = nil

        do {
            let response: GetMemoryResponse = try await supabase.functions
                .invoke(
                    "get-companion-memory",
                    options: FunctionInvokeOptions(
                        headers: authService.authHeaders
                    )
                )

            memories = response.memories
            dailyIntent = response.dailyIntent
            totalCount = response.totalCount
            maxLimit = response.maxLimit
        } catch {
            self.error = "Failed to load memories: \(error.localizedDescription)"
        }

        isLoading = false
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

        let response: UpdateMemoryResponse = try await supabase.functions
            .invoke(
                "update-companion-memory",
                options: FunctionInvokeOptions(
                    headers: authService.authHeaders,
                    body: request
                )
            )

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

        let response: UpdateMemoryResponse = try await supabase.functions
            .invoke(
                "update-companion-memory",
                options: FunctionInvokeOptions(
                    headers: authService.authHeaders,
                    body: request
                )
            )

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

        let response: DeleteMemoryResponse = try await supabase.functions
            .invoke(
                "delete-companion-memory",
                options: FunctionInvokeOptions(
                    headers: authService.authHeaders,
                    body: request
                )
            )

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

        let response: UpdateMemoryResponse = try await supabase.functions
            .invoke(
                "update-companion-memory",
                options: FunctionInvokeOptions(
                    headers: authService.authHeaders,
                    body: request
                )
            )

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

        let response: DeleteMemoryResponse = try await supabase.functions
            .invoke(
                "delete-companion-memory",
                options: FunctionInvokeOptions(
                    headers: authService.authHeaders,
                    body: request
                )
            )

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
