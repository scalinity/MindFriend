import XCTest
@testable import MindFriendApp

final class VaultStorageTests: XCTestCase {

    var sut: VaultStorageService!
    var encryptionService: VaultEncryptionService!

    override func setUp() async throws {
        try await super.setUp()
        encryptionService = VaultEncryptionService()
        sut = VaultStorageService(encryptionService: encryptionService)

        // Ensure clean state
        try await sut.deleteAllEntries()
    }

    override func tearDown() async throws {
        // Clean up after tests
        try await sut.deleteAllEntries()
        try? await encryptionService.deleteKey()
        sut = nil
        encryptionService = nil
        try await super.tearDown()
    }

    // MARK: - CRUD Tests

    func testSaveAndLoadEntry() async throws {
        let entry = VaultEntry(title: "Test Entry", body: "Test content")

        // Save
        try await sut.saveEntry(entry)

        // Load
        let loaded = try await sut.getEntry(entry.id)

        XCTAssertEqual(loaded.id, entry.id)
        XCTAssertEqual(loaded.title, entry.title)
        XCTAssertEqual(loaded.body, entry.body)
    }

    func testListEntries() async throws {
        // Create multiple entries
        let entry1 = VaultEntry(title: "Entry 1", body: "Content 1")
        let entry2 = VaultEntry(title: "Entry 2", body: "Content 2")
        let entry3 = VaultEntry(title: "Entry 3", body: "Content 3")

        try await sut.saveEntry(entry1)
        try await sut.saveEntry(entry2)
        try await sut.saveEntry(entry3)

        // List all
        let entries = try await sut.listEntries()

        XCTAssertEqual(entries.count, 3)

        // Verify all entries are present
        let ids = Set(entries.map { $0.id })
        XCTAssertTrue(ids.contains(entry1.id))
        XCTAssertTrue(ids.contains(entry2.id))
        XCTAssertTrue(ids.contains(entry3.id))
    }

    func testListEntriesSortedByUpdatedAt() async throws {
        // Create entries with different update times
        var entry1 = VaultEntry(title: "Oldest", body: "Content")
        entry1.updatedAt = Date().addingTimeInterval(-3600) // 1 hour ago

        var entry2 = VaultEntry(title: "Newest", body: "Content")
        entry2.updatedAt = Date()

        var entry3 = VaultEntry(title: "Middle", body: "Content")
        entry3.updatedAt = Date().addingTimeInterval(-1800) // 30 min ago

        try await sut.saveEntry(entry1)
        try await sut.saveEntry(entry2)
        try await sut.saveEntry(entry3)

        // List should be sorted newest first
        let entries = try await sut.listEntries()

        XCTAssertEqual(entries[0].id, entry2.id, "Newest entry should be first")
        XCTAssertEqual(entries[1].id, entry3.id, "Middle entry should be second")
        XCTAssertEqual(entries[2].id, entry1.id, "Oldest entry should be last")
    }

    func testUpdateEntry() async throws {
        var entry = VaultEntry(title: "Original", body: "Original content")

        // Save original
        try await sut.saveEntry(entry)

        // Update
        entry.title = "Updated Title"
        entry.body = "Updated content"
        entry.updatedAt = Date()
        try await sut.saveEntry(entry)

        // Load and verify
        let loaded = try await sut.getEntry(entry.id)

        XCTAssertEqual(loaded.title, "Updated Title")
        XCTAssertEqual(loaded.body, "Updated content")
    }

    func testDeleteEntry() async throws {
        let entry = VaultEntry(title: "To Delete", body: "Content")

        // Save
        try await sut.saveEntry(entry)

        // Verify exists
        let count1 = await sut.entryCount()
        XCTAssertEqual(count1, 1)

        // Delete
        try await sut.deleteEntry(entry.id)

        // Verify deleted
        let count2 = await sut.entryCount()
        XCTAssertEqual(count2, 0)

        // Verify can't load
        do {
            _ = try await sut.getEntry(entry.id)
            XCTFail("Should throw entryNotFound")
        } catch let error as VaultError {
            XCTAssertEqual(error, .entryNotFound(entry.id))
        }
    }

