import Combine
import Foundation

// MARK: - Owner data export (AC-20 / E01)
//
// One deliberate, user-initiated export that writes ONE protected JSON file and nothing else. It replaces a scaffold that
// fetched through the SDK's ambient session, capped rows implicitly and logged the whole object.
//
// What it does
//   * Reads a fixed, versioned list of cloud datasets through the narrow `export_owner_data_page` RPC
//     (supabase/migrations/20261107040000_support_data_export.sql): one owner, one dataset, one bounded keyset page
//     per request. There is no generic table, filter or SQL parameter on the wire.
//   * Embeds the protected on-device support journal by encoding the ACTUAL `SupportJournal` value (so a field added to the
//     journal is exported without editing this file), plus a derived status summary that says which items are only
//     on this device or still pending. It only READS `currentJournal`; it never replays, sends or mutates queued work.
//   * Writes the document incrementally to a temporary file with data protection, excluded from backup. The file is
//     discarded on every failure, cancellation and owner change; the caller discards it after sharing.
//
// Safety properties
//   * Bound to ONE immutable owner + account epoch. The owner proof is re-checked before the token fetch, after it,
//     immediately before dispatch, after every response, around the local read and before the result is returned.
//     A response that arrives after a change is dropped undecoded.
//   * The raw `URLRequest` carries `apikey` and `Authorization: Bearer <captured token>` itself. Nothing relies on an SDK
//     client's ambient session (the SDK would replace a supplied Authorization header). Fixed host, https only
//     (loopback http for a local stack), no cookies, no cache.
//   * Every page is validated: envelope echo (owner, dataset, cursor, catalog version/size, limits), row count and bounds,
//     per-row owner, strictly ascending keys, cursor == last key, `has_more` coherence. Anything inconsistent fails the whole
//     export; a half-written file is never offered.
//   * An absent optional dataset is written as `"status":"unavailable"` and marks the export incomplete. It is never an
//     empty successful dataset. A local journal that cannot be read is likewise `"unavailable"` with a fixed reason code.
//   * The subset is stated in the file and in the UI: this is NOT a claim of "all possible app data".
//   * No token, row text, response body or user content is logged or placed in an error value. This file has no logging.

// MARK: - Limits

enum SupportExportLimits {
    static let documentFormat = "mindfriend.owner-data-export"
    static let documentSchemaVersion = 1
    /// Must equal `c_catalog_version` / `cardinality(c_datasets)` in the migration.
    static let catalogVersion = 1
    static let pageRows = 100
    /// The server stops adding rows once a page reaches this much jsonb text (it always returns at least one row).
    static let pageBytesTarget = 262_144
    static let requestTimeout: TimeInterval = 30
}

/// Tunable only by tests; production uses `.standard`.
struct SupportExportConfiguration: Sendable, Equatable {
    /// Hard cap on a single HTTP response body. A page is ~256 KiB; this leaves room for one very large row.
    var responseBytesCap = 2_097_152
    var maxPagesPerDataset = 5_000
    var maxFileBytes = 100 * 1_048_576

    static let standard = SupportExportConfiguration()
}

// MARK: - Identity and injection

/// Narrow immutable authenticated owner + account epoch (`AppState.currentUser.id` / `AppState.accountEpoch`).
struct SupportExportBinding: Hashable, Sendable {
    let ownerID: UUID
    let accountEpoch: UInt64
}

/// The owner and access token captured TOGETHER by the token source. The token is never printed.
struct SupportExportCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let binding: SupportExportBinding
    fileprivate let accessToken: String

    init(binding: SupportExportBinding, accessToken: String) {
        self.binding = binding
        self.accessToken = accessToken
    }

    var description: String { "SupportExportCredential(owner: \(binding.ownerID), epoch: \(binding.accountEpoch), token: <redacted>)" }
    var debugDescription: String { description }
    /// Reflection (debugger, `dump`) must not reveal the token either.
    var customMirror: Mirror { Mirror(self, children: ["owner": binding.ownerID, "accountEpoch": binding.accountEpoch, "token": "<redacted>"]) }
}

/// Returns the CURRENT authenticated binding, or nil when signed out / switching. Called repeatedly around every await.
typealias SupportExportOwnerProof = @Sendable () async -> SupportExportBinding?
/// Returns the token captured with its owner, or nil when there is no session. May refresh. Must not return a stale owner.
typealias SupportExportTokenSource = @Sendable () async throws -> SupportExportCredential?

enum SupportExportLocalUnavailableReason: String, Equatable, Sendable {
    /// The per-account support scope is not loaded (signed out, still loading, or failed to load).
    case noSupportScope = "no_support_scope"
    case ownerMismatch = "owner_mismatch"
    case accountEpochMismatch = "account_epoch_mismatch"
    /// The journal was unreadable and is waiting on the person's recovery choice.
    case journalNeedsRecovery = "journal_needs_recovery"
    /// The repository refused the read (invalidated, not loaded, stale epoch).
    case journalUnreadable = "journal_unreadable"
    case journalOwnerMismatch = "journal_owner_mismatch"
}

enum SupportExportLocalOutcome: Sendable {
    case journal(SupportJournal)
    case unavailable(SupportExportLocalUnavailableReason)
}

/// Reads the protected local journal for exactly this binding (matching coordinator owner + epoch, then
/// `repository.currentJournal`). Must not send, replay or mutate anything.
typealias SupportExportLocalSource = @Sendable (SupportExportBinding) async -> SupportExportLocalOutcome

// MARK: - Datasets (immutable, mirrors the SQL catalog)

enum SupportExportDataset: String, CaseIterable, Sendable {
    case profile
    case userSettings = "user_settings"
    case moods
    case quests
    case conversations
    case messages
    case circleMemberships = "circle_memberships"
    case exerciseSessions = "exercise_sessions"
    case subscriptions
    case crisisEvents = "crisis_events"
    case companionMemories = "companion_memories"
    case memoryFragments = "memory_fragments"
    case supportPrivacyState = "support_privacy_state"
    case supportSessions = "support_sessions"
    case supportActivities = "support_activities"
    case supportSessionEvents = "support_session_events"
    case supportMutationReceipts = "support_mutation_receipts"
    case supportProposals = "support_proposals"
    case supportContextReceipts = "support_context_receipts"
    case supportContextReceiptSources = "support_context_receipt_sources"
    case supportPrivacyOperations = "support_privacy_operations"
    case supportSuppressions = "support_suppressions"
    case supportMemoryEvents = "support_memory_events"
    case supportOnboardingConsent = "support_onboarding_consent"
    case offlineMutationReceipts = "offline_mutation_receipts"

