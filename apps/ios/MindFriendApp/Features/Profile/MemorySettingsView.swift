import SwiftUI

struct MemorySettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var memories: [MemoryFragment] = []
    @State private var isLoading = true
    @State private var isDeleting = false
    @State private var showClearAllConfirm = false
    @State private var selectedType: MemoryType?
    @State private var showDeleteTypeConfirm = false
    @State private var loadTask: Task<Void, Never>?

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
            Text("This will permanently delete all memories MindFriend has learned about you. This action cannot be undone.")
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
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No Memories Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("As you chat with MindFriend, I'll remember important details about you to provide more personalized support.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No memories yet. As you chat with MindFriend, important details will be remembered to provide more personalized support.")
    }

    private var memoriesList: some View {
        List {
            // Info section
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("MindFriend automatically remembers details from your conversations to provide more personalized support.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Grouped memories
            ForEach(MemoryType.allCases, id: \.self) { type in
                if let typeMemories = groupedMemories[type], !typeMemories.isEmpty {
                    Section {
                        ForEach(typeMemories) { memory in
                            MemoryRow(memory: memory) {
                                deleteMemory(memory)
                            }
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
            Analytics.shared.track(.memorySettingsViewed, properties: [
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
                withAnimation {
                    memories.removeAll { $0.id == memory.id }
                }
                Analytics.shared.track(.memoryDeleted, properties: [
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
                withAnimation {
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
                withAnimation {
                    memories.removeAll { $0.fragmentType == type }
                }
                Analytics.shared.track(.memoriesDeletedByType, properties: [
                    "memory_type": type.rawValue
                ])
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }
            isDeleting = false
        }
    }
}

struct MemoryRow: View {
    let memory: MemoryFragment
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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(memory.displayContent)
                    .font(.body)

                HStack(spacing: 8) {
                    Text("Learned \(memory.extractedAt, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if memory.confidence < 0.7 {
                        Text("Low confidence")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if let expiresAt = memory.expiresAt {
                        Text("Expires \(expiresAt, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

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
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
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