    func testDeleteAllEntries() async throws {
        // Create multiple entries
        for i in 1...5 {
            let entry = VaultEntry(title: "Entry \(i)", body: "Content")
            try await sut.saveEntry(entry)
        }

        let countBefore = await sut.entryCount()
        XCTAssertEqual(countBefore, 5)

        // Delete all
        try await sut.deleteAllEntries()

        // Verify all deleted
        let countAfter = await sut.entryCount()
        XCTAssertEqual(countAfter, 0)

        let entries = try await sut.listEntries()
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - Error Handling Tests

    func testGetNonexistentEntry() async throws {
        let nonexistentId = UUID()

        do {
            _ = try await sut.getEntry(nonexistentId)
            XCTFail("Should throw entryNotFound")
        } catch let error as VaultError {
            XCTAssertEqual(error, .entryNotFound(nonexistentId))
        }
    }

    func testDeleteNonexistentEntry() async throws {
        let nonexistentId = UUID()

        do {
            try await sut.deleteEntry(nonexistentId)
            XCTFail("Should throw entryNotFound")
        } catch let error as VaultError {
            XCTAssertEqual(error, .entryNotFound(nonexistentId))
        }
    }

    // MARK: - Entry Count Tests

    func testEntryCount() async throws {
        let count0 = await sut.entryCount()
        XCTAssertEqual(count0, 0)

        // Add entries
        for i in 1...3 {
            let entry = VaultEntry(title: "Entry \(i)", body: "Content")
            try await sut.saveEntry(entry)
        }

        let count3 = await sut.entryCount()
        XCTAssertEqual(count3, 3)

        // Delete one
        let entries = try await sut.listEntries()
        if let first = entries.first {
            try await sut.deleteEntry(first.id)
        }

        let count2 = await sut.entryCount()
        XCTAssertEqual(count2, 2)
    }

    // MARK: - Edge Cases

    func testSaveEntryWithEmptyTitle() async throws {
        let entry = VaultEntry(title: nil, body: "Body only")

        try await sut.saveEntry(entry)
        let loaded = try await sut.getEntry(entry.id)

        XCTAssertNil(loaded.title)
        XCTAssertEqual(loaded.body, "Body only")
    }

    func testSaveEntryWithLongContent() async throws {
        let longBody = String(repeating: "Long content. ", count: 5000) // ~70KB
        let entry = VaultEntry(title: "Long Entry", body: longBody)

        try await sut.saveEntry(entry)
        let loaded = try await sut.getEntry(entry.id)

        XCTAssertEqual(loaded.body, longBody)
    }

    func testSaveEntryWithSpecialCharacters() async throws {
        let entry = VaultEntry(
            title: "Special: <>&\"'",
            body: "Content with special chars: <>&\"'\n\t\r\\/"
        )

        try await sut.saveEntry(entry)
        let loaded = try await sut.getEntry(entry.id)

        XCTAssertEqual(loaded.title, entry.title)
        XCTAssertEqual(loaded.body, entry.body)
    }

    func testListEntriesWithEmptyVault() async throws {
        let entries = try await sut.listEntries()
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentSaves() async throws {
        // Create multiple entries concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask {
                    let entry = VaultEntry(title: "Entry \(i)", body: "Content \(i)")
                    try? await self.sut.saveEntry(entry)
                }
            }
        }

        // All entries should be saved
        let count = await sut.entryCount()
        XCTAssertEqual(count, 10)
    }

    func testConcurrentReadWrite() async throws {
        let entry = VaultEntry(title: "Concurrent", body: "Content")
        try await sut.saveEntry(entry)

        // Concurrent reads and writes
        await withTaskGroup(of: Void.self) { group in
            // Multiple reads
            for _ in 1...5 {
                group.addTask {
                    _ = try? await self.sut.getEntry(entry.id)
                }
            }

            // Update
            group.addTask {
                var updated = entry
                updated.body = "Updated content"
                try? await self.sut.saveEntry(updated)
            }
        }

        // Should not crash and entry should still be readable
        let loaded = try await sut.getEntry(entry.id)
        XCTAssertNotNil(loaded)
    }
}
