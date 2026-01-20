# Medication Reminders

> Track medication adherence and correlate with mental wellness outcomes.

**Priority:** P3 - Nice to Have
**Effort:** Medium (2-3 weeks)
**Impact:** Medication adherence; holistic health tracking

---

## 1. Overview

### 1.1 What It Does

A medication tracking companion feature:

- Set reminders for medications/supplements
- Log when medication is taken
- Track adherence over time
- Correlate medication adherence with mood patterns
- Optional notes for side effects or observations

### 1.2 Why It Exists

- **Adherence Challenge:** 50% of patients don't take meds as prescribed
- **Holistic View:** Mental health often involves medication
- **Correlation Insights:** "You feel better on days you take your meds"
- **User Request:** Common feature ask from users on psychiatric medications

### 1.3 Success Metrics

| Metric            | Target       | Measurement            |
| ----------------- | ------------ | ---------------------- |
| Feature adoption  | 15% of users | Users with 1+ med      |
| Adherence rate    | 80%+         | Taken / Scheduled      |
| Correlation views | 40% of users | Users viewing insights |

---

## 2. Functional Requirements

### 2.1 Core Features

| ID    | Requirement                             | Priority |
| ----- | --------------------------------------- | -------- |
| MR-01 | Add medication with name and dosage     | Must     |
| MR-02 | Set reminder schedule (time, frequency) | Must     |
| MR-03 | Push notification reminders             | Must     |
| MR-04 | Log medication as taken                 | Must     |
| MR-05 | Log as skipped with reason              | Should   |
| MR-06 | View adherence history                  | Must     |
| MR-07 | Correlate with mood data                | Should   |
| MR-08 | Add notes (side effects, observations)  | Should   |
| MR-09 | Multiple medications support            | Must     |
| MR-10 | Refill reminders                        | Could    |

### 2.2 Privacy Features

| ID    | Requirement                          | Priority |
| ----- | ------------------------------------ | -------- |
| PV-01 | Medication data encrypted            | Must     |
| PV-02 | Optional Face ID to view medications | Should   |
| PV-03 | Generic notification text option     | Must     |
| PV-04 | Export data option                   | Should   |

---

## 3. Technical Requirements

### 3.1 Data Models

```sql
-- Medications
CREATE TABLE medications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Medication info
    name TEXT NOT NULL,
    dosage TEXT, -- "50mg", "1 tablet"
    purpose TEXT, -- "Anxiety", "Depression", "Sleep"
    color TEXT, -- For pill icon display
    icon TEXT DEFAULT 'pill', -- 'pill', 'capsule', 'liquid', 'injection'

    -- Schedule
    frequency TEXT NOT NULL, -- 'daily', 'twice_daily', 'weekly', 'as_needed'
    times_per_day INTEGER DEFAULT 1,
    scheduled_times TIME[], -- ['08:00', '20:00']
    days_of_week INTEGER[], -- [0,1,2,3,4,5,6] for daily, [1,3,5] for specific days

    -- Reminders
    reminder_enabled BOOLEAN DEFAULT true,
    reminder_sound TEXT DEFAULT 'default',
    notification_text TEXT, -- Custom or null for default

    -- Tracking
    supply_count INTEGER, -- Pills remaining
    refill_reminder_count INTEGER, -- Remind when X left

    -- Status
    is_active BOOLEAN DEFAULT true,
    started_at DATE DEFAULT CURRENT_DATE,
    ended_at DATE,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Medication logs
CREATE TABLE medication_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    medication_id UUID NOT NULL REFERENCES medications(id) ON DELETE CASCADE,

    -- Scheduling
    scheduled_at TIMESTAMPTZ NOT NULL,

    -- Status
    status TEXT NOT NULL, -- 'taken', 'skipped', 'late', 'pending'
    logged_at TIMESTAMPTZ,

    -- Details
    skip_reason TEXT, -- If skipped
    notes TEXT,
    side_effects TEXT[],

    -- Correlation
    mood_at_time INTEGER, -- If user logged mood close to this time

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE medications ENABLE ROW LEVEL SECURITY;
ALTER TABLE medication_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own medications"
    ON medications FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users manage own logs"
    ON medication_logs FOR ALL USING (auth.uid() = user_id);

-- Indexes
CREATE INDEX idx_med_logs_user_date ON medication_logs(user_id, scheduled_at DESC);
CREATE INDEX idx_medications_active ON medications(user_id) WHERE is_active = true;
```

