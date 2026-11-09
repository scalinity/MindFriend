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
            VStack(spacing: SupportTheme.Spacing.l) {
                // Header
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 48))
                        .foregroundColor(SupportTheme.accent)

                    Text("Share Your Reflection")
                        .font(.title2.bold())

                    Text("What did you notice or feel during this ritual?")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)

                // Text input
                VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xs) {
                    TextEditor(text: $reflection)
                        .scrollContentBackground(.hidden)
                        .supportField()
                        .frame(height: 120)
                        .padding(SupportTheme.Spacing.xs)
                        .background(SupportTheme.surface)
                        .cornerRadius(SupportTheme.controlRadius)
                        .accessibilityLabel("Reflection text")
                        .onChange(of: reflection) { _, newValue in
                            if newValue.count > maxCharacters {
                                reflection = String(newValue.prefix(maxCharacters))
                            }
                        }

                    Text("\(reflection.count)/\(maxCharacters)")
                        .font(.caption)
                        .foregroundColor(reflection.count > maxCharacters - 20 ? SupportTheme.accent : SupportTheme.textSecondary)
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
                VStack(spacing: SupportTheme.Spacing.s) {
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
                    .buttonStyle(.supportPrimary)
                    .controlSize(.large)
                    .disabled(reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)

                    Button {
                        onComplete()
                        dismiss()
                    } label: {
                        Text("Skip for now")
                            .font(.subheadline)
                    }
                    .foregroundColor(SupportTheme.textSecondary)
                }
                .padding(.horizontal)
                .padding(.bottom, SupportTheme.Spacing.l)
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
