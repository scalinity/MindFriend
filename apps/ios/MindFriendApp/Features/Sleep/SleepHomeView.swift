import SwiftUI

/// Main view for the Sleep & Wind-Down feature
struct SleepHomeView: View {
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: SleepViewModel
    @State private var selectedContent: SleepContent?
    @State private var showPlayer = false
    @State private var selectedTab: SleepContentType = .story

    init(container: DependencyContainer, appState: AppState) {
        _viewModel = StateObject(wrappedValue: SleepViewModel(container: container, appState: appState))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Night-themed background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.15),
                        Color(red: 0.1, green: 0.1, blue: 0.25)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let error = viewModel.error {
                    errorView(error)
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header
                            headerView

                            // Content type tabs
                            contentTypeTabs

                            // Featured section
                            if !viewModel.featuredContent.isEmpty {
                                featuredSection
                            }

                            // Content based on selected tab
                            switch selectedTab {
                            case .story:
                                storiesSection
                            case .soundscape:
                                soundscapesSection
                            case .routine:
                                routinesSection
                            }
                        }
                        .padding(.bottom, 100) // Space for mini player
                    }
                }

                // Mini player overlay
                if viewModel.playerState.currentContent != nil {
                    VStack {
                        Spacer()
                        miniPlayer
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Sleep")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Show bedtime reminder settings
                    } label: {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(.white)
                    }
                }
            }
            .sheet(isPresented: $showPlayer) {
                if let content = selectedContent {
                    SleepPlayerView(content: content, viewModel: viewModel)
                }
            }
            .onChange(of: selectedContent) { _, newContent in
                if newContent != nil {
                    showPlayer = true
                }
            }
        }
        .task {
            await viewModel.loadContent()
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greeting)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text("Ready for restful sleep?")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 18 || hour < 4 {
            return String(localized: "Good evening")
        } else if hour >= 4 && hour < 12 {
            return String(localized: "Good morning")
        } else {
            return String(localized: "Good afternoon")
        }
    }

    private var contentTypeTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SleepContentType.allCases) { type in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = type
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: type.icon)
                            Text(type.displayName)
                        }
                        .font(.subheadline)
                        .fontWeight(selectedTab == type ? .semibold : .regular)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            selectedTab == type
                                ? Color.indigo
                                : Color.white.opacity(0.1)
                        )
                        .foregroundStyle(
                            selectedTab == type
                                ? .white
                                : .white.opacity(0.8)
                        )
                        .cornerRadius(20)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Featured Tonight")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(viewModel.featuredContent) { content in
                        SleepContentCard(
                            content: content,
                            isPremiumUser: appState.entitlements.tier == .premium
                        ) {
                            selectedContent = content
                            Task {
                                await viewModel.play(content)
                            }
                        }
                        .frame(width: 160, height: 180)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var storiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Stories")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal)

            if viewModel.stories.isEmpty {
                emptyStateView(for: .story)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.stories) { content in
                        SleepContentListItem(
                            content: content,
                            isPremiumUser: appState.entitlements.tier == .premium
                        ) {
                            selectedContent = content
                            Task {
                                await viewModel.play(content)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var soundscapesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Soundscapes")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal)

            if viewModel.soundscapes.isEmpty {
                emptyStateView(for: .soundscape)
            } else {
                // Grid layout for soundscapes
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .top),
                        GridItem(.flexible(), alignment: .top)
                    ],
                    spacing: 16
                ) {
                    ForEach(viewModel.soundscapes) { content in
                        SleepContentCard(
                            content: content,
                            isPremiumUser: appState.entitlements.tier == .premium
                        ) {
                            selectedContent = content
                            Task {
                                await viewModel.play(content)
                            }
                        }
                        .frame(height: 180)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wind-Down Routines")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal)

            Text("Guided routines coming soon...")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        }
    }

    private func emptyStateView(for type: SleepContentType) -> some View {
        VStack(spacing: 12) {
            Image(systemName: type.icon)
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.4))

            Text("No \(type.displayName.lowercased()) available")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task {
                    await viewModel.loadContent()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
        .padding()
    }

    private var miniPlayer: some View {
        Group {
            if let content = viewModel.playerState.currentContent {
                HStack(spacing: 12) {
                    // Thumbnail
                    ZStack {
                        LinearGradient(
                            colors: [Color.indigo.opacity(0.8), Color.purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: content.contentType.icon)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 44, height: 44)
                    .cornerRadius(8)

                    // Info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(content.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(content.contentType.displayName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    // Controls
                    HStack(spacing: 16) {
                        Button {
                            viewModel.togglePlayPause()
                        } label: {
                            Image(systemName: viewModel.playerState.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                        }

                        Button {
                            selectedContent = content
                            showPlayer = true
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SleepHomeView(container: DependencyContainer.preview, appState: AppState())
        .environmentObject(DependencyContainer.preview)
        .environmentObject(AppState())
}
