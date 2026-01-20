import SwiftUI

/// Sheet for adding a reflection after a ritual
struct AddReflectionSheet: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    let ritualId: UUID
    let onComplete: () -> Void

    @State private var reflection = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let maxCharacters = 140

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)

                    Text("Share Your Reflection")
                        .font(.title2.bold())

                    Text("What did you notice or feel during this ritual?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)

                // Text input
                VStack(alignment: .trailing, spacing: 8) {
                    TextEditor(text: $reflection)
                        .frame(height: 120)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .accessibilityLabel("Reflection text")
                        .onChange(of: reflection) { _, newValue in
                            if newValue.count > maxCharacters {
                                reflection = String(newValue.prefix(maxCharacters))
                            }
                        }

                    Text("\(reflection.count)/\(maxCharacters)")
                        .font(.caption)
                        .foregroundColor(reflection.count > maxCharacters - 20 ? .orange : .secondary)
                }
                .padding(.horizontal)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    Button {
                        submitReflection()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Share Reflection")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)

                    Button {
                        onComplete()
                        dismiss()
                    } label: {
                        Text("Skip for now")
                            .font(.subheadline)
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func submitReflection() {
        let content = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                _ = try await container.ritualService.addReflection(
                    ritualId: ritualId,
                    content: content
                )

                await MainActor.run {
                    onComplete()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}

#Preview {
    AddReflectionSheet(ritualId: UUID()) {}
        .environmentObject(DependencyContainer())
}
