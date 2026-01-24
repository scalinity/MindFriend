import SwiftUI

/// Wind-down routine view for guided bedtime preparation
struct WindDownRoutineView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: DependencyContainer
    @StateObject private var viewModel = WindDownRoutineViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if let session = viewModel.session {
                    routineView(session)
                } else {
                    setupView
                }
            }
            .navigationTitle("Wind-Down Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadGoals(trackingService: dependencies.sleepTrackingService)
            }
        }
    }

    // MARK: - Loading

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Creating your routine...")
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Setup

    @ViewBuilder
    private var setupView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.purple)

                Text("Prepare for Better Sleep")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("A personalized wind-down routine helps you relax and prepare for restful sleep")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Duration Picker
                VStack(spacing: 12) {
                    Text("How much time do you have?")
                        .font(.headline)

                    Picker("Duration", selection: $viewModel.durationMinutes) {
                        Text("15 min").tag(15)
                        Text("20 min").tag(20)
                        Text("30 min").tag(30)
                        Text("45 min").tag(45)
                        Text("60 min").tag(60)
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Start Button
                Button {
                    Task {
                        await viewModel.generateRoutine(trackingService: dependencies.sleepTrackingService)
                    }
                } label: {
                    Text("Start Wind-Down")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }
            }
            .padding()
        }
    }

    // MARK: - Routine

    @ViewBuilder
    private func routineView(_ session: WindDownSession) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Progress
                progressSection(session)

                // Current/Next Activity
                if let current = viewModel.currentActivity {
                    currentActivitySection(current)
                } else if session.completed {
                    completedSection
                }

                // All Activities
                activitiesListSection(session)

                // Complete Button
                if session.completed && viewModel.feedbackRating == 0 {
                    feedbackSection
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func progressSection(_ session: WindDownSession) -> some View {
        VStack(spacing: 12) {
            Text("\(session.routine.filter { $0.completed }.count)/\(session.routine.count) Activities")
                .font(.headline)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 8)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * session.progress, height: 8)
                        .cornerRadius(4)
                        .animation(.spring(), value: session.progress)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func currentActivitySection(_ activity: WindDownActivity) -> some View {
        VStack(spacing: 16) {
            Image(systemName: activity.icon)
                .font(.system(size: 50))
                .foregroundColor(.accentColor)

            Text(activity.name)
                .font(.title2)
                .fontWeight(.semibold)

            Text("\(activity.durationMinutes) minutes")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button {
                viewModel.completeActivity(activity, trackingService: dependencies.sleepTrackingService)
            } label: {
                Text("Complete")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var completedSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("Routine Complete!")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Great job preparing for sleep. Sweet dreams!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func activitiesListSection(_ session: WindDownSession) -> some View {
        VStack(spacing: 12) {
            Text("Activities")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(session.routine) { activity in
                activityRow(activity)
            }
        }
    }

    @ViewBuilder
    private func activityRow(_ activity: WindDownActivity) -> some View {
        HStack(spacing: 12) {
            Image(systemName: activity.completed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(activity.completed ? .green : .gray)

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(activity.durationMinutes) min • \(activity.type.capitalized)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: activity.icon)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var feedbackSection: some View {
        VStack(spacing: 16) {
            Text("How was the routine?")
                .font(.headline)

            HStack(spacing: 16) {
                ForEach(1...5, id: \.self) { rating in
                    Button {
                        viewModel.feedbackRating = rating
                        Task {
                            await viewModel.submitFeedback(trackingService: dependencies.sleepTrackingService)
                        }
                    } label: {
                        Image(systemName: rating <= viewModel.feedbackRating ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundColor(rating <= viewModel.feedbackRating ? .yellow : .gray)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - View Model

@MainActor
final class WindDownRoutineViewModel: ObservableObject {
    @Published var session: WindDownSession?
    @Published var goals: SleepGoals?
    @Published var durationMinutes: Int = 30
    @Published var isLoading = false
    @Published var feedbackRating: Int = 0

    var currentActivity: WindDownActivity? {
        session?.routine.first { !$0.completed }
    }

    func loadGoals(trackingService: SleepTrackingService) async {
        do {
            goals = try await trackingService.fetchGoals()
            durationMinutes = goals?.windDownDurationMinutes ?? 30
        } catch {
            print("Failed to load goals: \(error)")
        }
    }

    func generateRoutine(trackingService: SleepTrackingService) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let targetBedtime = goals?.targetBedtime ?? Date()
            let preferences = goals?.preferredWindDownTypes ?? ["breathing", "meditation"]

            session = try await trackingService.generateWindDown(
                targetBedtime: targetBedtime,
                availableMinutes: durationMinutes,
                preferences: preferences
            )
        } catch {
            print("Failed to generate routine: \(error)")
        }
    }

    func completeActivity(_ activity: WindDownActivity, trackingService: SleepTrackingService) {
        guard let session = session else { return }

        Task {
            do {
                try await trackingService.completeWindDownActivity(
                    sessionId: session.id,
                    activityId: activity.id
                )

                // Update local state
                if let index = self.session?.routine.firstIndex(where: { $0.id == activity.id }) {
                    self.session?.routine[index].completed = true
                }

                // Check if all completed
                if self.session?.routine.allSatisfy({ $0.completed }) == true {
                    self.session?.completed = true
                }
            } catch {
                print("Failed to complete activity: \(error)")
            }
        }
    }

    func submitFeedback(trackingService: SleepTrackingService) async {
        guard let session = session, feedbackRating > 0 else { return }

        do {
            try await trackingService.rateWindDownSession(
                sessionId: session.id,
                rating: feedbackRating
            )
        } catch {
            print("Failed to submit feedback: \(error)")
        }
    }
}

#Preview {
    WindDownRoutineView()
        .environmentObject(DependencyContainer.preview)
}
