# N007: Stress Signature Fingerprint

> **Type:** NOVEL DIFFERENTIATOR
> **Phase:** Advanced Prediction
> **Complexity:** High
> **Priority:** P1
> **Dependencies:** N001 (Nervous System State Engine), N006 (Wellbeing Debt), Mood Logging (Existing)

---

## 1. Overview

### 1.1 Summary

The Stress Signature Fingerprint creates a personalized "early warning fingerprint" for each user — a unique pattern of prodromal symptoms (the warning signs that precede a mental health crisis). Every person has their own signature: one person stops sleeping but feels wired; another withdraws socially; another obsesses over small mistakes. By explicitly learning each user's signature through onboarding and historical analysis, MindFriend can detect the earliest signs of an approaching crisis 24-72 hours in advance and intervene before the spiral begins.

This is **personalized crisis prevention**: knowing your unique pattern before you recognize it yourself.

### 1.2 Business Value

- **Highest-Impact Intervention:** Prevent crises, not just respond to them
- **Deep Personalization:** Users feel truly known ("The app knows my patterns before I do")
- **Clinical Alignment:** Prodromal detection is a major focus in psychiatry research
- **Differentiation:** No consumer app does personalized prodromal pattern learning
- **Retention Through Trust:** Users who avoid crises become lifelong advocates

### 1.3 Scientific Foundation

- **Prodromal Symptoms:** Early warning signs precede psychiatric episodes (Yung, 2005)
- **Early Intervention:** Acting in prodromal phase prevents full episode (McGorry, 2008)
- **Individual Patterns:** Prodromal symptoms are highly individual (Niendam, 2007)
- **Self-Monitoring:** Awareness of personal patterns reduces relapse (Morriss, 2004)

---

## 2. Requirements

### 2.1 Functional Requirements

| ID     | Requirement                                                                     | Priority |
| ------ | ------------------------------------------------------------------------------- | -------- |
| FR-001 | System SHALL collect user's self-reported warning signs during onboarding       | P0       |
| FR-002 | System SHALL learn additional signature patterns from historical data           | P0       |
| FR-003 | System SHALL monitor for signature pattern emergence in real-time               | P0       |
| FR-004 | System SHALL alert user when signature pattern detected                         | P0       |
| FR-005 | System SHALL provide pattern-specific early intervention                        | P0       |
| FR-006 | System SHALL collect feedback on prediction accuracy to refine model            | P0       |
| FR-007 | System SHALL show "My Warning Signs" dashboard                                  | P1       |
| FR-008 | System SHALL support multiple signature patterns (anxiety, depression, burnout) | P1       |
| FR-009 | System SHALL track pattern accuracy over time                                   | P1       |
| FR-010 | System SHALL integrate with N006 wellbeing debt for compound signals            | P2       |

### 2.2 Non-Functional Requirements

| ID      | Requirement                                 | Target                       |
| ------- | ------------------------------------------- | ---------------------------- |
| NFR-001 | Pattern detection latency                   | < 1 hour from emergence      |
| NFR-002 | True positive rate (catching real patterns) | > 80%                        |
| NFR-003 | False positive rate (false alarms)          | < 20%                        |
| NFR-004 | Prediction lead time                        | 24-72 hours before crisis    |
| NFR-005 | Minimum data for pattern learning           | 30 days + 1 historical event |

### 2.3 Acceptance Criteria

1. Given a new user in onboarding, when they complete the warning signs questionnaire, then the system stores their self-reported signature
2. Given a user with 60 days of data and 1 past crisis, when the system analyzes history, then it identifies patterns that preceded the crisis
3. Given a user whose signature pattern is emerging, when 2+ signals are detected, then the user receives a gentle early warning
4. Given a detected pattern, when the user confirms or denies accuracy, then the system updates the pattern weights

---

## 3. Technical Design

