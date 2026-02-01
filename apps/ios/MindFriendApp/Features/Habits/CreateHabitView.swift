import SwiftUI

// MARK: - Create Habit View

/// View for creating a new custom habit
struct CreateHabitView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var anchor = ""
    @State private var behavior = ""
    @State private var selectedCategory: HabitCategory = .custom
    @State private var selectedDifficulty: HabitDifficulty = .easy
    @State private var enableReminder = false
    @State private var reminderTime = Date()
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !anchor.trimmingCharacters(in: .whitespaces).isEmpty &&
        !behavior.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var habitStatement: String {
        let anchorText = anchor.isEmpty ? "[anchor]" : anchor
        let behaviorText = behavior.isEmpty ? "[behavior]" : behavior
        return "After I \(anchorText), I will \(behaviorText)"
    }

    var body: some View {
        Form {
            // Habit statement preview
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Habit Statement")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(habitStatement)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 8)
            }

            // Basic info
            Section("Habit Details") {
                TextField("Habit Name", text: $name)
                    .textContentType(.none)

                TextField("After I... (e.g., wake up, eat lunch)", text: $anchor)
                    .textContentType(.none)

                TextField("I will... (e.g., meditate for 5 minutes)", text: $behavior)
                    .textContentType(.none)
            }

            // Category
            Section("Category") {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(HabitCategory.allCases, id: \.self) { category in
                        HStack {
                            Text(categoryEmoji(for: category))
                            Text(category.displayName)
                        }
                        .tag(category)
                    }
                }
                .pickerStyle(.menu)
            }

            // Difficulty
            Section {
                Picker("Difficulty", selection: $selectedDifficulty) {
                    ForEach(HabitDifficulty.allCases, id: \.self) { difficulty in
                        Text(difficulty.displayName).tag(difficulty)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Duration")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatDuration(selectedDifficulty.defaultDuration))
                        .foregroundStyle(.primary)
                }
            } header: {
                Text("Difficulty")
            } footer: {
                Text("Start easy and build up. After a 7-day streak, you can graduate to the next level.")
            }

            // Reminder
            Section {
                Toggle("Daily Reminder", isOn: $enableReminder)

                if enableReminder {
                    DatePicker(
                        "Reminder Time",
                        selection: $reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Get a gentle nudge to help you stay on track.")
            }
        }
        .navigationTitle("Create Habit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await saveHabit() }
                }
                .disabled(!isFormValid || isSaving)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func categoryEmoji(for category: HabitCategory) -> String {
        switch category {
        case .breathing: return "🫁"
        case .meditation: return "🧘"
        case .journaling: return "📝"
        case .movement: return "🏃"
        case .custom: return "✨"
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes == 1 {
            return "1 minute"
        }
        return "\(minutes) minutes"
    }

    private func saveHabit() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await container.habitService.createHabit(
                name: name.trimmingCharacters(in: .whitespaces),
                anchor: anchor.trimmingCharacters(in: .whitespaces),
                behavior: behavior.trimmingCharacters(in: .whitespaces),
                category: selectedCategory,
                difficulty: selectedDifficulty,
                reminderTime: enableReminder ? reminderTime : nil
            )

            // Schedule notification if reminder is enabled
            if enableReminder {
                let habits = container.habitService.habits
                if let newHabit = habits.first(where: { $0.name == name }) {
                    try? await container.habitNotificationService.scheduleHabitReminder(
                        habit: newHabit,
                        anchorTime: reminderTime
                    )
                }
            }

            await MainActor.run {
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        CreateHabitView()
            .environmentObject(DependencyContainer())
    }
}
