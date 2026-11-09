import Foundation
import Combine
#if canImport(Supabase)
import Supabase
#endif

// MARK: - Unified history (SUPPORT_SESSION_SPEC §5.6, §9.6, AC-30)
//
// Merge + paging for the History screen. This file owns no domain state and no store:
// - the protected local journal (SupportSessionCoordinator.journal) stays the only copy of local session work;
// - cloud session summaries come from SupportSessionSync.loadHistory (adapter below);
// - standalone conversation / exercise / journal references are bounded, owner-bound, keyset reads.
// Nothing here sends a chat message, creates a conversation, attaches a record to a session, or infers a session.
// Titles and text are user content: never log them.

// MARK: - Items

enum SupportHistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all, conversations, activities, savedSteps
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .conversations: return "Conversations"
        case .activities: return "Activities"
        case .savedSteps: return "Saved steps"
        }
    }
}

enum SupportHistoryKind: String, Equatable, Sendable {
    case session, conversation, exercise, journal
}

/// Where a row's status comes from. Never claims a cloud save that has not been confirmed.
enum SupportHistorySync: Equatable, Sendable {
    /// Existing standalone record (its own screen owns its sync story).
    case existingRecord
    case synced
    case waiting
    case deviceOnly
    case needsChoice
    case failed
    /// Session known only from the account list; open it to load it onto this device.
    case accountOnly
    /// The account copy is at a newer revision than this device has installed.
    case newerInAccount
}

struct SupportHistoryItem: Identifiable, Equatable, Sendable {
    let kind: SupportHistoryKind
    let recordID: UUID
    var id: String { "\(kind.rawValue):\(recordID.uuidString.lowercased())" }
    var title: String
    /// Original record date: when it was created/started. Nil only for undated legacy records; never "now".
    var date: Date?
    /// Last change, labeled separately from the original date. Nil when unknown.
    var updatedAt: Date?
    /// Account revision known from the cloud list (nil when the session is not in the loaded account pages).
    var remoteRevision: Int64?
    var status: SupportSessionStatus?
    var isUnfinished = false
    var hasConversation = false
    var hasActivity = false
    var hasSavedStep = false
    var conversationID: UUID?
    var sync: SupportHistorySync
    /// Lowercased text that is explicitly searchable and already on this device (titles, concern, saved step text).
    /// Drafts and activity answers are deliberately never included.
    var searchText = ""
    /// Standalone exercise records only.
    var completed: Bool?
}

struct SupportHistoryGroup: Identifiable, Equatable, Sendable {
    /// Start of the local day in the grouping calendar; nil for undated records.
    let day: Date?
    var items: [SupportHistoryItem]
    var id: String { day.map { String($0.timeIntervalSince1970) } ?? "undated" }
}

// MARK: - Sources

struct SupportHistoryCloudSession: Equatable, Sendable {
    var id: UUID
    var conversationID: UUID?
    var previousSessionID: UUID?
    var title: String
    var status: SupportSessionStatus
    var revision: Int64
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var unfinishedCount: Int
    var selectedActivityKind: SupportActivityKind?
    /// Nil means the server did not supply the metadata (unknown), never zero.
    var activityCount: Int? = nil
    var savedStepCount: Int? = nil
    var canonicalReferences: [SupportCanonicalReference]? = nil
}

struct SupportHistoryCloudSnapshot: Equatable, Sendable {
    var rows: [SupportHistoryCloudSession]
    var hasMore: Bool
}

enum SupportStandaloneKind: String, CaseIterable, Sendable {
    case conversations, exercises, journals
    var historyKind: SupportHistoryKind {
        switch self {
        case .conversations: return .conversation
        case .exercises: return .exercise
        case .journals: return .journal
        }
    }
}

struct SupportStandaloneRecord: Equatable, Sendable {
    var kind: SupportHistoryKind
    var id: UUID
    var title: String?
    var createdAt: Date?
    var updatedAt: Date?
    var completed: Bool?
    var key: String { "\(kind.rawValue):\(id.uuidString.lowercased())" }
}

