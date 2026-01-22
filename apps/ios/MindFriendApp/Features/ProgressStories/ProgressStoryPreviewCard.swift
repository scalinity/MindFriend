import SwiftUI

/// Preview card for Progress Stories shown on the Home screen
/// Tapping opens the full-screen story viewer
struct ProgressStoryPreviewCard: View {
    @EnvironmentObject private var container: DependencyContainer

    @State private var story: WeeklyStory?
    @State private var isLoading = false
    @State private var showViewer = false

    var body: some View {
        Button {
            showViewer = true
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
        .task {
            await loadStory()
        }
        .fullScreenCover(isPresented: $showViewer) {
            ProgressStoryViewer(weekStart: nil)
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
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("Your weekly story will appear here")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Load Story

    private func loadStory() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let weekStart = Date()
            // Note: getWeeklyStory is a stub returning [String: Any]? 
            // When implemented, this will need proper type decoding
            _ = try await container.supabaseDataService.getWeeklyStory(weekStart: weekStart)
            // For now, story remains nil since the stub returns nil
        } catch {
            // Silently fail - card will show "no story" state
        }
    }
}

// MARK: - Preview

#Preview {
    ProgressStoryPreviewCard()
        .environmentObject(DependencyContainer.preview)
        .padding()
}
