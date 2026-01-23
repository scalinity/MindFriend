# N004: Social Vitality Index

> **Type:** NOVEL DIFFERENTIATOR
> **Phase:** Social Intelligence
> **Complexity:** Medium-High
> **Priority:** P0
> **Dependencies:** Circles (Already Implemented), Mood logging (Existing)

---

## 1. Overview

### 1.1 Summary

The Social Vitality Index models each user's "social health" as a dynamic score that predicts emotional wellbeing. It tracks the frequency, depth, and reciprocity of social interactions across circles, identifies social withdrawal patterns as early warning signs of depression, and enables proactive peer support interventions. When a user begins withdrawing, their trusted circle members can be notified to reach out — with the user's consent — before isolation spirals into crisis.

This is **social contagion modeling for good**: using the science of social networks to prevent mental health deterioration.

### 1.2 Business Value

- **Early Intervention:** Social withdrawal precedes 70%+ of depressive episodes by 7-14 days
- **Peer Support Scalability:** Users support each other, reducing reliance on AI/therapists
- **Network Effects:** Users invite friends, driving organic growth
- **Retention Through Connection:** Users with active circles have 3x retention
- **Clinical Differentiation:** First app to model social dynamics + mental health predictively

### 1.3 Scientific Foundation

- **Social Contagion:** Emotions spread through networks (Fowler & Christakis, 2008)
- **Loneliness as Predictor:** Social isolation precedes depression onset (Cacioppo, 2006)
- **Social Support as Buffer:** Peer support moderates stress effects (Cohen & Wills, 1985)
- **Digital Phenotyping:** Smartphone usage patterns predict mental health (Torous, 2016)

---

## 2. Requirements

### 2.1 Functional Requirements

| ID     | Requirement                                                                   | Priority |
| ------ | ----------------------------------------------------------------------------- | -------- |
| FR-001 | System SHALL calculate a Social Vitality Index (0-100) for each user          | P0       |
| FR-002 | Index SHALL update daily based on circle activity                             | P0       |
| FR-003 | System SHALL detect social withdrawal patterns (declining index over 5+ days) | P0       |
| FR-004 | System SHALL enable opt-in peer notification when user is withdrawing         | P0       |
| FR-005 | System SHALL track interaction quality (not just frequency)                   | P0       |
| FR-006 | System SHALL identify "energy vampires" (negative-correlated relationships)   | P1       |
| FR-007 | System SHALL identify "support pillars" (positive-correlated relationships)   | P1       |
| FR-008 | System SHALL correlate social index with mood to show relationship            | P1       |
| FR-009 | System SHALL provide "Social Health" dashboard with insights                  | P1       |
| FR-010 | System SHALL suggest when to reach out to specific people                     | P2       |

### 2.2 Non-Functional Requirements

| ID      | Requirement                      | Target                                          |
| ------- | -------------------------------- | ----------------------------------------------- |
| NFR-001 | Index calculation latency        | < 2 seconds                                     |
| NFR-002 | Withdrawal detection sensitivity | > 80% (catches true withdrawals)                |
| NFR-003 | Withdrawal detection specificity | > 70% (avoids false alarms)                     |
| NFR-004 | Privacy protection               | All peer notifications require explicit consent |
| NFR-005 | Minimum data for baseline        | 14 days of activity                             |

### 2.3 Acceptance Criteria

1. Given a user with 30 days of circle activity, when they view their Social Vitality Index, then they see a score (0-100) and trend indicator
2. Given a user whose index drops from 75 to 40 over 7 days, when the system detects this pattern, then it asks if user wants friends notified
3. Given a user who opts in to peer notification, when they are withdrawing, then their designated friends receive a gentle prompt to reach out
4. Given a user with mixed relationships, when they view Social Insights, then they see which relationships correlate with better/worse moods

---

## 3. Technical Design

