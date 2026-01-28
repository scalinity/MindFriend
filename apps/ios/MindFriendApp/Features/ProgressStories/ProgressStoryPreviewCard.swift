import SwiftUI

/// Preview card for Progress Stories shown on the Home screen
/// Tapping opens the full-screen story viewer
struct ProgressStoryPreviewCard: View {
    @EnvironmentObject private var container: DependencyContainer

    @State private var story: WeeklyStory?
    @State private var isLoading = false
    @State private var isGenerating = false
    @State private var showDetailView = false
    @State private var errorMessage: String?

    var body: some View {
        Button {
            if story != nil {
                showDetailView = true
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Label("Weekly Story", systemImage: "rectangle.stack.fill")
                        .font(.headline)

                    Spacer()

                    if story != nil {
                        Text("View")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .frame(height: 60)
                } else if let story = story, !story.cards.isEmpty {
                    // Card preview
                    storyPreview(story)
                } else {
                    // No story yet
                    noStoryView
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .disabled(story == nil)
        .task {
            await loadStory()
        }
        .sheet(isPresented: $showDetailView) {
            if let story = story {
                NavigationStack {
                    NarrativeDetailView(
                        story: story,
                        dataService: container.supabaseDataService,
                        onUpdate: { updatedStory in
                            self.story = updatedStory
                        }
                    )
                }
            }
        }
    }

    // MARK: - Story Preview

    @ViewBuilder
    private func storyPreview(_ story: WeeklyStory) -> some View {
        HStack(spacing: 8) {
            // Mini card previews (first 3 cards)
            ForEach(Array(story.cards.prefix(3).enumerated()), id: \.offset) { _, card in
                miniCardPreview(card)
            }

            // More indicator if > 3 cards
            if story.cards.count > 3 {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 50, height: 80)

                    Text("+\(story.cards.count - 3)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func miniCardPreview(_ card: StoryCard) -> some View {
        ZStack {
            // Gradient background
            LinearGradient(
                gradient: Gradient(colors: card.variant.gradientColors),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 2) {
                Image(systemName: card.cardType.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)

                if let stat = card.data.stat {
                    Text(stat)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 50, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - No Story View

    @ViewBuilder
    private var noStoryView: some View {
        VStack(spacing: 8) {
            if isGenerating {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Generating your story...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if let error = errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await loadStory() }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            } else {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text("Your weekly story will appear here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Load Story

    private func loadStory() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Calculate the Monday of the current week using UTC calendar
            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!

            let today = Date()
            let weekday = utcCalendar.component(.weekday, from: today)
            let daysFromMonday = weekday == 1 ? 6 : weekday - 2
            guard let currentMonday = utcCalendar.date(byAdding: .day, value: -daysFromMonday, to: today) else {
                return
            }

            // Format as YYYY-MM-DD in UTC for comparison
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            let currentWeekStart = formatter.string(from: currentMonday)
            
            // Fetch the most recent story (limit 1)
            let stories = try await container.supabaseDataService.fetchWeeklyStories(
                limit: 1,
                offset: 0,
                favoritesOnly: false
            )

            // Check if we have a story for the current week
            if let existingStory = stories.first, existingStory.weekStart == currentWeekStart {
                story = existingStory
                return
            }
            
            // No story for current week - trigger generation
            isGenerating = true
            defer { isGenerating = false }
            
            let generatedStory = try await container.supabaseDataService.generateWeeklyStory(weekStart: today)
            story = generatedStory
            
        } catch {
            // Silently fail - card will show "no story" state
            print("Failed to load/generate weekly story: \(error.localizedDescription)")
            errorMessage = "Unable to generate story"
        }
    }
}

// MARK: - Preview

#Preview {
    ProgressStoryPreviewCard()
        .environmentObject(DependencyContainer.preview)
        .padding()
}
