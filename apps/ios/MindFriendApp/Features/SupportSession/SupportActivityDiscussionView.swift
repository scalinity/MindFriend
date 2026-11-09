import SwiftUI

/// A field-level preview. Preparing the editable Chat draft never starts an AI request.
struct SupportActivityDiscussionView: View {
    let snapshot: SupportActivityDiscussionSnapshot
    @ObservedObject var coordinator: SupportSessionCoordinator
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var question = "Help me think about this."
    @State private var isSaving = false
    @State private var error: String?

    private var preview: String {
        SupportActivityDiscussion.message(title: snapshot.title, fields: snapshot.fields, selected: selected,
            question: question, existingDraft: snapshot.existingDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose which answers to include. Nothing is sent or billed until you select Send in Chat.")
                    Text("The activity stays in this account. This choice does not turn on sharing for other answers or later replies.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Once you send it, this text is part of the conversation and later replies in it can use it.")
                    if snapshot.sessionIsClosed {
                        Text("This session is closed. Reviewing the draft starts a new linked session. A new conversation is created only when you select Send.")
                    }
                }
                Section("Answers to include") {
                    if snapshot.fields.isEmpty { Text("There are no written answers to include. You can still ask a question.") }
                    ForEach(snapshot.fields) { field in
                        Toggle(isOn: Binding(get: { selected.contains(field.id) }, set: { include in
                            if include { selected.insert(field.id) } else { selected.remove(field.id) }
                        })) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(field.label).font(.headline)
                                Text(field.text).textSelection(.enabled)
                            }
                        }
                        .accessibilityIdentifier("support-share-" + field.id)
                    }
                }
                if !snapshot.existingDraft.isEmpty {
                    Section("Your existing unsent draft") {
                        Text(snapshot.existingDraft).textSelection(.enabled)
                        Text("This stays at the start of the message. Nothing in your draft is replaced.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section("What would you like to ask?") {
                    TextField("Your question", text: $question, axis: .vertical).lineLimit(3...8)
                }
                Section("Message preview") {
                    Text(preview.isEmpty ? "No message yet" : preview).textSelection(.enabled)
                    Text("Message size: \(preview.utf16.count) of \(SupportSessionLimits.draftMaxCharacters). Emoji and some characters count as more than one.")
                        .font(.caption).foregroundStyle(.secondary)
                    if preview.utf16.count > SupportSessionLimits.draftMaxCharacters {
                        Text("Choose fewer answers or shorten the question. Your original answers stay unchanged.")
                    }
                }
                Section {
                    Button("Review message in Chat") { prepareDraft() }
                        .frame(minHeight: 44)
                        .disabled(isSaving || preview.isEmpty || preview.utf16.count > SupportSessionLimits.draftMaxCharacters)
                    if isSaving { ProgressView("Saving your draft…") }
                    if let error { Text(error).foregroundStyle(.primary) }
                }
            }
            .disabled(isSaving)
            .supportCanvas()
            .navigationTitle("Choose what to share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) } }
        }
        .sentryMaskChat()
    }

    private func prepareDraft() {
        guard !isSaving, appState.currentUser?.id == coordinator.identity.ownerID,
              container.supportSessionCoordinator === coordinator else { return }
        let owner = coordinator.identity.ownerID, epoch = appState.accountEpoch
        isSaving = true; error = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                let handoff = try await coordinator.prepareActivityDiscussion(snapshot, selected: selected, question: question)
                guard !Task.isCancelled, appState.currentUser?.id == owner, appState.accountEpoch == epoch,
                      container.supportSessionCoordinator === coordinator else { return }
                appState.selectedTab = .chat
                if let conversationID = handoff.conversationID {
                    deepLinkRouter.handleRoute(.chat(conversationId: conversationID.uuidString), appState: appState)
                } else { appState.shouldOpenNewChat = true }
                dismiss()
            } catch {
                guard appState.currentUser?.id == owner, appState.accountEpoch == epoch,
                      container.supportSessionCoordinator === coordinator else { return }
                self.error = SupportSessionCoordinator.message(for: error)
            }
        }
    }
}
