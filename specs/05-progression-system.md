# Progression System Beyond Streaks

## Overview

**Goal:** Create a Duolingo-style progression system with XP, levels, skill trees, and seasonal events that gives users long-term goals beyond daily streaks.

**Why it matters:** Streaks work for daily engagement but plateau over time. Users need milestones to work towards, a sense of leveling up, and seasonal variety to stay engaged for months/years. Duolingo's progression is 90% of why people stay - MindFriend should learn from this.

**Impact:** P5 priority - Long-term retention

---

## User Stories

- As a user, I want to earn XP for activities so that I can see my progress quantified
- As a user, I want to level up so that I feel a sense of achievement
- As a user, I want to master specific exercise types so that I can track my skill development
- As a user, I want seasonal challenges so that the app feels fresh and time-limited events create urgency

---

## Product Requirements

### Must Have (MVP)

1. **XP System**
   - Quest completion: 50 XP
   - Exercise completion: 30 XP
   - Mood check-in: 10 XP
   - Circle check-in: 20 XP
   - XP visible on home screen

2. **Levels (1-50)**
   - Clear level thresholds (exponential curve)
   - Unique titles for each level tier
   - Level-up celebration animation
   - Level shown on profile

3. **Skill Trees (per exercise type)**
   - 5 skills: Breathing, Meditation, Grounding, Journaling, Movement
   - 5 levels per skill (Novice → Apprentice → Practitioner → Expert → Master)
   - Progress bar visible in exercise library

4. **Seasonal Events**
   - "30 Days of Gratitude" (November)
   - "New Year Mindfulness" (January)
   - "Spring Renewal" (April)
   - Limited-time badges
   - Event-specific quests

### Nice to Have (V2)

- XP multipliers for streaks
- Weekly XP challenges
- Leaderboards (opt-in)
- XP decay for inactivity
- Achievement showcases on profile
- Level-gated premium exercises

### Out of Scope

- Competitive rankings
- XP purchasing
- XP trading between users
- NFT badges

---

## Technical Design

### Data Model Changes

