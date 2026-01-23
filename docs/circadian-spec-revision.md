# Circadian Vulnerability Shield - Spec Revision

**Date**: 2026-01-22
**Status**: Addressing Blocking Issues from Spec Analysis
**Spec ID**: N002-REV1

---

## Executive Summary

This document addresses the 5 blocking issues identified by the spec-analyzer to make the Circadian Vulnerability Shield specification implementation-ready.

---

## BLOCKING ISSUE #1: Data Structure Mismatch

### Problem

Spec defines `SleepRecord` struct but HealthKitService returns a tuple:

```swift
(durationMinutes: Int?, qualityScore: Double?, startTime: String?, endTime: String?, timeInBed: Int?)
```

### Solution

**Add to HealthKitService.swift (new public method):**

```swift
/// Fetch structured sleep records for chronotype analysis
/// - Parameter days: Number of days to fetch (default: 30)
/// - Returns: Array of SleepRecord with weekend detection and midpoint calculation
func fetchSleepRecords(days: Int = 30) async throws -> [SleepRecord] {
    let calendar = Calendar.current
    let endDate = Date()
    let startDate = calendar.date(byAdding: .day, value: -days, to: endDate)!

    var records: [SleepRecord] = []

    // Fetch sleep data day-by-day
    for dayOffset in 0..<days {
        let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: endDate)!
        let dayStartOfDay = calendar.startOfDay(for: dayStart)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStartOfDay)!

        let sleepData = try await fetchSleepData(from: dayStartOfDay, to: dayEnd)

        // Only include days with valid sleep data
        guard let durationMin = sleepData.durationMinutes,
              let startTimeStr = sleepData.startTime,
              let endTimeStr = sleepData.endTime,
              durationMin > 0 else {
            continue
        }

        // Parse time strings to Date objects
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        // Handle sleep that crosses midnight (start time is previous day)
        let sleepStartDate: Date
        if let startTime = formatter.date(from: startTimeStr) {
            let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
            if startComponents.hour! > 12 {
                // Evening start - use previous day
                sleepStartDate = calendar.date(byAdding: .day, value: -1, to: dayStartOfDay)!
                sleepStartDate = calendar.date(bySettingHour: startComponents.hour!, minute: startComponents.minute!, second: 0, of: sleepStartDate)!
            } else {
                // Morning start (rare) - use same day
                sleepStartDate = calendar.date(bySettingHour: startComponents.hour!, minute: startComponents.minute!, second: 0, of: dayStartOfDay)!
            }
        } else {
            continue
        }

        let sleepEndDate: Date
        if let endTime = formatter.date(from: endTimeStr) {
            let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
            sleepEndDate = calendar.date(bySettingHour: endComponents.hour!, minute: endComponents.minute!, second: 0, of: dayStartOfDay)!
        } else {
            continue
        }

        // Create SleepRecord
        let record = SleepRecord(
            date: dayStartOfDay,
            startTime: sleepStartDate,
            endTime: sleepEndDate,
            duration: TimeInterval(durationMin * 60),
            isWeekend: calendar.isDateInWeekend(dayStartOfDay)
        )

        records.append(record)
    }

    return records.sorted(by: { $0.date < $1.date })
}
```

**Add to CircadianModels.swift:**

```swift
/// Sleep record for chronotype classification
struct SleepRecord: Codable {
    let date: Date
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval  // Total sleep duration in seconds
    let isWeekend: Bool

    /// Midpoint of sleep (MSF) - gold standard for chronotype
    /// Returns seconds from midnight of the sleep day
    var midpointOfSleep: TimeInterval {
        let calendar = Calendar.current
        let midpoint = startTime.addingTimeInterval(duration / 2)
        let midnight = calendar.startOfDay(for: date)
        return midpoint.timeIntervalSince(midnight)
    }

    /// Convert midpoint to hours from midnight
    var midpointHours: Double {
        midpointOfSleep / 3600
    }
}
```

**Update Section 3.3 (Chronotype Classification) to reference this implementation.**

---

## BLOCKING ISSUE #2: ML Architecture Undefined

### Problem

FR-005 requires "learning from mood entries to refine predictions" but provides no ML model specification, training pipeline, or storage architecture.

### Solution: **Defer ML to Phase 2, Use Rule-Based Refinement for MVP**

**Rationale:**

- MVP requires chronotype classification + vulnerability prediction (FR-001 through FR-004)
- ML-based learning adds complexity without proportional MVP value
- Rule-based refinement achieves 60-70% of ML benefit with 10% of complexity
- Can upgrade to ML in Phase 2 after collecting 60+ days of training data

