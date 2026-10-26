//
//  WellbeingDebtServiceTests.swift
//  MindFriendAppTests
//
//  N006: Wellbeing Debt Calculator - Unit Tests
//  Tests for debt score fetching, transaction logging, and recovery program generation
//
//  FIXME: Partially disabled due to API mismatches:
//  - RecoveryProgram has no members: intensity, currentDebt, dailyPlan
//  - WellbeingDebtProfile has no members: learnedThreshold, lastCrashDate, crashHistory
//  The working tests for DebtScore, Transaction, and enums are kept.

import XCTest
import SwiftUI
import Supabase
@testable import MindFriendApp

final class WellbeingDebtServiceTests: XCTestCase {

    // MARK: - Model Tests

    func testDebtScoreDecoding() throws {
        // Given: Valid JSON for a debt score
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "user_id": "user-123",
            "date": "2026-01-25",
            "daily_balance": 5.0,
            "rolling_debt_7day": -15.0,
            "rolling_debt_14day": -25.0,
            "rolling_debt_30day": -40.0,
            "trend": {
                "direction": "worsening",
                "velocity": -2.5,
                "projection_7day": -32.5
            },
            "threshold_status": {
                "current_debt": -25.0,
                "threshold": -50.0,
                "severity": "warning",
                "days_until_crash": 10,
                "confidence": 0.75
            },
            "created_at": "2026-01-25T10:30:00Z"
        }
        """.data(using: .utf8)!

        // When: Decoding the JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let score = try decoder.decode(DebtScore.self, from: json)

        // Then: Values are correctly decoded
        XCTAssertEqual(score.date, "2026-01-25")
        XCTAssertEqual(score.dailyBalance, 5.0)
        XCTAssertEqual(score.rollingDebt14Day, -25.0)
        XCTAssertEqual(score.trend.direction, .worsening)
        XCTAssertEqual(score.trend.velocity, -2.5)
        XCTAssertEqual(score.thresholdStatus.severity, .warning)
        XCTAssertEqual(score.thresholdStatus.daysUntilCrash, 10)
    }

    func testTransactionDecoding() throws {
        // Given: Valid JSON for a transaction
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440001",
            "user_id": "user-123",
            "date": "2026-01-25",
            "type": "deposit",
            "category": "exercise_completion",
            "amount": 5.0,
            "source": "exercise_sessions",
            "description": "Completed meditation session",
            "created_at": "2026-01-25T14:00:00Z"
        }
        """.data(using: .utf8)!

        // When: Decoding the JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let transaction = try decoder.decode(WellbeingTransaction.self, from: json)