    var title: String {
        switch self {
        case .profile: return "Profile"
        case .userSettings: return "Settings"
        case .moods: return "Mood check-ins"
        case .quests: return "Quests"
        case .conversations: return "Conversations"
        case .messages: return "Messages"
        case .circleMemberships: return "Circle memberships"
        case .exerciseSessions: return "Exercise sessions"
        case .subscriptions: return "Subscription"
        case .crisisEvents: return "Crisis records"
        case .companionMemories: return "Saved memories"
        case .memoryFragments: return "Memory suggestions from conversations"
        case .supportPrivacyState: return "Privacy state"
        case .supportSessions: return "Support sessions"
        case .supportActivities: return "Support activities"
        case .supportSessionEvents: return "Support session events"
        case .supportMutationReceipts: return "Support sync receipts"
        case .supportProposals: return "Suggested activities"
        case .supportContextReceipts: return "Reply context receipts"
        case .supportContextReceiptSources: return "Reply context sources"
        case .supportPrivacyOperations: return "Privacy and forget operations"
        case .supportSuppressions: return "Forgotten-source records"
        case .supportMemoryEvents: return "Memory change history"
        case .supportOnboardingConsent: return "Sign-up consent record"
        case .offlineMutationReceipts: return "Offline sync receipts"
        }
    }
}

/// Statements shown in the UI and written into the file so the subset is never described as "all data".
enum SupportExportScope {
    static let statement = "This file contains the records listed under \"cloud.datasets\" and \"local\". It is not a copy of everything MindFriend may hold or have ever held."
    static let notIncluded: [String] = [
        "Private Vault entries: they stay on this device only and are not part of this export.",
        "Apple Health readings: MindFriend does not read Apple Health for this export; they remain in Apple Health.",
        "Other areas of the app that keep their own records (for example journal entries) are not covered by this export version.",
        "Downloaded audio, images and other media files.",
    ]
    static let consistencyNote = "Each cloud dataset is read in separate pages, not from one database snapshot. A record changed while the export runs may appear in its older or newer state."
}

// MARK: - Errors (content-free: fixed codes only)

enum SupportExportError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The captured owner/epoch is no longer current. Whatever arrived is discarded, never published.
    case ownerChanged
    case cancelled
    case notConfigured
    case authenticationRequired
    /// The export function is not deployed on this server.
    case serviceUnavailable
    case temporaryFailure(status: Int)
    case rejected(status: Int)
    case transport(String)
    /// A reply that violates the page contract. `reason` is a fixed code, never page content.
    case malformed(dataset: String, reason: String)
    case catalogMismatch
    case limitExceeded(String)
    case fileFailure(String)

    var description: String {
        switch self {
        case .ownerChanged: return "SupportExportError.ownerChanged"
        case .cancelled: return "SupportExportError.cancelled"
        case .notConfigured: return "SupportExportError.notConfigured"
        case .authenticationRequired: return "SupportExportError.authenticationRequired"
        case .serviceUnavailable: return "SupportExportError.serviceUnavailable"
        case .temporaryFailure(let status): return "SupportExportError.temporaryFailure(\(status))"
        case .rejected(let status): return "SupportExportError.rejected(\(status))"
        case .transport(let code): return "SupportExportError.transport(\(code))"
        case .malformed(let dataset, let reason): return "SupportExportError.malformed(\(dataset), \(reason))"
        case .catalogMismatch: return "SupportExportError.catalogMismatch"
        case .limitExceeded(let code): return "SupportExportError.limitExceeded(\(code))"
        case .fileFailure(let code): return "SupportExportError.fileFailure(\(code))"
        }
    }

    /// Plain-language, content-free explanation for the person. Nothing was shared and the temporary file is gone.
    var userMessage: String {
        switch self {
        case .ownerChanged:
            return "Your account changed while the export was running, so it was cancelled and discarded."
        case .cancelled:
            return "The export was cancelled and nothing was saved."
        case .notConfigured:
            return "Export isn't available in this build."
        case .authenticationRequired:
            return "Please sign in again, then try the export again."
        case .serviceUnavailable:
            return "Export isn't available on the server yet. Nothing was saved."
        case .temporaryFailure:
            return "The server couldn't finish the export right now. Nothing was saved. Please try again in a moment."
        case .rejected:
            return "The server refused the export request. Nothing was saved."
        case .transport:
            return "The connection dropped during the export. Nothing was saved. Check your connection and try again."
        case .malformed, .catalogMismatch:
            return "The server's reply didn't match what this version of the app expects, so the export was stopped and nothing was saved."
        case .limitExceeded:
            return "Your data is larger than this version of the app can export in one file. Nothing was saved."
        case .fileFailure(let code):
            return code == "protected_data_unavailable"
                ? "The device was locked while the export was being saved. Nothing was kept. Unlock your device and try again."
                : (code == "no_space"
                    ? "There isn't enough free storage to build the export file. Nothing was kept."
                    : "The export file couldn't be saved safely. Nothing was kept.")
        }
    }
}

// MARK: - JSON value

