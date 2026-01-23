# F008: Achievement Milestones System

## Overview

### Summary

Comprehensive achievement and milestone system with tiered badges, visual progression tracking, and celebratory moments that reward long-term engagement patterns.

### Business Value

- Drives long-term retention through visible progress
- Creates shareable moments for organic growth
- Provides premium conversion touchpoints at milestone celebrations

### User Benefit

- Clear sense of progress and accomplishment
- Recognition for wellness journey milestones
- Motivation through collectible badges and trophies

### Dependencies

- F007: Streak Shields Enhancement (for streak-based achievements)
- F006: Progress Narrative (for milestone story integration)

---

## Requirements

### Functional Requirements

| ID     | Requirement                                                                                        | Priority    |
| ------ | -------------------------------------------------------------------------------------------------- | ----------- |
| FR-001 | Track 50+ unique achievements across categories (streaks, exercises, social, exploration, special) | Must Have   |
| FR-002 | Badge tiers (Bronze, Silver, Gold, Diamond) for progressive achievements                           | Must Have   |
| FR-003 | Celebratory animation and haptic feedback on achievement unlock                                    | Must Have   |
| FR-004 | Achievement gallery view with locked/unlocked states and progress bars                             | Must Have   |
| FR-005 | Push notification for major milestone achievements                                                 | Should Have |
| FR-006 | Share achievement cards to social media                                                            | Should Have |
| FR-007 | Seasonal and limited-time achievements                                                             | Should Have |
| FR-008 | Achievement points (XP) contributing to user level                                                 | Must Have   |
| FR-009 | Hidden/secret achievements revealed only when unlocked                                             | Could Have  |
| FR-010 | Achievement leaderboard within circles                                                             | Could Have  |

### Non-Functional Requirements

| ID      | Requirement                  | Target                 |
| ------- | ---------------------------- | ---------------------- |
| NFR-001 | Achievement check latency    | < 100ms                |
| NFR-002 | Achievement unlock animation | 60fps                  |
| NFR-003 | Badge asset loading          | Preloaded/cached       |
| NFR-004 | Offline achievement display  | Full gallery available |

### Acceptance Criteria

```gherkin
Feature: Achievement System

Scenario: First badge unlock
  Given user has never completed a quest
  When user completes their first quest
  Then "First Step" achievement should unlock
  And celebratory animation should play
  And haptic feedback should trigger
  And notification banner should appear
  And XP should be awarded

Scenario: Tiered achievement progression
  Given user has Bronze "Consistent" badge (7-day streak)
  When user reaches 30-day streak
  Then Silver "Consistent" badge should unlock
  And Bronze badge should show "upgraded" state
  And additional XP bonus should be awarded

Scenario: View achievement gallery
  Given user has 15 unlocked achievements
  When user opens achievement gallery
  Then 15 achievements should show as unlocked with dates
  And remaining achievements should show locked with progress hints
  And achievements should be grouped by category
  And overall completion percentage should display

Scenario: Share achievement
  Given user just unlocked "30-Day Streak" achievement
  When user taps share button
  Then shareable card should be generated with badge art
  And share sheet should open with card image
  And privacy-safe content should be shared (no personal data)
```

---

