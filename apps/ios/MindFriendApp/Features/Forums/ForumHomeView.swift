// Forum Home View - Categories and Boards
// Per architect plan Phase E1: Grid layout for categories, list for boards

import SwiftUI

struct ForumHomeView: View {
    @StateObject private var viewModel: ForumHomeViewModel
    @Environment(\.dismiss) private var dismiss

    init(forumService: ForumService) {
        _viewModel = StateObject(wrappedValue: ForumHomeViewModel(forumService: forumService))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading forums...")
                } else if let error = viewModel.error {
                    ContentUnavailableView(
                        "Unable to Load Forums",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    content
                }
            }
            .navigationTitle("Community")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Welcome header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to the MindFriend Community")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Share experiences, find support, and connect with others on their mental health journey.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                // Categories and boards
                ForEach(viewModel.categoriesWithBoards, id: \.0.id) { category, boards in
                    categorySection(category: category, boards: boards)
                }
            }
            .padding(.vertical)
        }
    }

    @ViewBuilder
    private func categorySection(category: ForumCategory, boards: [ForumBoard]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: category.icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text(category.name)
                    .font(.headline)
            }
            .padding(.horizontal)

            if let description = category.description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            // Boards list
            VStack(spacing: 0) {
                ForEach(boards) { board in
                    NavigationLink(value: board) {
                        boardRow(board: board)
                    }
                    .buttonStyle(.plain)

                    if board.id != boards.last?.id {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 8)
            .padding(.horizontal)
        }
        .navigationDestination(for: ForumBoard.self) { board in
            BoardView(forumService: viewModel.forumService, board: board)
        }
    }

    @ViewBuilder
    private func boardRow(board: ForumBoard) -> some View {
        HStack(spacing: 12) {
            // Icon (boards don't have individual icons, use default)
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 36)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(board.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                if let description = board.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text("\(board.threadCount) discussions")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}

// MARK: - ViewModel

@MainActor
final class ForumHomeViewModel: ObservableObject {
    let forumService: ForumService

    @Published var categoriesWithBoards: [(ForumCategory, [ForumBoard])] = []
    @Published var isLoading = false
    @Published var error: String?

    init(forumService: ForumService) {
        self.forumService = forumService
        Task {
            await load()
        }
    }

    func load() async {
        isLoading = true
        error = nil

        do {
            categoriesWithBoards = try await forumService.fetchCategoriesWithBoards()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func refresh() async {
        await load()
    }
}

// MARK: - Previews

#Preview("Forum Home") {
    ForumHomeView(forumService: ForumService(supabase: .mock))
}