### 3.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    iOS App Layer                                 │
├─────────────────────────────────────────────────────────────────┤
│ SocialHealthDashboard │ RelationshipInsightsView │ PeerAlertUI  │
├─────────────────────────────────────────────────────────────────┤
│                 SocialVitalityViewModel                          │
├─────────────────────────────────────────────────────────────────┤
│                  SocialVitalityEngine                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  Interaction │  │  Withdrawal  │  │ Relationship │          │
│  │   Analyzer   │  │   Detector   │  │   Correlator │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
├─────────────────────────────────────────────────────────────────┤
│ CirclesService │ MoodService │ NotificationService │ Supabase  │
│   (existing)   │  (existing) │     (existing)      │ Realtime  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Data Models

#### 3.2.1 SocialVitalityScore Model

```swift
struct SocialVitalityScore: Codable, Identifiable {
    let id: UUID
    let userId: String
    let date: Date
    let overallScore: Int                   // 0-100
    let trend: ScoreTrend                   // improving, stable, declining, plummeting
    let components: ScoreComponents

    struct ScoreComponents: Codable {
        let interactionFrequency: Int       // 0-25 points
        let interactionDepth: Int           // 0-25 points (message length, response time)
        let reciprocity: Int                // 0-25 points (give vs receive balance)
        let diversityOfConnections: Int     // 0-25 points (multiple circles, not just one)
    }

    enum ScoreTrend: String, Codable {
        case improving = "improving"        // +10 or more over 7 days
        case stable = "stable"              // -10 to +10 over 7 days
        case declining = "declining"        // -10 to -25 over 7 days
        case plummeting = "plummeting"      // -25 or more over 7 days (alert)
    }
}
```

#### 3.2.2 InteractionMetric Model

```swift
struct InteractionMetric: Codable {
    let userId: String
    let otherUserId: String
    let circleId: String
    let date: Date

    // Quantitative metrics
    let messagesSent: Int
    let messagesReceived: Int
    let averageResponseTimeMinutes: Double?
    let averageMessageLength: Int

    // Derived metrics
    let reciprocityRatio: Double           // sent/received (1.0 = balanced)
    let engagementScore: Double            // Composite of depth signals
}
```

#### 3.2.3 RelationshipCorrelation Model

```swift
struct RelationshipCorrelation: Codable, Identifiable {
    let id: UUID
    let userId: String
    let otherUserId: String
    let otherUserDisplayName: String
    let moodCorrelation: Double           // -1.0 to +1.0
    let interactionCount: Int             // For statistical significance
    let classification: RelationshipType
    let lastUpdated: Date

    enum RelationshipType: String, Codable {
        case supportPillar = "support_pillar"    // r > 0.3
        case neutral = "neutral"                  // -0.3 to 0.3
        case draining = "draining"               // r < -0.3
    }
}
```

#### 3.2.4 Database Schema

```sql
-- Daily social vitality scores
CREATE TABLE social_vitality_scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    overall_score INTEGER NOT NULL CHECK (overall_score >= 0 AND overall_score <= 100),
    trend TEXT NOT NULL CHECK (trend IN ('improving', 'stable', 'declining', 'plummeting')),
    interaction_frequency INTEGER NOT NULL,
    interaction_depth INTEGER NOT NULL,
    reciprocity INTEGER NOT NULL,
    diversity INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, date)
);

-- Interaction metrics (aggregated daily per relationship)
CREATE TABLE interaction_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    other_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    messages_sent INTEGER DEFAULT 0,
    messages_received INTEGER DEFAULT 0,
    avg_response_time_minutes DECIMAL(10,2),
    avg_message_length INTEGER,
    reciprocity_ratio DECIMAL(4,3),
    engagement_score DECIMAL(4,3),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, other_user_id, circle_id, date)
);

-- Relationship correlations (updated weekly)
CREATE TABLE relationship_correlations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    other_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    mood_correlation DECIMAL(4,3) NOT NULL CHECK (mood_correlation >= -1 AND mood_correlation <= 1),
    interaction_count INTEGER NOT NULL,
    classification TEXT NOT NULL CHECK (classification IN ('support_pillar', 'neutral', 'draining')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, other_user_id)
);

-- Peer alert preferences
CREATE TABLE peer_alert_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
    enabled BOOLEAN DEFAULT FALSE,
    alert_threshold TEXT DEFAULT 'plummeting',  -- When to notify
    designated_supporters UUID[] DEFAULT '{}',  -- Who can be notified
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Peer alerts sent
CREATE TABLE peer_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    supporter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    alert_type TEXT NOT NULL,  -- 'withdrawal_detected', 'reach_out_reminder'
    message TEXT,
    acknowledged BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_social_vitality_user_date ON social_vitality_scores(user_id, date DESC);
CREATE INDEX idx_interaction_metrics_user_date ON interaction_metrics(user_id, date DESC);
CREATE INDEX idx_relationship_correlations_user ON relationship_correlations(user_id);

-- RLS
ALTER TABLE social_vitality_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE interaction_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE relationship_correlations ENABLE ROW LEVEL SECURITY;
ALTER TABLE peer_alert_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE peer_alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own scores" ON social_vitality_scores
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can read own metrics" ON interaction_metrics
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can read own correlations" ON relationship_correlations
    FOR SELECT USING (auth.uid() = user_id);
```