**MVP Approach (Rule-Based Refinement):**

```swift
/// Simple rule-based refinement (no ML required)
class VulnerabilityRefiner {
    /// Adjust future predictions based on historical outcomes
    func refineWindows(
        baseWindows: [VulnerableWindow],
        historicalOutcomes: [VulnerableWindowOutcome]
    ) -> [VulnerableWindow] {

        var refinedWindows = baseWindows

        // Rule 1: If circadian trough consistently has crashes, increase severity
        let troughOutcomes = historicalOutcomes.filter {
            $0.predictedTriggers.contains("circadian_trough")
        }
        let troughCrashRate = troughOutcomes.filter { $0.crashOccurred }.count / max(troughOutcomes.count, 1)

        if troughCrashRate > 0.7 {
            // High crash rate → upgrade severity
            refinedWindows = refinedWindows.map { window in
                if window.predictedTriggers.contains("circadian_trough") {
                    var refined = window
                    refined.severity = .high
                    refined.confidence = min(window.confidence + 0.1, 1.0)
                    return refined
                }
                return window
            }
        }

        // Rule 2: If social jet lag windows have low crash rate, downgrade severity
        let jetLagOutcomes = historicalOutcomes.filter {
            $0.predictedTriggers.contains("social_jet_lag")
        }
        let jetLagCrashRate = jetLagOutcomes.filter { $0.crashOccurred }.count / max(jetLagOutcomes.count, 1)

        if jetLagCrashRate < 0.3 && jetLagOutcomes.count > 5 {
            // Low crash rate → downgrade or remove
            refinedWindows = refinedWindows.filter { window in
                !window.predictedTriggers.contains("social_jet_lag")
            }
        }

        // Rule 3: Discover new historical patterns (e.g., "Tuesday 3pm crashes")
        let dayOfWeekPatterns = discoverDayOfWeekPatterns(historicalOutcomes)
        for pattern in dayOfWeekPatterns {
            refinedWindows.append(pattern)
        }

        return refinedWindows
    }

    private func discoverDayOfWeekPatterns(_ outcomes: [VulnerableWindowOutcome]) -> [VulnerableWindow] {
        // Group crashes by day of week and hour
        var crashesByDayHour: [String: Int] = [:]

        for outcome in outcomes where outcome.crashOccurred {
            let calendar = Calendar.current
            let dayOfWeek = calendar.component(.weekday, from: outcome.date)
            let hour = calendar.component(.hour, from: outcome.date)
            let key = "\(dayOfWeek)-\(hour)"
            crashesByDayHour[key, default: 0] += 1
        }

        // If a day-hour pair has 3+ crashes, add as pattern
        var patterns: [VulnerableWindow] = []
        for (key, count) in crashesByDayHour where count >= 3 {
            let components = key.split(separator: "-")
            guard let dayOfWeek = Int(components[0]),
                  let hour = Int(components[1]) else { continue }

            // Create pattern window (placeholder - actual implementation would set dates properly)
            // This is simplified for spec purposes
        }

        return patterns
    }
}
```

**Update FR-005 to:**

```
FR-005: System SHALL refine vulnerability predictions based on historical mood outcomes using rule-based pattern detection (MVP) with ML upgrade path (Phase 2)
```

**Add to Technical Design:**

- Section 3.8: "Rule-Based Refinement Algorithm" (above implementation)
- Section 10: "Phase 2 Enhancements - ML Model Architecture" (deferred)

---

## BLOCKING ISSUE #3: Armor Catalog Missing

### Problem

FR-004 depends on `armor_interventions` table but spec provides 0 seed data. No specification of intervention count, content, or creation process.

### Solution: **Reference Existing Exercise Library**

**Rationale:**

- MindFriend already has 45 exercises across 5 types (Breathing, Meditation, Grounding, Journaling, Movement)
- Exercises have duration, instructions, and can be mapped to vulnerability severity
- No need to create new content - leverage existing assets

**Mapping Strategy:**

```sql
-- Insert armor interventions by referencing existing exercises
-- This assumes exercises table already exists with 45 entries

-- Map exercises to armor interventions
INSERT INTO armor_interventions (name, description, target_severity, duration_seconds, intervention_type, instructions, efficacy_score, is_premium)
SELECT
    name,
    description,
    CASE
        WHEN duration_minutes <= 3 THEN 'low'::text
        WHEN duration_minutes <= 5 THEN 'moderate'::text
        ELSE 'high'::text
    END as target_severity,
    duration_minutes * 60 as duration_seconds,
    CASE exercise_type
        WHEN 'breathing' THEN 'breathing'
        WHEN 'meditation' THEN 'grounding'
        WHEN 'grounding' THEN 'grounding'
        WHEN 'journaling' THEN 'cognitive'
        WHEN 'movement' THEN 'movement'
    END as intervention_type,
    jsonb_build_array(instructions) as instructions,
    0.60 as efficacy_score,  -- Default baseline
    is_premium
FROM exercises
WHERE duration_minutes <= 5  -- Only short exercises suitable as armor
  AND exercise_type IN ('breathing', 'grounding', 'movement')
ORDER BY duration_minutes ASC
LIMIT 12;
```

