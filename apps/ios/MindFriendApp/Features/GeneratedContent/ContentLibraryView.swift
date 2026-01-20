import SwiftUI

/// View displaying user's library of generated content
struct ContentLibraryView: View {
    @StateObject private var viewModel: ContentLibraryViewModel

    init(service: GeneratedContentService) {
        _viewModel = StateObject(wrappedValue: ContentLibraryViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.content.isEmpty {
                    loadingView
                } else if viewModel.content.isEmpty && !viewModel.isLoading {
                    emptyView
                } else {
                    contentList
                }
            }
            .navigationTitle("My Content")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showCreateSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            viewModel.filterType = nil
                        } label: {
                            Label("All Types", systemImage: viewModel.filterType == nil ? "checkmark" : "")
                        }

                        Divider()

                        ForEach(GeneratedContentType.allCases) { type in
                            Button {
                                viewModel.filterType = type
                            } label: {
                                Label(type.displayName, systemImage: viewModel.filterType == type ? "checkmark" : type.icon)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showCreateSheet) {
                ContentRequestView(service: viewModel.service)
            }
            .sheet(item: $viewModel.selectedContent) { content in
                ContentPlayerSheet(content: content, service: viewModel.service)
            }
            .refreshable {
                await viewModel.loadContent()
            }
        }
        .task {
            await viewModel.loadContent()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading your content...")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Content Yet", systemImage: "sparkles")
        } description: {
            Text("Create personalized meditations, sleep stories, and more with AI")
        } actions: {
            Button {
                viewModel.showCreateSheet = true
            } label: {
                Text("Create Content")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Content List

    private var contentList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Quick filters
                filterChips

                // Favorites section
                if viewModel.filterType == nil && !viewModel.favorites.isEmpty {
                    favoritesSection
                }

                // Recent section
                recentSection
            }
            .padding()
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ContentFilterChip(
                    title: "All",
                    isSelected: viewModel.filterType == nil,
                    action: { viewModel.filterType = nil }
                )

                ContentFilterChip(
                    title: "Favorites",
                    icon: "heart.fill",
                    isSelected: viewModel.showFavoritesOnly,
                    action: { viewModel.showFavoritesOnly.toggle() }
                )

                ForEach(GeneratedContentType.allCases) { type in
                    ContentFilterChip(
                        title: type.displayName,
                        icon: type.icon,
                        isSelected: viewModel.filterType == type,
                        action: { viewModel.filterType = type }
                    )
                }
            }
        }
    }

    // MARK: - Favorites Section

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("Favorites")
                    .font(.headline)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.favorites) { content in
                        ContentCard(content: content, compact: true) {
                            viewModel.selectedContent = content
                        }
                        .frame(width: 160)
                    }
                }
            }
        }
    }

    // MARK: - Recent Section

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.filterType?.displayName ?? "Recent")
                .font(.headline)

            ForEach(viewModel.filteredContent) { content in
                ContentCard(content: content, compact: false) {
                    viewModel.selectedContent = content
                }
            }
        }
    }
}

// MARK: - Filter Chip

private struct ContentFilterChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(.systemGray6))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Content Card

private struct ContentCard: View {
    let content: GeneratedContent
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if compact {
                compactLayout
            } else {
                fullLayout
            }
        }
        .buttonStyle(.plain)
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(height: 80)

                Image(systemName: content.contentType.icon)
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
            }

            Text(content.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)

            HStack {
                if content.hasAudio {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(content.formattedDuration)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fullLayout: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 60, height: 60)

                Image(systemName: content.contentType.icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(content.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(content.contentType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if content.hasAudio {
                        Label(content.formattedDuration, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Rating
                if let rating = content.averageRating {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= Int(rating.rounded()) ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                        Text("(\(content.ratingCount))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Favorite indicator
            if content.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Content Player Sheet

private struct ContentPlayerSheet: View {
    let content: GeneratedContent
    let service: GeneratedContentService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentPlayerView(content: content, service: service)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - View Model

@MainActor
final class ContentLibraryViewModel: ObservableObject {
    let service: GeneratedContentService

    @Published var content: [GeneratedContent] = []
    @Published var favorites: [GeneratedContent] = []
    @Published var isLoading = false
    @Published var filterType: GeneratedContentType?
    @Published var showFavoritesOnly = false
    @Published var selectedContent: GeneratedContent?
    @Published var showCreateSheet = false

    var filteredContent: [GeneratedContent] {
        var result = content

        if let filterType = filterType {
            result = result.filter { $0.contentType == filterType }
        }

        if showFavoritesOnly {
            result = result.filter { $0.isFavorite }
        }

        return result
    }

    init(service: GeneratedContentService) {
        self.service = service
    }

    func loadContent() async {
        isLoading = true

        do {
            async let contentTask = service.fetchContentLibrary()
            async let favoritesTask = service.fetchFavorites()

            let (loadedContent, loadedFavorites) = try await (contentTask, favoritesTask)
            content = loadedContent
            favorites = loadedFavorites
        } catch {
            // Handle error silently for now
            print("Error loading content: \(error)")
        }

        isLoading = false
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ContentLibraryView(service: .preview)
}
#endif