/// Minimal JSON value that keeps integers exact and re-encodes deterministically (sorted keys).
indirect enum SupportExportJSON: Equatable, Sendable, Codable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([SupportExportJSON])
    case object([String: SupportExportJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([SupportExportJSON].self) { self = .array(v) }
        else if let v = try? c.decode([String: SupportExportJSON].self) { self = .object(v) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    var objectValue: [String: SupportExportJSON]? { if case .object(let v) = self { return v }; return nil }
    var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    var intValue: Int64? { if case .int(let v) = self { return v }; return nil }
    var boolValue: Bool? { if case .bool(let v) = self { return v }; return nil }
    var arrayValue: [SupportExportJSON]? { if case .array(let v) = self { return v }; return nil }
    var isNull: Bool { if case .null = self { return true }; return false }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    func data(using encoder: JSONEncoder = SupportExportJSON.encoder()) throws -> Data { try encoder.encode(self) }
}

// MARK: - Dates

enum SupportExportDates {
    /// UTC ISO-8601 with fractional seconds, e.g. 2026-11-07T04:00:00.123Z
    static func string(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

// MARK: - Transport

/// One request, one response. Injectable so tests drive a real `URLSession` through a `URLProtocol` stub.
protocol SupportExportTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionSupportExportTransport: SupportExportTransport {
    let session: URLSession
    let maxResponseBytes: Int

    init(session: URLSession, maxResponseBytes: Int = SupportExportConfiguration.standard.responseBytesCap) {
        self.session = session
        self.maxResponseBytes = maxResponseBytes
    }

    /// Ephemeral: no cache, no cookies, no ambient headers. The request itself is authoritative.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = SupportExportLimits.requestTimeout
        configuration.timeoutIntervalForResource = 120
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard data.count <= maxResponseBytes else { throw URLError(.dataLengthExceedsMaximum) }
        return (data, http)
    }
}

// MARK: - Protected temporary file

/// Creates, protects and discards the one temporary export file. Nothing outside `baseDirectory` is touched.
struct SupportExportFiles: Sendable {
    let baseDirectory: URL

    static func standard() -> SupportExportFiles {
        SupportExportFiles(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("MindFriendExports", isDirectory: true))
    }

    func begin(fileName: String) throws -> SupportExportFileWriter {
        let fm = FileManager.default
        let directory = baseDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        do {
            var attributes: [FileAttributeKey: Any] = [:]
            #if os(iOS) || os(watchOS) || os(tvOS)
            // Readable only after first unlock; a file opened while unlocked stays writable if the screen locks mid-export.
            attributes[.protectionKey] = FileProtectionType.completeUnlessOpen
            #endif
            try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true, attributes: attributes.isEmpty ? nil : attributes)
            try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: attributes.isEmpty ? nil : attributes)
            var options: Data.WritingOptions = []
            #if os(iOS) || os(watchOS) || os(tvOS)
            options.insert(.completeFileProtectionUnlessOpen)
            #endif
            try Data().write(to: url, options: options)   // creates the empty file with its protection class already applied
            try Self.excludeFromBackup(directory)
            try Self.excludeFromBackup(url)
            #if os(iOS) && !targetEnvironment(simulator)
            let applied = try fm.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType
            guard applied == .completeUnlessOpen || applied == .complete else { throw SupportExportError.fileFailure("protection_not_applied") }
            #endif
            let handle = try FileHandle(forWritingTo: url)
            return SupportExportFileWriter(url: url, directory: directory, handle: handle)
        } catch {
            try? fm.removeItem(at: directory)
            throw Self.mapFileError(error)
        }
    }

    /// Removes the export's own directory (and only that). Safe to call more than once.
    func discard(_ fileURL: URL) {
        let directory = fileURL.deletingLastPathComponent()
        guard directory.deletingLastPathComponent().standardizedFileURL == baseDirectory.standardizedFileURL,
              UUID(uuidString: directory.lastPathComponent) != nil else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    /// Removes export directories left behind by an interrupted earlier run.
    func purge(olderThan age: TimeInterval, now: Date = Date()) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for entry in entries where UUID(uuidString: entry.lastPathComponent) != nil {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) >= age { try? fm.removeItem(at: entry) }
        }
    }

    static func excludeFromBackup(_ url: URL) throws {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try target.setResourceValues(values)
        #if os(iOS) || os(tvOS) || os(watchOS)
        // On iOS the key reads back what was set. (macOS stores an xattr that this key does not report, so it is not verified there.)
        target.removeAllCachedResourceValues()   // the read-back must come from disk, not the URL's cache
        guard (try target.resourceValues(forKeys: [.isExcludedFromBackupKey])).isExcludedFromBackup == true else {
            throw SupportExportError.fileFailure("backup_exclusion_not_applied")
        }
        #endif
    }

    static func mapFileError(_ error: Error) -> SupportExportError {
        if let known = error as? SupportExportError { return known }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            if ns.code == NSFileWriteNoPermissionError || ns.code == NSFileReadNoPermissionError { return .fileFailure("protected_data_unavailable") }
            if ns.code == NSFileWriteOutOfSpaceError { return .fileFailure("no_space") }
        }
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(ENOSPC) { return .fileFailure("no_space") }
        return .fileFailure("write_failed")
    }
}

final class SupportExportFileWriter {
    let url: URL
    private let directory: URL
    private var handle: FileHandle?
    private(set) var bytesWritten = 0

    fileprivate init(url: URL, directory: URL, handle: FileHandle) {
        self.url = url
        self.directory = directory
        self.handle = handle
    }

    func write(_ data: Data) throws {
        guard let handle else { throw SupportExportError.fileFailure("closed") }
        do { try handle.write(contentsOf: data) } catch { throw SupportExportFiles.mapFileError(error) }
        bytesWritten += data.count
    }

    func write(_ text: String) throws { try write(Data(text.utf8)) }

    /// Flushes and closes. Verifies the size on disk equals what was written.
    func finish() throws -> Int {
        guard let handle else { throw SupportExportError.fileFailure("closed") }
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            self.handle = nil
            throw SupportExportFiles.mapFileError(error)
        }
        self.handle = nil
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
        guard size == bytesWritten else { throw SupportExportError.fileFailure("size_mismatch") }
        return bytesWritten
    }

    func discard() {
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: directory)
    }
}

// MARK: - Result

struct SupportExportDatasetSummary: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case included
        /// Table absent on the server: written to the file as unavailable, never as an empty success.
        case unavailable(reason: String)
    }
    let dataset: SupportExportDataset
    let status: Status
    let rowCount: Int
    let pages: Int
}

struct SupportExportLocalSummary: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case included
        case unavailable(SupportExportLocalUnavailableReason)
    }
    let status: Status
    let sessions: Int
    let drafts: Int
    let unsentMutations: Int
    let pendingTranscriptEvents: Int
    let pendingChatRequests: Int
    let unacknowledgedPrivacyChanges: Int
}

struct SupportExportSummary: Equatable, Sendable {
    let ownerID: UUID
    let exportedAt: Date
    let completedAt: Date
    let byteCount: Int
    let datasets: [SupportExportDatasetSummary]
    let local: SupportExportLocalSummary

    var totalRows: Int { datasets.reduce(0) { $0 + $1.rowCount } }
    var omissions: [String] {
        var out: [String] = []
        for item in datasets {
            if case .unavailable = item.status { out.append("\(item.dataset.title) is not available on the server and is not in this file.") }
        }
        if case .unavailable = local.status { out.append("The protected on-device support data could not be read and is not in this file.") }
        return out
    }
    var isComplete: Bool { omissions.isEmpty }
}

struct SupportExportResult: Sendable {
    let fileURL: URL
    let binding: SupportExportBinding
    let summary: SupportExportSummary
}

enum SupportExportProgress: Equatable, Sendable {
    case preparing
    case readingDevice
    case readingCloud(dataset: SupportExportDataset, index: Int, total: Int)
    case finishing
}

// MARK: - Page contract

/// A fully validated page. Only this value is ever turned into file bytes.
private struct ValidatedPage {
    let rows: [SupportExportJSON]
    let keys: [String]
    let hasMore: Bool
    let nextCursor: String?
    let unavailableReason: String?
}