### 3.3 Social Vitality Calculation Algorithm

```swift
class SocialVitalityCalculator {
    func calculateDailyScore(for userId: String, on date: Date) async -> SocialVitalityScore {
        // Fetch interaction data for the day
        let interactions = await fetchInteractions(userId: userId, date: date)

        // Component 1: Interaction Frequency (0-25)
        let frequencyScore = calculateFrequencyScore(interactions)

        // Component 2: Interaction Depth (0-25)
        let depthScore = calculateDepthScore(interactions)

        // Component 3: Reciprocity (0-25)
        let reciprocityScore = calculateReciprocityScore(interactions)

        // Component 4: Diversity of Connections (0-25)
        let diversityScore = calculateDiversityScore(interactions)

        let overallScore = frequencyScore + depthScore + reciprocityScore + diversityScore

        // Calculate trend by comparing to past 7 days
        let trend = await calculateTrend(userId: userId, currentScore: overallScore)

        return SocialVitalityScore(
            id: UUID(),
            userId: userId,
            date: date,
            overallScore: overallScore,
            trend: trend,
            components: SocialVitalityScore.ScoreComponents(
                interactionFrequency: frequencyScore,
                interactionDepth: depthScore,
                reciprocity: reciprocityScore,
                diversityOfConnections: diversityScore
            )
        )
    }

    private func calculateFrequencyScore(_ interactions: [InteractionMetric]) -> Int {
        let totalMessages = interactions.reduce(0) { $0 + $1.messagesSent + $1.messagesReceived }

        // Scoring rubric:
        // 0 messages = 0 points
        // 1-5 messages = 10 points
        // 6-15 messages = 17 points
        // 16+ messages = 25 points
        switch totalMessages {
        case 0: return 0
        case 1...5: return 10
        case 6...15: return 17
        default: return 25
        }
    }

    private func calculateDepthScore(_ interactions: [InteractionMetric]) -> Int {
        guard !interactions.isEmpty else { return 0 }

        // Average message length as proxy for depth
        let avgLength = interactions.compactMap { $0.averageMessageLength }.average() ?? 0

        // Response time (faster = more engaged)
        let avgResponseTime = interactions.compactMap { $0.averageResponseTimeMinutes }.average() ?? Double.infinity

        var score = 0

        // Length contribution (0-12)
        switch avgLength {
        case 0..<20: score += 3
        case 20..<50: score += 7
        case 50..<100: score += 10
        default: score += 12
        }

        // Response time contribution (0-13)
        switch avgResponseTime {
        case 0..<30: score += 13      // Under 30 min
        case 30..<120: score += 9     // Under 2 hours
        case 120..<480: score += 5    // Under 8 hours
        default: score += 2
        }

        return min(score, 25)
    }

    private func calculateReciprocityScore(_ interactions: [InteractionMetric]) -> Int {
        let totalSent = interactions.reduce(0) { $0 + $1.messagesSent }
        let totalReceived = interactions.reduce(0) { $0 + $1.messagesReceived }

        guard totalSent + totalReceived > 0 else { return 0 }

        // Ratio near 1.0 is ideal (balanced)
        let ratio = Double(totalSent) / max(Double(totalReceived), 1.0)

        // Score based on how close to 1.0
        let deviation = abs(ratio - 1.0)

        switch deviation {
        case 0..<0.3: return 25     // Very balanced
        case 0.3..<0.6: return 18   // Slightly imbalanced
        case 0.6..<1.0: return 10   // Notably imbalanced
        default: return 5           // Severely imbalanced
        }
    }

    private func calculateDiversityScore(_ interactions: [InteractionMetric]) -> Int {
        let uniquePeople = Set(interactions.map { $0.otherUserId }).count
        let uniqueCircles = Set(interactions.map { $0.circleId }).count

        var score = 0

        // People diversity (0-15)
        switch uniquePeople {
        case 0: score += 0
        case 1: score += 5
        case 2: score += 10
        default: score += 15
        }

        // Circle diversity (0-10)
        switch uniqueCircles {
        case 0: score += 0
        case 1: score += 4
        default: score += 10
        }

        return min(score, 25)
    }
}
```

