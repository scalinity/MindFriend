import SwiftUI

struct EditMemoryFragmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    let memory: MemoryFragment
    let onSave: (String, String) -> Void

    @State private var editedKey: String
    @State private var editedValue: String
    @State private var isSaving = false

    private let maxValueLength = 500

    init(memory: MemoryFragment, onSave: @escaping (String, String) -> Void) {
        self.memory = memory
        self.onSave = onSave
        _editedKey = State(initialValue: memory.key.replacingOccurrences(of: "_", with: " ").capitalized)
        _editedValue = State(initialValue: memory.value)
    }

    private var isValid: Bool {
        !editedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !editedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        editedValue.count <= maxValueLength
    }

    private var normalizedKey: String {
        editedKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Label")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g., Dog Name, Work Location", text: $editedKey)
                            .textInputAutocapitalization(.words)
                    }
                } header: {
                    Label(memory.fragmentType.displayName, systemImage: memory.fragmentType.icon)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Value")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Enter value", text: $editedValue, axis: .vertical)
                            .lineLimit(3...6)

                        HStack {
                            Spacer()
                            Text("\(editedValue.count)/\(maxValueLength)")
                                .font(.caption)
                                .foregroundStyle(editedValue.count > maxValueLength ? .red : .secondary)
                        }
                    }
                }

                if let expiresAt = memory.expiresAt {
                    Section {
                        HStack {
                            Text("Expires")
                            Spacer()
                            Text(expiresAt, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("This memory will automatically expire and be removed.")
                    }
                }
            }
            .navigationTitle("Edit Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            saveMemory()
                        }
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func saveMemory() {
        let trimmedKey = normalizedKey
        let trimmedValue = editedValue.trimmingCharacters(in: .whitespacesAndNewlines)

        isSaving = true
        onSave(trimmedKey, trimmedValue)
    }
}

#Preview {
    EditMemoryFragmentSheet(
        memory: MemoryFragment(
            id: "1",
            fragmentType: .fact,
            key: "current_project",
            value: "my app",
            confidence: 0.9,
            extractedAt: Date().addingTimeInterval(-3600),
            expiresAt: nil,
            scheduledTime: nil
        ),
        onSave: { _, _ in }
    )
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
