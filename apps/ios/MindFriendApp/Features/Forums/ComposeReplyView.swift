// Compose Reply View - Reply to thread or nested reply
// Per architect plan Phase E5: Content field, anonymous toggle, submit button

import SwiftUI

struct ComposeReplyView: View {
    @StateObject private var viewModel: ComposeReplyViewModel
    @Environment(\.dismiss) private var dismiss

    init(forumService: ForumService, threadId: UUID, parentReplyId: UUID?, isAnonymous: Bool) {
        _viewModel = StateObject(wrappedValue: ComposeReplyViewModel(
            forumService: forumService,
            threadId: threadId,
            parentReplyId: parentReplyId,
            inheritedAnonymous: isAnonymous
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $viewModel.content)
                        .frame(minHeight: 100)

                    Text("\(viewModel.content.count)/10,000")
                        .font(.caption)
                        .foregroundStyle(viewModel.content.count > 10000 ? .red : .secondary)
                }

                if viewModel.parentReplyId == nil {
                    Section {
                        Toggle("Reply Anonymously", isOn: $viewModel.isAnonymous)
                    } footer: {
                        Text(viewModel.inheritedAnonymous ?
                            "Thread is anonymous. Your reply will also be anonymous." :
                            "Post anonymously with a generated name.")
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
            .navigationTitle(viewModel.parentReplyId == nil ? "Reply to Thread" : "Reply to Comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Post Reply") {
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
                    ProgressView("Posting reply...")
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
final class ComposeReplyViewModel: ObservableObject {
    let forumService: ForumService
    let threadId: UUID
    let parentReplyId: UUID?
    let inheritedAnonymous: Bool

    @Published var content = ""
    @Published var isAnonymous = false
    @Published var isSubmitting = false
    @Published var didSubmit = false
    @Published var error: String?

    var canSubmit: Bool {
        !content.isEmpty && content.count <= 10000 && !isSubmitting
    }

    init(forumService: ForumService, threadId: UUID, parentReplyId: UUID?, inheritedAnonymous: Bool) {
        self.forumService = forumService
        self.threadId = threadId
        self.parentReplyId = parentReplyId
        self.inheritedAnonymous = inheritedAnonymous
        self.isAnonymous = inheritedAnonymous // Default to thread's anonymity
    }

    func submit() async {
        guard canSubmit else { return }

        isSubmitting = true
        error = nil

        do {
            _ = try await forumService.createReply(
                threadId: threadId,
                parentReplyId: parentReplyId,
                content: content,
                isAnonymous: isAnonymous
            )

            didSubmit = true
        } catch {
            self.error = error.localizedDescription
        }

        isSubmitting = false
    }
}
