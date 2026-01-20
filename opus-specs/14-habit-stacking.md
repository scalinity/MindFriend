# Habit Stacking & Routines

> Build lasting mental wellness habits by connecting new behaviors to existing routines.

**Priority:** P2 - Enhancement
**Effort:** Medium (3-4 weeks)
**Impact:** Long-term adherence; behavior change science

---

## 1. Overview

### 1.1 What It Does

A habit formation system based on behavioral science:

- Create habit stacks (link new habits to existing ones)
- Morning and evening wellness routines
- Visual habit tracking with streaks
- Contextual reminders at optimal times
- Gradual habit building (start small, grow)

### 1.2 Why It Exists

- **Behavior Science:** Habit stacking is proven effective (James Clear, BJ Fogg)
- **Long-term Retention:** Habits create automatic engagement
- **Reduced Friction:** Attaching to existing routines lowers activation energy
- **User Request:** "How do I make this part of my daily routine?"

### 1.3 Success Metrics

| Metric                | Target       | Measurement           |
| --------------------- | ------------ | --------------------- |
| Routine completion    | 60%+ daily   | Completed / Created   |
| Habit stack adoption  | 40% of users | Users with 1+ stack   |
| 30-day retention lift | +15%         | Cohort analysis       |
| Habit streak avg      | 14+ days     | Average streak length |

---

## 2. Functional Requirements

### 2.1 Habit Types

| Type           | Description                    | Example                               |
| -------------- | ------------------------------ | ------------------------------------- |
| Anchor Habit   | Existing behavior to attach to | "After I pour my morning coffee..."   |
| Wellness Habit | MindFriend action to build     | "...I will do 2 minutes of breathing" |
| Routine        | Sequence of habits             | Morning: Breathe → Journal → Quest    |
| Micro-habit    | Tiny version of a larger habit | 1 deep breath instead of 5 minutes    |

### 2.2 Core Features

| ID    | Requirement                             | Priority |
| ----- | --------------------------------------- | -------- |
| HS-01 | Create habit stacks (anchor + behavior) | Must     |
| HS-02 | Track daily habit completion            | Must     |
| HS-03 | Visual habit tracker (calendar/grid)    | Must     |
| HS-04 | Streak tracking for each habit          | Must     |
| HS-05 | Smart reminders based on anchor time    | Must     |
| HS-06 | Pre-built routine templates             | Should   |
| HS-07 | Micro-habit suggestions for struggling  | Should   |
| HS-08 | Habit graduation (increase difficulty)  | Should   |
| HS-09 | Weekly habit review/reflection          | Should   |
| HS-10 | Habit sharing with accountability buddy | Could    |

### 2.3 Routine Builder

| ID    | Requirement                   | Priority |
| ----- | ----------------------------- | -------- |
| RB-01 | Morning routine template      | Must     |
| RB-02 | Evening wind-down routine     | Must     |
| RB-03 | Custom routine creation       | Should   |
| RB-04 | Reorder habits within routine | Should   |
| RB-05 | Skip individual habit option  | Must     |
| RB-06 | Routine duration estimate     | Should   |

---

## 3. Technical Requirements

### 3.1 Data Models

