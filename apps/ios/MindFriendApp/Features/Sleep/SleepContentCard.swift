import SwiftUI

/// Card component for displaying sleep content (stories, soundscapes, routines)
struct SleepContentCard: View {
    let content: SleepContent
    var isPremiumUser: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Thumbnail with overlay
                ZStack(alignment: .bottomLeading) {
                    // Thumbnail or gradient placeholder
                    // Soundscapes always use gradient placeholder for consistency
                    if content.contentType != .soundscape, let thumbnailUrl = content.thumbnailURL {
                        AsyncImage(url: thumbnailUrl) { phase in
                            switch phase {
                            case .empty:
                                thumbnailPlaceholder
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .failure:
                                thumbnailPlaceholder
                            @unknown default:
                                thumbnailPlaceholder
                            }
                        }
                        .frame(height: 100)
                        .clipped()
                        .cornerRadius(12)
                    } else {
                        thumbnailPlaceholder
                    }

                    // Duration badge (hidden for soundscapes)
                    if content.contentType != .soundscape {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(content.formattedDuration)
                                .font(.caption2)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(8)
                    }

                    // Premium badge - only show if content is premium AND user is not premium
                    if content.isPremium && !isPremiumUser {
                        HStack {
                            Spacer()
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .cornerRadius(6)
                                .padding(8)
                        }
                    }
                }

                // Content info
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(height: 40, alignment: .top)

                    HStack(spacing: 4) {
                        Image(systemName: content.contentType.icon)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(content.category.displayName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors(for: content.contentType),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: content.contentType.icon)
                .font(.title)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(height: 100)
        .cornerRadius(12)
    }

    private func gradientColors(for type: SleepContentType) -> [Color] {
        switch type {
        case .story:
            return [Color.indigo.opacity(0.8), Color.purple.opacity(0.6)]
        case .soundscape:
            return [Color.teal.opacity(0.8), Color.cyan.opacity(0.6)]
        case .routine:
            return [Color.blue.opacity(0.8), Color.indigo.opacity(0.6)]
        }
    }
}

/// Horizontal list item for sleep content
struct SleepContentListItem: View {
    let content: SleepContent
    var isPremiumUser: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Thumbnail
                ZStack {
                    if let thumbnailUrl = content.thumbnailURL {
                        AsyncImage(url: thumbnailUrl) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            default:
                                thumbnailPlaceholder
                            }
                        }
                    } else {
                        thumbnailPlaceholder
                    }
                }
                .frame(width: 60, height: 60)
                .cornerRadius(8)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Label(content.formattedDuration, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))

                        // Premium badge - only show if content is premium AND user is not premium
                        if content.isPremium && !isPremiumUser {
                            Label("Premium", systemImage: "crown.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }
                }

                Spacer()

                // Play indicator
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.indigo)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo.opacity(0.6), Color.purple.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: content.contentType.icon)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - Preview

#Preview("Sleep Content Card") {
    SleepContentCard(
        content: SleepContent(
            id: "1",
            title: "Rainy Night in the Forest",
            description: "A gentle walk through a misty forest",
            contentType: .story,
            category: .nature,
            durationSeconds: 1800,
            narrator: "Sarah",
            isPremium: false,
            isKids: false,
            audioUrl: "https://example.com/audio.m4a",
            thumbnailUrl: nil,
            isLoopable: false,
            isFeatured: true,
            sortOrder: 1,
            createdAt: Date()
        ),
        onTap: {}
    )
    .frame(width: 160)
    .padding()
}
