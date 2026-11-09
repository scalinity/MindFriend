import SwiftUI

struct MemorySettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var memories: [MemoryFragment] = []
    @State private var isLoading = true
    @State private var isDeleting = false
    @State private var showClearAllConfirm = false
    @State private var selectedType: MemoryType?
    @State private var showDeleteTypeConfirm = false
    @State private var loadTask: Task<Void, Never>?
    @State private var memoryToEdit: MemoryFragment?

    private var groupedMemories: [MemoryType: [MemoryFragment]] {
        Dictionary(grouping: memories, by: { $0.fragmentType })
    }

    var body: some View {
        Group {
            if isLoading && memories.isEmpty {
                ProgressView("Loading memories...")
            } else if memories.isEmpty {
                emptyStateView
            } else {
                memoriesList
            }
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("AI Memory")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !memories.isEmpty {
                    if isDeleting {
                        ProgressView()
                    } else {
                        Button(role: .destructive) {
                            showClearAllConfirm = true
                        } label: {
                            Text("Clear All")
                        }
                        .disabled(isDeleting)
                    }
                }
            }
        }
        .confirmationDialog("Clear All Memories", isPresented: $showClearAllConfirm) {
            Button("Clear All Memories", role: .destructive) {
                clearAllMemories()
            }
        } message: {
            Text(
                "This will permanently delete all memories MindFriend has learned about you. This action cannot be undone."
            )
        }
        .confirmationDialog("Clear \(selectedType?.displayName ?? "") Memories", isPresented: $showDeleteTypeConfirm) {
            Button("Clear All \(selectedType?.displayName ?? "")", role: .destructive) {
                if let type = selectedType {
                    clearMemoriesByType(type)
                }
            }
        }
        .task {
            await loadMemories()
        }
        .refreshable {
            await loadMemories()
        }
        .onDisappear {
            // Cancel any pending load task when view disappears
            loadTask?.cancel()
        }
        .trackScreen("memory_settings")
        .sheet(item: $memoryToEdit) { memory in
            EditMemoryFragmentSheet(memory: memory) { newKey, newValue in
                updateMemory(memory, key: newKey, value: newValue)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundStyle(SupportTheme.textSecondary)
                .accessibilityHidden(true)

            Text("No Memories Yet")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.semibold)

            Text(
                "As you chat with MindFriend, I'll remember important details about you to provide more personalized support."
            )
            .font(.body)
            .foregroundStyle(SupportTheme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, SupportTheme.Spacing.xl)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "No memories yet. As you chat with MindFriend, important details will be remembered to provide more personalized support."
        )
    }

    private var memoriesList: some View {
        List {
            // Info section
            Section {
                HStack(spacing: SupportTheme.Spacing.s) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(SupportTheme.accent)
                    Text(
                        "MindFriend automatically remembers details from your conversations to provide more personalized support."
                    )
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            .listRowBackground(SupportTheme.surface)

            // Grouped memories
            ForEach(MemoryType.allCases, id: \.self) { type in
                if let typeMemories = groupedMemories[type], !typeMemories.isEmpty {
                    Section {
                        ForEach(typeMemories) { memory in
                            MemoryRow(
                                memory: memory,
                                onEdit: {
                                    memoryToEdit = memory
                                },
                                onDelete: {
                                    deleteMemory(memory)
                                })
                        }
                    } header: {
                        HStack {
                            Label(type.displayName, systemImage: type.icon)
                            Spacer()
                            Button("Clear") {
                                selectedType = type
                                showDeleteTypeConfirm = true
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                    } footer: {
                        Text(type.description)
                    }
                    .listRowBackground(SupportTheme.surface)
                }
            }
        }
    }

    @MainActor
    private func loadMemories() async {
        isLoading = true
        do {
            // Check for cancellation before making network request
            try Task.checkCancellation()
            let fetchedMemories = try await container.supabaseDataService.getMemories()

            // Check for cancellation before updating state
            try Task.checkCancellation()
            memories = fetchedMemories
            Analytics.shared.track(
                .memorySettingsViewed,
                properties: [
                    "memory_count": memories.count
                ])
        } catch is CancellationError {
            // Task was cancelled, don't show error
            return
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
        isLoading = false
    }

    private func deleteMemory(_ memory: MemoryFragment) {
        Task { @MainActor in
            isDeleting = true
            do {
                try await container.supabaseDataService.deleteMemory(id: memory.id)
                withAnimation(reduceMotion ? nil : .default) {
                    memories.removeAll { $0.id == memory.id }
                }
                Analytics.shared.track(
                    .memoryDeleted,
                    properties: [
                        "memory_type": memory.fragmentType.rawValue
                    ])
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }
            isDeleting = false
        }
    }

    private func clearAllMemories() {
        Task { @MainActor in
            isDeleting = true
            do {
                try await container.supabaseDataService.deleteAllMemories()
                withAnimation(reduceMotion ? nil : .default) {
                    memories = []
                }
                Analytics.shared.track(.allMemoriesDeleted)
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }
            isDeleting = false
        }
    }

    private func clearMemoriesByType(_ type: MemoryType) {
        Task { @MainActor in
            isDeleting = true
            do {
                try await container.supabaseDataService.deleteMemories(type: type)
                withAnimation(reduceMotion ? nil : .default) {
                    memories.removeAll { $0.fragmentType == type }
                }
                Analytics.shared.track(
                    .memoriesDeletedByType,
                    properties: [
                        "memory_type": type.rawValue
                    ])
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }
            isDeleting = false
        }
    }

    private func updateMemory(_ memory: MemoryFragment, key: String, value: String) {
        Task { @MainActor in
            do {
                try await container.supabaseDataService.updateMemory(id: memory.id, key: key, value: value)
                // Update local state with the new values
                if let index = memories.firstIndex(where: { $0.id == memory.id }) {
                    withAnimation(reduceMotion ? nil : .default) {
                        memories[index] = MemoryFragment(
                            id: memory.id,
                            fragmentType: memory.fragmentType,
                            key: key,
                            value: value,
                            confidence: memory.confidence,
                            extractedAt: memory.extractedAt,
                            expiresAt: memory.expiresAt,
                            scheduledTime: memory.scheduledTime
                        )
                    }
                }
                memoryToEdit = nil
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }
        }
    }
}

struct MemoryRow: View {
    let memory: MemoryFragment
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var accessibilityDescription: String {
        var description = "\(memory.fragmentType.displayName): \(memory.displayContent)"
        if let expiresAt = memory.expiresAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relativeDate = formatter.localizedString(for: expiresAt, relativeTo: Date())
            description += ". Expires \(relativeDate)"
        }
        return description
    }

    var body: some View {
        HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(memory.displayContent)
                    .font(.body)

                HStack(spacing: SupportTheme.Spacing.xs) {
                    Text("Learned \(memory.extractedAt, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)

                    if memory.confidence < 0.7 {
                        Text("Low confidence")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.accent)
                    }

                    if let expiresAt = memory.expiresAt {
                        Text("Expires \(expiresAt, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.accent)
                    }
                }
            }

            Spacer()

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .tint(SupportTheme.accent)
            .accessibilityLabel("Edit memory")
            .accessibilityHint("Double tap to edit this memory")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete memory")
            .accessibilityHint("Double tap to delete this memory")
        }
        .padding(.vertical, SupportTheme.Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAction(named: "Edit") {
            onEdit()
        }
        .accessibilityAction(named: "Delete") {
            onDelete()
        }
    }
}

#Preview {
    NavigationStack {
        MemorySettingsView()
            .environmentObject(AppState())
            .environmentObject(DependencyContainer())
    }
}