```sql
-- Migration: 20260119_progression_system.sql

-- Add XP and level to user_stats
ALTER TABLE user_stats ADD COLUMN xp_total INT DEFAULT 0;
ALTER TABLE user_stats ADD COLUMN xp_this_week INT DEFAULT 0;
ALTER TABLE user_stats ADD COLUMN level INT DEFAULT 1;
ALTER TABLE user_stats ADD COLUMN level_title TEXT DEFAULT 'Beginner';

-- Create level thresholds lookup
CREATE TABLE level_thresholds (
  level INT PRIMARY KEY,
  xp_required INT NOT NULL,
  title TEXT NOT NULL
);

-- Seed level data (exponential curve)
INSERT INTO level_thresholds (level, xp_required, title) VALUES
  (1, 0, 'Beginner'),
  (2, 100, 'Beginner'),
  (3, 250, 'Beginner'),
  (4, 450, 'Beginner'),
  (5, 700, 'Novice'),
  (6, 1000, 'Novice'),
  (7, 1350, 'Novice'),
  (8, 1750, 'Novice'),
  (9, 2200, 'Apprentice'),
  (10, 2700, 'Apprentice'),
  (11, 3250, 'Apprentice'),
  (12, 3850, 'Apprentice'),
  (13, 4500, 'Practitioner'),
  (14, 5200, 'Practitioner'),
  (15, 5950, 'Practitioner'),
  (16, 6750, 'Practitioner'),
  (17, 7600, 'Journeyer'),
  (18, 8500, 'Journeyer'),
  (19, 9450, 'Journeyer'),
  (20, 10450, 'Journeyer'),
  (21, 11500, 'Explorer'),
  (22, 12600, 'Explorer'),
  (23, 13750, 'Explorer'),
  (24, 14950, 'Explorer'),
  (25, 16200, 'Pathfinder'),
  (26, 17500, 'Pathfinder'),
  (27, 18850, 'Pathfinder'),
  (28, 20250, 'Pathfinder'),
  (29, 21700, 'Seeker'),
  (30, 23200, 'Seeker'),
  (31, 24750, 'Seeker'),
  (32, 26350, 'Seeker'),
  (33, 28000, 'Sage'),
  (34, 29700, 'Sage'),
  (35, 31450, 'Sage'),
  (36, 33250, 'Sage'),
  (37, 35100, 'Master'),
  (38, 37000, 'Master'),
  (39, 38950, 'Master'),
  (40, 40950, 'Master'),
  (41, 43000, 'Grandmaster'),
  (42, 45100, 'Grandmaster'),
  (43, 47250, 'Grandmaster'),
  (44, 49450, 'Grandmaster'),
  (45, 51700, 'Legend'),
  (46, 54000, 'Legend'),
  (47, 56350, 'Legend'),
  (48, 58750, 'Legend'),
  (49, 61200, 'Transcendent'),
  (50, 63700, 'Transcendent');

-- Skill progress per exercise type
CREATE TABLE skill_progress (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  skill_type TEXT NOT NULL CHECK (skill_type IN ('breathing', 'meditation', 'grounding', 'journaling', 'movement')),
  xp INT DEFAULT 0,
  level INT DEFAULT 1,
  exercises_completed INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, skill_type)
);

CREATE INDEX idx_skill_progress_user ON skill_progress(user_id);

-- Skill level thresholds
CREATE TABLE skill_thresholds (
  level INT PRIMARY KEY,
  xp_required INT NOT NULL,
  title TEXT NOT NULL
);

INSERT INTO skill_thresholds (level, xp_required, title) VALUES
  (1, 0, 'Novice'),
  (2, 150, 'Apprentice'),
  (3, 400, 'Practitioner'),
  (4, 800, 'Expert'),
  (5, 1500, 'Master');

-- Seasonal events
CREATE TABLE seasonal_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  event_type TEXT NOT NULL CHECK (event_type IN ('challenge', 'theme', 'special')),
  reward_badge_id UUID REFERENCES badges(id),
  target_count INT DEFAULT 30,  -- e.g., 30 days of gratitude
  xp_multiplier FLOAT DEFAULT 1.0,
  created_at TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT valid_event_dates CHECK (ends_at > starts_at)
);

CREATE INDEX idx_events_active ON seasonal_events(starts_at, ends_at);

-- User event participation
CREATE TABLE event_participation (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  event_id UUID NOT NULL REFERENCES seasonal_events(id) ON DELETE CASCADE,
  progress INT DEFAULT 0,
  completed_at TIMESTAMPTZ,
  joined_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, event_id)
);

CREATE INDEX idx_event_participation_user ON event_participation(user_id);

-- Seed initial seasonal events
INSERT INTO seasonal_events (name, description, starts_at, ends_at, event_type, target_count) VALUES
  ('30 Days of Gratitude', 'Complete a gratitude journal entry every day in November', '2026-11-01', '2026-11-30', 'challenge', 30),
  ('New Year Mindfulness', 'Start the year with daily meditation', '2027-01-01', '2027-01-31', 'challenge', 31),
  ('Spring Renewal', 'Focus on movement and outdoor activities', '2027-04-01', '2027-04-30', 'challenge', 30);

-- XP award function
CREATE OR REPLACE FUNCTION award_xp(
  p_user_id UUID,
  p_amount INT,
  p_activity_type TEXT,
  p_skill_type TEXT DEFAULT NULL
) RETURNS TABLE(new_xp INT, new_level INT, level_up BOOLEAN) AS $$
DECLARE
  v_current_xp INT;
  v_new_xp INT;
  v_current_level INT;
  v_new_level INT;
  v_level_changed BOOLEAN := FALSE;
BEGIN
  -- Get current stats
  SELECT xp_total, level INTO v_current_xp, v_current_level
  FROM user_stats WHERE user_id = p_user_id;

  IF v_current_xp IS NULL THEN
    v_current_xp := 0;
    v_current_level := 1;
  END IF;

  -- Add XP
  v_new_xp := v_current_xp + p_amount;

  -- Check for level up
  SELECT lt.level INTO v_new_level
  FROM level_thresholds lt
  WHERE lt.xp_required <= v_new_xp
  ORDER BY lt.level DESC
  LIMIT 1;

  v_level_changed := v_new_level > v_current_level;

  -- Update stats
  UPDATE user_stats
  SET xp_total = v_new_xp,
      xp_this_week = xp_this_week + p_amount,
      level = v_new_level,
      level_title = (SELECT title FROM level_thresholds WHERE level = v_new_level),
      updated_at = NOW()
  WHERE user_id = p_user_id;

  -- Update skill progress if applicable
  IF p_skill_type IS NOT NULL THEN
    INSERT INTO skill_progress (user_id, skill_type, xp, exercises_completed)
    VALUES (p_user_id, p_skill_type, p_amount, 1)
    ON CONFLICT (user_id, skill_type) DO UPDATE
    SET xp = skill_progress.xp + p_amount,
        exercises_completed = skill_progress.exercises_completed + 1,
        level = (SELECT st.level FROM skill_thresholds st WHERE st.xp_required <= skill_progress.xp + p_amount ORDER BY st.level DESC LIMIT 1),
        updated_at = NOW();
  END IF;

  RETURN QUERY SELECT v_new_xp, v_new_level, v_level_changed;
END;
$$ LANGUAGE plpgsql;

-- RLS Policies
ALTER TABLE skill_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE seasonal_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_participation ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users see own skill progress" ON skill_progress
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "All users see events" ON seasonal_events
  FOR SELECT USING (true);

CREATE POLICY "Users see own participation" ON event_participation
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can join events" ON event_participation
  FOR INSERT WITH CHECK (auth.uid() = user_id);
```

