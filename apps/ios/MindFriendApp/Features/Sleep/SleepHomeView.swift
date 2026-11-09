import SwiftUI

/// Main view for the Sleep & Wind-Down feature
struct SleepHomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var appState: AppState
    @Environment(\.supportRootEmbedded) private var supportRootEmbedded
    @StateObject private var viewModel: SleepViewModel
    @State private var selectedContent: SleepContent?
    @State private var showPlayer = false
    @State private var selectedTab: SleepContentType = .story

    init(container: DependencyContainer, appState: AppState) {
        _viewModel = StateObject(wrappedValue: SleepViewModel(container: container, appState: appState))
    }

    var body: some View {
        // Inside the shell, Explore's stack hosts Sleep; standalone it brings its own.
        SupportRootNavigation(embedded: supportRootEmbedded) {
            ZStack {
                // Night-themed background gradient
                SupportTheme.canvas
                .ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                        .tint(SupportTheme.accent)
                } else if let error = viewModel.error {
                    errorView(error)
                } else {
                    ScrollView {
                        VStack(spacing: SupportTheme.Spacing.l) {
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
                        .padding(.bottom, SupportTheme.Spacing.xl)
                    }
                }
            }
            // The mini player reserves its own height, so the last item scrolls clear of it at any text size.
            .safeAreaInset(edge: .bottom) {
                if viewModel.playerState.currentContent != nil {
                    miniPlayer
                }
            }
            .supportScreen()
            .navigationTitle("Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        // Show bedtime reminder settings.
                    } label: {
                        Label("Bedtime reminder", systemImage: "bell.badge")
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
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text(greeting)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(SupportTheme.textPrimary)

            Text("Ready for restful sleep?")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textPrimary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SupportTheme.Spacing.m)
        .padding(.top, SupportTheme.Spacing.m)
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
            HStack(spacing: SupportTheme.Spacing.s) {
                ForEach(SleepContentType.allCases) { type in
                    Button {
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.2)) {
                            selectedTab = type
                        }
                    } label: {
                        HStack(spacing: SupportTheme.Spacing.xxs) {
                            Image(systemName: type.icon)
                            Text(type.displayName)
                        }
                        .font(.subheadline)
                        .fontWeight(selectedTab == type ? .semibold : .regular)
                        .padding(.horizontal, SupportTheme.Spacing.m)
                        .padding(.vertical, SupportTheme.Spacing.xs)
                        .background(
                            selectedTab == type
                                ? SupportTheme.accent
                                : SupportTheme.surface.opacity(0.1)
                        )
                        .foregroundStyle(
                            selectedTab == type
                                ? SupportTheme.onAccent
                                : SupportTheme.textPrimary.opacity(0.8)
                        )
                        .cornerRadius(SupportTheme.cardRadius)
                    }
                }
            }
            .padding(.horizontal, SupportTheme.Spacing.m)
        }
    }

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Featured Tonight")
                .font(.headline)
                .foregroundStyle(SupportTheme.textPrimary)
                .padding(.horizontal, SupportTheme.Spacing.m)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: SupportTheme.Spacing.m) {
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
                .padding(.horizontal, SupportTheme.Spacing.m)
            }
        }
    }

    private var storiesSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Sleep Stories")
                .font(.headline)
                .foregroundStyle(SupportTheme.textPrimary)
                .padding(.horizontal, SupportTheme.Spacing.m)

            if viewModel.stories.isEmpty {
                emptyStateView(for: .story)
            } else {
                LazyVStack(spacing: SupportTheme.Spacing.xs) {
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
                .padding(.horizontal, SupportTheme.Spacing.m)
            }
        }
    }

    private var soundscapesSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Soundscapes")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .foregroundStyle(SupportTheme.textPrimary)
                .padding(.horizontal, SupportTheme.Spacing.m)

            if viewModel.soundscapes.isEmpty {
                emptyStateView(for: .soundscape)
            } else {
                // Grid layout for soundscapes
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                    spacing: SupportTheme.Spacing.m
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
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)
            }
        }
    }

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Wind-Down Routines")
                .font(.headline)
                .foregroundStyle(SupportTheme.textPrimary)
                .padding(.horizontal, SupportTheme.Spacing.m)

            Text("Guided routines coming soon...")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textPrimary.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, SupportTheme.Spacing.xl)
        }
    }

    private func emptyStateView(for type: SleepContentType) -> some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: type.icon)
                .font(.largeTitle)
                .foregroundStyle(SupportTheme.textPrimary.opacity(0.4))

            Text("No \(type.displayName.lowercased()) available")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textPrimary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SupportTheme.Spacing.xl)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(SupportTheme.accent)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textPrimary.opacity(0.8))
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task {
                    await viewModel.loadContent()
                }
            }
            .buttonStyle(.supportPrimary)
            .tint(SupportTheme.accent)
        }
        .padding(SupportTheme.Spacing.m)
    }

    private var miniPlayer: some View {
        Group {
            if let content = viewModel.playerState.currentContent {
                HStack(spacing: SupportTheme.Spacing.s) {
                    // Thumbnail
                    ZStack {
                        SupportTheme.surface
                        Image(systemName: content.contentType.icon)
                            .foregroundStyle(SupportTheme.textPrimary)
                    }
                    .frame(width: 44, height: 44)
                    .cornerRadius(SupportTheme.controlRadius)

                    // Info
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text(content.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(SupportTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(content.contentType.displayName)
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textPrimary.opacity(0.7))
                    }

                    Spacer()

                    // Controls
                    HStack(spacing: SupportTheme.Spacing.m) {
                        Button {
                            viewModel.togglePlayPause()
                        } label: {
                            Image(systemName: viewModel.playerState.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                                .foregroundStyle(SupportTheme.textPrimary)
                                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                                .accessibilityLabel(viewModel.playerState.isPlaying ? "Pause" : "Play")
                        }

                        Button {
                            selectedContent = content
                            showPlayer = true
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.title3)
                                .foregroundStyle(SupportTheme.textPrimary.opacity(0.7))
                                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                                .accessibilityLabel("Open player")
                        }
                    }
                }
                .padding(SupportTheme.Spacing.m)
                .background(SupportTheme.elevated)
                .cornerRadius(SupportTheme.cardRadius)
                .padding(.horizontal, SupportTheme.Spacing.m)
                .padding(.bottom, SupportTheme.Spacing.xs)
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
