# N005: Intervention Efficacy Engine

> **Type:** NOVEL DIFFERENTIATOR
> **Phase:** Core Analytics
> **Complexity:** High
> **Priority:** P0
> **Dependencies:** N001 (Nervous System State Engine), Emotion Analyzer (Existing), Exercise Sessions (Existing)

---

## 1. Overview

### 1.1 Summary

The Intervention Efficacy Engine tracks emotional state _during_ interventions — not just before and after — to measure what actually works for each user. By analyzing real-time voice emotion, biometrics, and behavioral signals while a user completes an exercise, the system creates personalized "efficacy profiles" that answer: "Which specific exercises work best for _me_, in _this_ state, at _this_ time of day?"

This transforms MindFriend from a content library into a precision wellness tool.

### 1.2 Business Value

- **Personalization:** Each user gets interventions proven to work for them
- **Outcome Proof:** Show users measurable improvement ("This exercise shifts your state 73% of the time")
- **Continuous Improvement:** System learns which exercises to recommend
- **Clinical Value:** Exportable data showing what works for individual patients
- **Differentiation:** No wellness app tracks real-time emotional trajectory during exercises

### 1.3 Scientific Foundation

- **Ecological Momentary Assessment (EMA):** Real-time data collection in natural settings
- **N-of-1 Trials:** Personalized treatment evaluation methodology
- **Biofeedback Research:** Real-time physiological monitoring improves outcomes
- **Treatment Response Prediction:** Early response predicts full response (Szegedi, 2009)

---

## 2. Requirements

### 2.1 Functional Requirements

| ID     | Requirement                                                                                    | Priority |
| ------ | ---------------------------------------------------------------------------------------------- | -------- |
| FR-001 | System SHALL capture emotional state at intervention start, during (every 30s), and end        | P0       |
| FR-002 | System SHALL calculate "efficacy score" for each intervention completion                       | P0       |
| FR-003 | System SHALL build per-user efficacy profiles for each exercise                                | P0       |
| FR-004 | System SHALL use efficacy profiles to personalize exercise recommendations                     | P0       |
| FR-005 | System SHALL show users "what works for you" dashboard                                         | P0       |
| FR-006 | System SHALL detect "breakthrough moments" (rapid positive shifts)                             | P1       |
| FR-007 | System SHALL track time-of-day efficacy patterns                                               | P1       |
| FR-008 | System SHALL correlate efficacy with starting state (e.g., "works when anxious, not when sad") | P1       |
| FR-009 | System SHALL track long-term efficacy trends (does this exercise work better over time?)       | P1       |
| FR-010 | System SHALL enable efficacy data export for therapist sharing                                 | P2       |

### 2.2 Non-Functional Requirements

| ID      | Requirement                               | Target                        |
| ------- | ----------------------------------------- | ----------------------------- |
| NFR-001 | Real-time capture latency                 | < 2 seconds                   |
| NFR-002 | Efficacy calculation latency              | < 5 seconds post-intervention |
| NFR-003 | Minimum completions for reliable efficacy | 5 sessions per exercise       |
| NFR-004 | Battery impact during tracking            | < 3% for 15-min session       |
| NFR-005 | Privacy: on-device processing             | Raw signals never transmitted |

### 2.3 Acceptance Criteria

1. Given a user starting a breathing exercise while anxious, when emotion is tracked throughout, then the system shows moment-by-moment trajectory on completion
2. Given a user with 10+ completions of an exercise, when they view "What Works", then they see efficacy score and contextual factors
3. Given two exercises with different efficacy scores, when the system recommends, then higher-efficacy exercises are prioritized
4. Given a "breakthrough moment" detected mid-session, when the session ends, then the system highlights what happened

---

## 3. Technical Design

### 3.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    iOS App Layer                                 │
├─────────────────────────────────────────────────────────────────┤
│  ExercisePlayer  │  EfficacyDashboard  │  BreakthroughOverlay   │
├─────────────────────────────────────────────────────────────────┤
│                 InterventionEfficacyViewModel                    │
├─────────────────────────────────────────────────────────────────┤
│                  InterventionEfficacyEngine                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Trajectory   │  │  Efficacy    │  │ Breakthrough │          │
│  │  Tracker     │  │  Calculator  │  │   Detector   │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
├─────────────────────────────────────────────────────────────────┤
│ NervousSystemStateEngine │ EmotionAnalyzer │ ExerciseService   │
│        (N001)            │    (existing)   │    (existing)      │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Data Models

#### 3.2.1 EmotionalTrajectory Model

