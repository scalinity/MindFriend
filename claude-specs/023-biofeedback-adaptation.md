# F024: Biofeedback Adaptation

## Overview

### Summary

Real-time physiological adaptation system that uses heart rate, HRV, and other biometric signals from Apple Watch and HealthKit to dynamically adjust exercise pacing, breathing guidance, and intervention intensity based on the user's actual physiological state.

### Business Value

- Creates highly personalized, responsive wellness experiences
- Increases exercise effectiveness through real-time optimization
- Demonstrates advanced health technology integration
- Strong Apple Watch engagement drives premium conversions

### User Benefit

- Exercises that actually respond to your body's signals
- More effective stress reduction through real-time calibration
- Visible proof that wellness practices are working
- Personalized pacing that matches individual physiology

### Dependencies

- F001 (Biometric Correlation Engine) - Biometric data infrastructure
- F012 (Sleep Optimization) - Uses similar HealthKit patterns
- Core Exercise System - Exercise delivery framework

---

## Requirements

### Functional Requirements

| ID        | Requirement                                                 | Priority |
| --------- | ----------------------------------------------------------- | -------- |
| FR-024-01 | Read real-time heart rate from Apple Watch during exercises | P0       |
| FR-024-02 | Adjust breathing exercise pace based on current HRV         | P0       |
| FR-024-03 | Provide visual feedback of physiological state              | P0       |
| FR-024-04 | Alert when relaxation threshold is achieved                 | P0       |
| FR-024-05 | Track physiological changes throughout exercise session     | P1       |
| FR-024-06 | Adapt meditation guidance based on heart rate trends        | P1       |
| FR-024-07 | Extend exercises automatically if stress remains high       | P1       |
| FR-024-08 | Show post-exercise biometric summary                        | P2       |
| FR-024-09 | Learn individual baseline and response patterns             | P2       |
| FR-024-10 | Support manual override of adaptive features                | P2       |

### Non-Functional Requirements

| ID         | Requirement                          | Target                  |
| ---------- | ------------------------------------ | ----------------------- |
| NFR-024-01 | Heart rate update latency from Watch | < 1 second              |
| NFR-024-02 | Adaptation response time             | < 2 seconds             |
| NFR-024-03 | Battery impact on Apple Watch        | < 5% per 10-min session |
| NFR-024-04 | Data privacy compliance              | HIPAA-aligned           |
| NFR-024-05 | Graceful degradation without Watch   | Required                |
| NFR-024-06 | Baseline calculation accuracy        | ±5 BPM                  |

### Acceptance Criteria (Gherkin)

```gherkin
Feature: Biofeedback Adaptation

  Scenario: Breathing pace adapts to HRV
    Given the user starts a breathing exercise
    And their Apple Watch is connected
    When the system reads their current HRV
    Then the breathing pace is set based on their stress level
    And a faster pace is used if HRV indicates high stress
    And the pace slows as their HRV improves

  Scenario: Visual heart rate feedback during meditation
    Given the user is in a meditation session
    And biofeedback mode is enabled
    When their heart rate changes
    Then the visual display updates in real-time
    And shows heart rate trend direction
    And color indicates relative stress level

  Scenario: Exercise extends when stress remains high
    Given the user is completing a relaxation exercise
    And their heart rate remains elevated
    When the planned exercise duration ends
    Then the system offers to extend the session
    And explains that more time may help
    And tracks the extended session separately

  Scenario: Post-exercise biometric summary
    Given the user completes a biofeedback-enabled exercise
    When the summary screen displays
    Then they see starting vs ending heart rate
    And HRV change during the session
    And time to reach relaxation threshold
    And comparison to their personal baseline
```

---

## Technical Design

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Biofeedback Adaptation Layer                  │
├─────────────────────────────────────────────────────────────────┤
│  ┌────────────────┐  ┌─────────────────┐  ┌──────────────────┐  │
│  │ Exercise       │  │ Biometric       │  │ Adaptation       │  │
│  │ Controller     │  │ Monitor         │  │ Engine           │  │
│  └───────┬────────┘  └────────┬────────┘  └────────┬─────────┘  │
│          │                    │                    │            │
│  ┌───────▼────────────────────▼────────────────────▼──────────┐ │
│  │               Biofeedback Coordinator                       │ │
│  └────────────────────────────┬────────────────────────────────┘ │
├───────────────────────────────┼─────────────────────────────────┤
│                               │                                 │
│  ┌────────────────────────────▼────────────────────────────────┐ │
│  │                   HealthKit Integration                      │ │
│  │  ┌──────────────┐ ┌──────────────┐ ┌────────────────────┐   │ │
│  │  │ Heart Rate   │ │ HRV          │ │ Workout Session    │   │ │
│  │  │ Stream       │ │ Calculator   │ │ Manager            │   │ │
│  │  └──────────────┘ └──────────────┘ └────────────────────┘   │ │
│  └─────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    WatchConnectivity                         │ │
│  │  • Real-time HR transfer  • HRV calculation  • Workout sync │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘

    ┌─────────────────────────────────────────────────────────┐
    │                    Apple Watch                          │
    │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
    │  │ Heart Rate   │  │ Workout      │  │ HealthKit    │  │
    │  │ Sensor       │  │ Session      │  │ Store        │  │
    │  └──────────────┘  └──────────────┘  └──────────────┘  │
    └─────────────────────────────────────────────────────────┘