## Technical Design

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    iOS Application                       │
├─────────────────────────────────────────────────────────┤
│  AchievementService                                     │
│  ├── Achievement evaluation engine                      │
│  ├── XP calculation and leveling                        │
│  └── Local achievement cache                            │
├─────────────────────────────────────────────────────────┤
│  AchievementViews                                       │
│  ├── AchievementGalleryView (grid display)              │
│  ├── AchievementUnlockOverlay (celebration)             │
│  ├── AchievementDetailSheet (badge info)                │
│  └── AchievementShareCard (social sharing)              │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              Supabase Edge Functions                     │
├─────────────────────────────────────────────────────────┤
│  check-achievements (event-driven)                      │
│  ├── Evaluate achievement criteria                      │
│  ├── Handle tier upgrades                               │
│  └── Calculate XP rewards                               │
├─────────────────────────────────────────────────────────┤
│  get-achievement-leaderboard                            │
│  └── Circle achievement rankings                        │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                  PostgreSQL Tables                       │
├─────────────────────────────────────────────────────────┤
│  achievement_definitions │ user_achievements │ xp_events │
└─────────────────────────────────────────────────────────┘
```

### Data Models

#### Database Schema

```sql
-- Achievement definitions (seeded data)
CREATE TABLE achievement_definitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN (
        'getting_started', 'streaks', 'exercises', 'social',
        'exploration', 'wellness', 'seasonal', 'special'
    )),
    tier TEXT CHECK (tier IN ('bronze', 'silver', 'gold', 'diamond')),
    parent_achievement_key TEXT REFERENCES achievement_definitions(key),
    xp_reward INTEGER NOT NULL DEFAULT 50,
    icon_name TEXT NOT NULL,
    badge_color TEXT NOT NULL,
    criteria JSONB NOT NULL,
    is_hidden BOOLEAN NOT NULL DEFAULT false,
    is_seasonal BOOLEAN NOT NULL DEFAULT false,
    available_from DATE,
    available_until DATE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- User earned achievements
CREATE TABLE user_achievements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    achievement_id UUID NOT NULL REFERENCES achievement_definitions(id),
    unlocked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    progress_snapshot JSONB,
    shared BOOLEAN NOT NULL DEFAULT false,
    viewed BOOLEAN NOT NULL DEFAULT false,
    UNIQUE(user_id, achievement_id)
);

-- Achievement progress tracking
CREATE TABLE achievement_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    achievement_id UUID NOT NULL REFERENCES achievement_definitions(id),
    current_value INTEGER NOT NULL DEFAULT 0,
    target_value INTEGER NOT NULL,
    last_updated TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, achievement_id)
);