        // Then: Values are correctly decoded
        XCTAssertEqual(transaction.type, .deposit)
        XCTAssertEqual(transaction.category, .exerciseCompletion)
        XCTAssertEqual(transaction.amount, 5.0)
        XCTAssertEqual(transaction.source, .exerciseSessions)
    }

    func testThresholdSeverityDisplayName() {
        // Test severity display names
        XCTAssertEqual(ThresholdSeverity.safe.displayName, "Safe")
        XCTAssertEqual(ThresholdSeverity.warning.displayName, "Warning")
        XCTAssertEqual(ThresholdSeverity.danger.displayName, "Danger")
    }

    func testThresholdSeverityColor() {
        // Test severity colors
        XCTAssertEqual(ThresholdSeverity.safe.color, "green")
        XCTAssertEqual(ThresholdSeverity.warning.color, "yellow")
        XCTAssertEqual(ThresholdSeverity.danger.color, "red")
    }

    func testDebtTrendDirection() {
        // Test trend direction encoding/decoding
        XCTAssertEqual(DebtTrendDirection.improving.rawValue, "improving")
        XCTAssertEqual(DebtTrendDirection.worsening.rawValue, "worsening")
        XCTAssertEqual(DebtTrendDirection.stable.rawValue, "stable")
    }

    func testTransactionCategories() {
        // Test deposit categories
        XCTAssertEqual(TransactionCategory.sleepQuality.rawValue, "sleep_quality")
        XCTAssertEqual(TransactionCategory.exerciseCompletion.rawValue, "exercise_completion")
        XCTAssertEqual(TransactionCategory.socialConnection.rawValue, "social_connection")
        XCTAssertEqual(TransactionCategory.questCompletion.rawValue, "quest_completion")

        // Test withdrawal categories
        XCTAssertEqual(TransactionCategory.poorSleep.rawValue, "poor_sleep")
        XCTAssertEqual(TransactionCategory.workStress.rawValue, "work_stress")
        XCTAssertEqual(TransactionCategory.socialIsolation.rawValue, "social_isolation")
        XCTAssertEqual(TransactionCategory.negativeMood.rawValue, "negative_mood")
    }

    func testTransactionSources() {
        // Test transaction sources
        XCTAssertEqual(TransactionSource.healthkit.rawValue, "healthkit")
        XCTAssertEqual(TransactionSource.moodLog.rawValue, "mood_log")
        XCTAssertEqual(TransactionSource.exerciseSessions.rawValue, "exercise_sessions")
        XCTAssertEqual(TransactionSource.circlePosts.rawValue, "circle_posts")
        XCTAssertEqual(TransactionSource.circadianShield.rawValue, "circadian_shield")
    }

    // MARK: - Recovery Program Model Tests (DISABLED)
    // FIXME: Re-enable when RecoveryProgram API is updated
    // RecoveryProgram has different structure than expected (no intensity, currentDebt, dailyPlan members)

    // MARK: - Profile Model Tests (DISABLED)
    // FIXME: Re-enable when WellbeingDebtProfile API is updated
    // WellbeingDebtProfile has different structure than expected (no learnedThreshold, lastCrashDate, crashHistory members)

    func testCanonicalProfileAndLegacyHistoryDecodingWithoutFabricatedMood() throws {
        let canonical = """
        {"user_id":"11111111-1111-4111-8111-111111111111","learned_threshold":12.5,
         "crash_history":[{"date":"2026-10-20","debt_at_crash":5}],
         "top_drains":{"categories":[]},"top_deposits":{"categories":[]}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WellbeingDebtProfile.self, from: canonical)
        XCTAssertEqual(decoded.personalThreshold, 12.5)
        XCTAssertEqual(decoded.crashHistory.crashes.count, 1)
        XCTAssertNil(decoded.crashHistory.crashes[0].moodScore)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        XCTAssertNotNil(encoded["learned_threshold"])
        XCTAssertNil(encoded["personal_threshold"])
        XCTAssertNotNil(encoded["crash_history"] as? [[String: Any]])
        let legacy = """
        {"user_id":"11111111-1111-4111-8111-111111111111","personal_threshold":-75,
         "crash_history":{"crashes":[],"last_updated":null},
         "top_drains":{"categories":[]},"top_deposits":{"categories":[]}}
        """.data(using: .utf8)!
        let old = try JSONDecoder().decode(WellbeingDebtProfile.self, from: legacy)
        XCTAssertEqual(old.personalThreshold, -75)
        XCTAssertTrue(old.crashHistory.crashes.isEmpty)
    }

    // MARK: - Error Handling Tests

    func testWellbeingDebtErrorDescriptions() {
        // Test error descriptions
        let profileError = WellbeingDebtError.profileNotFound
        XCTAssertNotNil(profileError.errorDescription)

        let dateError = WellbeingDebtError.invalidDate("bad-date")
        XCTAssertTrue(dateError.errorDescription?.contains("bad-date") ?? false)

        let generationError = WellbeingDebtError.generationFailed("API timeout")
        XCTAssertTrue(generationError.errorDescription?.contains("API timeout") ?? false)
    }
}

@MainActor
final class DebtBreakdownRegressionTests: XCTestCase {
    private let owner = "11111111-1111-4111-8111-111111111111"

    func testWindowsContainExactlySevenFourteenAndThirtyCompleteUTCDays() {
        let now = ISO8601DateFormatter().date(from: "2026-10-23T18:00:00Z")!
        for (days, start) in [(7, "2026-10-16"), (14, "2026-10-09"), (30, "2026-09-23")] {
            let window = DebtTransactionWindow(days: days, now: now)
            XCTAssertEqual(window.start, start)
            XCTAssertEqual(window.end, "2026-10-22")
        }
        let nearMidnight = ISO8601DateFormatter().date(from: "2026-03-09T03:30:00Z")!
        XCTAssertEqual(DebtTransactionWindow(days: 7, now: nearMidnight).end, "2026-03-08")
    }

    func testAccountingExcludesOldFutureOtherOwnerAndUnsupportedIsolationButKeepsExplicitLogs() {
        let now = ISO8601DateFormatter().date(from: "2026-10-23T18:00:00Z")!
        let window = DebtTransactionWindow(days: 14, now: now)
        let records = [
            transaction(date: "2026-10-09", amount: Decimal(string: "1.5")!),
            transaction(date: "2026-10-22", type: .withdrawal, amount: Decimal(string: "0.25")!),
            transaction(date: "2026-10-22", type: .withdrawal, category: .socialIsolation, amount: 5, source: .inferred),
            transaction(date: "2026-01-29", amount: 100),
            transaction(date: "2026-10-23", amount: 100),
            transaction(date: "2026-10-22", amount: 100, user: "other"),
        ]
        let accounted = window.accounted(records, owner: owner)
        XCTAssertEqual(accounted.count, 2)
        let balance = accounted.reduce(Decimal.zero) { $0 + ($1.type == .deposit ? $1.amount : -$1.amount) }
        XCTAssertEqual(balance, Decimal(string: "1.25")!)
        XCTAssertTrue(transaction(date: "2026-10-22", category: .socialIsolation, amount: 2).isSupportedForAccounting)
    }

    func testRenderCurrentWindowAndExactDecimalSumsWithStaleScore() async throws {
        let window = DebtTransactionWindow(days: 7)
        let fixture = DebtTransactionFixture(owner: owner, records: [
            transaction(date: window.end, amount: Decimal(string: "1.5")!),
            transaction(date: window.end, type: .withdrawal, amount: Decimal(string: "0.25")!),
            transaction(date: window.end, type: .withdrawal, category: .socialIsolation, amount: 5, source: .inferred),
            transaction(date: "2026-01-29", amount: 100),
        ])
        let score = DebtScore(id: nil, userId: owner, date: "2026-01-29", dailyBalance: 0,
            rollingDebt7Day: 22, rollingDebt14Day: 22, rollingDebt30Day: 22,
            trend: TrendData(direction: .stable, velocity: 0, projection7Day: 22),
            thresholdStatus: ThresholdStatus(currentDebt: 22, threshold: nil, severity: .safe, daysUntilCrash: nil, confidence: 0), createdAt: nil)
        let host = UIHostingController(rootView: DebtBreakdownView(debtScore: score, transactionReader: fixture)
            .environmentObject(DependencyContainer.preview).environmentObject(AppState()).preferredColorScheme(.dark))
        let windowUI = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        windowUI.rootViewController = host
        windowUI.makeKeyAndVisible()
        defer { windowUI.isHidden = true }
        for _ in 0..<50 {
            if await fixture.ownerReads >= 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let ownerReads = await fixture.ownerReads
        XCTAssertGreaterThanOrEqual(ownerReads, 2, "Wait for the post-read account check before capturing the completed UI")
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
        let attachment = XCTAttachment(image: renderer.image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) })
        attachment.name = "Issue21-current-window-reconciled-decimals"
        attachment.lifetime = .keepAlways
        add(attachment)
        let request = await fixture.request
        XCTAssertEqual(request?.0, window.start)
        XCTAssertEqual(request?.1, window.end)
    }

    private func transaction(date: String, type: TransactionType = .deposit,
        category: TransactionCategory = .positiveEvent, amount: Decimal,
        source: TransactionSource = .userLogged, user: String? = nil) -> WellbeingTransaction {
        WellbeingTransaction(id: UUID(), userId: user ?? owner, date: date, type: type,
            category: category, amount: amount, source: source, description: "Synthetic check-in", metadata: nil, createdAt: nil)
    }
}

private actor DebtTransactionFixture: WellbeingTransactionReading {
    let owner: String
    let records: [WellbeingTransaction]
    var request: (String, String)?
    var ownerReads = 0
    init(owner: String, records: [WellbeingTransaction]) { self.owner = owner; self.records = records }
    func transactionOwnerID() async throws -> String { ownerReads += 1; return owner }
    func fetchTransactions(from: String, to: String) async throws -> [WellbeingTransaction] {
        request = (from, to)
        return records
    }
}

@MainActor
final class DebtCalculationRegressionTests: XCTestCase {
    private let owner = "11111111-1111-4111-8111-111111111111"
    private func score(current: Bool, available: Bool = true) -> DebtScore {
        let date = DebtTransactionWindow(days: 1).end
        return DebtScore(id: nil, userId: owner, date: current ? date : "2026-01-29", dailyBalance: -3.25,
            rollingDebt7Day: 3.25, rollingDebt14Day: 3.25, rollingDebt30Day: 3.25,
            trend: TrendData(direction: .worsening, velocity: 2, projection7Day: 17.25,
                available: available, observedDays: available ? 3 : 1, accountingVersion: current ? 2 : nil,
                calculatedAt: "2026-10-23T20:00:00.123Z"),
            thresholdStatus: ThresholdStatus(currentDebt: 3.25, threshold: -75, severity: .safe, daysUntilCrash: nil, confidence: 0), createdAt: nil,
            sourceTransactions: [WellbeingTransaction(id: UUID(), userId: owner, date: date, type: .withdrawal,
                category: .workStress, amount: 3.25, source: .userLogged, description: "Synthetic logged event", metadata: nil, createdAt: nil)])
    }
    func testFreshnessRequiresCurrentDateVersionValidDomainAndMatchingSummary() throws {
        let current = score(current: true)
        XCTAssertTrue(current.isCurrentSourceCalculation(requireSnapshot: true))
        XCTAssertFalse(score(current: false).isCurrentSourceCalculation())
        var persisted = current
        persisted.sourceTransactions = nil
        XCTAssertFalse(persisted.isCurrentSourceCalculation(requireSnapshot: true))
        persisted = try restoredFromPersistence(current)
        XCTAssertNil(persisted.sourceTransactions)
        XCTAssertTrue(persisted.isCurrentSourceCalculation(requireSnapshot: true))
        let encoder = JSONEncoder()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(current)) as? [String: Any])
        json["rolling_debt_14day"] = -3.25
        let invalid = try JSONDecoder().decode(DebtScore.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(invalid.isCurrentSourceCalculation())
    }
    private func restoredFromPersistence(_ score: DebtScore) throws -> DebtScore {
        let encoded = try JSONEncoder().encode(score)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var trend = try XCTUnwrap(json["trend"] as? [String: Any])
        trend["source_transactions"] = json.removeValue(forKey: "source_transactions")
        json["trend"] = trend
        return try JSONDecoder().decode(DebtScore.self, from: JSONSerialization.data(withJSONObject: json))
    }
    func testRenderSavedCalculationAfterReloadWithMatchingBreakdownSnapshot() async throws {
        try await render(score: restoredFromPersistence(score(current: true)), name: "Issue20-saved-calculation-reloaded")
    }
    func testRenderStaleCalculationWithoutSafeStatusOrProjection() async throws {
        try await render(score: score(current: false), name: "Issue20-stale-calculation-needs-updating")
    }
    func testRenderCurrentDecimalCalculationAndUnavailableTrend() async throws {
        try await render(score: score(current: true, available: false), name: "Issue20-current-decimal-limited-history")
    }
    func testRenderCurrentTrendWithConsistentDebtEstimate() async throws {
        try await render(score: score(current: true), name: "Issue20-current-debt-trend-estimate")
    }
    func testBreakdownUsesCalculationSnapshotRatherThanStaleLedger() async throws {
        let current = score(current: true)
        let fixture = DebtTransactionFixture(owner: owner, records: [])
        let host = UIHostingController(rootView: DebtBreakdownView(debtScore: current, transactionReader: fixture)
            .environmentObject(DependencyContainer.preview).environmentObject(AppState()).preferredColorScheme(.dark))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for _ in 0..<100 {
            if await fixture.ownerReads >= 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let request = await fixture.request
        let reads = await fixture.ownerReads
        XCTAssertGreaterThanOrEqual(reads, 2)
        XCTAssertNil(request, "The matching response snapshot must reconcile the visible score without reading stale derived rows")
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        })
        attachment.name = "Issue20-breakdown-current-source-snapshot"
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testRenderHomeCardWithReloadedDecimalScore() async throws {
        let current = try restoredFromPersistence(score(current: true))
        let fixture = DebtCalculationFixture(owner: owner, score: current)
        let host = UIHostingController(rootView: WellbeingDebtCard(reader: fixture)
            .environmentObject(DependencyContainer.preview).environmentObject(AppState()).preferredColorScheme(.dark))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for _ in 0..<100 {
            if await fixture.ownerReads >= 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let reads = await fixture.ownerReads
        XCTAssertGreaterThanOrEqual(reads, 2)
        try await Task.sleep(for: .milliseconds(900))
        host.view.layoutIfNeeded()
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        })
        attachment.name = "Issue20-home-card-reloaded-decimals"
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testRenderCanonicalProfileWithCurrentScore() async throws {
        let json = """
        {"user_id":"11111111-1111-4111-8111-111111111111","learned_threshold":null,
         "crash_history":[],"top_drains":{"categories":[]},"top_deposits":{"categories":[]}}
        """.data(using: .utf8)!
        let profile = try JSONDecoder().decode(WellbeingDebtProfile.self, from: json)
        try await render(score: score(current: true), name: "Issue20-canonical-profile-current-dashboard", profile: profile)
    }
    private func render(score: DebtScore, name: String, profile: WellbeingDebtProfile? = nil) async throws {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "wellbeing_debt_tutorial_completed")
        defaults.set(true, forKey: "wellbeing_debt_tutorial_completed")
        defer { if let saved { defaults.set(saved, forKey: "wellbeing_debt_tutorial_completed") } else { defaults.removeObject(forKey: "wellbeing_debt_tutorial_completed") } }
        let fixture = DebtCalculationFixture(owner: owner, score: score, profile: profile)
        let host = UIHostingController(rootView: WellbeingDebtDashboardView(reader: fixture)
            .environmentObject(DependencyContainer.preview).environmentObject(AppState()).preferredColorScheme(.dark))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for _ in 0..<100 {
            if await fixture.ownerReads >= 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let reads = await fixture.ownerReads
        XCTAssertGreaterThanOrEqual(reads, 2)
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        })
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
private actor DebtCalculationFixture: WellbeingDebtReading {
    let owner: String
    let score: DebtScore
    let profile: WellbeingDebtProfile?
    var ownerReads = 0
    init(owner: String, score: DebtScore, profile: WellbeingDebtProfile? = nil) { self.owner = owner; self.score = score; self.profile = profile }
    func transactionOwnerID() async throws -> String { ownerReads += 1; return owner }
    func fetchLatestDebtScore() async throws -> DebtScore? { score }
    func fetchProfile() async throws -> WellbeingDebtProfile? { profile }
    func fetchActiveRecoveryProgram() async throws -> RecoveryProgram? { nil }
    func calculateDebtScore(for date: String?) async throws -> DebtScore { score }
    func backfillTransactions(days: Int) async throws -> Int { XCTFail("Reading a score must not start historical reprocessing"); return 0 }
    func fetchTransactions(from: String, to: String) async throws -> [WellbeingTransaction] { score.sourceTransactions ?? [] }
}

@MainActor
final class DebtRecalculationRegressionTests: XCTestCase {
    private func fixture(behavior: DebtRefreshFixture.Behavior = .success, large: Bool = false) -> DebtRefreshFixture {
        let owner = "11111111-1111-4111-8111-111111111111"
        let date = DebtTransactionWindow(days: 1).end
        let categories: [TransactionCategory] = [.workStress, .conflict, .negativeMood, .healthIssue, .missedSleep, .socialIsolation]
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withFullDate]
        let end = formatter.date(from: date)!
        let records = (0..<(large ? 180 : 1)).map { index in
            WellbeingTransaction(id: UUID(), userId: owner,
                date: formatter.string(from: end.addingTimeInterval(-Double(index / categories.count) * 86_400)),
                type: .withdrawal, category: categories[index % categories.count],
                amount: 1, source: .userLogged, description: "Synthetic event", metadata: nil, createdAt: nil)
        }
        func value(_ days: Int) -> Decimal {
            let window = DebtTransactionWindow(days: days)
            return records.filter { $0.date >= window.start && $0.date <= window.end }.reduce(0) { $0 + $1.amount }
        }
        let score = DebtScore(id: nil, userId: owner, date: date, dailyBalance: -(large ? 6 : 1), rollingDebt7Day: value(7),
            rollingDebt14Day: value(14), rollingDebt30Day: value(30),
            trend: TrendData(direction: .stable, velocity: 0, projection7Day: value(14), available: large,
                observedDays: large ? 7 : 1, accountingVersion: 2, calculatedAt: "2026-10-23T21:00:00Z"),
            thresholdStatus: ThresholdStatus(currentDebt: value(14), threshold: -75, severity: large ? .danger : .safe, daysUntilCrash: nil, confidence: 0),
            createdAt: nil, sourceTransactions: records)
        return DebtRefreshFixture(score: score, behavior: behavior)
    }

    func testOneCalculationWithoutBackfillAndMeasuredStagesForLargeResponse() async throws {
        let reader = fixture(large: true)
        let operation = DebtRecalculation(timeout: .seconds(2))
        operation.start(using: reader)
        operation.start(using: reader)
        try await finish(operation)
        XCTAssertNotNil(operation.result)
        XCTAssertNil(operation.errorMessage)
        let calls = await reader.calls
        let backfills = await reader.backfills
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(backfills, 0)
        XCTAssertNotNil(operation.stageMilliseconds["calculation"])
        XCTAssertNotNil(operation.stageMilliseconds["details"])
        let attachment = XCTAttachment(string: String(describing: operation.stageMilliseconds))
        attachment.name = "Issue22-synthetic-stage-milliseconds-large-response"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    func testTimeoutCancelsAndRetryDoesNotOverlap() async throws {
        let reader = fixture(behavior: .slow)
        let operation = DebtRecalculation(timeout: .milliseconds(60))
        operation.start(using: reader)
        try await finish(operation)
        XCTAssertNil(operation.result)
        XCTAssertTrue(operation.errorMessage?.contains("too long") == true)
        XCTAssertLessThan(operation.stageMilliseconds["total"] ?? 10_000, 1_000)
        await reader.setBehavior(.success)
        operation.start(using: reader)
        try await finish(operation)
        XCTAssertNotNil(operation.result)
        let maximum = await reader.maximumActive
        XCTAssertEqual(maximum, 1)
    }

    func testEmptyOfflineAndBackendFailureAllowRetryWithoutFabricatingScore() async throws {
        for behavior in [DebtRefreshFixture.Behavior.empty, .offline, .backend] {
            let reader = fixture(behavior: behavior)
            let operation = DebtRecalculation(timeout: .seconds(2))
            operation.start(using: reader)
            try await finish(operation)
            XCTAssertNil(operation.result)
            XCTAssertNotNil(operation.errorMessage)
            await reader.setBehavior(.success)
            operation.start(using: reader)
            try await finish(operation)
            XCTAssertNotNil(operation.result)
        }
    }

    func testCancellationWaitsForCleanupBeforeRetry() async throws {
        let reader = fixture(behavior: .slow)
        let operation = DebtRecalculation(timeout: .seconds(2))
        operation.start(using: reader)
        for _ in 0..<100 {
            if await reader.calls > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        operation.cancel()
        operation.start(using: reader)
        try await finish(operation)
        XCTAssertNil(operation.result)
        XCTAssertNil(operation.errorMessage)
        let calls = await reader.calls
        XCTAssertEqual(calls, 1, "Retry must wait for the canceled work to finish")
        await reader.setBehavior(.success)
        operation.start(using: reader)
        try await finish(operation)
        XCTAssertNotNil(operation.result)
    }

    func testRenderNonblockingProgressAndTimeoutRecovery() async throws {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "wellbeing_debt_tutorial_completed")
        defaults.set(true, forKey: "wellbeing_debt_tutorial_completed")
        defer { if let saved { defaults.set(saved, forKey: "wellbeing_debt_tutorial_completed") } else { defaults.removeObject(forKey: "wellbeing_debt_tutorial_completed") } }
        let reader = fixture(behavior: .slow)
        let operation = DebtRecalculation(timeout: .seconds(3))
        let host = UIHostingController(rootView: WellbeingDebtDashboardView(reader: reader, recalculation: operation)
            .environmentObject(DependencyContainer.preview).environmentObject(AppState()).preferredColorScheme(.dark))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { operation.cancel(); window.isHidden = true }
        for _ in 0..<200 {
            if await reader.ownerReads >= 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let initialReads = await reader.ownerReads
        XCTAssertGreaterThanOrEqual(initialReads, 2, "Wait for the hosted dashboard read to complete")
        try await Task.sleep(for: .milliseconds(100))
        capture(host, name: "Issue22-ready-before-analysis")
        XCTAssertTrue(activate("Analyze History", in: host.view.window ?? host.view), "Start through the rendered analysis button")
        try await Task.sleep(for: .milliseconds(200))
        capture(host, name: "Issue22-inline-progress-with-cancel")
        XCTAssertTrue(operation.isRunning, "Activate Cancel before the injected test deadline")
        XCTAssertTrue(activate("Cancel", in: host.view.window ?? host.view), "Cancel through the rendered inline control")
        try await finish(operation)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(operation.result)
        XCTAssertTrue(activate("Analyze History", in: host.view.window ?? host.view), "The screen must be usable again after cancellation")
        try await finish(operation)
        try await Task.sleep(for: .milliseconds(200))
        capture(host, name: "Issue22-timeout-with-retry")
        await reader.setBehavior(.success)
        XCTAssertTrue(activate("Retry", in: host.view.window ?? host.view), "Activate the rendered recovery control")
        try await finish(operation)
        XCTAssertNotNil(operation.result)
        try await Task.sleep(for: .milliseconds(200))
        capture(host, name: "Issue22-retry-control-completed")
    }

    func testLifecycleCancellationClearsCompletedAccountSnapshot() async throws {
        let reader = fixture()
        let operation = DebtRecalculation(timeout: .seconds(1))
        operation.start(using: reader)
        try await finish(operation)
        XCTAssertNotNil(operation.result)
        operation.cancel()
        XCTAssertNil(operation.result)
        XCTAssertNil(operation.errorMessage)
        XCTAssertTrue(operation.canStart)
    }

    func testAccountChangeRejectsLateCalculation() async throws {
        let reader = fixture(behavior: .delayedSuccess)
        let operation = DebtRecalculation(timeout: .seconds(1))
        operation.start(using: reader)
        for _ in 0..<100 {
            if await reader.calls > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        await reader.setOwner("22222222-2222-4222-8222-222222222222")
        try await finish(operation)
        XCTAssertNil(operation.result)
        XCTAssertNil(operation.errorMessage)
    }

    func testDefaultDeadlineCancelsNativeURLSessionRequest() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DebtStalledURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let reader = fixture(behavior: .transport)
        await reader.setTransport(session)
        let initialStops = DebtStalledURLProtocol.events.stopped
        let operation = DebtRecalculation()
        operation.start(using: reader)
        for _ in 0..<3_000 {
            if operation.canStart { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(operation.canStart)
        XCTAssertTrue(operation.errorMessage?.contains("too long") == true)
        XCTAssertGreaterThan(DebtStalledURLProtocol.events.stopped, initialStops)
        let elapsed = operation.stageMilliseconds["total"] ?? 0
        XCTAssertGreaterThanOrEqual(elapsed, 24_000)
        XCTAssertLessThan(elapsed, 30_000)
        let attachment = XCTAttachment(string: "Default deadline canceled native URLSession at \(elapsed)ms")
        attachment.name = "Issue22-native-URLSession-default-deadline"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    func testLateInitialLoadCannotReplaceSuccessfulRecalculation() async throws {
        let score = await fixture().score
        let reader = DebtHeldLoadFixture(score: score)
        let operation = DebtRecalculation(timeout: .seconds(2))
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "wellbeing_debt_tutorial_completed")
        defaults.set(true, forKey: "wellbeing_debt_tutorial_completed")
        defer { if let saved { defaults.set(saved, forKey: "wellbeing_debt_tutorial_completed") } else { defaults.removeObject(forKey: "wellbeing_debt_tutorial_completed") } }
        let host = UIHostingController(rootView: WellbeingDebtDashboardView(reader: reader, recalculation: operation)
            .environmentObject(DependencyContainer.preview).environmentObject(AppState()).preferredColorScheme(.dark))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { operation.cancel(); window.isHidden = true }
        for _ in 0..<200 {
            if await reader.isHeld { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let held = await reader.isHeld
        XCTAssertTrue(held)
        operation.start(using: reader)
        try await finish(operation)
        XCTAssertNotNil(operation.result)
        await reader.release()
        for _ in 0..<200 {
            if await reader.ownerReads >= 4 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let reads = await reader.ownerReads
        XCTAssertGreaterThanOrEqual(reads, 4, "The older read must reach its final publication check")
        try await Task.sleep(for: .milliseconds(200))
        capture(host, name: "Issue22-recalculated-score-survives-late-load")
        XCTAssertNotNil(findElement("14-Day Debt Score", in: host.view.window ?? host.view))
    }

    func testAutomaticRefreshRendersWithoutManualAnalyze() async throws {
        let reader = fixture()
        await reader.enableAutomaticRefresh()
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "wellbeing_debt_tutorial_completed")
        defaults.set(true, forKey: "wellbeing_debt_tutorial_completed")
        defer { if let saved { defaults.set(saved, forKey: "wellbeing_debt_tutorial_completed") } else { defaults.removeObject(forKey: "wellbeing_debt_tutorial_completed") } }
        let host = UIHostingController(rootView: WellbeingDebtDashboardView(reader: reader)
            .environmentObject(DependencyContainer.preview).environmentObject(AppState()).preferredColorScheme(.dark))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for _ in 0..<200 {
            if await reader.calls > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(200))
        capture(host, name: "Issue23-automatic-score-without-analyze")
        XCTAssertNotNil(findElement("14-Day Debt Score", in: window))
        let calls = await reader.calls; XCTAssertEqual(calls, 1)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        for _ in 0..<200 {
            if await reader.calls > calls { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let foregroundCalls = await reader.calls
        XCTAssertEqual(foregroundCalls, 2, "Foreground should request freshness without a manual action")
    }

    func testAutomaticFailureShowsWorkingRetryOnHomeCard() async throws {
        let reader = fixture(behavior: .offline)
        await reader.enableAutomaticRefresh()
        let host = UIHostingController(rootView: WellbeingDebtCard(reader: reader)
            .environmentObject(DependencyContainer.preview).environmentObject(AppState()).preferredColorScheme(.dark))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for _ in 0..<200 { if await reader.calls > 0 { break }; try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(200))
        capture(host, name: "Issue23-automatic-failure-retry")
        await reader.setBehavior(.success)
        XCTAssertTrue(activate("Retry", in: window))
        for _ in 0..<200 { if await reader.calls > 1 { break }; try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(200))
        capture(host, name: "Issue23-home-recovered-score")
        XCTAssertNotNil(findElement("Wellbeing Balance", in: window))
    }

    private func findElement(_ label: String, in root: NSObject) -> NSObject? {
        var visited = Set<ObjectIdentifier>()
        var description: [String] = []
        func find(_ item: NSObject) -> NSObject? {
            guard visited.insert(ObjectIdentifier(item)).inserted else { return nil }
            let count = item.accessibilityElementCount()
            description.append("\(type(of: item)) count=\(count) label=\(item.accessibilityLabel ?? "nil")")
            if item.accessibilityLabel == label { return item }
            if count > 0 && count < 256 {
                for index in 0..<count {
                    if let child = item.accessibilityElement(at: index) as? NSObject,
                       let found = find(child) { return found }
                }
            }
            if let view = item as? UIView {
                for child in view.subviews { if let found = find(child) { return found } }
            }
            return nil
        }
        let target = find(root)
        let details = XCTAttachment(string: "target=\(String(describing: target.map { type(of: $0) }))\n" + description.joined(separator: "\n"))
        details.name = "Issue22-accessibility-\(label)"
        details.lifetime = .keepAlways; add(details)
        return target
    }

    private func activate(_ label: String, in root: NSObject) -> Bool {
        findElement(label, in: root)?.accessibilityActivate() ?? false
    }

    private func finish(_ operation: DebtRecalculation) async throws {
        for _ in 0..<600 {
            if operation.canStart { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Calculation controls must recover within the bounded test interval")
        operation.cancel()
    }
    private func capture(_ host: UIHostingController<some View>, name: String) {
        host.view.layoutIfNeeded()
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        })
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
private actor DebtRefreshFixture: WellbeingDebtReading {
    enum Behavior { case success, slow, empty, offline, backend, transport, delayedSuccess }
    let score: DebtScore
    var behavior: Behavior
    var currentOwner: String
    func setOwner(_ owner: String) { currentOwner = owner }
    private var automatic = false
    func enableAutomaticRefresh() { automatic = true }
    func refreshDebtScoreIfNeeded() async throws -> DebtScore? {
        automatic ? try await calculateDebtScore(for: nil) : nil
    }
    var ownerReads = 0
    var calls = 0
    var backfills = 0
    var active = 0
    var maximumActive = 0
    var transport: URLSession?
    func setTransport(_ session: URLSession) { transport = session }
    init(score: DebtScore, behavior: Behavior) { self.score = score; self.behavior = behavior; self.currentOwner = score.userId }
    func setBehavior(_ behavior: Behavior) { self.behavior = behavior }
    func transactionOwnerID() async throws -> String { ownerReads += 1; return currentOwner }
    func fetchLatestDebtScore() async throws -> DebtScore? { nil }
    func fetchProfile() async throws -> WellbeingDebtProfile? {
        if automatic {
            XCTAssertGreaterThan(calls, 0, "Profile details must follow an actual calculation")
            XCTAssertEqual(active, 0, "Profile details must be read after the new calculation is persisted")
        }
        return nil
    }
    func fetchActiveRecoveryProgram() async throws -> RecoveryProgram? { nil }
    func backfillTransactions(days: Int) async throws -> Int { backfills += 1; return 0 }
    func fetchTransactions(from: String, to: String) async throws -> [WellbeingTransaction] { score.calculationTransactions ?? [] }
    func calculateDebtScore(for date: String?) async throws -> DebtScore {
        calls += 1; active += 1; maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        switch behavior {
        case .success: try await Task.sleep(for: .milliseconds(25)); return score
        case .slow: try await Task.sleep(for: .seconds(20)); return score
        case .delayedSuccess: try await Task.sleep(for: .milliseconds(80)); return score
        case .empty: throw WellbeingDebtError.needsMoreData("No recorded events in this window.")
        case .offline: throw URLError(.notConnectedToInternet)
        case .backend: throw URLError(.badServerResponse)
        case .transport:
            guard let transport else { throw URLError(.badURL) }
            _ = try await transport.data(from: URL(string: "https://debt.synthetic.invalid/stall")!)
            return score
        }
    }
}

private final class DebtStalledURLProtocol: URLProtocol {
    static let events = DebtURLProtocolEvents()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "debt.synthetic.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() { Self.events.recordStop() }
}
// URLSession invokes protocol callbacks off the main actor; all counter access is locked.
private final class DebtURLProtocolEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var stopped: Int { lock.lock(); defer { lock.unlock() }; return count }
    func recordStop() { lock.lock(); count += 1; lock.unlock() }
}

private actor DebtHeldLoadFixture: WellbeingDebtReading {
    let score: DebtScore
    var ownerReads = 0
    var isHeld = false
    private var continuation: CheckedContinuation<RecoveryProgram?, Never>?
    init(score: DebtScore) { self.score = score }
    func transactionOwnerID() async throws -> String { ownerReads += 1; return score.userId }
    func fetchLatestDebtScore() async throws -> DebtScore? { nil }
    func fetchProfile() async throws -> WellbeingDebtProfile? { nil }
    func fetchActiveRecoveryProgram() async throws -> RecoveryProgram? {
        await withCheckedContinuation { continuation in self.continuation = continuation; isHeld = true }
    }
    func release() { continuation?.resume(returning: nil); continuation = nil }
    func calculateDebtScore(for date: String?) async throws -> DebtScore { score }
    func backfillTransactions(days: Int) async throws -> Int { XCTFail("No historical fan-out"); return 0 }
    func fetchTransactions(from: String, to: String) async throws -> [WellbeingTransaction] { score.calculationTransactions ?? [] }
}

final class DebtAutomaticRefreshTests: XCTestCase {
    func testConcurrentConsumersCacheEmptyResultsAndInvalidateOnSourceOrOwnerKey() async throws {
        let refresh = DebtScoreRefresh()
        let fixture = DebtAutomaticWork()
        let started = ContinuousClock.now
        let results = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<20 { group.addTask { try await refresh.value(key: "ownerA-date-revision0") { try await fixture.run() } == nil } }
            var values: [Bool] = []; for try await value in group { values.append(value) }; return values
        }
        XCTAssertEqual(results, Array(repeating: true, count: 20))
        _ = try await refresh.value(key: "ownerA-date-revision0") { try await fixture.run() }
        var calls = await fixture.calls; XCTAssertEqual(calls, 1)
        _ = try await refresh.value(key: "ownerA-date-revision1") { try await fixture.run() }
        _ = try await refresh.value(key: "ownerB-date-revision1") { try await fixture.run() }
        calls = await fixture.calls; XCTAssertEqual(calls, 3)
        let maximum = await fixture.maximum; XCTAssertEqual(maximum, 1)
        let attachment = XCTAttachment(string: "20 concurrent consumers + cached read: one invocation; source/owner invalidation: two further invocations; total synthetic duration \(started.duration(to: .now))")
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testAutomaticTimeoutFailureAndManualRetryDoNotCacheErrors() async throws {
        let refresh = DebtScoreRefresh(timeout: .milliseconds(30))
        let fixture = DebtAutomaticWork()
        do { _ = try await refresh.value(key: "owner-date") { try await fixture.run(delay: .seconds(2)) }; XCTFail("Must time out") }
        catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        _ = try await refresh.value(key: "owner-date") { try await fixture.run() }
        _ = try await refresh.value(key: "owner-date", force: true) { try await fixture.run() }
        let calls = await fixture.calls; XCTAssertEqual(calls, 3)
        let maximum = await fixture.maximum; XCTAssertEqual(maximum, 1)
    }
    func testLeavingOneAutomaticConsumerPreservesSharedWorkForAnother() async throws {
        let refresh = DebtScoreRefresh()
        let fixture = DebtAutomaticWork()
        let first = Task { try await refresh.value(key: "owner-date") { try await fixture.run(delay: .milliseconds(80)) } }
        while await fixture.calls == 0 { await Task.yield() }
        let second = Task { try await refresh.value(key: "owner-date") { try await fixture.run() } }
        first.cancel()
        _ = try await second.value
        do { _ = try await first.value; XCTFail("Canceled consumer cannot publish") } catch { XCTAssertTrue(error is CancellationError) }
        _ = try await refresh.value(key: "owner-date") { try await fixture.run() }
        let calls = await fixture.calls; XCTAssertEqual(calls, 1)
    }
    func testControlledBeforeAfterLatencyAndCacheExpiry() async throws {
        let fixture = DebtAutomaticWork()
        let before = ContinuousClock.now
        for _ in 0..<30 { _ = try await fixture.run(delay: .milliseconds(5)) }
        let priorDuration = before.duration(to: .now)
        let refresh = DebtScoreRefresh(maximumAge: 0)
        let after = ContinuousClock.now
        _ = try await refresh.value(key: "owner-date") { try await fixture.run(delay: .milliseconds(5)) }
        let currentDuration = after.duration(to: .now)
        _ = try await refresh.value(key: "owner-date") { try await fixture.run() }
        let calls = await fixture.calls; XCTAssertEqual(calls, 32)
        let attachment = XCTAttachment(string: "Controlled synthetic5ms/request: prior30 detector requests \(priorDuration); replacement1 request \(currentDuration). This is a local scheduling/call-count comparison, not hosted Nano latency. Zero TTL rechecks once after expiration.")
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testAlreadyCanceledCallerCannotCancelCurrentOwnerWork() async throws {
        let refresh = DebtScoreRefresh()
        let fixture = DebtAutomaticWork()
        let current = Task { try await refresh.value(key: "currentOwner") { try await fixture.run(delay: .milliseconds(80)) } }
        while await fixture.calls == 0 { await Task.yield() }
        let stale = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await refresh.value(key: "oldOwner") { try await fixture.run() }
        }
        do { _ = try await stale.value; XCTFail("Canceled caller must fail before touching active work") } catch { XCTAssertTrue(error is CancellationError) }
        _ = try await current.value
        let calls = await fixture.calls; XCTAssertEqual(calls, 1)
    }
    func testSharedTimeoutHasTheSameActionableErrorForEveryConsumer() async throws {
        let refresh = DebtScoreRefresh(timeout: .milliseconds(30))
        let fixture = DebtAutomaticWork()
        let first = Task { try await refresh.value(key: "owner") { try await fixture.run(delay: .seconds(2)) } }
        while await fixture.calls == 0 { await Task.yield() }
        let manual = Task { try await refresh.value(key: "owner", force: true, cancelsSharedWork: true) { try await fixture.run() } }
        for task in [first, manual] {
            do { _ = try await task.value; XCTFail("Must report timeout") } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        }
    }
    func testManualCancellationAlsoCancelsAJoinedRequest() async throws {
        let refresh = DebtScoreRefresh()
        let fixture = DebtAutomaticWork()
        let first = Task { try await refresh.value(key: "owner") { try await fixture.run(delay: .seconds(2)) } }
        while await fixture.calls == 0 { await Task.yield() }
        let manual = Task { try await refresh.value(key: "owner", force: true, cancelsSharedWork: true) { try await fixture.run() } }
        try await Task.sleep(for: .milliseconds(10)); manual.cancel()
        do { _ = try await manual.value; XCTFail("Canceled manual consumer cannot publish") } catch { XCTAssertTrue(error is CancellationError) }
        _ = try? await first.value
        _ = try await refresh.value(key: "owner", force: true) { try await fixture.run() }
        let maximum = await fixture.maximum; XCTAssertEqual(maximum, 1)
    }
    func testSourceInvalidationOnlyIncludesTheCompleteDateWindow() {
        let initial = DebtSourceChanges.revision
        DebtSourceChanges.saved(date: "1900-01-01")
        DebtSourceChanges.saved(date: "2999-01-01")
        XCTAssertEqual(DebtSourceChanges.revision, initial)
        DebtSourceChanges.saved(date: DebtTransactionWindow(days: 1).end)
        XCTAssertEqual(DebtSourceChanges.revision, initial + 1)
    }
    func testChangedSourceCancelsOldWorkBeforeRecalculation() async throws {
        let refresh = DebtScoreRefresh()
        let fixture = DebtAutomaticWork()
        let old = Task { try await refresh.value(key: "owner-date-revision0") { try await fixture.run(delay: .seconds(2)) } }
        while await fixture.calls == 0 { await Task.yield() }
        _ = try await refresh.value(key: "owner-date-revision1") { try await fixture.run() }
        _ = try? await old.value
        let maximum = await fixture.maximum; XCTAssertEqual(maximum, 1)
        let calls = await fixture.calls; XCTAssertEqual(calls, 2)
    }
}
private actor DebtAutomaticWork {
    var calls = 0; var active = 0; var maximum = 0
    func run(delay: Duration = .milliseconds(10)) async throws -> DebtScore? {
        calls += 1; active += 1; maximum = max(maximum, active)
        defer { active -= 1 }
        try await Task.sleep(for: delay)
        return nil
    }
}

final class DebtOwnerWireRegressionTests: XCTestCase {
    private func service(failFirst: Bool = false) async throws -> WellbeingDebtService {
        DebtOwnerURLProtocol.fixture.reset(failFirst: failFirst)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DebtOwnerURLProtocol.self]
        let client = SupabaseClient(supabaseURL: URL(string: "https://debt-owner-fixture.invalid")!, supabaseKey: "synthetic-anon",
            options: .init(auth: .init(storage: DebtOwnerAuthStorage(), autoRefreshToken: false),
                           global: .init(session: URLSession(configuration: configuration))))
        _ = try await client.auth.signIn(email: "qa@example.invalid", password: "synthetic-offline")
        return WellbeingDebtService(supabase: client)
    }
    func testUUIDOwnerIsCanonicalOnActualSDKFunctionRequestAndCoalescedReload() async throws {
        let service = try await service()
        let owner = try await service.transactionOwnerID()
        XCTAssertEqual(owner, DebtOwnerHTTP.owner)
        let first = try await service.refreshDebtScoreIfNeeded()
        let second = try await service.refreshDebtScoreIfNeeded()
        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(DebtOwnerURLProtocol.fixture.owners, [DebtOwnerHTTP.owner])
    }
    func testFailedRequestCanRetryWithTheSameCanonicalOwner() async throws {
        let service = try await service(failFirst: true)
        do { _ = try await service.refreshDebtScoreIfNeeded(); XCTFail("Expected synthetic service failure") }
        catch { }
        let retried = try await service.refreshDebtScoreIfNeeded()
        XCTAssertNil(retried)
        XCTAssertEqual(DebtOwnerURLProtocol.fixture.owners, [DebtOwnerHTTP.owner, DebtOwnerHTTP.owner])
    }
}
private final class DebtOwnerAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.lock(); defer { lock.unlock() }; values[key] = value }
    func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func remove(key: String) throws { lock.lock(); defer { lock.unlock() }; values[key] = nil }
}
private final class DebtOwnerURLProtocol: URLProtocol {
    static let fixture = DebtOwnerHTTP()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "debt-owner-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.fixture.respond(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
private final class DebtOwnerHTTP: @unchecked Sendable {
    static let owner = "aabbccdd-1111-4111-8111-aabbccddeeff"
    private let lock = NSLock()
    private var recorded: [String] = []
    private var failFirst = false
    var owners: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
    func reset(failFirst: Bool) { lock.lock(); defer { lock.unlock() }; recorded = []; self.failFirst = failFirst }
    func respond(_ request: URLRequest) -> (Int, Data) {
        lock.lock(); defer { lock.unlock() }
        if request.url?.path == "/auth/v1/token" {
            let body: [String: Any] = ["access_token": "synthetic-access", "refresh_token": "synthetic-refresh", "token_type": "bearer",
                "expires_in": 3600, "expires_at": Int(Date().timeIntervalSince1970) + 3600,
                "user": ["id": Self.owner, "aud": "authenticated", "role": "authenticated", "app_metadata": [:], "user_metadata": [:],
                         "created_at": "2026-10-25T00:00:00Z", "updated_at": "2026-10-25T00:00:00Z"]]
            return (200, try! JSONSerialization.data(withJSONObject: body))
        }
        guard request.url?.path == "/functions/v1/calculate-debt-score" else { return (404, Data("{}".utf8)) }
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable && data.count < 16384 {
                let n = stream.read(&bytes, maxLength: bytes.count)
                if n <= 0 { break }
                data.append(contentsOf: bytes.prefix(n))
            }
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let owner = body?["user_id"] as? String ?? "missing"
        recorded.append(owner)
        // Match the deployed server's strict owner guard without weakening ownership.
        guard owner == Self.owner else { return (403, Data(#"{"error":"Forbidden"}"#.utf8)) }
        if failFirst && recorded.count == 1 { return (503, Data(#"{"error":"Synthetic unavailable"}"#.utf8)) }
        return (200, Data(#"{"success":true,"score":null}"#.utf8))
    }
}