```sql
-- Habit definitions
CREATE TABLE habits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Habit details
    name TEXT NOT NULL,
    description TEXT,
    category TEXT, -- 'breathing', 'meditation', 'journaling', 'movement', 'custom'

    -- Habit stack
    anchor_text TEXT, -- "After I pour my morning coffee"
    behavior_text TEXT, -- "I will do 2 minutes of box breathing"

    -- Linked action (optional)
    linked_exercise_id UUID REFERENCES exercises(id),
    linked_action TEXT, -- 'mood_check', 'quest', 'journal', 'chat', null for custom

    -- Timing
    preferred_time TIME,
    reminder_enabled BOOLEAN DEFAULT true,
    reminder_minutes_before INTEGER DEFAULT 0,

    -- Progression
    current_level INTEGER DEFAULT 1, -- For habit graduation
    target_duration_seconds INTEGER DEFAULT 120, -- Start small

    -- Status
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Routines (collections of habits)
CREATE TABLE routines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    name TEXT NOT NULL,
    description TEXT,
    type TEXT DEFAULT 'custom', -- 'morning', 'evening', 'custom'

    -- Timing
    target_time TIME,
    reminder_enabled BOOLEAN DEFAULT true,

    -- Status
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Habits within routines (ordered)
CREATE TABLE routine_habits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    routine_id UUID NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
    habit_id UUID NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
    order_index INTEGER NOT NULL,

    UNIQUE(routine_id, habit_id),
    UNIQUE(routine_id, order_index)
);

-- Daily habit completions
CREATE TABLE habit_completions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    habit_id UUID NOT NULL REFERENCES habits(id) ON DELETE CASCADE,

    completed_date DATE NOT NULL DEFAULT CURRENT_DATE,
    completed_at TIMESTAMPTZ DEFAULT NOW(),

    -- Context
    within_routine BOOLEAN DEFAULT false,
    routine_id UUID REFERENCES routines(id),
    duration_seconds INTEGER,
    skipped BOOLEAN DEFAULT false,
    skip_reason TEXT,

    -- Streak tracking (denormalized for performance)
    current_streak INTEGER DEFAULT 1,

    UNIQUE(habit_id, completed_date)
);

-- Routine completions
CREATE TABLE routine_completions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    routine_id UUID NOT NULL REFERENCES routines(id) ON DELETE CASCADE,

    completed_date DATE NOT NULL DEFAULT CURRENT_DATE,
    completed_at TIMESTAMPTZ DEFAULT NOW(),

    -- Stats
    habits_completed INTEGER,
    habits_skipped INTEGER,
    total_duration_seconds INTEGER,

    UNIQUE(routine_id, completed_date)
);

-- Habit templates (pre-built suggestions)
CREATE TABLE habit_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL,

    anchor_text TEXT,
    behavior_text TEXT,
    linked_action TEXT,

    suggested_duration_seconds INTEGER,
    difficulty TEXT DEFAULT 'easy', -- 'easy', 'medium', 'hard'

    is_active BOOLEAN DEFAULT true
);

-- RLS
ALTER TABLE habits ENABLE ROW LEVEL SECURITY;
ALTER TABLE routines ENABLE ROW LEVEL SECURITY;
ALTER TABLE routine_habits ENABLE ROW LEVEL SECURITY;
ALTER TABLE habit_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE routine_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE habit_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own habits"
    ON habits FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users manage own routines"
    ON routines FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users access routine habits through routines"
    ON routine_habits FOR ALL
    USING (routine_id IN (SELECT id FROM routines WHERE user_id = auth.uid()));

CREATE POLICY "Users manage own completions"
    ON habit_completions FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users manage own routine completions"
    ON routine_completions FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Templates readable by all"
    ON habit_templates FOR SELECT USING (is_active = true);

-- Indexes
CREATE INDEX idx_completions_habit_date ON habit_completions(habit_id, completed_date DESC);
CREATE INDEX idx_completions_user_date ON habit_completions(user_id, completed_date DESC);
CREATE INDEX idx_routine_completions_date ON routine_completions(routine_id, completed_date DESC);
```

### 3.2 Swift Models

```swift
struct Habit: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let name: String
    let description: String?
    let category: HabitCategory

    // Habit stack
    let anchorText: String?
    let behaviorText: String?

    // Linked action
    let linkedExerciseId: UUID?
    let linkedAction: LinkedAction?

    // Timing
    let preferredTime: Date?
    let reminderEnabled: Bool
    let reminderMinutesBefore: Int

    // Progression
    let currentLevel: Int
    let targetDurationSeconds: Int

    let isActive: Bool
    let createdAt: Date
}

enum HabitCategory: String, Codable, CaseIterable {
    case breathing
    case meditation
    case journaling
    case movement
    case custom

    var icon: String {
        switch self {
        case .breathing: return "wind"
        case .meditation: return "brain.head.profile"
        case .journaling: return "book"
        case .movement: return "figure.walk"
        case .custom: return "sparkles"
        }
    }
}

enum LinkedAction: String, Codable {
    case moodCheck = "mood_check"
    case quest
    case journal
    case chat
}

struct Routine: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let name: String
    let description: String?
    let type: RoutineType
    let targetTime: Date?
    let reminderEnabled: Bool
    let isActive: Bool
    let createdAt: Date

    // Populated via join
    var habits: [Habit]?
}

enum RoutineType: String, Codable {
    case morning
    case evening
    case custom
}

struct HabitCompletion: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let habitId: UUID
    let completedDate: Date
    let completedAt: Date
    let withinRoutine: Bool
    let routineId: UUID?
    let durationSeconds: Int?
    let skipped: Bool
    let skipReason: String?
    let currentStreak: Int
}

struct HabitTemplate: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String?
    let category: HabitCategory
    let anchorText: String?
    let behaviorText: String?
    let linkedAction: LinkedAction?
    let suggestedDurationSeconds: Int?
    let difficulty: HabitDifficulty
}

enum HabitDifficulty: String, Codable {
    case easy
    case medium
    case hard
}
```

