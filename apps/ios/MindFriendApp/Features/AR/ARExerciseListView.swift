import SwiftUI

/// Main list view for AR grounding exercises
public struct ARExerciseListView: View {

    // MARK: - Environment

    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var exerciseService: ARExerciseService
    @EnvironmentObject private var capabilityService: ARCapabilityService

    // MARK: - State

    @State private var exercises: [ARExercise] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var selectedExercise: ARExercise?
    @State private var showExercise: Bool = false
    @State private var showFallback: Bool = false
    @State private var showCapabilityInfo: Bool = false

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(message: error)
                } else if exercises.isEmpty {
                    emptyView
                } else {
                    exerciseList
                }
            }
            .navigationTitle("AR Grounding")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCapabilityInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .task {
                await loadExercises()
            }
            .refreshable {
                await loadExercises()
            }
            .sheet(isPresented: $showCapabilityInfo) {
                capabilityInfoSheet
            }
            .fullScreenCover(isPresented: $showExercise) {
                if let exercise = selectedExercise {
                    exerciseView(for: exercise)
                }
            }
            .fullScreenCover(isPresented: $showFallback) {
                if let exercise = selectedExercise {
                    fallbackView(for: exercise)
                }
            }
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Loading exercises...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Unable to Load")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task {
                    await loadExercises()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arkit")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Exercises Available")
                .font(.title2)
                .fontWeight(.semibold)

            Text("AR grounding exercises will appear here when available.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var exerciseList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Device capability banner
                if !capabilityService.capabilities.arkit {
                    capabilityWarningBanner
                }

                // Exercise cards
                ForEach(exercises) { exercise in
                    exerciseCard(exercise)
                }
            }
            .padding()
        }
    }

    private var capabilityWarningBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arkit")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("AR Not Available")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("Using non-AR fallback mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.orange.opacity(0.1))
        .cornerRadius(12)
    }

    private func exerciseCard(_ exercise: ARExercise) -> some View {
        Button {
            selectExercise(exercise)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    // Type icon
                    exerciseTypeIcon(exercise.arType)
                        .font(.title)
                        .foregroundStyle(exerciseTypeColor(exercise.arType))
                        .frame(width: 50, height: 50)
                        .background(exerciseTypeColor(exercise.arType).opacity(0.1))
                        .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(exercise.exerciseName)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            if exercise.isPremium {
                                premiumBadge
                            }
                        }

                        Text(exercise.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Capability badges
                HStack(spacing: 8) {
                    durationBadge(exercise.durationSeconds)
                    capabilityBadge(for: exercise)
                }
            }
            .padding()
            .background(.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8)
        }
        .buttonStyle(.plain)
    }

    private func exerciseTypeIcon(_ type: ARExerciseTypeEnum) -> some View {
        let iconName: String
        switch type {
        case .breathingOrb:
            iconName = "circle.hexagongrid.fill"
        case .grounding541:
            iconName = "hand.point.up.left.fill"
        case .safeSpace:
            iconName = "house.fill"
        case .natureImmersion:
            iconName = "leaf.fill"
        }
        return Image(systemName: iconName)
    }

    private func exerciseTypeColor(_ type: ARExerciseTypeEnum) -> Color {
        switch type {
        case .breathingOrb:
            return .indigo
        case .grounding541:
            return .blue
        case .safeSpace:
            return .purple
        case .natureImmersion:
            return .green
        }
    }

    private var premiumBadge: some View {
        Text("PRO")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange)
            .cornerRadius(4)
    }

    private func durationBadge(_ seconds: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.caption2)
            Text("\(seconds / 60) min")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.gray.opacity(0.1))
        .cornerRadius(8)
    }

    private func capabilityBadge(for exercise: ARExercise) -> some View {
        let result = capabilityService.canRun(exercise: exercise)
        let useFallback = capabilityService.shouldUseFallback(for: exercise)

        return HStack(spacing: 4) {
            Image(systemName: result.canRun ? "arkit" : "rectangle.on.rectangle")
                .font(.caption2)
            Text(useFallback ? "Non-AR" : "AR Ready")
                .font(.caption)
        }
        .foregroundStyle(result.canRun ? .green : .orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((result.canRun ? Color.green : Color.orange).opacity(0.1))
        .cornerRadius(8)
    }

    private var capabilityInfoSheet: some View {
        NavigationStack {
            List {
                Section("Device Capabilities") {
                    capabilityRow(
                        "ARKit",
                        available: capabilityService.capabilities.arkit,
                        icon: "arkit"
                    )
                    capabilityRow(
                        "TrueDepth Camera",
                        available: capabilityService.capabilities.trueDepth,
                        icon: "faceid"
                    )
                    capabilityRow(
                        "LiDAR Scanner",
                        available: capabilityService.capabilities.lidar,
                        icon: "light.max"
                    )
                }

                Section("What This Means") {
                    if capabilityService.capabilities.arkit {
                        Text("Your device supports full AR experiences with real-world tracking.")
                            .font(.subheadline)
                    } else {
                        Text("Your device will use non-AR fallback modes for grounding exercises. The experience is still effective, just without AR visuals.")
                            .font(.subheadline)
                    }

                    if capabilityService.capabilities.lidar {
                        Text("LiDAR enables enhanced depth sensing for more accurate object placement.")
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("AR Capabilities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showCapabilityInfo = false
                    }
                }
            }
        }
    }

    private func capabilityRow(_ name: String, available: Bool, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(available ? .green : .secondary)
                .frame(width: 30)

            Text(name)

            Spacer()

            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? .green : .red)
        }
    }

    // MARK: - Exercise Views

    @ViewBuilder
    private func exerciseView(for exercise: ARExercise) -> some View {
        switch exercise.arType {
        case .breathingOrb:
            BreathingOrbARView(exercise: exercise)
                .environmentObject(exerciseService)

        case .grounding541:
            Grounding541ARView(exercise: exercise)
                .environmentObject(exerciseService)

        case .safeSpace:
            SafeSpaceARView(exercise: exercise)
                .environmentObject(exerciseService)

        case .natureImmersion:
            // Nature immersion uses same safe space view with different config
            SafeSpaceARView(exercise: exercise)
                .environmentObject(exerciseService)
        }
    }

    @ViewBuilder
    private func fallbackView(for exercise: ARExercise) -> some View {
        switch exercise.arType {
        case .breathingOrb:
            BreathingOrbFallbackView(exercise: exercise)
                .environmentObject(exerciseService)

        case .grounding541:
            Grounding541FallbackView(exercise: exercise)
                .environmentObject(exerciseService)

        case .safeSpace, .natureImmersion:
            // Safe space and nature immersion don't have fallbacks, use grounding as default
            Grounding541FallbackView(exercise: exercise)
                .environmentObject(exerciseService)
        }
    }

    // MARK: - Actions

    private func loadExercises() async {
        isLoading = true
        errorMessage = nil

        do {
            exercises = try await exerciseService.fetchARExercises()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func selectExercise(_ exercise: ARExercise) {
        selectedExercise = exercise

        if capabilityService.shouldUseFallback(for: exercise) {
            showFallback = true
        } else {
            showExercise = true
        }
    }
}

// MARK: - Preview

#Preview {
    // Preview uses container which provides all services
    let container = DependencyContainer.shared
    return ARExerciseListView()
        .environmentObject(container)
        .environmentObject(container.arExerciseService)
        .environmentObject(container.arCapabilityService)
}