```

### Database Schema

```sql
-- User's physiological baseline data
CREATE TABLE biometric_baselines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    resting_heart_rate DECIMAL(5,2),
    resting_hrv DECIMAL(6,2),
    exercise_recovery_rate DECIMAL(5,2),  -- BPM decrease per minute
    stress_hr_threshold DECIMAL(5,2),
    relaxed_hr_threshold DECIMAL(5,2),
    calculated_at TIMESTAMPTZ DEFAULT NOW(),
    sample_count INTEGER DEFAULT 0,
    confidence_score DECIMAL(3,2) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

-- Biofeedback exercise sessions
CREATE TABLE biofeedback_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    exercise_session_id UUID REFERENCES exercise_sessions(id),
    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    duration_seconds INTEGER,
    was_extended BOOLEAN DEFAULT FALSE,
    extension_seconds INTEGER DEFAULT 0,
    adaptation_mode TEXT DEFAULT 'auto' CHECK (adaptation_mode IN ('auto', 'gentle', 'aggressive', 'off')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Real-time biometric readings during session
CREATE TABLE biofeedback_readings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES biofeedback_sessions(id) ON DELETE CASCADE,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    heart_rate DECIMAL(5,2) NOT NULL,
    hrv_sdnn DECIMAL(6,2),
    hrv_rmssd DECIMAL(6,2),
    relative_stress_level DECIMAL(3,2),  -- 0-1 normalized
    adaptation_applied JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Adaptations made during session
CREATE TABLE biofeedback_adaptations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES biofeedback_sessions(id) ON DELETE CASCADE,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    adaptation_type TEXT NOT NULL CHECK (adaptation_type IN (
        'breathing_pace', 'exercise_extension', 'intensity_reduction',
        'guidance_frequency', 'visual_feedback', 'audio_tempo'
    )),
    previous_value JSONB,
    new_value JSONB,
    trigger_reason TEXT,
    biometric_trigger JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Session summary metrics
CREATE TABLE biofeedback_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES biofeedback_sessions(id) ON DELETE CASCADE,
    starting_heart_rate DECIMAL(5,2),
    ending_heart_rate DECIMAL(5,2),
    lowest_heart_rate DECIMAL(5,2),
    highest_heart_rate DECIMAL(5,2),
    average_heart_rate DECIMAL(5,2),
    starting_hrv DECIMAL(6,2),
    ending_hrv DECIMAL(6,2),
    hrv_improvement_percent DECIMAL(5,2),
    time_to_relaxation_seconds INTEGER,
    total_adaptations INTEGER DEFAULT 0,
    effectiveness_score DECIMAL(3,2),
    comparison_to_baseline JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE biometric_baselines ENABLE ROW LEVEL SECURITY;
ALTER TABLE biofeedback_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE biofeedback_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE biofeedback_adaptations ENABLE ROW LEVEL SECURITY;
ALTER TABLE biofeedback_summaries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own baselines"
    ON biometric_baselines FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users manage own biofeedback sessions"
    ON biofeedback_sessions FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users access own readings"
    ON biofeedback_readings FOR ALL
    USING (session_id IN (
        SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid()
    ));

CREATE POLICY "Users access own adaptations"
    ON biofeedback_adaptations FOR ALL
    USING (session_id IN (
        SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid()
    ));

CREATE POLICY "Users access own summaries"
    ON biofeedback_summaries FOR ALL
    USING (session_id IN (
        SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid()
    ));

-- Indexes
CREATE INDEX idx_biofeedback_sessions_user ON biofeedback_sessions(user_id);
CREATE INDEX idx_biofeedback_readings_session ON biofeedback_readings(session_id);
CREATE INDEX idx_biofeedback_readings_timestamp ON biofeedback_readings(session_id, timestamp);
```

### Swift Models

```swift
import Foundation
import HealthKit

// MARK: - Baseline Models

struct BiometricBaseline: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var restingHeartRate: Double?
    var restingHRV: Double?
    var exerciseRecoveryRate: Double?
    var stressHRThreshold: Double?
    var relaxedHRThreshold: Double?
    let calculatedAt: Date
    var sampleCount: Int
    var confidenceScore: Double
    let createdAt: Date
    var updatedAt: Date

    var isReliable: Bool {
        confidenceScore >= 0.7 && sampleCount >= 10
    }

    func stressLevel(forHeartRate hr: Double) -> StressLevel {
        guard let resting = restingHeartRate,
              let stress = stressHRThreshold else {
            return .unknown
        }

        let range = stress - resting
        let current = hr - resting
        let ratio = current / range

        if ratio <= 0.2 { return .relaxed }
        if ratio <= 0.5 { return .calm }
        if ratio <= 0.75 { return .moderate }
        if ratio <= 1.0 { return .elevated }
        return .high
    }

    enum StressLevel: String, Codable {
        case relaxed, calm, moderate, elevated, high, unknown

        var color: String {
            switch self {
            case .relaxed: return "green"
            case .calm: return "teal"
            case .moderate: return "yellow"
            case .elevated: return "orange"
            case .high: return "red"
            case .unknown: return "gray"
            }
        }
    }
}

