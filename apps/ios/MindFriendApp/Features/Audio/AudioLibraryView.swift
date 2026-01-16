import SwiftUI

/// Main view for browsing and discovering audio content
struct AudioLibraryView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel: AudioLibraryViewModel

    @State private var selectedCategory: AudioCategory?
    @State private var searchText = ""
    @State private var selectedTrack: AudioTrack?
    @State private var showPlayer = false

    init(container: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: AudioLibraryViewModel(container: container))
    }

    var filteredTracks: [AudioTrack] {
        let categoryFiltered = selectedCategory == nil ? viewModel.allTracks : viewModel.allTracks.filter { $0.category == selectedCategory }
        guard !searchText.isEmpty else { return categoryFiltered }
        return categoryFiltered.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.description?.localizedCaseInsensitiveContains(searchText) ?? false }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    headerView

                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxHeight: .infinity)
                    } else if let error = viewModel.error {
                        errorView(error)
                    } else {
                        ScrollView {
                            VStack(spacing: 24) {
                                // Search bar
                                searchBarView

                                // Category filter
                                categoryFilterView

                                // Featured tracks section
                                if !viewModel.featuredTracks.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Featured")
                                            .font(.headline)
                                            .padding(.horizontal)

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(viewModel.featuredTracks) { track in
                                                    AudioTrackCard(track: track) {
                                                        selectedTrack = track
                                                        showPlayer = true
                                                    }
                                                    .frame(width: 160)
                                                }
                                            }
                                            .padding(.horizontal)
                                        }
                                    }
                                }

                                // Recent plays section
                                if !viewModel.recentlyPlayed.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Recently Played")
                                            .font(.headline)
                                            .padding(.horizontal)

                                        VStack(spacing: 8) {
                                            ForEach(viewModel.recentlyPlayed.prefix(5)) { track in
                                                AudioTrackListItem(track: track) {
                                                    selectedTrack = track
                                                    showPlayer = true
                                                }
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }

                                // All tracks section
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(selectedCategory?.displayName ?? "All Tracks")
                                        .font(.headline)
                                        .padding(.horizontal)

                                    if filteredTracks.isEmpty {
                                        VStack(spacing: 12) {
                                            Image(systemName: "music.note")
                                                .font(.title)
                                                .foregroundStyle(.secondary)
                                            Text("No tracks found")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 40)
                                    } else {
                                        VStack(spacing: 8) {
                                            ForEach(filteredTracks) { track in
                                                AudioTrackListItem(track: track) {
                                                    selectedTrack = track
                                                    showPlayer = true
                                                }
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }

                                Spacer(minLength: 20)
                            }
                            .padding(.vertical)
                        }
                    }
                }
            }
            .navigationTitle("Audio")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPlayer, onDismiss: { selectedTrack = nil }) {
                if let track = selectedTrack {
                    AudioPlayerView(track: track)
                        .environmentObject(container)
                }
            }
            .task {
                await viewModel.loadContent()
            }
        }
    }

    // MARK: - Components

    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome Back")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let completionCount = viewModel.userCompletionCount {
                        Text("Completed \(completionCount) sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding()
        }
        .background(Color(.secondarySystemBackground))
    }

    private var searchBarView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search tracks", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
    }

    private var categoryFilterView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All button
                FilterButton(
                    label: "All",
                    isSelected: selectedCategory == nil,
                    action: { selectedCategory = nil }
                )

                // Category buttons
                ForEach(AudioCategory.allCases, id: \.self) { category in
                    FilterButton(
                        label: category.displayName,
                        isSelected: selectedCategory == category,
                        action: { selectedCategory = category }
                    )
                }
            }
            .padding(.horizontal)
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)

            Text("Couldn't load audio content")
                .font(.headline)

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task {
                    await viewModel.loadContent()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Filter Button

struct FilterButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Audio Track Card

struct AudioTrackCard: View {
    let track: AudioTrack
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                // Cover image
                ZStack {
                    if let coverUrl = track.coverImageUrl {
                        AsyncImage(url: coverUrl) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Image(systemName: "music.note")
                                    .font(.title)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color(.tertiary))
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "music.note")
                            .font(.title)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.tertiary))
                    }

                    // Play button overlay
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    if let narrator = track.narrator {
                        Text(narrator.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text(track.shortDuration)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title)\(track.narrator.map { ", by \($0.name)" } ?? "")")
    }
}

// MARK: - Audio Track List Item

struct AudioTrackListItem: View {
    let track: AudioTrack
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Thumbnail
                ZStack {
                    if let coverUrl = track.coverImageUrl {
                        AsyncImage(url: coverUrl) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                            case .success(let image):
                                image.resizable()
                                    .scaledToFill()
                            case .failure:
                                Image(systemName: "music.note")
                                    .font(.caption)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "music.note")
                            .font(.caption)
                    }
                }
                .frame(width: 44, height: 44)
                .background(Color(.tertiary))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        if let narrator = track.narrator {
                            Text(narrator.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("•")
                            .foregroundStyle(.secondary)

                        Text(track.shortDuration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title), \(track.shortDuration)")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AudioLibraryView(container: DependencyContainer())
    }
}
