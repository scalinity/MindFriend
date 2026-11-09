import XCTest
@testable import MindFriendApp

final class SupportMemoryStateTests: XCTestCase {
    private func make(io: FaultyJournalIO, owner: UUID = UUID()) async throws -> SupportSessionRepository {
        let repository = SupportSessionRepository(identity: .init(ownerID: owner), io: io)
        _ = try await repository.load(epoch: repository.identity.epochID)
        return repository
    }
    private func item(id: UUID = UUID(), content: String = "Synthetic original", revision: Int = 1) -> SupportMemoryRecord {
        .init(id: id, content: content, category: "preferences", origin: "user_authored", state: "confirmed", revision: revision,
              confirmedAt: nil, reviewDueAt: nil, expiresAt: nil, lastUsedAt: nil, sourceMessageID: nil,
              sourceConversationID: nil, isSuggestion: false)
    }

    func testCorrectionIsAtomicDurableAndOldPagesCannotRestoreIt() async throws {
        let io = FaultyJournalIO(), owner = UUID(), repository = try await make(io: io, owner: owner)
        let epoch = repository.identity.epochID, original = item()
        try await repository.cacheMemoryRecords(epoch: epoch, records: [original], privacyRevision: 7)
        let change = try await repository.queueMemoryChange(epoch: epoch, targetID: original.id, action: .edit,
            content: "Synthetic correction", category: "preferences", expectedRevision: 1)
        try await repository.markMemoryChangeSent(epoch: epoch, id: change.id)
        try await repository.cacheMemoryRecords(epoch: epoch, records: [original], privacyRevision: 7)
        let journal = try await repository.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.memoryRecords[original.id]?.content, "Synthetic correction")
        XCTAssertTrue(journal.personalizedCloudPaused)
        await repository.invalidate()
        let reloaded = try await make(io: io, owner: owner)
        let restored = try await reloaded.currentJournal(epoch: reloaded.identity.epochID)
        XCTAssertEqual(restored.memoryChanges.first?.id, change.id)
        XCTAssertEqual(restored.memoryChanges.first?.expectedRevision, 1)
        XCTAssertTrue(restored.memoryChanges.first?.sent == true)
        XCTAssertTrue(restored.personalizedCloudPaused)
    }

    func testForgetRemovesOlderUnknownCorrectionAndProtectedCopies() async throws {
        let io = FaultyJournalIO(), repository = try await make(io: io), original = item(content: "SYNTHETIC_FORGET_ORIGINAL")
        let epoch = repository.identity.epochID, owner = repository.identity.ownerID
        try await repository.cacheMemoryRecords(epoch: epoch, records: [original], privacyRevision: 2)
        let edit = try await repository.queueMemoryChange(epoch: epoch, targetID: original.id, action: .edit,
            content: "SYNTHETIC_FORGET_CORRECTION", expectedRevision: 1)
        try await repository.markMemoryChangeSent(epoch: epoch, id: edit.id)
        let forget = try await repository.queueMemoryChange(epoch: epoch, targetID: original.id, action: .forgetMemory)
        let journal = try await repository.currentJournal(epoch: epoch)
        XCTAssertNil(journal.memoryRecords[original.id])
        XCTAssertEqual(journal.memoryChanges.map(\.id), [forget.id])
        for bytes in [io.primary(ownerID: owner), try io.loadBackup(ownerID: owner)].compactMap({ $0 }) {
            let text = String(decoding: bytes, as: UTF8.self)
            XCTAssertFalse(text.contains("SYNTHETIC_FORGET_ORIGINAL"))
            XCTAssertFalse(text.contains("SYNTHETIC_FORGET_CORRECTION"))
        }
        try await repository.cacheMemoryRecords(epoch: epoch, records: [original], privacyRevision: 2)
        let late = try await repository.currentJournal(epoch: epoch)
        XCTAssertNil(late.memoryRecords[original.id])
        XCTAssertTrue(late.personalizedCloudPaused)
    }

    func testReceiptCannotLowerPrivacyRevisionAndConflictNeedsExplicitChoice() async throws {
        let repository = try await make(io: FaultyJournalIO()), original = item()
        let scope = repository.identity.epochID
        try await repository.cacheMemoryRecords(epoch: scope, records: [original], privacyRevision: 12)
        let edit = try await repository.queueMemoryChange(epoch: scope, targetID: original.id, action: .edit,
            content: "Local correction", expectedRevision: 1)
        try await repository.rejectMemoryChange(epoch: scope, id: edit.id, code: "REVISION_CONFLICT",
            conflictingContent: "Other device version", conflictingRevision: 3)
        let held = try await repository.currentJournal(epoch: scope)
        XCTAssertEqual(held.memoryRecords[original.id]?.content, "Local correction")
        XCTAssertTrue(held.personalizedCloudPaused)
        try await repository.resolveMemoryConflict(epoch: scope, id: edit.id, keepLocal: true)
        let rebased = try await repository.currentJournal(epoch: scope)
        XCTAssertNotEqual(rebased.memoryChanges.first?.id, edit.id)
        XCTAssertEqual(rebased.memoryChanges.first?.expectedRevision, 3)
        try await repository.confirmMemoryChange(epoch: scope, id: try XCTUnwrap(rebased.memoryChanges.first).id, privacyRevision: 10)
        let settled = try await repository.currentJournal(epoch: scope)
        XCTAssertEqual(settled.accountPrivacyRevision, 12)
        XCTAssertFalse(settled.personalizedCloudPaused)
    }

    func testWriteFailureLeavesCorrectionAndSuppressionUnchanged() async throws {
        let io = FaultyJournalIO(), repository = try await make(io: io), original = item()
        let epoch = repository.identity.epochID
        try await repository.cacheMemoryRecords(epoch: epoch, records: [original], privacyRevision: 1)
        io.failCommits = true
        do { _ = try await repository.queueMemoryChange(epoch: epoch, targetID: original.id, action: .stopUsing); XCTFail("Expected write failure") }
        catch {}
        let journal = try await repository.currentJournal(epoch: epoch)
        XCTAssertTrue(journal.memoryChanges.isEmpty)
        XCTAssertEqual(journal.memoryRecords[original.id]?.state, "confirmed")
        XCTAssertFalse(journal.personalizedCloudPaused)
    }
}
