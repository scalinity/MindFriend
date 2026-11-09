import SwiftUI

struct CreativeHubView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.scenePhase) private var scenePhase

    @State private var recentWorks: [CreativeWork] = []
    @State private var quota: CreativeQuota?
    @State private var isLoading = true
    @State private var showArtGenerator = false
    @State private var showVoiceRecorder = false
    @State private var showDrawingCanvas = false

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                // Quota display
                if let quota = quota {
                    QuotaCard(quota: quota)
                        .padding(.horizontal, SupportTheme.Spacing.m)
                }

                // Quick Create Section
                quickCreateSection
                    .padding(.horizontal, SupportTheme.Spacing.m)

                // Recent Creations
                if !recentWorks.isEmpty {
                    recentCreationsSection
                }

                // Creative Exercises
                exercisesSection
                    .padding(.horizontal, SupportTheme.Spacing.m)
            }
            .padding(.vertical, SupportTheme.Spacing.m)
        }
        .supportScreen()
        .navigationTitle("Create")
        .navigationBarTitleDisplayMode(.large)

        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CreativeGalleryView()
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                }
                .accessibilityLabel("Gallery")
            }
        }
        .sheet(isPresented: $showArtGenerator, onDismiss: {
            Task { await loadData() }
        }) {
            ArtGeneratorView()
        }
        .sheet(isPresented: $showVoiceRecorder, onDismiss: {
            Task { await loadData() }
        }) {
            VoiceJournalRecorderView()
        }
        .fullScreenCover(isPresented: $showDrawingCanvas, onDismiss: {
            Task { await loadData() }
        }) {
            DrawingCanvasView()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            if recentWorks.isEmpty {
                await loadData()
            } else {
                do {
                    let refreshed = try await container.creativeExpressionService.refreshMedia(recentWorks)
                    try Task.checkCancellation()
                    recentWorks = refreshed
                } catch {
                    if !Task.isCancelled { Log.creative.error("Failed to refresh recent media", error: error) }
                }
            }
        }
        .refreshable {
            await loadData()
        }
    }

    // MARK: - Quick Create Section

    private var quickCreateSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            Text("Express Yourself")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), spacing: SupportTheme.Spacing.s) {
                QuickCreateButton(
                    icon: "wand.and.stars",
                    title: "AI Art",
                    subtitle: "Create from feelings",
                    color: SupportTheme.accent
                ) {
                    showArtGenerator = true
                }

                QuickCreateButton(
                    icon: "mic.fill",
                    title: "Voice",
                    subtitle: "Record thoughts",
                    color: SupportTheme.accent
                ) {
                    showVoiceRecorder = true
                }

                QuickCreateButton(
                    icon: "pencil.tip",
                    title: "Draw",
                    subtitle: "Free expression",
                    color: SupportTheme.accent
                ) {
                    showDrawingCanvas = true
                }
            }
        }
    }

    // MARK: - Recent Creations Section

    private var recentCreationsSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Text("Recent Creations")
                    .font(.headline)
                .accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink("See All") {
                    CreativeGalleryView()
                }
                .font(.subheadline)
            }
            .padding(.horizontal, SupportTheme.Spacing.m)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SupportTheme.Spacing.s) {
                    ForEach(recentWorks.prefix(5)) { work in
                        NavigationLink {
                            CreativeWorkDetailView(work: work)
                        } label: {
                            CreativeWorkThumbnail(work: work)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)
            }
        }
    }

    // MARK: - Exercises Section

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Guided Exercises")
                .font(.headline)

            NavigationLink {
                CreativeExercisesListView()
            } label: {
                HStack {
                    Image(systemName: "paintpalette")
                        .font(.title2)
                        .foregroundStyle(SupportTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(SupportTheme.surface)
                        .cornerRadius(SupportTheme.controlRadius)

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text("Art Therapy Exercises")
                            .font(.subheadline.bold())
                            .foregroundStyle(SupportTheme.textPrimary)
                        Text("Guided creative activities for emotional expression")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .supportCard()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let quotaTask = container.creativeExpressionService.fetchQuota()
            async let worksTask = container.creativeExpressionService.fetchGallery(limit: 10)

            quota = try await quotaTask
            recentWorks = try await worksTask
        } catch {
            Log.creative.error("CreativeHubView loadData error", error: error)
        }
    }
}

// MARK: - Supporting Views

struct QuotaCard: View {
    let quota: CreativeQuota

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.m) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Label("\(quota.aiArtLimit - quota.aiArtCount) AI Art", systemImage: "wand.and.stars")
                    .font(.caption.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text("left today")
                    .font(.caption2)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            .fixedSize(horizontal: true, vertical: false)

            Divider()
                .frame(height: 30)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Label("\(quota.voiceMinutesLimit - quota.voiceMinutesUsed) min Voice", systemImage: "mic")
                    .font(.caption.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text("left today")
                    .font(.caption2)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer()

            if !quota.isPremium {
                Button {
                    // Show paywall
                } label: {
                    Text("Upgrade")
                        .font(.caption.bold())
                        .padding(.horizontal, SupportTheme.Spacing.s)
                        .padding(.vertical, SupportTheme.Spacing.xxs)
                        .background(SupportTheme.accent)
                        .foregroundStyle(SupportTheme.onAccent)
                        .cornerRadius(SupportTheme.controlRadius)
                }
                .fixedSize()
            }
        }
        .supportCard()
    }
}

struct QuickCreateButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(color)

                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(SupportTheme.textPrimary)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SupportTheme.Spacing.m)
            .background(SupportTheme.surface)
            .cornerRadius(SupportTheme.controlRadius)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityHint("Double tap to start")
    }
}

struct CreativeWorkThumbnail: View {
    let work: CreativeWork

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            // Thumbnail image
            Group {
                if let storagePath = work.storagePath {
                    AsyncImage(url: storageURL(for: storagePath)) { phase in
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
                        @unknown default:
                            placeholderView
                        }
                    }
                } else {
                    placeholderView
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))

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
        .frame(width: 120)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(work.workType.displayName) from \(work.createdAt.formatted(date: .abbreviated, time: .omitted))")
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(SupportTheme.surface)
            .overlay {
                Image(systemName: work.workType.icon)
                    .font(.title)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
    }

    private func storageURL(for path: String) -> URL? { work.mediaUrl }
}

#Preview {
    NavigationStack {
        CreativeHubView()
    }
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
