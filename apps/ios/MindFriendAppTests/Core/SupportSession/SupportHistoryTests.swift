import XCTest
#if canImport(MindFriendApp)
@testable import MindFriendApp
#endif

/// Synthetic data only. Exercises the real merge, paging and race-guard code with injected sources.
@MainActor
final class SupportHistoryTests: XCTestCase {
    private let owner = UUID()
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Builders

    private func session(_ n: Int, status: SupportSessionStatus = .open, sync: SupportSyncStatus = .synced,
                         conversation: UUID? = nil, updated: Date? = nil, title: String? = nil,
                         concern: String? = nil) -> SupportSession {
        SupportSession(id: uuid(n), ownerID: owner, conversationID: conversation, previousSessionID: nil,
                       selectedActivityID: nil, title: title ?? "Session \(n)", concern: concern, status: status,
                       contextScope: .conversationOnly, localRevision: 1, syncStatus: sync,
                       createdAt: updated ?? base, updatedAt: updated ?? base, closedAt: nil)
    }

    private func activity(_ n: Int, in sessionID: UUID, status: SupportActivityStatus = .paused,
                          step: SupportStepPayload? = nil, reference: SupportCanonicalReference? = nil) -> SupportActivity {
        SupportActivity(id: uuid(1_000 + n), sessionID: sessionID, templateKey: .groundPresentV1, templateVersion: 1,
                        status: status, canonicalReference: reference, checkpoint: .empty, step: step,
                        activeMilliseconds: 0, result: nil, reflection: nil, lastChangedRevision: 1,
                        syncStatus: .synced, createdAt: base, updatedAt: base, finishedAt: nil)
    }

    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    private func cloud(_ n: Int, updated: Date? = nil, revision: Int64 = 1, status: SupportSessionStatus = .open,
                       deleted: Bool = false, conversation: UUID? = nil, unfinished: Int = 0, created: Date? = nil,
                       activities: Int? = nil, savedSteps: Int? = nil,
                       references: [SupportCanonicalReference]? = nil) -> SupportHistoryCloudSession {
        SupportHistoryCloudSession(id: uuid(n), conversationID: conversation, previousSessionID: nil, title: "Cloud \(n)",
                                   status: status, revision: revision, createdAt: created ?? updated ?? base,
                                   updatedAt: updated ?? base,
                                   isDeleted: deleted, unfinishedCount: unfinished, selectedActivityKind: nil,
                                   activityCount: activities, savedStepCount: savedSteps, canonicalReferences: references)
    }

    private func journal(_ sessions: [SupportSession] = [], activities: [SupportActivity] = []) -> SupportJournal {
        var journal = SupportJournal(ownerID: owner)
        for s in sessions { journal.sessions[s.id] = s }
        for a in activities { journal.activities[a.id] = a }
        return journal
    }

    private func items(_ journal: SupportJournal, cloud: [SupportHistoryCloudSession] = [],
                       standalone: [SupportStandaloneRecord] = [], filter: SupportHistoryFilter = .all,
                       query: String = "", unfinishedOnly: Bool = false) -> [SupportHistoryItem] {
        SupportHistoryMerge.items(journal: journal, cloud: cloud, standalone: standalone, filter: filter,
                                  query: query, unfinishedOnly: unfinishedOnly)
    }

    // MARK: Fakes

    /// Mimics SupportSessionSync: the page source accumulates; reset restarts at page 0.
    private final class FakeCloud: SupportHistoryCloudSource {
        var pages: [[SupportHistoryCloudSession]]
        var loaded: [SupportHistoryCloudSession] = []
        var next = 0
        var calls: [Bool] = []
        var error: Error?
        /// Called on entry; may suspend to hold a request in flight.
        var gate: ((Int) async -> Void)?

        init(pages: [[SupportHistoryCloudSession]]) { self.pages = pages }

        func loadPage(reset: Bool) async throws -> SupportHistoryCloudSnapshot {
            calls.append(reset)
            let call = calls.count
            await gate?(call)
            if let error { throw error }
            if reset { loaded = []; next = 0 }
            if next < pages.count { loaded += pages[next]; next += 1 }
            return SupportHistoryCloudSnapshot(rows: loaded, hasMore: next < pages.count)
        }
    }

