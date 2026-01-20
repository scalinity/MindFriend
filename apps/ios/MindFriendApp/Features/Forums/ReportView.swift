// Report View - Report inappropriate content
// Per architect plan Phase E6: Reason picker, details field, submit button

import SwiftUI

struct ReportView: View {
    @StateObject private var viewModel: ReportViewModel
    @Environment(\.dismiss) private var dismiss

    init(forumService: ForumService, threadId: UUID?, replyId: UUID?) {
        _viewModel = StateObject(wrappedValue: ReportViewModel(
            forumService: forumService,
            threadId: threadId,
            replyId: replyId
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Why are you reporting this?") {
                    ForEach(ReportReason.allCases, id: \.self) { reason in
                        Button {
                            viewModel.selectedReason = reason
                        } label: {
                            HStack {
                                Image(systemName: reason.icon)
                                    .foregroundStyle(.blue)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reason.displayName)
                                        .foregroundStyle(.primary)
                                    Text(reason.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if viewModel.selectedReason == reason {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if viewModel.selectedReason != nil {
                    Section("Additional Details (Optional)") {
                        TextEditor(text: $viewModel.details)
                            .frame(minHeight: 80)

                        Text("\(viewModel.details.count)/1,000")
                            .font(.caption)
                            .foregroundStyle(viewModel.details.count > 1000 ? .red : .secondary)
                    }
                }

                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Report Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit Report") {
                        Task {
                            await viewModel.submit()
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                    .fontWeight(.semibold)
                }
            }
            .disabled(viewModel.isSubmitting)
            .overlay {
                if viewModel.isSubmitting {
                    ProgressView("Submitting report...")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .onChange(of: viewModel.didSubmit) { _, submitted in
                if submitted {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ReportViewModel: ObservableObject {
    let forumService: ForumService
    let threadId: UUID?
    let replyId: UUID?

    @Published var selectedReason: ReportReason?
    @Published var details = ""
    @Published var isSubmitting = false
    @Published var didSubmit = false
    @Published var error: String?

    var canSubmit: Bool {
        selectedReason != nil && details.count <= 1000 && !isSubmitting
    }

    init(forumService: ForumService, threadId: UUID?, replyId: UUID?) {
        self.forumService = forumService
        self.threadId = threadId
        self.replyId = replyId
    }

    func submit() async {
        guard let reason = selectedReason, canSubmit else { return }

        isSubmitting = true
        error = nil

        do {
            try await forumService.reportContent(
                threadId: threadId,
                replyId: replyId,
                reason: reason,
                details: details.isEmpty ? nil : details
            )

            didSubmit = true
        } catch {
            self.error = error.localizedDescription
        }

        isSubmitting = false
    }
}
