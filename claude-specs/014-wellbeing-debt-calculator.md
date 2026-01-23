# N006: Wellbeing Debt Calculator

> **Type:** NOVEL DIFFERENTIATOR
> **Phase:** Predictive Prevention
> **Complexity:** Medium
> **Priority:** P1
> **Dependencies:** F001 (Biometric Correlation Engine), Mood Logging (Existing), N002 (Circadian Vulnerability Shield)

---

## 1. Overview

### 1.1 Summary

The Wellbeing Debt Calculator models cumulative stress as a finite resource that depletes with life stressors and replenishes with self-care. Like sleep debt or technical debt, "wellbeing debt" accumulates silently until it reaches a tipping point that triggers a crash. The system tracks daily deposits (self-care, social connection, sleep) and withdrawals (work stress, conflicts, poor sleep) to calculate a rolling debt score. When debt exceeds a personalized threshold, the system intervenes _before_ the crash with a targeted "recovery program."

This is **preventive mental health at the systems level**: managing the underlying capacity, not just the symptoms.

### 1.2 Business Value

- **Prevention > Treatment:** Intervene before breakdown, not after
- **Intuitive Mental Model:** "Debt" is universally understood; makes mental health tangible
- **Actionable Insights:** Users see exactly what's draining them and what helps
- **Long-term Retention:** Users manage their ongoing "budget," not just fix crises
- **Clinical Novelty:** First consumer app to model allostatic load for mental health

### 1.3 Scientific Foundation

- **Allostatic Load:** Cumulative physiological wear from chronic stress (McEwen, 1998)
- **Stress Inoculation:** Building resilience through managed exposure (Meichenbaum, 1985)
- **Resource Conservation Theory:** Stress accumulates when losses exceed gains (Hobfoll, 1989)
- **Burnout Research:** Chronic imbalance between demands and resources (Maslach, 2001)

---

## 2. Requirements

### 2.1 Functional Requirements

| ID     | Requirement                                                                 | Priority |
| ------ | --------------------------------------------------------------------------- | -------- |
| FR-001 | System SHALL calculate daily "wellbeing debt" score (-100 to +100)          | P0       |
| FR-002 | System SHALL track "deposits" (positive) and "withdrawals" (negative) daily | P0       |
| FR-003 | System SHALL calculate rolling 7/14/30-day debt trends                      | P0       |
| FR-004 | System SHALL detect when debt exceeds personalized threshold                | P0       |
| FR-005 | System SHALL trigger preventive intervention when threshold exceeded        | P0       |
| FR-006 | System SHALL show "Wellbeing Budget" dashboard with trends                  | P1       |
| FR-007 | System SHALL identify top drains and top recharges for each user            | P1       |
| FR-008 | System SHALL learn personalized debt thresholds from crash history          | P1       |
| FR-009 | System SHALL suggest "deposit" activities when debt is rising               | P1       |
| FR-010 | System SHALL integrate calendar events as predicted withdrawals             | P2       |

### 2.2 Non-Functional Requirements

| ID      | Requirement                      | Target                                  |
| ------- | -------------------------------- | --------------------------------------- |
| NFR-001 | Debt calculation latency         | < 3 seconds                             |
| NFR-002 | Threshold detection accuracy     | > 75% predicts crash within 3 days      |
| NFR-003 | Minimum data for personalization | 14 days of activity                     |
| NFR-004 | Battery impact                   | < 0.5% per day (daily calculation only) |

### 2.3 Acceptance Criteria

1. Given a user with 7 days of low sleep, skipped exercises, and high work stress, when debt is calculated, then score reflects significant negative debt
2. Given debt exceeding threshold, when the user opens the app, then they see a "Wellness Recovery" prompt
3. Given a user viewing their dashboard, when they tap on debt breakdown, then they see top drains and deposits
4. Given 30 days of data, when a mood crash occurs, then the system learns the user's personal crash threshold

---

## 3. Technical Design

### 3.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    iOS App Layer                                 │
├─────────────────────────────────────────────────────────────────┤
│ WellbeingBudgetDashboard │ DebtBreakdownView │ RecoveryProgramUI│
├─────────────────────────────────────────────────────────────────┤
│                 WellbeingDebtViewModel                           │
├─────────────────────────────────────────────────────────────────┤
│                   WellbeingDebtEngine                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  Transaction │  │   Threshold  │  │  Recovery    │          │
│  │   Tracker    │  │   Detector   │  │  Planner     │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
├─────────────────────────────────────────────────────────────────┤
│ HealthKitService │ MoodService │ ExerciseService │ CirclesService
│    (existing)    │  (existing) │    (existing)   │   (existing) │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Data Models

