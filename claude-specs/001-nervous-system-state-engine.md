# N001: Nervous System State Engine

> **Type:** NOVEL DIFFERENTIATOR
> **Phase:** Foundation
> **Complexity:** High
> **Priority:** P0
> **Dependencies:** F001 (Biometric Correlation Engine) - Already Implemented

---

## 1. Overview

### 1.1 Summary

The Nervous System State Engine provides real-time detection of the user's autonomic nervous system state using Polyvagal Theory as its clinical foundation. By combining voice biomarkers (already captured via EmotionAnalyzer), heart rate variability from HealthKit, and behavioral micro-signals, the system classifies users into one of three nervous system states: **Ventral Vagal** (safe, social), **Sympathetic** (fight/flight), or **Dorsal Vagal** (freeze/shutdown). Based on the detected state, it delivers targeted micro-interventions to guide users back to their "window of tolerance."

### 1.2 Business Value

- **Clinical Differentiation:** No consumer app implements Polyvagal Theory. This positions MindFriend as clinically sophisticated.
- **Real-Time Intervention:** Instead of reactive mood logging, proactively help users regulate in the moment.
- **Measurable Efficacy:** Track whether interventions actually shift nervous system state (proof of value).
- **Therapist Appeal:** Polyvagal language is mainstream in trauma-informed therapy. Therapists will recommend MindFriend.

### 1.3 Scientific Foundation

- **Polyvagal Theory** (Stephen Porges): Three-branch model of autonomic regulation
- **Heart Rate Variability (HRV):** Gold standard for parasympathetic tone measurement
- **Voice Biomarkers:** Vocal prosody correlates with vagal tone (Porges, 2011)
- **Window of Tolerance:** Dan Siegel's model for optimal arousal zone

---

## 2. Requirements

### 2.1 Functional Requirements

| ID     | Requirement                                                                                                              | Priority |
| ------ | ------------------------------------------------------------------------------------------------------------------------ | -------- |
| FR-001 | System SHALL classify user's nervous system state into one of three categories: Ventral Vagal, Sympathetic, Dorsal Vagal | P0       |
| FR-002 | Classification SHALL update in real-time during voice conversations (every 10 seconds)                                   | P0       |
| FR-003 | Classification SHALL use passive background signals when not in active session (every 5 minutes)                         | P0       |
| FR-004 | System SHALL display current state to user via intuitive visual indicator                                                | P0       |
| FR-005 | System SHALL recommend state-specific micro-interventions                                                                | P0       |
| FR-006 | System SHALL track state transitions over time for pattern analysis                                                      | P0       |
| FR-007 | System SHALL detect "state cascades" (rapid deterioration) and escalate intervention intensity                           | P1       |
| FR-008 | System SHALL integrate with existing SmartNotificationService for state-aware notification timing                        | P1       |
| FR-009 | System SHALL provide "state history" visualization showing daily/weekly patterns                                         | P1       |
| FR-010 | System SHALL correlate nervous system states with mood entries for pattern discovery                                     | P2       |

### 2.2 Non-Functional Requirements

| ID      | Requirement                                                        | Target                                         |
| ------- | ------------------------------------------------------------------ | ---------------------------------------------- |
| NFR-001 | Classification latency during voice session                        | < 500ms                                        |
| NFR-002 | Background classification battery impact                           | < 2% per hour                                  |
| NFR-003 | Classification accuracy (validated against clinical HRV standards) | > 75%                                          |
| NFR-004 | On-device processing for privacy                                   | 100% (no cloud transmission of raw biometrics) |
| NFR-005 | Graceful degradation when HRV unavailable                          | Use voice-only model                           |

### 2.3 Acceptance Criteria

1. Given a user in a voice conversation, when their voice patterns indicate anxiety (high pitch, rapid speech, tremor), then the system classifies them as Sympathetic within 10 seconds
2. Given a user with low HRV and monotone voice, when behavioral signals show withdrawal (short responses, long pauses), then the system classifies them as Dorsal Vagal
3. Given a Sympathetic classification, when the system recommends a vagal toning exercise and the user completes it, then the system detects state shift to Ventral Vagal within 2 minutes
4. Given historical state data, when the user views their dashboard, then they see a timeline showing state distribution over the past 7 days

---

## 3. Technical Design

### 3.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    iOS App Layer                                 │
├─────────────────────────────────────────────────────────────────┤
│  NervousSystemStateView   │  StateHistoryView  │ InterventionUI │
├─────────────────────────────────────────────────────────────────┤
│                 NervousSystemViewModel                           │
├─────────────────────────────────────────────────────────────────┤
│              NervousSystemStateEngine (Core ML)                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ VoiceSignal  │  │  HRVSignal   │  │ Behavioral   │          │
│  │  Extractor   │  │  Extractor   │  │  Extractor   │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
├─────────────────────────────────────────────────────────────────┤
│  EmotionAnalyzer │ HealthKitService │ BehaviorTracker          │
│  (existing)      │   (existing)     │    (new)                 │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Data Models