/// Opaque keyset position (created_at desc, id desc). `createdAt` is the server string verbatim, nil for undated rows.
struct SupportHistoryCursor: Equatable, Sendable {
    var createdAt: String?
    var id: UUID
}

struct SupportStandalonePage: Equatable, Sendable {
    var items: [SupportStandaloneRecord]
    var nextCursor: SupportHistoryCursor?
}

@MainActor
protocol SupportHistoryCloudSource {
    /// `reset == true` restarts from the newest page; otherwise advances the existing cursor.
    func loadPage(reset: Bool) async throws -> SupportHistoryCloudSnapshot
}

@MainActor
protocol SupportHistoryStandaloneSource {
    func loadPage(_ kind: SupportStandaloneKind, after cursor: SupportHistoryCursor?) async throws -> SupportStandalonePage
}

// MARK: - Merge

enum SupportHistoryMerge {
    /// Builds the visible rows. Pure and deterministic: date descending, then id ascending for ties.
    /// - Local protected work is authoritative: a session in the journal wins over its cloud summary unless the
    ///   local copy is fully synced and the account copy is at a newer revision.
    /// - Deleted/tombstoned sessions never appear. Records they referenced stay as standalone rows.
    static func items(
        journal: SupportJournal,
        cloud: [SupportHistoryCloudSession],
        standalone: [SupportStandaloneRecord],
        filter: SupportHistoryFilter = .all,
        query: String = "",
        unfinishedOnly: Bool = false
    ) -> [SupportHistoryItem] {
        var rows: [String: SupportHistoryItem] = [:]
        var claimedConversations = Set<UUID>()
        var claimedExercises = Set<UUID>()
        var claimedJournals = Set<UUID>()

        func claim(_ references: [SupportCanonicalReference]?) {
            for reference in references ?? [] {
                switch reference.kind {
                case .exerciseSession: claimedExercises.insert(reference.id)
                case .journalEntry: claimedJournals.insert(reference.id)
                }
            }
        }

        let activitiesBySession = Dictionary(grouping: journal.activities.values, by: \.sessionID)
        let cloudByID = Dictionary(cloud.map { ($0.id, $0) }, uniquingKeysWith: { _, later in later })
        // An authoritative account deletion hides the identity everywhere. Protected local text for it is retained by
        // the repository until its erasure reconciliation, but it is never presented as current history.
        let deletedInAccount = Set(cloud.filter(\.isDeleted).map(\.id))

        for session in journal.sessions.values
        where session.status != .deleted && journal.tombstones[session.id] == nil && !deletedInAccount.contains(session.id) {
            let activities = activitiesBySession[session.id] ?? []
            let draft = journal.drafts[session.id] ?? ""
            var item = SupportHistoryItem(
                kind: .session, recordID: session.id, title: session.title, date: session.createdAt,
                updatedAt: session.updatedAt, remoteRevision: cloudByID[session.id]?.revision,
                status: session.status,
                isUnfinished: session.status == .open &&
                    (!draft.isEmpty || activities.contains { $0.status.isUnfinished } || session.conversationID != nil),
                hasConversation: session.conversationID != nil,
                hasActivity: !activities.isEmpty,
                hasSavedStep: activities.contains { $0.step?.state == .saved },
                conversationID: session.conversationID,
                sync: localSync(session, journal: journal))
            var text = [session.title, session.concern ?? ""]
            text += activities.compactMap { $0.step?.state == .saved ? $0.step?.actionText : nil }
            item.searchText = fold(text.joined(separator: " "))
            var conversation = session.conversationID
            if let remote = cloudByID[session.id], session.syncStatus == .synced,
               !journal.hasUnresolvedConflict(sessionID: session.id),
               let installed = journal.serverRevisions[session.id], remote.revision > installed {
                // Accepted newer account summary: take its eligible fields, including the flags derived from them.
                item.title = remote.title
                item.updatedAt = remote.updatedAt
                item.status = remote.status
                item.conversationID = remote.conversationID
                item.hasConversation = remote.conversationID != nil
                item.isUnfinished = remote.status == .open && (remote.unfinishedCount > 0 || remote.conversationID != nil)
                if let count = remote.activityCount { item.hasActivity = count > 0 || remote.unfinishedCount > 0 }
                if let saved = remote.savedStepCount { item.hasSavedStep = saved > 0 }
                item.sync = .newerInAccount
                conversation = remote.conversationID
                item.searchText = fold(([remote.title, session.concern ?? ""] + (item.hasSavedStep ? text.dropFirst(2) : [])).joined(separator: " "))
            }
            rows[item.id] = item
            if let conversation { claimedConversations.insert(conversation) }
            claim(cloudByID[session.id]?.canonicalReferences)
            for activity in activities { claim(activity.canonicalReference.map { [$0] }) }
        }

        for remote in cloud where !remote.isDeleted && journal.tombstones[remote.id] == nil
            && journal.sessions[remote.id] == nil {
            let known = remote.activityCount
            var item = SupportHistoryItem(
                kind: .session, recordID: remote.id, title: remote.title, date: remote.createdAt,
                updatedAt: remote.updatedAt, remoteRevision: remote.revision,
                status: remote.status,
                isUnfinished: remote.status == .open && (remote.unfinishedCount > 0 || remote.conversationID != nil),
                hasConversation: remote.conversationID != nil,
                hasActivity: (known ?? 0) > 0 || remote.unfinishedCount > 0 || remote.selectedActivityKind != nil,
                hasSavedStep: (remote.savedStepCount ?? 0) > 0,
                conversationID: remote.conversationID,
                sync: .accountOnly)
            item.searchText = fold(remote.title)
            rows[item.id] = item
            if let conversation = remote.conversationID { claimedConversations.insert(conversation) }
            claim(remote.canonicalReferences)
        }

        for record in standalone {
            switch record.kind {
            case .conversation where claimedConversations.contains(record.id): continue
            case .exercise where claimedExercises.contains(record.id): continue
            case .journal where claimedJournals.contains(record.id): continue
            case .session: continue
            default: break
            }
            let fallback: String
            switch record.kind {
            case .conversation: fallback = "Conversation"
            case .exercise: fallback = "Exercise"
            case .journal: fallback = "Journal entry"
            case .session: fallback = "Session"
            }
            let trimmed = record.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var item = SupportHistoryItem(
                kind: record.kind, recordID: record.id, title: trimmed.isEmpty ? fallback : trimmed,
                date: record.createdAt ?? record.updatedAt, updatedAt: record.updatedAt,
                status: nil, isUnfinished: false,
                hasConversation: record.kind == .conversation,
                hasActivity: record.kind != .conversation,
                hasSavedStep: false,
                conversationID: record.kind == .conversation ? record.id : nil,
                sync: .existingRecord)
            item.completed = record.completed
            item.searchText = fold(item.title)
            rows[item.id] = item
        }

        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return rows.values.filter { item in
            if unfinishedOnly { guard item.kind == .session, item.isUnfinished else { return false } }
            switch filter {
            case .all: break
            case .conversations: guard item.hasConversation else { return false }
            case .activities: guard item.hasActivity else { return false }
            case .savedSteps: guard item.hasSavedStep else { return false }
            }
            return needle.isEmpty || fold(item.title).contains(needle) || item.searchText.contains(needle)
        }.sorted(by: order)
    }

