import SwiftUI

/// Modal sheet for sharing a story card to a circle
struct CircleShareSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: DependencyContainer

    /// The story view model
    let viewModel: ProgressStoryViewModel

    /// Index of the card being shared
    let cardIndex: Int

    @State private var selectedCircle: FriendCircle?
    @State private var caption: String = ""
    @State private var circles: [FriendCircle] = []
    @State private var isLoading = false
    @State private var isPosting = false
    @State private var circleLoadError: String?

    private let maxCaptionLength = 500

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Image preview
                imagePreview
                    .padding(.top, SupportTheme.Spacing.m)

                // Circle picker
                circlePicker
                    .padding(.top, SupportTheme.Spacing.l)

                // Caption field
                captionField
                    .padding(.top, SupportTheme.Spacing.m)

                // Privacy notice
                privacyNotice
                    .padding(.top, SupportTheme.Spacing.s)

                Spacer()
            }
            .padding(.horizontal, SupportTheme.Spacing.m)
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("Share to Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task { await postToCircle() }
                    }
                    .disabled(selectedCircle == nil || isPosting)
                }
            }
        }
        .task {
            await loadCircles()
        }
        .overlay {
            if isPosting {
                postingOverlay
            }
        }
    }

    // MARK: - Image Preview

    @ViewBuilder
    private var imagePreview: some View {
        if let image = viewModel.exportedImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(9 / 16, contentMode: .fit)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                .shadow(color: SupportTheme.canvas.opacity(0.2), radius: 8, x: 0, y: 4)
        } else {
            RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                .fill(SupportTheme.textSecondary.opacity(0.2))
                .frame(height: 200)
                .overlay {
                    ProgressView()
                }
        }
    }

    // MARK: - Circle Picker

    @ViewBuilder
    private var circlePicker: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text("Select Circle")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(height: 60)
            } else if let error = circleLoadError {
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)

                    Button("Retry") {
                        Task { await loadCircles() }
                    }
                    .font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, SupportTheme.Spacing.m)
            } else if circles.isEmpty {
                Text("You're not in any circles yet.")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, SupportTheme.Spacing.m)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SupportTheme.Spacing.s) {
                        ForEach(circles, id: \.id) { circle in
                            circleButton(circle)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func circleButton(_ circle: FriendCircle) -> some View {
        let isSelected = selectedCircle?.id == circle.id

        Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : (.spring(response: 0.3))) {
                selectedCircle = circle
            }
        } label: {
            VStack(spacing: SupportTheme.Spacing.xxs) {
                Image(systemName: "person.3.fill")
                    .font(.title2)

                Text(circle.name)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 80, height: 70)
            .background(
                RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                    .fill(isSelected ? SupportTheme.accent : SupportTheme.textSecondary.opacity(0.1))
            )
            .foregroundStyle(isSelected ? SupportTheme.onAccent : SupportTheme.textPrimary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Caption Field

    @ViewBuilder
    private var captionField: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            HStack {
                Text("Caption")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Text("\(caption.count)/\(maxCaptionLength)")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            TextField("Add a caption (optional)", text: $caption, axis: .vertical)
                .supportField()
                .lineLimit(3...5)
                .onChange(of: caption) { _, newValue in
                    if newValue.count > maxCaptionLength {
                        caption = String(newValue.prefix(maxCaptionLength))
                    }
                }
        }
    }

    // MARK: - Privacy Notice

    @ViewBuilder
    private var privacyNotice: some View {
        HStack(alignment: .top, spacing: SupportTheme.Spacing.xs) {
            Image(systemName: "eye")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)

            Text("This story card will be visible to all members of the selected circle.")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .padding(SupportTheme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                .fill(SupportTheme.textSecondary.opacity(0.1))
        )
    }

    // MARK: - Posting Overlay

    @ViewBuilder
    private var postingOverlay: some View {
        ZStack {
            SupportTheme.canvas.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: SupportTheme.Spacing.s) {
                ProgressView()
                    .scaleEffect(1.2)

                Text("Posting to \(selectedCircle?.name ?? "circle")...")
                    .font(.subheadline)
            }
            .padding(SupportTheme.Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                    .fill(SupportTheme.surface)
            )
        }
    }

    // MARK: - Actions

    private func loadCircles() async {
        isLoading = true
        circleLoadError = nil
        defer { isLoading = false }

        do {
            circles = try await container.supabaseDataService.getCircles()

            // Auto-select first circle if only one exists
            if circles.count == 1 {
                selectedCircle = circles.first
            }
        } catch {
            circleLoadError = "Unable to load circles. Check your connection and try again."
        }
    }

    private func postToCircle() async {
        guard let circle = selectedCircle,
            let circleUUID = UUID(uuidString: circle.id)
        else { return }

        isPosting = true
        defer { isPosting = false }

        await viewModel.shareToCircle(
            index: cardIndex,
            circleId: circleUUID,
            caption: caption.isEmpty ? nil : caption
        )
    }
}

// MARK: - Preview

#Preview {
    CircleShareSheet(
        viewModel: ProgressStoryViewModel(
            dataService: DependencyContainer.preview.supabaseDataService
        ),
        cardIndex: 0
    )
    .environmentObject(DependencyContainer.preview)
}
