import Supabase
import SwiftUI

/// List view displaying all weekly stories with favorites filtering
struct NarrativeListView: View {
    @StateObject private var viewModel: NarrativeListViewModel
    @State private var showingPreferences = false

    init(dataService: SupabaseDataService) {
        _viewModel = StateObject(wrappedValue: NarrativeListViewModel(dataService: dataService))
    }

    /// Set by the stable shell so pushed work adds no second NavigationStack; standalone callers keep their own.
    @Environment(\.supportRootEmbedded) private var supportEmbedded

    var body: some View {
        SupportRootNavigation(embedded: supportEmbedded) {
            ZStack {
                if viewModel.isLoading && viewModel.stories.isEmpty {
                    ProgressView("Loading your stories...")
                } else if let error = viewModel.error, viewModel.stories.isEmpty {
                    SupportUnavailableState(
                        title: "Stories unavailable", message: error,
                        actionTitle: "Try again", action: { Task { await viewModel.fetchStories() } })
                } else if viewModel.stories.isEmpty {
                    emptyStateView
                } else {
                    storiesList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("My Stories")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingPreferences = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Story preferences")
                }
            }
            .sheet(isPresented: $showingPreferences) {
                NavigationStack {
                    NarrativePreferencesView(dataService: viewModel.dataService)
                }
            }
            .task {
                await viewModel.fetchStories()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundStyle(SupportTheme.textSecondary)

            Text(viewModel.showFavoritesOnly ? "No Favorite Stories" : "No Stories Yet")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.semibold)

            Text(
                viewModel.showFavoritesOnly
                    ? "Mark stories as favorites to see them here"
                    : "Your first weekly story will appear after your first week of activity"
            )
            .font(.body)
            .foregroundStyle(SupportTheme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)

            if viewModel.showFavoritesOnly {
                Button("Show All Stories") {
                    viewModel.toggleFavoritesFilter()
                }
                .buttonStyle(.supportPrimary)
            }
        }
        .padding()
    }

    // MARK: - Stories List

    private var storiesList: some View {
        List {
            if let error = viewModel.error {
                Section {
                    Text(error)
                    Button("Try again") { Task { await viewModel.refresh() } }
                }
                .listRowBackground(SupportTheme.surface)
            }
            // Filter toggle
            Section {
                Toggle(
                    "Favorites Only",
                    isOn: Binding(
                        get: { viewModel.showFavoritesOnly },
                        set: { _ in viewModel.toggleFavoritesFilter() }
                    ))
            }

            .listRowBackground(SupportTheme.surface)

            // Stories
            Section {
                ForEach(viewModel.stories) { story in
                    NavigationLink {
                        NarrativeDetailView(
                            story: story,
                            dataService: viewModel.dataService,
                            onUpdate: { updatedStory in
                                viewModel.updateStory(updatedStory)
                            }
                        )
                    } label: {
                        StoryRowView(story: story)
                    }
                    .onAppear {
                        Task {
                            await viewModel.loadMoreIfNeeded(currentStory: story)
                        }
                    }
                }

                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }

            .listRowBackground(SupportTheme.surface)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
}

// MARK: - Story Row

private struct StoryRowView: View {
    let story: WeeklyStory

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            HStack {
                Text(story.weekRangeFormatted)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                if story.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(SupportTheme.Celebration.gold)
                        .font(.caption)
                }

                if let rating = story.userRating {
                    Image(systemName: rating == 1 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .foregroundStyle(rating == 1 ? SupportTheme.accent : SupportTheme.textSecondary)
                        .font(.caption)
                }
            }

            Text(story.previewText)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .lineLimit(2)

            HStack(spacing: SupportTheme.Spacing.s) {
                Label("\(story.cards.filter { $0.cardType != .streak }.count)", systemImage: "rectangle.stack")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)

                Text(story.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .padding(.vertical, SupportTheme.Spacing.xxs)
    }
}

#Preview {
    NavigationStack {
        NarrativeListViewPreview()
    }
}

private struct NarrativeListViewPreview: View {
    var body: some View {
        NarrativeListView(dataService: createMockDataService())
    }

    private func createMockDataService() -> SupabaseDataService {
        return SupabaseDataService(authService: DependencyContainer.preview.supabaseAuthService)
    }
}