#### 3.2.1 WellbeingTransaction Model

```swift
struct WellbeingTransaction: Codable, Identifiable {
    let id: UUID
    let userId: String
    let date: Date
    let type: TransactionType
    let category: TransactionCategory
    let amount: Int                        // Positive = deposit, Negative = withdrawal
    let source: TransactionSource          // What data source detected this
    let description: String
    let metadata: [String: String]?

    enum TransactionType: String, Codable {
        case deposit
        case withdrawal
    }

    enum TransactionCategory: String, Codable {
        // Deposits
        case goodSleep = "good_sleep"
        case exercise = "exercise"
        case socialConnection = "social_connection"
        case meditation = "meditation"
        case outdoorTime = "outdoor_time"
        case questCompletion = "quest_completion"
        case positiveEvent = "positive_event"

        // Withdrawals
        case poorSleep = "poor_sleep"
        case missedSleep = "missed_sleep"
        case workStress = "work_stress"
        case conflict = "conflict"
        case skippedExercise = "skipped_exercise"
        case isolation = "isolation"
        case healthIssue = "health_issue"
        case negativeEvent = "negative_event"
        case circadianDisruption = "circadian_disruption"
    }

    enum TransactionSource: String, Codable {
        case healthKit
        case appActivity
        case userLogged
        case calendar
        case inferred
    }
}
```

#### 3.2.2 WellbeingDebtScore Model

```swift
struct WellbeingDebtScore: Codable, Identifiable {
    let id: UUID
    let userId: String
    let date: Date
    let dailyBalance: Int                  // Today's net (deposits - withdrawals)
    let rollingDebt7Day: Int               // Cumulative over 7 days
    let rollingDebt14Day: Int              // Cumulative over 14 days
    let rollingDebt30Day: Int              // Cumulative over 30 days
    let trend: DebtTrend
    let thresholdStatus: ThresholdStatus

    struct DebtTrend: Codable {
        let direction: Direction
        let velocity: Double               // Points per day
        let daysInCurrentDirection: Int

        enum Direction: String, Codable {
            case accumulating              // Getting worse
            case stable
            case recovering                // Getting better
        }
    }

    struct ThresholdStatus: Codable {
        let personalThreshold: Int         // User's crash point (learned)
        let percentToThreshold: Double     // How close to crash
        let daysToThreshold: Int?          // Estimated at current velocity
        let alert: AlertLevel

        enum AlertLevel: String, Codable {
            case healthy                   // < 50% of threshold
            case caution                   // 50-75% of threshold
            case warning                   // 75-90% of threshold
            case critical                  // > 90% of threshold
        }
    }
}
```

#### 3.2.3 Database Schema

```sql
-- Wellbeing transactions (deposits and withdrawals)
CREATE TABLE wellbeing_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('deposit', 'withdrawal')),
    category TEXT NOT NULL,
    amount INTEGER NOT NULL,
    source TEXT NOT NULL,
    description TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Daily debt scores
CREATE TABLE wellbeing_debt_scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    daily_balance INTEGER NOT NULL,
    rolling_debt_7day INTEGER NOT NULL,
    rolling_debt_14day INTEGER NOT NULL,
    rolling_debt_30day INTEGER NOT NULL,
    trend JSONB NOT NULL,
    threshold_status JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, date)
);

-- User debt profiles (personalized thresholds)
CREATE TABLE wellbeing_debt_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
    personal_threshold INTEGER NOT NULL DEFAULT -50,
    crash_history JSONB NOT NULL DEFAULT '[]',
    top_drains JSONB NOT NULL DEFAULT '[]',
    top_deposits JSONB NOT NULL DEFAULT '[]',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_transactions_user_date ON wellbeing_transactions(user_id, date DESC);
CREATE INDEX idx_debt_scores_user_date ON wellbeing_debt_scores(user_id, date DESC);

-- RLS
ALTER TABLE wellbeing_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE wellbeing_debt_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE wellbeing_debt_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own transactions" ON wellbeing_transactions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users read own scores" ON wellbeing_debt_scores FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users read own profiles" ON wellbeing_debt_profiles FOR SELECT USING (auth.uid() = user_id);
```