### 3.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    iOS App Layer                                 │
├─────────────────────────────────────────────────────────────────┤
│ SignatureOnboardingFlow │ WarningDashboard │ EarlyInterventionUI│
├─────────────────────────────────────────────────────────────────┤
│                 StressSignatureViewModel                         │
├─────────────────────────────────────────────────────────────────┤
│                   StressSignatureEngine                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  Pattern     │  │   Signal     │  │  Prediction  │          │
│  │  Learner     │  │   Monitor    │  │   Ranker     │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
├─────────────────────────────────────────────────────────────────┤
│NervousSystemEngine│ WellbeingDebt │ MoodService │ HealthKit    │
│       (N001)      │     (N006)    │  (existing) │  (existing)  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Data Models

#### 3.2.1 SignatureComponent Model

```swift
struct SignatureComponent: Codable, Identifiable, Hashable {
    let id: UUID
    let category: ComponentCategory
    let signal: String
    let displayName: String
    let description: String

    enum ComponentCategory: String, Codable {
        case sleep = "sleep"
        case social = "social"
        case cognitive = "cognitive"
        case emotional = "emotional"
        case behavioral = "behavioral"
        case physical = "physical"
    }

    // Predefined library of signature components
    static let library: [SignatureComponent] = [
        // Sleep
        SignatureComponent(id: UUID(), category: .sleep, signal: "insomnia_wired",
            displayName: "Can't sleep but feel wired",
            description: "Difficulty sleeping despite feeling mentally active"),
        SignatureComponent(id: UUID(), category: .sleep, signal: "oversleeping",
            displayName: "Sleeping too much",
            description: "Wanting to sleep 10+ hours or stay in bed all day"),
        SignatureComponent(id: UUID(), category: .sleep, signal: "early_waking",
            displayName: "Waking up too early",
            description: "Waking at 3-4am and unable to fall back asleep"),

        // Social
        SignatureComponent(id: UUID(), category: .social, signal: "isolation",
            displayName: "Withdrawing from people",
            description: "Avoiding friends, ignoring messages, canceling plans"),
        SignatureComponent(id: UUID(), category: .social, signal: "irritability",
            displayName: "Snapping at loved ones",
            description: "Getting unusually irritated with people close to you"),

        // Cognitive
        SignatureComponent(id: UUID(), category: .cognitive, signal: "rumination",
            displayName: "Can't stop thinking about problems",
            description: "Obsessive thoughts about work, relationships, or mistakes"),
        SignatureComponent(id: UUID(), category: .cognitive, signal: "indecision",
            displayName: "Can't make decisions",
            description: "Even small decisions feel overwhelming"),
        SignatureComponent(id: UUID(), category: .cognitive, signal: "catastrophizing",
            displayName: "Worst-case thinking",
            description: "Everything feels like it will lead to disaster"),

        // Emotional
        SignatureComponent(id: UUID(), category: .emotional, signal: "numbness",
            displayName: "Feeling numb or empty",
            description: "Unable to feel emotions, going through the motions"),
        SignatureComponent(id: UUID(), category: .emotional, signal: "tearfulness",
            displayName: "Crying easily",
            description: "Tears come unexpectedly or at small triggers"),

        // Behavioral
        SignatureComponent(id: UUID(), category: .behavioral, signal: "procrastination",
            displayName: "Avoiding responsibilities",
            description: "Putting off work, chores, or important tasks"),
        SignatureComponent(id: UUID(), category: .behavioral, signal: "compulsions",
            displayName: "Stress behaviors",
            description: "Nail biting, skin picking, or other nervous habits"),

        // Physical
        SignatureComponent(id: UUID(), category: .physical, signal: "appetite_change",
            displayName: "Appetite changes",
            description: "Eating much more or much less than usual"),
        SignatureComponent(id: UUID(), category: .physical, signal: "tension",
            displayName: "Physical tension",
            description: "Headaches, jaw clenching, shoulder tightness"),
    ]
}
```

#### 3.2.2 StressSignature Model

```swift
struct StressSignature: Codable, Identifiable {
    let id: UUID
    let userId: String
    let crisisType: CrisisType
    let components: [WeightedComponent]
    let source: SignatureSource
    let confidence: Double
    let lastUpdated: Date

    enum CrisisType: String, Codable {
        case anxiety = "anxiety"
        case depression = "depression"
        case burnout = "burnout"
        case panic = "panic"
        case general = "general"
    }

    struct WeightedComponent: Codable {
        let componentId: UUID
        let signal: String
        let weight: Double              // 0.0-1.0 importance
        let detectionThreshold: Double  // When to consider "active"
        let lastActive: Date?
    }

    enum SignatureSource: String, Codable {
        case userReported               // From onboarding
        case historicalLearned          // From past crisis analysis
        case hybridRefined              // Combined and refined
    }
}
```