// MARK: - Session Models

struct BiofeedbackSession: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let exerciseSessionId: UUID?
    let startedAt: Date
    var completedAt: Date?
    var durationSeconds: Int?
    var wasExtended: Bool
    var extensionSeconds: Int
    let adaptationMode: AdaptationMode
    let createdAt: Date

    enum AdaptationMode: String, Codable {
        case auto, gentle, aggressive, off
    }
}

struct BiofeedbackReading: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let timestamp: Date
    let heartRate: Double
    let hrvSdnn: Double?
    let hrvRmssd: Double?
    let relativeStressLevel: Double?
    let adaptationApplied: [String: AnyCodable]?
    let createdAt: Date
}

struct BiofeedbackAdaptation: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let timestamp: Date
    let adaptationType: AdaptationType
    let previousValue: [String: AnyCodable]?
    let newValue: [String: AnyCodable]?
    let triggerReason: String?
    let biometricTrigger: [String: AnyCodable]?
    let createdAt: Date

    enum AdaptationType: String, Codable {
        case breathingPace = "breathing_pace"
        case exerciseExtension = "exercise_extension"
        case intensityReduction = "intensity_reduction"
        case guidanceFrequency = "guidance_frequency"
        case visualFeedback = "visual_feedback"
        case audioTempo = "audio_tempo"
    }
}

// MARK: - Summary Models

struct BiofeedbackSummary: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let startingHeartRate: Double
    let endingHeartRate: Double
    let lowestHeartRate: Double
    let highestHeartRate: Double
    let averageHeartRate: Double
    let startingHRV: Double?
    let endingHRV: Double?
    let hrvImprovementPercent: Double?
    let timeToRelaxationSeconds: Int?
    let totalAdaptations: Int
    let effectivenessScore: Double?
    let comparisonToBaseline: BaselineComparison?
    let createdAt: Date
}

struct BaselineComparison: Codable {
    let heartRateVsBaseline: Double  // Percentage difference
    let hrvVsBaseline: Double?
    let recoveryRateVsBaseline: Double?
    let performanceTrend: PerformanceTrend

    enum PerformanceTrend: String, Codable {
        case improving, stable, declining
    }
}

// MARK: - Real-time Data

struct LiveBiometricData {
    let heartRate: Double
    let hrvRMSSD: Double?
    let timestamp: Date

    var isValid: Bool {
        heartRate > 30 && heartRate < 220
    }
}

// MARK: - Adaptation Parameters

struct AdaptationParameters: Codable {
    var breathingInhaleSeconds: Double
    var breathingHoldSeconds: Double
    var breathingExhaleSeconds: Double
    var breathingPauseSeconds: Double
    var guidanceVerbosity: GuidanceVerbosity
    var visualIntensity: Double  // 0-1
    var audioTempo: Double       // BPM

    enum GuidanceVerbosity: String, Codable {
        case minimal, moderate, detailed
    }

    static var `default`: AdaptationParameters {
        AdaptationParameters(
            breathingInhaleSeconds: 4,
            breathingHoldSeconds: 4,
            breathingExhaleSeconds: 4,
            breathingPauseSeconds: 2,
            guidanceVerbosity: .moderate,
            visualIntensity: 0.7,
            audioTempo: 60
        )
    }
}
```

### API Contracts

```typescript
// REST API endpoints
// GET /rest/v1/biometric_baselines?user_id=eq.{userId}
// Response: BiometricBaseline

// POST /rest/v1/biofeedback_sessions
interface CreateBiofeedbackSessionRequest {
  user_id: string;
  exercise_session_id?: string;
  adaptation_mode: "auto" | "gentle" | "aggressive" | "off";
}

// POST /rest/v1/biofeedback_readings
interface CreateReadingRequest {
  session_id: string;
  heart_rate: number;
  hrv_sdnn?: number;
  hrv_rmssd?: number;
  relative_stress_level?: number;
  adaptation_applied?: Record<string, any>;
}

// POST /rest/v1/biofeedback_adaptations
interface CreateAdaptationRequest {
  session_id: string;
  adaptation_type: string;
  previous_value?: Record<string, any>;
  new_value: Record<string, any>;
  trigger_reason: string;
  biometric_trigger?: Record<string, any>;
}

// Edge Function: calculate-baseline
// POST /functions/v1/calculate-baseline
interface CalculateBaselineRequest {
  lookback_days?: number; // Default 14
}

