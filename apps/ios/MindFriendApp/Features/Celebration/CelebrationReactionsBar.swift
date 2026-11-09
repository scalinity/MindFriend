import SwiftUI

/// Horizontal bar of emoji reactions for milestone posts in circle feed
struct CelebrationReactionsBar: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let celebrationId: UUID
    @State private var reactions: [CelebrationReactionSummary] = []
    @State private var isLoading = true
    @State private var isProcessingReaction = false

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            ScrollView(.horizontal) {
            HStack(spacing: SupportTheme.Spacing.xs) {
            ForEach(CelebrationEmoji.allCases, id: \.rawValue) { emoji in
                ReactionButton(
                    emoji: emoji.rawValue,
                    count: reactionCount(for: emoji.rawValue),
                    isSelected: isUserReaction(emoji.rawValue),
                    onTap: { toggleReaction(emoji.rawValue) }
                )
            }

            }
            }
            .scrollIndicators(.hidden)

            if !reactions.isEmpty {
                let totalCount = reactions.reduce(0) { $0 + $1.count }
                Text("\(totalCount) \(totalCount == 1 ? "reaction" : "reactions")")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .padding(.horizontal, SupportTheme.Spacing.xxs)
        .task {
            await loadReactions()
        }
    }

    private func reactionCount(for emoji: String) -> Int {
        reactions.first { $0.emoji == emoji }?.count ?? 0
    }

    private func isUserReaction(_ emoji: String) -> Bool {
        reactions.first { $0.emoji == emoji }?.userReacted ?? false
    }

    private func loadReactions() async {
        isLoading = true
        defer { isLoading = false }

        do {
            reactions = try await container.supabaseDataService.getCelebrationReactions(celebrationId: celebrationId)
        } catch {
            Log.data.error("[Reactions] Failed to load: \(error)")
        }
    }

    private func toggleReaction(_ emoji: String) {
        // Prevent rapid-fire taps causing race conditions
        guard !isProcessingReaction else { return }
        isProcessingReaction = true

        // Optimistic update
        let wasSelected = isUserReaction(emoji)

        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3)) {
            if wasSelected {
                // Remove reaction
                if let index = reactions.firstIndex(where: { $0.emoji == emoji }) {
                    let current = reactions[index]
                    if current.count <= 1 {
                        reactions.remove(at: index)
                    } else {
                        reactions[index] = CelebrationReactionSummary(
                            emoji: emoji,
                            count: current.count - 1,
                            userReacted: false
                        )
                    }
                }
            } else {
                // Remove any previous user reaction (use firstIndex to avoid mutation during iteration)
                if let existingIndex = reactions.firstIndex(where: { $0.userReacted }) {
                    let existing = reactions[existingIndex]
                    if existing.count <= 1 {
                        reactions.remove(at: existingIndex)
                    } else {
                        reactions[existingIndex] = CelebrationReactionSummary(
                            emoji: existing.emoji,
                            count: existing.count - 1,
                            userReacted: false
                        )
                    }
                }

                // Add new reaction
                if let index = reactions.firstIndex(where: { $0.emoji == emoji }) {
                    reactions[index] = CelebrationReactionSummary(
                        emoji: emoji,
                        count: reactions[index].count + 1,
                        userReacted: true
                    )
                } else {
                    reactions.append(CelebrationReactionSummary(
                        emoji: emoji,
                        count: 1,
                        userReacted: true
                    ))
                }
            }
        }

        // Server update
        Task {
            defer {
                Task { @MainActor in
                    isProcessingReaction = false
                }
            }

            do {
                if wasSelected {
                    try await container.supabaseDataService.removeCelebrationReaction(celebrationId: celebrationId)
                } else {
                    try await container.supabaseDataService.addCelebrationReaction(celebrationId: celebrationId, emoji: emoji)
                }
            } catch {
                Log.data.error("[Reactions] Failed to update: \(error)")
                // Reload to sync state
                await loadReactions()
            }
        }
    }
}

// MARK: - Reaction Button

struct ReactionButton: View {
    let emoji: String
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: SupportTheme.Spacing.xxs) {
                Text(emoji)
                    .font(.system(size: 16))

                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(isSelected ? SupportTheme.accent : SupportTheme.textSecondary)
                }
            }
            .padding(.horizontal, SupportTheme.Spacing.xs)
            .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
            .background(
                Capsule()
                    .fill(isSelected ? SupportTheme.elevated : SupportTheme.surface)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? SupportTheme.accent : SupportTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("\(emoji) reaction, \(count) \(count == 1 ? "person" : "people")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct ScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Milestone Post Card

/// Card component for displaying milestone posts in circle feed
struct MilestonePostCard: View {
    let post: CirclePost
    let celebrationId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            // Header
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(SupportTheme.Celebration.gold)

                Text(post.userDisplayName)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(post.createdAt.timeAgoShort)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            // Milestone content
            Text(post.bodyText ?? "achieved a milestone!")
                .font(.body)

            // Reactions bar (if celebration ID is available)
            if let celebrationId = celebrationId {
                CelebrationReactionsBar(celebrationId: celebrationId)
                    .padding(.top, SupportTheme.Spacing.xxs)
            }
        }
        .padding(SupportTheme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                .fill(SupportTheme.surface)
        )
    }
}

// MARK: - Date Extension for Time Ago

extension Date {
    var timeAgoShort: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview("Reactions Bar") {
    VStack(spacing: SupportTheme.Spacing.l) {
        CelebrationReactionsBar(celebrationId: UUID())
            .environmentObject(DependencyContainer.preview)
            .padding(SupportTheme.Spacing.m)
            .background(SupportTheme.canvas)

        CelebrationReactionsBar(celebrationId: UUID())
            .environmentObject(DependencyContainer.preview)
            .padding(SupportTheme.Spacing.m)
            .background(SupportTheme.surface)
    }
    .padding(SupportTheme.Spacing.m)
}

#Preview("Reaction Button") {
    HStack(spacing: SupportTheme.Spacing.s) {
        ReactionButton(emoji: "🎉", count: 5, isSelected: true, onTap: {})
        ReactionButton(emoji: "👏", count: 3, isSelected: false, onTap: {})
        ReactionButton(emoji: "🔥", count: 0, isSelected: false, onTap: {})
    }
    .padding(SupportTheme.Spacing.m)
}