private struct DecodedPage: Decodable {
    let catalogVersion: Int
    let catalogSize: Int
    let owner: UUID
    let dataset: String
    let status: String
    let reason: String?
    let after: String?
    let rows: [SupportExportJSON]
    let rowCount: Int
    let hasMore: Bool
    let nextCursor: String?
    let maxRows: Int
    let maxPageBytes: Int
    let requestedRows: Int

    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init(_ name: String) { stringValue = name }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        func key(_ name: String) -> Key { Key(name) }
        /// A key must be PRESENT (null allowed) so a dropped field can't pass as an absent cursor.
        func nullableString(_ name: String) throws -> String? {
            let k = key(name)
            guard c.contains(k) else { throw DecodingError.keyNotFound(k, .init(codingPath: [], debugDescription: "missing")) }
            if try c.decodeNil(forKey: k) { return nil }
            return try c.decode(String.self, forKey: k)
        }
        catalogVersion = try c.decode(Int.self, forKey: key("catalog_version"))
        catalogSize = try c.decode(Int.self, forKey: key("catalog_size"))
        owner = try c.decode(UUID.self, forKey: key("owner"))
        dataset = try c.decode(String.self, forKey: key("dataset"))
        status = try c.decode(String.self, forKey: key("status"))
        reason = try c.decodeIfPresent(String.self, forKey: key("reason"))
        after = try nullableString("after")
        rows = try c.decode([SupportExportJSON].self, forKey: key("rows"))
        rowCount = try c.decode(Int.self, forKey: key("row_count"))
        hasMore = try c.decode(Bool.self, forKey: key("has_more"))
        nextCursor = try nullableString("next_cursor")
        let limits = try c.nestedContainer(keyedBy: Key.self, forKey: key("limits"))
        maxRows = try limits.decode(Int.self, forKey: key("max_rows"))
        maxPageBytes = try limits.decode(Int.self, forKey: key("max_page_bytes"))
        requestedRows = try limits.decode(Int.self, forKey: key("requested_rows"))
    }
}

// MARK: - Exporter

final class SupportDataExporter: Sendable {
    static let rpcPath = "rest/v1/rpc/export_owner_data_page"

    let binding: SupportExportBinding

    private let ownerProof: SupportExportOwnerProof
    private let tokenSource: SupportExportTokenSource
    private let local: SupportExportLocalSource
    private let transport: any SupportExportTransport
    private let files: SupportExportFiles
    private let endpoint: URL
    private let apiKey: String
    private let configuration: SupportExportConfiguration
    private let appVersion: String
    private let clock: @Sendable () -> Date

    init(
        binding: SupportExportBinding,
        ownerProof: @escaping SupportExportOwnerProof,
        tokenSource: @escaping SupportExportTokenSource,
        local: @escaping SupportExportLocalSource,
        transport: any SupportExportTransport,
        files: SupportExportFiles = .standard(),
        projectURL: URL,
        apiKey: String,
        appVersion: String,
        configuration: SupportExportConfiguration = .standard,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.binding = binding
        self.ownerProof = ownerProof
        self.tokenSource = tokenSource
        self.local = local
        self.transport = transport
        self.files = files
        self.endpoint = projectURL.appendingPathComponent(Self.rpcPath)
        self.apiKey = apiKey
        self.appVersion = appVersion
        self.configuration = configuration
        self.clock = clock
    }

    /// Removes an export file produced by this exporter (after sharing, dismissal or an account change).
    func discard(_ result: SupportExportResult) { files.discard(result.fileURL) }
    func purgeLeftovers(olderThan age: TimeInterval = 3_600) { files.purge(olderThan: age) }
    /// Removes export directories an interrupted earlier run left in the app's temporary export folder.
    static func purgeLeftoverFiles(olderThan age: TimeInterval = 3_600) { SupportExportFiles.standard().purge(olderThan: age) }

    /// True only while the captured owner and epoch are still the signed-in ones. Call before presenting a share sheet.
    func isStillCurrent() async -> Bool { await ownerProof() == binding && !Task.isCancelled }

    // MARK: Run

    func run(progress: @escaping @Sendable (SupportExportProgress) -> Void = { _ in }) async throws -> SupportExportResult {
        progress(.preparing)
        try await requireCurrent()
        guard Self.isAllowedEndpoint(endpoint), !apiKey.isEmpty else { throw SupportExportError.notConfigured }
        files.purge(olderThan: 3_600)

        let startedAt = clock()
        let writer = try files.begin(fileName: Self.fileName(for: startedAt))
        do {
            let summary = try await produce(into: writer, startedAt: startedAt, progress: progress)
            try await requireCurrent()                                  // last check before the file can be published
            return SupportExportResult(fileURL: writer.url, binding: binding, summary: summary)
        } catch {
            writer.discard()
            throw Self.normalized(error)
        }
    }