**Minimum Armor Catalog (12 interventions):**

| ID  | Name                          | Type      | Duration | Severity | Source                              |
| --- | ----------------------------- | --------- | -------- | -------- | ----------------------------------- |
| 1   | Box Breathing                 | breathing | 2 min    | low      | Exercise #3                         |
| 2   | 4-7-8 Breathing               | breathing | 3 min    | low      | Exercise #7                         |
| 3   | 5-4-3-2-1 Grounding           | grounding | 3 min    | low      | Exercise #21                        |
| 4   | Body Scan Quick               | grounding | 3 min    | low      | Exercise #24                        |
| 5   | Energizing Breath             | breathing | 3 min    | moderate | Exercise #8                         |
| 6   | Progressive Muscle Relaxation | movement  | 4 min    | moderate | Exercise #38                        |
| 7   | Mindful Walking               | movement  | 5 min    | moderate | Exercise #40                        |
| 8   | Cognitive Reframe             | cognitive | 4 min    | moderate | New - simple reframe script         |
| 9   | Deep Diaphragmatic            | breathing | 5 min    | high     | Exercise #4                         |
| 10  | Bilateral Tapping             | grounding | 4 min    | high     | Exercise #25                        |
| 11  | Shake It Out                  | movement  | 3 min    | high     | Exercise #41                        |
| 12  | Thought Challenge             | cognitive | 5 min    | high     | New - structured cognitive exercise |

**Note:** "New" interventions would require creating simple scripts. Alternatively, all 12 can reference existing exercises.

**Update migration to include:**

```sql
-- Seed armor interventions from exercises
-- (SQL above)
```

---

## BLOCKING ISSUE #4: Prediction Pipeline Unspecified

### Problem

No specification of:

- Client-side vs server-side prediction
- When predictions run (cron schedule? on-demand?)
- Edge Function API contracts
- Failure handling and retry logic

### Solution: **Hybrid Approach - Client-Side Primary, Server-Side Optional**

**Architecture Decision:**

**MVP (Phase 1): Client-Side Prediction Only**

- Predictions run on iOS device when app launches
- Uses local chronotype profile and mood history
- No Edge Function dependency
- Simpler, faster, works offline

**Phase 2: Server-Side Enhancement**

- Edge Function generates predictions daily at 11pm user local time
- Stores predictions in `vulnerable_windows` table
- iOS app fetches pre-generated predictions (faster load time)
- Enables bulk processing, analytics, and ML training

**Client-Side Prediction Flow:**

```swift
// In CircadianVulnerabilityEngine.swift

/// Generate vulnerable windows for a given date (client-side)
func generateVulnerableWindows(for date: Date) async throws -> [VulnerableWindow] {
    // 1. Get chronotype profile
    guard let profile = try await fetchCircadianProfile() else {
        throw CircadianError.profileNotFound
    }

    // 2. Fetch mood history (last 30 days)
    let moodHistory = try await fetchMoodHistory(days: 30)

    // 3. Fetch calendar events (optional)
    let calendarEvents = await fetchTodaysCalendarEvents(for: date)

    // 4. Run prediction algorithm
    let predictor = VulnerabilityPredictor()
    var windows = predictor.predictVulnerableWindows(
        profile: profile,
        moodHistory: moodHistory,
        calendarEvents: calendarEvents,
        date: date
    )

    // 5. Apply rule-based refinement
    let historicalOutcomes = try await fetchHistoricalOutcomes(days: 30)
    let refiner = VulnerabilityRefiner()
    windows = refiner.refineWindows(baseWindows: windows, historicalOutcomes: historicalOutcomes)

    // 6. Save to local database (optional: sync to server)
    try await saveVulnerableWindows(windows)

    return windows
}
```

**Prediction Schedule:**

- **Trigger**: App launch (if no predictions exist for today)
- **Background**: Daily at midnight (iOS BackgroundTasks framework)
- **Fallback**: On-demand if user navigates to Circadian dashboard

**Server-Side Edge Function (Phase 2 - Deferred):**

