import Foundation
import Combine

/// Manages mentorship messaging and conversations
@MainActor
final class MentorshipMessagingService: ObservableObject {
    @Published var messages: [MentorshipMessage] = []
    @Published var unreadCount = 0
    @Published var isLoading = false
    @Published var isSending = false
    @Published var error: Error?

    private let dataService: MentorshipDataService
    private let encryptionService: MentorshipEncryptionService?
    private var currentMatchId: UUID?
    private var updateTask: Task<Void, Never>?

    nonisolated init(dataService: MentorshipDataService, encryptionService: MentorshipEncryptionService? = nil) {
        self.dataService = dataService
        self.encryptionService = encryptionService
    }

    deinit {
        updateTask?.cancel()
    }

    // MARK: - Cleanup

    func cleanup() async {
        stopAutoUpdate()
        messages = []
        unreadCount = 0
        currentMatchId = nil
    }

    // MARK: - Loading Messages

    /// Load messages for a mentorship match
    func loadMessages(matchId: UUID, limit: Int = 50, offset: Int = 0) async {
        self.currentMatchId = matchId
        isLoading = true
        error = nil

        do {
            messages = try await dataService.fetchMessages(
                matchId: matchId,
                limit: limit,
                offset: offset
            )
            updateUnreadCount(matchId: matchId)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Load more messages (pagination)
    func loadMoreMessages(matchId: UUID, limit: Int = 50, offset: Int) async {
        isLoading = true
        error = nil

        do {
            let moreMessages = try await dataService.fetchMessages(
                matchId: matchId,
                limit: limit,
                offset: offset
            )
            messages.insert(contentsOf: moreMessages, at: 0)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Start auto-updating messages for a match
    func startAutoUpdate(matchId: UUID, interval: TimeInterval = 5) {
        updateTask?.cancel()

        currentMatchId = matchId
        updateTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    
                    if !Task.isCancelled {
                        let messages = try await dataService.fetchMessages(matchId: matchId)
                        self.messages = messages
                        updateUnreadCount(matchId: matchId)
                    }
                } catch {
                    // Silently handle cancellation
                    if !(error is CancellationError) {
                        self.error = error
                    }
                }
            }
        }
    }

    /// Stop auto-updating messages
    func stopAutoUpdate() {
        updateTask?.cancel()
        updateTask = nil
    }

    // MARK: - Sending Messages

    /// Send a message in the mentorship
    func sendMessage(matchId: UUID, content: String) async throws {
        isSending = true
        defer { isSending = false }

        let message = try await dataService.sendMessage(matchId: matchId, content: content)
        messages.append(message)
    }

    // MARK: - Message Management

    /// Mark all messages in match as read
    func markAsRead(matchId: UUID) async {
        error = nil

        do {
            try await dataService.markMessagesAsRead(matchId: matchId)
            
            // Update local messages
            for i in messages.indices {
                messages[i].isRead = true
            }
            
            updateUnreadCount(matchId: matchId)
        } catch {
            self.error = error
        }
    }

    /// Delete a message
    func deleteMessage(messageId: UUID) async throws {
        try await dataService.deleteMessage(messageId: messageId)

        // Remove from local messages
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages.remove(at: index)
        }
    }

    /// Flag a message for safety review
    func flagMessage(messageId: UUID, reason: String) async {
        error = nil

        do {
            try await dataService.flagMessage(messageId: messageId, reason: reason)

            // Update local message
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index].isFlagged = true
                messages[index].flaggedAt = Date()
            }
        } catch {
            self.error = error
        }
    }

    // MARK: - Private Helpers

    private func updateUnreadCount(matchId: UUID) {
        unreadCount = messages.filter { !($0.isRead ?? false) }.count
    }

    // MARK: - Computed Properties

    var hasMessages: Bool {
        !messages.isEmpty
    }

    var messageCount: Int {
        messages.count
    }

    var latestMessage: MentorshipMessage? {
        messages.last
    }

    var oldestMessage: MentorshipMessage? {
        messages.first
    }

    var hasUnreadMessages: Bool {
        unreadCount > 0
    }

    var flaggedMessages: [MentorshipMessage] {
        messages.filter { $0.isFlagged == true }
    }

    var unreadMessages: [MentorshipMessage] {
        messages.filter { !($0.isRead ?? false) }
    }

    /// Messages grouped by day
    var messagesByDay: [(date: Date, messages: [MentorshipMessage])] {
        let grouped = Dictionary(grouping: messages) { message -> Date in
            Calendar.current.startOfDay(for: message.createdAt)
        }

        return grouped
            .sorted { $0.key > $1.key }
            .map { (date: $0.key, messages: $0.value.sorted { $0.createdAt < $1.createdAt }) }
    }

    // MARK: - Filtering

    /// Filter messages by sender
    func messagesBySender(_ userId: UUID) -> [MentorshipMessage] {
        messages.filter { $0.senderId == userId }
    }

    /// Filter messages containing text
    func messagesContaining(_ text: String) -> [MentorshipMessage] {
        messages.filter { $0.content.localizedCaseInsensitiveContains(text) }
    }

    /// Filter messages after date
    func messagesAfter(_ date: Date) -> [MentorshipMessage] {
        messages.filter { $0.createdAt > date }
    }

    /// Filter messages before date
    func messagesBefore(_ date: Date) -> [MentorshipMessage] {
        messages.filter { $0.createdAt < date }
    }
}
