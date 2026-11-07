import SwiftUI

struct SupportContextView: View {
    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    @EnvironmentObject private var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID
    let receipt: SupportChatReceipt?
    @State private var error: String?
    private var session: SupportSession? { coordinator.journal.sessions[sessionID] }

    var body: some View {
        NavigationStack {
            Form {
                Section("This session") {
                    if let session {
                        Text(session.title)
                        Picker("For the next reply", selection: Binding(get: { session.contextScope }, set: { scope in
                            Task { do { try await coordinator.setScope(scope, sessionID: sessionID) }
                                   catch { self.error = SupportSessionCoordinator.message(for: error) } }
                        })) {
                            Text("Use only this conversation").tag(SupportContextScope.conversationOnly)
                            Text("Include approved saved context").tag(SupportContextScope.personalized)
                        }
                        // The server accepts only a rename on a closed session, so the scope choice is not offered there.
                        .disabled(session.status != .open)
                        Text("Conversation-only includes this conversation and results you deliberately shared in this session. Saved personal memories and other conversations are excluded.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if session.status != .open {
                            Text("This session is closed, so its context choice can’t be changed.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else { Text("This session is no longer available.") }
                    if coordinator.journal.personalizedCloudPaused {
                        Text("A context correction is saved here. Account confirmation is pending; cloud replies are paused.")
                    }
                }
                Section(receipt == nil ? "Saved context proposed for the next reply" : "Shared with this reply") {
                    if let receipt {
                        Text(receipt.scope == .conversationOnly ? "Conversation-only" : "Approved saved context included")
                        Text("This is the recorded context sent with the reply. It does not reveal which source the model relied on.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        ForEach(receipt.sources) { source in
                            VStack(alignment: .leading, spacing: 8) {
                                if source.kind == "companion_memory", let item = coordinator.journal.memoryRecords[source.id] {
                                    Text(item.content)
                                    Text("Saved context · revision \(source.revision)").font(.caption)
                                    Button("That no longer applies") { stopUsing(item) }
                                } else {
                                    Text(source.kind.replacingOccurrences(of: "_", with: " ").capitalized)
                                    Text(source.date.flatMap(SupportChatTimestamp.date)?.formatted(date: .abbreviated, time: .shortened) ?? "Date not supplied")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if coordinator.journal.suppressions.contains(where: { $0.targetID == source.id.uuidString.lowercased() }) {
                                        Text("Removed from future context").font(.caption)
                                    }
                                }
                            }
                        }
                    } else {
                        Text(session?.contextScope == .personalized
                            ? "Only approved, current items may be selected by the account’s context controls. The exact included sources appear here after a confirmed reply."
                            : "Saved personal memories will not be included.")
                    }
                }
                Section("Not included") {
                    let exclusions = receipt?.exclusions ?? ["other_conversations", "health_data", "inferred_affect", "private_vault", "unapproved_suggestions"]
                    ForEach(exclusions, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ").capitalized) }
                }
                Section("Memory suggestions") {
                    if session?.conversationID != nil {
                        NavigationLink("Suggest memories from this session") { SupportMemorySuggestionView(sessionID: sessionID) }
                        Text("You choose which of your messages are previewed. Nothing is sent to an AI service until you choose Generate.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("Suggesting memories needs a conversation attached to this session.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section { NavigationLink("Manage memory") { SupportMemoryView() } }
                if let error { Section { Text(error) } }
            }
            .navigationTitle("Context")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func stopUsing(_ item: SupportMemoryRecord) {
        Task {
            do {
                _ = try await coordinator.repository.queueMemoryChange(epoch: coordinator.identity.epochID,
                    targetID: item.id, action: .stopUsing, expectedRevision: item.revision)
                try await container.supportSync?.retry()
            } catch { self.error = "Stopped using is pending here. Open Manage memory to review or retry the change." }
        }
    }
}
