import SwiftUI

// Unified History (SUPPORT_SESSION_SPEC §5.6, §9.6, AC-30).
// Reads the protected local journal through the coordinator and pages account summaries through the existing sync.
// It never creates a conversation, sends a message, or attaches a record to a session. No paywall appears here.

/// Owns the loader for one immutable owner + account epoch. A different owner/epoch builds a new loader and the
/// old one is invalidated, so a late page can never appear under another account.
@MainActor
private final class SupportHistoryModel: ObservableObject {
    @Published private(set) var loader: SupportHistoryLoader?
    private var scope: Scope?

    struct Scope: Hashable {
        let identity: SupportSessionIdentity
        /// The exact coordinator instance: a same-owner replacement is a different scope.
        let coordinatorID: ObjectIdentifier
        /// The exact sync object (nil when account sync is unavailable).
        let syncID: ObjectIdentifier?
        let accountEpoch: UInt64
        let includeStandalone: Bool
    }

    func configure(_ scope: Scope, coordinator: SupportSessionCoordinator, appState: AppState,
                   container: DependencyContainer) {
        guard self.scope != scope else { return }
        loader?.invalidate()
        self.scope = scope
        let ownerID = scope.identity.ownerID
        let epoch = scope.accountEpoch
        let coordinatorID = scope.coordinatorID
        let syncID = scope.syncID
        let isCurrent: @MainActor () -> Bool = { [weak appState, weak container, weak coordinator] in
            guard let appState, let container, let coordinator else { return false }
            return appState.authState == .authenticated && appState.currentUser?.id == ownerID
                && appState.accountEpoch == epoch && container.supabaseAuthService.userId == ownerID
                && container.supportSessionCoordinator === coordinator
                && ObjectIdentifier(coordinator) == coordinatorID && coordinator.identity == scope.identity
                && container.supportSync.map(ObjectIdentifier.init) == syncID
        }
        let cloud = container.supportSync.map { SupportSyncHistoryAdapter(sync: $0) }
        var standalone: SupportLiveHistoryReader?
        if scope.includeStandalone {
            let owner = OfflineOwnerProof(userId: ownerID, epoch: epoch)
            standalone = SupportLiveHistoryReader(
                supabase: container.supabaseClient, dataService: container.supabaseDataService, owner: owner,
                ownerProof: { [weak appState, weak container] in
                    await MainActor.run {
                        // App owner, auth service owner and the SDK session owner must all still be this account.
                        guard let appState, let container, appState.currentUser?.id == ownerID,
                              appState.accountEpoch == epoch, container.supabaseAuthService.userId == ownerID,
                              container.supabaseClient.auth.currentSession?.user.id == ownerID else { return nil }
                        return owner
                    }
                })
        }
        loader = SupportHistoryLoader(cloud: cloud, standalone: standalone, isCurrent: isCurrent)
    }
}

struct SupportHistoryView: View {
    var unfinishedOnly: Bool = false

    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var model = SupportHistoryModel()

    private var scope: SupportHistoryModel.Scope {
        .init(identity: coordinator.identity, coordinatorID: ObjectIdentifier(coordinator),
              syncID: container.supportSync.map(ObjectIdentifier.init), accountEpoch: appState.accountEpoch,
              includeStandalone: !unfinishedOnly)
    }

    var body: some View {
        Group {
            if let loader = model.loader {
                SupportHistoryContent(loader: loader, unfinishedOnly: unfinishedOnly)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: scope) {
            model.configure(scope, coordinator: coordinator, appState: appState, container: container)
            await model.loader?.reset()
        }
    }
}

private struct SupportHistoryContent: View {
    @ObservedObject var loader: SupportHistoryLoader
    let unfinishedOnly: Bool

    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var filter = SupportHistoryFilter.all
    @State private var query = ""
    @State private var error: String?

    private var items: [SupportHistoryItem] {
        SupportHistoryMerge.items(journal: coordinator.journal, cloud: loader.cloudRows, standalone: loader.standalone,
                                  filter: filter, query: query, unfinishedOnly: unfinishedOnly)
    }