```swift
struct EmotionalTrajectory: Codable {
    let sessionId: String
    let userId: String
    let exerciseId: String
    let startTime: Date
    let endTime: Date
    let samples: [TrajectoryPoint]

    struct TrajectoryPoint: Codable {
        let timestamp: Date
        let secondsFromStart: Int
        let nervousSystemState: NervousSystemState?
        let emotionClassification: EmotionClassification?
        let hrvReading: Double?
        let compositeScore: Double  // -1.0 (distressed) to +1.0 (calm/positive)
    }

    var startingState: Double {
        samples.first?.compositeScore ?? 0
    }

    var endingState: Double {
        samples.last?.compositeScore ?? 0
    }

    var netChange: Double {
        endingState - startingState
    }

    var trajectory: TrajectoryShape {
        // Analyze shape of change over time
        let midpoint = samples[samples.count / 2].compositeScore
        if netChange > 0.3 && midpoint > startingState {
            return .steadyImprovement
        } else if netChange > 0.3 && midpoint < startingState {
            return .lateBreakthrough
        } else if netChange < -0.1 {
            return .deterioration
        } else {
            return .flat
        }
    }

    enum TrajectoryShape: String, Codable {
        case steadyImprovement     // Gradual positive change
        case lateBreakthrough      // Initial dip, then improvement
        case earlyPeak             // Early improvement, then plateau
        case deterioration         // Got worse
        case flat                  // No significant change
    }
}
```

#### 3.2.2 InterventionEfficacy Model

```swift
struct InterventionEfficacy: Codable, Identifiable {
    let id: UUID
    let userId: String
    let exerciseId: String
    let sessionId: String
    let completedAt: Date

    // Core metrics
    let efficacyScore: Double           // 0-100 overall score
    let netEmotionalChange: Double      // -1.0 to +1.0
    let trajectoryShape: EmotionalTrajectory.TrajectoryShape
    let breakthroughDetected: Bool
    let breakthroughSecond: Int?        // When breakthrough occurred

    // Context
    let startingState: InterventionContext
    let timeOfDay: TimeOfDay
    let dayOfWeek: Int
    let priorSleepQuality: Double?
    let stressLevel: Double?

    struct InterventionContext: Codable {
        let nervousSystemState: NervousSystemState
        let primaryEmotion: String
        let stressLevel: Double
    }

    enum TimeOfDay: String, Codable {
        case morning = "morning"     // 5am-12pm
        case afternoon = "afternoon" // 12pm-5pm
        case evening = "evening"     // 5pm-9pm
        case night = "night"         // 9pm-5am
    }
}
```

#### 3.2.3 UserEfficacyProfile Model

```swift
struct UserEfficacyProfile: Codable {
    let userId: String
    let exerciseId: String
    let exerciseName: String
    let lastUpdated: Date

    // Aggregate efficacy
    let overallEfficacyScore: Double     // 0-100 weighted average
    let completionCount: Int
    let confidence: Double               // Increases with more data

    // Contextual efficacy
    let efficacyByState: [NervousSystemState: Double]
    let efficacyByTimeOfDay: [InterventionEfficacy.TimeOfDay: Double]
    let efficacyByEmotion: [String: Double]

    // Insights
    let bestContext: String?             // "Works best when you're anxious, in the evening"
    let trend: EfficacyTrend             // Getting better over time?

    enum EfficacyTrend: String, Codable {
        case improving      // Efficacy increasing over time
        case stable
        case declining      // User may be habituating
    }
}
```

#### 3.2.4 Database Schema

```sql
-- Emotional trajectory data points
CREATE TABLE emotional_trajectories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id),
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    samples JSONB NOT NULL DEFAULT '[]',  -- Array of trajectory points
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Intervention efficacy scores
CREATE TABLE intervention_efficacy (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id),
    session_id UUID NOT NULL,
    completed_at TIMESTAMPTZ NOT NULL,
    efficacy_score DECIMAL(5,2) NOT NULL CHECK (efficacy_score >= 0 AND efficacy_score <= 100),
    net_emotional_change DECIMAL(4,3) NOT NULL,
    trajectory_shape TEXT NOT NULL,
    breakthrough_detected BOOLEAN DEFAULT FALSE,
    breakthrough_second INTEGER,
    starting_state JSONB NOT NULL,
    time_of_day TEXT NOT NULL,
    day_of_week INTEGER NOT NULL,
    prior_sleep_quality DECIMAL(3,2),
    stress_level DECIMAL(3,2),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- User efficacy profiles (aggregated, updated daily)
CREATE TABLE user_efficacy_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id),
    overall_efficacy_score DECIMAL(5,2) NOT NULL,
    completion_count INTEGER NOT NULL,
    confidence DECIMAL(3,2) NOT NULL,
    efficacy_by_state JSONB NOT NULL DEFAULT '{}',
    efficacy_by_time_of_day JSONB NOT NULL DEFAULT '{}',
    efficacy_by_emotion JSONB NOT NULL DEFAULT '{}',
    best_context TEXT,
    trend TEXT NOT NULL DEFAULT 'stable',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, exercise_id)
);

-- Indexes
CREATE INDEX idx_trajectories_user_session ON emotional_trajectories(user_id, session_id);
CREATE INDEX idx_efficacy_user_exercise ON intervention_efficacy(user_id, exercise_id);
CREATE INDEX idx_profiles_user ON user_efficacy_profiles(user_id);

-- RLS
ALTER TABLE emotional_trajectories ENABLE ROW LEVEL SECURITY;
ALTER TABLE intervention_efficacy ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_efficacy_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own trajectories" ON emotional_trajectories FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users insert own trajectories" ON emotional_trajectories FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users read own efficacy" ON intervention_efficacy FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users read own profiles" ON user_efficacy_profiles FOR SELECT USING (auth.uid() = user_id);
```