interface CalculateBaselineResponse {
  baseline: {
    resting_heart_rate: number;
    resting_hrv: number;
    exercise_recovery_rate: number;
    stress_hr_threshold: number;
    relaxed_hr_threshold: number;
    confidence_score: number;
    sample_count: number;
  };
}
```

---

## Implementation Details

### Step-by-Step Approach

1. **Phase 1: HealthKit Integration** (Week 1)
   - Set up real-time heart rate streaming from Watch
   - Implement HRV calculation from RR intervals
   - Create workout session management
   - Build baseline calculation system

2. **Phase 2: Adaptation Engine** (Week 2)
   - Create adaptation rule engine
   - Implement breathing pace calculator
   - Build real-time feedback system
   - Add extension logic for incomplete relaxation

3. **Phase 3: Visual Feedback** (Week 3)
   - Design heart rate visualization component
   - Create stress level indicator
   - Build trend direction arrows
   - Implement color-coded feedback

4. **Phase 4: Exercise Integration** (Week 4)
   - Integrate with breathing exercises
   - Add meditation adaptations
   - Create biofeedback-aware grounding exercises
   - Build post-exercise summary view

5. **Phase 5: Learning & Optimization** (Week 5)
   - Implement baseline learning over time
   - Add effectiveness tracking
   - Create personalization engine
   - Performance testing and optimization

### File Structure

```
apps/ios/MindFriendApp/Features/Biofeedback/
├── BiofeedbackView.swift
├── BiofeedbackViewModel.swift
├── Components/
│   ├── HeartRateGaugeView.swift
│   ├── HRVIndicatorView.swift
│   ├── StressLevelBadge.swift
│   ├── BiometricTrendView.swift
│   └── AdaptationIndicator.swift
├── Models/
│   └── BiofeedbackModels.swift
├── Engine/
│   ├── BiofeedbackCoordinator.swift
│   ├── AdaptationEngine.swift
│   ├── BaselineCalculator.swift
│   └── AdaptationRules.swift
├── HealthKit/
│   ├── HeartRateMonitor.swift
│   ├── HRVCalculator.swift
│   └── WorkoutSessionManager.swift
├── Services/
│   └── BiofeedbackService.swift
└── Summary/
    ├── SessionSummaryView.swift
    └── TrendComparisonView.swift

apps/watchos/MindFriendWatch/
├── HeartRateStreamer.swift
├── WorkoutManager.swift
└── BiofeedbackExtension.swift
```

### Key Algorithms

#### Heart Rate Monitor

```swift
import HealthKit
import Combine

@MainActor
final class HeartRateMonitor: ObservableObject {
    @Published var currentHeartRate: Double?
    @Published var heartRateTrend: Trend = .stable
    @Published var isMonitoring = false

    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var workoutSession: HKWorkoutSession?
    private var recentReadings: [Double] = []
    private let maxReadingsForTrend = 10

    enum Trend {
        case increasing, decreasing, stable

        var icon: String {
            switch self {
            case .increasing: return "arrow.up"
            case .decreasing: return "arrow.down"
            case .stable: return "minus"
            }
        }
    }

    func startMonitoring() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw BiofeedbackError.healthKitUnavailable
        }

        // Request authorization
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!

        try await healthStore.requestAuthorization(
            toShare: [HKWorkoutType.workoutType()],
            read: [heartRateType, hrvType]
        )

        // Start workout session for continuous heart rate
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .mindAndBody
        configuration.locationType = .indoor

        workoutSession = try HKWorkoutSession(
            healthStore: healthStore,
            configuration: configuration
        )

        workoutSession?.startActivity(with: Date())

        // Start heart rate query
        startHeartRateQuery()
        isMonitoring = true
    }

    private func startHeartRateQuery() {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: nil,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.processHeartRateSamples(samples as? [HKQuantitySample])
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.processHeartRateSamples(samples as? [HKQuantitySample])
        }

        healthStore.execute(query)
        heartRateQuery = query
    }

    private func processHeartRateSamples(_ samples: [HKQuantitySample]?) {
        guard let samples = samples, !samples.isEmpty else { return }

        let latestSample = samples
            .sorted { $0.endDate > $1.endDate }
            .first!

        let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
        let bpm = latestSample.quantity.doubleValue(for: heartRateUnit)

        Task { @MainActor in
            self.currentHeartRate = bpm
            self.updateTrend(with: bpm)
        }
    }

    private func updateTrend(with newReading: Double) {
        recentReadings.append(newReading)
        if recentReadings.count > maxReadingsForTrend {
            recentReadings.removeFirst()
        }

        guard recentReadings.count >= 3 else {
            heartRateTrend = .stable
            return
        }

        // Calculate trend using simple linear regression
        let n = Double(recentReadings.count)
        let sumX = (0..<recentReadings.count).reduce(0.0) { $0 + Double($1) }
        let sumY = recentReadings.reduce(0, +)
        let sumXY = recentReadings.enumerated().reduce(0.0) { $0 + Double($1.offset) * $1.element }
        let sumX2 = (0..<recentReadings.count).reduce(0.0) { $0 + pow(Double($1), 2) }

        let slope = (n * sumXY - sumX * sumY) / (n * sumX2 - pow(sumX, 2))

        if slope > 1 {
            heartRateTrend = .increasing
        } else if slope < -1 {
            heartRateTrend = .decreasing
        } else {
            heartRateTrend = .stable
        }
    }

    func stopMonitoring() {
        heartRateQuery?.stop()
        heartRateQuery = nil
        workoutSession?.end()
        workoutSession = nil
        isMonitoring = false
        recentReadings.removeAll()
    }
}

enum BiofeedbackError: Error {
    case healthKitUnavailable
    case authorizationDenied
    case noHeartRateData
    case watchNotConnected
}
```

#### Adaptation Engine

```swift
import Foundation
import Combine