-- XP and leveling
CREATE TABLE user_xp (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    total_xp INTEGER NOT NULL DEFAULT 0,
    current_level INTEGER NOT NULL DEFAULT 1,
    xp_to_next_level INTEGER NOT NULL DEFAULT 100,
    achievements_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- XP event log
CREATE TABLE xp_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    source_type TEXT NOT NULL CHECK (source_type IN (
        'achievement', 'quest', 'exercise', 'mood_log',
        'circle_post', 'streak_bonus', 'level_up'
    )),
    source_id UUID,
    xp_amount INTEGER NOT NULL,
    level_before INTEGER NOT NULL,
    level_after INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_achievement_defs_category ON achievement_definitions(category);
CREATE INDEX idx_achievement_defs_seasonal ON achievement_definitions(is_seasonal, available_from, available_until);
CREATE INDEX idx_user_achievements_user ON user_achievements(user_id);
CREATE INDEX idx_user_achievements_unlocked ON user_achievements(user_id, unlocked_at DESC);
CREATE INDEX idx_achievement_progress_user ON achievement_progress(user_id);
CREATE INDEX idx_user_xp_level ON user_xp(current_level DESC);
CREATE INDEX idx_xp_events_user ON xp_events(user_id, created_at DESC);

-- RLS Policies
ALTER TABLE achievement_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE achievement_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_xp ENABLE ROW LEVEL SECURITY;
ALTER TABLE xp_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view achievement definitions" ON achievement_definitions
    FOR SELECT USING (true);

CREATE POLICY "Users can view own achievements" ON user_achievements
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can view own progress" ON achievement_progress
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can view own XP" ON user_xp
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can view own XP events" ON xp_events
    FOR SELECT USING (auth.uid() = user_id);

-- Function to calculate level from XP
CREATE OR REPLACE FUNCTION calculate_level(xp INTEGER)
RETURNS INTEGER AS $$
DECLARE
    level INTEGER := 1;
    xp_threshold INTEGER := 100;
    remaining_xp INTEGER := xp;
BEGIN
    WHILE remaining_xp >= xp_threshold LOOP
        remaining_xp := remaining_xp - xp_threshold;
        level := level + 1;
        xp_threshold := FLOOR(xp_threshold * 1.2); -- 20% increase per level
    END LOOP;
    RETURN level;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
```

#### Achievement Seed Data

```sql
-- Getting Started achievements
INSERT INTO achievement_definitions (key, name, description, category, tier, xp_reward, icon_name, badge_color, criteria, sort_order) VALUES
('first_step', 'First Step', 'Complete your first quest', 'getting_started', NULL, 50, 'footprint', '#4CAF50', '{"type": "quest_count", "value": 1}', 1),
('mood_tracker', 'Mood Tracker', 'Log your first mood entry', 'getting_started', NULL, 25, 'heart.fill', '#E91E63', '{"type": "mood_count", "value": 1}', 2),
('deep_breather', 'Deep Breather', 'Complete your first exercise', 'getting_started', NULL, 25, 'wind', '#2196F3', '{"type": "exercise_count", "value": 1}', 3),
('circle_joiner', 'Circle Joiner', 'Join your first circle', 'getting_started', NULL, 50, 'person.2.fill', '#9C27B0', '{"type": "circle_joined", "value": 1}', 4),
('chat_starter', 'Chat Starter', 'Have your first AI conversation', 'getting_started', NULL, 25, 'bubble.left.fill', '#FF9800', '{"type": "chat_count", "value": 1}', 5);

-- Streak achievements (tiered)
INSERT INTO achievement_definitions (key, name, description, category, tier, xp_reward, icon_name, badge_color, criteria, sort_order) VALUES
('consistent_bronze', 'Consistent', 'Maintain a 7-day streak', 'streaks', 'bronze', 100, 'flame.fill', '#CD7F32', '{"type": "streak", "value": 7}', 10),
('consistent_silver', 'Consistent', 'Maintain a 30-day streak', 'streaks', 'silver', 250, 'flame.fill', '#C0C0C0', '{"type": "streak", "value": 30}', 11),
('consistent_gold', 'Consistent', 'Maintain a 100-day streak', 'streaks', 'gold', 500, 'flame.fill', '#FFD700', '{"type": "streak", "value": 100}', 12),
('consistent_diamond', 'Consistent', 'Maintain a 365-day streak', 'streaks', 'diamond', 1000, 'flame.fill', '#B9F2FF', '{"type": "streak", "value": 365}', 13);

UPDATE achievement_definitions SET parent_achievement_key = 'consistent_bronze' WHERE key = 'consistent_silver';
UPDATE achievement_definitions SET parent_achievement_key = 'consistent_silver' WHERE key = 'consistent_gold';
UPDATE achievement_definitions SET parent_achievement_key = 'consistent_gold' WHERE key = 'consistent_diamond';

-- Exercise achievements
INSERT INTO achievement_definitions (key, name, description, category, tier, xp_reward, icon_name, badge_color, criteria, sort_order) VALUES
('breath_master_bronze', 'Breath Master', 'Complete 10 breathing exercises', 'exercises', 'bronze', 75, 'lungs.fill', '#CD7F32', '{"type": "exercise_type_count", "exercise_type": "breathing", "value": 10}', 20),
('breath_master_silver', 'Breath Master', 'Complete 50 breathing exercises', 'exercises', 'silver', 150, 'lungs.fill', '#C0C0C0', '{"type": "exercise_type_count", "exercise_type": "breathing", "value": 50}', 21),
('mindfulness_guru_bronze', 'Mindfulness Guru', 'Complete 10 meditation sessions', 'exercises', 'bronze', 75, 'brain.head.profile', '#CD7F32', '{"type": "exercise_type_count", "exercise_type": "meditation", "value": 10}', 22),
('explorer', 'Exercise Explorer', 'Try all 5 exercise types', 'exercises', NULL, 100, 'compass', '#673AB7', '{"type": "exercise_types_tried", "value": 5}', 25);

-- Social achievements
INSERT INTO achievement_definitions (key, name, description, category, tier, xp_reward, icon_name, badge_color, criteria, sort_order) VALUES
('supportive_friend', 'Supportive Friend', 'React to 10 circle posts', 'social', NULL, 75, 'hand.thumbsup.fill', '#4CAF50', '{"type": "reactions_given", "value": 10}', 30),
('circle_creator', 'Circle Creator', 'Create your own circle', 'social', NULL, 100, 'plus.circle.fill', '#2196F3', '{"type": "circles_created", "value": 1}', 31),
('daily_sharer', 'Daily Sharer', 'Post 30 daily check-ins', 'social', NULL, 150, 'calendar.badge.checkmark', '#FF9800', '{"type": "circle_posts", "value": 30}', 32);

-- Special/Hidden achievements
INSERT INTO achievement_definitions (key, name, description, category, tier, xp_reward, icon_name, badge_color, criteria, is_hidden, sort_order) VALUES
('night_owl', 'Night Owl', 'Complete 5 exercises after 10 PM', 'special', NULL, 50, 'moon.fill', '#673AB7', '{"type": "late_night_exercises", "value": 5}', true, 50),
('early_bird', 'Early Bird', 'Complete 5 exercises before 6 AM', 'special', NULL, 50, 'sunrise.fill', '#FFC107', '{"type": "early_morning_exercises", "value": 5}', true, 51),
('comeback_kid', 'Comeback Kid', 'Return after 30+ days away', 'special', NULL, 100, 'arrow.uturn.up.circle.fill', '#4CAF50', '{"type": "return_after_absence", "value": 30}', true, 52);
```

#### Swift Models

```swift
// MARK: - Achievement Models

struct AchievementDefinition: Codable, Identifiable {
    let id: UUID
    let key: String
    let name: String
    let description: String
    let category: AchievementCategory
    let tier: AchievementTier?
    let parentAchievementKey: String?
    let xpReward: Int
    let iconName: String
    let badgeColor: String
    let criteria: AchievementCriteria
    let isHidden: Bool
    let isSeasonal: Bool
    let availableFrom: Date?
    let availableUntil: Date?
    let sortOrder: Int
}

enum AchievementCategory: String, Codable, CaseIterable {
    case gettingStarted = "getting_started"
    case streaks
    case exercises
    case social
    case exploration
    case wellness
    case seasonal
    case special

    var displayName: String {
        switch self {
        case .gettingStarted: return "Getting Started"
        case .streaks: return "Streaks"
        case .exercises: return "Exercises"
        case .social: return "Social"
        case .exploration: return "Exploration"
        case .wellness: return "Wellness"
        case .seasonal: return "Seasonal"
        case .special: return "Special"
        }
    }

    var iconName: String {
        switch self {
        case .gettingStarted: return "star.fill"
        case .streaks: return "flame.fill"
        case .exercises: return "figure.mind.and.body"
        case .social: return "person.2.fill"
        case .exploration: return "map.fill"
        case .wellness: return "heart.fill"
        case .seasonal: return "gift.fill"
        case .special: return "sparkles"
        }
    }
}

enum AchievementTier: String, Codable, CaseIterable {
    case bronze
    case silver
    case gold
    case diamond

    var displayName: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .bronze: return Color(hex: "#CD7F32")
        case .silver: return Color(hex: "#C0C0C0")
        case .gold: return Color(hex: "#FFD700")
        case .diamond: return Color(hex: "#B9F2FF")
        }
    }

    var nextTier: AchievementTier? {
        switch self {
        case .bronze: return .silver
        case .silver: return .gold
        case .gold: return .diamond
        case .diamond: return nil
        }
    }
}