### 3.3 Real-Time Trajectory Tracking

```swift
class TrajectoryTracker {
    private let nervousSystemEngine: NervousSystemStateEngine
    private let emotionAnalyzer: EmotionAnalyzer
    private var currentTrajectory: EmotionalTrajectory?
    private var samplingTimer: Timer?

    private let samplingInterval: TimeInterval = 30  // Every 30 seconds

    func startTracking(sessionId: String, exerciseId: String) {
        let startTime = Date()

        // Capture starting state
        let startingPoint = captureCurrentState(secondsFromStart: 0)

        currentTrajectory = EmotionalTrajectory(
            sessionId: sessionId,
            userId: currentUserId,
            exerciseId: exerciseId,
            startTime: startTime,
            endTime: startTime,  // Will be updated
            samples: [startingPoint]
        )

        // Start periodic sampling
        samplingTimer = Timer.scheduledTimer(withTimeInterval: samplingInterval, repeats: true) { [weak self] _ in
            self?.captureSample()
        }
    }

    func stopTracking() -> EmotionalTrajectory? {
        samplingTimer?.invalidate()
        samplingTimer = nil

        // Capture final state
        if var trajectory = currentTrajectory {
            let finalPoint = captureCurrentState(secondsFromStart: Int(Date().timeIntervalSince(trajectory.startTime)))
            trajectory.samples.append(finalPoint)
            trajectory.endTime = Date()
            currentTrajectory = nil
            return trajectory
        }

        return nil
    }

    private func captureSample() {
        guard var trajectory = currentTrajectory else { return }

        let secondsFromStart = Int(Date().timeIntervalSince(trajectory.startTime))
        let point = captureCurrentState(secondsFromStart: secondsFromStart)
        trajectory.samples.append(point)
        currentTrajectory = trajectory
    }

    private func captureCurrentState(secondsFromStart: Int) -> EmotionalTrajectory.TrajectoryPoint {
        // Get current signals from various sources
        let nervousSystemState = nervousSystemEngine.currentState
        let emotionClassification = emotionAnalyzer.latestClassification
        let hrvReading = nervousSystemEngine.currentHRV

        // Calculate composite score
        let compositeScore = calculateCompositeScore(
            nervousSystem: nervousSystemState,
            emotion: emotionClassification,
            hrv: hrvReading
        )

        return EmotionalTrajectory.TrajectoryPoint(
            timestamp: Date(),
            secondsFromStart: secondsFromStart,
            nervousSystemState: nervousSystemState,
            emotionClassification: emotionClassification,
            hrvReading: hrvReading,
            compositeScore: compositeScore
        )
    }

    private func calculateCompositeScore(
        nervousSystem: NervousSystemState?,
        emotion: EmotionClassification?,
        hrv: Double?
    ) -> Double {
        var score = 0.0
        var weights = 0.0

        // Nervous system contribution (weight: 0.4)
        if let ns = nervousSystem {
            switch ns {
            case .ventralVagal: score += 0.4 * 1.0
            case .sympathetic: score += 0.4 * 0.0
            case .dorsalVagal: score += 0.4 * -0.5
            default: break
            }
            weights += 0.4
        }

        // Emotion contribution (weight: 0.4)
        if let emotion = emotion {
            let emotionScore = emotionToScore(emotion)
            score += 0.4 * emotionScore
            weights += 0.4
        }

        // HRV contribution (weight: 0.2)
        if let hrv = hrv {
            // Higher HRV = better (normalize to 0-1 range)
            let hrvScore = min(max((hrv - 20) / 80, 0), 1)
            score += 0.2 * hrvScore
            weights += 0.2
        }

        // Normalize to -1 to +1 range
        return weights > 0 ? (score / weights) * 2 - 1 : 0
    }
}
```

