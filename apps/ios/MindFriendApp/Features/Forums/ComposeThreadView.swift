// Compose Thread View - Create new forum thread with anonymous option
// Per architect plan Phase E4: Title + content fields, anonymous toggle, character counters

import SwiftUI

struct ComposeThreadView: View {
    @StateObject private var viewModel: ComposeThreadViewModel
    @Environment(\.dismiss) private var dismiss

    init(forumService: ForumService, boardId: UUID) {
        _viewModel = StateObject(wrappedValue: ComposeThreadViewModel(forumService: forumService, boardId: boardId))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $viewModel.title, axis: .vertical)
                        .lineLimit(1...3)

                    Text("\(viewModel.title.count)/300")
                        .font(.caption)
                        .foregroundStyle(viewModel.title.count > 300 ? .red : .secondary)
                }

                Section {
                    TextEditor(text: $viewModel.content)
                        .frame(minHeight: 150)

                    Text("\(viewModel.content.count)/10,000")
                        .font(.caption)
                        .foregroundStyle(viewModel.content.count > 10000 ? .red : .secondary)
                }

                Section {
                    Toggle("Post Anonymously", isOn: $viewModel.isAnonymous)
                } footer: {
                    Text("Your identity will be hidden with a randomly generated name like \"Anonymous Otter\".")
                }

                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Discussion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
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
                    ProgressView("Submitting for review...")
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
final class ComposeThreadViewModel: ObservableObject {
    let forumService: ForumService
    let boardId: UUID

    @Published var title = ""
    @Published var content = ""
    @Published var isAnonymous = false
    @Published var isSubmitting = false
    @Published var didSubmit = false
    @Published var error: String?

    var canSubmit: Bool {
        !title.isEmpty && !content.isEmpty &&
        title.count <= 300 && content.count <= 10000 &&
        !isSubmitting
    }

    init(forumService: ForumService, boardId: UUID) {
        self.forumService = forumService
        self.boardId = boardId
    }

    func submit() async {
        guard canSubmit else { return }

        isSubmitting = true
        error = nil

        do {
            let thread = try await forumService.createThread(
                boardId: boardId,
                title: title,
                content: content,
                isAnonymous: isAnonymous
            )

            // Show pending moderation status
            if thread.status == .pending {
                // TODO: Show alert "Post submitted, pending review"
            }

            didSubmit = true
        } catch {
            self.error = error.localizedDescription
        }

        isSubmitting = false
    }
}
