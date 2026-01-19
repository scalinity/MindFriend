import SwiftUI

/// View for family challenges
struct FamilyChallengesView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var challenges: [FamilyChallenge] = []
    @State private var isLoading = false
    @State private var showCreateSheet = false
    let familyGroup: FamilyWellnessGroup

    var activeChallenges: [FamilyChallenge] {
        challenges.filter { $0.status == .active }
    }

    var completedChallenges: [FamilyChallenge] {
        challenges.filter { $0.status == .completed }
    }

    var body: some View {
        ZStack {
            if challenges.isEmpty && !isLoading {
                VStack(spacing: 16) {
                    Image(systemName: "target")
                        .font(.system(size: 40))
                        .foregroundStyle(.gray)
                    Text("No challenges yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(action: { showCreateSheet = true }) {
                        Text("Create First Challenge")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // Active Challenges
                        if !activeChallenges.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Active Challenges")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(activeChallenges, id: \.id) { challenge in
                                    ChallengeDetailCard(challenge: challenge)
                                }
                            }
                        }

                        // Completed Challenges
                        if !completedChallenges.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Completed")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(completedChallenges, id: \.id) { challenge in
                                    ChallengeDetailCard(challenge: challenge)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }

            if isLoading {
                ProgressView()
            }
        }
        .navigationTitle("Challenges")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showCreateSheet = true }) {
                    Image(systemName: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            NavigationStack {
                CreateChallengeSheet(isPresented: $showCreateSheet)
                    .environmentObject(container)
            }
        }
        .task {
            await loadChallenges()
        }
    }

    private func loadChallenges() async {
        isLoading = true
        defer { isLoading = false }

        do {
            challenges = try await container.familyService.fetchChallenges()
        } catch {
            Log.family.error("Failed to load challenges", error: error)
        }
    }
}

// MARK: - Challenge Detail Card

struct ChallengeDetailCard: View {
    let challenge: FamilyChallenge

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if let description = challenge.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(challenge.challengeType.rawValue.capitalized)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }
            }

            // Progress Bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(challenge.currentProgress)/\(challenge.targetValue)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }

                ProgressView(value: challenge.progressPercentage)
                    .tint(.blue)
            }

            // Date Range
            if let endDate = challenge.endDate {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text(endDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.white)
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Create Challenge Sheet

struct CreateChallengeSheet: View {
    @EnvironmentObject private var container: DependencyContainer
    @Binding var isPresented: Bool

    @State private var title = ""
    @State private var description = ""
    @State private var targetValue = ""
    @State private var durationDays = "7"
    @State private var selectedType: FamilyChallengeType = .cumulative
    @State private var isLoading = false

    var body: some View {
        Form {
            Section("Challenge Details") {
                TextField("Title", text: $title)
                TextField("Description (optional)", text: $description, axis: .vertical)
                    .lineLimit(3...)

                Picker("Type", selection: $selectedType) {
                    Text("Streak").tag(FamilyChallengeType.streak)
                    Text("Cumulative").tag(FamilyChallengeType.cumulative)
                    Text("Event").tag(FamilyChallengeType.event)
                    Text("Custom").tag(FamilyChallengeType.custom)
                }
            }

            Section("Target") {
                TextField("Target Value", text: $targetValue)
                    .keyboardType(.numberPad)
                TextField("Duration (days)", text: $durationDays)
                    .keyboardType(.numberPad)
            }

            Section {
                Button(action: createChallenge) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Create Challenge")
                    }
                }
                .disabled(title.isEmpty || targetValue.isEmpty || isLoading)
            }
        }
        .navigationTitle("New Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { isPresented = false }
            }
        }
    }

    private func createChallenge() {
        // TODO: Implement challenge creation
        isPresented = false
    }
}

#Preview {
    NavigationStack {
        FamilyChallengesView(
            familyGroup: .init(
                id: "test",
                name: "Test Family",
                adminUserId: "admin",
                circleId: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        .environmentObject(DependencyContainer.preview)
    }
}
