import SwiftUI
import UIKit

/// Full-screen swipeable story viewer for weekly progress recaps
struct ProgressStoryViewer: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var appState: AppState

    /// Week start date (nil = current week)
    let weekStart: Date?

    /// Privacy mode setting
    var privacyMode: Bool = false

    /// Callback when share sheet should be presented
    var onShare: ((UIImage) -> Void)?

    @State private var viewModel: ProgressStoryViewModel?
    @State private var showSaveSuccess = false
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var showLoadingTimeout = false
    @State private var showMoodLogger = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Dark background
                Color.black.ignoresSafeArea()

                if let vm = viewModel {
                    if vm.isLoading && vm.story == nil {
                        loadingView
                    } else if let story = vm.story, !story.cards.isEmpty {
                        storyContentView(story: story, vm: vm)
                    } else if let error = vm.error {
                        errorView(error: error)
                    } else {
                        emptyView
                    }
                } else {
                    loadingView
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    closeButton
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel?.story != nil {
                        toolbarButtons
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            await initializeAndLoad()
        }
        .alert("Error", isPresented: .init(
            get: { viewModel?.showError ?? false },
            set: { viewModel?.showError = $0 }
        )) {
            Button("OK") {
                viewModel?.showError = false
            }
        } message: {
            Text(viewModel?.error?.localizedDescription ?? "An error occurred")
        }
        .overlay(alignment: .bottom) {
            if showSaveSuccess {
                saveSuccessToast
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                StoryShareSheet(items: [image])
            }
        }
        .sheet(isPresented: .init(
            get: { viewModel?.showCircleShare ?? false },
            set: { viewModel?.showCircleShare = $0 }
        )) {
            if let vm = viewModel {
                CircleShareSheet(
                    viewModel: vm,
                    cardIndex: vm.currentIndex
                )
            }
        }
        .sheet(isPresented: $showMoodLogger) {
            MoodCheckInView()
                .environmentObject(container)
                .environmentObject(appState)
        }
    }

    // MARK: - Story Content

    @ViewBuilder
    private func storyContentView(story: WeeklyStory, vm: ProgressStoryViewModel) -> some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressIndicator(current: vm.currentIndex, total: story.cards.count)
                .padding(.top, 16)
                .padding(.horizontal, 16)

            // Swipeable cards - use safe binding from non-optional vm parameter
            TabView(selection: Binding(
                get: { vm.currentIndex },
                set: { vm.currentIndex = $0 }
            )) {
                ForEach(Array(story.cards.enumerated()), id: \.offset) { index, card in
                    StoryCardView(
                        card: card,
                        privacyMode: privacyMode,
                        onCTAAction: { ctaTitle in
                            handleCTAAction(ctaTitle)
                        }
                    )
                    .tag(index)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 32)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.currentIndex)

            // Action buttons
            actionButtons
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
        }
    }

    // MARK: - Progress Indicator

    @ViewBuilder
    private func progressIndicator(current: Int, total: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.white : Color.white.opacity(0.3))
                    .frame(height: 3)
                    .animation(.easeInOut(duration: 0.2), value: current)
            }
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 16) {
            // Save to Photos
            Button {
                Task { await saveToPhotos() }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.2))
                    )
            }
            .disabled(viewModel?.isExporting ?? false)

            // Share
            Button {
                Task { await shareCard() }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.2))
                    )
            }
            .disabled(viewModel?.isExporting ?? false)

            // Share to Circle
            Button {
                Task { await prepareCircleShare() }
            } label: {
                Label("Circle", systemImage: "person.2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.2))
                    )
            }
            .disabled(viewModel?.isExporting ?? false)
        }
    }

    // MARK: - Toolbar Buttons

    @ViewBuilder
    private var toolbarButtons: some View {
        if viewModel?.isExporting ?? false {
            ProgressView()
                .tint(.white)
        }
    }

    // MARK: - Close Button

    @ViewBuilder
    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(.white.opacity(0.2))
                )
        }
    }

    // MARK: - Loading View

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Loading your story...")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            if showLoadingTimeout {
                Text("This is taking longer than usual. Check your connection and try refreshing.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Button("Retry") {
                    Task { await viewModel?.loadStory() }
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .task {
            // Show timeout message after 10 seconds
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if viewModel?.isLoading ?? false {
                withAnimation {
                    showLoadingTimeout = true
                }
            }
        }
    }

    // MARK: - Empty View

    @ViewBuilder
    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Story Yet", systemImage: "book.closed")
                .foregroundStyle(.white)
        } description: {
            Text("Your weekly story will appear here after you've logged some activities.")
                .foregroundStyle(.white.opacity(0.7))
        } actions: {
            Button("Generate Story") {
                Task { await viewModel?.generateStory() }
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(error: StoryViewError) -> some View {
        ContentUnavailableView {
            Label("Unable to Load", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.white)
        } description: {
            Text(error.localizedDescription)
                .foregroundStyle(.white.opacity(0.7))
        } actions: {
            Button("Try Again") {
                Task { await viewModel?.loadStory() }
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }

    // MARK: - Save Success Toast

    @ViewBuilder
    private var saveSuccessToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text("Saved to Photos")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.regularMaterial)
        )
        .padding(.bottom, 120)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.3), value: showSaveSuccess)
    }

    // MARK: - Actions

    private func initializeAndLoad() async {
        let week = weekStart ?? Date()
        viewModel = ProgressStoryViewModel(
            dataService: container.supabaseDataService,
            weekStart: week
        )
        await viewModel?.loadStory()
    }

    private func saveToPhotos() async {
        guard let vm = viewModel else { return }
        await vm.saveToPhotos(index: vm.currentIndex)

        // Show success toast
        withAnimation {
            showSaveSuccess = true
        }

        // Hide toast after 2 seconds with proper cancellation handling
        do {
            try await Task.sleep(for: .seconds(2))
            withAnimation {
                showSaveSuccess = false
            }
        } catch {
            // Task was cancelled (view dismissed), ignore
        }
    }

    private func shareCard() async {
        guard let vm = viewModel else { return }
        await vm.prepareShare(index: vm.currentIndex)

        if let image = vm.exportedImage {
            if let onShare = onShare {
                // Use custom share handler
                onShare(image)
            } else {
                // Show share sheet
                shareImage = image
                showShareSheet = true
            }
        }
    }

    private func prepareCircleShare() async {
        guard let vm = viewModel else { return }
        await vm.prepareShare(index: vm.currentIndex)
        vm.showCircleShare = true
    }

    private func handleCTAAction(_ ctaTitle: String) {
        // Handle different CTA actions based on title
        let normalizedTitle = ctaTitle.lowercased()

        if normalizedTitle.contains("mood") || normalizedTitle.contains("log") {
            showMoodLogger = true
        }
        // Add other CTA handlers here as needed (e.g., exercise, quest)
    }
}

// MARK: - Story Share Sheet (UIKit Wrapper)

private struct StoryShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    ProgressStoryViewer(weekStart: nil)
        .environmentObject(DependencyContainer.preview)
        .environmentObject(AppState())
}