    private static func normalized(_ error: Error) -> SupportExportError {
        if let known = error as? SupportExportError { return known }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError, urlError.code == .cancelled { return .cancelled }
        return SupportExportFiles.mapFileError(error)
    }

    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "MindFriend-Data-Export-\(formatter.string(from: date)).json"
    }

    // MARK: Document

    private func produce(into writer: SupportExportFileWriter, startedAt: Date, progress: @escaping @Sendable (SupportExportProgress) -> Void) async throws -> SupportExportSummary {
        // 1. Device data first: cheap, and it fixes the local part of the document before any network wait.
        progress(.readingDevice)
        let outcome = await local(binding)
        try await requireCurrent()
        let localSection: (json: SupportExportJSON, summary: SupportExportLocalSummary)
        switch outcome {
        case .journal(let journal):
            guard journal.ownerID == binding.ownerID else {
                localSection = Self.unavailableLocal(.journalOwnerMismatch)
                break
            }
            localSection = try Self.localSection(for: journal)
        case .unavailable(let reason):
            localSection = Self.unavailableLocal(reason)
        }

        // 2. Header: owner, time, scope and limits make the extent of the file inspectable.
        try writer.write("{\n")
        try writeMember(writer, "export", Self.headerJSON(startedAt: startedAt, appVersion: appVersion))
        try writeMember(writer, "owner", .object(["user_id": .string(binding.ownerID.uuidString.lowercased())]))
        try writeMember(writer, "scope", Self.scopeJSON())
        try writeMember(writer, "limits", Self.limitsJSON(configuration))
        try writeMember(writer, "local", localSection.json)
        try writer.write("\"cloud\": {\"datasets\": {\n")

        // 3. Cloud datasets, one validated page at a time, streamed to the file.
        let datasets = SupportExportDataset.allCases
        var summaries: [SupportExportDatasetSummary] = []
        for (index, dataset) in datasets.enumerated() {
            progress(.readingCloud(dataset: dataset, index: index + 1, total: datasets.count))
            summaries.append(try await exportDataset(dataset, into: writer, isLast: index == datasets.count - 1))
        }
        try writer.write("}},\n")

        // 4. Completeness footer, then close. A summary exists only if every page validated.
        progress(.finishing)
        let completedAt = clock()
        let partial = SupportExportSummary(
            ownerID: binding.ownerID, exportedAt: startedAt, completedAt: completedAt, byteCount: 0,
            datasets: summaries, local: localSection.summary)
        try writeMember(writer, "completeness", Self.completenessJSON(partial, completedAt: completedAt), last: true)
        try writer.write("}\n")
        let byteCount = try writer.finish()
        return SupportExportSummary(
            ownerID: binding.ownerID, exportedAt: startedAt, completedAt: completedAt, byteCount: byteCount,
            datasets: summaries, local: localSection.summary)
    }

    private func writeMember(_ writer: SupportExportFileWriter, _ key: String, _ value: SupportExportJSON, last: Bool = false) throws {
        let encoder = SupportExportJSON.encoder()
        try writer.write("\(try SupportExportJSON.string(key).data(using: encoder).utf8String): ")
        try writer.write(try value.data(using: encoder))
        try writer.write(last ? "\n" : ",\n")
        try checkFileSize(writer)
    }

    private func checkFileSize(_ writer: SupportExportFileWriter) throws {
        if writer.bytesWritten > configuration.maxFileBytes { throw SupportExportError.limitExceeded("file_bytes") }
    }

    // MARK: Cloud paging

    private func exportDataset(_ dataset: SupportExportDataset, into writer: SupportExportFileWriter, isLast: Bool) async throws -> SupportExportDatasetSummary {
        let name = dataset.rawValue
        let encoder = SupportExportJSON.encoder()
        var cursor: String?
        var previousKey: String?
        var pages = 0
        var rowCount = 0
        var wroteHeader = false
        var firstRow = true
        var unavailableReason: String?

        while true {
            pages += 1
            if pages > configuration.maxPagesPerDataset { throw SupportExportError.limitExceeded("pages") }
            let page = try await fetchPage(dataset, after: cursor, previousKey: previousKey)

            if let reason = page.unavailableReason {
                guard pages == 1 else { throw SupportExportError.malformed(dataset: name, reason: "unavailable_midway") }
                unavailableReason = reason
                break
            }
            if !wroteHeader {
                try writer.write("\(try SupportExportJSON.string(name).data(using: encoder).utf8String): {\"status\": \"available\", \"rows\": [\n")
                wroteHeader = true
            }
            for row in page.rows {
                try writer.write(firstRow ? "" : ",\n")
                try writer.write(try row.data(using: encoder))
                firstRow = false
            }
            try checkFileSize(writer)
            rowCount += page.rows.count
            previousKey = page.keys.last ?? previousKey
            guard page.hasMore else { break }
            cursor = page.nextCursor
        }

        if let unavailableReason {
            try writer.write("\(try SupportExportJSON.string(name).data(using: encoder).utf8String): {\"status\": \"unavailable\", \"reason\": \(try SupportExportJSON.string(unavailableReason).data(using: encoder).utf8String), \"rows\": [], \"row_count\": 0, \"pages\": 1, \"complete\": false}")
            try writer.write(isLast ? "\n" : ",\n")
            return SupportExportDatasetSummary(dataset: dataset, status: .unavailable(reason: unavailableReason), rowCount: 0, pages: 1)
        }
        try writer.write("\n], \"row_count\": \(rowCount), \"pages\": \(pages), \"complete\": true}")
        try writer.write(isLast ? "\n" : ",\n")
        try checkFileSize(writer)
        return SupportExportDatasetSummary(dataset: dataset, status: .included, rowCount: rowCount, pages: pages)
    }

    private func fetchPage(_ dataset: SupportExportDataset, after: String?, previousKey: String?) async throws -> ValidatedPage {
        let body: SupportExportJSON = .object([
            "p_expected_owner": .string(binding.ownerID.uuidString.lowercased()),
            "p_dataset": .string(dataset.rawValue),
            "p_after": after.map { .string($0) } ?? .null,
            "p_limit": .int(Int64(SupportExportLimits.pageRows)),
        ])
        let (status, data) = try await perform(try body.data())
        guard (200..<300).contains(status) else { throw Self.classify(status: status, data: data) }
        let decoded: DecodedPage
        do { decoded = try JSONDecoder().decode(DecodedPage.self, from: data) }
        catch { throw SupportExportError.malformed(dataset: dataset.rawValue, reason: "undecodable_page") }
        return try validate(decoded, dataset: dataset, after: after, previousKey: previousKey)
    }

    private func validate(_ page: DecodedPage, dataset: SupportExportDataset, after: String?, previousKey: String?) throws -> ValidatedPage {
        let name = dataset.rawValue
        func bad(_ reason: String) -> SupportExportError { .malformed(dataset: name, reason: reason) }

        guard page.catalogVersion == SupportExportLimits.catalogVersion,
              page.catalogSize == SupportExportDataset.allCases.count else { throw SupportExportError.catalogMismatch }
        guard page.owner == binding.ownerID else { throw bad("owner_echo") }
        guard page.dataset == name else { throw bad("dataset_echo") }
        guard page.after == after else { throw bad("cursor_echo") }
        guard page.maxRows == SupportExportLimits.pageRows, page.maxPageBytes == SupportExportLimits.pageBytesTarget,
              page.requestedRows == SupportExportLimits.pageRows else { throw bad("limits_echo") }
        guard page.rowCount == page.rows.count, page.rows.count <= SupportExportLimits.pageRows else { throw bad("row_count") }

        if page.status == "unavailable" {
            guard page.rows.isEmpty, !page.hasMore, page.nextCursor == nil, page.reason == "table_absent" else { throw bad("unavailable_shape") }
            return ValidatedPage(rows: [], keys: [], hasMore: false, nextCursor: nil, unavailableReason: page.reason)
        }
        guard page.status == "available" else { throw bad("status") }

        var keys: [String] = []
        keys.reserveCapacity(page.rows.count)
        var last = previousKey
        for row in page.rows {
            guard let object = row.objectValue, let key = object["export_key"]?.stringValue, !key.isEmpty else { throw bad("row_shape") }
            guard let ownerText = object["export_owner_id"]?.stringValue, UUID(uuidString: ownerText) == binding.ownerID else { throw bad("row_owner") }
            // Defense in depth for tables that also carry their own owner column.
            if let userText = object["user_id"]?.stringValue, UUID(uuidString: userText) != binding.ownerID { throw bad("row_user") }
            if let last, !last.utf8.lexicographicallyPrecedes(key.utf8) { throw bad("key_order") }
            last = key
            keys.append(key)
        }
        if let first = keys.first, let after, !after.utf8.lexicographicallyPrecedes(first.utf8) { throw bad("cursor_progress") }
        if page.hasMore {
            guard !keys.isEmpty, let next = page.nextCursor, next == keys.last else { throw bad("next_cursor") }
        } else {
            guard page.nextCursor == nil else { throw bad("next_cursor_without_more") }
        }
        return ValidatedPage(rows: page.rows, keys: keys, hasMore: page.hasMore, nextCursor: page.nextCursor, unavailableReason: nil)
    }

    // MARK: Request pipeline

    /// Owner/epoch/cancellation are verified before the token fetch, after it, immediately before dispatch, after the
    /// response await and on the failure path. A response observed after the owner changed is dropped undecoded.
    private func perform(_ body: Data) async throws -> (status: Int, data: Data) {
        try await requireCurrent()                                       // 1. before token fetch
        let credential: SupportExportCredential?
        do {
            credential = try await tokenSource()
        } catch is CancellationError {
            throw SupportExportError.cancelled
        } catch let error as SupportExportError {
            throw error
        } catch {
            try await requireCurrent()
            throw SupportExportError.authenticationRequired
        }
        try await requireCurrent()                                       // 2. after token fetch
        guard let credential else { throw SupportExportError.authenticationRequired }
        // A token captured for another owner/epoch is never used, whatever the proof says.
        guard credential.binding == binding else { throw SupportExportError.ownerChanged }
        guard Self.isValidToken(credential.accessToken) else { throw SupportExportError.authenticationRequired }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = SupportExportLimits.requestTimeout
        request.httpShouldHandleCookies = false
        // Set on the request itself: the SDK client would replace a supplied Authorization header with its ambient session's.
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        try await requireCurrent()                                       // 3. immediately before dispatch
        let response: (Data, HTTPURLResponse)
        do {
            response = try await transport.send(request)
        } catch {
            try await requireCurrent()                                   // 5. owner change wins over a transport error
            throw Self.classify(transportError: error)
        }
        try await requireCurrent()                                       // 4. after the await, before anything is decoded
        return (response.1.statusCode, response.0)
    }

    private func requireCurrent() async throws {
        if Task.isCancelled { throw SupportExportError.cancelled }
        guard await ownerProof() == binding else { throw SupportExportError.ownerChanged }
        if Task.isCancelled { throw SupportExportError.cancelled }
    }

    // MARK: Classification (pure)

    /// https only; plain http is allowed solely for a loopback development stack.
    static func isAllowedEndpoint(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if scheme == "https" { return true }
        return scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
    }

    /// Conservative bearer-token charset: refuses anything that could split a header.
    static func isValidToken(_ token: String) -> Bool {
        guard !token.isEmpty, token.utf8.count <= 8_192 else { return false }
        return token.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45 || $0 == 46
                || $0 == 95 || $0 == 126 || $0 == 43 || $0 == 47 || $0 == 61
        }
    }

    static func classify(transportError error: Error) -> SupportExportError {
        if error is CancellationError { return .cancelled }
        guard let urlError = error as? URLError else { return .transport("other") }
        switch urlError.code {
        case .cancelled: return .cancelled
        case .timedOut: return .transport("timeout")
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: return .transport("offline")
        case .networkConnectionLost: return .transport("connection_lost")
        case .dataLengthExceedsMaximum: return .limitExceeded("response_bytes")
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected,
             .appTransportSecurityRequiresSecureConnection:
            return .transport("secure_connection")
        default: return .transport("other")
        }
    }

    /// Non-2xx → typed error. The body is read only for PostgREST's short SQLSTATE `code`; its text is never kept.
    static func classify(status: Int, data: Data) -> SupportExportError {
        let code = (try? JSONDecoder().decode(SupportExportJSON.self, from: data))?.objectValue?["code"]?.stringValue
        switch status {
        case 401: return .authenticationRequired
        case 403: return code == "42501" ? .ownerChanged : .authenticationRequired
        case 404: return .serviceUnavailable
        case 408, 425, 429, 500...599: return .temporaryFailure(status: status)
        default: return .rejected(status: status)
        }
    }

    // MARK: Document sections

    private static func headerJSON(startedAt: Date, appVersion: String) -> SupportExportJSON {
        .object([
            "format": .string(SupportExportLimits.documentFormat),
            "schema_version": .int(Int64(SupportExportLimits.documentSchemaVersion)),
            "exported_at": .string(SupportExportDates.string(startedAt)),
            "app_version": .string(appVersion),
            "row_extras": .string("Cloud rows carry export_owner_id and export_key, added by the export for ownership checks and ordering."),
        ])
    }

    private static func scopeJSON() -> SupportExportJSON {
        .object([
            "statement": .string(SupportExportScope.statement),
            "cloud_datasets": .array(SupportExportDataset.allCases.map { .string($0.rawValue) }),
            "local_data": .string("Protected on-device support journal: drafts, transcript events, and the pending outbox, with their sync status."),
            "private_vault": .object([
                "included": .bool(false),
                "reason": .string("device_only"),
                "note": .string(SupportExportScope.notIncluded[0]),
            ]),
            "not_included": .array(SupportExportScope.notIncluded.map { .string($0) }),
            "consistency": .string(SupportExportScope.consistencyNote),
        ])
    }

    private static func limitsJSON(_ configuration: SupportExportConfiguration) -> SupportExportJSON {
        .object([
            "cloud": .object([
                "page_rows": .int(Int64(SupportExportLimits.pageRows)),
                "page_bytes_target": .int(Int64(SupportExportLimits.pageBytesTarget)),
                "response_bytes_cap": .int(Int64(configuration.responseBytesCap)),
                "max_pages_per_dataset": .int(Int64(configuration.maxPagesPerDataset)),
                "max_file_bytes": .int(Int64(configuration.maxFileBytes)),
                "catalog_version": .int(Int64(SupportExportLimits.catalogVersion)),
            ]),
            "local": .object([
                "journal_max_bytes": .int(Int64(SupportSessionLimits.journalMaxBytes)),
            ]),
            "behavior_on_limit": .string("The export stops and is discarded; a file that hit a limit is never shared as if complete."),
        ])
    }

    private static func completenessJSON(_ summary: SupportExportSummary, completedAt: Date) -> SupportExportJSON {
        var cloud: [String: SupportExportJSON] = [:]
        for item in summary.datasets {
            switch item.status {
            case .included:
                cloud[item.dataset.rawValue] = .object(["status": .string("available"), "rows": .int(Int64(item.rowCount)), "pages": .int(Int64(item.pages))])
            case .unavailable(let reason):
                cloud[item.dataset.rawValue] = .object(["status": .string("unavailable"), "reason": .string(reason)])
            }
        }
        let localStatus: SupportExportJSON
        switch summary.local.status {
        case .included: localStatus = .object(["status": .string("included")])
        case .unavailable(let reason): localStatus = .object(["status": .string("unavailable"), "reason": .string(reason.rawValue)])
        }
        return .object([
            "complete": .bool(summary.isComplete),
            "completed_at": .string(SupportExportDates.string(completedAt)),
            "total_cloud_rows": .int(Int64(summary.totalRows)),
            "omissions": .array(summary.omissions.map { .string($0) }),
            "cloud": .object(cloud),
            "local": localStatus,
        ])
    }

    // MARK: Local journal

    private static func unavailableLocal(_ reason: SupportExportLocalUnavailableReason) -> (json: SupportExportJSON, summary: SupportExportLocalSummary) {
        let json: SupportExportJSON = .object([
            "status": .string("unavailable"),
            "reason": .string(reason.rawValue),
            "note": .string("The protected on-device support data could not be read, so it is not in this file."),
        ])
        return (json, SupportExportLocalSummary(
            status: .unavailable(reason), sessions: 0, drafts: 0, unsentMutations: 0, pendingTranscriptEvents: 0,
            pendingChatRequests: 0, unacknowledgedPrivacyChanges: 0))
    }

    /// Encodes the ACTUAL journal value. UUID-keyed dictionaries (which Codable writes as flat key/value arrays) are
    /// reshaped into objects for readability; any other field passes through exactly as encoded.
    static func localSection(for journal: SupportJournal) throws -> (json: SupportExportJSON, summary: SupportExportLocalSummary) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SupportExportDates.string(date))
        }
        let data: Data
        do { data = try encoder.encode(journal) }
        catch { throw SupportExportError.fileFailure("journal_encoding") }
        let tree: SupportExportJSON
        do { tree = try JSONDecoder().decode(SupportExportJSON.self, from: data) }
        catch { throw SupportExportError.fileFailure("journal_encoding") }

        let unsentMutations = journal.intents.count
        let unconfirmedAttempts = journal.attempts.count
        let pendingTranscript = journal.transcriptEvents.filter { $0.syncState == .pending }.count
        let savedTranscript = journal.transcriptEvents.count - pendingTranscript
        let unacknowledgedPrivacy = journal.suppressions.filter { !$0.isAcknowledged }.count
        let unsentMemoryChanges = journal.memoryChanges.filter { !$0.sent }.count
        let drafts = journal.drafts.values.filter { !$0.isEmpty }.count
        func syncCounts<S: Sequence>(_ statuses: S) -> SupportExportJSON where S.Element == SupportSyncStatus {
            var counts: [String: Int64] = [:]
            for status in statuses { counts[status.rawValue, default: 0] += 1 }
            return .object(counts.mapValues { .int($0) })
        }
        let counts: [String: SupportExportJSON] = [
            "sessions": .int(Int64(journal.sessions.count)),
            "activities": .int(Int64(journal.activities.count)),
            "events": .int(Int64(journal.events.count)),
            "drafts_with_text": .int(Int64(drafts)),
            "unsent_mutations": .int(Int64(unsentMutations)),
            "attempts_awaiting_confirmation": .int(Int64(unconfirmedAttempts)),
            "transcript_events_pending": .int(Int64(pendingTranscript)),
            "transcript_events_saved": .int(Int64(savedTranscript)),
            "pending_chat_requests": .int(Int64(journal.pendingChatRequests.count)),
            "unacknowledged_privacy_suppressions": .int(Int64(unacknowledgedPrivacy)),
            "unsent_memory_changes": .int(Int64(unsentMemoryChanges)),
            "memory_records_cached": .int(Int64(journal.memoryRecords.count)),
            "conflicts": .int(Int64(journal.conflicts.count)),
            "failures": .int(Int64(journal.failures.count)),
            "tombstones": .int(Int64(journal.tombstones.count)),
        ]
        let status: SupportExportJSON = .object([
            "counts": .object(counts),
            "session_sync_status": syncCounts(journal.sessions.values.map(\.syncStatus)),
            "activity_sync_status": syncCounts(journal.activities.values.map(\.syncStatus)),
            "personalized_cloud_paused": .bool(journal.personalizedCloudPaused),
            "commit_sequence": .int(journal.commitSequence),
            "meaning": .object([
                "drafts": .string("Text saved only on this device. A draft is never sent without a deliberate Send."),
                "unsent_mutations": .string("Changes saved on this device that have not yet reached your account (pending outbox)."),
                "attempts_awaiting_confirmation": .string("Changes that were sent but whose result is not yet confirmed."),
                "transcript_events_pending": .string("Voice/text transcript lines saved on this device and not yet confirmed by your account."),
                "pending_chat_requests": .string("Messages you chose to send whose result is not yet confirmed."),
                "unacknowledged_privacy_suppressions": .string("Forget/stop-using choices not yet confirmed by your account."),
            ]),
        ])
        let json: SupportExportJSON = .object([
            "status": .string("included"),
            "source": .string("Protected on-device support journal, read without sending or replaying anything."),
            "encoding": .object([
                "dates": .string("UTC ISO-8601"),
                "uuid_keyed_collections": .string("Collections keyed by a UUID are written as objects keyed by that UUID."),
            ]),
            "status_summary": status,
            "journal": reshapedJournal(tree),
        ])
        let summary = SupportExportLocalSummary(
            status: .included, sessions: journal.sessions.count, drafts: drafts, unsentMutations: unsentMutations,
            pendingTranscriptEvents: pendingTranscript, pendingChatRequests: journal.pendingChatRequests.count,
            unacknowledgedPrivacyChanges: unacknowledgedPrivacy + unsentMemoryChanges)
        return (json, summary)
    }

    /// Top-level `[UUID: Value]` journal fields that Codable emits as `[key, value, key, value, …]`.
    private static let uuidKeyedFields: Set<String> = [
        "sessions", "activities", "drafts", "serverRevisions", "nextTranscriptSequence", "tombstones",
        "pendingChatRequests", "reservedConversationIDs", "memoryRecords", "declinedTemplates",
    ]

    static func reshapedJournal(_ tree: SupportExportJSON) -> SupportExportJSON {
        guard case .object(var fields) = tree else { return tree }
        for name in uuidKeyedFields {
            guard case .array(let flat)? = fields[name], flat.count % 2 == 0 else { continue }
            var object: [String: SupportExportJSON] = [:]
            var ok = true
            var index = 0
            while index < flat.count {
                guard case .string(let key) = flat[index], UUID(uuidString: key) != nil, object[key] == nil else { ok = false; break }
                var value = flat[index + 1]
                if name == "declinedTemplates", case .array(let items) = value {
                    value = .array(items.sorted { ($0.stringValue ?? "") < ($1.stringValue ?? "") })
                }
                object[key] = value
                index += 2
            }
            if ok { fields[name] = .object(object) }
        }
        return .object(fields)
    }
}