#### 3.2.3 PatternAlert Model

```swift
struct PatternAlert: Codable, Identifiable {
    let id: UUID
    let userId: String
    let signatureId: UUID
    let detectedAt: Date
    let activeComponents: [ActiveSignal]
    let overallSeverity: Severity
    let predictedTimeToEvent: TimeInterval?
    let interventionDelivered: Bool
    let userFeedback: AlertFeedback?

    struct ActiveSignal: Codable {
        let componentId: UUID
        let signal: String
        let detectedValue: Double       // Current signal strength
        let threshold: Double           // Component threshold
        let daysActive: Int            // How long signal has been present
    }

    enum Severity: String, Codable {
        case mild = "mild"              // 1-2 components active
        case moderate = "moderate"      // 3-4 components active
        case severe = "severe"          // 5+ components or critical signals
    }

    enum AlertFeedback: String, Codable {
        case accuratePrediction         // User confirms pattern was real
        case falseAlarm                 // Pattern was detected but no crisis
        case missedPattern              // Crisis happened without detection
        case helpedPrevent              // Early intervention worked
    }
}
```

#### 3.2.4 Database Schema

```sql
-- User stress signatures
CREATE TABLE stress_signatures (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    crisis_type TEXT NOT NULL,
    components JSONB NOT NULL,          -- Array of WeightedComponent
    source TEXT NOT NULL,
    confidence DECIMAL(3,2) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, crisis_type)
);

-- Pattern detection alerts
CREATE TABLE pattern_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    signature_id UUID NOT NULL REFERENCES stress_signatures(id),
    detected_at TIMESTAMPTZ NOT NULL,
    active_components JSONB NOT NULL,
    severity TEXT NOT NULL,
    predicted_time_to_event INTEGER,    -- Seconds
    intervention_delivered BOOLEAN DEFAULT FALSE,
    user_feedback TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Signal measurements (for pattern monitoring)
CREATE TABLE signature_signals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    signal TEXT NOT NULL,
    value DECIMAL(5,3) NOT NULL,
    date DATE NOT NULL,
    source TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, signal, date)
);

-- Historical crisis events (for learning)
CREATE TABLE crisis_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    crisis_type TEXT NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL,
    severity TEXT,
    user_reported BOOLEAN DEFAULT TRUE,
    analyzed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_signatures_user ON stress_signatures(user_id);
CREATE INDEX idx_alerts_user_time ON pattern_alerts(user_id, detected_at DESC);
CREATE INDEX idx_signals_user_date ON signature_signals(user_id, date DESC);

-- RLS
ALTER TABLE stress_signatures ENABLE ROW LEVEL SECURITY;
ALTER TABLE pattern_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE signature_signals ENABLE ROW LEVEL SECURITY;
ALTER TABLE crisis_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own signatures" ON stress_signatures FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users read own alerts" ON pattern_alerts FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users read own signals" ON signature_signals FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users read own crises" ON crisis_events FOR SELECT USING (auth.uid() = user_id);
```

### 3.3 Onboarding Flow

```swift
class SignatureOnboardingViewModel: ObservableObject {
    @Published var selectedComponents: Set<UUID> = []
    @Published var currentStep: OnboardingStep = .introduction

    enum OnboardingStep {
        case introduction
        case sleepPatterns
        case socialPatterns
        case cognitivePatterns
        case emotionalPatterns
        case behavioralPatterns
        case physicalPatterns
        case summary
    }

    func presentStep(_ step: OnboardingStep) -> [SignatureComponent] {
        switch step {
        case .sleepPatterns:
            return SignatureComponent.library.filter { $0.category == .sleep }
        case .socialPatterns:
            return SignatureComponent.library.filter { $0.category == .social }
        // ... etc
        default:
            return []
        }
    }

    func completeOnboarding() async -> StressSignature {
        let components = selectedComponents.compactMap { id in
            SignatureComponent.library.first { $0.id == id }
        }

        let weightedComponents = components.map { component in
            StressSignature.WeightedComponent(
                componentId: component.id,
                signal: component.signal,
                weight: 0.5,  // Start with equal weights
                detectionThreshold: 0.6,  // Default threshold
                lastActive: nil
            )
        }

        let signature = StressSignature(
            id: UUID(),
            userId: currentUserId,
            crisisType: .general,
            components: weightedComponents,
            source: .userReported,
            confidence: 0.5,  // Low confidence until validated
            lastUpdated: Date()
        )

        await saveSignature(signature)
        return signature
    }
}
```

