import SwiftUI

struct CreativeGalleryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var works: [CreativeWork] = []
    @State private var selectedFilter: CreativeWorkType?
    @State private var isLoading = true
    @State private var showingDeleteAlert = false
    @State private var workToDelete: CreativeWork?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var filteredWorks: [CreativeWork] {
        guard let filter = selectedFilter else { return works }
        return works.filter { $0.workType == filter }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Filter Pills
                filterSection

                // Grid
                if isLoading {
                    ProgressView()
                        .padding(.top, 60)
                } else if filteredWorks.isEmpty {
                    emptyStateView
                } else {
                    galleryGrid
                }
            }
        }
        .navigationTitle("Gallery")
        .task {
            await loadWorks()
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
            HStack(spacing: 8) {
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
            .padding(.horizontal)
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
            .buttonStyle(.bordered)
        }
        .padding(.top, 60)
    }

    // MARK: - Gallery Grid

    private var galleryGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(filteredWorks) { work in
                NavigationLink {
                    CreativeWorkDetailView(work: work)
                } label: {
                    GalleryThumbnailView(work: work)
                        .contextMenu {
                            Button {
                                Task { await toggleFavorite(work) }
                            } label: {
                                Label(
                                    work.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                                    systemImage: work.isFavorite ? "heart.slash" : "heart"
                                )
                            }

                            if let url = shareURL(for: work) {
                                ShareLink(item: url) {
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
        .padding(.horizontal)
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

    private func shareURL(for work: CreativeWork) -> URL? {
        guard let path = work.storagePath,
              let baseURL = URL(string: SupabaseConfig.projectURL.absoluteString) else {
            return nil
        }
        return baseURL.appendingPathComponent("storage/v1/object/public/creative-works/\(path)")
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
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.subheadline)
                if let count = count, count > 0 {
                    Text("(\(count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }
}

// MARK: - Gallery Thumbnail View

struct GalleryThumbnailView: View {
    let work: CreativeWork

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack(alignment: .topTrailing) {
                thumbnailImage
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if work.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.red)
                        .clipShape(Circle())
                        .padding(8)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: work.workType.icon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(work.title ?? work.workType.displayName)
                        .font(.caption)
                        .lineLimit(1)
                }

                Text(work.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                        .background(Color(.secondarySystemBackground))
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
            .fill(Color(.secondarySystemBackground))
            .overlay {
                Image(systemName: work.workType.icon)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
    }

    private func storageURL(for path: String) -> URL? {
        guard let baseURL = URL(string: SupabaseConfig.projectURL.absoluteString) else { return nil }
        return baseURL.appendingPathComponent("storage/v1/object/public/creative-works/\(path)")
    }

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

    let work: CreativeWork
    @State private var localWork: CreativeWork
    @State private var analysis: VoiceJournalAnalysis?
    @State private var showingDeleteAlert = false
    @State private var isPlaying = false

    init(work: CreativeWork) {
        self.work = work
        _localWork = State(initialValue: work)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
            }
            .padding()
        }
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

                    if let url = shareURL {
                        ShareLink(item: url) {
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
        .task {
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
                            .clipShape(RoundedRectangle(cornerRadius: 16))
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
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(Color(.secondarySystemBackground))
            .frame(height: 300)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("Image not available")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var voicePlayerView: some View {
        VStack(spacing: 16) {
            // Waveform placeholder
            WaveformVisualization(
                levels: Array(repeating: 0.3, count: 40),
                isRecording: false
            )
            .frame(height: 60)

            // Time display
            if let duration = localWork.durationSeconds {
                Text(formatDuration(duration))
                    .font(.system(size: 32, weight: .light, design: .monospaced))
            }

            // Play button
            Button {
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.accentColor)
            }

            // Transcription
            if let transcription = localWork.transcription {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcription")
                        .font(.headline)
                    Text(transcription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = localWork.title {
                Text(title)
                    .font(.title2.bold())
            }

            if let prompt = localWork.generationPrompt {
                Text("\"\(prompt)\"")
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Label(localWork.createdAt.formatted(date: .long, time: .shortened), systemImage: "calendar")

                if let mood = localWork.moodScore {
                    Label("\(mood)/10", systemImage: "face.smiling")
                }

                if let style = localWork.artStyle {
                    Label(style.displayName, systemImage: "paintbrush")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tagsSection(_ tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mood Tags")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(16)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func voiceAnalysisSection(_ analysis: VoiceJournalAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insights")
                .font(.headline)

            if let summary = analysis.aiSummary {
                Text(summary)
                    .font(.subheadline)
            }

            if !analysis.keyThemes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Key Themes")
                        .font(.caption.bold())
                    FlowLayout(spacing: 8) {
                        ForEach(analysis.keyThemes, id: \.self) { theme in
                            Text(theme)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(12)
                        }
                    }
                }
            }

            if !analysis.reflectionPrompts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reflection Prompts")
                        .font(.caption.bold())
                    ForEach(analysis.reflectionPrompts, id: \.self) { prompt in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                            Text(prompt)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Actions

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

    private func storageURL(for path: String) -> URL? {
        guard let baseURL = URL(string: SupabaseConfig.projectURL.absoluteString) else { return nil }
        return baseURL.appendingPathComponent("storage/v1/object/public/creative-works/\(path)")
    }

    private var shareURL: URL? {
        guard let path = localWork.storagePath else { return nil }
        return storageURL(for: path)
    }

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
