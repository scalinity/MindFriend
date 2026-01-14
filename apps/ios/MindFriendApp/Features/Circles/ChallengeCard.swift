import SwiftUI

/// Displays an active circle challenge with member completion status
struct ChallengeCard: View {
    let challenge: CircleChallenge
    let members: [CircleMember]
    let currentUserId: String

    @EnvironmentObject private var container: DependencyContainer
    @State private var isCompleting = false
    @State private var localCompletions: Set<String>

    init(challenge: CircleChallenge, members: [CircleMember], currentUserId: String) {
        self.challenge = challenge
        self.members = members
        self.currentUserId = currentUserId
        // Initialize with existing completions
        let completedIds = Set(challenge.completions?.map { $0.userId } ?? [])
        _localCompletions = State(initialValue: completedIds)
    }

    var hasCurrentUserCompleted: Bool {
        localCompletions.contains(currentUserId)
    }

    // Fix 7: Sync local state when challenge completions change from parent
    private func syncCompletions() {
        let newCompletedIds = Set(challenge.completions?.map { $0.userId } ?? [])
        if newCompletedIds != localCompletions {
            localCompletions = newCompletedIds
        }
    }

    var completionProgress: String {
        "\(localCompletions.count)/\(members.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.fill")
                            .foregroundColor(.orange)
                        Text("TODAY'S CHALLENGE")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }

                    Text(challenge.title)
                        .font(.headline)
                }

                Spacer()

                Text(challenge.timeRemaining)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }

            if let description = challenge.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Member completion status
            HStack(spacing: -8) {
                ForEach(members.prefix(6)) { member in
                    MemberCompletionBadge(
                        member: member,
                        isCompleted: localCompletions.contains(member.userId)
                    )
                }

                if members.count > 6 {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .overlay {
                            Text("+\(members.count - 6)")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                }

                Spacer()

                Text(completionProgress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Action button
            if !hasCurrentUserCompleted {
                Button {
                    completeChallenge()
                } label: {
                    HStack {
                        if isCompleting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.circle")
                        }
                        Text("Mark Complete")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isCompleting)
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Completed!")
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
        // Fix 7: Sync state when completions change from parent
        .onChange(of: challenge.completions) { _, _ in
            syncCompletions()
        }
    }

    private func completeChallenge() {
        guard !isCompleting else { return }

        isCompleting = true

        Task {
            do {
                try await container.supabaseDataService.completeChallenge(id: challenge.id)
                await MainActor.run {
                    withAnimation {
                        localCompletions.insert(currentUserId)
                    }
                    isCompleting = false
                }
            } catch {
                await MainActor.run {
                    isCompleting = false
                }
            }
        }
    }
}

/// Small badge showing member completion status
private struct MemberCompletionBadge: View {
    let member: CircleMember
    let isCompleted: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isCompleted ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 32, height: 32)

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundColor(.white)
            } else {
                Text(String(member.displayName.prefix(1)).uppercased())
                    .font(.caption.bold())
                    .foregroundColor(.primary)
            }
        }
        .overlay {
            Circle()
                .stroke(Color(.systemBackground), lineWidth: 2)
        }
    }
}

/// Sheet for creating a new challenge (owner only)
struct CreateChallengeSheet: View {
    let circleId: String
    let onCreated: (CircleChallenge) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: DependencyContainer

    @State private var title = ""
    @State private var description = ""
    @State private var challengeType: ChallengeType = .custom
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Challenge title", text: $title)
                        .autocapitalization(.sentences)

                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("What's the challenge?")
                }

                Section {
                    Picker("Type", selection: $challengeType) {
                        Text("Custom").tag(ChallengeType.custom)
                        Text("Do an exercise").tag(ChallengeType.exercise)
                        Text("Log your mood").tag(ChallengeType.moodCheckin)
                        Text("Complete today's quest").tag(ChallengeType.quest)
                    }
                } header: {
                    Text("Challenge type")
                } footer: {
                    Text("Challenges last 24 hours. Members can mark themselves complete.")
                }
            }
            .navigationTitle("New Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createChallenge()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
            .alert("Couldn't Create Challenge", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func createChallenge() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        isCreating = true

        Task {
            do {
                let challenge = try await container.supabaseDataService.createChallenge(
                    in: circleId,
                    type: challengeType,
                    title: trimmedTitle,
                    description: description.isEmpty ? nil : description
                )

                await MainActor.run {
                    onCreated(challenge)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

#Preview {
    VStack {
        ChallengeCard(
            challenge: CircleChallenge(
                id: "1",
                circleId: "c1",
                createdBy: "u1",
                challengeType: .custom,
                title: "Do a breathing exercise today",
                description: "Take 5 minutes to practice deep breathing",
                targetExerciseId: nil,
                startsAt: Date(),
                endsAt: Date().addingTimeInterval(86400),
                createdAt: Date(),
                completions: [
                    ChallengeCompletion(id: "comp1", challengeId: "1", userId: "u2", completedAt: Date(), userName: nil)
                ],
                creatorName: "Danny"
            ),
            members: [
                CircleMember(id: "1", userId: "u1", displayName: "Danny", role: .owner, joinedAt: Date(), premiumBadge: "premium_supporter"),
                CircleMember(id: "2", userId: "u2", displayName: "Sarah", role: .member, joinedAt: Date(), premiumBadge: nil),
                CircleMember(id: "3", userId: "u3", displayName: "Mike", role: .member, joinedAt: Date(), premiumBadge: nil),
            ],
            currentUserId: "u1"
        )
        .padding()
    }
    .environmentObject(DependencyContainer())
}