    private final class FakeStandalone: SupportHistoryStandaloneSource {
        var records: [SupportStandaloneKind: [SupportStandaloneRecord]] = [:]
        var pageSize = 50
        var calls: [(SupportStandaloneKind, SupportHistoryCursor?)] = []
        var stuckCursor = false
        var failKind: SupportStandaloneKind?

        func loadPage(_ kind: SupportStandaloneKind, after cursor: SupportHistoryCursor?) async throws -> SupportStandalonePage {
            calls.append((kind, cursor))
            if failKind == kind { throw URLError(.notConnectedToInternet) }
            let all = records[kind] ?? []
            let start = cursor.flatMap { c in all.firstIndex { $0.id == c.id }.map { $0 + 1 } } ?? 0
            let slice = Array(all[min(start, all.count)..<min(start + pageSize, all.count)])
            var nextCursor = start + pageSize < all.count ? slice.last.map { SupportHistoryCursor(createdAt: nil, id: $0.id) } : nil
            if stuckCursor, let cursor { nextCursor = cursor }
            return SupportStandalonePage(items: slice, nextCursor: nextCursor)
        }
    }

    private func standalone(_ kind: SupportHistoryKind, _ n: Int, title: String? = nil, at date: Date? = nil) -> SupportStandaloneRecord {
        SupportStandaloneRecord(kind: kind, id: uuid(100_000 + (kind == .conversation ? 0 : kind == .exercise ? 10_000 : 20_000) + n),
                                title: title, createdAt: date, updatedAt: date)
    }

    // MARK: Merge rules

    func testLocalUnsyncedWorkBeatsCloudSummaryAndCloudOnlyRowsAreAdded() {
        let local = session(1, sync: .pending, updated: base.addingTimeInterval(10), title: "Local title")
        let synced = session(2, sync: .synced, title: "Synced local")
        let merged = items(journal([local, synced]), cloud: [
            cloud(1, updated: base.addingTimeInterval(500), revision: 99),   // would win if it ignored local work
            cloud(2, revision: 1), cloud(3)])
        XCTAssertEqual(merged.first { $0.recordID == uuid(1) }?.title, "Local title")
        XCTAssertEqual(merged.first { $0.recordID == uuid(1) }?.sync, .waiting)
        XCTAssertEqual(merged.first { $0.recordID == uuid(2) }?.sync, .synced)
        XCTAssertEqual(merged.first { $0.recordID == uuid(3) }?.sync, .accountOnly)
        XCTAssertEqual(merged.count, 3)
    }

    func testFullySyncedLocalSessionShowsNewerAccountRevision() {
        var j = journal([session(1, sync: .synced, title: "Old")])
        j.serverRevisions[uuid(1)] = 3
        let merged = items(j, cloud: [cloud(1, updated: base.addingTimeInterval(60), revision: 4, status: .closed)])
        XCTAssertEqual(merged.first?.sync, .newerInAccount)
        XCTAssertEqual(merged.first?.title, "Cloud 1")
        XCTAssertEqual(merged.first?.status, .closed)
        j.serverRevisions[uuid(1)] = 4
        XCTAssertEqual(items(j, cloud: [cloud(1, revision: 4)]).first?.sync, .synced)
    }

    func testDeletedAndTombstonedSessionsNeverAppearButTheirConversationDoes() {
        let conversation = uuid(777)
        var j = journal([session(1, status: .deleted, conversation: conversation), session(2, conversation: uuid(778))])
        j.tombstones[uuid(2)] = SupportSessionTombstone(sessionID: uuid(2), deletedAt: base)
        j.tombstones[uuid(3)] = SupportSessionTombstone(sessionID: uuid(3), deletedAt: base)
        let merged = items(j, cloud: [cloud(1), cloud(2), cloud(3), cloud(4, deleted: true), cloud(5)],
                           standalone: [SupportStandaloneRecord(kind: .conversation, id: conversation, title: "Kept", createdAt: base, updatedAt: base)])
        XCTAssertEqual(Set(merged.map(\.id)), ["session:\(uuid(5).uuidString.lowercased())", "conversation:\(conversation.uuidString.lowercased())"])
    }

