// Board View - Thread list with sorting, filtering, and search
// Per architect plan Phase E2: Sort tabs (New/Popular/Helpful), search, pagination

import SwiftUI

struct BoardView: View {
    @StateObject private var viewModel: BoardViewModel
    @State private var showingCompose = false

    init(forumService: ForumService, board: ForumBoard) {
        _viewModel = StateObject(wrappedValue: BoardViewModel(forumService: forumService, board: board))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.threads.isEmpty {
                ProgressView("Loading discussions...")
            } else if viewModel.threads.isEmpty {
                emptyState
            } else {
                threadList
            }
        }
        .navigationTitle(viewModel.board.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCompose = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .searchable(text: $viewModel.searchQuery, prompt: "Search discussions")
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: $showingCompose) {
            ComposeThreadView(forumService: viewModel.forumService, boardId: viewModel.board.id)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView(
            "No Discussions Yet",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("Be the first to start a discussion in this board.")
        )
        .overlay(alignment: .bottom) {
            Button("Start Discussion") {
                showingCompose = true
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private var threadList: some View {
        List {
            // Sort picker
            Section {
                Picker("Sort By", selection: $viewModel.sortOrder) {
                    ForEach(ThreadSortOrder.allCases, id: \.self) { order in
                        Label(order.displayName, systemImage: order.icon)
                            .tag(order)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            // Threads
            ForEach(viewModel.threads) { thread in
                NavigationLink(value: thread) {
                    ThreadRowView(thread: thread)
                }
            }

            // Load more
            if viewModel.hasMore {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .task {
                        await viewModel.loadMore()
                    }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: ForumThread.self) { thread in
            ThreadView(forumService: viewModel.forumService, threadId: thread.id)
        }
    }
}

// MARK: - Thread Row

struct ThreadRowView: View {
    let thread: ForumThread

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(thread.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(2)

            // Preview
            Text(thread.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Metadata
            HStack(spacing: 12) {
                Label(thread.authorDisplayName, systemImage: "person.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(thread.createdAt.relativeTimeString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                if thread.replyCount > 0 {
                    Label("\(thread.replyCount)", systemImage: "bubble.left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if thread.helpfulCount > 0 {
                    Label("\(thread.helpfulCount)", systemImage: "hand.thumbsup")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ViewModel

@MainActor
final class BoardViewModel: ObservableObject {
    let forumService: ForumService
    let board: ForumBoard

    @Published var threads: [ForumThread] = []
    @Published var sortOrder: ThreadSortOrder = .new {
        didSet {
            if oldValue != sortOrder {
                Task { await refresh() }
            }
        }
    }
    @Published var searchQuery: String = "" {
        didSet {
            if oldValue != searchQuery {
                searchTask?.cancel()
                if searchQuery.isEmpty {
                    Task { await refresh() }
                } else if searchQuery.count >= 3 {
                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }
                        await search()
                    }
                }
            }
        }
    }

    @Published var isLoading = false
    @Published var hasMore = true

    private var searchTask: Task<Void, Never>?
    private var lastCursor: Date?

    init(forumService: ForumService, board: ForumBoard) {
        self.forumService = forumService
        self.board = board

        Task {
            await load()
        }
    }

    func load() async {
        isLoading = true
        lastCursor = nil
        hasMore = true

        do {
            threads = try await forumService.fetchThreads(
                boardId: board.id,
                sortBy: sortOrder,
                cursor: nil,
                limit: 20
            )
            hasMore = threads.count >= 20
            lastCursor = threads.last?.createdAt
        } catch {
            print("Error loading threads:", error)
        }

        isLoading = false
    }

    func loadMore() async {
        guard hasMore, !isLoading, let cursor = lastCursor else { return }

        isLoading = true

        do {
            let newThreads = try await forumService.fetchThreads(
                boardId: board.id,
                sortBy: sortOrder,
                cursor: cursor,
                limit: 20
            )
            threads.append(contentsOf: newThreads)
            hasMore = newThreads.count >= 20
            lastCursor = newThreads.last?.createdAt
        } catch {
            print("Error loading more threads:", error)
        }

        isLoading = false
    }

    func refresh() async {
        await load()
    }

    private func search() async {
        guard searchQuery.count >= 3 else { return }

        isLoading = true

        do {
            threads = try await forumService.searchThreads(
                query: searchQuery,
                boardId: board.id,
                cursor: nil,
                limit: 20
            )
            hasMore = false // No pagination for search results
        } catch {
            print("Error searching threads:", error)
        }

        isLoading = false
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Board View") {
    NavigationStack {
        BoardView(
            forumService: ForumService(supabase: .mock),
            board: ForumBoard(
                id: UUID(),
                categoryId: UUID(),
                name: "Anxiety & Stress",
                description: "Managing anxiety and stress together",
                position: 1,
                threadCount: 42,
                createdAt: Date()
            )
        )
    }
}
#endif