// MARK: - Run / share state machine (generation-bound)

/// The state machine behind the export screen. Every run and every share sheet is bound to the GENERATION in which it
/// started; `reset()` (account change, dismissal, discard) and every new `start` open a new generation. A callback that
/// belongs to an older generation (a cancelled run finishing late, a late progress hop, a delayed share-sheet completion)
/// may still delete the file IT created, by its own exporter and exact result, but it can never change the current phase,
/// clear the current task handle, publish, or discard the newer run's file.
@MainActor
final class SupportExportController: ObservableObject {
    enum Phase {
        case idle
        case running(String)
        case ready(SupportExportResult)
        case failed(String)
    }

    /// Everything a share sheet needs to clean up exactly what it shared, long after the screen's state moved on.
    struct ShareTicket {
        let generation: Int
        let result: SupportExportResult
        let exporter: SupportDataExporter
    }

    @Published private(set) var phase: Phase = .idle
    /// Bound to the sheet presentation.
    @Published var showShareSheet = false

    private(set) var generation = 0
    /// Test seam: stale completions (finish / fail / share-sheet end) that were recognised and ignored.
    private(set) var ignoredStaleCompletions = 0
    private var task: Task<Void, Never>?
    private var exporter: SupportDataExporter?

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    var shareTicket: ShareTicket? {
        guard case .ready(let result) = phase, let exporter else { return nil }
        return ShareTicket(generation: generation, result: result, exporter: exporter)
    }