@MainActor
final class AdaptationEngine: ObservableObject {
    @Published var currentParameters: AdaptationParameters = .default
    @Published var adaptationsApplied: [BiofeedbackAdaptation.AdaptationType] = []

    private let baseline: BiometricBaseline
    private let mode: BiofeedbackSession.AdaptationMode
    private var lastAdaptationTime: Date?
    private let minimumAdaptationInterval: TimeInterval = 15  // seconds

    init(baseline: BiometricBaseline, mode: BiofeedbackSession.AdaptationMode) {
        self.baseline = baseline
        self.mode = mode
    }

    func processReading(_ reading: LiveBiometricData) -> AdaptationResult {
        guard mode != .off else {
            return AdaptationResult(adapted: false, parameters: currentParameters)
        }

        // Check if enough time has passed since last adaptation
        if let lastTime = lastAdaptationTime,
           Date().timeIntervalSince(lastTime) < minimumAdaptationInterval {
            return AdaptationResult(adapted: false, parameters: currentParameters)
        }

        let stressLevel = baseline.stressLevel(forHeartRate: reading.heartRate)
        var adaptations: [AdaptationChange] = []

        // Breathing pace adaptation
        if shouldAdaptBreathingPace(stressLevel: stressLevel) {
            let newPace = calculateBreathingPace(
                currentHR: reading.heartRate,
                hrv: reading.hrvRMSSD,
                stressLevel: stressLevel
            )
            if newPace != currentParameters.breathingPattern {
                adaptations.append(.breathingPace(old: currentParameters.breathingPattern, new: newPace))
                currentParameters.breathingInhaleSeconds = newPace.inhale
                currentParameters.breathingHoldSeconds = newPace.hold
                currentParameters.breathingExhaleSeconds = newPace.exhale
                currentParameters.breathingPauseSeconds = newPace.pause
            }
        }

        // Visual intensity adaptation
        if shouldAdaptVisuals(stressLevel: stressLevel) {
            let newIntensity = calculateVisualIntensity(stressLevel: stressLevel)
            if abs(newIntensity - currentParameters.visualIntensity) > 0.1 {
                adaptations.append(.visualIntensity(old: currentParameters.visualIntensity, new: newIntensity))
                currentParameters.visualIntensity = newIntensity
            }
        }

        // Guidance verbosity adaptation
        if shouldAdaptGuidance(stressLevel: stressLevel, hrv: reading.hrvRMSSD) {
            let newVerbosity = calculateGuidanceVerbosity(stressLevel: stressLevel)
            if newVerbosity != currentParameters.guidanceVerbosity {
                adaptations.append(.guidanceVerbosity(old: currentParameters.guidanceVerbosity, new: newVerbosity))
                currentParameters.guidanceVerbosity = newVerbosity
            }
        }

        if !adaptations.isEmpty {
            lastAdaptationTime = Date()
            adaptationsApplied.append(contentsOf: adaptations.map { $0.type })
        }

        return AdaptationResult(
            adapted: !adaptations.isEmpty,
            parameters: currentParameters,
            changes: adaptations
        )
    }

    private func calculateBreathingPace(
        currentHR: Double,
        hrv: Double?,
        stressLevel: BiometricBaseline.StressLevel
    ) -> BreathingPattern {

        // Higher stress = faster, shallower breaths initially, then gradually slow
        switch stressLevel {
        case .high, .elevated:
            // Start with shorter cycles, emphasis on exhale for calming
            return BreathingPattern(inhale: 3, hold: 2, exhale: 5, pause: 1)
        case .moderate:
            // Balanced 4-4-4-2 pattern
            return BreathingPattern(inhale: 4, hold: 4, exhale: 4, pause: 2)
        case .calm:
            // Slower, deeper breaths
            return BreathingPattern(inhale: 4, hold: 6, exhale: 6, pause: 2)
        case .relaxed:
            // Deep, slow breaths
            return BreathingPattern(inhale: 5, hold: 7, exhale: 8, pause: 3)
        case .unknown:
            return BreathingPattern(inhale: 4, hold: 4, exhale: 4, pause: 2)
        }
    }

    private func calculateVisualIntensity(stressLevel: BiometricBaseline.StressLevel) -> Double {
        switch stressLevel {
        case .high: return 0.4      // Dimmer, calmer
        case .elevated: return 0.5
        case .moderate: return 0.6
        case .calm: return 0.7
        case .relaxed: return 0.8   // Can handle more intensity
        case .unknown: return 0.6
        }
    }

    private func calculateGuidanceVerbosity(stressLevel: BiometricBaseline.StressLevel) -> AdaptationParameters.GuidanceVerbosity {
        // Higher stress = more guidance to help focus
        switch stressLevel {
        case .high, .elevated: return .detailed
        case .moderate: return .moderate
        case .calm, .relaxed: return .minimal
        case .unknown: return .moderate
        }
    }

    private func shouldAdaptBreathingPace(stressLevel: BiometricBaseline.StressLevel) -> Bool {
        switch mode {
        case .aggressive: return true
        case .auto: return stressLevel != .calm && stressLevel != .unknown
        case .gentle: return stressLevel == .high || stressLevel == .elevated
        case .off: return false
        }
    }