### 3.3 Transaction Detection Algorithm

```swift
class TransactionDetector {
    func detectDailyTransactions(for userId: String, date: Date) async -> [WellbeingTransaction] {
        var transactions: [WellbeingTransaction] = []

        // DEPOSITS

        // 1. Sleep quality (from HealthKit)
        if let sleep = await fetchSleepData(userId: userId, date: date) {
            if sleep.duration >= 7 * 3600 && sleep.quality >= 0.7 {
                transactions.append(WellbeingTransaction(
                    id: UUID(),
                    userId: userId,
                    date: date,
                    type: .deposit,
                    category: .goodSleep,
                    amount: calculateSleepDeposit(sleep),  // +5 to +15
                    source: .healthKit,
                    description: "Good sleep: \(Int(sleep.duration / 3600))h",
                    metadata: nil
                ))
            } else if sleep.duration < 6 * 3600 {
                transactions.append(WellbeingTransaction(
                    id: UUID(),
                    userId: userId,
                    date: date,
                    type: .withdrawal,
                    category: .poorSleep,
                    amount: -calculateSleepWithdrawal(sleep),  // -5 to -15
                    source: .healthKit,
                    description: "Poor sleep: \(Int(sleep.duration / 3600))h",
                    metadata: nil
                ))
            }
        }

        // 2. Exercise sessions completed
        let exercises = await fetchExerciseSessions(userId: userId, date: date)
        if !exercises.isEmpty {
            transactions.append(WellbeingTransaction(
                id: UUID(),
                userId: userId,
                date: date,
                type: .deposit,
                category: .exercise,
                amount: 5 * exercises.count,  // +5 per exercise
                source: .appActivity,
                description: "\(exercises.count) exercise(s) completed",
                metadata: nil
            ))
        }

        // 3. Social connection (circle activity)
        let socialActivity = await fetchCircleActivity(userId: userId, date: date)
        if socialActivity.messageCount > 0 {
            transactions.append(WellbeingTransaction(
                id: UUID(),
                userId: userId,
                date: date,
                type: .deposit,
                category: .socialConnection,
                amount: min(socialActivity.messageCount * 2, 10),  // +2 per message, max +10
                source: .appActivity,
                description: "Circle interactions: \(socialActivity.messageCount)",
                metadata: nil
            ))
        } else {
            // No social activity = mild withdrawal
            transactions.append(WellbeingTransaction(
                id: UUID(),
                userId: userId,
                date: date,
                type: .withdrawal,
                category: .isolation,
                amount: -3,
                source: .inferred,
                description: "No social connection today",
                metadata: nil
            ))
        }

        // 4. Quest completion
        if await didCompleteQuest(userId: userId, date: date) {
            transactions.append(WellbeingTransaction(
                id: UUID(),
                userId: userId,
                date: date,
                type: .deposit,
                category: .questCompletion,
                amount: 5,
                source: .appActivity,
                description: "Quest completed",
                metadata: nil
            ))
        }

        // WITHDRAWALS

        // 5. Circadian disruption (from N002)
        if let circadian = await fetchCircadianData(userId: userId, date: date) {
            if circadian.socialJetLagMinutes > 60 {
                transactions.append(WellbeingTransaction(
                    id: UUID(),
                    userId: userId,
                    date: date,
                    type: .withdrawal,
                    category: .circadianDisruption,
                    amount: -(circadian.socialJetLagMinutes / 20),  // -3 to -6
                    source: .healthKit,
                    description: "Sleep schedule disruption",
                    metadata: nil
                ))
            }
        }

        // 6. Negative mood entries
        let moods = await fetchMoodEntries(userId: userId, date: date)
        for mood in moods where mood.score < 4 {
            transactions.append(WellbeingTransaction(
                id: UUID(),
                userId: userId,
                date: date,
                type: .withdrawal,
                category: .negativeEvent,
                amount: -(5 - mood.score),  // Lower mood = bigger withdrawal
                source: .appActivity,
                description: "Low mood logged",
                metadata: nil
            ))
        }

        return transactions
    }

    private func calculateSleepDeposit(_ sleep: SleepData) -> Int {
        var base = 5
        if sleep.duration >= 8 * 3600 { base += 5 }
        if sleep.quality >= 0.85 { base += 5 }
        return base
    }

    private func calculateSleepWithdrawal(_ sleep: SleepData) -> Int {
        var base = 5
        if sleep.duration < 5 * 3600 { base += 5 }
        if sleep.quality < 0.5 { base += 5 }
        return base
    }
}
```