### iOS Implementation

**New Models** (`Core/Models.swift`):

```swift
struct UserLevel: Codable {
    let level: Int
    let title: String
    let currentXP: Int
    let nextLevelXP: Int
    let xpThisWeek: Int

    var progress: Double {
        guard nextLevelXP > 0 else { return 1.0 }
        return Double(currentXP) / Double(nextLevelXP)
    }

    var xpToNextLevel: Int {
        max(0, nextLevelXP - currentXP)
    }
}

struct SkillProgress: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let skillType: ExerciseType
    let xp: Int
    let level: Int
    let exercisesCompleted: Int

    var levelTitle: String {
        switch level {
        case 1: return "Novice"
        case 2: return "Apprentice"
        case 3: return "Practitioner"
        case 4: return "Expert"
        case 5: return "Master"
        default: return "Novice"
        }
    }

    var nextLevelXP: Int {
        switch level {
        case 1: return 150
        case 2: return 400
        case 3: return 800
        case 4: return 1500
        default: return 1500
        }
    }

    var progress: Double {
        let thresholds = [0, 150, 400, 800, 1500]
        let current = thresholds[min(level - 1, 4)]
        let next = thresholds[min(level, 4)]
        guard next > current else { return 1.0 }
        return Double(xp - current) / Double(next - current)
    }
}

struct SeasonalEvent: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String?
    let startsAt: Date
    let endsAt: Date
    let eventType: EventType
    let rewardBadgeId: UUID?
    let targetCount: Int
    let xpMultiplier: Double

    var isActive: Bool {
        let now = Date()
        return now >= startsAt && now <= endsAt
    }

    var daysRemaining: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: endsAt).day ?? 0
    }

    enum EventType: String, Codable {
        case challenge, theme, special
    }
}

struct EventParticipation: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let eventId: UUID
    let progress: Int
    let completedAt: Date?
    let joinedAt: Date

    var event: SeasonalEvent?

    var isCompleted: Bool {
        completedAt != nil
    }
}

struct XPAward {
    let amount: Int
    let newTotal: Int
    let newLevel: Int
    let leveledUp: Bool
}

enum XPActivity {
    case questComplete
    case exerciseComplete(ExerciseType)
    case moodCheckin
    case circleCheckin

    var xpAmount: Int {
        switch self {
        case .questComplete: return 50
        case .exerciseComplete: return 30
        case .moodCheckin: return 10
        case .circleCheckin: return 20
        }
    }
}
```

**Service Methods** (`Networking/Services/SupabaseDataService.swift`):