    private func shouldAdaptVisuals(stressLevel: BiometricBaseline.StressLevel) -> Bool {
        mode == .aggressive || mode == .auto
    }

    private func shouldAdaptGuidance(stressLevel: BiometricBaseline.StressLevel, hrv: Double?) -> Bool {
        mode == .aggressive || (mode == .auto && (stressLevel == .high || stressLevel == .elevated))
    }

    func checkShouldExtend(averageHR: Double, targetHR: Double, elapsedTime: TimeInterval) -> ExtensionRecommendation {
        guard elapsedTime >= 180 else {  // Minimum 3 minutes before considering extension
            return .notNeeded
        }

        let hrDelta = averageHR - targetHR
        let stressLevel = baseline.stressLevel(forHeartRate: averageHR)

        if stressLevel == .relaxed || stressLevel == .calm {
            return .notNeeded
        }

        if hrDelta > 15 {
            return .recommended(additionalSeconds: 180, reason: "Your heart rate is still elevated. A few more minutes may help you reach a calmer state.")
        } else if hrDelta > 8 {
            return .optional(additionalSeconds: 120, reason: "You're making progress! A bit more time could deepen your relaxation.")
        }

        return .notNeeded
    }
}

struct BreathingPattern: Equatable {
    let inhale: Double
    let hold: Double
    let exhale: Double
    let pause: Double
}

struct AdaptationResult {
    let adapted: Bool
    let parameters: AdaptationParameters
    var changes: [AdaptationChange] = []
}

enum AdaptationChange {
    case breathingPace(old: BreathingPattern, new: BreathingPattern)
    case visualIntensity(old: Double, new: Double)
    case guidanceVerbosity(old: AdaptationParameters.GuidanceVerbosity, new: AdaptationParameters.GuidanceVerbosity)
    case audioTempo(old: Double, new: Double)

    var type: BiofeedbackAdaptation.AdaptationType {
        switch self {
        case .breathingPace: return .breathingPace
        case .visualIntensity: return .visualFeedback
        case .guidanceVerbosity: return .guidanceFrequency
        case .audioTempo: return .audioTempo
        }
    }
}

enum ExtensionRecommendation {
    case notNeeded
    case optional(additionalSeconds: Int, reason: String)
    case recommended(additionalSeconds: Int, reason: String)
}
```

#### Baseline Calculator

```typescript
// supabase/functions/calculate-baseline/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface HealthKitSample {
  value: number;
  timestamp: string;
  context?: string; // 'resting', 'active', 'sleep'
}

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const authHeader = req.headers.get("Authorization")!;
  const {
    data: { user },
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
  if (!user) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { lookback_days = 14 } = await req.json();

  // Fetch biometric data from user's stored HealthKit samples
  const lookbackDate = new Date();
  lookbackDate.setDate(lookbackDate.getDate() - lookback_days);

  const { data: heartRateSamples } = await supabase
    .from("healthkit_heart_rate")
    .select("*")
    .eq("user_id", user.id)
    .gte("timestamp", lookbackDate.toISOString())
    .order("timestamp", { ascending: true });

  const { data: hrvSamples } = await supabase
    .from("healthkit_hrv")
    .select("*")
    .eq("user_id", user.id)
    .gte("timestamp", lookbackDate.toISOString())
    .order("timestamp", { ascending: true });

  if (!heartRateSamples || heartRateSamples.length < 10) {
    return new Response(
      JSON.stringify({
        error: "Insufficient data",
        required: 10,
        actual: heartRateSamples?.length || 0,
      }),
      { status: 400 },
    );
  }

  // Calculate resting heart rate (lowest 10th percentile during rest/sleep)
  const restingHRSamples = heartRateSamples
    .filter((s: any) => s.context === "resting" || s.context === "sleep")
    .map((s: any) => s.value)
    .sort((a: number, b: number) => a - b);

  const restingHR =
    restingHRSamples.length > 0
      ? percentile(restingHRSamples, 10)
      : percentile(
          heartRateSamples
            .map((s: any) => s.value)
            .sort((a: number, b: number) => a - b),
          10,
        );

  // Calculate stress threshold (85th percentile of active readings)
  const activeHRSamples = heartRateSamples
    .filter((s: any) => s.context !== "sleep")
    .map((s: any) => s.value)
    .sort((a: number, b: number) => a - b);

  const stressThreshold = percentile(activeHRSamples, 85);

  // Calculate relaxed threshold (30th percentile of resting)
  const relaxedThreshold = restingHR + (stressThreshold - restingHR) * 0.3;

  // Calculate resting HRV (median of all HRV readings)
  const hrvValues = (hrvSamples || [])
    .map((s: any) => s.value)
    .sort((a: number, b: number) => a - b);
  const restingHRV = hrvValues.length > 0 ? median(hrvValues) : null;

  // Calculate recovery rate from exercise sessions (if available)
  const { data: exerciseSessions } = await supabase
    .from("biofeedback_sessions")
    .select("*, biofeedback_readings(*)")
    .eq("user_id", user.id)
    .gte("created_at", lookbackDate.toISOString());

  let recoveryRate = null;
  if (exerciseSessions && exerciseSessions.length >= 3) {
    const recoveryRates = exerciseSessions
      .filter((s: any) => s.biofeedback_readings.length >= 5)
      .map((session: any) =>
        calculateRecoveryRate(session.biofeedback_readings),
      )
      .filter((rate: number) => rate > 0);

    recoveryRate = recoveryRates.length > 0 ? median(recoveryRates) : null;
  }

  // Calculate confidence score
  const sampleCount = heartRateSamples.length;
  const confidenceScore = Math.min(
    1.0,
    (sampleCount / 100) * (hrvValues.length > 0 ? 1.2 : 0.8),
  );

  // Upsert baseline
  const baseline = {
    user_id: user.id,
    resting_heart_rate: restingHR,
    resting_hrv: restingHRV,
    exercise_recovery_rate: recoveryRate,
    stress_hr_threshold: stressThreshold,
    relaxed_hr_threshold: relaxedThreshold,
    sample_count: sampleCount,
    confidence_score: Math.round(confidenceScore * 100) / 100,
    calculated_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  await supabase
    .from("biometric_baselines")
    .upsert(baseline, { onConflict: "user_id" });

  return new Response(JSON.stringify({ baseline }), {
    headers: { "Content-Type": "application/json" },
  });
});

