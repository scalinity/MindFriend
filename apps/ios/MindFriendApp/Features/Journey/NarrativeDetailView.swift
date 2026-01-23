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

                // Story Cards
                ForEach(Array(viewModel.story.cards.enumerated()), id: \.element.id) { index, card in
                    StoryCardView(card: card)
                        .transition(.opacity.combined(with: .slide))
                        .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.1), value: viewModel.story.cards.count)
                }

                // Actions
                actionsSection

                Spacer(minLength: 20)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [viewModel.getShareText()])
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

private struct StoryCardView: View {
    let card: StoryCard

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Card header with type icon
            HStack {
                Image(systemName: card.cardType.iconName)
                    .foregroundStyle(.white)
                    .font(.title3)

                if let headline = card.data.headline {
                    Text(headline)
                        .font(.headline)
                        .foregroundStyle(.white)
                }

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
            if let message = card.data.message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }
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

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let sampleCard = StoryCard(
        id: UUID(),
        cardType: .mood,
        variant: .celebration,
        data: StoryCardData(
            headline: "Rising Up!",
            stat: "6.8",
            statLabel: "Average Mood",
            message: "Your mood is trending up! Small steps lead to big changes.",
            icon: nil,
            callToAction: nil,
            trend: "improving",
            checkinCount: 5,
            moodMin: 4.0,
            moodMax: 8.0,
            exerciseCount: nil,
            exerciseMinutes: nil,
            questCount: nil,
            streakDays: nil,
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
        NarrativeDetailView(
            story: sampleStory,
            dataService: SupabaseDataService.shared
        )
    }
}
