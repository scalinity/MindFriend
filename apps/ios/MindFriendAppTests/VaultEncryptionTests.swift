import XCTest
import CryptoKit
@testable import MindFriendApp

final class VaultEncryptionTests: XCTestCase {

    var sut: VaultEncryptionService!

    override func setUp() async throws {
        try await super.setUp()
        sut = VaultEncryptionService()
        // Clean up any existing key from previous tests
        try? await sut.deleteKey()
    }

    override func tearDown() async throws {
        // Clean up test key
        try? await sut.deleteKey()
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Key Generation Tests

    func testKeyGeneration() async throws {
        // Initially no key exists
        let existsBefore = await sut.keyExists()
        XCTAssertFalse(existsBefore, "Key should not exist before generation")

        // Generate key
        try await sut.generateKey()

        // Key should now exist
        let existsAfter = await sut.keyExists()
        XCTAssertTrue(existsAfter, "Key should exist after generation")
    }

    func testKeyPersistence() async throws {
        // Generate key
        try await sut.generateKey()

        // Create a new service instance
        let newService = VaultEncryptionService()

        // Key should still exist (persisted in Keychain)
        let keyExists = await newService.keyExists()
        XCTAssertTrue(keyExists, "Key should persist across service instances")
    }

    func testDeleteKey() async throws {
        // Generate key first
        try await sut.generateKey()
        let existsBefore = await sut.keyExists()
        XCTAssertTrue(existsBefore)

        // Delete key
        try await sut.deleteKey()

        // Key should no longer exist
        let existsAfter = await sut.keyExists()
        XCTAssertFalse(existsAfter, "Key should not exist after deletion")
    }

    // MARK: - Encryption/Decryption Tests

    func testEncryptDecryptRoundtrip() async throws {
        let entry = VaultEntry(
            title: "Test Entry",
            body: "This is a test entry with some content."
        )

        // Encrypt
        let encrypted = try await sut.encrypt(entry)
        XCTAssertFalse(encrypted.isEmpty, "Encrypted data should not be empty")

        // Verify it's actually encrypted (should not contain plaintext)
        let encryptedString = String(data: encrypted, encoding: .utf8) ?? ""
        XCTAssertFalse(encryptedString.contains("Test Entry"), "Plaintext should not be visible in encrypted data")

        // Decrypt
        let decrypted = try await sut.decrypt(encrypted)

        // Verify roundtrip
        XCTAssertEqual(decrypted.id, entry.id)
        XCTAssertEqual(decrypted.title, entry.title)
        XCTAssertEqual(decrypted.body, entry.body)
        XCTAssertEqual(decrypted.createdAt.timeIntervalSince1970, entry.createdAt.timeIntervalSince1970, accuracy: 1)
    }

    func testEncryptDecryptWithoutTitle() async throws {
        let entry = VaultEntry(title: nil, body: "Body only entry")

        let encrypted = try await sut.encrypt(entry)
        let decrypted = try await sut.decrypt(encrypted)

        XCTAssertNil(decrypted.title)
        XCTAssertEqual(decrypted.body, entry.body)
    }

    func testEncryptDecryptWithEmoji() async throws {
        let entry = VaultEntry(
            title: "Emoji Test 🔐",
            body: "Content with emojis: 😀🎉💡🌟"
        )

        let encrypted = try await sut.encrypt(entry)
        let decrypted = try await sut.decrypt(encrypted)

        XCTAssertEqual(decrypted.title, entry.title)
        XCTAssertEqual(decrypted.body, entry.body)
    }

    func testEncryptDecryptWithUnicode() async throws {
        let entry = VaultEntry(
            title: "Unicode: 日本語 العربية",
            body: "中文内容 • Ελληνικά • עברית"
        )

        let encrypted = try await sut.encrypt(entry)
        let decrypted = try await sut.decrypt(encrypted)

        XCTAssertEqual(decrypted.title, entry.title)
        XCTAssertEqual(decrypted.body, entry.body)
    }

    func testEncryptDecryptLargeEntry() async throws {
        // Create a large entry (~100KB)
        let largeBody = String(repeating: "This is a test sentence. ", count: 4000)
        let entry = VaultEntry(title: "Large Entry", body: largeBody)

        let encrypted = try await sut.encrypt(entry)
        let decrypted = try await sut.decrypt(encrypted)

        XCTAssertEqual(decrypted.body, entry.body)
    }

    // MARK: - Error Handling Tests

    func testDecryptInvalidData() async throws {
        // Generate key first so we can attempt decryption
        try await sut.generateKey()

        let invalidData = Data([0x00, 0x01, 0x02, 0x03])

        do {
            _ = try await sut.decrypt(invalidData)
            XCTFail("Should throw VaultError.invalidData")
        } catch let error as VaultError {
            XCTAssertEqual(error, .invalidData)
        }
    }

    func testDecryptCorruptedData() async throws {
        let entry = VaultEntry(title: "Test", body: "Content")
        let encrypted = try await sut.encrypt(entry)

        // Corrupt the ciphertext by flipping some bytes
        var corrupted = encrypted
        if corrupted.count > 20 {
            corrupted[15] ^= 0xFF
            corrupted[16] ^= 0xFF
        }

        do {
            _ = try await sut.decrypt(corrupted)
            XCTFail("Should throw error for corrupted data")
        } catch {
            // Expected: either decryptionFailed or invalidData
            XCTAssertTrue(error is VaultError)
        }
    }

    func testDecryptTruncatedData() async throws {
        let entry = VaultEntry(title: "Test", body: "Content")
        let encrypted = try await sut.encrypt(entry)

        // Truncate data to be too short
        let truncated = encrypted.prefix(10)

        do {
            _ = try await sut.decrypt(Data(truncated))
            XCTFail("Should throw VaultError.invalidData for truncated data")
        } catch let error as VaultError {
            XCTAssertEqual(error, .invalidData)
        }
    }

    func testDecryptWithoutKey() async throws {
        // Ensure no key exists
        try await sut.deleteKey()

        let dummyData = Data(repeating: 0, count: 100)

        do {
            _ = try await sut.decrypt(dummyData)
            XCTFail("Should throw VaultError.keyNotFound")
        } catch let error as VaultError {
            XCTAssertEqual(error, .keyNotFound)
        }
    }

    // MARK: - Encrypted Data Format Tests

    func testEncryptedDataFormat() async throws {
        let entry = VaultEntry(title: "Test", body: "Content")
        let encrypted = try await sut.encrypt(entry)

        // Verify minimum size: 12 (nonce) + 16 (tag) + some ciphertext
        XCTAssertGreaterThan(encrypted.count, EncryptedVaultData.minimumSize)

        // Verify we can parse the format
        let parsed = EncryptedVaultData(combined: encrypted)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.nonce.count, EncryptedVaultData.nonceSize)
        XCTAssertEqual(parsed?.tag.count, EncryptedVaultData.tagSize)
        XCTAssertGreaterThan(parsed?.ciphertext.count ?? 0, 0)
    }

    func testUniqueNoncePerEncryption() async throws {
        let entry = VaultEntry(title: "Test", body: "Same content")

        let encrypted1 = try await sut.encrypt(entry)
        let encrypted2 = try await sut.encrypt(entry)

        // Nonces should be different (first 12 bytes)
        let nonce1 = encrypted1.prefix(12)
        let nonce2 = encrypted2.prefix(12)
        XCTAssertNotEqual(nonce1, nonce2, "Each encryption should use a unique nonce")

        // But both should decrypt to the same content
        let decrypted1 = try await sut.decrypt(encrypted1)
        let decrypted2 = try await sut.decrypt(encrypted2)
        XCTAssertEqual(decrypted1.body, decrypted2.body)
    }
}