### 3.3 Habit Tracking Service

```swift
@MainActor
class HabitService: ObservableObject {
    private let supabase: SupabaseClient

    @Published var habits: [Habit] = []
    @Published var routines: [Routine] = []
    @Published var todayCompletions: [HabitCompletion] = []
    @Published var templates: [HabitTemplate] = []

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Habits

    func fetchHabits() async throws {
        let userId = try await supabase.auth.session.user.id

        habits = try await supabase
            .from("habits")
            .select()
            .eq("user_id", value: userId)
            .eq("is_active", value: true)
            .execute()
            .value
    }

    func createHabit(_ habit: CreateHabitRequest) async throws -> Habit {
        let userId = try await supabase.auth.session.user.id

        let newHabit: Habit = try await supabase
            .from("habits")
            .insert([
                "user_id": userId.uuidString,
                "name": habit.name,
                "description": habit.description as Any,
                "category": habit.category.rawValue,
                "anchor_text": habit.anchorText as Any,
                "behavior_text": habit.behaviorText as Any,
                "linked_action": habit.linkedAction?.rawValue as Any,
                "preferred_time": habit.preferredTime?.ISO8601Format() as Any,
                "target_duration_seconds": habit.targetDurationSeconds
            ])
            .select()
            .single()
            .execute()
            .value

        habits.append(newHabit)
        return newHabit
    }

    func createHabitFromTemplate(_ template: HabitTemplate) async throws -> Habit {
        let request = CreateHabitRequest(
            name: template.name,
            description: template.description,
            category: template.category,
            anchorText: template.anchorText,
            behaviorText: template.behaviorText,
            linkedAction: template.linkedAction,
            preferredTime: nil,
            targetDurationSeconds: template.suggestedDurationSeconds ?? 120
        )
        return try await createHabit(request)
    }

    // MARK: - Completions

    func completeHabit(
        _ habitId: UUID,
        duration: Int? = nil,
        routineId: UUID? = nil
    ) async throws {
        let userId = try await supabase.auth.session.user.id

        // Calculate streak
        let previousStreak = try await getCurrentStreak(habitId: habitId)
        let yesterdayCompleted = try await wasCompletedYesterday(habitId: habitId)
        let newStreak = yesterdayCompleted ? previousStreak + 1 : 1

        let completion: HabitCompletion = try await supabase
            .from("habit_completions")
            .insert([
                "user_id": userId.uuidString,
                "habit_id": habitId.uuidString,
                "within_routine": routineId != nil,
                "routine_id": routineId?.uuidString as Any,
                "duration_seconds": duration as Any,
                "current_streak": newStreak
            ])
            .select()
            .single()
            .execute()
            .value

        todayCompletions.append(completion)

        // Check for habit graduation
        if newStreak % 7 == 0 {
            await graduateHabit(habitId)
        }
    }

    func skipHabit(_ habitId: UUID, reason: String?) async throws {
        let userId = try await supabase.auth.session.user.id

        try await supabase
            .from("habit_completions")
            .insert([
                "user_id": userId.uuidString,
                "habit_id": habitId.uuidString,
                "skipped": true,
                "skip_reason": reason as Any,
                "current_streak": 0
            ])
            .execute()
    }

    private func getCurrentStreak(habitId: UUID) async throws -> Int {
        let completion: HabitCompletion? = try await supabase
            .from("habit_completions")
            .select()
            .eq("habit_id", value: habitId)
            .eq("skipped", value: false)
            .order("completed_date", ascending: false)
            .limit(1)
            .execute()
            .value
            .first

        return completion?.currentStreak ?? 0
    }

    private func wasCompletedYesterday(habitId: UUID) async throws -> Bool {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let dateString = ISO8601DateFormatter().string(from: yesterday).prefix(10)

        let count: Int = try await supabase
            .from("habit_completions")
            .select("id", head: true, count: .exact)
            .eq("habit_id", value: habitId)
            .eq("completed_date", value: String(dateString))
            .eq("skipped", value: false)
            .execute()
            .count ?? 0

        return count > 0
    }

    private func graduateHabit(_ habitId: UUID) async {
        // Increase difficulty/duration after consistent completion
        guard let habit = habits.first(where: { $0.id == habitId }) else { return }

        let newDuration = min(habit.targetDurationSeconds + 60, 600) // Cap at 10 min
        let newLevel = habit.currentLevel + 1

        do {
            try await supabase
                .from("habits")
                .update([
                    "current_level": newLevel,
                    "target_duration_seconds": newDuration
                ])
                .eq("id", value: habitId)
                .execute()

            // Update local state
            if let index = habits.firstIndex(where: { $0.id == habitId }) {
                // Refetch to get updated data
                try await fetchHabits()
            }
        } catch {
            print("Error graduating habit: \(error)")
        }
    }

    // MARK: - Routines

    func fetchRoutines() async throws {
        let userId = try await supabase.auth.session.user.id

        routines = try await supabase
            .from("routines")
            .select("""
                *,
                routine_habits (
                    order_index,
                    habits (*)
                )
            """)
            .eq("user_id", value: userId)
            .eq("is_active", value: true)
            .execute()
            .value
    }

    func completeRoutine(_ routineId: UUID, completedHabits: [UUID], skippedHabits: [UUID]) async throws {
        let userId = try await supabase.auth.session.user.id

        // Complete individual habits
        for habitId in completedHabits {
            try await completeHabit(habitId, routineId: routineId)
        }

        // Skip habits
        for habitId in skippedHabits {
            try await skipHabit(habitId, reason: "Skipped in routine")
        }

        // Record routine completion
        try await supabase
            .from("routine_completions")
            .insert([
                "user_id": userId.uuidString,
                "routine_id": routineId.uuidString,
                "habits_completed": completedHabits.count,
                "habits_skipped": skippedHabits.count
            ])
            .execute()
    }

    // MARK: - Templates

    func fetchTemplates() async throws {
        templates = try await supabase
            .from("habit_templates")
            .select()
            .eq("is_active", value: true)
            .execute()
            .value
    }

    // MARK: - Analytics

    func getWeeklyStats(habitId: UUID) async throws -> HabitWeeklyStats {
        let startOfWeek = Calendar.current.date(
            from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        )!

        let completions: [HabitCompletion] = try await supabase
            .from("habit_completions")
            .select()
            .eq("habit_id", value: habitId)
            .gte("completed_date", value: startOfWeek.ISO8601Format())
            .execute()
            .value

        let completedDays = completions.filter { !$0.skipped }.count
        let skippedDays = completions.filter { $0.skipped }.count

        return HabitWeeklyStats(
            habitId: habitId,
            completedDays: completedDays,
            skippedDays: skippedDays,
            completionRate: Double(completedDays) / 7.0
        )
    }
}

struct CreateHabitRequest {
    let name: String
    let description: String?
    let category: HabitCategory
    let anchorText: String?
    let behaviorText: String?
    let linkedAction: LinkedAction?
    let preferredTime: Date?
    let targetDurationSeconds: Int
}

struct HabitWeeklyStats {
    let habitId: UUID
    let completedDays: Int
    let skippedDays: Int
    let completionRate: Double
}
```