#### 3.2.1 NervousSystemState Enum

```swift
enum NervousSystemState: String, Codable {
    case ventralVagal = "ventral_vagal"    // Safe, social, connected
    case sympathetic = "sympathetic"        // Fight/flight, anxious, activated
    case dorsalVagal = "dorsal_vagal"       // Freeze, shutdown, dissociated
    case transitioning = "transitioning"    // Between states
    case unknown = "unknown"                // Insufficient data
}
```

#### 3.2.2 StateClassification Model

```swift
struct StateClassification: Codable, Identifiable {
    let id: UUID
    let userId: String
    let state: NervousSystemState
    let confidence: Double              // 0.0-1.0
    let timestamp: Date
    let source: ClassificationSource    // .voice, .hrv, .behavioral, .combined

    // Signal contributions (for explainability)
    let voiceScore: Double?             // -1 (dorsal) to +1 (ventral)
    let hrvScore: Double?               // -1 (dorsal) to +1 (ventral)
    let behavioralScore: Double?        // -1 (dorsal) to +1 (ventral)

    // Context
    let sessionId: String?              // If during active session
    let triggerEvent: String?           // What triggered classification
}

enum ClassificationSource: String, Codable {
    case voice
    case hrv
    case behavioral
    case combined
}
```

#### 3.2.3 Database Schema

```sql
-- Nervous system state classifications
CREATE TABLE nervous_system_states (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    state TEXT NOT NULL CHECK (state IN ('ventral_vagal', 'sympathetic', 'dorsal_vagal', 'transitioning', 'unknown')),
    confidence DECIMAL(3,2) NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    source TEXT NOT NULL CHECK (source IN ('voice', 'hrv', 'behavioral', 'combined')),
    voice_score DECIMAL(4,3),
    hrv_score DECIMAL(4,3),
    behavioral_score DECIMAL(4,3),
    session_id UUID REFERENCES conversations(id),
    trigger_event TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for time-series queries
CREATE INDEX idx_nervous_system_states_user_time
    ON nervous_system_states(user_id, created_at DESC);

-- State-specific interventions catalog
CREATE TABLE state_interventions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_state TEXT NOT NULL,  -- The state this intervention addresses
    intervention_type TEXT NOT NULL,  -- 'vagal_tone', 'grounding', 'activation', 'co_regulation'
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    duration_seconds INTEGER NOT NULL,
    audio_url TEXT,
    instructions JSONB NOT NULL,
    efficacy_score DECIMAL(3,2) DEFAULT 0.5,  -- Updated based on user outcomes
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- RLS Policies
ALTER TABLE nervous_system_states ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own states"
    ON nervous_system_states FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own states"
    ON nervous_system_states FOR INSERT
    WITH CHECK (auth.uid() = user_id);
```

### 3.3 Signal Processing Pipeline

#### 3.3.1 Voice Signal Extraction

Extends existing `EmotionAnalyzer` to extract polyvagal-relevant features:

```swift
struct VoicePolyvagalFeatures {
    let pitchVariability: Double      // Low = dorsal, high = sympathetic, moderate = ventral
    let speechRate: Double            // Words per minute
    let pauseDuration: Double         // Average pause between utterances
    let volumeVariability: Double     // Monotone = dorsal
    let voiceTremor: Double           // Sympathetic activation indicator
    let prosodyContour: [Double]      // Melodic variation (ventral indicator)
}
```

#### 3.3.2 HRV Signal Extraction

```swift
struct HRVPolyvagalFeatures {
    let rmssd: Double                 // Root mean square of successive differences
    let sdnn: Double                  // Standard deviation of NN intervals
    let lfHfRatio: Double             // Low freq / high freq power ratio
    let respiratorySinusArrhythmia: Double  // RSA - direct vagal tone measure
}
```

#### 3.3.3 Behavioral Signal Extraction

```swift
struct BehavioralPolyvagalFeatures {
    let responseLatency: Double       // Time to respond in chat (slow = dorsal)
    let messageLength: Double         // Short = dorsal, moderate = ventral
    let sessionDuration: Double       // Engagement level
    let featureExploration: Double    // Curiosity = ventral
    let socialEngagement: Double      // Circle activity (social = ventral)
}
```

### 3.4 Classification Algorithm