### 3.2 Swift Models

```swift
struct Medication: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let name: String
    let dosage: String?
    let purpose: String?
    let color: String?
    let icon: MedicationIcon
    let frequency: MedicationFrequency
    let timesPerDay: Int
    let scheduledTimes: [Date] // Time components only
    let daysOfWeek: [Int]?
    let reminderEnabled: Bool
    let reminderSound: String
    let notificationText: String?
    let supplyCount: Int?
    let refillReminderCount: Int?
    let isActive: Bool
    let startedAt: Date
    let endedAt: Date?
}

enum MedicationIcon: String, Codable, CaseIterable {
    case pill
    case capsule
    case liquid
    case injection
    case patch
    case drops

    var systemImage: String {
        switch self {
        case .pill: return "pills.fill"
        case .capsule: return "capsule.fill"
        case .liquid: return "drop.fill"
        case .injection: return "syringe.fill"
        case .patch: return "bandage.fill"
        case .drops: return "drop.triangle.fill"
        }
    }
}

enum MedicationFrequency: String, Codable {
    case daily
    case twiceDaily = "twice_daily"
    case threeTimesDaily = "three_times_daily"
    case weekly
    case asNeeded = "as_needed"
    case custom

    var description: String {
        switch self {
        case .daily: return "Once daily"
        case .twiceDaily: return "Twice daily"
        case .threeTimesDaily: return "Three times daily"
        case .weekly: return "Weekly"
        case .asNeeded: return "As needed"
        case .custom: return "Custom schedule"
        }
    }
}

struct MedicationLog: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let medicationId: UUID
    let scheduledAt: Date
    let status: MedicationStatus
    let loggedAt: Date?
    let skipReason: String?
    let notes: String?
    let sideEffects: [String]?
    let moodAtTime: Int?
}

enum MedicationStatus: String, Codable {
    case pending
    case taken
    case skipped
    case late
}
```

### 3.3 Medication Service

