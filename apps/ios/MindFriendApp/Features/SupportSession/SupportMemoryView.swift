import SwiftUI

struct SupportMemoryView: View {
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    @State private var editing: SupportMemoryRecord?
    @State private var showTodayFocus = false
    @State private var showAdd = false
    @State private var forgetting: SupportMemoryRecord?
    @State private var error: String?
    @State private var recoveryDecision = false
    @State private var recoveryChange: (SupportMemoryRecord, SupportMemoryAction, String?)?

    private var saved: [SupportMemoryRecord] { records.filter { !$0.isSuggestion } }
    private var suggestions: [SupportMemoryRecord] { records.filter(\.isSuggestion) }
    private var records: [SupportMemoryRecord] {
        coordinator.journal.memoryRecords.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    /// Real local sessions that have a conversation attached, the foreground one first. Nothing is invented: an empty
    /// result is shown as unavailable.
    private var suggestionSources: [SupportSession] {
        let foreground = coordinator.foregroundSessionID
        return coordinator.journal.sessions.values
            .filter { $0.conversationID != nil && $0.status != .deleted }
            .sorted { lhs, rhs in
                if (lhs.id == foreground) != (rhs.id == foreground) { return lhs.id == foreground }
                return lhs.updatedAt != rhs.updatedAt ? lhs.updatedAt > rhs.updatedAt : lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(8).map { $0 }
    }

    var body: some View {
        Form {
            Section {
                Text("You can inspect and change the saved context MindFriend may share with AI. Suggestions are excluded until you save them.")
                if let sync = container.supportSync { Text(sync.status).font(.subheadline).foregroundStyle(.secondary) }
                if coordinator.journal.memoryUpdatedAt == nil {
                    Text("Saved context has not been loaded on this device.")
                }
                Button("Refresh account context") { refresh() }
                if let error { Text(error).foregroundStyle(.primary) }
            }
            Section("Saved by you") {
                Button("Add saved context") { showAdd = true }
                if saved.isEmpty { Text("No saved items in the available account snapshot.").foregroundStyle(.secondary) }
                ForEach(saved) { item in memoryRow(item) }
            }
            Section("Suggestions to review") {
                if suggestions.isEmpty { Text("No suggestions in the available account snapshot.").foregroundStyle(.secondary) }
                ForEach(suggestions) { item in memoryRow(item) }
            }
            Section("Suggest memories from a session") {
                Text("Pick a session to look through for things you clearly said about yourself. You see exactly what would be sent, and choose which messages, before anything is. Suggestions stay here for review and aren’t used until you save them.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if suggestionSources.isEmpty {
                    Text("Unavailable: no session on this device has a conversation attached.").foregroundStyle(.secondary)
                }
                ForEach(suggestionSources) { session in
                    NavigationLink {
                        SupportMemorySuggestionView(sessionID: session.id, cameFromMemoryList: true)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title.isEmpty ? "Untitled session" : session.title)
                            Text(sourceCaption(session)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("For today") {
                if let today = container.supportSync?.memory?.dailyIntent, today.expiresAt > Date() {
                    Text(today.intent)
                    Text("Expires \(today.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("No current focus is available in this snapshot.").foregroundStyle(.secondary)
                }
                Button("Change today’s focus") { showTodayFocus = true }
            }
            if !coordinator.journal.memoryChanges.isEmpty {
                Section("Changes awaiting confirmation") {
                    ForEach(coordinator.journal.memoryChanges) { change in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(change.failureCode == nil ? "Saved here. Syncing the change…" : "This change needs attention.")
                            Text("Personalized AI is paused until these changes are settled.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let other = change.conflictingContent {
                                Text("The account now contains:").font(.headline)
                                Text(other)
                                if let local = change.content { Text("Your correction:").font(.headline); Text(local) }
                                Button("Keep my correction") { resolve(change, keepLocal: true) }
                                Button("Use the account version") { resolve(change, keepLocal: false) }
                            } else if let code = change.failureCode {
                                Text("The account did not accept this change (\(code)). Your local choice is retained.")
                                    .font(.subheadline)
                            }
                        }
                    }
                    Button("Retry account sync") { retry() }
                }
            }
            Section("Personalization controls") {
                NavigationLink("Choose what AI may use") { MemorySettingsView() }
                Text("Conversation-only uses the current conversation and its explicitly shared activity results. It excludes saved personal memories, earlier conversations, Health data, and inferred emotions.")
                NavigationLink("Private journal · on this device") { VaultListView().environmentObject(container.vaultViewModel) }
                Text("The private journal stays on this device and is never included through these memory controls.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("What MindFriend remembers")
        .supportCanvas()
        .task { refresh() }
        .sheet(isPresented: $showAdd, onDismiss: { refresh() }) {
            EditMemorySheet(mode: .create).environmentObject(container.companionMemoryService).id(coordinator.identity.epochID)
                .task { await container.companionMemoryService.fetchMemories() }
        }
        .sheet(isPresented: $showTodayFocus, onDismiss: { refresh() }) {
            SetIntentSheet().environmentObject(container.companionMemoryService).id(coordinator.identity.epochID)
                .task { await container.companionMemoryService.fetchMemories() }
        }
        .sheet(item: $editing) { item in
            SupportMemoryEditor(item: item) { text in
                submit(item, action: item.isSuggestion ? .approveCandidate : .edit, content: text)
            }
        }
        .confirmationDialog("Forget this saved context?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } })) {
            if let item = forgetting {
                Button("Forget", role: .destructive) {
                    submit(item, action: item.isSuggestion ? .forgetCandidate : .forgetMemory)
                    forgetting = nil
                }
            }
            Button("Cancel", role: .cancel) { forgetting = nil }
        } message: {
            Text("The item stops being used here immediately. Account-wide removal and exclusion of known derived replies begin when sync is confirmed. Existing conversation history remains visible. Previously sent provider context cannot be recalled.")
        }
        .alert("Unreadable recovery copies may contain this context", isPresented: $recoveryDecision) {
            Button("Keep recovery copies", role: .cancel) { recoveryChange = nil }
            Button("Remove copies and continue", role: .destructive) {
                guard let request = recoveryChange else { return }
                recoveryChange = nil
                Task {
                    do {
                        try await coordinator.discardRecoveryCopies()
                        submit(request.0, action: request.1, content: request.2)
                    } catch { self.error = SupportSessionCoordinator.message(for: error) }
                }
            }
        } message: { Text("Removing them allows the correction or deletion to cover every local journal copy. Their unreadable work cannot be recovered afterward.") }
    }

    @ViewBuilder private func memoryRow(_ item: SupportMemoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.content)
            Text(item.category.replacingOccurrences(of: "_", with: " ").capitalized).font(.subheadline)
            Text(origin(item)).font(.subheadline).foregroundStyle(.secondary)
            Text(item.state.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption).foregroundStyle(.secondary)
            if let date = item.confirmedAt { Text("Confirmed \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption) }
            if let date = item.reviewDueAt { Text("Review \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption) }
            if let date = item.expiresAt { Text("Expires \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption) }
            if !coordinator.journal.memoryChanges.contains(where: { $0.targetID == item.id }) {
                if item.isSuggestion {
                    Button("Save") { submit(item, action: .approveCandidate) }
                    Button("Edit first") { editing = item }
                    Button("Dismiss") { submit(item, action: .dismissCandidate) }
                } else {
                    Button("Edit") { editing = item }
                    Button(item.state == "disabled" ? "Use again" : "Stop using") {
                        submit(item, action: item.state == "disabled" ? .resumeUsing : .stopUsing)
                    }
                }
            }
            Button("Forget", role: .destructive) { forgetting = item }
        }
        .padding(.vertical, 8)
    }

    private func sourceCaption(_ session: SupportSession) -> String {
        var parts = [session.updatedAt.formatted(date: .abbreviated, time: .shortened)]
        if session.id == coordinator.foregroundSessionID { parts.append("Current session") }
        if session.status == .closed { parts.append("Closed") }
        return parts.joined(separator: " · ")
    }

    private func origin(_ item: SupportMemoryRecord) -> String {
        if item.isSuggestion {
            if item.origin == "unknown" || (item.sourceMessageID == nil && item.sourceConversationID == nil) {
                return "Original source unknown. Review this suggestion before saving."
            }
            return item.origin == "message"
                ? "Suggested from your message. Not yet shared as saved context."
                : "Suggested from an account conversation. Not yet shared as saved context."
        }
        switch item.origin {
        case "user_authored": return "You added this"
        case "approved_candidate": return "Suggested from a message, then approved"
        default: return "Original source unknown"
        }
    }

    private func submit(_ item: SupportMemoryRecord, action: SupportMemoryAction, content: String? = nil) {
        error = nil
        Task {
            do {
                _ = try await coordinator.repository.queueMemoryChange(epoch: coordinator.identity.epochID, targetID: item.id,
                    action: action, content: content, category: item.isSuggestion ? nil : item.category,
                    expectedRevision: item.isSuggestion ? nil : item.revision)
                retry()
            } catch SupportSessionError.recoveryCopiesNeedDecision {
                recoveryChange = (item, action, content); recoveryDecision = true
            } catch { self.error = SupportSessionCoordinator.message(for: error) }
        }
    }

    private func resolve(_ change: SupportMemoryChange, keepLocal: Bool) {
        Task {
            do { try await coordinator.repository.resolveMemoryConflict(epoch: coordinator.identity.epochID, id: change.id, keepLocal: keepLocal); retry() }
            catch { self.error = SupportSessionCoordinator.message(for: error) }
        }
    }
    private func refresh() {
        Task {
            do { try await container.supportSync?.refreshMemory() }
            catch { self.error = "Account context could not be refreshed. The last protected snapshot remains available." }
        }
    }
    private func retry() {
        Task {
            do { try await container.supportSync?.retry() }
            catch { self.error = "The change is saved here. Account sync is paused; you can retry when ready." }
        }
    }
}

private struct SupportMemoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    let item: SupportMemoryRecord
    let save: (String) -> Void
    @State private var text: String
    init(item: SupportMemoryRecord, save: @escaping (String) -> Void) {
        self.item = item; self.save = save; _text = State(initialValue: item.content)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Saved context") { TextEditor(text: $text).frame(minHeight: 120) }
                Text("\(text.unicodeScalars.count) / 500 characters").font(.caption)
                Text("The old item stops being used here when you save. Account sync must confirm the correction before personalized AI resumes.")
            }
            .navigationTitle(item.isSuggestion ? "Review suggestion" : "Correct saved context")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(text.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.unicodeScalars.count > 500)
                }
            }
        }
    }
}