```swift
class NervousSystemClassifier {
    // Weighted fusion of three signal sources
    func classify(
        voice: VoicePolyvagalFeatures?,
        hrv: HRVPolyvagalFeatures?,
        behavioral: BehavioralPolyvagalFeatures?
    ) -> StateClassification {

        // Convert each signal source to state scores
        let voiceScore = voice.map { calculateVoiceScore($0) }
        let hrvScore = hrv.map { calculateHRVScore($0) }
        let behavioralScore = behavioral.map { calculateBehavioralScore($0) }

        // Weighted combination (HRV most reliable, then voice, then behavioral)
        let weights = (hrv: 0.5, voice: 0.35, behavioral: 0.15)

        // Calculate composite score: -1 (dorsal) to +1 (ventral)
        // 0 = sympathetic
        let compositeScore = weightedAverage(
            scores: [voiceScore, hrvScore, behavioralScore],
            weights: [weights.voice, weights.hrv, weights.behavioral]
        )

        // Map to discrete state
        let state: NervousSystemState
        let confidence: Double

        switch compositeScore {
        case 0.4...1.0:
            state = .ventralVagal
            confidence = min((compositeScore - 0.4) / 0.6 + 0.6, 1.0)
        case -0.3..<0.4:
            state = .sympathetic
            confidence = 0.7 - abs(compositeScore) * 0.3
        case -1.0..<(-0.3):
            state = .dorsalVagal
            confidence = min((abs(compositeScore) - 0.3) / 0.7 + 0.6, 1.0)
        default:
            state = .unknown
            confidence = 0.3
        }

        return StateClassification(
            id: UUID(),
            userId: currentUserId,
            state: state,
            confidence: confidence,
            timestamp: Date(),
            source: determineSource(voice, hrv, behavioral),
            voiceScore: voiceScore,
            hrvScore: hrvScore,
            behavioralScore: behavioralScore,
            sessionId: activeSessionId,
            triggerEvent: nil
        )
    }
}
```

### 3.5 State-Specific Interventions

| State         | Intervention Type | Examples                                                      | Duration |
| ------------- | ----------------- | ------------------------------------------------------------- | -------- |
| Sympathetic   | Vagal Toning      | Slow exhale breathing, cold water on face, humming            | 2-5 min  |
| Sympathetic   | Discharge         | Shaking, pushing against wall, vocalization                   | 1-3 min  |
| Dorsal Vagal  | Gentle Activation | Orienting exercise, name 5 things you see, gentle movement    | 2-4 min  |
| Dorsal Vagal  | Co-Regulation     | Soothing voice audio, pet interaction, trusted person contact | 3-5 min  |
| Ventral Vagal | Maintenance       | Gratitude practice, social connection, play                   | 2-3 min  |

### 3.6 API Contracts

#### 3.6.1 Get Current State

```
GET /api/v1/nervous-system/current
Authorization: Bearer <jwt>

Response 200:
{
    "state": "sympathetic",
    "confidence": 0.82,
    "since": "2026-01-22T14:30:00Z",
    "signals": {
        "voice": -0.3,
        "hrv": -0.4,
        "behavioral": -0.1
    },
    "recommendedIntervention": {
        "id": "uuid",
        "name": "4-7-8 Breathing",
        "type": "vagal_toning",
        "duration": 180
    }
}
```

#### 3.6.2 Log State Classification

```
POST /api/v1/nervous-system/classify
Authorization: Bearer <jwt>
Content-Type: application/json

{
    "voiceFeatures": { ... },
    "hrvFeatures": { ... },
    "behavioralFeatures": { ... },
    "sessionId": "uuid"
}

Response 201:
{
    "classification": { ... },
    "stateChange": {
        "previous": "sympathetic",
        "current": "ventralVagal",
        "transitionDuration": 240
    }
}
```

---

## 4. Implementation Details

### 4.1 Step-by-Step Implementation

1. **Extend EmotionAnalyzer** (2 days)
   - Add polyvagal feature extraction to existing audio processing
   - Extract pitch variability, speech rate, prosody contour
   - Output `VoicePolyvagalFeatures` alongside emotion classification

2. **Create HRV Processor** (2 days)
   - Integrate with existing HealthKitService
   - Request HRV data (requires Apple Watch)
   - Calculate RMSSD, SDNN, LF/HF ratio
   - Handle graceful degradation when no HRV available

3. **Create Behavioral Tracker** (1 day)
   - Track response latency in chat
   - Track session engagement metrics
   - Track social interaction frequency

4. **Build Classification Engine** (3 days)
   - Implement weighted fusion algorithm
   - Train/validate against labeled data
   - Create Core ML model for on-device inference

5. **Create Database Schema** (1 day)
   - Apply migrations
   - Set up RLS policies
   - Seed intervention catalog

6. **Build iOS UI Components** (3 days)
   - `NervousSystemIndicatorView` - Current state display
   - `StateHistoryChart` - Timeline visualization
   - `InterventionRecommendationCard` - Suggested exercises

7. **Integration & Testing** (2 days)
   - Connect to existing chat flow
   - Add to home dashboard
   - Write unit and integration tests