    /// Starts a fresh run (a previous file is discarded first). Does nothing while a run is in flight.
    func start(makeExporter: () -> SupportDataExporter?) {
        guard !isRunning else { return }
        reset()
        guard let exporter = makeExporter() else {
            phase = .failed("Sign in to export your data.")
            return
        }
        let mine = generation
        self.exporter = exporter
        phase = .running("Preparing…")
        // Strong only while this run is alive; a late hop is dropped by the generation check in `apply`.
        let sink: @Sendable (SupportExportProgress) -> Void = { progress in
            Task { @MainActor in self.apply(progress, generation: mine) }
        }
        task = Task { [weak self] in
            do {
                let result = try await exporter.run(progress: sink)
                let stillCurrent = await exporter.isStillCurrent()
                let cancelled = Task.isCancelled
                // No suspension from here to the state change.
                guard let self else { exporter.discard(result); return }
                self.finish(result: result, exporter: exporter, generation: mine, stillCurrent: stillCurrent, cancelled: cancelled)
            } catch {
                self?.fail(error, generation: mine)
            }
        }
    }

    /// The Cancel button: stops the current run only.
    func cancel() { task?.cancel() }

    /// Opens a new generation, cancels any run, deletes any finished file and returns to idle.
    func reset() {
        generation += 1
        task?.cancel()
        task = nil
        if case .ready(let result) = phase { exporter?.discard(result) }
        exporter = nil
        showShareSheet = false
        phase = .idle
    }

