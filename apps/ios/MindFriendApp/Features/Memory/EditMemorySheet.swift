import SwiftUI

/// Sheet for creating or editing a companion memory
struct EditMemorySheet: View {
    enum Mode: Identifiable {
        case create
        case edit(CompanionMemory)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let memory): return memory.id
            }
        }
    }

    @EnvironmentObject private var memoryService: CompanionMemoryService
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var selectedCategory: MemoryCategory = .preferences
    @State private var content = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let maxLength = 500

    var body: some View {
        NavigationStack {
            Form {
                // Category Picker
                Section {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(MemoryCategory.allCases) { category in
                            Label(category.displayName, systemImage: category.icon)
                                .tag(category)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("Category")
                } footer: {
                    Text(selectedCategory.description)
                }

                // Content Editor
                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if content.isEmpty {
                                Text("What would you like your companion to remember?")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    HStack {
                        Text("Memory Content")
                        Spacer()
                        Text("\(content.count)/\(maxLength)")
                            .font(.caption)
                            .foregroundStyle(content.count > maxLength ? .red : .secondary)
                    }
                } footer: {
                    Text("Be specific. Example: \"I prefer direct advice over gentle suggestions\" or \"My dog Max helps me feel calm\"")
                }

                // Error Message
                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Memory" : "Add Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        Task {
                            await saveMemory()
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                if case .edit(let memory) = mode {
                    selectedCategory = memory.category
                    content = memory.content
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isValid: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        content.count <= maxLength
    }

    // MARK: - Actions

    private func saveMemory() async {
        isSaving = true
        errorMessage = nil

        do {
            switch mode {
            case .create:
                try await memoryService.createMemory(category: selectedCategory, content: content)
            case .edit(let memory):
                try await memoryService.updateMemory(id: memory.id, category: selectedCategory, content: content)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }
}

// MARK: - Preview

#Preview("Create") {
    EditMemorySheet(mode: .create)
        .environmentObject(DependencyContainer.preview.companionMemoryService)
}

#Preview("Edit") {
    let sampleMemory = CompanionMemory(
        id: "123",
        category: .preferences,
        content: "I prefer direct advice",
        lastUsedAt: Date(),
        usageCount: 5,
        createdAt: Date(),
        updatedAt: Date()
    )
    EditMemorySheet(mode: .edit(sampleMemory))
        .environmentObject(DependencyContainer.preview.companionMemoryService)
}