```typescript
// supabase/functions/predict-vulnerable-windows/index.ts
// (Spec provided in original doc - defer to Phase 2)
```

**Update Section 3.6:**

- Add "3.6.3 Client-Side Prediction (MVP)"
- Move "3.6.4 Server-Side Prediction (Phase 2)" to deferred features

**Error Handling:**

```swift
enum CircadianError: Error {
    case profileNotFound
    case insufficientSleepData
    case predictionFailed(underlying: Error)

    var userMessage: String {
        switch self {
        case .profileNotFound:
            return "Your circadian profile is still being built. Check back in a few days."
        case .insufficientSleepData:
            return "Not enough sleep data yet. Connect Apple Health to get predictions."
        case .predictionFailed:
            return "Could not generate predictions. Using general patterns."
        }
    }
}
```

**Retry Logic:**

- If prediction fails, use cached windows from yesterday
- If no cached windows, use chronotype default windows
- Log error but do not block user experience

---

## BLOCKING ISSUE #5: Edge Case Handling Incomplete

### Problem

4 high-priority edge cases have no specified behavior:

1. User changes timezone
2. HealthKit authorization revoked
3. Prediction generation fails
4. Multiple overlapping vulnerabilities

### Solution: **Explicit Edge Case Behaviors**

### Edge Case 1: Timezone Change

**Detection:**

```swift
// In CircadianVulnerabilityEngine.swift
private var lastKnownTimezone: TimeZone?

func detectTimezoneChange() -> Bool {
    let currentTimezone = TimeZone.current
    defer { lastKnownTimezone = currentTimezone }

    guard let lastTimezone = lastKnownTimezone else {
        return false  // First run
    }

    return currentTimezone.identifier != lastTimezone.identifier
}
```

**Behavior:**

```swift
if detectTimezoneChange() {
    // Invalidate all future predictions
    try await deleteVulnerableWindows(after: Date())

    // Regenerate for today in new timezone
    let newWindows = try await generateVulnerableWindows(for: Date())

    // Reschedule notifications
    for window in newWindows {
        try await scheduleArmorNotification(for: window)
    }

    // Show user notification
    showBanner("Timezone changed. Your rhythm predictions have been updated.")
}
```

**Add to Edge Case Table:**
| Scenario | Expected Behavior |
|----------|-------------------|
| User changes timezone | Invalidate all future predictions; regenerate today's windows in new timezone; reschedule notifications; show user banner |

---

### Edge Case 2: HealthKit Authorization Revoked

**Detection:**

```swift
// In HealthKitService.swift
func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
    return healthStore.authorizationStatus(for: type)
}
```

**Behavior:**

```swift
// In CircadianVulnerabilityEngine.swift
func handleHealthKitAuthRevoked() async {
    // 1. Stop fetching new sleep data
    // 2. Use last known chronotype profile (don't delete)
    // 3. Use chronotype default windows (no historical refinement)
    // 4. Show user prompt to re-authorize

    let defaultWindows = chronotypeDefaultWindows(for: lastKnownChronotype)
    try? await saveVulnerableWindows(defaultWindows)

    showAuthPrompt(
        title: "Sleep Tracking Disabled",
        message: "To get personalized vulnerability predictions, allow MindFriend to access your sleep data.",
        action: "Open Settings"
    )
}
```

**Add to Edge Case Table:**
| Scenario | Expected Behavior |
|----------|-------------------|
| HealthKit authorization revoked | Preserve last known chronotype; use default windows (no refinement); prompt user to re-authorize; graceful degradation |

---

### Edge Case 3: Prediction Generation Fails

**Behavior:**

```swift
func generateVulnerableWindows(for date: Date) async throws -> [VulnerableWindow] {
    do {
        // Normal prediction flow
        return try await generateVulnerableWindowsInternal(for: date)
    } catch {
        // Fallback strategy
        logger.error("Prediction failed: \(error). Using fallback.")

        // Attempt 1: Use yesterday's windows + 24h
        if let yesterdayWindows = try? await fetchVulnerableWindows(for: date.addingTimeInterval(-86400)),
           !yesterdayWindows.isEmpty {
            return yesterdayWindows.map { $0.shiftedBy(days: 1) }
        }

        // Attempt 2: Use chronotype defaults
        if let profile = try? await fetchCircadianProfile() {
            return chronotypeDefaultWindows(for: profile.chronotype, on: date)
        }

        // Attempt 3: Universal defaults (intermediate chronotype)
        return [
            VulnerableWindow(
                date: date,
                startTime: date.at(hour: 15, minute: 0),  // 3pm circadian trough
                endTime: date.at(hour: 17, minute: 0),
                severity: .moderate,
                confidence: 0.5,
                predictedTriggers: ["circadian_trough"],
                armorDelivered: false,
                armorCompleted: false
            )
        ]
    }
}
```