### 3.4 Pattern Learning from History

```swift
class PatternLearner {
    func learnFromHistory(userId: String, crisisEvents: [CrisisEvent]) async -> StressSignature? {
        guard !crisisEvents.isEmpty else { return nil }

        // For each crisis, look at the 7 days before
        var signalScores: [String: [Double]] = [:]

        for crisis in crisisEvents {
            let weekBefore = await fetchSignals(
                userId: userId,
                from: crisis.occurredAt.addingTimeInterval(-7 * 24 * 3600),
                to: crisis.occurredAt
            )

            // Score each signal type by presence before crisis
            for signal in weekBefore {
                if signalScores[signal.signal] == nil {
                    signalScores[signal.signal] = []
                }
                signalScores[signal.signal]?.append(signal.value)
            }
        }

        // Find signals that were consistently elevated before crises
        let consistentSignals = signalScores.filter { (_, values) in
            let avgValue = values.average() ?? 0
            let consistency = Double(values.filter { $0 > 0.5 }.count) / Double(values.count)
            return avgValue > 0.5 && consistency > 0.6
        }

        guard !consistentSignals.isEmpty else { return nil }

        // Create learned signature
        let components = consistentSignals.map { (signal, values) in
            StressSignature.WeightedComponent(
                componentId: UUID(),
                signal: signal,
                weight: values.average() ?? 0.5,
                detectionThreshold: 0.6,
                lastActive: nil
            )
        }

        return StressSignature(
            id: UUID(),
            userId: userId,
            crisisType: determineCrisisType(from: crisisEvents),
            components: components,
            source: .historicalLearned,
            confidence: min(Double(crisisEvents.count) * 0.15 + 0.3, 0.9),
            lastUpdated: Date()
        )
    }
}
```

### 3.5 Real-Time Signal Monitoring

```swift
class SignalMonitor {
    private let nervousSystemEngine: NervousSystemStateEngine
    private let wellbeingDebtEngine: WellbeingDebtCalculator

    func measureDailySignals(for userId: String) async -> [SignatureSignal] {
        var signals: [SignatureSignal] = []
        let date = Date()

        // Sleep signals
        if let sleep = await fetchSleepData(userId: userId, date: date) {
            // Insomnia detection
            if sleep.duration < 5 * 3600 && sleep.quality < 0.4 {
                signals.append(SignatureSignal(
                    signal: "insomnia_wired",
                    value: 1.0 - (sleep.duration / (8 * 3600)),
                    date: date,
                    source: "healthkit"
                ))
            }
            // Oversleeping detection
            if sleep.duration > 10 * 3600 {
                signals.append(SignatureSignal(
                    signal: "oversleeping",
                    value: min((sleep.duration - 8 * 3600) / (4 * 3600), 1.0),
                    date: date,
                    source: "healthkit"
                ))
            }
        }

        // Social signals
        let socialActivity = await fetchCircleActivity(userId: userId, date: date)
        let avgSocialActivity = await fetchAverageSocialActivity(userId: userId)
        if socialActivity.messageCount < avgSocialActivity * 0.3 {
            signals.append(SignatureSignal(
                signal: "isolation",
                value: 1.0 - (Double(socialActivity.messageCount) / avgSocialActivity),
                date: date,
                source: "app_activity"
            ))
        }

        // Cognitive signals (from distortion detection)
        let distortions = await fetchDistortions(userId: userId, date: date)
        let catastrophizingCount = distortions.filter { $0.type == .catastrophizing }.count
        if catastrophizingCount >= 3 {
            signals.append(SignatureSignal(
                signal: "catastrophizing",
                value: min(Double(catastrophizingCount) / 5.0, 1.0),
                date: date,
                source: "cognitive_detection"
            ))
        }

        // Emotional signals (from nervous system)
        let states = await nervousSystemEngine.getDayStates(userId: userId, date: date)
        let dorsalPercent = Double(states.filter { $0.state == .dorsalVagal }.count) / Double(states.count)
        if dorsalPercent > 0.4 {
            signals.append(SignatureSignal(
                signal: "numbness",
                value: dorsalPercent,
                date: date,
                source: "nervous_system"
            ))
        }

        // Physical signals
        if let activity = await fetchActivityData(userId: userId, date: date) {
            if activity.steps < 1000 {  // Very low activity
                signals.append(SignatureSignal(
                    signal: "low_energy",
                    value: 1.0 - (Double(activity.steps) / 5000.0),
                    date: date,
                    source: "healthkit"
                ))
            }
        }

        await saveSignals(signals)
        return signals
    }
}
```