    func testStandaloneRecordsOwnedBySessionsAreNotDuplicated() {
        let conversation = uuid(900)
        let exercise = uuid(901), entry = uuid(902)
        let s = session(1, conversation: conversation)
        let a1 = activity(1, in: s.id, status: .completed, reference: .init(kind: .exerciseSession, id: exercise))
        let a2 = activity(2, in: s.id, status: .completed, reference: .init(kind: .journalEntry, id: entry))
        let merged = items(journal([s], activities: [a1, a2]), cloud: [cloud(2, conversation: uuid(903))], standalone: [
            SupportStandaloneRecord(kind: .conversation, id: conversation, title: nil, createdAt: base, updatedAt: base),
            SupportStandaloneRecord(kind: .conversation, id: uuid(903), title: nil, createdAt: base, updatedAt: base),
            SupportStandaloneRecord(kind: .exercise, id: exercise, title: nil, createdAt: base, updatedAt: base),
            SupportStandaloneRecord(kind: .journal, id: entry, title: nil, createdAt: base, updatedAt: base),
            SupportStandaloneRecord(kind: .journal, id: uuid(904), title: "Separate", createdAt: base, updatedAt: base)])
        XCTAssertEqual(merged.filter { $0.kind != .session }.map(\.recordID), [uuid(904)])
        XCTAssertEqual(merged.count, 3)
    }

    func testStandaloneKeepsOriginalTitleAndDateAndNeverInventsADate() {
        let dated = standalone(.journal, 1, title: "  Evening pages ", at: base)
        let undated = standalone(.conversation, 2, title: nil, at: nil)
        let merged = items(journal(), standalone: [undated, dated])
        XCTAssertEqual(merged.first?.title, "Evening pages")
        XCTAssertEqual(merged.first?.date, base)
        XCTAssertEqual(merged.last?.title, "Conversation")
        XCTAssertNil(merged.last?.date, "undated legacy records sort last and are not given today's date")
        XCTAssertEqual(SupportHistoryMerge.groups(merged, calendar: .current).last?.day, nil)
    }

    func testFiltersAndExplicitLocalSearch() {
        let withConversation = session(1, conversation: uuid(50), title: "Talked it through")
        let withStep = session(2, title: "Email", concern: "my supervisor")
        let step = activity(1, in: withStep.id, status: .paused,
                            step: SupportStepPayload(actionText: "Write the subject line", state: .saved))
        let plain = session(3, title: "Plain")
        var j = journal([withConversation, withStep, plain], activities: [step])
        j.drafts[plain.id] = "a private draft about zebras"
        XCTAssertEqual(Set(items(j, filter: .conversations).map(\.recordID)), [uuid(1)])
        XCTAssertEqual(Set(items(j, filter: .activities).map(\.recordID)), [uuid(2)])
        XCTAssertEqual(Set(items(j, filter: .savedSteps).map(\.recordID)), [uuid(2)])
        XCTAssertEqual(items(j, query: "SUBJECT").map(\.recordID), [uuid(2)], "saved step text is explicitly searchable")
        XCTAssertEqual(items(j, query: "supervisor").map(\.recordID), [uuid(2)])
        XCTAssertTrue(items(j, query: "zebras").isEmpty, "drafts and answers are never searched")
        XCTAssertEqual(items(j, query: "talked it").map(\.recordID), [uuid(1)])
        XCTAssertEqual(items(j, query: "  ").count, 3)
    }