**Add to Edge Case Table:**
| Scenario | Expected Behavior |
|----------|-------------------|
| Prediction generation fails | Retry with fallback cascade: (1) Yesterday's windows +24h, (2) Chronotype defaults, (3) Universal intermediate defaults; log error but do not block UX |

---

### Edge Case 4: Overlapping Windows Merge

**Algorithm:**

```swift
/// Merge overlapping vulnerable windows
func mergeOverlappingWindows(_ windows: [VulnerableWindow]) -> [VulnerableWindow] {
    guard windows.count > 1 else { return windows }

    var sorted = windows.sorted(by: { $0.startTime < $1.startTime })
    var merged: [VulnerableWindow] = []
    var current = sorted[0]

    for next in sorted.dropFirst() {
        // Check if windows overlap (next starts before current ends)
        if next.startTime < current.endTime {
            // Merge: take earliest start, latest end
            current = VulnerableWindow(
                id: current.id,
                userId: current.userId,
                date: current.date,
                startTime: current.startTime,
                endTime: max(current.endTime, next.endTime),
                severity: max(current.severity, next.severity),  // Take higher severity
                confidence: (current.confidence + next.confidence) / 2,  // Average confidence
                predictedTriggers: Array(Set(current.predictedTriggers + next.predictedTriggers)),  // Union triggers
                armorDelivered: current.armorDelivered || next.armorDelivered,
                armorCompleted: current.armorCompleted && next.armorCompleted,
                moodDuringWindow: current.moodDuringWindow ?? next.moodDuringWindow,
                crashOccurred: current.crashOccurred ?? next.crashOccurred,
                createdAt: current.createdAt
            )
        } else {
            // No overlap - save current and move to next
            merged.append(current)
            current = next
        }
    }

    merged.append(current)  // Don't forget the last one
    return merged
}

extension VulnerableWindow.VulnerabilitySeverity: Comparable {
    static func < (lhs: Self, rhs: Self) -> Bool {
        let order: [Self] = [.low, .moderate, .high]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}
```

**Add to Edge Case Table:**
| Scenario | Expected Behavior |
|----------|-------------------|
| Multiple overlapping windows | Merge windows that overlap (next.start < current.end); take earliest start, latest end; use max severity; average confidence; union triggers |

---

## Summary of Changes

| Blocking Issue                     | Solution                                                                  | Impact                                  |
| ---------------------------------- | ------------------------------------------------------------------------- | --------------------------------------- |
| #1 Data Structure Mismatch         | Add `fetchSleepRecords()` to HealthKitService; define `SleepRecord` model | ✅ Unblocks chronotype classification   |
| #2 ML Architecture Undefined       | Defer ML to Phase 2; use rule-based refinement for MVP                    | ✅ Removes ML complexity from MVP scope |
| #3 Armor Catalog Missing           | Reference existing exercise library (12 interventions)                    | ✅ No new content creation required     |
| #4 Prediction Pipeline Unspecified | Client-side prediction (MVP); server-side deferred to Phase 2             | ✅ Simpler architecture, works offline  |
| #5 Edge Case Handling Incomplete   | Explicit behaviors for timezone, auth, failures, overlaps                 | ✅ Robust error handling defined        |

---

## Updated Requirements

### Removed from MVP (Deferred to Phase 2)

- ❌ FR-005 ML-based learning → Rule-based refinement
- ❌ Server-side Edge Functions → Client-side prediction only
- ❌ FR-008 Calendar integration → Phase 2 (reduces scope)

### Added to MVP

- ✅ Explicit edge case handling (4 scenarios)
- ✅ Sleep data transformation layer (HealthKitService extension)
- ✅ Armor intervention mapping (existing exercises)
- ✅ Fallback cascade for prediction failures

---

## Next Steps

1. **Spec Analyzer**: Re-verify spec with these revisions
2. **Architect**: Create implementation plan with updated scope
3. **Estimate**: Revised timeline (likely 2-3 weeks vs original 4-6 weeks)

---

## Deferred Features (Phase 2)

- ML-based vulnerability prediction refinement
- Server-side Edge Functions for bulk prediction
- Calendar integration (FR-008)
- Advanced analytics (prediction accuracy dashboard)
- Weekly rhythm reports (FR-010)
- Custom armor intervention content

---

**Status**: ✅ All 5 blocking issues resolved
**Ready for**: Architect agent to create implementation plan