### 3.4 Efficacy Score Calculation

```swift
class EfficacyCalculator {
    func calculateEfficacy(trajectory: EmotionalTrajectory, context: InterventionContext) -> InterventionEfficacy {
        // Core metric: Net emotional change
        let netChange = trajectory.netChange

        // Secondary: Was the change sustained?
        let lastQuarterAvg = trajectory.samples.suffix(trajectory.samples.count / 4).map { $0.compositeScore }.average() ?? 0
        let sustained = lastQuarterAvg >= trajectory.endingState - 0.1

        // Tertiary: Was there a breakthrough moment?
        let breakthrough = detectBreakthrough(trajectory)

        // Calculate efficacy score (0-100)
        var efficacyScore = 50.0  // Baseline

        // Net change contribution (up to ±40 points)
        efficacyScore += netChange * 40

        // Sustained improvement bonus (up to +10 points)
        if sustained && netChange > 0 {
            efficacyScore += 10
        }

        // Breakthrough bonus (up to +10 points)
        if breakthrough.detected {
            efficacyScore += 10
        }

        // Starting state penalty (easier to improve from worse state)
        if trajectory.startingState > 0.5 {
            efficacyScore *= 0.9  // 10% penalty for already-good state
        }

        efficacyScore = min(max(efficacyScore, 0), 100)

        return InterventionEfficacy(
            id: UUID(),
            userId: trajectory.userId,
            exerciseId: trajectory.exerciseId,
            sessionId: trajectory.sessionId,
            completedAt: trajectory.endTime,
            efficacyScore: efficacyScore,
            netEmotionalChange: netChange,
            trajectoryShape: trajectory.trajectory,
            breakthroughDetected: breakthrough.detected,
            breakthroughSecond: breakthrough.second,
            startingState: context,
            timeOfDay: determineTimeOfDay(trajectory.startTime),
            dayOfWeek: Calendar.current.component(.weekday, from: trajectory.startTime),
            priorSleepQuality: nil,  // Optional enhancement
            stressLevel: context.stressLevel
        )
    }

    private func detectBreakthrough(_ trajectory: EmotionalTrajectory) -> (detected: Bool, second: Int?) {
        // Breakthrough = rapid positive shift of > 0.4 within 60 seconds
        let samples = trajectory.samples

        for i in 0..<(samples.count - 1) {
            let current = samples[i]
            let next = samples[i + 1]
            let change = next.compositeScore - current.compositeScore

            if change > 0.4 && (next.secondsFromStart - current.secondsFromStart) <= 60 {
                return (true, next.secondsFromStart)
            }
        }

        return (false, nil)
    }
}
```

### 3.5 Profile-Based Recommendations

```swift
class EfficacyBasedRecommender {
    func recommendExercise(
        for userId: String,
        currentState: NervousSystemState,
        currentEmotion: String,
        timeOfDay: InterventionEfficacy.TimeOfDay
    ) async -> [ExerciseRecommendation] {

        // Fetch user's efficacy profiles
        let profiles = await fetchUserProfiles(userId: userId)

        // Score each exercise based on contextual efficacy
        var recommendations: [ExerciseRecommendation] = []

        for profile in profiles {
            let contextualScore = calculateContextualScore(
                profile: profile,
                state: currentState,
                emotion: currentEmotion,
                timeOfDay: timeOfDay
            )

            recommendations.append(ExerciseRecommendation(
                exerciseId: profile.exerciseId,
                exerciseName: profile.exerciseName,
                predictedEfficacy: contextualScore,
                confidence: profile.confidence,
                reason: generateReason(profile: profile, state: currentState, timeOfDay: timeOfDay)
            ))
        }

        // Sort by predicted efficacy
        return recommendations.sorted { $0.predictedEfficacy > $1.predictedEfficacy }
    }

    private func calculateContextualScore(
        profile: UserEfficacyProfile,
        state: NervousSystemState,
        emotion: String,
        timeOfDay: InterventionEfficacy.TimeOfDay
    ) -> Double {
        var score = profile.overallEfficacyScore

        // Adjust for current state match
        if let stateEfficacy = profile.efficacyByState[state] {
            score = (score + stateEfficacy) / 2
        }

        // Adjust for time of day
        if let timeEfficacy = profile.efficacyByTimeOfDay[timeOfDay] {
            score = (score + timeEfficacy) / 2
        }

        // Adjust for emotion
        if let emotionEfficacy = profile.efficacyByEmotion[emotion] {
            score = (score + emotionEfficacy) / 2
        }

        return score
    }
}

struct ExerciseRecommendation {
    let exerciseId: String
    let exerciseName: String
    let predictedEfficacy: Double
    let confidence: Double
    let reason: String  // "Works 73% of the time when you're anxious"
}
```

