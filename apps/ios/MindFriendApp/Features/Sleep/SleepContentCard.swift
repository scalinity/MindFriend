import SwiftUI

/// Card component for displaying sleep content (stories, soundscapes, routines)
struct SleepContentCard: View {
    let content: SleepContent
    var isPremiumUser: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
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
                        .cornerRadius(SupportTheme.controlRadius)
                    } else {
                        thumbnailPlaceholder
                    }

                    // Duration badge (hidden for soundscapes)
                    if content.contentType != .soundscape {
                        HStack(spacing: SupportTheme.Spacing.xxs) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(content.formattedDuration)
                                .font(.caption2)
                        }
                        .padding(.horizontal, SupportTheme.Spacing.xs)
                        .padding(.vertical, SupportTheme.Spacing.xxs)
                        .background(SupportTheme.elevated)
                        .cornerRadius(SupportTheme.controlRadius)
                        .padding(SupportTheme.Spacing.xs)
                    }

                    // Premium badge - only show if content is premium AND user is not premium
                    if content.isPremium && !isPremiumUser {
                        HStack {
                            Spacer()
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.accent)
                                .padding(SupportTheme.Spacing.xxs)
                                .background(SupportTheme.elevated)
                                .cornerRadius(SupportTheme.controlRadius)
                                .padding(SupportTheme.Spacing.xs)
                        }
                    }
                }

                // Content info
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(content.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(SupportTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        Image(systemName: content.contentType.icon)
                            .font(.caption2)
                            .foregroundStyle(SupportTheme.textPrimary.opacity(0.7))
                        Text(content.category.displayName)
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textPrimary.opacity(0.7))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            SupportTheme.surface

            Image(systemName: content.contentType.icon)
                .font(.title)
                .foregroundStyle(SupportTheme.textPrimary.opacity(0.8))
        }
        .frame(height: 100)
        .cornerRadius(SupportTheme.controlRadius)
    }

    private func gradientColors(for type: SleepContentType) -> [Color] {
        switch type {
        case .story:
            return [SupportTheme.accent.opacity(0.8), SupportTheme.accent.opacity(0.6)]
        case .soundscape:
            return [SupportTheme.accent.opacity(0.8), SupportTheme.accent.opacity(0.6)]
        case .routine:
            return [SupportTheme.accent.opacity(0.8), SupportTheme.accent.opacity(0.6)]
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
            HStack(spacing: SupportTheme.Spacing.s) {
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
                .cornerRadius(SupportTheme.controlRadius)

                // Info
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(content.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(SupportTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: SupportTheme.Spacing.xs) {
                        Label(content.formattedDuration, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textPrimary.opacity(0.7))

                        // Premium badge - only show if content is premium AND user is not premium
                        if content.isPremium && !isPremiumUser {
                            Label("Premium", systemImage: "crown.fill")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.accent)
                        }
                    }
                }

                Spacer()

                // Play indicator
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(SupportTheme.accent)
            }
            .padding(.vertical, SupportTheme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            SupportTheme.surface
            Image(systemName: content.contentType.icon)
                .foregroundStyle(SupportTheme.textPrimary.opacity(0.8))
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
    .padding(SupportTheme.Spacing.m)
}
