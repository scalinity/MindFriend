import SwiftUI

/// Editor view for creating and editing vault entries.
struct VaultEntryEditorView: View {
    @EnvironmentObject private var viewModel: VaultViewModel
    @Environment(\.dismiss) private var dismiss

    /// The entry being edited, or nil for new entries
    let entry: VaultEntry?

    @State private var title: String = ""
    @State private var entryBody: String = ""
    @State private var isSaving: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
        case entryBody
    }

    /// Whether this is editing an existing entry
    private var isEditing: Bool {
        entry != nil
    }

    /// Whether the save button should be enabled
    private var canSave: Bool {
        !entryBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    /// Whether any changes have been made
    private var hasChanges: Bool {
        if let entry = entry {
            let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let newBody = entryBody.trimmingCharacters(in: .whitespacesAndNewlines)
            return (entry.title ?? "") != newTitle || entry.body != newBody
        }
        return !title.isEmpty || !entryBody.isEmpty
    }

    init(entry: VaultEntry? = nil) {
        self.entry = entry
        if let entry = entry {
            _title = State(initialValue: entry.title ?? "")
            _entryBody = State(initialValue: entry.body)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title (optional)", text: $title)
                        .focused($focusedField, equals: .title)
                        .accessibilityLabel("Entry title")
                        .accessibilityHint("Optional title for your journal entry")
                }

                Section {
                    TextEditor(text: $entryBody)
                        .frame(minHeight: 200)
                        .focused($focusedField, equals: .entryBody)
                        .accessibilityLabel("Entry content")
                        .accessibilityHint("Write your private journal entry here")
                } header: {
                    Text("Entry")
                } footer: {
                    Text("Your entry is encrypted and stored only on this device.")
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Delete Entry", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Entry" : "New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveEntry()
                        }
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .onAppear {
                // Focus on body field for new entries, title for editing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    focusedField = isEditing ? .title : .entryBody
                }
            }
            .alert("Delete Entry?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteEntry()
                    }
                }
            } message: {
                Text("This entry will be permanently deleted. This action cannot be undone.")
            }
            .keyboardDoneButton()
        }
    }

    // MARK: - Actions

    private func saveEntry() async {
        isSaving = true
        defer { isSaving = false }

        let success: Bool
        if let entry = entry {
            success = await viewModel.updateEntry(entry, title: title, body: entryBody)
        } else {
            success = await viewModel.createEntry(title: title, body: entryBody)
        }

        if success {
            dismiss()
        }
    }

    private func deleteEntry() async {
        guard let entry = entry else { return }

        isSaving = true
        await viewModel.deleteEntry(entry.id)
        isSaving = false
        dismiss()
    }
}

#Preview("New Entry") {
    VaultEntryEditorView()
}

#Preview("Edit Entry") {
    VaultEntryEditorView(entry: VaultEntry(
        title: "Sample Entry",
        body: "This is a sample journal entry for preview purposes."
    ))
}