struct AchievementCriteria: Codable {
    let type: String
    let value: Int
    let exerciseType: String?

    enum CodingKeys: String, CodingKey {
        case type
        case value
        case exerciseType = "exercise_type"
    }
}

struct UserAchievement: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let achievementId: UUID
    let unlockedAt: Date
    let progressSnapshot: [String: AnyCodable]?
    var shared: Bool
    var viewed: Bool

    // Joined data
    var definition: AchievementDefinition?
}

struct AchievementProgress: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let achievementId: UUID
    var currentValue: Int
    let targetValue: Int
    let lastUpdated: Date

    var progressPercentage: Double {
        Double(currentValue) / Double(targetValue)
    }

    var isComplete: Bool {
        currentValue >= targetValue
    }
}

struct UserXP: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var totalXP: Int
    var currentLevel: Int
    var xpToNextLevel: Int
    var achievementsCount: Int

    var levelProgress: Double {
        let xpForCurrentLevel = calculateXPForLevel(currentLevel)
        let xpIntoLevel = totalXP - xpForCurrentLevel
        return Double(xpIntoLevel) / Double(xpToNextLevel)
    }

    private func calculateXPForLevel(_ level: Int) -> Int {
        var total = 0
        var threshold = 100
        for _ in 1..<level {
            total += threshold
            threshold = Int(Double(threshold) * 1.2)
        }
        return total
    }
}

