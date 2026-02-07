import SwiftUI

/// Horizontal bar of emoji reactions for milestone posts in circle feed
struct CelebrationReactionsBar: View {
    @EnvironmentObject var container: DependencyContainer

    let celebrationId: UUID
    @State private var reactions: [CelebrationReactionSummary] = []
    @State private var isLoading = true
    @State private var isProcessingReaction = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CelebrationEmoji.allCases, id: \.rawValue) { emoji in
                ReactionButton(
                    emoji: emoji.rawValue,
                    count: reactionCount(for: emoji.rawValue),
                    isSelected: isUserReaction(emoji.rawValue),
                    onTap: { toggleReaction(emoji.rawValue) }
                )
            }

            Spacer()

            if !reactions.isEmpty {
                let totalCount = reactions.reduce(0) { $0 + $1.count }
                Text("\(totalCount) \(totalCount == 1 ? "reaction" : "reactions")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
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

        withAnimation(.spring(response: 0.3)) {
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
            HStack(spacing: 4) {
                Text(emoji)
                    .font(.system(size: 16))

                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(uiColor: .systemGray6))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("\(emoji) reaction, \(count) \(count == 1 ? "person" : "people")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Milestone Post Card

/// Card component for displaying milestone posts in circle feed
struct MilestonePostCard: View {
    let post: CirclePost
    let celebrationId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)

                Text(post.userDisplayName)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(post.createdAt.timeAgoShort)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Milestone content
            Text(post.bodyText ?? "achieved a milestone!")
                .font(.body)

            // Reactions bar (if celebration ID is available)
            if let celebrationId = celebrationId {
                CelebrationReactionsBar(celebrationId: celebrationId)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
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
    VStack(spacing: 20) {
        CelebrationReactionsBar(celebrationId: UUID())
            .environmentObject(DependencyContainer.preview)
            .padding()
            .background(Color(.systemBackground))

        CelebrationReactionsBar(celebrationId: UUID())
            .environmentObject(DependencyContainer.preview)
            .padding()
            .background(Color(.secondarySystemBackground))
    }
    .padding()
}

#Preview("Reaction Button") {
    HStack(spacing: 12) {
        ReactionButton(emoji: "🎉", count: 5, isSelected: true, onTap: {})
        ReactionButton(emoji: "👏", count: 3, isSelected: false, onTap: {})
        ReactionButton(emoji: "🔥", count: 0, isSelected: false, onTap: {})
    }
    .padding()
}