### 3.4 Withdrawal Detection Algorithm

```swift
class WithdrawalDetector {
    func detectWithdrawal(for userId: String) async -> WithdrawalStatus? {
        // Get last 14 days of scores
        let scores = await fetchScores(userId: userId, days: 14)
        guard scores.count >= 7 else { return nil }  // Need minimum data

        let recentScores = Array(scores.prefix(7))
        let olderScores = Array(scores.suffix(7))

        let recentAvg = recentScores.map { $0.overallScore }.average()!
        let olderAvg = olderScores.map { $0.overallScore }.average()!

        let decline = olderAvg - recentAvg

        // Check for consistent decline pattern
        let isConsistentlyDeclining = recentScores.dropFirst().allSatisfy { score in
            score.overallScore <= (recentScores.first?.overallScore ?? 0)
        }

        if decline > 25 && isConsistentlyDeclining {
            return WithdrawalStatus(
                severity: .severe,
                declinePercent: Int((decline / olderAvg) * 100),
                daysSincePeak: findDaysSincePeak(scores),
                shouldAlert: true
            )
        } else if decline > 15 && isConsistentlyDeclining {
            return WithdrawalStatus(
                severity: .moderate,
                declinePercent: Int((decline / olderAvg) * 100),
                daysSincePeak: findDaysSincePeak(scores),
                shouldAlert: false
            )
        }

        return nil
    }

    struct WithdrawalStatus {
        let severity: Severity
        let declinePercent: Int
        let daysSincePeak: Int
        let shouldAlert: Bool

        enum Severity: String {
            case moderate
            case severe
        }
    }
}
```

### 3.5 Peer Alert System

```swift
class PeerAlertService {
    private let notificationService: NotificationService

    func handleWithdrawalDetected(userId: String, status: WithdrawalStatus) async {
        // Check if user has opted in
        guard let preferences = await fetchAlertPreferences(userId: userId),
              preferences.enabled else {
            return
        }

        // Check if threshold is met
        guard status.severity.rawValue >= preferences.alertThreshold else {
            return
        }

        // Send alerts to designated supporters
        for supporterId in preferences.designatedSupporters {
            let alert = PeerAlert(
                userId: userId,
                supporterId: supporterId,
                alertType: .withdrawalDetected,
                message: generateSupporterMessage(userName: await getUserName(userId))
            )

            await savePeerAlert(alert)
            await sendPushToSupporter(supporterId: supporterId, alert: alert)
        }
    }

    private func generateSupporterMessage(userName: String) -> String {
        // Gentle, non-alarming message
        return "\(userName) might appreciate hearing from you today. A quick message could brighten their day. 💙"
    }

    private func sendPushToSupporter(supporterId: String, alert: PeerAlert) async {
        await notificationService.send(
            to: supporterId,
            title: "A Friend Could Use Support",
            body: alert.message,
            category: .peerSupport,
            payload: ["alertId": alert.id.uuidString]
        )
    }
}
```

### 3.6 API Contracts

#### 3.6.1 Get Social Vitality Dashboard