    /// Shows the share sheet only if the captured owner/epoch is still current and nothing was reset meanwhile.
    func presentShare() async {
        guard case .ready = phase, let exporter else { return }
        let mine = generation
        let current = await exporter.isStillCurrent()
        guard mine == generation else { return }   // a reset/restart already owns the file
        if current {
            showShareSheet = true
        } else {
            reset()
            phase = .failed(SupportExportError.ownerChanged.userMessage)
        }
    }

    /// The share sheet ended (sent, saved or cancelled), possibly long after a reset or a newer export. The exact file it
    /// shared is always deleted; the screen state is touched only if this is still the same generation.
    func finishSharing(_ ticket: ShareTicket) {
        ticket.exporter.discard(ticket.result)
        guard ticket.generation == generation else { ignoredStaleCompletions += 1; return }
        reset()
    }

    // MARK: Generation-guarded publishing (internal for tests)

    func apply(_ progress: SupportExportProgress, generation mine: Int) {
        guard mine == generation else { return }      // a late hop from an older run is dropped
        guard case .running = phase else { return }   // a late update must never overwrite a result
        switch progress {
        case .preparing: phase = .running("Preparing…")
        case .readingDevice: phase = .running("Reading support data saved on this device…")
        case .readingCloud(let dataset, let index, let total): phase = .running("Reading \(dataset.title) (\(index) of \(total))…")
        case .finishing: phase = .running("Finishing…")
        }
    }

    func finish(result: SupportExportResult, exporter runExporter: SupportDataExporter, generation mine: Int, stillCurrent: Bool, cancelled: Bool) {
        guard mine == generation else {
            runExporter.discard(result)               // this run's own file, by its own exporter; the newer run is untouched
            ignoredStaleCompletions += 1
            return
        }
        task = nil
        if cancelled {
            runExporter.discard(result)
            exporter = nil
            phase = .idle
        } else if !stillCurrent {
            runExporter.discard(result)
            exporter = nil
            phase = .failed(SupportExportError.ownerChanged.userMessage)
        } else {
            exporter = runExporter                    // the ready file is always paired with the exporter that can delete it
            phase = .ready(result)
        }
    }

    func fail(_ error: Error, generation mine: Int) {
        // The engine already removed the file of a failed or cancelled run.
        guard mine == generation else { ignoredStaleCompletions += 1; return }
        task = nil
        exporter = nil
        if let known = error as? SupportExportError {
            phase = known == .cancelled ? .idle : .failed(known.userMessage)
        } else {
            phase = .failed(SupportExportError.fileFailure("write_failed").userMessage)
        }
    }
}

private extension Data {
    var utf8String: String { String(decoding: self, as: UTF8.self) }
}