```swift
@MainActor
class MedicationService: ObservableObject {
    private let supabase: SupabaseClient

    @Published var medications: [Medication] = []
    @Published var todayLogs: [MedicationLog] = []
    @Published var adherenceRate: Double = 0

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Medications

    func fetchMedications() async throws {
        let userId = try await supabase.auth.session.user.id

        medications = try await supabase
            .from("medications")
            .select()
            .eq("user_id", value: userId)
            .eq("is_active", value: true)
            .execute()
            .value
    }

    func addMedication(_ request: AddMedicationRequest) async throws -> Medication {
        let userId = try await supabase.auth.session.user.id

        let med: Medication = try await supabase
            .from("medications")
            .insert([
                "user_id": userId.uuidString,
                "name": request.name,
                "dosage": request.dosage as Any,
                "purpose": request.purpose as Any,
                "frequency": request.frequency.rawValue,
                "times_per_day": request.timesPerDay,
                "scheduled_times": request.scheduledTimes.map { formatTime($0) },
                "reminder_enabled": request.reminderEnabled
            ])
            .select()
            .single()
            .execute()
            .value

        medications.append(med)

        // Schedule reminders
        await scheduleNotifications(for: med)

        return med
    }

    func deactivateMedication(_ medicationId: UUID) async throws {
        try await supabase
            .from("medications")
            .update(["is_active": false, "ended_at": Date().ISO8601Format()])
            .eq("id", value: medicationId)
            .execute()

        medications.removeAll { $0.id == medicationId }

        // Cancel notifications
        await cancelNotifications(for: medicationId)
    }

    // MARK: - Logging

    func logMedicationTaken(_ medicationId: UUID, scheduledAt: Date, notes: String? = nil) async throws {
        let userId = try await supabase.auth.session.user.id

        let log: MedicationLog = try await supabase
            .from("medication_logs")
            .upsert([
                "user_id": userId.uuidString,
                "medication_id": medicationId.uuidString,
                "scheduled_at": scheduledAt.ISO8601Format(),
                "status": MedicationStatus.taken.rawValue,
                "logged_at": Date().ISO8601Format(),
                "notes": notes as Any
            ])
            .select()
            .single()
            .execute()
            .value

        if let index = todayLogs.firstIndex(where: { $0.medicationId == medicationId && Calendar.current.isDate($0.scheduledAt, equalTo: scheduledAt, toGranularity: .hour) }) {
            todayLogs[index] = log
        } else {
            todayLogs.append(log)
        }

        // Update supply count
        if let med = medications.first(where: { $0.id == medicationId }),
           let supply = med.supplyCount {
            try await supabase
                .from("medications")
                .update(["supply_count": supply - 1])
                .eq("id", value: medicationId)
                .execute()
        }
    }

    func skipMedication(_ medicationId: UUID, scheduledAt: Date, reason: String?) async throws {
        let userId = try await supabase.auth.session.user.id

        let log: MedicationLog = try await supabase
            .from("medication_logs")
            .upsert([
                "user_id": userId.uuidString,
                "medication_id": medicationId.uuidString,
                "scheduled_at": scheduledAt.ISO8601Format(),
                "status": MedicationStatus.skipped.rawValue,
                "logged_at": Date().ISO8601Format(),
                "skip_reason": reason as Any
            ])
            .select()
            .single()
            .execute()
            .value

        todayLogs.append(log)
    }

    // MARK: - Today's Schedule

    func fetchTodaySchedule() async throws {
        let userId = try await supabase.auth.session.user.id
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        todayLogs = try await supabase
            .from("medication_logs")
            .select()
            .eq("user_id", value: userId)
            .gte("scheduled_at", value: startOfDay.ISO8601Format())
            .lt("scheduled_at", value: endOfDay.ISO8601Format())
            .execute()
            .value
    }

    func getTodayScheduleItems() -> [ScheduledMedication] {
        var items: [ScheduledMedication] = []

        for med in medications {
            for time in med.scheduledTimes {
                let scheduledAt = Calendar.current.date(
                    bySettingHour: Calendar.current.component(.hour, from: time),
                    minute: Calendar.current.component(.minute, from: time),
                    second: 0,
                    of: Date()
                )!

                let existingLog = todayLogs.first {
                    $0.medicationId == med.id &&
                    Calendar.current.isDate($0.scheduledAt, equalTo: scheduledAt, toGranularity: .hour)
                }

                items.append(ScheduledMedication(
                    medication: med,
                    scheduledAt: scheduledAt,
                    status: existingLog?.status ?? .pending,
                    log: existingLog
                ))
            }
        }

        return items.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    // MARK: - Adherence

    func calculateAdherenceRate(days: Int = 30) async throws -> Double {
        let userId = try await supabase.auth.session.user.id
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        let logs: [MedicationLog] = try await supabase
            .from("medication_logs")
            .select()
            .eq("user_id", value: userId)
            .gte("scheduled_at", value: startDate.ISO8601Format())
            .execute()
            .value

        let taken = logs.filter { $0.status == .taken || $0.status == .late }.count
        let total = logs.count

        adherenceRate = total > 0 ? Double(taken) / Double(total) : 1.0
        return adherenceRate
    }

    // MARK: - Mood Correlation

    func getMoodCorrelation() async throws -> MedicationMoodCorrelation {
        let userId = try await supabase.auth.session.user.id
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!

        // Get mood logs
        let moods: [Mood] = try await supabase
            .from("moods")
            .select()
            .eq("user_id", value: userId)
            .gte("logged_at", value: thirtyDaysAgo.ISO8601Format())
            .execute()
            .value

        // Get medication logs
        let medLogs: [MedicationLog] = try await supabase
            .from("medication_logs")
            .select()
            .eq("user_id", value: userId)
            .gte("scheduled_at", value: thirtyDaysAgo.ISO8601Format())
            .execute()
            .value

        // Group by day and calculate correlation
        var adherentDayMoods: [Int] = []
        var nonAdherentDayMoods: [Int] = []

        let calendar = Calendar.current
        var currentDate = thirtyDaysAgo

        while currentDate <= Date() {
            let dayMoods = moods.filter { calendar.isDate($0.loggedAt, inSameDayAs: currentDate) }
            let dayLogs = medLogs.filter { calendar.isDate($0.scheduledAt, inSameDayAs: currentDate) }

            if !dayMoods.isEmpty && !dayLogs.isEmpty {
                let avgMood = dayMoods.map { $0.score }.reduce(0, +) / dayMoods.count
                let adherent = dayLogs.allSatisfy { $0.status == .taken || $0.status == .late }

                if adherent {
                    adherentDayMoods.append(avgMood)
                } else {
                    nonAdherentDayMoods.append(avgMood)
                }
            }

            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        let avgAdherent = adherentDayMoods.isEmpty ? 0 : Double(adherentDayMoods.reduce(0, +)) / Double(adherentDayMoods.count)
        let avgNonAdherent = nonAdherentDayMoods.isEmpty ? 0 : Double(nonAdherentDayMoods.reduce(0, +)) / Double(nonAdherentDayMoods.count)

        return MedicationMoodCorrelation(
            averageMoodWhenAdherent: avgAdherent,
            averageMoodWhenNotAdherent: avgNonAdherent,
            adherentDays: adherentDayMoods.count,
            nonAdherentDays: nonAdherentDayMoods.count
        )
    }

    // MARK: - Notifications

    private func scheduleNotifications(for medication: Medication) async {
        guard medication.reminderEnabled else { return }

        for time in medication.scheduledTimes {
            let content = UNMutableNotificationContent()
            content.title = "Medication Reminder"
            content.body = medication.notificationText ?? "Time to take \(medication.name)"
            content.sound = .default
            content.categoryIdentifier = "MEDICATION"
            content.userInfo = ["medicationId": medication.id.uuidString]

            var dateComponents = Calendar.current.dateComponents([.hour, .minute], from: time)

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: "med-\(medication.id)-\(dateComponents.hour ?? 0)-\(dateComponents.minute ?? 0)",
                content: content,
                trigger: trigger
            )

            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func cancelNotifications(for medicationId: UUID) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending.filter { $0.identifier.hasPrefix("med-\(medicationId)") }
        center.removePendingNotificationRequests(withIdentifiers: toRemove.map { $0.identifier })
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct AddMedicationRequest {
    let name: String
    let dosage: String?
    let purpose: String?
    let frequency: MedicationFrequency
    let timesPerDay: Int
    let scheduledTimes: [Date]
    let reminderEnabled: Bool
}

struct ScheduledMedication {
    let medication: Medication
    let scheduledAt: Date
    let status: MedicationStatus
    let log: MedicationLog?
}

struct MedicationMoodCorrelation {
    let averageMoodWhenAdherent: Double
    let averageMoodWhenNotAdherent: Double
    let adherentDays: Int
    let nonAdherentDays: Int

    var moodDifference: Double {
        averageMoodWhenAdherent - averageMoodWhenNotAdherent
    }

    var insight: String {
        if moodDifference > 0.5 {
            return "Your mood tends to be better on days you take your medication consistently."
        } else if moodDifference < -0.5 {
            return "Your mood may be affected by your medication. Consider talking to your doctor."
        } else {
            return "Your mood appears stable regardless of medication adherence."
        }
    }
}
```

