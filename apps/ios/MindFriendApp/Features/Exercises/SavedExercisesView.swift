import SwiftUI

// Import dependencies
// Note: DependencyContainer should be imported from the App module
// GeneratedContent and related types from GeneratedContentModels

/// View showing user's saved and favorited generated exercises
struct SavedExercisesView: View {
    @StateObject private var viewModel: SavedExercisesViewModel
    @Environment(\.dismiss) private var dismiss

    init(container: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: SavedExercisesViewModel(
            dataService: container.supabaseDataService
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading exercises...")
                } else if viewModel.exercises.isEmpty {
                    emptyState
                } else {
                    exercisesList
                }
            }
            .navigationTitle("My Exercises")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    filterMenu
                }
            }
            .refreshable {
                await viewModel.loadExercises()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
        }
        .task {
            await viewModel.loadExercises()
        }
    }

    private var exercisesList: some View {
        List {
            ForEach(viewModel.exercises) { exercise in
                ExerciseRowView(
                    exercise: exercise,
                    onToggleFavorite: {
                        Task {
                            await viewModel.toggleFavorite(exercise)
                        }
                    },
                    onRate: { rating in
                        Task {
                            await viewModel.rateExercise(exercise, rating: rating)
                        }
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectedExercise = exercise
                }
            }
        }
        .listStyle(.plain)
        .sheet(item: $viewModel.selectedExercise) { exercise in
            // TODO: Open full player view when implemented
            // For now, show a simple detail view
            exerciseDetailView(for: exercise)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Saved Exercises", systemImage: "wind")
        } description: {
            Text(viewModel.favoritesOnly
                ? "You haven't favorited any exercises yet"
                : "Generate your first exercise to get started")
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Filter by Type", selection: $viewModel.filterType) {
                Text("All Types").tag(nil as GeneratedContentType?)
                ForEach([GeneratedContentType.breathing, .meditation, .grounding, .journaling, .mindfulness]) { type in
                    Text(type.displayName).tag(type as GeneratedContentType?)
                }
            }

            Divider()

            Toggle("Favorites Only", isOn: $viewModel.favoritesOnly)
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .onChange(of: viewModel.filterType) {
            Task { await viewModel.loadExercises() }
        }
        .onChange(of: viewModel.favoritesOnly) {
            Task { await viewModel.loadExercises() }
        }
    }

    // Simple detail view until full player is implemented
    private func exerciseDetailView(for exercise: GeneratedContent) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(exercise.title)
                            .font(.title2.bold())

                        HStack {
                            Label(exercise.contentType.displayName, systemImage: exercise.contentType.icon)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            if let duration = exercise.duration {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text("\(duration / 60) min")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Divider()

                    // Content
                    Text(exercise.textContent)
                        .font(.body)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        viewModel.selectedExercise = nil
                    }
                }
            }
        }
    }
}

/// Row view for each exercise in the list
struct ExerciseRowView: View {
    let exercise: GeneratedContent
    let onToggleFavorite: () -> Void
    let onRate: (Int) -> Void

    @State private var showRating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title and type
            HStack {
                Image(systemName: exercise.contentType.icon)
                    .foregroundColor(.blue)

                Text(exercise.title)
                    .font(.headline)

                Spacer()

                Button(action: onToggleFavorite) {
                    Image(systemName: exercise.isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(exercise.isFavorite ? .red : .gray)
                }
                .buttonStyle(.plain)
            }

            // Metadata
            HStack {
                if let duration = exercise.duration {
                    Label("\(duration / 60) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let rating = exercise.userRating {
                    Label("\(rating)", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                } else {
                    Button("Rate") {
                        showRating = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }

                Spacer()

                Text(exercise.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog("Rate Exercise", isPresented: $showRating) {
            ForEach(1...5, id: \.self) { rating in
                Button(String(repeating: "⭐", count: rating)) {
                    onRate(rating)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - ViewModel

@MainActor
class SavedExercisesViewModel: ObservableObject {
    @Published var exercises: [GeneratedContent] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var selectedExercise: GeneratedContent?
    @Published var filterType: GeneratedContentType?
    @Published var favoritesOnly = false

    private let dataService: SupabaseDataService

    init(dataService: SupabaseDataService) {
        self.dataService = dataService
    }

    func loadExercises() async {
        isLoading = true
        defer { isLoading = false }

        do {
            exercises = try await dataService.getUserGeneratedContent(
                type: filterType,
                favoritesOnly: favoritesOnly,
                limit: 50
            )
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func toggleFavorite(_ exercise: GeneratedContent) async {
        do {
            try await dataService.toggleFavorite(contentId: exercise.id.uuidString)
            // Reload to get updated favorite status
            await loadExercises()
        } catch {
            errorMessage = "Failed to update favorite: \(error.localizedDescription)"
            showError = true
        }
    }

    func rateExercise(_ exercise: GeneratedContent, rating: Int) async {
        do {
            try await dataService.rateContent(
                contentId: exercise.id.uuidString,
                rating: rating
            )
            // Reload to get updated rating
            await loadExercises()
        } catch {
            errorMessage = "Failed to save rating: \(error.localizedDescription)"
            showError = true
        }
    }
}