### 4.2 File Structure

```
MindFriendApp/
├── Core/
│   ├── Services/
│   │   ├── NervousSystemStateEngine.swift      # Main classification engine
│   │   ├── VoicePolyvagalExtractor.swift       # Voice feature extraction
│   │   ├── HRVPolyvagalExtractor.swift         # HRV feature extraction
│   │   └── BehavioralPolyvagalTracker.swift    # Behavioral signal tracking
│   └── Models/
│       └── NervousSystemModels.swift           # State, Classification types
├── Features/
│   └── NervousSystem/
│       ├── NervousSystemIndicatorView.swift    # State indicator widget
│       ├── StateHistoryView.swift              # Historical visualization
│       ├── InterventionView.swift              # Intervention player
│       └── NervousSystemViewModel.swift        # View model
└── Resources/
    └── CoreML/
        └── PolyvagalClassifier.mlmodel         # On-device ML model
```

### 4.3 Configuration

```swift
struct NervousSystemConfig {
    static let classificationIntervalActive: TimeInterval = 10      // During voice session
    static let classificationIntervalPassive: TimeInterval = 300    // Background (5 min)
    static let minimumConfidenceThreshold: Double = 0.6
    static let stateChangeDebounce: TimeInterval = 30               // Prevent rapid toggling
    static let hrvWindowDuration: TimeInterval = 120                // 2 min HRV window
}
```

---

## 5. Dependencies

### 5.1 Prerequisites

- F001: Biometric Correlation Engine (Already Implemented) - Provides HealthKit integration
- EmotionAnalyzer service (Existing) - Provides voice processing foundation
- Apple Watch paired (Optional) - For HRV data

### 5.2 External Libraries

- Accelerate framework (Apple) - Signal processing
- HealthKit (Apple) - HRV data access
- Core ML (Apple) - On-device inference

### 5.3 Internal Modules

- `EmotionAnalyzer` - Extend for polyvagal features
- `HealthKitService` - Add HRV queries
- `SmartNotificationService` - State-aware notification timing

---

## 6. Edge Cases and Error Handling

| Edge Case                                 | Expected Behavior                                             |
| ----------------------------------------- | ------------------------------------------------------------- |
| No HRV data (no Apple Watch)              | Use voice + behavioral signals only; reduce confidence by 20% |
| User not speaking (text-only chat)        | Use HRV + behavioral only; classify less frequently           |
| Rapid state fluctuation                   | Apply 30-second debounce; show "transitioning" state          |
| Classification confidence < 60%           | Show "unknown" state; suggest calibration session             |
| User in crisis (dorsal + crisis keywords) | Bypass normal flow; escalate to crisis resources              |
| First-time user (no baseline)             | Run 5-minute calibration session; explain polyvagal states    |

---

## 7. Testing Requirements

### 7.1 Unit Tests

```swift
class NervousSystemStateEngineTests: XCTestCase {
    func testClassifiesSympatheticFromHighPitchRapidSpeech()
    func testClassifiesDorsalFromMonotoneLowEnergy()
    func testClassifiesVentralFromModerateProsody()
    func testHRVWeightingIncreasesConfidence()
    func testGracefulDegradationWithoutHRV()
    func testStateChangeDebouncing()
    func testInterventionRecommendationMatchesState()
}
```

### 7.2 Integration Tests

```swift
class NervousSystemIntegrationTests: XCTestCase {
    func testRealTimeClassificationDuringVoiceSession()
    func testStateHistoryPersistence()
    func testInterventionEfficacyTracking()
    func testNotificationTimingRespectsState()
}
```

### 7.3 Test Data

- Audio samples for each state (from RAVDESS or recorded)
- Synthetic HRV sequences (high/low variability)
- Behavioral session logs (engaged vs withdrawn)

---

## 8. Success Metrics

| Metric                             | Target                               | Measurement                               |
| ---------------------------------- | ------------------------------------ | ----------------------------------------- |
| Classification accuracy            | > 75%                                | User feedback on state correctness        |
| Intervention efficacy              | > 60% show state improvement         | State change within 5 min of intervention |
| User engagement with state feature | > 40% daily active users check state | Analytics                                 |
| Therapist referral rate            | 10% increase                         | Attribution tracking                      |

---

## 9. Competitive Analysis

| App       | Polyvagal Feature   | MindFriend Advantage                           |
| --------- | ------------------- | ---------------------------------------------- |
| Calm      | None                | First-mover in consumer polyvagal              |
| Headspace | None                | Clinical credibility                           |
| Woebot    | Mood tracking only  | Real-time physiological integration            |
| Finch     | Emotional check-ins | Multi-signal fusion (voice + HRV + behavioral) |

**MindFriend is the first consumer app to implement Polyvagal Theory with multi-modal sensing.**
