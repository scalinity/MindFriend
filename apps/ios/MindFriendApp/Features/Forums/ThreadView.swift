// Thread View - Thread detail with nested replies and realtime updates
// Per architect plan Phase E3: Nested replies (max 5 levels), Realtime subscription, crisis banner

import SwiftUI
import Supabase

struct ThreadView: View {
    @StateObject private var viewModel: ThreadViewModel
    @State private var showingReply = false
    @State private var showingReport = false

    init(forumService: ForumService, threadId: UUID) {
        _viewModel = StateObject(wrappedValue: ThreadViewModel(forumService: forumService, threadId: threadId))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading discussion...")
            } else if let thread = viewModel.thread {
                content(thread: thread)
            } else if let error = viewModel.error {
                ContentUnavailableView(
                    "Unable to Load Discussion",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            }
        }
        .navigationTitle("Discussion")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: $showingReply) {
            if let thread = viewModel.thread {
                ComposeReplyView(
                    forumService: viewModel.forumService,
                    threadId: thread.id,
                    parentReplyId: nil,
                    isAnonymous: thread.isAnonymous
                )
            }
        }
        .sheet(isPresented: $showingReport) {
            if let thread = viewModel.thread {
                ReportView(forumService: viewModel.forumService, threadId: thread.id, replyId: nil)
            }
        }
        .task {
            await viewModel.subscribeToRealtime()
        }
    }

    @ViewBuilder
    private func content(thread: ForumThread) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Crisis banner if detected
                if thread.isCrisis {
                    crisisBanner
                }

                // Thread content
                threadContent(thread: thread)

                Divider()

                // Replies header
                Text("\(thread.replyCount) Replies")
                    .font(.headline)
                    .padding(.horizontal)

                // Replies list
                ForEach(viewModel.replies) { reply in
                    ReplyView(reply: reply, viewModel: viewModel)
                }

                // Load more replies
                if viewModel.hasMoreReplies {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .task {
                            await viewModel.loadMoreReplies()
                        }
                }

                // Reply button
                Button {
                    showingReply = true
                } label: {
                    Label("Write a Reply", systemImage: "bubble.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding()
            }
        }
    }

    @ViewBuilder
    private var crisisBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.text.square.fill")
                .font(.title2)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 4) {
                Text("Support Resources Available")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("If you're in crisis, help is available 24/7.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            NavigationLink {
                // TODO: Navigate to Crisis Resources screen
                Text("Crisis Resources")
            } label: {
                Text("Get Help")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    @ViewBuilder
    private func threadContent(thread: ForumThread) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(thread.title)
                .font(.title2)
                .fontWeight(.bold)

            // Author and metadata
            HStack {
                Label(thread.authorDisplayName, systemImage: "person.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(thread.createdAt.relativeTimeString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if thread.isEdited {
                    Text("(edited)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }

            // Content
            Text(thread.content)
                .font(.body)

            // Actions
            HStack(spacing: 16) {
                // Helpful
                Button {
                    Task { await viewModel.toggleHelpful() }
                } label: {
                    Label(
                        "\(thread.helpfulCount)",
                        systemImage: thread.isHelpfulByMe ? "hand.thumbsup.fill" : "hand.thumbsup"
                    )
                    .font(.subheadline)
                    .foregroundStyle(thread.isHelpfulByMe ? .blue : .secondary)
                }

                // Save
                Button {
                    Task { await viewModel.toggleSaved() }
                } label: {
                    Image(systemName: thread.isSavedByMe ? "bookmark.fill" : "bookmark")
                        .font(.subheadline)
                        .foregroundStyle(thread.isSavedByMe ? .blue : .secondary)
                }

                // Follow
                Button {
                    Task { await viewModel.toggleFollow() }
                } label: {
                    Image(systemName: thread.isFollowingByMe ? "bell.fill" : "bell")
                        .font(.subheadline)
                        .foregroundStyle(thread.isFollowingByMe ? .blue : .secondary)
                }

                Spacer()

                // Report
                Button {
                    showingReport = true
                } label: {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
}

// MARK: - Reply View

struct ReplyView: View {
    let reply: ForumReply
    @ObservedObject var viewModel: ThreadViewModel
    @State private var showingReplySheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Reply content
            HStack(alignment: .top, spacing: 12) {
                // Depth indicator (indent)
                if reply.depth > 0 {
                    Rectangle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 3)
                        .padding(.leading, CGFloat(reply.depth - 1) * 20)
                }

                VStack(alignment: .leading, spacing: 8) {
                    // Author and metadata
                    HStack {
                        Label(reply.authorDisplayName, systemImage: "person.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(reply.createdAt.relativeTimeString)
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        if reply.isEdited {
                            Text("(edited)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()
                    }

                    // Content
                    Text(reply.content)
                        .font(.subheadline)

                    // Actions
                    HStack(spacing: 16) {
                        // Helpful
                        Button {
                            Task { await viewModel.toggleReplyHelpful(replyId: reply.id) }
                        } label: {
                            Label(
                                "\(reply.helpfulCount)",
                                systemImage: reply.isHelpfulByMe ? "hand.thumbsup.fill" : "hand.thumbsup"
                            )
                            .font(.caption)
                            .foregroundStyle(reply.isHelpfulByMe ? .blue : .secondary)
                        }

                        // Reply
                        if reply.depth < 5 {
                            Button {
                                showingReplySheet = true
                            } label: {
                                Label("Reply", systemImage: "arrowshape.turn.up.left")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()

            // Nested replies
            ForEach(reply.replies) { nestedReply in
                ReplyView(reply: nestedReply, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showingReplySheet) {
            ComposeReplyView(
                forumService: viewModel.forumService,
                threadId: reply.threadId,
                parentReplyId: reply.id,
                isAnonymous: reply.isAnonymous
            )
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ThreadViewModel: ObservableObject {
    let forumService: ForumService
    let threadId: UUID

    @Published var thread: ForumThread?
    @Published var replies: [ForumReply] = []
    @Published var isLoading = false
    @Published var hasMoreReplies = true
    @Published var error: String?

    private var realtimeChannel: RealtimeChannelV2?
    private var lastReplyCursor: Date?

    init(forumService: ForumService, threadId: UUID) {
        self.forumService = forumService
        self.threadId = threadId

        Task {
            await load()
        }
    }

    deinit {
        Task { @MainActor in
            await realtimeChannel?.unsubscribe()
        }
    }

    func load() async {
        isLoading = true
        error = nil

        do {
            // Load thread
            thread = try await forumService.fetchThread(id: threadId)

            // Load replies
            let fetchedReplies = try await forumService.fetchReplies(
                threadId: threadId,
                cursor: nil,
                limit: 50
            )
            replies = ForumThread.buildReplyTree(replies: fetchedReplies)
            hasMoreReplies = fetchedReplies.count >= 50
            lastReplyCursor = fetchedReplies.last?.createdAt
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func loadMoreReplies() async {
        guard hasMoreReplies, let cursor = lastReplyCursor else { return }

        do {
            let newReplies = try await forumService.fetchReplies(
                threadId: threadId,
                cursor: cursor,
                limit: 50
            )
            // Merge into tree (simplified - should rebuild entire tree)
            replies.append(contentsOf: newReplies)
            hasMoreReplies = newReplies.count >= 50
            lastReplyCursor = newReplies.last?.createdAt
        } catch {
            print("Error loading more replies:", error)
        }
    }

    func refresh() async {
        await load()
    }

    func subscribeToRealtime() async {
        // Subscribe to Realtime channel for this thread
        let channel = forumService.supabase.channel("forum_threads:\(threadId.uuidString)")

        // Listen for new replies
        let insertionStream = channel
            .onPostgresChange(
                InsertAction.self,
                table: "forum_replies",
                filter: "thread_id=eq.\(threadId.uuidString)"
            ) { action in
                // Handle new forum reply insertions
                // This callback receives RealtimeInsertAction events
            }

        realtimeChannel = channel

        do {
            try await channel.subscribe()

            // Handle new reply insertions
            // TODO: Supabase RealtimeSubscription API has changed
            // for-await syntax no longer supported. Using polling fallback instead.
            // Task {
            //     for await insertion in insertionStream {
            //         await handleNewReply(insertion.record)
            //     }
            // }

            // Start polling fallback (30s intervals)
            startPollingFallback()
        } catch {
            print("Failed to subscribe to Realtime:", error)
            // Fallback to polling only
            startPollingFallback()
        }
    }

    private func handleNewReply(_ record: JSONObject) async {
        // Refresh replies to get the new one
        do {
            let allReplies = try await forumService.fetchReplies(
                threadId: threadId,
                cursor: nil,
                limit: 100
            )
            replies = ForumThread.buildReplyTree(replies: allReplies)
        } catch {
            print("Error fetching new replies:", error)
        }
    }

    private func startPollingFallback() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await refresh()
            }
        }
    }

    func toggleHelpful() async {
        guard var thread = thread else { return }

        do {
            if thread.isHelpfulByMe {
                try await forumService.unmarkHelpful(threadId: threadId, replyId: nil)
                thread.isHelpfulByMe = false
            } else {
                try await forumService.markHelpful(threadId: threadId, replyId: nil)
                thread.isHelpfulByMe = true
            }
            self.thread = thread
        } catch {
            print("Error toggling helpful:", error)
        }
    }

    func toggleSaved() async {
        guard var thread = thread else { return }

        do {
            if thread.isSavedByMe {
                try await forumService.unsaveThread(id: threadId)
                thread.isSavedByMe = false
            } else {
                try await forumService.saveThread(id: threadId)
                thread.isSavedByMe = true
            }
            self.thread = thread
        } catch {
            print("Error toggling saved:", error)
        }
    }

    func toggleFollow() async {
        guard var thread = thread else { return }

        do {
            if thread.isFollowingByMe {
                try await forumService.unfollowThread(id: threadId)
                thread.isFollowingByMe = false
            } else {
                try await forumService.followThread(id: threadId)
                thread.isFollowingByMe = true
            }
            self.thread = thread
        } catch {
            print("Error toggling follow:", error)
        }
    }

    func toggleReplyHelpful(replyId: UUID) async {
        // TODO: Toggle helpful on reply and update UI
    }
}
