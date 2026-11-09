import SwiftUI

struct ArtGeneratorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sharing = CreativeWorkSharing()

    @State private var prompt = ""
    @State private var selectedStyle: ArtStyle = .none
    @State private var moodScore: Int = 5
    @State private var selectedMoodTags: Set<String> = []
    @State private var isGenerating = false
    @State private var generatedWork: CreativeWork?
    @State private var generatedImageURL: URL?
    @State private var partialImage: UIImage?  // For streaming progressive updates
    @State private var quotaRemaining: Int?
    @State private var error: String?
    @State private var generationTask: Task<Void, Never>?

    private let moodTags = ["happy", "sad", "calm", "anxious", "hopeful", "grateful", "peaceful", "energetic"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    if let imageURL = generatedImageURL {
                        generatedImageView(url: imageURL)
                    } else {
                        promptInputSection
                    }
                }
                .padding(SupportTheme.Spacing.m)
            }
            .scrollDismissesKeyboard(.interactively)
            .supportScreen()
            .navigationTitle("Create AI Art")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                if generatedImageURL != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if error != nil {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        if let error = error {
                            Text(error)
                        }

                        Button("OK") { error = nil }
                    }
                    .foregroundStyle(SupportTheme.textSecondary)
                    .buttonStyle(.supportSecondary)
                    .supportCard()
                    .padding(SupportTheme.Spacing.m)
                }
            }
            .modifier(CreativeWorkSharePresentation(sharing: sharing))
            .task(id: scenePhase) {
                guard scenePhase == .active, let work = generatedWork else { return }
                do {
                    let refreshed = try await container.creativeExpressionService.refreshMedia([work])
                    try Task.checkCancellation()
                    guard generatedWork?.id == work.id else { return }
                    generatedWork?.mediaUrl = refreshed.first?.mediaUrl
                    generatedImageURL = refreshed.first?.mediaUrl
                } catch {
                    if !Task.isCancelled { self.error = "Unable to refresh this image. Please try again." }
                }
            }
            .onDisappear {
                generationTask?.cancel()
                generationTask = nil
            }
        }
    }

    // MARK: - Prompt Input Section

    private var promptInputSection: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            // Prompt Input
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                Text("Describe your feeling or mood")
                    .font(.headline)

                Text("The AI will create unique artwork representing your emotions")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)

                TextField("e.g., A peaceful moment of clarity after a storm...", text: $prompt, axis: .vertical)
                    .supportField()
                    .lineLimit(3...6)
            }

            // Style Selection
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                Text("Art Style")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: SupportTheme.Spacing.s) {
                    ForEach(ArtStyle.allCases, id: \.self) { style in
                        StyleOptionButton(
                            style: style,
                            isSelected: selectedStyle == style
                        ) {
                            selectedStyle = style
                        }
                    }
                }
            }

            // Mood Score Slider
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                HStack {
                    Text("Current Mood")
                        .font(.headline)
                    Spacer()
                    Text("\(moodScore)/10")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                Slider(
                    value: Binding(
                        get: { Double(moodScore) },
                        set: { moodScore = Int($0) }
                    ),
                    in: 1...10,
                    step: 1
                )
                .tint(moodColor)
                .accessibilityLabel("Current mood level")
                .accessibilityValue("\(moodScore) out of 10, \(moodAccessibilityDescription)")
                .accessibilityHint("Adjust to set how you're feeling right now")

                HStack {
                    Text("Low")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                    Spacer()
                    Text("High")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            // Mood Tags
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                Text("Mood Tags (optional)")
                    .font(.headline)

                ArtFlowLayout(spacing: SupportTheme.Spacing.xs) {
                    ForEach(moodTags, id: \.self) { tag in
                        MoodTagButton(
                            tag: tag,
                            isSelected: selectedMoodTags.contains(tag)
                        ) {
                            if selectedMoodTags.contains(tag) {
                                selectedMoodTags.remove(tag)
                            } else {
                                selectedMoodTags.insert(tag)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: SupportTheme.Spacing.xl)

            // Streaming partial image preview during generation
            if isGenerating {
                VStack(spacing: SupportTheme.Spacing.s) {
                    if let partialImage {
                        ZStack {
                            Image(uiImage: partialImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 300)
                                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                                .opacity(0.8)
                                .blur(radius: 1)

                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(SupportTheme.accent)
                        }
                        .accessibilityLabel("Generating art")
                        .accessibilityValue("Preview showing, refining details")
                    } else {
                        ProgressView()
                            .scaleEffect(1.2)
                    }
                    Text(partialImage != nil ? "Refining your artwork..." : "Creating your artwork...")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .padding(SupportTheme.Spacing.m)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Generating")
                .accessibilityValue("Please wait while your artwork is being created")
            }

            // Generate Button
            Button {
                generateArt()
            } label: {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .tint(SupportTheme.accent)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(isGenerating ? "Creating..." : "Generate Art")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(SupportTheme.Spacing.m)
                .background(prompt.isEmpty || isGenerating ? SupportTheme.textSecondary : SupportTheme.accent)
                .foregroundStyle(SupportTheme.textPrimary)
                .cornerRadius(SupportTheme.controlRadius)
            }
            .disabled(prompt.isEmpty || isGenerating)

            if let quota = quotaRemaining {
                Text("\(quota) generations remaining today")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
    }

    // MARK: - Generated Image View

    private func generatedImageView(url: URL) -> some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                        .shadow(radius: 8)
                case .failure:
                    failedImageView
                case .empty:
                    ProgressView()
                        .frame(height: 300)
                @unknown default:
                    failedImageView
                }
            }
            .frame(maxHeight: 400)

            // Prompt display - keep quote marks together with text
            Text("\"\(prompt)\"")
                .font(.subheadline)
                .italic()
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, SupportTheme.Spacing.m)

            HStack(spacing: SupportTheme.Spacing.xxs) {
                Image(systemName: selectedStyle.icon)
                Text(selectedStyle.displayName)
            }
            .font(.caption)
            .foregroundStyle(SupportTheme.textSecondary)

            // Action Buttons - prevent text wrapping
            HStack(spacing: SupportTheme.Spacing.s) {
                Button {
                    generatedImageURL = nil
                    generatedWork = nil
                    partialImage = nil
                    prompt = ""
                } label: {
                    Label("New", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.supportSecondary)

                if let work = generatedWork {
                    Button {
                        sharing.share(work, using: container.creativeExpressionService)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.supportSecondary)
                }

                if let work = generatedWork {
                    Button {
                        Task { await toggleFavorite(work: work) }
                    } label: {
                        Label(
                            work.isFavorite ? "Saved" : "Save",
                            systemImage: work.isFavorite ? "heart.fill" : "heart"
                        )
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.supportSecondary)
                    .tint(work.isFavorite ? .red : nil)
                }
            }

            if let quota = quotaRemaining {
                Text("\(quota) generations remaining today")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
    }

    private var failedImageView: some View {
        Rectangle()
            .fill(SupportTheme.surface)
            .frame(height: 300)
            .overlay {
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("Failed to load image")
                        .font(.caption)
                }
                .foregroundStyle(SupportTheme.textSecondary)
            }
            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }

    private var moodColor: Color {
        switch moodScore {
        case 1...3: return .red
        case 4...6: return SupportTheme.accent
        case 7...10: return SupportTheme.accent
        default: return SupportTheme.accent
        }
    }

    private var moodAccessibilityDescription: String {
        switch moodScore {
        case 1...2: return "very low mood"
        case 3...4: return "low mood"
        case 5...6: return "neutral mood"
        case 7...8: return "good mood"
        case 9...10: return "great mood"
        default: return "mood level"
        }
    }

    // MARK: - Actions

    private func generateArt() {
        // Cancel any existing task
        generationTask?.cancel()

        isGenerating = true
        error = nil
        partialImage = nil

        generationTask = Task {
            do {
                // Try streaming API first for progressive image updates
                let work: CreativeWork
                do {
                    work = try await container.creativeExpressionService.generateArtStreaming(
                        prompt: prompt,
                        style: selectedStyle,
                        moodScore: moodScore,
                        moodTags: Array(selectedMoodTags),
                        onPartialImage: { imageData, _ in
                            Task { @MainActor in
                                guard !Task.isCancelled else { return }
                                if let image = UIImage(data: imageData) {
                                    self.partialImage = image
                                }
                            }
                        }
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    throw error
                }

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    generatedWork = work
                    partialImage = nil

                    generatedImageURL = work.mediaUrl

                    isGenerating = false
                }

                // Update quota display
                if let quota = try? await container.creativeExpressionService.fetchQuota() {
                    await MainActor.run {
                        quotaRemaining = quota.aiArtLimit - quota.aiArtCount
                    }
                }
            } catch CreativeError.quotaExceeded {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    // Show paywall directly without error message
                    appState.showPaywall = true
                    partialImage = nil
                    isGenerating = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    // Check if error message indicates quota exceeded (fallback)
                    let errorString = error.localizedDescription.lowercased()
                    if errorString.contains("429") || errorString.contains("quota") || errorString.contains("limit") {
                        appState.showPaywall = true
                    } else {
                        self.error = error.localizedDescription
                    }
                    partialImage = nil
                    isGenerating = false
                }
            }
        }
    }

    private func toggleFavorite(work: CreativeWork) async {
        do {
            let newStatus = try await container.creativeExpressionService.toggleFavorite(workId: work.id)
            generatedWork?.isFavorite = newStatus
        } catch {
            Log.creative.error("Toggle favorite error", error: error)
        }
    }
}

// MARK: - Style Option Button

struct StyleOptionButton: View {
    let style: ArtStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: SupportTheme.Spacing.xxs) {
                Image(systemName: style.icon)
                    .font(.title2)
                    .frame(height: 30)

                Text(style.displayName)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SupportTheme.Spacing.s)
            .background(isSelected ? SupportTheme.accent.opacity(0.2) : SupportTheme.surface)
            .cornerRadius(SupportTheme.controlRadius)
            .overlay {
                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                    .stroke(isSelected ? SupportTheme.accent : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.displayName) style")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Mood Tag Button

struct MoodTagButton: View {
    let tag: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tag.capitalized)
                .font(.caption)
                .padding(.horizontal, SupportTheme.Spacing.s)
                .padding(.vertical, SupportTheme.Spacing.xxs)
                .background(isSelected ? SupportTheme.accent : SupportTheme.surface)
                .foregroundStyle(isSelected ? SupportTheme.onAccent : SupportTheme.textPrimary)
                .cornerRadius(SupportTheme.cardRadius)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tag)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Flow Layout

private struct ArtFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = ArtFlowLayoutResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = ArtFlowLayoutResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + result.positions[index].x,
                    y: bounds.minY + result.positions[index].y
                ),
                proposal: .unspecified
            )
        }
    }

    struct ArtFlowLayoutResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += maxHeight + spacing
                    maxHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                maxHeight = max(maxHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + maxHeight)
        }
    }
}

#Preview {
    ArtGeneratorView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