```swift
// MARK: - XP & Progression

func awardXP(activity: XPActivity) async throws -> XPAward {
    let userId = try await getCurrentUserId()
    let skillType: String? = {
        if case .exerciseComplete(let type) = activity {
            return type.rawValue
        }
        return nil
    }()

    let result: [[String: Any]] = try await supabase.rpc(
        "award_xp",
        params: [
            "p_user_id": userId,
            "p_amount": activity.xpAmount,
            "p_activity_type": String(describing: activity),
            "p_skill_type": skillType as Any
        ]
    ).execute().value

    guard let first = result.first else {
        throw AppError.apiError("XP award failed")
    }

    return XPAward(
        amount: activity.xpAmount,
        newTotal: first["new_xp"] as? Int ?? 0,
        newLevel: first["new_level"] as? Int ?? 1,
        leveledUp: first["level_up"] as? Bool ?? false
    )
}

func getUserLevel() async throws -> UserLevel {
    let userId = try await getCurrentUserId()

    let stats: UserStats = try await supabase
        .from("user_stats")
        .select()
        .eq("user_id", userId)
        .single()
        .execute()
        .value

    // Get next level threshold
    let thresholds: [LevelThreshold] = try await supabase
        .from("level_thresholds")
        .select()
        .gt("xp_required", stats.xpTotal)
        .order("level")
        .limit(1)
        .execute()
        .value

    let nextXP = thresholds.first?.xpRequired ?? stats.xpTotal

    return UserLevel(
        level: stats.level,
        title: stats.levelTitle,
        currentXP: stats.xpTotal,
        nextLevelXP: nextXP,
        xpThisWeek: stats.xpThisWeek
    )
}

func getSkillProgress() async throws -> [SkillProgress] {
    try await supabase
        .from("skill_progress")
        .select()
        .eq("user_id", try await getCurrentUserId())
        .execute()
        .value
}

func getActiveEvents() async throws -> [SeasonalEvent] {
    let now = Date().ISO8601Format()
    return try await supabase
        .from("seasonal_events")
        .select()
        .lte("starts_at", now)
        .gte("ends_at", now)
        .execute()
        .value
}

func joinEvent(id: UUID) async throws {
    try await supabase
        .from("event_participation")
        .insert(["user_id": try await getCurrentUserId(), "event_id": id])
        .execute()
}

func getEventParticipation() async throws -> [EventParticipation] {
    try await supabase
        .from("event_participation")
        .select("*, event:seasonal_events(*)")
        .eq("user_id", try await getCurrentUserId())
        .execute()
        .value
}
```

**New Views**:

```swift
// LevelProgressView.swift (Home screen widget)
struct LevelProgressView: View {
    let userLevel: UserLevel
    @State private var showLevelUp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Level \(userLevel.level)")
                    .font(.headline)
                Text(userLevel.title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(userLevel.currentXP) XP")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }

            ProgressView(value: userLevel.progress)
                .progressViewStyle(.linear)
                .tint(.accentColor)

            Text("\(userLevel.xpToNextLevel) XP to next level")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// SkillTreeView.swift
struct SkillTreeView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var skills: [SkillProgress] = []

    let allSkillTypes: [ExerciseType] = [.breathing, .meditation, .grounding, .journaling, .movement]

    var body: some View {
        List {
            ForEach(allSkillTypes, id: \.self) { type in
                let skill = skills.first { $0.skillType == type }
                SkillRow(type: type, progress: skill)
            }
        }
        .navigationTitle("Skills")
        .task { await loadSkills() }
    }

    func loadSkills() async {
        skills = (try? await container.supabaseDataService.getSkillProgress()) ?? []
    }
}

struct SkillRow: View {
    let type: ExerciseType
    let progress: SkillProgress?

    var body: some View {
        HStack {
            Image(systemName: type.icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 40)

            VStack(alignment: .leading) {
                Text(type.displayName)
                    .font(.headline)
                Text(progress?.levelTitle ?? "Novice")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let progress {
                VStack(alignment: .trailing) {
                    Text("Lv \(progress.level)")
                        .font(.headline)
                    ProgressView(value: progress.progress)
                        .frame(width: 60)
                }
            } else {
                Text("Not started")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// SeasonalEventCard.swift
struct SeasonalEventCard: View {
    let event: SeasonalEvent
    let participation: EventParticipation?
    let onJoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(event.name)
                        .font(.headline)
                    Text("\(event.daysRemaining) days left")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
            }

            if let desc = event.description {
                Text(desc)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let participation {
                HStack {
                    ProgressView(value: Double(participation.progress) / Double(event.targetCount))
                        .progressViewStyle(.linear)
                    Text("\(participation.progress)/\(event.targetCount)")
                        .font(.caption)
                }

                if participation.isCompleted {
                    Label("Completed!", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            } else {
                Button("Join Challenge", action: onJoin)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// LevelUpCelebration.swift (overlay)
struct LevelUpCelebration: View {
    let newLevel: Int
    let title: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("🎉")
                    .font(.system(size: 80))

                Text("LEVEL UP!")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Level \(newLevel)")
                    .font(.title)

                Text(title)
                    .font(.title2)
                    .foregroundColor(.secondary)

                Button("Continue", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .padding()
        }
    }
}
```

