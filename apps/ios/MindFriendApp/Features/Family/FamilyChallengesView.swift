import SwiftUI

/// View for family challenges
struct FamilyChallengesView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var challenges: [FamilyChallenge] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showCreateSheet = false
    let familyGroup: FamilyWellnessGroup

    var activeChallenges: [FamilyChallenge] {
        challenges.filter { $0.status == .active && $0.challengeType != .streak }
    }

    var completedChallenges: [FamilyChallenge] {
        challenges.filter { $0.status == .completed && $0.challengeType != .streak }
    }

    var body: some View {
        ZStack {
            if challenges.isEmpty && !isLoading {
                VStack(spacing: SupportTheme.Spacing.m) {
                    Image(systemName: "target")
                        .font(.system(size: 40))
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text("No challenges yet")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                    Button(action: { showCreateSheet = true }) {
                        Text("Create First Challenge")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportSecondary)
                    .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SupportTheme.surface)
            } else {
                ScrollView {
                    VStack(spacing: SupportTheme.Spacing.l) {
                        // Active Challenges
                        if !activeChallenges.isEmpty {
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                                Text("Active Challenges")
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)
                                    .padding(.horizontal)

                                ForEach(activeChallenges, id: \.id) { challenge in
                                    ChallengeDetailCard(challenge: challenge)
                                }
                            }
                        }

                        // Completed Challenges
                        if !completedChallenges.isEmpty {
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
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
        .safeAreaInset(edge: .bottom) {
            if let loadError {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Label("Challenges unavailable", systemImage: "exclamationmark.triangle")
                        .font(.headline).accessibilityAddTraits(.isHeader)
                    Text(loadError)
                    Button("Try Again") { Task { await loadChallenges() } }
                        .buttonStyle(.supportSecondary)
                }
                .supportCard()
                .padding(SupportTheme.Spacing.m)
            }
        }
        .foregroundStyle(SupportTheme.textPrimary)
        .supportScreen()
        .navigationTitle("Challenges")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showCreateSheet = true }) {
                    Image(systemName: "plus.circle")
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                }
                .accessibilityLabel("Create challenge")
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
        loadError = nil
        defer { isLoading = false }

        do {
            challenges = try await container.familyService.fetchChallenges()
        } catch {
            loadError = error.localizedDescription
            Log.family.error("Failed to load challenges", error: error)
        }
    }
}

// MARK: - Challenge Detail Card

struct ChallengeDetailCard: View {
    let challenge: FamilyChallenge

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(challenge.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if let description = challenge.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xxs) {
                    Text(challenge.challengeType.rawValue.capitalized)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(SupportTheme.accent)
                }
            }

            // Progress Bar
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                HStack {
                    Text("Progress")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                    Spacer()
                    Text("\(challenge.currentProgress)/\(challenge.targetValue)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }

                ProgressView(value: challenge.progressPercentage)
                    .tint(SupportTheme.accent)
            }

            // Date Range
            if let endDate = challenge.endDate {
                HStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "calendar")
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text(endDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
        }
        .supportCard()
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
                    .supportField()
                    .lineLimit(3...)

                Picker("Type", selection: $selectedType) {
                    Text("Cumulative").tag(FamilyChallengeType.cumulative)
                    Text("Event").tag(FamilyChallengeType.event)
                    Text("Custom").tag(FamilyChallengeType.custom)
                }
            }
            .listRowBackground(SupportTheme.surface)

            Section("Target") {
                TextField("Target Value", text: $targetValue)
                    .keyboardType(.numberPad)
                TextField("Duration (days)", text: $durationDays)
                    .supportField()
                    .keyboardType(.numberPad)
            }
            .listRowBackground(SupportTheme.surface)

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
            .listRowBackground(SupportTheme.surface)
        }
        .foregroundStyle(SupportTheme.textPrimary)
        .supportScreen()
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
