import SwiftUI

/// Main view for managing companion memories (Memory Vault)
struct CompanionMemoryView: View {
    @EnvironmentObject private var memoryService: CompanionMemoryService
    @State private var selectedCategory: MemoryCategory?
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var memoryToEdit: CompanionMemory?
    @State private var memoryToDelete: CompanionMemory?
    @State private var showingDeleteConfirmation = false
    @State private var deleteError: String?
    @State private var showingDeleteError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Daily Intent Section
                if let intent = memoryService.dailyIntent, !intent.isExpired {
                    DailyIntentBanner(intent: intent)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                // Category Filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        MemoryFilterChip(
                            title: "All",
                            isSelected: selectedCategory == nil,
                            color: .primary
                        ) {
                            selectedCategory = nil
                        }

                        ForEach(MemoryCategory.allCases) { category in
                            MemoryFilterChip(
                                title: category.displayName,
                                isSelected: selectedCategory == category,
                                color: category.color
                            ) {
                                selectedCategory = category
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }

                // Memory Count
                HStack {
                    Text("\(memoryService.totalCount) of \(memoryService.maxLimit) memories")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if memoryService.isLimitReached {
                        Label("Limit reached", systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                // Memory List
                if memoryService.isLoading && memoryService.memories.isEmpty {
                    Spacer()
                    ProgressView("Loading memories...")
                    Spacer()
                } else if filteredMemories.isEmpty {
                    Spacer()
                    EmptyMemoryView(
                        hasFilter: selectedCategory != nil || !searchText.isEmpty,
                        onAddTapped: { showingAddSheet = true }
                    )
                    Spacer()
                } else {
                    List {
                        ForEach(groupedMemories, id: \.key) { category, memories in
                            Section {
                                ForEach(memories) { memory in
                                    MemoryItemCard(memory: memory)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                memoryToDelete = memory
                                                showingDeleteConfirmation = true
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }

                                            Button {
                                                memoryToEdit = memory
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            .tint(.blue)
                                        }
                                }
                            } header: {
                                HStack {
                                    Image(systemName: category.icon)
                                        .foregroundStyle(category.color)
                                    Text(category.displayName)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await memoryService.fetchMemories()
                    }
                }
            }
            .navigationTitle("Memory Vault")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search memories")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(memoryService.isLimitReached)
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                EditMemorySheet(mode: .create)
            }
            .sheet(item: $memoryToEdit) { memory in
                EditMemorySheet(mode: .edit(memory))
            }
            .confirmationDialog(
                "Delete Memory",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let memory = memoryToDelete {
                        Task {
                            do {
                                try await memoryService.deleteMemory(id: memory.id)
                            } catch {
                                deleteError = error.localizedDescription
                                showingDeleteError = true
                            }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This memory will be permanently deleted.")
            }
            .alert("Delete Failed", isPresented: $showingDeleteError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "Failed to delete memory. Please try again.")
            }
            .task {
                if memoryService.memories.isEmpty {
                    await memoryService.fetchMemories()
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var filteredMemories: [CompanionMemory] {
        var result = memoryService.memories

        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.content.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    private var groupedMemories: [(key: MemoryCategory, value: [CompanionMemory])] {
        let grouped = Dictionary(grouping: filteredMemories, by: { $0.category })
        return MemoryCategory.allCases
            .compactMap { category in
                guard let memories = grouped[category], !memories.isEmpty else { return nil }
                return (key: category, value: memories)
            }
    }
}

// MARK: - Memory Filter Chip

private struct MemoryFilterChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color.opacity(0.15) : Color(.systemGray6))
                .foregroundStyle(isSelected ? color : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Memory Item Card

private struct MemoryItemCard: View {
    let memory: CompanionMemory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(memory.content)
                .font(.body)

            HStack(spacing: 12) {
                // Created date
                Label(memory.createdAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Usage indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(memory.usageLevel.color)
                        .frame(width: 6, height: 6)
                    Text(memory.usageLevel.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty View

private struct EmptyMemoryView: View {
    let hasFilter: Bool
    let onAddTapped: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            if hasFilter {
                Text("No memories match your filter")
                    .font(.headline)
                Text("Try a different category or search term")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No memories yet")
                    .font(.headline)
                Text("Add memories to help your companion understand you better")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Add Your First Memory") {
                    onAddTapped()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    CompanionMemoryView()
        .environmentObject(DependencyContainer.preview.companionMemoryService)
}