### Backend Integration

Integrate XP awards into existing completion flows:

```swift
// In quest completion
func completeQuest(id: UUID) async throws {
    try await supabase.from("quests")
        .update(["status": "completed", "completed_at": Date().ISO8601Format()])
        .eq("id", id)
        .execute()

    // Award XP
    let award = try await awardXP(activity: .questComplete)
    if award.leveledUp {
        // Show level up celebration
        await MainActor.run {
            container.appState.showLevelUp = true
            container.appState.newLevel = award.newLevel
        }
    }
}

// In exercise completion
func completeExercise(sessionId: UUID, type: ExerciseType) async throws {
    // ... existing completion logic ...

    let award = try await awardXP(activity: .exerciseComplete(type))
    // Handle level up
}
```

---

## UI/UX

### Home Screen with XP

```
┌─────────────────────────────────────┐
│  Welcome back, Danny!               │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────────┐│
│  │ Level 12 • Explorer             ││
│  │ ━━━━━━━━━━━━━━━░░░░  3,850 XP  ││
│  │ 650 XP to next level            ││
│  └─────────────────────────────────┘│
│                                     │
│  🔥 ACTIVE EVENT                    │
│  ┌─────────────────────────────────┐│
│  │ 30 Days of Gratitude      ⭐   ││
│  │ 18 days left                    ││
│  │ ━━━━━━━━━━━━░░░░░░  12/30      ││
│  └─────────────────────────────────┘│
│                                     │
│  📋 TODAY'S QUEST                   │
│  ...                                │
│                                     │
└─────────────────────────────────────┘
```

### Skills Screen

```
┌─────────────────────────────────────┐
│ < Profile         Skills            │
├─────────────────────────────────────┤
│                                     │
│  🌬️ Breathing                       │
│     Expert • Lv 4  ━━━━━━━━━░░ 720  │
│                                     │
│  🧘 Meditation                      │
│     Practitioner • Lv 3  ━━━━░░ 450 │
│                                     │
│  🌿 Grounding                       │
│     Apprentice • Lv 2  ━━░░░░ 200   │
│                                     │
│  📝 Journaling                      │
│     Novice • Lv 1  ━░░░░░░░░ 80     │
│                                     │
│  🏃 Movement                        │
│     Novice • Lv 1  ░░░░░░░░░ 30     │
│                                     │
└─────────────────────────────────────┘
```

---

## Verification

### Manual Testing

1. **XP Award:**
   - Complete quest → verify +50 XP
   - Complete exercise → verify +30 XP
   - Log mood → verify +10 XP
   - Post in circle → verify +20 XP

2. **Level Up:**
   - Accumulate enough XP to level
   - Verify level up celebration appears
   - Verify profile shows new level

3. **Skills:**
   - Complete breathing exercises
   - Verify breathing skill XP increases
   - Verify skill level increases at thresholds

4. **Events:**
   - Join seasonal event
   - Complete activities that count towards event
   - Verify progress increments
   - Verify badge awarded on completion

---

## Dependencies

- Quest completion tracking
- Exercise session tracking
- Mood logging
- Circle posting

---

## Risks & Mitigations

| Risk                         | Likelihood | Impact | Mitigation                                  |
| ---------------------------- | ---------- | ------ | ------------------------------------------- |
| Progression feels grindy     | Medium     | High   | Balanced XP curve, varied activities        |
| Events missed by users       | Medium     | Medium | Clear notifications, home screen visibility |
| XP inflation over time       | Low        | Medium | Fixed XP values, no multiplier stacking     |
| Level system feels arbitrary | Low        | Medium | Meaningful titles, clear milestones         |

---

## Implementation Estimate

| Task                            | Effort       |
| ------------------------------- | ------------ |
| Database migration              | 2 hours      |
| iOS Models                      | 2 hours      |
| XP award system                 | 3 hours      |
| Level progress UI               | 3 hours      |
| Skill tree UI                   | 3 hours      |
| Seasonal events                 | 4 hours      |
| Level up celebration            | 2 hours      |
| Integration with existing flows | 3 hours      |
| Testing                         | 3 hours      |
| **Total**                       | **25 hours** |
