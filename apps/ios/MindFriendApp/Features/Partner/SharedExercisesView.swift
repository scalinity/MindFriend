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
        .foregroundStyle(SupportTheme.textPrimary)
        .supportScreen()
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
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "figure.2.arms.open")
                .font(.system(size: 50))
                .foregroundStyle(SupportTheme.textSecondary)

            Text("No exercises available")
                .font(.headline)
                .foregroundStyle(SupportTheme.textSecondary)

            Text("Check back later for couples exercises you can do together")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
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
                .listRowBackground(SupportTheme.surface)
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
            HStack(spacing: SupportTheme.Spacing.s) {
                // Icon
                Image(systemName: iconForType(exercise.type))
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)

                // Info
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    HStack {
                        Text(exercise.name)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if exercise.requiresPremium {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                    }

                    HStack(spacing: SupportTheme.Spacing.xs) {
                        Label("\(exercise.durationMinutes) min", systemImage: "clock")
                        Label(exercise.difficulty.rawValue.capitalized, systemImage: "chart.bar")
                    }
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .buttonStyle(.supportSecondary)
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
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                    // Header
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        Text(exercise.name)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(exercise.description)
                            .font(.body)
                            .foregroundStyle(SupportTheme.textSecondary)

                        HStack(spacing: SupportTheme.Spacing.m) {
                            Label("\(exercise.durationMinutes) min", systemImage: "clock")
                            Label(exercise.difficulty.rawValue.capitalized, systemImage: "chart.bar")
                            if exercise.requiresBothPartners {
                                Label("Both partners", systemImage: "person.2")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                    }

                    // Instructions
                    if !exercise.instructions.steps.isEmpty {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            Text("Instructions")
                                .font(.headline)

                            ForEach(exercise.instructions.steps.sorted(by: { $0.order < $1.order }), id: \.order) { step in
                                HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                                    Text("\(step.order)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(SupportTheme.textPrimary)
                                        .frame(width: 24, height: 24)
                                        .background(SupportTheme.surface)
                                        .cornerRadius(SupportTheme.controlRadius)

                                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                        Text(step.title)
                                            .font(.subheadline)
                                            .fontWeight(.medium)

                                        Text(step.description)
                                            .font(.caption)
                                            .foregroundStyle(SupportTheme.textSecondary)
                                    }
                                }
                            }
                        }
                    }

                    // Tips
                    if let tips = exercise.instructions.tips {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                            Text("Tips")
                                .font(.headline)

                            Text(tips)
                                .font(.subheadline)
                                .foregroundStyle(SupportTheme.textSecondary)
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
                }
                .buttonStyle(.supportPrimary)
                .padding()
                .background(SupportTheme.surface)
            }
        }
    }
}

// Previews disabled - requires authenticated SupabaseDataService
