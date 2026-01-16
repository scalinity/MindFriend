import SwiftUI

struct CreativeHubView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var recentWorks: [CreativeWork] = []
    @State private var quota: CreativeQuota?
    @State private var isLoading = true
    @State private var showArtGenerator = false
    @State private var showVoiceRecorder = false
    @State private var showDrawingCanvas = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Quota display
                if let quota = quota {
                    QuotaCard(quota: quota)
                }

                // Quick Create Section
                quickCreateSection

                // Recent Creations
                if !recentWorks.isEmpty {
                    recentCreationsSection
                }

                // Creative Exercises
                exercisesSection
            }
            .padding()
        }
        .navigationTitle("Create")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CreativeGalleryView()
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                }
                .accessibilityLabel("Gallery")
            }
        }
        .sheet(isPresented: $showArtGenerator) {
            ArtGeneratorView()
        }
        .sheet(isPresented: $showVoiceRecorder) {
            VoiceJournalRecorderView()
        }
        .fullScreenCover(isPresented: $showDrawingCanvas) {
            DrawingCanvasView()
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
    }

    // MARK: - Quick Create Section

    private var quickCreateSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Express Yourself")
                .font(.headline)

            HStack(spacing: 12) {
                QuickCreateButton(
                    icon: "wand.and.stars",
                    title: "AI Art",
                    subtitle: "Create from feelings",
                    color: .purple
                ) {
                    showArtGenerator = true
                }

                QuickCreateButton(
                    icon: "mic.fill",
                    title: "Voice",
                    subtitle: "Record thoughts",
                    color: .red
                ) {
                    showVoiceRecorder = true
                }

                QuickCreateButton(
                    icon: "pencil.tip",
                    title: "Draw",
                    subtitle: "Free expression",
                    color: .blue
                ) {
                    showDrawingCanvas = true
                }
            }
        }
    }

    // MARK: - Recent Creations Section

    private var recentCreationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Creations")
                    .font(.headline)
                Spacer()
                NavigationLink("See All") {
                    CreativeGalleryView()
                }
                .font(.subheadline)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recentWorks.prefix(5)) { work in
                        NavigationLink {
                            CreativeWorkDetailView(work: work)
                        } label: {
                            CreativeWorkThumbnail(work: work)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Exercises Section

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Guided Exercises")
                .font(.headline)

            NavigationLink {
                CreativeExercisesListView()
            } label: {
                HStack {
                    Image(systemName: "paintpalette")
                        .font(.title2)
                        .foregroundStyle(.purple)
                        .frame(width: 44, height: 44)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Art Therapy Exercises")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Text("Guided creative activities for emotional expression")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
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
            print("CreativeHubView loadData error: \(error)")
        }
    }
}

// MARK: - Supporting Views

struct QuotaCard: View {
    let quota: CreativeQuota

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(quota.aiArtLimit - quota.aiArtCount) AI Art", systemImage: "wand.and.stars")
                    .font(.caption)
                Text("remaining today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Label("\(quota.voiceMinutesLimit - quota.voiceMinutesUsed) min Voice", systemImage: "mic")
                    .font(.caption)
                Text("remaining today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !quota.isPremium {
                Button {
                    // Show paywall
                } label: {
                    Text("Upgrade")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
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
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(color)

                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(0.1))
            .cornerRadius(12)
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
        VStack(alignment: .leading, spacing: 8) {
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
            .clipShape(RoundedRectangle(cornerRadius: 12))

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
        .frame(width: 120)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(work.workType.displayName) from \(work.createdAt.formatted(date: .abbreviated, time: .omitted))")
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color(.secondarySystemBackground))
            .overlay {
                Image(systemName: work.workType.icon)
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
    }

    private func storageURL(for path: String) -> URL? {
        guard let baseURL = URL(string: SupabaseConfig.projectURL.absoluteString) else { return nil }
        return baseURL.appendingPathComponent("storage/v1/object/public/creative-works/\(path)")
    }
}

#Preview {
    NavigationStack {
        CreativeHubView()
    }
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
