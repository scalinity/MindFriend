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
            VStack(spacing: 24) {
                // Card preview
                ShareCardPreview(celebration: celebration)
                    .padding(.horizontal, 40)
                    .padding(.top, 20)

                Spacer()

                // Share options
                VStack(spacing: 16) {
                    if let image = generatedImage {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview(celebration.shareMessage, image: Image(uiImage: image))
                        ) {
                            HStack(spacing: 8) {
                                Image(systemName: "photo.fill")
                                Text("Share Image")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(14)
                        }
                        .simultaneousGesture(TapGesture().onEnded { onShare() })
                    } else if isGenerating {
                        ProgressView("Generating card...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }

                    ShareLink(item: celebration.shareMessage) {
                        HStack(spacing: 8) {
                            Image(systemName: "text.bubble.fill")
                            Text("Share Text Only")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tint)
                    }
                    .simultaneousGesture(TapGesture().onEnded { onShare() })
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
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

        let renderer = ImageRenderer(content: ShareCardPreview(celebration: celebration))
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
        VStack(spacing: 20) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: celebration.celebrationType.confettiColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: celebration.celebrationType.confettiColors.first?.opacity(0.4) ?? .clear, radius: 15)

                Image(systemName: celebration.displayIconName)
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }

            // Title
            Text(celebration.title)
                .font(.title.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            // Share message
            Text(celebration.shareMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Spacer()

            // Branding
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text("MindFriend")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)
        }
        .padding(24)
        .frame(width: 320, height: 420)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        )
    }
}

// MARK: - Preview

#Preview("Share Sheet") {
    ShareCardSheet(
        celebration: CelebrationEvent(
            id: UUID(),
            userId: UUID(),
            celebrationType: .streakMilestone,
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
    .padding()
    .background(Color.gray.opacity(0.2))
}
