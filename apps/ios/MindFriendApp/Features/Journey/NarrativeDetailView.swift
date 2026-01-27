import SwiftUI
import Supabase

/// Detail view for a single weekly story with cards, rating, and favorite actions
struct NarrativeDetailView: View {
    @StateObject private var viewModel: NarrativeDetailViewModel
    @State private var showShareSheet = false

    let onUpdate: ((WeeklyStory) -> Void)?

    init(
        story: WeeklyStory,
        dataService: SupabaseDataService,
        onUpdate: ((WeeklyStory) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: NarrativeDetailViewModel(
            story: story,
            dataService: dataService
        ))
        self.onUpdate = onUpdate
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Story cards
                ForEach(viewModel.story.cards) { card in
                    NarrativeStoryCardView(card: card)
                }

                // Actions
                actionsSection

                Spacer(minLength: 20)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [viewModel.getShareText()])
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
        .onChange(of: viewModel.story) { _, newStory in
            onUpdate?(newStory)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Text(viewModel.story.weekRangeFormatted)
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 16) {
                Label("\(viewModel.story.cards.count) cards", systemImage: "rectangle.stack")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(viewModel.story.createdAt, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 20) {
            // Rating
            HStack(spacing: 40) {
                VStack(spacing: 8) {
                    Button {
                        Task {
                            let newRating = viewModel.isThumbsUpActive ? nil : 1
                            await viewModel.rateStory(rating: newRating)
                        }
                    } label: {
                        Image(systemName: viewModel.isThumbsUpActive ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.title2)
                            .foregroundStyle(viewModel.isThumbsUpActive ? .blue : .secondary)
                    }
                    .disabled(viewModel.isUpdating)

                    Text("Helpful")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    Button {
                        Task {
                            let newRating = viewModel.isThumbsDownActive ? nil : -1
                            await viewModel.rateStory(rating: newRating)
                        }
                    } label: {
                        Image(systemName: viewModel.isThumbsDownActive ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .font(.title2)
                            .foregroundStyle(viewModel.isThumbsDownActive ? .secondary : .secondary)
                    }
                    .disabled(viewModel.isUpdating)

                    Text("Not helpful")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Favorite & Share
            HStack(spacing: 20) {
                Button {
                    Task {
                        await viewModel.toggleFavorite()
                    }
                } label: {
                    Label(
                        viewModel.story.isFavorite ? "Favorited" : "Add to Favorites",
                        systemImage: viewModel.story.isFavorite ? "star.fill" : "star"
                    )
                    .foregroundStyle(viewModel.story.isFavorite ? .yellow : .blue)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isUpdating)

                Button {
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Story Card View

private struct NarrativeStoryCardView: View {
    let card: StoryCard

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Card header with type icon
            HStack {
                Image(systemName: card.cardType.iconName)
                    .foregroundStyle(.white)
                    .font(.title3)

                Text(card.data.headline)
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()
            }

            // Stats if present
            if let stat = card.data.stat, let statLabel = card.data.statLabel {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stat)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.white)

                    Text(statLabel)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            // Message
            Text(card.data.message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: card.variant.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    let sampleCard = StoryCard(
        id: UUID(),
        cardType: .mood,
        variant: .celebration,
        data: StoryCardData(
            headline: "Rising Up!",
            message: "Your mood is trending up! Small steps lead to big changes.",
            stat: "6.8",
            statLabel: "Average Mood",
            icon: nil,
            callToAction: nil,
            streakDays: nil,
            trend: "improving",
            checkinCount: 5,
            moodMin: 4.0,
            moodMax: 8.0,
            exerciseCount: nil,
            exerciseMinutes: nil,
            questCount: nil,
            aiGenerated: nil,
            milestoneType: nil
        ),
        generatedAt: Date()
    )

    let sampleStory = WeeklyStory(
        id: UUID(),
        userId: UUID(),
        weekStart: "2026-01-20",
        cards: [sampleCard],
        createdAt: Date(),
        updatedAt: Date(),
        userRating: nil,
        isFavorite: false
    )

    NavigationStack {
        NarrativeDetailViewPreview(story: sampleStory)
    }
}

private struct NarrativeDetailViewPreview: View {
    let story: WeeklyStory

    var body: some View {
        NarrativeDetailView(
            story: story,
            dataService: createMockDataService()
        )
    }

    private func createMockDataService() -> SupabaseDataService {
        return SupabaseDataService(authService: DependencyContainer.preview.supabaseAuthService)
    }
}