### 3.4 Debt Score Calculator

```swift
class WellbeingDebtCalculator {
    func calculateDailyScore(for userId: String, date: Date) async -> WellbeingDebtScore {
        // Get today's transactions
        let todayTransactions = await fetchTransactions(userId: userId, date: date)
        let dailyBalance = todayTransactions.reduce(0) { $0 + $1.amount }

        // Get rolling totals
        let last7Days = await fetchTransactions(userId: userId, days: 7, before: date)
        let last14Days = await fetchTransactions(userId: userId, days: 14, before: date)
        let last30Days = await fetchTransactions(userId: userId, days: 30, before: date)

        let rolling7Day = last7Days.reduce(0) { $0 + $1.amount }
        let rolling14Day = last14Days.reduce(0) { $0 + $1.amount }
        let rolling30Day = last30Days.reduce(0) { $0 + $1.amount }

        // Calculate trend
        let trend = calculateTrend(last7Days: last7Days)

        // Get personalized threshold
        let profile = await fetchUserProfile(userId: userId)
        let thresholdStatus = calculateThresholdStatus(
            currentDebt: rolling14Day,
            threshold: profile.personalThreshold,
            trend: trend
        )

        return WellbeingDebtScore(
            id: UUID(),
            userId: userId,
            date: date,
            dailyBalance: dailyBalance,
            rollingDebt7Day: rolling7Day,
            rollingDebt14Day: rolling14Day,
            rollingDebt30Day: rolling30Day,
            trend: trend,
            thresholdStatus: thresholdStatus
        )
    }

    private func calculateThresholdStatus(
        currentDebt: Int,
        threshold: Int,
        trend: WellbeingDebtScore.DebtTrend
    ) -> WellbeingDebtScore.ThresholdStatus {
        let percentToThreshold = Double(abs(currentDebt)) / Double(abs(threshold))

        // Estimate days to threshold at current velocity
        let daysToThreshold: Int?
        if trend.direction == .accumulating && trend.velocity < 0 {
            let remainingDebt = abs(threshold) - abs(currentDebt)
            daysToThreshold = Int(Double(remainingDebt) / abs(trend.velocity))
        } else {
            daysToThreshold = nil
        }

        let alertLevel: WellbeingDebtScore.ThresholdStatus.AlertLevel
        switch percentToThreshold {
        case ..<0.5: alertLevel = .healthy
        case 0.5..<0.75: alertLevel = .caution
        case 0.75..<0.9: alertLevel = .warning
        default: alertLevel = .critical
        }

        return WellbeingDebtScore.ThresholdStatus(
            personalThreshold: threshold,
            percentToThreshold: percentToThreshold,
            daysToThreshold: daysToThreshold,
            alert: alertLevel
        )
    }
}
```

### 3.5 Recovery Program Generator

```swift
class RecoveryProgramGenerator {
    func generateRecoveryProgram(for profile: WellbeingDebtProfile, currentDebt: Int) -> RecoveryProgram {
        // Identify top drains to avoid
        let drainsToAvoid = profile.topDrains.prefix(3)

        // Identify top deposits to prioritize
        let depositsToPrioritize = profile.topDeposits.prefix(3)

        // Calculate target daily deposit needed
        let daysToRecover = 7
        let dailyDepositTarget = abs(currentDebt) / daysToRecover + 5  // Extra buffer

        // Generate specific actions
        var actions: [RecoveryAction] = []

        // Sleep priority
        actions.append(RecoveryAction(
            category: .goodSleep,
            action: "Protect 8 hours of sleep every night this week",
            impact: "+10 daily",
            priority: .critical
        ))

        // Based on user's top deposits
        for deposit in depositsToPrioritize {
            actions.append(RecoveryAction(
                category: deposit.category,
                action: deposit.suggestedAction,
                impact: "+\(deposit.averageAmount) per occurrence",
                priority: .high
            ))
        }

        // Based on user's top drains (avoidance)
        for drain in drainsToAvoid {
            actions.append(RecoveryAction(
                category: drain.category,
                action: "Minimize: \(drain.suggestedAvoidance)",
                impact: "Saves \(abs(drain.averageAmount)) daily",
                priority: .medium
            ))
        }

        return RecoveryProgram(
            duration: 7,  // days
            dailyTarget: dailyDepositTarget,
            currentDebt: currentDebt,
            actions: actions,
            milestones: [
                (day: 2, message: "Early momentum matters"),
                (day: 4, message: "Halfway there"),
                (day: 7, message: "Debt cleared!")
            ]
        )
    }
}

struct RecoveryProgram {
    let duration: Int
    let dailyTarget: Int
    let currentDebt: Int
    let actions: [RecoveryAction]
    let milestones: [(day: Int, message: String)]
}

struct RecoveryAction {
    let category: WellbeingTransaction.TransactionCategory
    let action: String
    let impact: String
    let priority: Priority

    enum Priority {
        case critical
        case high
        case medium
    }
}
```

