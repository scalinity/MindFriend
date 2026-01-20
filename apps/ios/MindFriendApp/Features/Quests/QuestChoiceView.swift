import SwiftUI

/// View that displays quest alternatives and allows users to choose their daily quest
struct QuestChoiceView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    @State private var alternatives: QuestAlternatives?
    @State private var isLoading = true
    @State private var isRerolling = false
    @State private var errorMessage: String?
    @State private var selectedQuest: Quest?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    LoadingView()
                } else if let error = errorMessage {
                    ErrorView(message: error, onRetry: loadAlternatives)
                } else if let alternatives = alternatives {
                    QuestOptionsContent(
                        alternatives: alternatives,
                        isRerolling: isRerolling,
                        onSelectPrimary: { selectVariant(.primary) },
                        onSelectQuick: { selectVariant(.quick) },
                        onSelectAlt: { selectVariant(.alt) },
                        onReroll: rerollQuest
                    )
                }
            }
            .navigationTitle("Today's Quest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(item: $selectedQuest) { quest in
                QuestDetailView(quest: quest)
            }
        }
        .task {
            await loadAlternatives()
        }
    }

    private func loadAlternatives() async {
        isLoading = true
        errorMessage = nil

        do {
            alternatives = try await container.supabaseDataService.getTodayQuestAlternatives()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func selectVariant(_ variant: QuestAlternatives.SelectedVariant) {
        guard let alternatives = alternatives else { return }

        Task {
            do {
                try await container.supabaseDataService.selectQuestVariant(variant, alternativesId: alternatives.id)

                // Create the appropriate Quest object based on selection
                let quest = createQuestFromSelection(alternatives: alternatives, variant: variant)
                if let quest = quest {
                    // Update preference tracking
                    if let category = quest.template.category {
                        try? await container.supabaseDataService.updateQuestPreference(
                            category: category.rawValue,
                            completed: false,
                            rating: nil
                        )
                    }
                    selectedQuest = quest
                }
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }
        }
    }

    private func createQuestFromSelection(alternatives: QuestAlternatives, variant: QuestAlternatives.SelectedVariant) -> Quest? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())

        switch variant {
        case .primary, .reroll:
            guard let template = alternatives.primaryQuest else { return nil }
            return Quest(
                id: alternatives.id.uuidString,
                localDate: today,
                status: .assigned,
                assignedAt: Date(),
                completedAt: nil,
                template: template
            )

        case .quick:
            guard let quickVariant = alternatives.quickVariant,
                  let template = alternatives.primaryQuest else { return nil }
            // Create a modified template for quick variant
            let quickTemplate = QuestTemplate(
                id: quickVariant.id.uuidString,
                type: template.type,
                title: quickVariant.title,
                description: quickVariant.description,
                estimatedMinutes: quickVariant.estimatedMinutes,
                difficulty: "easy",
                tags: template.tags,
                instructions: quickVariant.steps,
                category: template.category
            )
            return Quest(
                id: alternatives.id.uuidString,
                localDate: today,
                status: .assigned,
                assignedAt: Date(),
                completedAt: nil,
                template: quickTemplate,
                isQuickVariant: true,
                xpMultiplier: quickVariant.xpMultiplier
            )

        case .alt:
            guard let template = alternatives.altQuest else { return nil }
            return Quest(
                id: alternatives.id.uuidString,
                localDate: today,
                status: .assigned,
                assignedAt: Date(),
                completedAt: nil,
                template: template
            )
        }
    }

    private func rerollQuest() {
        guard let currentAlternatives = alternatives else { return }
        guard currentAlternatives.canReroll else {
            appState.showError(.apiError("No rerolls remaining today"))
            return
        }

        isRerolling = true

        Task {
            do {
                let newAlternatives = try await container.supabaseDataService.rerollQuest(alternativesId: currentAlternatives.id)
                await MainActor.run {
                    alternatives = newAlternatives
                }
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }
            isRerolling = false
        }
    }
}

// MARK: - Content View

private struct QuestOptionsContent: View {
    let alternatives: QuestAlternatives
    let isRerolling: Bool
    let onSelectPrimary: () -> Void
    let onSelectQuick: () -> Void
    let onSelectAlt: () -> Void
    let onReroll: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text("Choose Your Quest")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Pick the option that fits your day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top)

                // Quest options
                VStack(spacing: 16) {
                    // Primary (Recommended)
                    if let primaryQuest = alternatives.primaryQuest {
                        QuestOptionCard(
                            template: primaryQuest,
                            badge: "Recommended",
                            badgeColor: .green,
                            xpNote: nil,
                            onSelect: onSelectPrimary
                        )
                    }

                    // Quick version
                    if let quickVariant = alternatives.quickVariant,
                       let primaryQuest = alternatives.primaryQuest {
                        QuickVariantCard(
                            variant: quickVariant,
                            parentType: primaryQuest.type,
                            onSelect: onSelectQuick
                        )
                    }

                    // Alternative
                    if let altQuest = alternatives.altQuest {
                        QuestOptionCard(
                            template: altQuest,
                            badge: "Different Focus",
                            badgeColor: .purple,
                            xpNote: nil,
                            onSelect: onSelectAlt
                        )
                    }
                }
                .padding(.horizontal)

                // Reroll section
                RerollButton(
                    alternatives: alternatives,
                    isRerolling: isRerolling,
                    onReroll: onReroll
                )
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer(minLength: 20)
            }
        }
    }
}

// MARK: - Quest Option Card

struct QuestOptionCard: View {
    let template: QuestTemplate
    let badge: String
    let badgeColor: Color
    let xpNote: String?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with badge
                HStack {
                    Image(systemName: template.type.icon)
                        .font(.title2)
                        .foregroundStyle(badgeColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(badge)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(badgeColor)

                        Text(template.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(template.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Metadata
                HStack(spacing: 16) {
                    Label("\(template.estimatedMinutes) min", systemImage: "clock")
                    Label(template.difficulty, systemImage: "speedometer")

                    if let xpNote = xpNote {
                        Text(xpNote)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(badgeColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Variant Card

struct QuickVariantCard: View {
    let variant: QuestQuickVariant
    let parentType: QuestType
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with badge
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quick Version")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)

                        Text(variant.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(variant.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Metadata
                HStack(spacing: 16) {
                    Label("\(variant.estimatedMinutes) min", systemImage: "clock")
                    Label("Easy", systemImage: "speedometer")

                    Text("\(Int(variant.xpMultiplier * 100))% XP")
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reroll Button

struct RerollButton: View {
    let alternatives: QuestAlternatives
    let isRerolling: Bool
    let onReroll: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onReroll) {
                HStack {
                    if isRerolling {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(isRerolling ? "Getting new quest..." : "Try a different quest")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(alternatives.canReroll ? Color.accentColor : Color.secondary)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(20)
            }
            .disabled(!alternatives.canReroll || isRerolling)

            // Reroll count indicator
            if alternatives.isPremiumUnlimited {
                Label("Unlimited rerolls", systemImage: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            } else {
                Text("\(alternatives.rerollsRemaining) reroll\(alternatives.rerollsRemaining == 1 ? "" : "s") remaining")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Loading View

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading quest options...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Error View

private struct ErrorView: View {
    let message: String
    let onRetry: () async -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("Couldn't load quests")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task { await onRetry() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    QuestChoiceView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