struct XPEvent: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let sourceType: XPSourceType
    let sourceId: UUID?
    let xpAmount: Int
    let levelBefore: Int
    let levelAfter: Int
    let createdAt: Date
}

enum XPSourceType: String, Codable {
    case achievement
    case quest
    case exercise
    case moodLog = "mood_log"
    case circlePost = "circle_post"
    case streakBonus = "streak_bonus"
    case levelUp = "level_up"
}

// MARK: - Display Models

struct AchievementDisplayItem: Identifiable {
    let id: UUID
    let definition: AchievementDefinition
    let userAchievement: UserAchievement?
    let progress: AchievementProgress?

    var isUnlocked: Bool { userAchievement != nil }
    var isNew: Bool { userAchievement?.viewed == false }

    var displayState: AchievementDisplayState {
        if isUnlocked { return .unlocked }
        if let progress = progress, progress.progressPercentage > 0 {
            return .inProgress(progress.progressPercentage)
        }
        return .locked
    }
}

enum AchievementDisplayState {
    case locked
    case inProgress(Double)
    case unlocked
}
```

### API Contracts

#### Get All Achievements

```
GET /rest/v1/achievement_definitions?order=sort_order

Response 200:
[
  {
    "id": "uuid",
    "key": "first_step",
    "name": "First Step",
    "description": "Complete your first quest",
    "category": "getting_started",
    "tier": null,
    "xp_reward": 50,
    "icon_name": "footprint",
    "badge_color": "#4CAF50",
    "criteria": {"type": "quest_count", "value": 1},
    "is_hidden": false
  }
]
```

#### Get User Achievements

```
GET /rest/v1/user_achievements?user_id=eq.{userId}&select=*,achievement:achievement_definitions(*)

Response 200:
[
  {
    "id": "uuid",
    "achievement_id": "uuid",
    "unlocked_at": "2024-01-15T10:30:00Z",
    "viewed": false,
    "achievement": {
      "key": "first_step",
      "name": "First Step",
      ...
    }
  }
]
```

#### Check Achievements (Edge Function)

```
POST /functions/v1/check-achievements

Request:
{
  "trigger": "quest_completed",
  "data": {
    "questId": "uuid"
  }
}

Response 200:
{
  "achievements_unlocked": [
    {
      "key": "first_step",
      "name": "First Step",
      "xp_reward": 50,
      "tier": null
    }
  ],
  "xp_gained": 50,
  "level_up": false,
  "new_level": 1
}
```

#### Get User XP & Level

```
GET /rest/v1/user_xp?user_id=eq.{userId}

Response 200:
{
  "total_xp": 1250,
  "current_level": 8,
  "xp_to_next_level": 215,
  "achievements_count": 12
}
```

---

## Implementation Details

### Step-by-Step Approach

1. **Database Setup**
   - Create migrations for achievement tables
   - Seed achievement definitions
   - Create user_xp row on signup (trigger)

2. **Achievement Engine**
   - Event-driven checking (quest complete, mood log, etc.)
   - Criteria evaluation based on type
   - Tier upgrade handling
   - XP award and level calculation

3. **iOS Service Layer**
   - Load and cache achievement definitions
   - Track local achievement progress
   - Handle unlock celebrations
   - Sync viewed state

4. **UI Components**
   - Achievement gallery with categories
   - Unlock overlay with animation
   - Progress indicators
   - Share card generation

5. **Notifications**
   - Push notification on major achievements
   - In-app notification banner
   - Badge count on profile tab

### File Structure

```
apps/ios/MindFriendApp/
├── Features/
│   └── Achievements/
│       ├── AchievementService.swift
│       ├── AchievementGalleryView.swift
│       ├── AchievementCategoryView.swift
│       ├── AchievementDetailSheet.swift
│       ├── AchievementUnlockOverlay.swift
│       ├── AchievementShareCard.swift
│       ├── XPProgressView.swift
│       └── Components/
│           ├── AchievementBadge.swift
│           ├── TieredBadgeView.swift
│           └── ProgressRing.swift
│
supabase/
├── functions/
│   ├── check-achievements/
│   └── get-achievement-leaderboard/
├── migrations/
│   └── YYYYMMDD_achievements.sql
```

### Key Algorithms

#### Achievement Check Engine (TypeScript)

```typescript
interface AchievementTrigger {
  type:
    | "quest_completed"
    | "mood_logged"
    | "exercise_completed"
    | "circle_joined"
    | "circle_posted"
    | "chat_sent"
    | "streak_updated";
  data: Record<string, any>;
}