    /// Groups already-ordered items by local day in `calendar`. Every item lands in exactly one group.
    static func groups(_ items: [SupportHistoryItem], calendar: Calendar) -> [SupportHistoryGroup] {
        var result: [SupportHistoryGroup] = []
        for item in items {
            let day = item.date.map { calendar.startOfDay(for: $0) }
            if let index = result.firstIndex(where: { $0.day == day }) { result[index].items.append(item) }
            else { result.append(SupportHistoryGroup(day: day, items: [item])) }
        }
        return result
    }

    static func order(_ a: SupportHistoryItem, _ b: SupportHistoryItem) -> Bool {
        switch (a.date, b.date) {
        case let (x?, y?) where x != y: return x > y
        case (nil, _?): return false
        case (_?, nil): return true
        default: return a.id < b.id
        }
    }

    static func localSync(_ session: SupportSession, journal: SupportJournal) -> SupportHistorySync {
        if journal.hasUnresolvedConflict(sessionID: session.id) { return .needsChoice }
        switch session.syncStatus {
        case .synced: return .synced
        case .pending: return .waiting
        case .localOnly: return .deviceOnly
        case .conflict: return .needsChoice
        case .failed: return .failed
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

// MARK: - Paging / race-safe loader

/// Pages the cloud summaries and standalone records. Local rows are never touched by this type, so a failed or
/// cancelled load can only leave the visible list as it was. Results are applied only if (a) they belong to the
/// current generation and (b) the immutable owner/epoch captured by `isCurrent` still holds.
@MainActor
final class SupportHistoryLoader: ObservableObject {
    enum Source: Hashable, CaseIterable {
        case cloud, conversations, exercises, journals
        var standaloneKind: SupportStandaloneKind? {
            switch self {
            case .cloud: return nil
            case .conversations: return .conversations
            case .exercises: return .exercises
            case .journals: return .journals
            }
        }
    }

    enum Phase: Equatable {
        case idle, loading, failed(String)
    }

    struct State: Equatable {
        var phase: Phase = .idle
        var hasMore = false
        var loadedOnce = false
    }

    @Published private(set) var cloudRows: [SupportHistoryCloudSession] = []
    @Published private(set) var standalone: [SupportStandaloneRecord] = []
    @Published private(set) var states: [Source: State] = Dictionary(uniqueKeysWithValues: Source.allCases.map { ($0, State()) })
    @Published private(set) var isInvalidated = false

    private let cloudSource: (any SupportHistoryCloudSource)?
    private let standaloneSource: (any SupportHistoryStandaloneSource)?
    private let isCurrent: @MainActor () -> Bool
    private var generation = UUID()
    private var tasks: [Source: Task<Void, Never>] = [:]
    private var cursors: [Source: SupportHistoryCursor] = [:]
    private var standaloneByKey: [String: SupportStandaloneRecord] = [:]

    init(cloud: (any SupportHistoryCloudSource)?, standalone: (any SupportHistoryStandaloneSource)?,
         isCurrent: @escaping @MainActor () -> Bool) {
        cloudSource = cloud
        standaloneSource = standalone
        self.isCurrent = isCurrent
    }

    var activeSources: [Source] {
        Source.allCases.filter { $0 == .cloud ? cloudSource != nil : standaloneSource != nil }
    }

    var hasMore: Bool { activeSources.contains { states[$0]?.hasMore == true } }
    var isLoading: Bool { activeSources.contains { states[$0]?.phase == .loading } }
    var failures: [(Source, String)] {
        activeSources.compactMap { source in
            if case .failed(let message) = states[source]?.phase { return (source, message) }
            return nil
        }
    }

    /// Restart every source from its newest page. Rows already shown stay until a new first page replaces them.
    func reset() async {
        guard isCurrent() else { invalidate(); return }
        isInvalidated = false
        let mine = UUID()
        generation = mine
        let previous = Array(tasks.values)
        tasks.removeAll()
        previous.forEach { $0.cancel() }
        for task in previous { await task.value }
        // A newer reset or an owner switch during the wait wins.
        guard mine == generation, isCurrent() else { return }
        await withTaskGroup(of: Void.self) { group in
            for source in activeSources {
                group.addTask { @MainActor in await self.run(source, reset: true, generation: mine) }
            }
        }
    }

    func loadMore(_ source: Source) async {
        guard states[source]?.loadedOnce == true, states[source]?.hasMore == true, isCurrent() else { return }
        await run(source, reset: false, generation: generation)
    }

    func loadMoreAll() async {
        await withTaskGroup(of: Void.self) { group in
            for source in activeSources {
                group.addTask { @MainActor in await self.loadMore(source) }
            }
        }
    }

    /// Owner/epoch ended: drop everything, cancel in-flight work, accept nothing late.
    func invalidate() {
        generation = UUID()
        isInvalidated = true
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        cursors.removeAll()
        standaloneByKey.removeAll()
        cloudRows = []
        standalone = []
        states = Dictionary(uniqueKeysWithValues: Source.allCases.map { ($0, State()) })
    }

    // MARK: Private

    private func run(_ source: Source, reset: Bool, generation gen: UUID) async {
        // A load for this source is already running: ignore a duplicate load-more instead of racing its cursor.
        if tasks[source] != nil { return }
        states[source, default: State()].phase = .loading
        let task = Task { @MainActor in await self.perform(source, reset: reset, generation: gen) }
        tasks[source] = task
        // If the caller (a view's .task / refresh) is cancelled, the load is cancelled with it.
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if tasks[source] == task { tasks[source] = nil }
    }

    private func accepts(_ gen: UUID) -> Bool {
        guard !Task.isCancelled, gen == generation else { return false }
        guard isCurrent() else { invalidate(); return false }
        return true
    }

    private func perform(_ source: Source, reset: Bool, generation gen: UUID) async {
        do {
            if source == .cloud {
                guard let cloudSource else { return }
                let snapshot = try await cloudSource.loadPage(reset: reset)
                guard accepts(gen) else { return settleIfCurrent(source, gen) }
                var seen: [UUID: Int] = [:]
                var rows: [SupportHistoryCloudSession] = []
                for row in snapshot.rows {
                    if let index = seen[row.id] { rows[index] = row } else { seen[row.id] = rows.count; rows.append(row) }
                }
                cloudRows = rows
                states[.cloud] = State(phase: .idle, hasMore: snapshot.hasMore, loadedOnce: true)
            } else if let kind = source.standaloneKind {
                guard let standaloneSource else { return }
                let cursor = reset ? nil : cursors[source]
                let page = try await standaloneSource.loadPage(kind, after: cursor)
                guard accepts(gen) else { return settleIfCurrent(source, gen) }
                if let next = page.nextCursor, next == cursor {
                    throw SupportHistoryLoadError.cursorDidNotAdvance
                }
                if reset {
                    standaloneByKey = standaloneByKey.filter { $0.value.kind != kind.historyKind }
                }
                for item in page.items where item.kind == kind.historyKind { standaloneByKey[item.key] = item }
                standalone = Array(standaloneByKey.values)
                cursors[source] = page.nextCursor
                states[source] = State(phase: .idle, hasMore: page.nextCursor != nil, loadedOnce: true)
            }
        } catch is CancellationError {
            settleIfCurrent(source, gen)
        } catch {
            guard accepts(gen) else { return settleIfCurrent(source, gen) }
            var state = states[source] ?? State()
            state.phase = .failed(Self.message(for: error))
            states[source] = state
        }
    }

    private func settleIfCurrent(_ source: Source, _ gen: UUID) {
        guard gen == generation, !isInvalidated else { return }
        if states[source]?.phase == .loading { states[source]?.phase = .idle }
    }

    static func message(for error: Error) -> String {
        if error is SupportHistoryLoadError { return "History could not be paged safely. Showing what is already loaded." }
        return "Couldn't load more history. Showing what is already available."
    }
}

enum SupportHistoryLoadError: Error, Equatable {
    case cursorDidNotAdvance
}

// MARK: - Detail decisions (pure, so the rules are testable)

enum SupportHistoryContinuation: Equatable, Sendable {
    /// Resume the selected unfinished activity of an open session.
    case resumeActivity(UUID)
    /// Reopen the same Chat. Never creates or sends anything.
    case openConversation(UUID)
    /// Open session without a conversation yet: a blank, editable Chat (the cloud conversation exists only after Send).
    case blankChat
    /// Closed session: a NEW session linked by `previousSessionID`, same scope, with NO conversation reused.
    case startLinkedSession(previousSessionID: UUID, scope: SupportContextScope)

    static func plan(for session: SupportSession, journal: SupportJournal) -> SupportHistoryContinuation {
        guard session.status == .open else {
            return .startLinkedSession(previousSessionID: session.id, scope: session.contextScope)
        }
        if let selected = session.selectedActivityID, let activity = journal.activities[selected],
           activity.sessionID == session.id, activity.status.isUnfinished {
            return .resumeActivity(selected)
        }
        if let conversation = session.conversationID { return .openConversation(conversation) }
        return .blankChat
    }
}

enum SupportHistorySessionRules {
    /// True when closing would stop something: a saved draft or an unfinished activity.
    static func hasUnfinishedWork(_ session: SupportSession, journal: SupportJournal) -> Bool {
        guard session.status == .open else { return false }
        return !(journal.drafts[session.id] ?? "").isEmpty
            || journal.activities.values.contains { $0.sessionID == session.id && $0.status.isUnfinished }
    }

    /// Titles are 1…80 Unicode scalars after trimming (the same unit the server counts).
    static func validatedTitle(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= SupportSessionLimits.titleMaxCharacters else { return nil }
        return trimmed
    }
}

// MARK: - Live adapters (app target only)

#if canImport(Supabase)

/// Pages account session summaries through the existing `SupportSessionSync.loadHistory`. The sync object keeps the
/// accumulated list and cursor; this adapter only reads it after each awaited page and never mutates the journal.
@MainActor
struct SupportSyncHistoryAdapter: SupportHistoryCloudSource {
    let sync: SupportSessionSync

    func loadPage(reset: Bool) async throws -> SupportHistoryCloudSnapshot {
        if reset || sync.hasMoreHistory { try await sync.loadHistory(reset: reset) }
        return SupportHistoryCloudSnapshot(rows: sync.history.map(Self.row), hasMore: sync.hasMoreHistory)
    }

    static func row(_ summary: SupportCloudSessionSummary) -> SupportHistoryCloudSession {
        SupportHistoryCloudSession(
            id: summary.id, conversationID: summary.conversationID, previousSessionID: summary.previousSessionID,
            title: summary.title, status: summary.status, revision: summary.revision,
            createdAt: summary.createdAt, updatedAt: summary.updatedAt,
            isDeleted: summary.status == .deleted || summary.deletedAt != nil,
            unfinishedCount: summary.unfinishedCount,
            selectedActivityKind: summary.selectedActivity?.templateKey.kind,
            activityCount: summary.activityCount, savedStepCount: summary.savedStepCount,
            canonicalReferences: summary.canonicalReferences)
    }
}

/// Bounded (50 per page), owner-bound keyset reads of existing records. Journal content and exercise notes are never
/// selected; only id, title and dates. Owner and epoch are re-proven after every await.
@MainActor
final class SupportLiveHistoryReader: SupportHistoryStandaloneSource {
    private let supabase: SupabaseClient
    private let dataService: SupabaseDataService
    private let owner: OfflineOwnerProof
    private let ownerProof: @Sendable () async -> OfflineOwnerProof?
    private var exerciseTitles: [UUID: String]?

    init(supabase: SupabaseClient, dataService: SupabaseDataService, owner: OfflineOwnerProof,
         ownerProof: @escaping @Sendable () async -> OfflineOwnerProof?) {
        self.supabase = supabase
        self.dataService = dataService
        self.owner = owner
        self.ownerProof = ownerProof
    }

    private static let pageSize = 50

    func loadPage(_ kind: SupportStandaloneKind, after cursor: SupportHistoryCursor?) async throws -> SupportStandalonePage {
        switch kind {
        case .conversations: return try await conversations(after: cursor)
        case .exercises: return try await exercises(after: cursor)
        case .journals: return try await journals(after: cursor)
        }
    }

    private func conversations(after cursor: SupportHistoryCursor?) async throws -> SupportStandalonePage {
        let page = try await dataService.getConversationPage(
            owner: owner,
            cursor: cursor.map { SupportConversationCursor(createdAt: $0.createdAt, id: $0.id) },
            ownerProof: ownerProof)
        let items = page.items.compactMap { conversation -> SupportStandaloneRecord? in
            guard let id = UUID(uuidString: conversation.id) else { return nil }
            let dated = conversation.dateIsKnown != false
            return SupportStandaloneRecord(
                kind: .conversation, id: id, title: conversation.title,
                createdAt: dated ? conversation.createdAt : nil, updatedAt: dated ? conversation.updatedAt : nil)
        }
        return SupportStandalonePage(
            items: items, nextCursor: page.nextCursor.map { SupportHistoryCursor(createdAt: $0.createdAt, id: $0.id) })
    }

    private struct Row: Decodable {
        let id: UUID
        let title: String?
        let exerciseId: UUID?
        let createdAt: String?
        let updatedAt: String?
        let completedAt: String?
        enum CodingKeys: String, CodingKey {
            case id, title
            case exerciseId = "exercise_id", createdAt = "created_at", updatedAt = "updated_at", completedAt = "completed_at"
        }
    }

    private func rows(table: String, columns: String, after cursor: SupportHistoryCursor?) async throws -> [Row] {
        guard await ownerProof() == owner else { throw CancellationError() }
        var query = supabase.from(table).select(columns).eq("user_id", value: owner.userId)
        if let cursor {
            if let date = cursor.createdAt {
                guard date.utf8.count <= 64, SupportChatTimestamp.date(date) != nil else { throw DataError.invalidId }
                query = query.or("created_at.lt.\(date),and(created_at.eq.\(date),id.lt.\(cursor.id.uuidString)),created_at.is.null")
            } else {
                query = query.is("created_at", value: nil).lt("id", value: cursor.id)
            }
        }
        let rows: [Row] = try await query.order("created_at", ascending: false, nullsFirst: false)
            .order("id", ascending: false).limit(Self.pageSize).execute().value
        guard await ownerProof() == owner, !Task.isCancelled else { throw CancellationError() }
        guard Set(rows.map(\.id)).count == rows.count else { throw SupportHistoryLoadError.cursorDidNotAdvance }
        return rows
    }

    private func next(_ rows: [Row], after cursor: SupportHistoryCursor?) throws -> SupportHistoryCursor? {
        guard rows.count == Self.pageSize, let last = rows.last else { return nil }
        let next = SupportHistoryCursor(createdAt: last.createdAt, id: last.id)
        guard next != cursor else { throw SupportHistoryLoadError.cursorDidNotAdvance }
        return next
    }

    private func journals(after cursor: SupportHistoryCursor?) async throws -> SupportStandalonePage {
        let page = try await rows(table: "journal_entries", columns: "id,title,created_at,updated_at", after: cursor)
        let items = page.map { row in
            let created = row.createdAt.flatMap(SupportChatTimestamp.date)
            return SupportStandaloneRecord(kind: .journal, id: row.id, title: row.title, createdAt: created,
                                           updatedAt: row.updatedAt.flatMap(SupportChatTimestamp.date) ?? created)
        }
        return SupportStandalonePage(items: items, nextCursor: try next(page, after: cursor))
    }

    private func exercises(after cursor: SupportHistoryCursor?) async throws -> SupportStandalonePage {
        let page = try await rows(table: Tables.exerciseSessions, columns: "id,exercise_id,created_at,completed_at", after: cursor)
        if exerciseTitles == nil {
            // Existing catalog read; a failure only means rows fall back to a generic "Exercise" title.
            let catalog = (try? await dataService.getExercises()) ?? []
            guard await ownerProof() == owner else { throw CancellationError() }
            exerciseTitles = Dictionary(catalog.compactMap { item in UUID(uuidString: item.id).map { ($0, item.title) } },
                                        uniquingKeysWith: { first, _ in first })
        }
        let items = page.map { row in
            let created = row.createdAt.flatMap(SupportChatTimestamp.date)
            return SupportStandaloneRecord(
                kind: .exercise, id: row.id, title: row.exerciseId.flatMap { exerciseTitles?[$0] },
                createdAt: created, updatedAt: row.completedAt.flatMap(SupportChatTimestamp.date) ?? created,
                completed: row.completedAt != nil)
        }
        return SupportStandalonePage(items: items, nextCursor: try next(page, after: cursor))
    }
}

#endif