---

## 4. UI/UX Specifications

### 4.1 Medication List

```
┌─────────────────────────────────┐
│ Medications                 +   │
├─────────────────────────────────┤
│                                 │
│ Today's Schedule                │
│ ┌─────────────────────────────┐ │
│ │ 8:00 AM                     │ │
│ │ ┌───┐ Sertraline 50mg       │ │
│ │ │ ✓ │ Taken at 8:05 AM      │ │
│ │ └───┘                       │ │
│ ├─────────────────────────────┤ │
│ │ 8:00 PM                     │ │
│ │ ┌───┐ Sertraline 50mg       │ │
│ │ │   │ Due in 4 hours        │ │
│ │ └───┘    [Take] [Skip]      │ │
│ └─────────────────────────────┘ │
│                                 │
│ Adherence This Month            │
│ ┌─────────────────────────────┐ │
│ │ 92% adherence               │ │
│ │ ████████████████░░ 23/25    │ │
│ └─────────────────────────────┘ │
│                                 │
│ Mood Insight                    │
│ ┌─────────────────────────────┐ │
│ │ 📈 Your mood is 0.8 points  │ │
│ │ higher on days you take     │ │
│ │ your medication             │ │
│ └─────────────────────────────┘ │
│                                 │
│ My Medications                  │
│ ┌─────────────────────────────┐ │
│ │ 💊 Sertraline               │ │
│ │    50mg • Twice daily       │ │
│ │    For: Anxiety             │ │
│ │              [Edit] [Stop]  │ │
│ └─────────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

### 4.2 Add Medication

```
┌─────────────────────────────────┐
│ ← Add Medication                │
├─────────────────────────────────┤
│                                 │
│ Medication Name *               │
│ ┌─────────────────────────────┐ │
│ │ Sertraline                  │ │
│ └─────────────────────────────┘ │
│                                 │
│ Dosage                          │
│ ┌─────────────────────────────┐ │
│ │ 50mg                        │ │
│ └─────────────────────────────┘ │
│                                 │
│ What's it for? (optional)       │
│ [Anxiety] [Depression] [Sleep]  │
│ [Focus] [Other]                 │
│                                 │
│ How often?                      │
│ ┌─────────────────────────────┐ │
│ │ Twice daily              ▼  │ │
│ └─────────────────────────────┘ │
│                                 │
│ Reminder times                  │
│ ┌─────────────────────────────┐ │
│ │ Morning   [8:00 AM]         │ │
│ │ Evening   [8:00 PM]         │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 🔔 Reminders         [====] │ │
│ └─────────────────────────────┘ │
│                                 │
│         [Add Medication]        │
│                                 │
└─────────────────────────────────┘
```

---

## 5. Acceptance Criteria

- [ ] Users can add medications with schedules
- [ ] Reminders trigger at scheduled times
- [ ] Users can mark medications as taken/skipped
- [ ] Adherence rate is calculated correctly
- [ ] Mood correlation insight is displayed
- [ ] Medication data is private and encrypted
- [ ] Generic notification option works

---

## 6. Privacy & Compliance

| Consideration         | Implementation                                |
| --------------------- | --------------------------------------------- |
| Sensitive health data | Encrypted at rest, RLS enforced               |
| Generic notifications | "Reminder" instead of medication name         |
| Data deletion         | Full export and delete option                 |
| No sharing            | Medication data never shared with circles     |
| Face ID protection    | Optional biometric lock for medication screen |

---

## 7. Rollout Plan

### Phase 1 (Week 1)

- Medication data model
- Add/edit medications
- Basic scheduling

### Phase 2 (Week 2)

- Push notifications
- Logging (taken/skipped)
- Adherence calculation

### Phase 3 (Week 3)

- Mood correlation
- Supply tracking
- Privacy settings