async function checkAchievements(
  supabase: SupabaseClient,
  userId: string,
  trigger: AchievementTrigger,
): Promise<{
  achievementsUnlocked: AchievementDefinition[];
  xpGained: number;
  levelUp: boolean;
  newLevel: number;
}> {
  const results = {
    achievementsUnlocked: [] as AchievementDefinition[],
    xpGained: 0,
    levelUp: false,
    newLevel: 0,
  };

  // Get all achievement definitions
  const { data: definitions } = await supabase
    .from("achievement_definitions")
    .select("*")
    .eq("is_seasonal", false)
    .or(
      `available_from.is.null,available_from.lte.${new Date().toISOString()}`,
    );

  // Get user's current achievements
  const { data: userAchievements } = await supabase
    .from("user_achievements")
    .select("achievement_id")
    .eq("user_id", userId);

  const earnedIds = new Set(
    userAchievements?.map((a) => a.achievement_id) || [],
  );

  // Check each unearnened achievement
  for (const def of definitions || []) {
    if (earnedIds.has(def.id)) continue;
    if (def.is_hidden && !shouldCheckHidden(trigger, def)) continue;

    const criteria = def.criteria as AchievementCriteria;
    const earned = await evaluateCriteria(supabase, userId, criteria, trigger);

    if (earned) {
      // Check tier prerequisites
      if (def.parent_achievement_key) {
        const parent = definitions?.find(
          (d) => d.key === def.parent_achievement_key,
        );
        if (parent && !earnedIds.has(parent.id)) continue;
      }

      // Award achievement
      await supabase.from("user_achievements").insert({
        user_id: userId,
        achievement_id: def.id,
        progress_snapshot: await getProgressSnapshot(
          supabase,
          userId,
          criteria,
        ),
      });

      results.achievementsUnlocked.push(def);
      results.xpGained += def.xp_reward;
      earnedIds.add(def.id);
    }
  }

  // Award XP and check level up
  if (results.xpGained > 0) {
    const levelResult = await awardXP(
      supabase,
      userId,
      results.xpGained,
      "achievement",
    );
    results.levelUp = levelResult.levelUp;
    results.newLevel = levelResult.newLevel;
  }

  return results;
}

async function evaluateCriteria(
  supabase: SupabaseClient,
  userId: string,
  criteria: AchievementCriteria,
  trigger: AchievementTrigger,
): Promise<boolean> {
  switch (criteria.type) {
    case "quest_count": {
      const { count } = await supabase
        .from("quests")
        .select("*", { count: "exact", head: true })
        .eq("user_id", userId)
        .eq("completed", true);
      return (count || 0) >= criteria.value;
    }

    case "mood_count": {
      const { count } = await supabase
        .from("moods")
        .select("*", { count: "exact", head: true })
        .eq("user_id", userId);
      return (count || 0) >= criteria.value;
    }

    case "streak": {
      const { data: profile } = await supabase
        .from("profiles")
        .select("current_streak")
        .eq("id", userId)
        .single();
      return (profile?.current_streak || 0) >= criteria.value;
    }

    case "exercise_type_count": {
      const { count } = await supabase
        .from("exercise_sessions")
        .select("*, exercise:exercises!inner(type)", {
          count: "exact",
          head: true,
        })
        .eq("user_id", userId)
        .eq("exercise.type", criteria.exercise_type);
      return (count || 0) >= criteria.value;
    }

    case "exercise_types_tried": {
      const { data } = await supabase
        .from("exercise_sessions")
        .select("exercise:exercises(type)")
        .eq("user_id", userId);
      const types = new Set(data?.map((s) => s.exercise?.type).filter(Boolean));
      return types.size >= criteria.value;
    }

    // ... more criteria types

    default:
      return false;
  }
}

