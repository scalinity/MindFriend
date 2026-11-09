import SwiftUI
import AVFoundation

struct CreativeGalleryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sharing = CreativeWorkSharing()

    @State private var works: [CreativeWork] = []
    @State private var selectedFilter: CreativeWorkType?
    @State private var isLoading = true
    @State private var showingDeleteAlert = false
    @State private var workToDelete: CreativeWork?
    @State private var isRefreshingMedia = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: SupportTheme.Spacing.s)]

    var filteredWorks: [CreativeWork] {
        guard let filter = selectedFilter else { return works }
        return works.filter { $0.workType == filter }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Filter Pills
                filterSection

                // Grid
                if isLoading {
                    ProgressView()
                        .padding(.top, SupportTheme.Spacing.xl)
                } else if filteredWorks.isEmpty {
                    emptyStateView
                } else {
                    galleryGrid
                }
            }
        }
        .supportScreen()
        .navigationTitle("Gallery")
        .modifier(CreativeWorkSharePresentation(sharing: sharing))
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            if works.isEmpty { await loadWorks() } else { await refreshDisplayMedia() }
        }
        .refreshable {
            await loadWorks()
        }
        .alert("Delete Creation?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                workToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let work = workToDelete {
                    Task { await deleteWork(work) }
                }
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SupportTheme.Spacing.xs) {
                FilterPill(
                    title: "All",
                    count: works.count,
                    isSelected: selectedFilter == nil
                ) {
                    selectedFilter = nil
                }

                ForEach(CreativeWorkType.allCases, id: \.self) { type in
                    let count = works.filter { $0.workType == type }.count
                    if count > 0 {
                        FilterPill(
                            title: type.displayName,
                            icon: type.icon,
                            count: count,
                            isSelected: selectedFilter == type
                        ) {
                            selectedFilter = type
                        }
                    }
                }
            }
            .padding(.horizontal, SupportTheme.Spacing.m)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Creations Yet", systemImage: "paintbrush")
        } description: {
            Text("Start expressing yourself through art, voice, or drawing!")
        } actions: {
            NavigationLink("Create Something") {
                CreativeHubView()
            }
            .buttonStyle(.supportSecondary)
        }
        .padding(.top, SupportTheme.Spacing.xl)
    }

    // MARK: - Gallery Grid

    private var galleryGrid: some View {
        LazyVGrid(columns: columns, spacing: SupportTheme.Spacing.s) {
            ForEach(filteredWorks) { work in
                NavigationLink {
                    CreativeWorkDetailView(work: work)
                } label: {
                    GalleryThumbnailView(work: work)
                        .task { await refreshDisplayMedia() }
                        .contextMenu {
                            Button {
                                Task { await toggleFavorite(work) }
                            } label: {
                                Label(
                                    work.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                                    systemImage: work.isFavorite ? "heart.slash" : "heart"
                                )
                            }

                            if work.storagePath != nil {
                                Button {
                                    sharing.share(work, using: container.creativeExpressionService)
                                } label: {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                            }

                            Button(role: .destructive) {
                                workToDelete = work
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SupportTheme.Spacing.m)
    }

    // MARK: - Data Operations

    private func loadWorks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            works = try await container.creativeExpressionService.fetchGallery()
        } catch {
            Log.creative.error("Failed to load gallery", error: error)
        }
    }

    private func toggleFavorite(_ work: CreativeWork) async {
        do {
            let newStatus = try await container.creativeExpressionService.toggleFavorite(workId: work.id)
            if let index = works.firstIndex(where: { $0.id == work.id }) {
                works[index].isFavorite = newStatus
            }
        } catch {
            Log.creative.error("Failed to toggle favorite", error: error)
        }
    }

    private func deleteWork(_ work: CreativeWork) async {
        do {
            try await container.creativeExpressionService.deleteWork(id: work.id)
            works.removeAll { $0.id == work.id }
        } catch {
            Log.creative.error("Failed to delete work", error: error)
        }
        workToDelete = nil
    }

    private func refreshDisplayMedia() async {
        guard !isRefreshingMedia else { return }
        isRefreshingMedia = true
        defer { isRefreshingMedia = false }
        do {
            let refreshed = try await container.creativeExpressionService.refreshMedia(works)
            try Task.checkCancellation()
            let urls = Dictionary(uniqueKeysWithValues: refreshed.map { ($0.id, $0.mediaUrl) })
            for index in works.indices {
                if let url = urls[works[index].id] { works[index].mediaUrl = url }
            }
        } catch {
            if !Task.isCancelled { Log.creative.error("Failed to refresh gallery media", error: error) }
        }
    }
}

/// Keeps asynchronous signing and its sheet on the screen that owns the Share action.
@MainActor
final class CreativeWorkSharing: ObservableObject {
    struct Item: Identifiable {
        let id = UUID()
        let url: URL
    }
    @Published var item: Item?
    @Published var error: String?
    private var task: Task<Void, Never>?

    func share(_ work: CreativeWork, using service: CreativeExpressionService) {
        task?.cancel()
        error = nil
        task = Task { [weak self] in
            do {
                let url = try await service.freshShareURL(for: work)
                try Task.checkCancellation()
                self?.item = Item(url: url)
            } catch {
                guard !Task.isCancelled else { return }
                self?.error = "Unable to prepare this link. Please try sharing again."
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

struct CreativeWorkSharePresentation: ViewModifier {
    @ObservedObject var sharing: CreativeWorkSharing

    func body(content: Content) -> some View {
        content
            .sheet(item: $sharing.item) { item in
                ShareSheet(items: ["Anyone with this link can open it for one hour.", item.url])
            }
            .alert("Unable to Share", isPresented: Binding(
                get: { sharing.error != nil }, set: { if !$0 { sharing.error = nil } }
            )) {
                Button("OK") { sharing.error = nil }
            } message: {
                Text(sharing.error ?? "Please try again.")
            }
            .onDisappear { sharing.cancel() }
    }
}

// MARK: - Filter Pill

struct FilterPill: View {
    let title: String
    var icon: String?
    var count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SupportTheme.Spacing.xxs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.subheadline)
                if let count = count, count > 0 {
                    Text("(\(count))")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
            .padding(.horizontal, SupportTheme.Spacing.m)
            .padding(.vertical, SupportTheme.Spacing.xs)
            .background(isSelected ? SupportTheme.accent : SupportTheme.surface)
            .foregroundStyle(isSelected ? SupportTheme.onAccent : SupportTheme.textPrimary)
            .cornerRadius(SupportTheme.cardRadius)
        }
    }
}

// MARK: - Gallery Thumbnail View

struct GalleryThumbnailView: View {
    let work: CreativeWork

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            // Thumbnail
            ZStack(alignment: .topTrailing) {
                thumbnailImage
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))

                if work.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textPrimary)
                        .padding(SupportTheme.Spacing.xxs)
                        .background(Color.red)
                        .clipShape(Circle())
                        .padding(SupportTheme.Spacing.xs)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                HStack(spacing: SupportTheme.Spacing.xxs) {
                    Image(systemName: work.workType.icon)
                        .font(.caption2)
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text(work.title ?? work.workType.displayName)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(work.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let path = work.storagePath {
            AsyncImage(url: storageURL(for: path)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholderView
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(SupportTheme.surface)
                @unknown default:
                    placeholderView
                }
            }
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(SupportTheme.surface)
            .overlay {
                Image(systemName: work.workType.icon)
                    .font(.largeTitle)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
    }

    private func storageURL(for path: String) -> URL? { work.mediaUrl }

    private var accessibilityLabel: String {
        var label = work.workType.displayName
        if let title = work.title {
            label = "\(title), \(label)"
        }
        label += ", created \(work.createdAt.formatted(date: .abbreviated, time: .omitted))"
        if work.isFavorite {
            label += ", favorited"
        }
        return label
    }
}

// MARK: - Creative Work Detail View

struct CreativeWorkDetailView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sharing = CreativeWorkSharing()

    let work: CreativeWork
    @State private var localWork: CreativeWork
    @State private var analysis: VoiceJournalAnalysis?
    @State private var showingVoiceAnalysis = false
    @State private var showingDeleteAlert = false
    @State private var isPlaying = false
    @State private var audioPlayer: AVPlayer?
    @State private var playbackError: String?
    @State private var playbackTask: Task<Void, Never>?

    init(work: CreativeWork) {
        self.work = work
        _localWork = State(initialValue: work)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Main content based on type
                contentView

                // Metadata
                metadataSection

                // Mood tags
                if let tags = localWork.moodTags, !tags.isEmpty {
                    tagsSection(tags)
                }

                // Voice analysis (if applicable)
                if localWork.workType == .voiceJournal, let analysis = analysis {
                    voiceAnalysisSection(analysis)
                }
                if localWork.workType == .voiceJournal {
                    Button {
                        showingVoiceAnalysis = true
                    } label: {
                        Label(analysis == nil ? "Analyze Recording" : "View Analysis", systemImage: "waveform")
                    }
                    .buttonStyle(.supportSecondary)
                }
            }
            .padding(SupportTheme.Spacing.m)
        }
        .supportScreen()
        .navigationTitle(localWork.workType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await toggleFavorite() }
                    } label: {
                        Label(
                            localWork.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                            systemImage: localWork.isFavorite ? "heart.slash" : "heart"
                        )
                    }

                    if localWork.storagePath != nil {
                        Button {
                            sharing.share(localWork, using: container.creativeExpressionService)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }

                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("More options")
                }
            }
        }
        .alert("Delete Creation?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteWork() }
            }
        } message: {
            Text("This cannot be undone.")
        }
        .modifier(CreativeWorkSharePresentation(sharing: sharing))
        .sheet(isPresented: $showingVoiceAnalysis, onDismiss: {
            Task { await loadAnalysis() }
        }) {
            VoiceJournalAnalysisView(work: localWork, analyzeOnOpen: false)
        }
        .onDisappear {
            playbackTask?.cancel()
            playbackTask = nil
            audioPlayer?.pause()
            audioPlayer = nil
            isPlaying = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            if let item = notification.object as? AVPlayerItem, item === audioPlayer?.currentItem {
                isPlaying = false
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            if let refreshed = try? await container.creativeExpressionService.refreshMedia([localWork]),
               !Task.isCancelled, let url = refreshed.first?.mediaUrl {
                localWork.mediaUrl = url
            }
            if localWork.workType == .voiceJournal {
                await loadAnalysis()
            }
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch localWork.workType {
        case .aiArt, .drawing:
            if let path = localWork.storagePath {
                AsyncImage(url: storageURL(for: path)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                            .shadow(radius: 8)
                    case .failure:
                        imagePlaceholder
                    case .empty:
                        ProgressView()
                            .frame(height: 300)
                    @unknown default:
                        imagePlaceholder
                    }
                }
            } else {
                imagePlaceholder
            }

        case .voiceJournal:
            voicePlayerView

        case .collage:
            if let path = localWork.storagePath {
                AsyncImage(url: storageURL(for: path)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView()
                }
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
            }
        }
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(SupportTheme.surface)
            .frame(height: 300)
            .overlay {
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("Image not available")
                        .font(.caption)
                }
                .foregroundStyle(SupportTheme.textSecondary)
            }
            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }

    private var voicePlayerView: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            // Waveform placeholder
            WaveformVisualization(
                levels: Array(repeating: 0.3, count: 40),
                isRecording: false
            )
            .frame(height: 60)

            // Time display
            if let duration = localWork.durationSeconds {
                Text(formatDuration(duration))
                    .font(.system(.largeTitle, design: .monospaced).weight(.light))
            }

            // Play button
            Button {
                playbackTask?.cancel()
                playbackTask = Task { await toggleVoicePlayback() }
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(.largeTitle))
                    .foregroundStyle(SupportTheme.accent)
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel(isPlaying ? "Pause" : "Play")
            }

            if let playbackError { Text(playbackError).font(.caption).foregroundStyle(SupportTheme.textSecondary) }

            // Transcription
            if let transcription = analysis?.fullTranscription ?? localWork.transcription {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Transcription")
                        .font(.headline)
                    Text(transcription)
                        .font(.body)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .padding(SupportTheme.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SupportTheme.surface)
                .cornerRadius(SupportTheme.controlRadius)
            }
        }
        .supportCard()
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            if let title = localWork.title {
                Text(title)
                    .font(.title2.bold())
            }

            if let prompt = localWork.generationPrompt {
                Text("\"\(prompt)\"")
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            HStack(spacing: SupportTheme.Spacing.m) {
                Label(localWork.createdAt.formatted(date: .long, time: .shortened), systemImage: "calendar")

                if let mood = localWork.moodScore {
                    Label("\(mood)/10", systemImage: "face.smiling")
                }

                if let style = localWork.artStyle {
                    Label(style.displayName, systemImage: "paintbrush")
                }
            }
            .font(.caption)
            .foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tagsSection(_ tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text("Mood Tags")
                .font(.headline)

            FlowLayout(spacing: SupportTheme.Spacing.xs) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag.capitalized)
                        .font(.caption)
                        .padding(.horizontal, SupportTheme.Spacing.s)
                        .padding(.vertical, SupportTheme.Spacing.xxs)
                        .background(SupportTheme.surface)
                        .cornerRadius(SupportTheme.cardRadius)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func voiceAnalysisSection(_ analysis: VoiceJournalAnalysis) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            Text("Insights are inferred from the transcript.")
                .font(.caption).foregroundStyle(SupportTheme.textSecondary)
            Text("Insights")
                .font(.headline)

            if let summary = analysis.aiSummary {
                Text(summary)
                    .font(.subheadline)
            }

            if !analysis.keyThemes.isEmpty {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("Key Themes")
                        .font(.caption.bold())
                    FlowLayout(spacing: SupportTheme.Spacing.xs) {
                        ForEach(analysis.keyThemes, id: \.self) { theme in
                            Text(theme)
                                .font(.caption)
                                .padding(.horizontal, SupportTheme.Spacing.xs)
                                .padding(.vertical, SupportTheme.Spacing.xxs)
                                .background(SupportTheme.surface)
                                .cornerRadius(SupportTheme.controlRadius)
                        }
                    }
                }
            }

            if !analysis.reflectionPrompts.isEmpty {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Reflection Prompts")
                        .font(.caption.bold())
                    ForEach(analysis.reflectionPrompts, id: \.self) { prompt in
                        HStack(alignment: .top, spacing: SupportTheme.Spacing.xs) {
                            Image(systemName: "lightbulb")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.accent)
                            Text(prompt)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .padding(SupportTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)
    }

    // MARK: - Actions

    private func toggleVoicePlayback() async {
        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
            return
        }
        do {
            guard let path = localWork.storagePath else { return }
            let url = try await supabase.storage.from("creative-works").createSignedURL(path: path, expiresIn: 3600)
            try Task.checkCancellation()
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = AVPlayer(url: url)
            audioPlayer?.play()
            isPlaying = true
            playbackError = nil
        } catch {
            guard !Task.isCancelled else { return }
            playbackError = "Unable to play this recording. Please try again."
            isPlaying = false
        }
    }

    private func toggleFavorite() async {
        do {
            let newStatus = try await container.creativeExpressionService.toggleFavorite(workId: localWork.id)
            localWork.isFavorite = newStatus
        } catch {
            Log.creative.error("Failed to toggle favorite", error: error)
        }
    }

    private func deleteWork() async {
        do {
            try await container.creativeExpressionService.deleteWork(id: localWork.id)
            dismiss()
        } catch {
            Log.creative.error("Failed to delete work", error: error)
        }
    }

    private func loadAnalysis() async {
        do {
            analysis = try await container.creativeExpressionService.fetchVoiceAnalysis(workId: localWork.id)
        } catch {
            Log.creative.error("Failed to load analysis", error: error)
        }
    }

    private func storageURL(for path: String) -> URL? { localWork.mediaUrl }

    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    NavigationStack {
        CreativeGalleryView()
    }
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
