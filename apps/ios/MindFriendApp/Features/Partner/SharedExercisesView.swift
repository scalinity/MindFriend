import SwiftUI

/// View showing couples exercises available to do together
struct SharedExercisesView: View {
    @ObservedObject var viewModel: PartnerModeViewModel
    @State private var selectedExercise: CouplesExercise?
    @State private var showExerciseDetail = false

    var body: some View {
        Group {
            if viewModel.couplesExercises.isEmpty {
                emptyStateView
            } else {
                exerciseListView
            }
        }
        .navigationTitle("Couples Exercises")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            Task {
                await viewModel.loadCouplesExercises()
            }
        }
        .sheet(item: $selectedExercise) { exercise in
            ExerciseDetailSheet(
                exercise: exercise,
                onStart: {
                    Task {
                        do {
                            _ = try await viewModel.startExerciseSession(exercise.id)
                            selectedExercise = nil
                        } catch {
                            // Error handled by viewModel
                        }
                    }
                }
            )
            .presentationDetents([.large])
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.2.arms.open")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text("No exercises available")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Check back later for couples exercises you can do together")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Exercise List

    private var exerciseListView: some View {
        List {
            ForEach(groupedExercises.keys.sorted(), id: \.self) { category in
                Section(header: Text(category.replacingOccurrences(of: "-", with: " ").capitalized)) {
                    ForEach(groupedExercises[category] ?? []) { exercise in
                        ExerciseRow(exercise: exercise) {
                            selectedExercise = exercise
                        }
                    }
                }
            }
        }
    }

    private var groupedExercises: [String: [CouplesExercise]] {
        Dictionary(grouping: viewModel.couplesExercises) { $0.type.rawValue }
    }
}

// MARK: - Exercise Row

private struct ExerciseRow: View {
    let exercise: CouplesExercise
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: iconForType(exercise.type))
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(10)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(exercise.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        if exercise.requiresPremium {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        Label("\(exercise.durationMinutes) min", systemImage: "clock")
                        Label(exercise.difficulty.rawValue.capitalized, systemImage: "chart.bar")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func iconForType(_ type: CouplesExerciseType) -> String {
        switch type {
        case .communication: return "bubble.left.and.bubble.right"
        case .intimacy: return "heart.fill"
        case .goalSetting: return "target"
        case .mindfulness: return "brain.head.profile"
        }
    }
}

// MARK: - Exercise Detail Sheet

private struct ExerciseDetailSheet: View {
    let exercise: CouplesExercise
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(exercise.name)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(exercise.description)
                            .font(.body)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            Label("\(exercise.durationMinutes) min", systemImage: "clock")
                            Label(exercise.difficulty.rawValue.capitalized, systemImage: "chart.bar")
                            if exercise.requiresBothPartners {
                                Label("Both partners", systemImage: "person.2")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    // Instructions
                    if !exercise.instructions.steps.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Instructions")
                                .font(.headline)

                            ForEach(exercise.instructions.steps.sorted(by: { $0.order < $1.order }), id: \.order) { step in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(step.order)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                        .frame(width: 24, height: 24)
                                        .background(Color.accentColor)
                                        .cornerRadius(12)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(step.title)
                                            .font(.subheadline)
                                            .fontWeight(.medium)

                                        Text(step.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    // Tips
                    if let tips = exercise.instructions.tips {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tips")
                                .font(.headline)

                            Text(tips)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 80)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onStart) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Together")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
    }
}

// Previews disabled - requires authenticated SupabaseDataService