### 3.6 API Contracts

#### 3.6.1 Get Efficacy Dashboard

```
GET /api/v1/efficacy/dashboard
Authorization: Bearer <jwt>

Response 200:
{
    "topExercises": [
        {
            "exerciseId": "uuid",
            "name": "4-7-8 Breathing",
            "efficacyScore": 82,
            "completions": 23,
            "bestContext": "Works best when anxious, in the evening",
            "trend": "improving"
        }
    ],
    "recentSessions": [
        {
            "exerciseId": "uuid",
            "exerciseName": "Box Breathing",
            "completedAt": "2026-01-22T15:30:00Z",
            "efficacyScore": 78,
            "netChange": 0.45,
            "breakthroughDetected": true
        }
    ],
    "insights": [
        "Breathing exercises work 40% better for you in the evening",
        "You've had 3 breakthrough moments this week"
    ]
}
```

#### 3.6.2 Get Contextual Recommendation

```
GET /api/v1/efficacy/recommend?state=sympathetic&emotion=anxious&timeOfDay=evening
Authorization: Bearer <jwt>

Response 200:
{
    "recommendations": [
        {
            "exerciseId": "uuid",
            "name": "4-7-8 Breathing",
            "predictedEfficacy": 85,
            "confidence": 0.89,
            "reason": "This works 85% of the time when you're anxious in the evening"
        }
    ]
}
```

---

## 4. Implementation Details

### 4.1 Step-by-Step Implementation

1. **Build Trajectory Tracker** (2 days)
   - Integrate with existing exercise player
   - Implement periodic state sampling
   - Store trajectory data

2. **Implement Efficacy Calculator** (2 days)
   - Build scoring algorithm
   - Add breakthrough detection
   - Handle edge cases

3. **Create Profile Aggregator** (2 days)
   - Build daily aggregation job
   - Implement contextual segmentation
   - Add trend calculation

4. **Build Recommendation Engine** (2 days)
   - Implement contextual scoring
   - Add confidence weighting
   - Integrate with exercise selection

5. **Create iOS UI** (3 days)
   - `EfficacyDashboardView`
   - `TrajectoryVisualizationView`
   - `BreakthroughCelebrationView`

6. **Database & Edge Functions** (1 day)
   - Apply migrations
   - Create aggregation Edge Function

---

## 5. Dependencies

### 5.1 Prerequisites

- N001: Nervous System State Engine (provides real-time state)
- Emotion Analyzer (Existing)
- Exercise Sessions (Existing)

---

## 6. Edge Cases and Error Handling

| Edge Case                  | Expected Behavior                                       |
| -------------------------- | ------------------------------------------------------- |
| User quits exercise early  | Calculate partial efficacy; flag as incomplete          |
| No state signal available  | Use emotion-only scoring                                |
| First-time exercise        | No personalized recommendation; use population defaults |
| All exercises low efficacy | Suggest trying new exercise types                       |
| Breakthrough mid-crash     | Still flag breakthrough; note unusual pattern           |

---

## 7. Testing Requirements

### 7.1 Unit Tests

```swift
class InterventionEfficacyTests: XCTestCase {
    func testTrajectoryTracking()
    func testEfficacyScoreCalculation()
    func testBreakthroughDetection()
    func testProfileAggregation()
    func testContextualRecommendation()
}
```

---

## 8. Success Metrics

| Metric                         | Target                        | Measurement     |
| ------------------------------ | ----------------------------- | --------------- |
| Tracking accuracy              | > 90% sessions tracked        | Completion rate |
| Recommendation improvement     | 15% better outcomes vs random | A/B test        |
| User engagement with dashboard | > 40% DAU view                | Analytics       |
| Breakthrough rate increase     | 20% more breakthroughs        | Before/after    |

---

## 9. Competitive Analysis

| App           | Efficacy Feature          | MindFriend Advantage           |
| ------------- | ------------------------- | ------------------------------ |
| Calm          | Post-session rating (1-5) | Real-time trajectory tracking  |
| Headspace     | Completion tracking       | Personalized efficacy profiles |
| Insight Timer | Session length            | Contextual recommendations     |
| Waking Up     | None                      | Breakthrough detection         |

**MindFriend is the first app to track emotional trajectory during interventions for personalized efficacy.**