---

## 4. UI/UX Specifications

### 4.1 Habits Home

```
┌─────────────────────────────────┐
│ Habits                      +   │
├─────────────────────────────────┤
│                                 │
│ Morning Routine            7:00 │
│ ┌─────────────────────────────┐ │
│ │ ☀️ 3 habits • ~8 min        │ │
│ │ ████████████░░░ 2/3 done    │ │
│ │                [Continue →] │ │
│ └─────────────────────────────┘ │
│                                 │
│ Today's Habits                  │
│ ┌─────────────────────────────┐ │
│ │ ✓ 2-min breathing    🔥 14  │ │
│ │   After morning coffee      │ │
│ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │
│ │ ○ Gratitude journal  🔥 7   │ │
│ │   Before bed                │ │
│ │              [Do Now] [Skip]│ │
│ └─────────────────────────────┘ │
│                                 │
│ This Week                       │
│ ┌─────────────────────────────┐ │
│ │ M  T  W  T  F  S  S         │ │
│ │ ●  ●  ●  ●  ○  ○  ○         │ │
│ │         ↑ Today             │ │
│ └─────────────────────────────┘ │
│                                 │
│ [+ Add New Habit]               │
│                                 │
└─────────────────────────────────┘
```

### 4.2 Create Habit Stack

```
┌─────────────────────────────────┐
│ ← Create Habit Stack            │
├─────────────────────────────────┤
│                                 │
│ Build your habit stack          │
│                                 │
│ Step 1: Your Anchor             │
│ What existing habit will you    │
│ attach this to?                 │
│                                 │
│ After I...                      │
│ ┌─────────────────────────────┐ │
│ │ pour my morning coffee      │ │
│ └─────────────────────────────┘ │
│                                 │
│ Common anchors:                 │
│ [Wake up] [Brush teeth] [Lunch] │
│ [Get home] [Dinner] [Bed]       │
│                                 │
│ Step 2: Your New Habit          │
│ I will...                       │
│ ┌─────────────────────────────┐ │
│ │ do 2 minutes of breathing   │ │
│ └─────────────────────────────┘ │
│                                 │
│ Or choose from library:         │
│ [🫁 Breathing] [🧘 Meditation]  │
│ [📝 Journaling] [🏃 Movement]   │
│                                 │
│ Step 3: Start Small             │
│ Duration: [2 min ▼]             │
│                                 │
│ "After I pour my morning        │
│  coffee, I will do 2 minutes    │
│  of breathing."                 │
│                                 │
│         [Create Habit]          │
│                                 │
└─────────────────────────────────┘
```

