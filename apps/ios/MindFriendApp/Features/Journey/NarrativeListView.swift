import SwiftUI
import Supabase

/// List view displaying all weekly stories with favorites filtering
struct NarrativeListView: View {
    @StateObject private var viewModel: NarrativeListViewModel
    @State private var showingPreferences = false

    init(dataService: SupabaseDataService) {
        _viewModel = StateObject(wrappedValue: NarrativeListViewModel(dataService: dataService))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading && viewModel.stories.isEmpty {
                    ProgressView("Loading your stories...")
                } else if viewModel.stories.isEmpty {
                    emptyStateView
                } else {
                    storiesList
                }
            }
            .navigationTitle("My Stories")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingPreferences = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
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
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text(viewModel.showFavoritesOnly ? "No Favorite Stories" : "No Stories Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text(viewModel.showFavoritesOnly
                 ? "Mark stories as favorites to see them here"
                 : "Your first weekly story will appear after your first week of activity")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if viewModel.showFavoritesOnly {
                Button("Show All Stories") {
                    viewModel.toggleFavoritesFilter()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Stories List

    private var storiesList: some View {
        List {
            // Filter toggle
            Section {
                Toggle("Favorites Only", isOn: Binding(
                    get: { viewModel.showFavoritesOnly },
                    set: { _ in viewModel.toggleFavoritesFilter() }
                ))
            }

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
        }
        .refreshable {
            await viewModel.refresh()
        }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") {
                viewModel.error = nil
            }
        } message: {
            if let error = viewModel.error {
                Text(error)
            }
        }
    }
}

// MARK: - Story Row

private struct StoryRowView: View {
    let story: WeeklyStory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(story.weekRangeFormatted)
                    .font(.headline)

                Spacer()

                if story.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }

                if let rating = story.userRating {
                    Image(systemName: rating == 1 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .foregroundStyle(rating == 1 ? .blue : .secondary)
                        .font(.caption)
                }
            }

            Text(story.previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label("\(story.cards.count)", systemImage: "rectangle.stack")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(story.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
