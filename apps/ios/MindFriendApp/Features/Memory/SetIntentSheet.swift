import SwiftUI

/// Sheet for setting or updating the daily intent
struct SetIntentSheet: View {
    @EnvironmentObject private var memoryService: CompanionMemoryService
    @Environment(\.dismiss) private var dismiss

    @State private var intentText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let maxLength = 140

    private let examples = [
        "Stay present and not anxious",
        "Focus on gratitude today",
        "Be patient with myself",
        "Take breaks when I need them",
        "Remember my worth",
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "target")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("Set Today's Intent")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("What's your focus for today? Your companion will keep this in mind.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)

                // Text Input
                VStack(alignment: .trailing, spacing: 4) {
                    TextField("Enter your intent...", text: $intentText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .lineLimit(3...5)

                    Text("\(intentText.count)/\(maxLength)")
                        .font(.caption)
                        .foregroundStyle(intentText.count > maxLength ? .red : .secondary)
                }
                .padding(.horizontal)

                // Examples
                VStack(alignment: .leading, spacing: 8) {
                    Text("Examples")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(examples, id: \.self) { example in
                                Button {
                                    intentText = example
                                } label: {
                                    Text(example)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemGray6))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Error Message
                if let error = errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    Button {
                        Task {
                            await saveIntent()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Set Intent")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!isValid || isSaving)

                    if memoryService.dailyIntent != nil {
                        Button("Clear Current Intent", role: .destructive) {
                            Task {
                                await clearIntent()
                            }
                        }
                        .font(.subheadline)
                        .disabled(isSaving)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                if let existing = memoryService.dailyIntent, !existing.isExpired {
                    intentText = existing.intent
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var isValid: Bool {
        !intentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        intentText.count <= maxLength
    }

    // MARK: - Actions

    private func saveIntent() async {
        isSaving = true
        errorMessage = nil

        do {
            try await memoryService.setDailyIntent(intentText)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    private func clearIntent() async {
        isSaving = true
        errorMessage = nil

        do {
            try await memoryService.clearDailyIntent()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }
}

// MARK: - Preview

#Preview {
    SetIntentSheet()
        .environmentObject(DependencyContainer.preview.companionMemoryService)
}
