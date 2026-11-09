import SwiftUI

/// Session-level cache so scrolling the card in/out of a LazyVStack doesn't
/// re-fire the edge-function call and thrash layout (which previously wedged
/// HomeView's scroll position after scrolling to the bottom).
///
/// Must be cleared on sign-out (see `ProgressStoryLoadCache.clear`) — otherwise
/// a different user signing in on the same process would see the previous
/// user's weekly story because entries are keyed by week start, not user id.
@MainActor
enum ProgressStoryLoadCache {
    static var stories: [String: WeeklyStory] = [:]
    static var failedWeeks: Set<String> = []
    static var inFlight: [String: Task<Void, Never>] = [:]

    static func clear() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        stories.removeAll()
        failedWeeks.removeAll()
    }
}

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
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                // Header
                HStack {
                    Label("Weekly Story", systemImage: "rectangle.stack.fill")
                        .font(.headline)

                    Spacer()

                    if story != nil {
                        Text("View")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .frame(height: 60)
                } else if let story = story, !story.cards.filter { $0.cardType != .streak }.isEmpty {
                    // Card preview
                    storyPreview(story)
                } else {
                    // No story yet
                    noStoryView
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SupportTheme.surface)
            .cornerRadius(SupportTheme.controlRadius)
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
        HStack(spacing: SupportTheme.Spacing.xs) {
            // Mini card previews (first 3 cards)
            ForEach(Array(story.cards.filter { $0.cardType != .streak }.prefix(3).enumerated()), id: \.offset) {
                _, card in
                miniCardPreview(card)
            }

            // More indicator if > 3 cards
            if story.cards.filter { $0.cardType != .streak }.count > 3 {
                ZStack {
                    RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                        .fill(SupportTheme.textSecondary.opacity(0.2))
                        .frame(width: 50, height: 80)

                    Text("+\(story.cards.filter { $0.cardType != .streak }.count - 3)")
                        .font(.caption.bold())
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func miniCardPreview(_ card: StoryCard) -> some View {
        ZStack {
            // Gradient background
            SupportTheme.surface

            VStack(spacing: SupportTheme.Spacing.xxs) {
                Image(systemName: card.cardType.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(SupportTheme.textPrimary)

                if let stat = card.data.stat {
                    Text(stat)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SupportTheme.textPrimary)
                }
            }
        }
        .frame(width: 50, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }

    // MARK: - No Story View

    @ViewBuilder
    private var noStoryView: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            if isGenerating {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Generating your story...")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
            } else if let error = errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(SupportTheme.accent)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await loadStory() }
                }
                .font(.caption)
                .buttonStyle(.supportSecondary)
            } else {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(SupportTheme.textSecondary)

                Text("Your weekly story will appear here")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SupportTheme.Spacing.xs)
    }

    // MARK: - Load Story

    private func loadStory() async {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        let today = Date()
        let weekday = utcCalendar.component(.weekday, from: today)
        let daysFromMonday = weekday == 1 ? 6 : weekday - 2
        guard let currentMonday = utcCalendar.date(byAdding: .day, value: -daysFromMonday, to: today) else {
            return
        }

        let currentWeekStart = HabitDateFormatter.dayOnly.string(from: currentMonday)

        // Session cache: if we already have a story or a terminal failure for
        // this week, hydrate local state and skip the network call. Prevents
        // LazyVStack recycling from re-firing the edge function on every scroll.
        if let cached = ProgressStoryLoadCache.stories[currentWeekStart] {
            story = cached
            return
        }
        if ProgressStoryLoadCache.failedWeeks.contains(currentWeekStart) {
            errorMessage = "Unable to generate story"
            return
        }

        // De-dupe concurrent loads: if a fetch is already in flight for this
        // week (e.g. the card is rendered in multiple places, or .task re-fires
        // before the previous finishes), await its completion and re-read cache.
        if let existing = ProgressStoryLoadCache.inFlight[currentWeekStart] {
            await existing.value
            story = ProgressStoryLoadCache.stories[currentWeekStart]
            if story == nil, ProgressStoryLoadCache.failedWeeks.contains(currentWeekStart) {
                errorMessage = "Unable to generate story"
            }
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let task = Task<Void, Never> { @MainActor in
            do {
                let stories = try await container.supabaseDataService.fetchWeeklyStories(
                    limit: 1,
                    offset: 0,
                    favoritesOnly: false
                )

                if let existingStory = stories.first, existingStory.weekStart == currentWeekStart {
                    ProgressStoryLoadCache.stories[currentWeekStart] = existingStory
                    return
                }

                isGenerating = true
                defer { isGenerating = false }

                let generatedStory = try await container.supabaseDataService.generateWeeklyStory(weekStart: today)
                ProgressStoryLoadCache.stories[currentWeekStart] = generatedStory
            } catch is CancellationError {
                // Don't mark this week as failed on cancellation — let the next
                // attempt try fresh. Avoids the loop where scroll cancels load
                // then the cached "failed" state blocks every subsequent retry.
                return
            } catch {
                #if DEBUG
                    print("Failed to load/generate weekly story: \(error.localizedDescription)")
                #endif
                ProgressStoryLoadCache.failedWeeks.insert(currentWeekStart)
            }
        }
        ProgressStoryLoadCache.inFlight[currentWeekStart] = task
        await task.value
        ProgressStoryLoadCache.inFlight[currentWeekStart] = nil

        story = ProgressStoryLoadCache.stories[currentWeekStart]
        if story == nil, ProgressStoryLoadCache.failedWeeks.contains(currentWeekStart) {
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
