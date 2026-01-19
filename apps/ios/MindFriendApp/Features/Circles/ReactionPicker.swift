import SwiftUI

/// Displays reaction counts and allows adding/removing reactions
struct ReactionDisplay: View {
    let postId: String
    @Binding var reactions: [ReactionSummary]

    @EnvironmentObject private var container: DependencyContainer
    @State private var showPicker = false
    @State private var isLoading = false

    var body: some View {
        HStack(spacing: 8) {
            // Existing reactions
            ForEach(reactions, id: \.emoji) { reaction in
                ReactionBubble(
                    reaction: reaction,
                    onTap: {
                        if reaction.userReacted {
                            removeReaction()
                        } else if let emoji = ReactionEmoji.allCases.first(where: { $0.rawValue == reaction.emoji }) {
                            addReaction(emoji)
                        }
                    }
                )
            }

            // Add reaction button
            Button {
                showPicker = true
            } label: {
                Image(systemName: "face.smiling")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
            .popover(isPresented: $showPicker) {
                ReactionPickerPopover { emoji in
                    showPicker = false
                    addReaction(emoji)
                }
            }
        }
        .opacity(isLoading ? 0.5 : 1.0)
        .disabled(isLoading)
    }

    private func addReaction(_ emoji: ReactionEmoji) {
        isLoading = true

        Task {
            do {
                try await container.supabaseDataService.addReaction(to: postId, emoji: emoji)

                await MainActor.run {
                    // Update local state optimistically
                    updateLocalReactions(addedEmoji: emoji.rawValue)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }

    private func removeReaction() {
        isLoading = true

        Task {
            do {
                try await container.supabaseDataService.removeReaction(from: postId)

                await MainActor.run {
                    // Update local state optimistically
                    updateLocalReactions(removedByUser: true)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }

    private func updateLocalReactions(addedEmoji: String? = nil, removedByUser: Bool = false) {
        var newReactions = reactions

        // Remove user's previous reaction if any
        for index in newReactions.indices {
            if newReactions[index].userReacted {
                if newReactions[index].count == 1 {
                    newReactions.remove(at: index)
                } else {
                    newReactions[index] = ReactionSummary(
                        emoji: newReactions[index].emoji,
                        count: newReactions[index].count - 1,
                        userReacted: false
                    )
                }
                break
            }
        }

        // Add new reaction if not just removing
        if let emoji = addedEmoji, !removedByUser {
            if let index = newReactions.firstIndex(where: { $0.emoji == emoji }) {
                newReactions[index] = ReactionSummary(
                    emoji: emoji,
                    count: newReactions[index].count + 1,
                    userReacted: true
                )
            } else {
                newReactions.append(ReactionSummary(
                    emoji: emoji,
                    count: 1,
                    userReacted: true
                ))
            }
        }

        reactions = newReactions.sorted { $0.count > $1.count }
    }
}

/// A single reaction bubble showing emoji and count
private struct ReactionBubble: View {
    let reaction: ReactionSummary
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(reaction.emoji)
                    .font(.callout)
                Text("\(reaction.count)")
                    .font(.caption)
                    .foregroundColor(reaction.userReacted ? .accentColor : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(reaction.userReacted ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Popover picker for selecting a reaction emoji
struct ReactionPickerPopover: View {
    let onSelect: (ReactionEmoji) -> Void

    var body: some View {
        HStack(spacing: 16) {
            ForEach(ReactionEmoji.allCases, id: \.self) { emoji in
                Button {
                    onSelect(emoji)
                } label: {
                    Text(emoji.rawValue)
                        .font(.title)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .presentationCompactAdaptation(.popover)
    }
}

/// Inline reaction picker for showing all options at once
struct InlineReactionPicker: View {
    let onSelect: (ReactionEmoji) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(ReactionEmoji.allCases, id: \.self) { emoji in
                Button {
                    onSelect(emoji)
                } label: {
                    Text(emoji.rawValue)
                        .font(.title2)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ReactionDisplay(
            postId: "test-post",
            reactions: .constant([
                ReactionSummary(emoji: "🎉", count: 3, userReacted: false),
                ReactionSummary(emoji: "👏", count: 2, userReacted: true),
                ReactionSummary(emoji: "🔥", count: 1, userReacted: false),
            ])
        )

        InlineReactionPicker { emoji in
            Log.social.debug("Selected: \(emoji.rawValue, privacy: .public)")
        }
    }
    .padding()
    .environmentObject(DependencyContainer())
}
