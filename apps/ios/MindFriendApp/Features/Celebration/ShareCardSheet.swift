import SwiftUI

/// Sheet for generating and sharing celebration cards externally
struct ShareCardSheet: View {
    @Environment(\.dismiss) private var dismiss

    let celebration: CelebrationEvent
    let onShare: () -> Void

    @State private var generatedImage: UIImage?
    @State private var isGenerating = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Card preview
                    ShareCardPreview(celebration: celebration)
                        .padding(.horizontal, SupportTheme.Spacing.m)
                        .padding(.top, SupportTheme.Spacing.l)

                    Spacer()

                    // Share options
                    VStack(spacing: SupportTheme.Spacing.m) {
                        if let image = generatedImage {
                            ShareLink(
                                item: Image(uiImage: image),
                                preview: SharePreview(celebration.supportShareMessage, image: Image(uiImage: image))
                            ) {
                                HStack(spacing: SupportTheme.Spacing.xs) {
                                    Image(systemName: "photo.fill")
                                    Text("Share Image")
                                }
                            }
                            .buttonStyle(.supportPrimary)
                            .simultaneousGesture(TapGesture().onEnded { onShare() })
                        } else if isGenerating {
                            ProgressView("Generating card...")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, SupportTheme.Spacing.m)
                        }

                        ShareLink(item: celebration.supportShareMessage) {
                            HStack(spacing: SupportTheme.Spacing.xs) {
                                Image(systemName: "text.bubble.fill")
                                Text("Share Text Only")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SupportTheme.accent)
                        }
                        .buttonStyle(.supportSecondary)
                        .simultaneousGesture(TapGesture().onEnded { onShare() })
                    }
                    .padding(.horizontal, SupportTheme.Spacing.l)
                    .padding(.bottom, SupportTheme.Spacing.xl)
                }
            }
            .supportSheet()
            .navigationTitle("Share Achievement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await generateImage()
            }
        }
    }

    @MainActor
    private func generateImage() async {
        // Small delay for view to render
        try? await Task.sleep(nanoseconds: 100_000_000)

        let renderer = ImageRenderer(content: ShareCardPreview(celebration: celebration).frame(width: 320))
        renderer.scale = 3.0
        generatedImage = renderer.uiImage
        isGenerating = false
    }
}

// MARK: - Share Card Preview

/// The visual card that gets shared externally
struct ShareCardPreview: View {
    let celebration: CelebrationEvent

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Spacer()

            CelebrationEmblem(.symbol(celebration.supportIcon), tint: SupportTheme.Celebration.gold, diameter: 80, animated: false)

            // Title
            Text(celebration.supportTitle)
                .font(.title.bold())
                .foregroundStyle(SupportTheme.textPrimary)
                .multilineTextAlignment(.center)

            // Share message
            Text(celebration.supportShareMessage)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SupportTheme.Spacing.m)

            Spacer()

            // Branding
            HStack(spacing: SupportTheme.Spacing.xs) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.accent)
                Text("MindFriend")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            .padding(.bottom, SupportTheme.Spacing.s)
        }
        .padding(SupportTheme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }
}

// MARK: - Preview

#Preview("Share Sheet") {
    ShareCardSheet(
        celebration: CelebrationEvent(
            id: UUID(),
            userId: UUID(),
            celebrationType: .levelUp,
            value: 30,
            badgeId: nil,
            shownAt: nil,
            sharedToCircle: false,
            sharedExternally: false,
            circlePostId: nil,
            createdAt: Date()
        ),
        onShare: {}
    )
}

#Preview("Card Only") {
    ShareCardPreview(
        celebration: CelebrationEvent(
            id: UUID(),
            userId: UUID(),
            celebrationType: .levelUp,
            value: 10,
            badgeId: nil,
            shownAt: nil,
            sharedToCircle: false,
            sharedExternally: false,
            circlePostId: nil,
            createdAt: Date()
        )
    )
    .padding(SupportTheme.Spacing.m)
    .background(SupportTheme.textSecondary.opacity(0.2))
}