function percentile(sortedArr: number[], p: number): number {
  const index = (p / 100) * (sortedArr.length - 1);
  const lower = Math.floor(index);
  const upper = Math.ceil(index);
  const weight = index - lower;
  return sortedArr[lower] * (1 - weight) + sortedArr[upper] * weight;
}

function median(sortedArr: number[]): number {
  const mid = Math.floor(sortedArr.length / 2);
  return sortedArr.length % 2 === 0
    ? (sortedArr[mid - 1] + sortedArr[mid]) / 2
    : sortedArr[mid];
}

function calculateRecoveryRate(readings: any[]): number {
  // Recovery rate = average BPM decrease per minute after peak
  const sorted = readings.sort(
    (a: any, b: any) =>
      new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime(),
  );

  // Find peak heart rate
  let peakIndex = 0;
  let peakHR = 0;
  sorted.forEach((r: any, i: number) => {
    if (r.heart_rate > peakHR) {
      peakHR = r.heart_rate;
      peakIndex = i;
    }
  });

  // Calculate recovery from peak to end
  const recoveryReadings = sorted.slice(peakIndex);
  if (recoveryReadings.length < 3) return 0;

  const first = recoveryReadings[0];
  const last = recoveryReadings[recoveryReadings.length - 1];
  const hrDrop = first.heart_rate - last.heart_rate;
  const minutesDuration =
    (new Date(last.timestamp).getTime() - new Date(first.timestamp).getTime()) /
    60000;

  return minutesDuration > 0 ? hrDrop / minutesDuration : 0;
}
```

---

## Dependencies

### Internal Dependencies

- F001 (Biometric Correlation Engine) - Data infrastructure
- F012 (Sleep Optimization) - HealthKit patterns
- Core Exercise System - Exercise framework
- User Settings - Preference management

### External Dependencies

- HealthKit - Biometric data access
- WatchConnectivity - Real-time Watch data
- Apple Watch - Heart rate sensor

### Infrastructure

- Supabase Database - Session and reading storage
- Supabase Edge Functions - Baseline calculation

---

## Edge Cases & Error Handling

| Scenario                           | Handling                                           |
| ---------------------------------- | -------------------------------------------------- |
| Apple Watch not paired             | Show setup guidance, offer non-biofeedback mode    |
| Watch battery low                  | Reduce polling frequency, warn user                |
| HealthKit permission denied        | Explain benefits, provide settings deep link       |
| Heart rate spikes unexpectedly     | Filter outliers, maintain adaptation stability     |
| No baseline data yet               | Use age-based defaults, build baseline over time   |
| Very low HRV (health concern)      | Show concern, suggest medical consultation         |
| Watch loses connection mid-session | Buffer last known values, reconnect gracefully     |
| User removes Watch during session  | Detect absence, offer to continue without feedback |
| Baseline significantly changes     | Alert user, suggest recalculation                  |

---

## Testing Requirements

### Unit Tests

```swift
import XCTest
@testable import MindFriendApp

final class BiofeedbackTests: XCTestCase {