```
GET /api/v1/social-vitality/dashboard
Authorization: Bearer <jwt>

Response 200:
{
    "currentScore": 72,
    "trend": "stable",
    "components": {
        "frequency": 20,
        "depth": 18,
        "reciprocity": 22,
        "diversity": 12
    },
    "weeklyChange": -3,
    "topSupporters": [
        { "name": "Sarah", "correlation": 0.45 },
        { "name": "Mike", "correlation": 0.38 }
    ],
    "insight": "Your mood tends to improve after connecting with Sarah. Consider reaching out today.",
    "alertStatus": {
        "enabled": true,
        "supportersConfigured": 2
    }
}
```

#### 3.6.2 Configure Peer Alerts

```
PUT /api/v1/social-vitality/peer-alerts
Authorization: Bearer <jwt>
Content-Type: application/json

{
    "enabled": true,
    "alertThreshold": "severe",
    "designatedSupporters": ["uuid1", "uuid2"]
}

Response 200:
{
    "success": true,
    "message": "Peer alert preferences updated"
}
```

---

## 4. Implementation Details

### 4.1 Step-by-Step Implementation

1. **Create Interaction Tracking** (2 days)
   - Hook into circle post/reply events
   - Calculate response times and message lengths
   - Store daily aggregated metrics

2. **Build Vitality Calculator** (2 days)
   - Implement scoring algorithm for each component
   - Create trend calculation
   - Set up daily aggregation job

3. **Implement Withdrawal Detector** (2 days)
   - Build pattern detection algorithm
   - Add severity classification
   - Create alert trigger logic

4. **Build Relationship Correlator** (2 days)
   - Correlate interaction patterns with mood entries
   - Classify relationships (supporter, neutral, draining)
   - Update weekly

5. **Create Peer Alert System** (2 days)
   - Build preference management
   - Implement supporter notification flow
   - Add consent/privacy controls

6. **Build iOS UI** (3 days)
   - `SocialHealthDashboardView`
   - `RelationshipInsightsView`
   - `PeerAlertSettingsView`

7. **Database & Edge Functions** (1 day)
   - Apply migrations
   - Create aggregation Edge Function
   - Set up RLS policies

---

## 5. Dependencies

### 5.1 Prerequisites

- Circles feature (Implemented)
- Mood logging (Existing)
- Push notifications (Existing)

---

## 6. Edge Cases and Error Handling

| Edge Case                       | Expected Behavior                       |
| ------------------------------- | --------------------------------------- |
| User has no circles             | Show "Join a circle to start tracking"  |
| User in circles but no activity | Show score = 0 with encouragement       |
| Only one person in circle       | Diversity score capped at 15            |
| Supporter removes MindFriend    | Gracefully handle delivery failure      |
| User opts out after alerts sent | Stop future alerts; acknowledge receipt |
| Correlation insufficient data   | Require 10+ interactions to classify    |

---

## 7. Testing Requirements

### 7.1 Unit Tests

```swift
class SocialVitalityTests: XCTestCase {
    func testScoreCalculationWithBalancedActivity()
    func testScoreDropsWithWithdrawal()
    func testWithdrawalDetectionSensitivity()
    func testReciprocityScoreForImbalancedRelationship()
    func testCorrelationClassification()
}
```

---

## 8. Success Metrics

| Metric                        | Target                  | Measurement                            |
| ----------------------------- | ----------------------- | -------------------------------------- |
| Withdrawal detection accuracy | > 80% sensitivity       | User self-report validation            |
| Peer alert engagement         | > 50% act on alerts     | Track if supporter messages within 24h |
| Mood improvement post-support | 0.5+ point increase     | Mood comparison                        |
| Feature adoption              | > 30% DAU enable alerts | Analytics                              |
| Circle engagement increase    | 20% more posts          | Post frequency                         |

---

## 9. Competitive Analysis

| App        | Social Feature     | MindFriend Advantage                    |
| ---------- | ------------------ | --------------------------------------- |
| Finch      | Buddy system       | Withdrawal detection + proactive alerts |
| Happify    | Community tracks   | Relationship quality modeling           |
| Daylio     | No social features | Social vitality as first-class metric   |
| BetterHelp | Group therapy      | Async, peer-to-peer at scale            |

**MindFriend is the first app to model social dynamics predictively for mental health intervention.**