### 4.3 Routine Flow

```
┌─────────────────────────────────┐
│ Morning Routine            1/3  │
├─────────────────────────────────┤
│                                 │
│ ┌─────────────────────────────┐ │
│ │                             │ │
│ │      🫁                     │ │
│ │                             │ │
│ │   Box Breathing             │ │
│ │   2 minutes                 │ │
│ │                             │ │
│ │   ┌───────────────────┐     │ │
│ │   │  Breathe in...    │     │ │
│ │   │       4           │     │ │
│ │   └───────────────────┘     │ │
│ │                             │ │
│ └─────────────────────────────┘ │
│                                 │
│ Next: Gratitude Journal         │
│                                 │
│    [Skip]        [Complete]     │
│                                 │
└─────────────────────────────────┘
```

---

## 5. Acceptance Criteria

- [ ] Users can create habit stacks with anchor + behavior
- [ ] Users can track daily habit completion
- [ ] Streaks are calculated and displayed correctly
- [ ] Morning/evening routine templates are available
- [ ] Users can create custom routines
- [ ] Habits graduate (increase difficulty) after 7-day streaks
- [ ] Skip option available with optional reason
- [ ] Weekly completion grid shows habit history

---

## 6. Pre-Built Templates

```sql
INSERT INTO habit_templates (name, description, category, anchor_text, behavior_text, linked_action, suggested_duration_seconds, difficulty) VALUES
-- Breathing
('Morning Breath', 'Start your day with clarity', 'breathing', 'After I wake up', 'I will do 1 minute of deep breathing', NULL, 60, 'easy'),
('Coffee Calm', 'Mindful moment with your coffee', 'breathing', 'After I pour my morning coffee', 'I will do box breathing for 2 minutes', NULL, 120, 'easy'),
('Stress Reset', 'Quick reset during work', 'breathing', 'When I feel stressed', 'I will do 4-7-8 breathing 3 times', NULL, 90, 'easy'),

-- Meditation
('Morning Mindfulness', 'Set intention for the day', 'meditation', 'After I brush my teeth', 'I will meditate for 5 minutes', NULL, 300, 'medium'),
('Lunch Reset', 'Midday mental refresh', 'meditation', 'After I finish lunch', 'I will do a body scan for 3 minutes', NULL, 180, 'easy'),

-- Journaling
('Gratitude Moment', 'End day with appreciation', 'journaling', 'Before I go to bed', 'I will write 3 things I''m grateful for', 'journal', 180, 'easy'),
('Morning Pages', 'Clear your mind', 'journaling', 'After my morning coffee', 'I will write for 5 minutes', 'journal', 300, 'medium'),

-- Movement
('Wake Up Stretch', 'Gentle morning movement', 'movement', 'After I get out of bed', 'I will stretch for 2 minutes', NULL, 120, 'easy'),
('Walk Break', 'Move your body', 'movement', 'After I finish a work task', 'I will walk for 5 minutes', NULL, 300, 'easy');
```

---

## 7. Rollout Plan

### Phase 1 (Week 1-2)

- Habit data model
- Basic habit creation and tracking
- Streak calculation

### Phase 2 (Week 3)

- Routine builder
- Pre-built templates
- Habit graduation system

### Phase 3 (Week 4)

- Smart reminders
- Weekly review
- Analytics dashboard