    func testStressLevelCalculation() {
        let baseline = BiometricBaseline(
            id: UUID(),
            userId: UUID(),
            restingHeartRate: 60,
            restingHRV: 50,
            exerciseRecoveryRate: nil,
            stressHRThreshold: 100,
            relaxedHRThreshold: 72,
            calculatedAt: Date(),
            sampleCount: 50,
            confidenceScore: 0.8,
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(baseline.stressLevel(forHeartRate: 62), .relaxed)
        XCTAssertEqual(baseline.stressLevel(forHeartRate: 75), .calm)
        XCTAssertEqual(baseline.stressLevel(forHeartRate: 85), .moderate)
        XCTAssertEqual(baseline.stressLevel(forHeartRate: 95), .elevated)
        XCTAssertEqual(baseline.stressLevel(forHeartRate: 110), .high)
    }

    func testBreathingPaceAdaptation() async {
        let baseline = createTestBaseline()
        let engine = await AdaptationEngine(baseline: baseline, mode: .auto)

        // High stress reading
        let highStressReading = LiveBiometricData(heartRate: 105, hrvRMSSD: 25, timestamp: Date())
        let result = await engine.processReading(highStressReading)

        XCTAssertTrue(result.adapted)
        XCTAssertEqual(result.parameters.breathingExhaleSeconds, 5)  // Longer exhale for calming
    }

    func testExtensionRecommendation() async {
        let baseline = createTestBaseline()
        let engine = await AdaptationEngine(baseline: baseline, mode: .auto)

        // Still elevated after 5 minutes
        let recommendation = engine.checkShouldExtend(
            averageHR: 85,
            targetHR: 65,
            elapsedTime: 300
        )

        if case .recommended(let seconds, _) = recommendation {
            XCTAssertEqual(seconds, 180)
        } else {
            XCTFail("Expected recommended extension")
        }
    }

    func testMinimumAdaptationInterval() async {
        let baseline = createTestBaseline()
        let engine = await AdaptationEngine(baseline: baseline, mode: .auto)

        let reading = LiveBiometricData(heartRate: 100, hrvRMSSD: 30, timestamp: Date())

        // First reading adapts
        let result1 = await engine.processReading(reading)
        XCTAssertTrue(result1.adapted)

        // Immediate second reading should not adapt
        let result2 = await engine.processReading(reading)
        XCTAssertFalse(result2.adapted)
    }

    private func createTestBaseline() -> BiometricBaseline {
        BiometricBaseline(
            id: UUID(),
            userId: UUID(),
            restingHeartRate: 60,
            restingHRV: 50,
            exerciseRecoveryRate: 3,
            stressHRThreshold: 100,
            relaxedHRThreshold: 72,
            calculatedAt: Date(),
            sampleCount: 100,
            confidenceScore: 0.9,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
```

### Integration Tests

```swift
final class BiofeedbackIntegrationTests: XCTestCase {
    var service: BiofeedbackService!

    override func setUp() async throws {
        service = BiofeedbackService(supabase: TestSupabaseClient())
    }

    func testSessionLifecycle() async throws {
        // Create session
        let session = try await service.startSession(
            exerciseSessionId: nil,
            adaptationMode: .auto
        )
        XCTAssertNotNil(session.id)

        // Add readings
        for i in 0..<5 {
            try await service.recordReading(
                sessionId: session.id,
                heartRate: Double(80 - i * 3),
                hrvRmssd: Double(40 + i * 2)
            )
        }

        // Complete session
        let completed = try await service.completeSession(sessionId: session.id)
        XCTAssertNotNil(completed.completedAt)

        // Verify summary was generated
        let summary = try await service.fetchSummary(sessionId: session.id)
        XCTAssertEqual(summary.startingHeartRate, 80)
        XCTAssertEqual(summary.endingHeartRate, 68)
    }

    func testBaselineCalculation() async throws {
        // Seed test HealthKit data
        await seedTestHealthKitData()

        // Calculate baseline
        let baseline = try await service.calculateBaseline(lookbackDays: 7)

        XCTAssertNotNil(baseline.restingHeartRate)
        XCTAssertNotNil(baseline.stressHRThreshold)
        XCTAssertGreaterThan(baseline.confidenceScore, 0)
    }
}
```

### UI Tests

```swift
final class BiofeedbackUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        app = XCUIApplication()
        app.launchArguments.append("--mock-healthkit")
        app.launch()
    }

    func testBiofeedbackExerciseFlow() {
        navigateToExercise("Breathing")
        app.switches["Enable Biofeedback"].tap()

        app.buttons["Start Exercise"].tap()

        // Wait for heart rate display
        XCTAssertTrue(app.staticTexts["Heart Rate"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["BPM"].exists)

        // Verify adaptation indicator appears
        XCTAssertTrue(app.images["AdaptationIndicator"].waitForExistence(timeout: 10))
    }

    func testSessionSummary() {
        // Complete a biofeedback session
        completeTestSession()

        // Verify summary screen
        XCTAssertTrue(app.staticTexts["Session Summary"].exists)
        XCTAssertTrue(app.staticTexts["Starting HR"].exists)
        XCTAssertTrue(app.staticTexts["Ending HR"].exists)
        XCTAssertTrue(app.staticTexts["HRV Change"].exists)
    }

    func testNoWatchFallback() {
        app.launchArguments.append("--no-watch")
        app.launch()

        navigateToExercise("Breathing")

        // Biofeedback toggle should be disabled
        XCTAssertFalse(app.switches["Enable Biofeedback"].isEnabled)
        XCTAssertTrue(app.staticTexts["Apple Watch required"].exists)
    }

    private func navigateToExercise(_ name: String) {
        app.tabBars["TabBar"].buttons["Exercises"].tap()
        app.cells[name].tap()
    }

    private func completeTestSession() {
        navigateToExercise("Breathing")
        app.switches["Enable Biofeedback"].tap()
        app.buttons["Start Exercise"].tap()

        // Fast-forward simulation
        app.buttons["Complete"].tap()
    }
}
```
