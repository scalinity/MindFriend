import SwiftUI

struct QuestDetailView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    let quest: Quest
    @State private var currentStep = 0
    @State private var isCompleting = false
    @State private var showReflection = false
    @State private var reflectionNote = ""
    @State private var rating: Int = 0
    @State private var completionResult: QuestCompletion?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // Quest header
                    QuestHeader(quest: quest)

                    if quest.status == .completed {
                        CompletedBanner()
                    } else {
                        // Instructions
                        QuestInstructions(
                            instructions: quest.template.instructions,
                            currentStep: $currentStep
                        )
                    }
                }
                .padding()
            }

            // Bottom action
            if quest.status != .completed {
                VStack(spacing: 12) {
                    Button {
                        showReflection = true
                    } label: {
                        Text("Complete Quest")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }

                    Button {
                        skipQuest()
                    } label: {
                        Text("Skip for today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
            }
        }
        .navigationTitle(quest.template.type.rawValue.capitalized)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showReflection) {
            QuestReflectionSheet(
                quest: quest,
                reflectionNote: $reflectionNote,
                rating: $rating,
                onComplete: completeQuest
            )
        }
        .sheet(item: $completionResult) { result in
            QuestCompletionCelebration(result: result, onDismiss: { dismiss() })
        }
    }

    private func completeQuest() {
        isCompleting = true

        Task {
            do {
                let result = try await container.questService.completeQuest(
                    id: quest.id,
                    reflectionNote: reflectionNote.isEmpty ? nil : reflectionNote,
                    rating: rating > 0 ? rating : nil
                )

                await MainActor.run {
                    appState.currentStreak = result.streakDays
                    showReflection = false
                    completionResult = result
                }
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }
            isCompleting = false
        }
    }

    private func skipQuest() {
        Task {
            do {
                try await container.questService.skipQuest(id: quest.id)
                await MainActor.run {
                    appState.currentStreak = 0
                    dismiss()
                }
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }
        }
    }
}

struct QuestHeader: View {
    let quest: Quest

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: quest.template.type.icon)
                .font(.system(size: 50))
                .foregroundStyle(Color.accentColor)

            Text(quest.template.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(quest.template.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Label("\(quest.template.estimatedMinutes) min", systemImage: "clock")
                Label(quest.template.difficulty, systemImage: "speedometer")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct QuestInstructions: View {
    let instructions: [QuestInstruction]
    @Binding var currentStep: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Instructions")
                .font(.headline)

            ForEach(instructions.indices, id: \.self) { index in
                InstructionRow(
                    instruction: instructions[index],
                    isActive: index == currentStep,
                    isCompleted: index < currentStep,
                    onTap: { currentStep = index }
                )
            }
        }
    }
}

struct InstructionRow: View {
    let instruction: QuestInstruction
    let isActive: Bool
    let isCompleted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isCompleted ? Color.green : (isActive ? Color.accentColor : Color.secondary.opacity(0.3)))
                        .frame(width: 32, height: 32)

                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    } else {
                        Text("\(instruction.step)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(isActive ? .white : .secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(instruction.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    if let duration = instruction.durationSeconds {
                        Text("\(duration / 60) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .background(isActive ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct CompletedBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Quest completed!")
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
}

struct QuestReflectionSheet: View {
    let quest: Quest
    @Binding var reflectionNote: String
    @Binding var rating: Int
    let onComplete: () -> Void

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Great job completing your quest!")
                        .font(.title2)
                        .fontWeight(.semibold)

                    // Rating
                    VStack(spacing: 12) {
                        Text("How was this quest?")
                            .font(.headline)

                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    rating = star
                                } label: {
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .font(.title)
                                        .foregroundStyle(star <= rating ? .yellow : .secondary)
                                }
                            }
                        }
                    }

                    // Reflection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reflection (optional)")
                            .font(.headline)

                        TextField("How do you feel after completing this?", text: $reflectionNote, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                    }

                    Button(action: onComplete) {
                        Text("Save & Complete")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct QuestCompletionCelebration: View {
    let result: QuestCompletion
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "party.popper.fill")
                .font(.system(size: 80))
                .foregroundStyle(.yellow)

            Text("Quest Complete!")
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(result.streakDays) day streak!")
                        .font(.title2)
                }

                if !result.badgesEarned.isEmpty {
                    Text("New badges earned:")
                        .font(.headline)
                        .padding(.top)

                    ForEach(result.badgesEarned) { badge in
                        HStack {
                            Image(systemName: badge.icon)
                                .foregroundStyle(.yellow)
                            Text(badge.title)
                        }
                    }
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding()
        }
    }
}

extension QuestCompletion: Identifiable {
    var id: String { questId }
}

#Preview {
    NavigationStack {
        QuestDetailView(quest: Quest(
            id: "1",
            localDate: "2024-01-15",
            status: .assigned,
            assignedAt: Date(),
            template: QuestTemplate(
                id: "t1",
                type: .breathing,
                title: "4-7-8 Breathing",
                description: "A calming breathing technique to reduce stress",
                estimatedMinutes: 5,
                difficulty: "easy",
                tags: ["calming", "stress-relief"],
                instructions: [
                    QuestInstruction(step: 1, text: "Find a comfortable seated position", durationSeconds: nil),
                    QuestInstruction(step: 2, text: "Breathe in through your nose for 4 seconds", durationSeconds: 4),
                    QuestInstruction(step: 3, text: "Hold your breath for 7 seconds", durationSeconds: 7),
                    QuestInstruction(step: 4, text: "Exhale slowly through your mouth for 8 seconds", durationSeconds: 8),
                    QuestInstruction(step: 5, text: "Repeat 4 times", durationSeconds: nil)
                ]
            )
        ))
    }
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
