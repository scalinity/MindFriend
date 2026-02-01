import SwiftUI

struct JournalPromptsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    let onPromptSelected: (JournalPrompt) -> Void

    @State private var prompts: [JournalPrompt] = []
    @State private var selectedCategory: JournalPromptCategory?
    @State private var suggestedPrompts: [JournalPrompt] = []
    @State private var isLoading = true
    @State private var currentMood: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Mood-based suggestions
                    if !suggestedPrompts.isEmpty {
                        suggestedSection
                    }

                    // Category picker
                    categoryPicker

                    // Prompts list
                    promptsList
                }
                .padding()
            }
            .navigationTitle("Writing Prompts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadData()
            }
        }
    }

    // MARK: - Sections

    private var suggestedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("Suggested for You")
                    .font(.headline)
            }

            Text("Based on how you're feeling")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(suggestedPrompts) { prompt in
                PromptCard(
                    prompt: prompt,
                    isHighlighted: true,
                    isPremiumUser: appState.entitlements.tier == .premium
                ) {
                    onPromptSelected(prompt)
                    dismiss()
                }
            }
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by Category")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryChip(
                        title: "All",
                        icon: "tray.full",
                        isSelected: selectedCategory == nil
                    ) {
                        selectedCategory = nil
                    }

                    ForEach(JournalPromptCategory.allCases) { category in
                        CategoryChip(
                            title: category.displayName,
                            icon: category.icon,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
            }
        }
    }

    private var promptsList: some View {
        LazyVStack(spacing: 12) {
            let filtered = selectedCategory == nil
                ? prompts
                : prompts.filter { $0.category == selectedCategory }

            if filtered.isEmpty {
                ContentUnavailableView {
                    Label("No Prompts", systemImage: "doc.text")
                } description: {
                    Text("No prompts available in this category")
                }
            } else {
                ForEach(filtered) { prompt in
                    PromptCard(
                        prompt: prompt,
                        isHighlighted: false,
                        isPremiumUser: appState.entitlements.tier == .premium
                    ) {
                        onPromptSelected(prompt)
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true

        let service = JournalService(supabase: container.supabase)

        // Get current mood from recent mood entry if available
        if let recentMood = appState.todayMood?.moodScore {
            currentMood = recentMood
            suggestedPrompts = (try? await service.fetchPromptsForMood(recentMood, limit: 3)) ?? []
        }

        // Load all prompts
        prompts = (try? await service.fetchPrompts()) ?? []

        isLoading = false
    }
}

// MARK: - Supporting Views

private struct CategoryChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(.systemGray6))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct PromptCard: View {
    let prompt: JournalPrompt
    let isHighlighted: Bool
    var isPremiumUser: Bool = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: prompt.category.icon)
                        .foregroundStyle(isHighlighted ? .purple : .accentColor)
                    Text(prompt.category.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if prompt.isPremium && !isPremiumUser {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }

                Text(prompt.promptText)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

                HStack {
                    if let moods = prompt.moodAffinity, !moods.isEmpty {
                        Text("Good for: \(moodLabels(moods))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(isHighlighted ? Color.purple.opacity(0.1) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func moodLabels(_ moods: [Int]) -> String {
        let labels = ["Struggling", "Low", "Okay", "Good", "Great"]
        return moods.compactMap { mood in
            guard mood >= 1 && mood <= 5 else { return nil }
            return labels[mood - 1]
        }.joined(separator: ", ")
    }
}

#Preview {
    JournalPromptsView { prompt in
        print("Selected: \(prompt.promptText)")
    }
    .environmentObject(AppState())
    .environmentObject(DependencyContainer.preview)
}
