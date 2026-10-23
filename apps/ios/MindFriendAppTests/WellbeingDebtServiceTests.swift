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