async function awardXP(
  supabase: SupabaseClient,
  userId: string,
  amount: number,
  source: string,
  sourceId?: string,
): Promise<{ levelUp: boolean; newLevel: number }> {
  const { data: userXP } = await supabase
    .from("user_xp")
    .select("*")
    .eq("user_id", userId)
    .single();

  const oldLevel = userXP?.current_level || 1;
  const newTotalXP = (userXP?.total_xp || 0) + amount;
  const newLevel = calculateLevel(newTotalXP);
  const xpToNext = calculateXPForNextLevel(newLevel);

  await supabase.from("user_xp").upsert({
    user_id: userId,
    total_xp: newTotalXP,
    current_level: newLevel,
    xp_to_next_level: xpToNext,
    achievements_count:
      (userXP?.achievements_count || 0) + (source === "achievement" ? 1 : 0),
    updated_at: new Date().toISOString(),
  });

  await supabase.from("xp_events").insert({
    user_id: userId,
    source_type: source,
    source_id: sourceId,
    xp_amount: amount,
    level_before: oldLevel,
    level_after: newLevel,
  });

  return {
    levelUp: newLevel > oldLevel,
    newLevel,
  };
}

function calculateLevel(totalXP: number): number {
  let level = 1;
  let threshold = 100;
  let remaining = totalXP;

  while (remaining >= threshold) {
    remaining -= threshold;
    level++;
    threshold = Math.floor(threshold * 1.2);
  }

  return level;
}
```

#### Celebration Animation (SwiftUI)

```swift
struct AchievementUnlockOverlay: View {
    let achievement: AchievementDefinition
    let onDismiss: () -> Void

    @State private var showBadge = false
    @State private var showText = false
    @State private var showParticles = false
    @State private var badgeScale: CGFloat = 0.3

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 24) {
                // Particle burst
                if showParticles {
                    ParticleEmitter(
                        color: Color(hex: achievement.badgeColor),
                        particleCount: 50
                    )
                }

                // Badge
                if showBadge {
                    AchievementBadge(
                        iconName: achievement.iconName,
                        color: Color(hex: achievement.badgeColor),
                        tier: achievement.tier
                    )
                    .scaleEffect(badgeScale)
                }

                // Text
                if showText {
                    VStack(spacing: 8) {
                        Text("Achievement Unlocked!")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text(achievement.name)
                            .font(.title.bold())
                            .foregroundColor(.primary)

                        Text(achievement.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        HStack {
                            Image(systemName: "sparkles")
                            Text("+\(achievement.xpReward) XP")
                                .font(.headline)
                        }
                        .foregroundColor(.yellow)
                        .padding(.top, 8)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(32)
        }
        .onAppear {
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Staggered animation
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                showBadge = true
                badgeScale = 1.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring()) {
                    showParticles = true
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showText = true
                }
            }
        }
    }
}
```

---

## Dependencies

### Internal Dependencies

- **F007 Streak Shields**: For streak-based achievement criteria
- **F006 Progress Narrative**: For milestone story integration
- **Existing badge system**: Migrate/extend current badges table

### External Dependencies

- None (uses existing Supabase infrastructure)

### Infrastructure Requirements

- None additional

---

## Edge Cases & Error Handling

| Scenario                            | Handling                                    |
| ----------------------------------- | ------------------------------------------- |
| Achievement unlocked offline        | Queue locally, sync on reconnect            |
| Duplicate unlock attempt            | UNIQUE constraint prevents; return existing |
| Seasonal achievement expired        | Filter by available_until date              |
| Hidden achievement partial progress | Don't show progress until unlocked          |
| Level calculation overflow          | Cap at level 999                            |
| Parent achievement not earned       | Skip child tier achievements                |
| XP award during network failure     | Retry with exponential backoff              |
| Multiple achievements at once       | Show unlock queue, one at a time            |

---

## Testing Requirements

### Unit Tests

```swift
// AchievementServiceTests.swift

