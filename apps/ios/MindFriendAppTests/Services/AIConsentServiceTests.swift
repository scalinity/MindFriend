// AIConsentServiceTests.swift
import XCTest
@testable import MindFriendApp

@MainActor
final class AIConsentServiceTests: XCTestCase {
    var fakeStore: FakeConsentStore!
    var service: AIConsentService!
    let testUserId = UUID()

    override func setUp() async throws {
        fakeStore = FakeConsentStore(userId: testUserId)
        service = AIConsentService(store: fakeStore)
    }

    func test_isGranted_falseBeforeLoad() {
        XCTAssertFalse(service.isGranted(.chat))
    }

    func test_isGranted_trueAfterGrant() async throws {
        try await service.grant([.chat])
        XCTAssertTrue(service.isGranted(.chat))
    }

    func test_grant_writesGrantedAtTimestamp() async throws {
        try await service.grant([.chat])
        let record = fakeStore.upserts.last!.first { $0.feature == .chat }!
        XCTAssertEqual(record.state, .granted)
        XCTAssertNotNil(record.grantedAt)
        XCTAssertNil(record.revokedAt)
    }

    func test_revoke_setsDeniedAndRevokedAt() async throws {
        try await service.grant([.chat])
        try await service.revoke(.chat)
        XCTAssertFalse(service.isGranted(.chat))
        let last = fakeStore.upserts.last!.first { $0.feature == .chat }!
        XCTAssertEqual(last.state, .denied)
        XCTAssertNotNil(last.revokedAt)
    }

    func test_setConsent_denyOthers_writesAllFeatures() async throws {
        try await service.setConsent(grant: [.chat], denyOthers: true)
        let last = fakeStore.upserts.last!
        XCTAssertEqual(last.count, AIFeature.allCases.count)
        XCTAssertEqual(last.first { $0.feature == .chat }!.state, .granted)
        XCTAssertEqual(last.first { $0.feature == .journalAI }!.state, .denied)
    }

    func test_setConsent_denyOthersFalse_onlyWritesGrantedSubset() async throws {
        try await service.setConsent(grant: [.chat, .insights], denyOthers: false)
        let last = fakeStore.upserts.last!
        XCTAssertEqual(last.count, 2)
        XCTAssertTrue(last.allSatisfy { $0.state == .granted })
    }

    func test_needsConsentGate_trueWhenNoRows() {
        XCTAssertTrue(service.needsConsentGate())
    }

    func test_needsConsentGate_falseWhenAllExplicit() async throws {
        try await service.setConsent(grant: AIFeature.allCases.first.map { Set([$0]) } ?? [], denyOthers: true)
        XCTAssertFalse(service.needsConsentGate())
    }

    func test_needsConsentGate_trueWhenPolicyVersionStale() async throws {
        fakeStore.preloadedRecords = AIFeature.allCases.map {
            AIConsentRecord(
                userId: testUserId,
                feature: $0,
                state: .granted,
                grantedAt: Date(),
                revokedAt: nil,
                policyVersion: AIConsent.currentPolicyVersion - 1,
                updatedAt: Date()
            )
        }
        try await service.loadFromServer()
        XCTAssertTrue(service.needsConsentGate())
    }

    func test_revokeAll_writesAllAsDenied() async throws {
        try await service.revokeAll(deleteAIHistory: false)
        let last = fakeStore.upserts.last!
        XCTAssertEqual(last.count, AIFeature.allCases.count)
        XCTAssertTrue(last.allSatisfy { $0.state == .denied })
    }

    func test_revokeAll_withDeleteHistory_callsStoreDelete() async throws {
        try await service.revokeAll(deleteAIHistory: true)
        XCTAssertEqual(fakeStore.deleteAIHistoryCallCount, 1)
    }

    func test_markUnknown_flipsInMemoryState() async throws {
        try await service.grant([.chat])
        XCTAssertTrue(service.isGranted(.chat))
        service.markUnknown(.chat)
        XCTAssertFalse(service.isGranted(.chat))
    }
}

// MARK: - Test fake

@MainActor
final class FakeConsentStore: AIConsentStore {
    let userId: UUID
    var preloadedRecords: [AIConsentRecord] = []
    var upserts: [[AIConsentRecord]] = []
    var deleteAIHistoryCallCount = 0

    init(userId: UUID) {
        self.userId = userId
    }

    func currentUserId() async throws -> UUID { userId }

    func fetchAll() async throws -> [AIConsentRecord] { preloadedRecords }

    func upsert(_ records: [AIConsentRecord]) async throws {
        upserts.append(records)
        for r in records {
            if let i = preloadedRecords.firstIndex(where: { $0.feature == r.feature }) {
                preloadedRecords[i] = r
            } else {
                preloadedRecords.append(r)
            }
        }
    }

    func deleteAIHistory() async throws {
        deleteAIHistoryCallCount += 1
    }
}