    var body: some View {
        let groups = SupportHistoryMerge.groups(items, calendar: .current)
        List {
            removalFailures
            if !unfinishedOnly { filterSection }
            statusSection
            if groups.isEmpty {
                Section { emptyState }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.items) { item in row(item) }
                } header: {
                    if let day = group.day {
                        Text(day, format: .dateTime.weekday(.wide).month().day().year())
                    } else {
                        Text("Undated")
                    }
                }
            }
            if loader.hasMore {
                Section {
                    Button {
                        Task { await loader.loadMoreAll() }
                    } label: {
                        HStack {
                            Text("Load older")
                            if loader.isLoading { Spacer(); ProgressView() }
                        }
                        .frame(minHeight: SupportTheme.minimumTarget)
                    }
                    .disabled(loader.isLoading)
                }
            }
            if let error { Section { Label(error, systemImage: "exclamationmark.circle") } }
        }
        .supportCanvas()
        .navigationTitle(unfinishedOnly ? "Unfinished sessions" : "History")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search titles and saved steps"))
        .refreshable { await loader.reset() }
    }

    // MARK: Sections

    @ViewBuilder
    private var removalFailures: some View {
        ForEach(coordinator.journal.failures.filter { $0.kind == .deleteSession }, id: \.operationID) { failure in
            Section("Session removal needs attention") {
                Text("The session was removed from this device. Its account copy has not been confirmed removed.")
                Button("Try removing the account copy again") {
                    Task {
                        do { try await coordinator.retryDeletion(failure.sessionID) }
                        catch { self.error = SupportSessionCoordinator.message(for: error) }
                    }
                }
                .frame(minHeight: SupportTheme.minimumTarget)
            }
        }
    }

    private var filterSection: some View {
        Section {
            if typeSize.isAccessibilitySize {
                Picker("Show", selection: $filter) {
                    ForEach(SupportHistoryFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            } else {
                Picker("Show", selection: $filter) {
                    ForEach(SupportHistoryFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var statusSection: some View {
        Section {
            Label("Saved on this device", systemImage: "iphone")
            ForEach(Array(loader.failures.enumerated()), id: \.offset) { _, failure in
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Label(failure.1, systemImage: "exclamationmark.circle")
                    Button("Try again") { Task { await loader.reset() } }
                        .frame(minHeight: SupportTheme.minimumTarget)
                }
            }
            if loader.activeSources.isEmpty {
                Label("Account history isn't available right now.", systemImage: "icloud.slash")
            } else if loader.isLoading {
                HStack { ProgressView(); Text("Loading account history…").padding(.leading, 8) }
                    .accessibilityElement(children: .combine)
            }
        } footer: {
            Text(unfinishedOnly
                 ? "Older unfinished sessions in your account appear after you choose Load older."
                 : "Search covers titles and saved steps on this device. Account-only sessions are matched by title and by the activity and saved-step counts your account reports.")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if loader.isLoading {
            Text("Loading…")
        } else if !query.trimmingCharacters(in: .whitespaces).isEmpty || filter != .all {
            Text("Nothing here matches. Change the filter or search to see more.")
        } else if unfinishedOnly {
            Text("You have no unfinished sessions.")
        } else {
            Text("Your conversations and activities will appear here.")
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ item: SupportHistoryItem) -> some View {
        switch item.kind {
        case .session:
            NavigationLink { SupportHistoryDetailView(sessionID: item.recordID, accountRevision: item.remoteRevision) } label: { SupportHistoryRowLabel(item: item) }
        case .journal:
            NavigationLink { JournalDetailView(entryId: item.recordID.uuidString) } label: { SupportHistoryRowLabel(item: item) }
        case .conversation:
            Button {
                appState.selectedTab = .chat
                deepLinkRouter.handleRoute(.chat(conversationId: item.recordID.uuidString), appState: appState)
            } label: { SupportHistoryRowLabel(item: item) }
            .buttonStyle(.plain)
        case .exercise:
            // The app has no detail screen for a finished exercise record, so this row is informational only.
            SupportHistoryRowLabel(item: item)
        }
    }
}

private struct SupportHistoryRowLabel: View {
    let item: SupportHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
            Text(item.title).font(.body).foregroundStyle(SupportTheme.textPrimary)
            Text(detailLine).font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
            if let date = item.date {
                Text(date, format: .dateTime.month().day().year().hour().minute())
                    .font(.footnote).foregroundStyle(SupportTheme.textSecondary)
            }
            if item.kind == .session, let updated = item.updatedAt, let created = item.date,
               updated.timeIntervalSince(created) > 60 {
                Text("Updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote).foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .frame(minHeight: SupportTheme.minimumTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var detailLine: String {
        switch item.kind {
        case .session:
            let state = item.status == .closed ? "Closed" : (item.isUnfinished ? "Open · unfinished" : "Open")
            return "Session · \(state) · \(SupportHistoryText.sync(item.sync))"
        case .conversation: return "Conversation"
        case .exercise: return item.completed == true ? "Exercise · Completed" : "Exercise · Started"
        case .journal: return "Journal entry"
        }
    }
}

enum SupportHistoryText {
    static func outcome(_ value: SupportReflectionOutcome) -> String {
        switch value {
        case .helpful: return "Helpful"
        case .notForMe: return "Not for me"
        case .notSure: return "Not sure"
        case .skip: return "Skipped"
        }
    }

    static func stepState(_ state: SupportStepState) -> String {
        switch state {
        case .draft: return "Suggested step · not saved"
        case .saved: return "Saved for later"
        case .selfReportedDone: return "Done · self-reported"
        case .dismissed: return "Not now"
        }
    }

    static func activityStatus(_ status: SupportActivityStatus) -> String {
        switch status {
        case .ready: return "Ready"
        case .inProgress: return "In progress"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .stopped: return "Stopped"
        }
    }

    static func result(_ result: SupportActivityResult) -> String {
        var parts: [String] = []
        if result.acknowledgedStepCount > 0 { parts.append("\(result.acknowledgedStepCount) steps done") }
        if result.skippedStepCount > 0 { parts.append("\(result.skippedStepCount) skipped") }
        let minutes = Int(result.activeMilliseconds / 60_000)
        if minutes > 0 { parts.append("about \(minutes) min") }
        if let reason = result.stoppedReason {
            switch reason {
            case "skipped_all": parts.append("every prompt skipped")
            case "user_ended": parts.append("ended by you")
            case "discarded": parts.append("discarded")
            case "session_closed": parts.append("ended when the session closed")
            case "replaced": parts.append("replaced by another activity")
            default: parts.append("ended")
            }
        }
        return parts.isEmpty ? "No details recorded" : parts.joined(separator: " · ")
    }

    static func event(_ event: SupportSessionEvent) -> String {
        switch event.kind {
        case .sessionCreated: return "Session started"
        case .sessionRenamed: return "Renamed"
        case .scopeChanged: return "Context choice changed"
        case .sessionClosed: return "Session closed"
        case .activityStarted: return "Activity started"
        case .checkpointSaved: return "Progress saved"
        case .activityPaused: return "Activity paused"
        case .activityResumed: return "Activity resumed"
        case .activityCompleted: return "Activity completed"
        case .activityStopped: return "Activity stopped"
        case .activityDiscarded: return "Answers discarded"
        case .stepSaved: return "Next step saved"
        case .reflected: return "Reflection recorded"
        }
    }

    /// Precise, never optimistic: "synced" only when the journal says so.
    static func sync(_ state: SupportHistorySync) -> String {
        switch state {
        case .existingRecord: return "Existing record"
        case .synced: return "Saved to your account"
        case .waiting: return "On this device · waiting to sync"
        case .deviceOnly: return "On this device only"
        case .needsChoice: return "Needs a choice · saved on this device"
        case .failed: return "Sync failed · saved on this device"
        case .accountOnly: return "In your account · open to load"
        case .newerInAccount: return "Newer in your account · open to refresh"
        }
    }
}

// MARK: - Detail

struct SupportHistoryDetailView: View {
    let sessionID: UUID
    /// Account revision shown by the list for this session, if the list had it. Used only to decide whether to
    /// refresh an installed copy; the refresh itself goes through the existing sync.
    var accountRevision: Int64? = nil

    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @Environment(\.dismiss) private var dismiss
    @State private var isLoadingRemote = false
    @State private var loadError: String?
    @State private var notice: String?
    @State private var actionError: String?
    @State private var isWorking = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showClose = false
    @State private var showDelete = false
    @State private var showContext = false
    @State private var loadAttempt = UUID()

    private var session: SupportSession? { coordinator.journal.sessions[sessionID] }

    /// Everything that must still be true before a late result may publish state or navigate.
    private struct Guard {
        let coordinator: SupportSessionCoordinator
        let identity: SupportSessionIdentity
        let epoch: UInt64
        let sync: SupportSessionSync?
    }

    private func capture() -> Guard {
        Guard(coordinator: coordinator, identity: coordinator.identity, epoch: appState.accountEpoch, sync: container.supportSync)
    }

    private func holds(_ g: Guard) -> Bool {
        !Task.isCancelled && coordinator === g.coordinator && coordinator.identity == g.identity
            && appState.authState == .authenticated && appState.currentUser?.id == g.identity.ownerID
            && appState.accountEpoch == g.epoch && container.supabaseAuthService.userId == g.identity.ownerID
            && container.supportSessionCoordinator === g.coordinator && container.supportSync === g.sync
    }

    var body: some View {
        List {
            if let session {
                sessionSections(session)
            } else if isLoadingRemote {
                Section { HStack { ProgressView(); Text("Loading from your account…").padding(.leading, 8) } }
            } else {
                Section {
                    SupportUnavailableState(
                        title: "Session unavailable",
                        message: loadError ?? "This session isn't on this device or in your account. It may have been deleted.",
                        actionTitle: loadError == nil ? "Back to History" : "Try again",
                        action: { if loadError == nil { dismiss() } else { loadAttempt = UUID() } })
                }
            }
            if let notice { Section { Label(notice, systemImage: "info.circle") } }
            if let loadError, session != nil { Section { Label(loadError, systemImage: "exclamationmark.circle") } }
            if let message = actionError { Section { Label(message, systemImage: "exclamationmark.circle") } }
            if let message = coordinator.localSaveError { Section { Label(message, systemImage: "exclamationmark.circle") } }
        }
        .disabled(isWorking)
        .supportCanvas()
        .navigationTitle(session?.title ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadAttempt) { await refreshIfNeeded() }
        .sheet(isPresented: $showContext) { SupportContextView(sessionID: sessionID, receipt: nil) }
        .alert("Rename session", isPresented: $showRename) {
            TextField("Title", text: $renameText)
            Button("Save") { rename() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Up to \(SupportSessionLimits.titleMaxCharacters) characters.") }
        .alert("Close this session?", isPresented: $showClose) {
            Button("Save and leave") { run(leaveAfter: true) { try await coordinator.doneForNow(sessionID) } }
            Button("End unfinished work and close", role: .destructive) { run { try await closeSession(sessionID) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saving keeps unfinished work waiting. Ending stops or dismisses it; it is not marked completed.")
        }
        .alert("Delete this session?", isPresented: $showDelete) {
            Button("Delete session", role: .destructive) {
                run(leaveAfter: true) { try await coordinator.delete(sessionID) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the session, its saved steps and its activity notes from this device and, once synced, your account. A conversation, exercise record or journal entry connected to it is a separate record: it stays in its own history until you delete it there.")
        }
    }

    // MARK: Content

    @ViewBuilder
    private func sessionSections(_ session: SupportSession) -> some View {
        let sync = SupportHistoryMerge.localSync(session, journal: coordinator.journal)
        Section {
            Text(session.status == .closed ? "Closed session" : "Open session")
            Text(SupportHistoryText.sync(sync))
            Text("Started \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
            Text("Last changed \(session.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
            if let closed = session.closedAt {
                Text("Closed \(closed.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
            }
            if let previous = session.previousSessionID {
                if coordinator.journal.sessions[previous] != nil {
                    NavigationLink("Continued from an earlier session") { SupportHistoryDetailView(sessionID: previous) }
                } else {
                    Text("Continued from an earlier session")
                }
            }
        }

        if let concern = session.concern?.trimmingCharacters(in: .whitespacesAndNewlines), !concern.isEmpty {
            Section("What you brought") { Text(concern) }
        }

        Section {
            Button(continueTitle(session)) { continueSession(session) }
                .frame(minHeight: SupportTheme.minimumTarget)
            if let conversation = session.conversationID {
                if session.status == .open {
                    Button("Open conversation") { openConversation(conversation, guard: capture()) }
                        .frame(minHeight: SupportTheme.minimumTarget)
                } else {
                    NavigationLink("View conversation (read only)") {
                        SupportReadOnlyConversationView(conversationID: conversation, title: session.title)
                    }
                    .frame(minHeight: SupportTheme.minimumTarget)
                }
            }
            Button("Context") { showContext = true }.frame(minHeight: SupportTheme.minimumTarget)
            Button("Rename") { renameText = session.title; showRename = true }.frame(minHeight: SupportTheme.minimumTarget)
            if session.status == .open {
                Button("Close session") { requestClose(session) }.frame(minHeight: SupportTheme.minimumTarget)
            }
            Button("Delete", role: .destructive) { showDelete = true }.frame(minHeight: SupportTheme.minimumTarget)
        }

        ForEach(coordinator.journal.activities(in: sessionID)) { activity in
            Section(activity.templateKey.title) { activityRows(activity, session: session) }
        }

        Section("Timeline") {
            let events = coordinator.journal.events(for: sessionID)
            if events.isEmpty { Text("No activity recorded yet.") }
            ForEach(events) { event in
                HStack {
                    Text(SupportHistoryText.event(event))
                    Spacer()
                    Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote).foregroundStyle(SupportTheme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func activityRows(_ activity: SupportActivity, session: SupportSession) -> some View {
        Text(SupportHistoryText.activityStatus(activity.status))
        if let result = activity.result {
            Text(SupportHistoryText.result(result)).font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
        }
        if let step = activity.step {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(SupportHistoryText.stepState(step.state)).font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
                if !step.actionText.isEmpty { Text(step.actionText) }
                if let confirmed = step.confirmedAt {
                    Text(confirmed.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote).foregroundStyle(SupportTheme.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
        if let reflection = activity.reflection {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text("Your reflection: \(SupportHistoryText.outcome(reflection.outcome))")
                if let note = reflection.note, !note.isEmpty { Text(note) }
                Text(reflection.recordedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote).foregroundStyle(SupportTheme.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
        if let reference = activity.canonicalReference, reference.kind == .journalEntry {
            NavigationLink("Open journal entry") { JournalDetailView(entryId: reference.id.uuidString) }
        }
        if activity.status.isUnfinished, session.status == .open {
            Button("Continue") { resume(activity, session: session) }.frame(minHeight: SupportTheme.minimumTarget)
        }
    }

    private func continueTitle(_ session: SupportSession) -> String {
        switch SupportHistoryContinuation.plan(for: session, journal: coordinator.journal) {
        case .resumeActivity: return "Continue activity"
        case .openConversation: return "Continue conversation"
        case .blankChat: return "Continue in Chat"
        case .startLinkedSession: return "Continue as a new session"
        }
    }

    // MARK: Commands (all through the coordinator; every failure is shown)

    private func continueSession(_ session: SupportSession) {
        let g = capture()
        run {
            switch SupportHistoryContinuation.plan(for: session, journal: coordinator.journal) {
            case .resumeActivity(let id):
                try coordinator.selectSession(session.id)
                try await coordinator.resume(id, origin: session.conversationID.map { .chat(conversationID: $0) } ?? .today)
            case .openConversation(let conversation):
                try coordinator.selectSession(session.id)
                openConversation(conversation, guard: g)
            case .blankChat:
                try coordinator.selectSession(session.id)
                guard holds(g) else { return }
                appState.selectedTab = .chat
                appState.shouldOpenNewChat = true
            case .startLinkedSession(let previous, let scope):
                // A new session; the old conversation is not reused. The blank Chat creates a conversation only
                // when a message is deliberately sent.
                let next = try await coordinator.createSession(conversationID: nil, previousSessionID: previous, scope: scope)
                guard holds(g) else { return }
                try coordinator.selectSession(next.id)
                appState.selectedTab = .chat
                appState.shouldOpenNewChat = true
            }
        }
    }

    private func openConversation(_ id: UUID, guard g: Guard) {
        guard holds(g) else { return }
        appState.selectedTab = .chat
        deepLinkRouter.handleRoute(.chat(conversationId: id.uuidString), appState: appState)
    }

    private func resume(_ activity: SupportActivity, session: SupportSession) {
        run {
            try coordinator.selectSession(session.id)
            try await coordinator.resume(activity.id, origin: session.conversationID.map { .chat(conversationID: $0) } ?? .today)
        }
    }

    private func closeSession(_ id: UUID) async throws {
        try await coordinator.close(id)
        appState.celebrateCompletion(String(localized: "Session closed"), soft: true)
    }

    private func requestClose(_ session: SupportSession) {
        if SupportHistorySessionRules.hasUnfinishedWork(session, journal: coordinator.journal) {
            showClose = true
        } else {
            run { try await closeSession(session.id) }
        }
    }

    private func rename() {
        guard let title = SupportHistorySessionRules.validatedTitle(renameText) else {
            actionError = "Use between 1 and \(SupportSessionLimits.titleMaxCharacters) characters for the title."
            return
        }
        run { try await coordinator.rename(sessionID, title: title) }
    }

    /// `leaveAfter` pops this screen only after the coordinator's durable acknowledgement and only if the same
    /// coordinator/owner/epoch is still current.
    private func run(leaveAfter: Bool = false, _ body: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        actionError = nil
        let g = capture()
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await body()
                if leaveAfter, holds(g) { dismiss() }
            }
            catch is CancellationError { }
            catch { if holds(g) { actionError = SupportSessionCoordinator.message(for: error) } }
        }
    }

    /// Install or refresh the session through the existing sync (its conflict and privacy rules stay authoritative).
    /// Missing => load. Installed but the list showed a newer account revision => refresh, but only when the local
    /// copy has no unsent work; otherwise local changes sync first and are never overwritten here.
    private func refreshIfNeeded() async {
        let g = capture()
        let local = coordinator.journal.sessions[sessionID]
        if coordinator.journal.tombstones[sessionID] != nil { return }
        if let local {
            guard let accountRevision,
                  let installed = coordinator.journal.serverRevisions[sessionID], accountRevision > installed else { return }
            guard local.syncStatus == .synced, !coordinator.journal.hasUnresolvedConflict(sessionID: sessionID) else {
                notice = "A newer copy is in your account. Your changes on this device sync first; nothing here is overwritten."
                return
            }
        }
        guard let sync = g.sync else {
            loadError = "Account sync isn't available right now, so this session can't be loaded."
            return
        }
        isLoadingRemote = local == nil
        loadError = nil
        defer { isLoadingRemote = false }
        do {
            try await sync.refreshSession(sessionID)
            guard holds(g) else { return }
            try await coordinator.refreshJournal()
            guard holds(g) else { return }
            notice = nil
        } catch is CancellationError {
            return
        } catch {
            guard holds(g) else { return }
            loadError = "Couldn't load this session from your account. Check your connection and try again."
        }
    }
}

// MARK: - Read-only conversation (closed sessions stay inspectable)

/// Presentation only: loads the conversation through the existing owner-checked reader and shows the original
/// messages, roles and dates. No composer, no attach, no model call, no new session.
struct SupportReadOnlyConversationView: View {
    let conversationID: UUID
    let title: String

    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var appState: AppState
    @State private var messages: [Message] = []
    @State private var phase = Phase.loading
    @State private var attempt = UUID()

    private enum Phase: Equatable { case loading, loaded, failed }

    var body: some View {
        List {
            switch phase {
            case .loading:
                Section { HStack { ProgressView(); Text("Loading conversation…").padding(.leading, 8) } }
            case .failed:
                Section {
                    SupportUnavailableState(
                        title: "Couldn't load the conversation",
                        message: "It may have been deleted, or you may be offline. The session itself is unchanged.",
                        actionTitle: "Try again", action: { attempt = UUID() })
                }
            case .loaded:
                if messages.isEmpty {
                    Section { Text("There are no messages to show.") }
                } else {
                    Section {
                        ForEach(messages) { message in
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                MessageBubble(message: message)
                                Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.footnote).foregroundStyle(SupportTheme.textSecondary)
                            }
                            .listRowSeparator(.hidden)
                        }
                    } footer: {
                        Text("Read only. Showing up to the latest 100 messages. Use “Continue as a new session” to talk about it again.")
                    }
                }
            }
        }
        .supportCanvas()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: attempt) { await load() }
    }

    private func load() async {
        guard let ownerID = appState.currentUser?.id else { phase = .failed; return }
        let epoch = appState.accountEpoch
        phase = .loading
        do {
            let loaded = try await container.chatService.getMessages(conversationId: conversationID.uuidString, limit: 100)
            guard !Task.isCancelled, appState.currentUser?.id == ownerID, appState.accountEpoch == epoch,
                  container.supabaseAuthService.userId == ownerID else { return }
            messages = loaded
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, appState.currentUser?.id == ownerID, appState.accountEpoch == epoch else { return }
            phase = .failed
        }
    }
}