### 3.6 Pattern Detection Engine

```swift
class PatternDetector {
    func detectPatternEmergence(
        userId: String,
        signature: StressSignature
    ) async -> PatternAlert? {
        // Get signals from last 3 days
        let recentSignals = await fetchRecentSignals(userId: userId, days: 3)

        var activeComponents: [PatternAlert.ActiveSignal] = []

        for component in signature.components {
            let matchingSignals = recentSignals.filter { $0.signal == component.signal }

            if let latestSignal = matchingSignals.max(by: { $0.value < $1.value }),
               latestSignal.value >= component.detectionThreshold {

                let daysActive = matchingSignals.filter { $0.value >= component.detectionThreshold }.count

                activeComponents.append(PatternAlert.ActiveSignal(
                    componentId: component.componentId,
                    signal: component.signal,
                    detectedValue: latestSignal.value,
                    threshold: component.detectionThreshold,
                    daysActive: daysActive
                ))
            }
        }

        // Determine if alert should be triggered
        guard activeComponents.count >= 2 else { return nil }  // Need 2+ signals

        let severity: PatternAlert.Severity
        switch activeComponents.count {
        case 2: severity = .mild
        case 3...4: severity = .moderate
        default: severity = .severe
        }

        // Estimate time to event based on signal strength and historical data
        let avgSignalStrength = activeComponents.map { $0.detectedValue }.average() ?? 0.5
        let estimatedHours = Int((1.0 - avgSignalStrength) * 72)  // 0-72 hours

        return PatternAlert(
            id: UUID(),
            userId: userId,
            signatureId: signature.id,
            detectedAt: Date(),
            activeComponents: activeComponents,
            overallSeverity: severity,
            predictedTimeToEvent: TimeInterval(estimatedHours * 3600),
            interventionDelivered: false,
            userFeedback: nil
        )
    }
}
```

### 3.7 Early Intervention Delivery

```swift
class EarlyInterventionService {
    func deliverIntervention(for alert: PatternAlert, signature: StressSignature) async {
        // Generate personalized message
        let message = generateAlertMessage(activeComponents: alert.activeComponents)

        // Select intervention based on pattern
        let intervention = selectIntervention(
            severity: alert.overallSeverity,
            components: alert.activeComponents
        )

        // Deliver via notification
        await notificationService.send(
            title: "Pattern Noticed",
            body: message,
            category: .earlyWarning,
            payload: [
                "alertId": alert.id.uuidString,
                "interventionId": intervention.id.uuidString
            ]
        )

        // Mark as delivered
        await updateAlertDelivered(alertId: alert.id)
    }

    private func generateAlertMessage(activeComponents: [PatternAlert.ActiveSignal]) -> String {
        // Gentle, non-alarming language
        let topSignals = activeComponents.prefix(2).map { $0.signal }

        if topSignals.contains("isolation") && topSignals.contains("insomnia_wired") {
            return "I've noticed you've been quieter lately and sleep has been tough. This is a pattern we've seen before. Want to talk about it?"
        } else if topSignals.contains("catastrophizing") {
            return "It seems like worries have been building up. Let's take a moment to get grounded."
        } else {
            return "I'm noticing some familiar patterns. How are you really doing?"
        }
    }
}
```