    func testOrderingIsDeterministicForDateAndIDTies() {
        let sessions = (1...6).map { session($0, updated: base) } + [session(7, updated: base.addingTimeInterval(5))]
        let first = items(journal(sessions)).map(\.id)
        let second = items(journal(sessions.shuffled())).map(\.id)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.first, "session:\(uuid(7).uuidString.lowercased())")
        XCTAssertEqual(Array(first.dropFirst()), first.dropFirst().sorted())
    }

    func testOlderUnfinishedWorkIsGroupedOnceInAnyTimeZone() throws {
        let boundary = Date(timeIntervalSince1970: 1_790_000_000)           // far in the past relative to base
        var j = journal([session(1, updated: boundary, title: "Old unfinished")])
        j.drafts[uuid(1)] = "draft"
        let list = items(j, unfinishedOnly: true)
        XCTAssertEqual(list.count, 1)
        for zone in ["Pacific/Kiritimati", "Pacific/Pago_Pago", "UTC", "America/Los_Angeles"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
            let groups = SupportHistoryMerge.groups(list, calendar: calendar)
            XCTAssertEqual(groups.count, 1, zone)
            XCTAssertEqual(groups.first?.day, calendar.startOfDay(for: boundary), zone)
        }
        var east = Calendar(identifier: .gregorian), west = Calendar(identifier: .gregorian)
        east.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        west.timeZone = TimeZone(identifier: "Pacific/Pago_Pago")!
        XCTAssertNotEqual(SupportHistoryMerge.groups(list, calendar: east).first?.day,
                          SupportHistoryMerge.groups(list, calendar: west).first?.day,
                          "a record can legitimately fall on different local days; it is still shown once")
    }

    func testUnfinishedOnlyMatchesCoordinatorRule() {
        let openConversation = session(1, conversation: uuid(5))
        let closed = session(2, status: .closed)
        let empty = session(3)
        let withActivity = session(4)
        let j = journal([openConversation, closed, empty, withActivity], activities: [activity(1, in: withActivity.id, status: .inProgress)])
        XCTAssertEqual(Set(items(j, unfinishedOnly: true).map(\.recordID)), [uuid(1), uuid(4)])
        XCTAssertEqual(Set(items(j, cloud: [cloud(9, unfinished: 2), cloud(10, status: .closed, unfinished: 1)],
                                 unfinishedOnly: true).map(\.recordID)), [uuid(1), uuid(4), uuid(9)])
    }

    // MARK: Paging

    func testMoreThan100CloudSessionsPageWithoutDuplicatesOrOmissions() async {
        // 230 sessions, pages of 50, each page repeats the previous page's last row (a keyset tie at the boundary).
        let all = (1...230).map { cloud($0, updated: base.addingTimeInterval(Double(300 - ($0 / 2) * 2))) }  // many equal dates
        var pages: [[SupportHistoryCloudSession]] = []
        var start = 0
        while start < all.count {
            var page = Array(all[start..<min(start + 50, all.count)])
            if let overlap = pages.last?.last { page.insert(overlap, at: 0) }
            pages.append(page)
            start += 50
        }
        let source = FakeCloud(pages: pages)
        let loader = SupportHistoryLoader(cloud: source, standalone: nil, isCurrent: { true })
        await loader.reset()
        XCTAssertEqual(loader.cloudRows.count, 50)
        XCTAssertTrue(loader.hasMore)
        var guardCounter = 0
        while loader.hasMore && guardCounter < 20 { await loader.loadMoreAll(); guardCounter += 1 }
        XCTAssertFalse(loader.hasMore)
        XCTAssertEqual(loader.cloudRows.count, 230)
        XCTAssertEqual(Set(loader.cloudRows.map(\.id)), Set(all.map(\.id)))
        let merged = items(journal(), cloud: loader.cloudRows)
        XCTAssertEqual(merged.count, 230)
        XCTAssertEqual(Set(merged.map(\.id)).count, 230)
        XCTAssertEqual(source.calls, [true] + Array(repeating: false, count: pages.count - 1))
    }

    func testStandalonePagingPast100ForEveryKindWithCursorAdvancement() async {
        let fake = FakeStandalone()
        fake.records[.conversations] = (1...130).map { standalone(.conversation, $0, at: base.addingTimeInterval(Double(-$0))) }
        fake.records[.exercises] = (1...101).map { standalone(.exercise, $0, at: base.addingTimeInterval(Double(-$0))) }
        fake.records[.journals] = (1...7).map { standalone(.journal, $0, at: base.addingTimeInterval(Double(-$0))) }
        let loader = SupportHistoryLoader(cloud: nil, standalone: fake, isCurrent: { true })
        await loader.reset()
        XCTAssertEqual(loader.standalone.count, 50 + 50 + 7)
        XCTAssertEqual(loader.states[.journals]?.hasMore, false)
        await loader.loadMoreAll(); await loader.loadMoreAll()
        XCTAssertEqual(loader.standalone.count, 130 + 101 + 7)
        XCTAssertFalse(loader.hasMore)
        // Each load-more started at the previous page's cursor, never from the top.
        let conversationCursors = fake.calls.filter { $0.0 == .conversations }.map(\.1)
        XCTAssertEqual(conversationCursors.count, 3)
        XCTAssertNil(conversationCursors[0])
        XCTAssertNotNil(conversationCursors[1]); XCTAssertNotEqual(conversationCursors[1], conversationCursors[2])
        let merged = items(journal(), standalone: loader.standalone)
        XCTAssertEqual(merged.count, 238)
    }

    func testStuckCursorBecomesAVisibleErrorAndKeepsLoadedRows() async {
        let fake = FakeStandalone()
        fake.pageSize = 2
        fake.records[.journals] = (1...6).map { standalone(.journal, $0, at: base) }
        let loader = SupportHistoryLoader(cloud: nil, standalone: fake, isCurrent: { true })
        await loader.reset()
        XCTAssertEqual(loader.standalone.filter { $0.kind == .journal }.count, 2)
        fake.stuckCursor = true
        await loader.loadMore(.journals)
        XCTAssertEqual(loader.standalone.filter { $0.kind == .journal }.count, 2, "rows are kept")
        guard case .failed = loader.states[.journals]?.phase else { return XCTFail("error must be visible") }
    }

    func testFailedLoadNeverErasesRowsAndOtherSourcesStillLoad() async {
        let fake = FakeStandalone()
        fake.records[.conversations] = [standalone(.conversation, 1, at: base)]
        fake.records[.journals] = [standalone(.journal, 1, at: base)]
        let source = FakeCloud(pages: [[cloud(1)]])
        let loader = SupportHistoryLoader(cloud: source, standalone: fake, isCurrent: { true })
        await loader.reset()
        XCTAssertEqual(loader.cloudRows.count, 1)
        source.error = URLError(.timedOut)
        fake.failKind = .journals
        await loader.reset()
        XCTAssertEqual(loader.cloudRows.count, 1, "cloud rows survive a failed refresh")
        XCTAssertTrue(loader.standalone.contains { $0.kind == .journal }, "journal rows survive a failed refresh")
        XCTAssertTrue(loader.standalone.contains { $0.kind == .conversation })
        XCTAssertEqual(Set(loader.failures.map { "\($0.0)" }), ["cloud", "journals"])
        XCTAssertFalse(loader.failures.map(\.1).contains { $0.contains("timed") })   // generic copy, no raw error text
    }

    func testOwnerSwitchWhileLoadingDropsLateResults() async {
        var current = true
        let source = FakeCloud(pages: [[cloud(1), cloud(2)]])
        let released = expectation(description: "gate reached")
        var continuation: CheckedContinuation<Void, Never>?
        source.gate = { _ in
            await withCheckedContinuation { c in continuation = c; released.fulfill() }
        }
        let loader = SupportHistoryLoader(cloud: source, standalone: nil, isCurrent: { current })
        let work = Task { await loader.reset() }
        await fulfillment(of: [released], timeout: 2)
        current = false                      // account switched while the request was in flight
        continuation?.resume()
        await work.value
        XCTAssertTrue(loader.cloudRows.isEmpty, "late page for the old owner must not be applied")
        XCTAssertTrue(loader.isInvalidated)
        await loader.reset()                 // still the old owner: refuses to start
        XCTAssertEqual(source.calls.count, 1)
    }

    func testResetSupersedesAnInFlightLoadMore() async {
        let pages = [[cloud(1), cloud(2)], [cloud(3), cloud(4)]]
        let source = FakeCloud(pages: pages)
        let loader = SupportHistoryLoader(cloud: source, standalone: nil, isCurrent: { true })
        await loader.reset()
        XCTAssertEqual(loader.cloudRows.map(\.id), [uuid(1), uuid(2)])

        let reached = expectation(description: "load-more in flight")
        var continuation: CheckedContinuation<Void, Never>?
        source.gate = { call in
            guard call == 2 else { return }          // only hold the load-more
            await withCheckedContinuation { c in continuation = c; reached.fulfill() }
        }
        let more = Task { await loader.loadMore(.cloud) }
        await fulfillment(of: [reached], timeout: 2)
        let reset = Task { await loader.reset() }
        await Task.yield()
        continuation?.resume()                        // the cancelled load-more finishes late
        await more.value; await reset.value
        // Only the reset's first page is installed; the stale second page was dropped.
        XCTAssertEqual(loader.cloudRows.map(\.id), [uuid(1), uuid(2)])
        XCTAssertEqual(loader.states[.cloud]?.hasMore, true)
        XCTAssertEqual(source.calls, [true, false, true])
        await loader.loadMore(.cloud)
        XCTAssertEqual(loader.cloudRows.map(\.id), [uuid(1), uuid(2), uuid(3), uuid(4)])
    }

    func testDuplicateLoadMoreWhileInFlightIsIgnored() async {
        let source = FakeCloud(pages: [[cloud(1)], [cloud(2)], [cloud(3)]])
        let loader = SupportHistoryLoader(cloud: source, standalone: nil, isCurrent: { true })
        await loader.reset()
        let reached = expectation(description: "in flight")
        var continuation: CheckedContinuation<Void, Never>?
        source.gate = { call in
            guard call == 2 else { return }
            await withCheckedContinuation { c in continuation = c; reached.fulfill() }
        }
        let first = Task { await loader.loadMore(.cloud) }
        await fulfillment(of: [reached], timeout: 2)
        await loader.loadMore(.cloud)                // tapped again while loading
        continuation?.resume()
        await first.value
        XCTAssertEqual(source.calls.count, 2)
        XCTAssertEqual(loader.cloudRows.count, 2)
    }

    func testLoadMoreBeforeFirstPageDoesNothing() async {
        let source = FakeCloud(pages: [[cloud(1)], [cloud(2)]])
        let loader = SupportHistoryLoader(cloud: source, standalone: nil, isCurrent: { true })
        await loader.loadMore(.cloud)
        XCTAssertTrue(source.calls.isEmpty)
    }

    // MARK: HST-R01 / HST-R04

    func testAccountTombstoneHidesTheLocalSessionAndFreesItsRecords() {
        let conversation = uuid(60), exercise = uuid(61)
        let s = session(1, conversation: conversation, title: "Local text")
        let a = activity(1, in: s.id, status: .completed, reference: .init(kind: .exerciseSession, id: exercise))
        let merged = items(journal([s], activities: [a]), cloud: [cloud(1, revision: 9, deleted: true)], standalone: [
            SupportStandaloneRecord(kind: .conversation, id: conversation, title: "Chat", createdAt: base, updatedAt: base),
            SupportStandaloneRecord(kind: .exercise, id: exercise, title: "Grounding", createdAt: base, updatedAt: base)])
        XCTAssertFalse(merged.contains { $0.kind == .session }, "an account-deleted identity is never shown as current")
        XCTAssertEqual(Set(merged.map(\.recordID)), [conversation, exercise])
        XCTAssertTrue(items(journal([s], activities: [a]), cloud: [cloud(1, deleted: true)], unfinishedOnly: true).isEmpty)
    }

    func testNewerRemoteCloseUpdatesStatusUnfinishedFlagAndFilters() {
        let conversation = uuid(70)
        var j = journal([session(1, conversation: conversation, title: "Open locally")],
                        activities: [activity(1, in: uuid(1), status: .paused)])
        j.drafts[uuid(1)] = "unsent draft"
        j.serverRevisions[uuid(1)] = 1
        XCTAssertEqual(items(j, unfinishedOnly: true).count, 1)

        let remote = cloud(1, updated: base.addingTimeInterval(90), revision: 2, status: .closed, conversation: nil,
                           unfinished: 0, activities: 0, savedSteps: 0)
        let merged = items(j, cloud: [remote])
        let item = try? XCTUnwrap(merged.first)
        XCTAssertEqual(item?.status, .closed)
        XCTAssertEqual(item?.isUnfinished, false)
        XCTAssertEqual(item?.hasConversation, false)
        XCTAssertEqual(item?.hasActivity, false)
        XCTAssertEqual(item?.sync, .newerInAccount)
        XCTAssertEqual(item?.remoteRevision, 2)
        XCTAssertTrue(items(j, cloud: [remote], unfinishedOnly: true).isEmpty)
        XCTAssertTrue(items(j, cloud: [remote], filter: .conversations).isEmpty)
        XCTAssertTrue(items(j, cloud: [remote], filter: .activities).isEmpty)
        // The conversation it no longer owns is a standalone record again.
        let withConversation = items(j, cloud: [remote], standalone: [
            SupportStandaloneRecord(kind: .conversation, id: conversation, title: nil, createdAt: base, updatedAt: base)])
        XCTAssertEqual(withConversation.count, 2)
    }

    func testUnsyncedLocalSessionIsNotChangedByANewerRemoteSummary() {
        var j = journal([session(1, sync: .pending, conversation: uuid(5))])
        j.serverRevisions[uuid(1)] = 1
        let item = items(j, cloud: [cloud(1, revision: 5, status: .closed)]).first
        XCTAssertEqual(item?.status, .open)
        XCTAssertEqual(item?.isUnfinished, true)
        XCTAssertEqual(item?.sync, .waiting)
    }

    func testCloudOnlyActivityAndSavedStepMetadataDriveFiltersWithoutOpeningRows() {
        let completed = cloud(1, status: .closed, activities: 2, savedSteps: 0)
        let saved = cloud(2, status: .open, activities: 1, savedSteps: 1)
        let unknown = cloud(3, status: .closed)                                  // older server: metadata absent
        let none = cloud(4, status: .closed, activities: 0, savedSteps: 0)
        let all = [completed, saved, unknown, none]
        XCTAssertEqual(Set(items(journal(), cloud: all, filter: .activities).map(\.recordID)), [uuid(1), uuid(2)])
        XCTAssertEqual(Set(items(journal(), cloud: all, filter: .savedSteps).map(\.recordID)), [uuid(2)])
        XCTAssertEqual(items(journal(), cloud: all).count, 4, "unknown metadata hides nothing from All")
        XCTAssertFalse(items(journal(), cloud: [unknown], filter: .activities).contains { _ in true },
                       "absent metadata means unknown, not a claim of activity")
    }

    func testCanonicalReferencesDeduplicateBeforeTheSessionIsInstalled() {
        let exercise = uuid(81), entry = uuid(82)
        let remote = cloud(1, status: .closed, activities: 2, references: [
            .init(kind: .exerciseSession, id: exercise), .init(kind: .journalEntry, id: entry)])
        let merged = items(journal(), cloud: [remote], standalone: [
            SupportStandaloneRecord(kind: .exercise, id: exercise, title: nil, createdAt: base, updatedAt: base),
            SupportStandaloneRecord(kind: .journal, id: entry, title: nil, createdAt: base, updatedAt: base),
            SupportStandaloneRecord(kind: .journal, id: uuid(83), title: "Own entry", createdAt: base, updatedAt: base)])
        XCTAssertEqual(Set(merged.map(\.recordID)), [uuid(1), uuid(83)])
        // A reference kind never matches a different kind with the same id.
        let crossKind = items(journal(), cloud: [cloud(2, references: [.init(kind: .journalEntry, id: exercise)])],
                              standalone: [SupportStandaloneRecord(kind: .exercise, id: exercise, title: nil, createdAt: base, updatedAt: base)])
        XCTAssertEqual(crossKind.count, 2)
    }

    func testOriginalCreatedDateIsTheMainDateAndUpdatedIsSeparate() {
        let old = base.addingTimeInterval(-86_400 * 30)
        let newer = cloud(1, updated: base, created: old)
        let recent = cloud(2, updated: base.addingTimeInterval(10), created: base.addingTimeInterval(-60))
        let merged = items(journal(), cloud: [newer, recent])
        XCTAssertEqual(merged.map(\.recordID), [uuid(2), uuid(1)], "ordered by original date, not last change")
        XCTAssertEqual(merged.last?.date, old)
        XCTAssertEqual(merged.last?.updatedAt, base)
        let local = session(5, updated: base)
        var created = local
        created = SupportSession(id: created.id, ownerID: owner, conversationID: nil, previousSessionID: nil, selectedActivityID: nil,
                                 title: "t", concern: nil, status: .open, contextScope: .conversationOnly, localRevision: 1,
                                 syncStatus: .synced, createdAt: old, updatedAt: base, closedAt: nil)
        XCTAssertEqual(items(journal([created])).first?.date, old)
        let record = SupportStandaloneRecord(kind: .journal, id: uuid(9), title: "Entry", createdAt: old, updatedAt: base)
        XCTAssertEqual(items(journal(), standalone: [record]).first?.date, old)
    }

    // MARK: Detail decisions

    func testContinuationPlans() {
        let activityOwner = session(1)
        var withActivity = activityOwner
        let running = activity(1, in: activityOwner.id, status: .paused)
        withActivity.selectedActivityID = running.id
        let j = journal([withActivity], activities: [running])
        XCTAssertEqual(SupportHistoryContinuation.plan(for: withActivity, journal: j), .resumeActivity(running.id))

        let finished = activity(2, in: activityOwner.id, status: .completed)
        var done = session(2, conversation: uuid(40))
        done.selectedActivityID = finished.id
        XCTAssertEqual(SupportHistoryContinuation.plan(for: done, journal: journal([done], activities: [finished])),
                       .openConversation(uuid(40)))
        XCTAssertEqual(SupportHistoryContinuation.plan(for: session(3), journal: journal()), .blankChat)

        // A selected activity that belongs to another session is never resumed.
        var foreign = session(4)
        foreign.selectedActivityID = running.id
        XCTAssertEqual(SupportHistoryContinuation.plan(for: foreign, journal: j), .blankChat)
    }

    func testClosedSessionContinuesAsNewLinkedSessionWithoutReusingConversation() {
        var closed = session(5, status: .closed, conversation: uuid(41))
        closed.contextScope = .personalized
        XCTAssertEqual(SupportHistoryContinuation.plan(for: closed, journal: journal([closed])),
                       .startLinkedSession(previousSessionID: closed.id, scope: .personalized))
    }

    func testCloseChoiceAppliesOnlyWhenWorkWouldBeStopped() {
        let a = session(1), b = session(2), c = session(3, status: .closed)
        var j = journal([a, b, c], activities: [activity(1, in: b.id, status: .inProgress)])
        XCTAssertFalse(SupportHistorySessionRules.hasUnfinishedWork(a, journal: j))
        XCTAssertTrue(SupportHistorySessionRules.hasUnfinishedWork(b, journal: j))
        j.drafts[a.id] = "unsent"
        XCTAssertTrue(SupportHistorySessionRules.hasUnfinishedWork(a, journal: j))
        XCTAssertFalse(SupportHistorySessionRules.hasUnfinishedWork(c, journal: j))
    }

    func testRenameLimitsAreEightyUnicodeScalars() {
        XCTAssertEqual(SupportHistorySessionRules.validatedTitle("  Sleep plan "), "Sleep plan")
        XCTAssertNil(SupportHistorySessionRules.validatedTitle("   "))
        XCTAssertNotNil(SupportHistorySessionRules.validatedTitle(String(repeating: "a", count: 80)))
        XCTAssertNil(SupportHistorySessionRules.validatedTitle(String(repeating: "a", count: 81)))
        XCTAssertNil(SupportHistorySessionRules.validatedTitle(String(repeating: "👩‍👩‍👧", count: 27)),
                     "counted in Unicode scalars like the server, not grapheme clusters")
    }
}