func testQuestCountCriteriaEvaluation() async throws {
    let service = AchievementService(supabase: mockSupabase)
    mockSupabase.setCompletedQuestCount(1)

    let criteria = AchievementCriteria(type: "quest_count", value: 1, exerciseType: nil)
    let result = try await service.evaluateCriteria(criteria)

    XCTAssertTrue(result)
}

func testTierUpgrade() async throws {
    let service = AchievementService(supabase: mockSupabase)
    mockSupabase.setCurrentStreak(30)
    mockSupabase.setEarnedAchievements(["consistent_bronze"])

    let unlocked = try await service.checkAchievements(trigger: .streakUpdated)

    XCTAssertTrue(unlocked.contains { $0.key == "consistent_silver" })
}

func testXPLevelCalculation() {
    XCTAssertEqual(calculateLevel(0), 1)
    XCTAssertEqual(calculateLevel(100), 2)
    XCTAssertEqual(calculateLevel(220), 3) // 100 + 120
    XCTAssertEqual(calculateLevel(364), 4) // 100 + 120 + 144
}

func testHiddenAchievementNotShownInProgress() async throws {
    let service = AchievementService(supabase: mockSupabase)

    let displayItems = try await service.getAchievementDisplayItems()
    let hiddenItems = displayItems.filter { $0.definition.isHidden && !$0.isUnlocked }

    XCTAssertTrue(hiddenItems.isEmpty)
}

func testSeasonalAchievementAvailability() async throws {
    let service = AchievementService(supabase: mockSupabase)

    // Set current date to outside seasonal window
    mockSupabase.setSeasonalAchievement(
        availableFrom: Date().addingTimeInterval(86400),
        availableUntil: Date().addingTimeInterval(86400 * 30)
    )

    let available = try await service.getAvailableAchievements()

    XCTAssertFalse(available.contains { $0.isSeasonal })
}
```

### Integration Tests

```typescript
// supabase/functions/check-achievements/test.ts

Deno.test("first quest unlocks First Step achievement", async () => {
  const userId = await createTestUser();
  await completeQuest(userId);

  const result = await invokeFunction(
    "check-achievements",
    {
      trigger: "quest_completed",
      data: {},
    },
    userId,
  );

  assertEquals(result.achievements_unlocked.length, 1);
  assertEquals(result.achievements_unlocked[0].key, "first_step");
  assertEquals(result.xp_gained, 50);
});

Deno.test("tier upgrade requires parent achievement", async () => {
  const userId = await createTestUser();
  await setStreak(userId, 30);
  // Note: Bronze achievement not earned

  const result = await invokeFunction(
    "check-achievements",
    {
      trigger: "streak_updated",
      data: { streak: 30 },
    },
    userId,
  );

  // Should unlock bronze, not silver
  assertEquals(result.achievements_unlocked.length, 1);
  assertEquals(result.achievements_unlocked[0].tier, "bronze");
});

Deno.test("level up triggers on XP threshold", async () => {
  const userId = await createTestUser();
  await setUserXP(userId, 95); // 5 XP from level 2

  const result = await invokeFunction(
    "check-achievements",
    {
      trigger: "quest_completed",
      data: {},
    },
    userId,
  );

  assertEquals(result.level_up, true);
  assertEquals(result.new_level, 2);
});
```

### UI Tests

```swift
func testAchievementGalleryCategories() {
    let achievements = MockData.achievements
    let view = AchievementGalleryView(achievements: achievements)

    let rendered = try view.inspect()

    XCTAssertEqual(
        rendered.findAll(AchievementCategoryView.self).count,
        AchievementCategory.allCases.count
    )
}

func testUnlockAnimationSequence() async {
    let achievement = MockData.firstStepAchievement
    let view = AchievementUnlockOverlay(achievement: achievement, onDismiss: {})

    let rendered = try view.inspect()

    // Initially hidden
    XCTAssertFalse(rendered.find(AchievementBadge.self).exists)

    // After animation delay
    try await Task.sleep(nanoseconds: 600_000_000) // 0.6s

    XCTAssertTrue(rendered.find(AchievementBadge.self).exists)
    XCTAssertTrue(rendered.find(text: "Achievement Unlocked!").exists)
}
```