### 3.8 API Contracts

#### 3.8.1 Get My Warning Signs

```
GET /api/v1/signature/mine
Authorization: Bearer <jwt>

Response 200:
{
    "signatures": [
        {
            "id": "uuid",
            "crisisType": "general",
            "components": [
                {
                    "signal": "isolation",
                    "displayName": "Withdrawing from people",
                    "weight": 0.8,
                    "lastActive": "2026-01-20"
                }
            ],
            "confidence": 0.75,
            "source": "hybridRefined"
        }
    ],
    "recentAlerts": [
        {
            "detectedAt": "2026-01-21T10:00:00Z",
            "severity": "mild",
            "activeComponents": ["isolation", "insomnia_wired"],
            "feedback": null
        }
    ],
    "accuracyStats": {
        "totalAlerts": 5,
        "accuratePredictions": 3,
        "falseAlarms": 1,
        "helpedPrevent": 1
    }
}
```

#### 3.8.2 Submit Alert Feedback

```
POST /api/v1/signature/alerts/{alertId}/feedback
Authorization: Bearer <jwt>
Content-Type: application/json

{
    "feedback": "accurate_prediction",
    "notes": "Felt the crash coming 2 days later"
}

Response 200:
{
    "success": true,
    "message": "Thank you. Your signature has been refined.",
    "newConfidence": 0.82
}
```

---

## 4. Implementation Details

### 4.1 Step-by-Step Implementation

1. **Create Component Library** (1 day)
   - Define all signature components
   - Create display content
   - Set up database seeding

2. **Build Onboarding Flow** (2 days)
   - Create step-by-step UI
   - Implement component selection
   - Save initial signature

3. **Implement Pattern Learner** (3 days)
   - Build historical analysis
   - Create signal correlation
   - Merge with user-reported

4. **Build Signal Monitor** (2 days)
   - Integrate with existing services
   - Create daily measurement job
   - Store signal history

5. **Create Pattern Detector** (2 days)
   - Implement detection algorithm
   - Add severity classification
   - Build time estimation

6. **Build Intervention Delivery** (2 days)
   - Create message generation
   - Integrate with notifications
   - Add feedback collection

7. **Create iOS UI** (3 days)
   - `SignatureOnboardingFlow`
   - `WarningSignsDashboard`
   - `PatternAlertView`

---

## 5. Dependencies

- N001: Nervous System State Engine (emotional state signals)
- N003: Cognitive Distortion Detector (cognitive signals)
- N004: Social Vitality Index (social signals)
- N006: Wellbeing Debt Calculator (compound signals)
- HealthKit integration (sleep, activity signals)

---

## 6. Edge Cases and Error Handling

| Edge Case                                  | Expected Behavior                   |
| ------------------------------------------ | ----------------------------------- |
| No components selected in onboarding       | Suggest most common patterns        |
| No historical crisis data                  | Rely on user-reported only          |
| Pattern detected but user says false alarm | Reduce component weights            |
| Crisis without detection                   | Add new components from that period |
| All signals active                         | Cap severity; focus on top signals  |

---

## 7. Success Metrics

| Metric                 | Target                   | Measurement                   |
| ---------------------- | ------------------------ | ----------------------------- |
| True positive rate     | > 80%                    | Feedback: accurate_prediction |
| False alarm rate       | < 20%                    | Feedback: false_alarm         |
| Prevention success     | > 50%                    | Feedback: helped_prevent      |
| Lead time accuracy     | Within 24h of estimated  | Actual vs predicted           |
| Confidence improvement | +0.1 per validated alert | Rolling confidence            |

---

## 8. Competitive Analysis

| App      | Prodromal Feature      | MindFriend Advantage                |
| -------- | ---------------------- | ----------------------------------- |
| eMoods   | Mood charting only     | Personalized pattern learning       |
| Daylio   | Retrospective patterns | Prospective prediction              |
| Bearable | Symptom correlation    | Individual signature + intervention |
| Woebot   | Generic check-ins      | User's unique warning signs         |

**MindFriend is the first consumer app to learn and monitor personalized prodromal signatures.**
