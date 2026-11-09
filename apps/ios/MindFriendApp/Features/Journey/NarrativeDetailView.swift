import Supabase
import SwiftUI

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
        _viewModel = StateObject(
            wrappedValue: NarrativeDetailViewModel(
                story: story,
                dataService: dataService
            ))
        self.onUpdate = onUpdate
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                // Header
                headerSection

                // Story cards
                ForEach(viewModel.story.cards.filter { $0.cardType != .streak }) { card in
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
        .alert(
            "Error", isPresented: Binding(get: { viewModel.error != nil }, set: { if !$0 { viewModel.error = nil } })
        ) {
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
        VStack(spacing: SupportTheme.Spacing.s) {
            Text(viewModel.story.weekRangeFormatted)
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.bold)

            HStack(spacing: SupportTheme.Spacing.m) {
                Label(
                    "\(viewModel.story.cards.filter { $0.cardType != .streak }.count) cards",
                    systemImage: "rectangle.stack"
                )
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)

                Text(viewModel.story.createdAt, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(SupportTheme.canvas)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            // Rating
            HStack(spacing: SupportTheme.Spacing.xl) {
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Button {
                        Task {
                            let newRating = viewModel.isThumbsUpActive ? nil : 1
                            await viewModel.rateStory(rating: newRating)
                        }
                    } label: {
                        Image(systemName: viewModel.isThumbsUpActive ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.title2)
                            .foregroundStyle(
                                viewModel.isThumbsUpActive ? SupportTheme.accent : SupportTheme.textSecondary)
                    }
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Helpful")
                    .disabled(viewModel.isUpdating)

                    Text("Helpful")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                VStack(spacing: SupportTheme.Spacing.xs) {
                    Button {
                        Task {
                            let newRating = viewModel.isThumbsDownActive ? nil : -1
                            await viewModel.rateStory(rating: newRating)
                        }
                    } label: {
                        Image(systemName: viewModel.isThumbsDownActive ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .font(.title2)
                            .foregroundStyle(
                                viewModel.isThumbsDownActive ? SupportTheme.textSecondary : SupportTheme.textSecondary)
                    }
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Not helpful")
                    .disabled(viewModel.isUpdating)

                    Text("Not helpful")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            Divider()

            // Favorite & Share
            HStack(alignment: .top, spacing: SupportTheme.Spacing.xl) {
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Button {
                        Task {
                            await viewModel.toggleFavorite()
                        }
                    } label: {
                        Image(systemName: viewModel.story.isFavorite ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(
                                viewModel.story.isFavorite ? SupportTheme.Celebration.gold : SupportTheme.textSecondary)
                    }
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel(viewModel.story.isFavorite ? "Remove from favorites" : "Add to favorites")
                    .disabled(viewModel.isUpdating)

                    Text(viewModel.story.isFavorite ? "Favorited" : "Favorite")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                VStack(spacing: SupportTheme.Spacing.xs) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Share")

                    Text("Share")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
        }
        .supportCard()
    }
}

// MARK: - Story Card View

private struct NarrativeStoryCardView: View {
    let card: StoryCard

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            // Card header with type icon
            HStack {
                Image(systemName: card.cardType.iconName)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .font(.title3)
                    .accessibilityAddTraits(.isHeader)

                Text(card.data.headline)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .foregroundStyle(SupportTheme.textPrimary)

                Spacer()
            }

            // Stats if present
            if let stat = card.data.stat, let statLabel = card.data.statLabel {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(stat)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(SupportTheme.textPrimary)

                    Text(statLabel)
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textPrimary.opacity(0.9))
                }
            }

            // Message
            Text(card.data.message)
                .font(.body)
                .foregroundStyle(SupportTheme.textPrimary.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SupportTheme.Spacing.l)
        .background(
            SupportTheme.surface
        )
        .cornerRadius(SupportTheme.controlRadius)
        .shadow(color: SupportTheme.canvas.opacity(0.1), radius: 8, x: 0, y: 4)
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