### 3.6 API Contracts

#### 3.6.1 Get Wellbeing Budget Dashboard

```
GET /api/v1/wellbeing-debt/dashboard
Authorization: Bearer <jwt>

Response 200:
{
    "currentDebt": -35,
    "trend": {
        "direction": "accumulating",
        "velocity": -5.2,
        "daysInCurrentDirection": 4
    },
    "thresholdStatus": {
        "personalThreshold": -50,
        "percentToThreshold": 0.70,
        "daysToThreshold": 3,
        "alert": "warning"
    },
    "todayBalance": -8,
    "todayTransactions": [
        { "category": "poor_sleep", "amount": -10, "description": "5h sleep" },
        { "category": "exercise", "amount": 5, "description": "1 exercise completed" },
        { "category": "isolation", "amount": -3, "description": "No social connection" }
    ],
    "topDrains": [
        { "category": "poor_sleep", "totalLast30Days": -120 }
    ],
    "topDeposits": [
        { "category": "social_connection", "totalLast30Days": 85 }
    ]
}
```

---

## 4. Implementation Details

### 4.1 Step-by-Step Implementation

1. **Build Transaction Detector** (2 days)
   - Integrate with HealthKit sleep data
   - Track exercise completions
   - Track circle activity
   - Add mood-based transactions

2. **Create Debt Calculator** (2 days)
   - Implement rolling totals
   - Add trend calculation
   - Build threshold detection

3. **Build Profile Learning** (2 days)
   - Detect crash patterns
   - Learn personalized thresholds
   - Identify top drains/deposits

4. **Create Recovery Generator** (1 day)
   - Build program logic
   - Add milestone tracking
   - Create action recommendations

5. **Build iOS UI** (3 days)
   - `WellbeingBudgetDashboardView`
   - `DebtBreakdownView`
   - `RecoveryProgramView`

6. **Database & Edge Functions** (1 day)
   - Apply migrations
   - Create daily aggregation job

---

## 5. Dependencies

- F001: Biometric Correlation Engine (Implemented)
- N002: Circadian Vulnerability Shield (for disruption detection)
- Mood logging (Existing)
- Exercise sessions (Existing)
- Circles (Existing)

---

## 6. Edge Cases and Error Handling

| Edge Case           | Expected Behavior                |
| ------------------- | -------------------------------- |
| No data for day     | Skip day; don't penalize         |
| Threshold never hit | Use population default (-50)     |
| All days positive   | Show "building reserves" message |
| Crash detected      | Learn threshold; show recovery   |

---

## 7. Success Metrics

| Metric                      | Target              | Measurement                  |
| --------------------------- | ------------------- | ---------------------------- |
| Crash prediction accuracy   | > 75% within 3 days | Threshold alert → mood crash |
| Recovery program completion | > 50% complete      | 7-day program adherence      |
| User engagement with budget | > 35% DAU check     | Analytics                    |
| Crash frequency reduction   | 25% fewer crashes   | Before/after                 |

---

## 9. Competitive Analysis

| App      | Cumulative Feature | MindFriend Advantage         |
| -------- | ------------------ | ---------------------------- |
| Daylio   | Mood streaks       | Comprehensive debt model     |
| Bearable | Symptom tracking   | Predictive thresholds        |
| Finch    | Energy/mood        | Actionable recovery programs |

**MindFriend is the first app to model mental wellbeing as a cumulative debt system.**
