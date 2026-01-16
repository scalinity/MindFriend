# Dynamic Quest Difficulty & Choice

## Overview

**Goal:** Give users agency over their daily wellness practice by allowing them to choose between quest options, adjust difficulty, and reroll for different activities.

**Why it matters:** One-size-fits-all quests lead to disengagement when the daily assignment doesn't match the user's energy, time, or mood. Choice architecture keeps the experience fresh while maintaining the simplicity of a daily habit. Users who feel in control of their practice are 40% more likely to maintain long-term engagement.

**Impact:** P3 priority - Increases quest completion rate and satisfaction

---

## User Stories

- As a busy user, I want a quick version of today's quest so that I can maintain my streak even on hectic days
- As an engaged user, I want to choose from different quest types so that my practice stays fresh
- As a user having a tough day, I want easier options so that I don't feel overwhelmed
- As a premium user, I want more quest choices so that I have maximum flexibility

---

## Product Requirements

### Must Have (MVP)

1. **Quest Variants Display**
   - Show assigned quest as "Recommended for you"
   - Offer 2 alternatives below:
     - "Quick version" (same type, 3-5 min instead of 10-15 min)
     - "Different focus" (different quest type entirely)
   - Clear visual distinction between recommended and alternatives

2. **Daily Reroll**
   - Free users: 1 free reroll per day
   - Premium users: Unlimited rerolls
   - Reroll generates new quest from same difficulty pool
   - Reroll button with remaining count indicator
   - Animation showing new quest appearing

3. **Quest Preference Learning**
   - Track which quest types user completes vs skips
   - Track ratings given after completion
   - Weight future recommendations toward preferred types
   - Store preferences in `user_quest_preferences` table

4. **Quick Quest Option**
   - Always available as alternative to full quest
   - Reduced XP reward (50% of full quest)
   - Counts toward streak
   - Limited steps (2-3 vs 4-6)
   - Clear "Quick" badge on selection

### Nice to Have (V2)

- Time-of-day recommendations (energizing AM, calming PM)
- "Surprise me" random quest option
- Quest scheduling (pick tomorrow's quest today)
- Difficulty progression (auto-increase as user levels up)
- Quest filtering by equipment/location needed
- Friend's quest recommendations

### Out of Scope

- Creating custom quests
- Quest marketplace
- AI-generated personalized quests
- Quest difficulty ratings beyond simple/quick

---

## Technical Design

### Data Model Changes

```sql
-- Migration: 20260118_quest_choice.sql

-- Quest preference tracking
CREATE TABLE user_quest_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  quest_type TEXT NOT NULL, -- breathing, meditation, journaling, etc.
  completion_count INT DEFAULT 0,
  skip_count INT DEFAULT 0,
  total_rating_sum INT DEFAULT 0,
  rating_count INT DEFAULT 0,
  last_completed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, quest_type)
);

CREATE INDEX idx_quest_prefs_user ON user_quest_preferences(user_id);

-- Quest alternatives (generated daily)
CREATE TABLE quest_alternatives (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  quest_date DATE NOT NULL,
  primary_quest_id UUID REFERENCES quest_templates(id),
  quick_quest_id UUID REFERENCES quest_templates(id),
  alt_quest_id UUID REFERENCES quest_templates(id),
  rerolls_used INT DEFAULT 0,
  rerolls_max INT DEFAULT 1,
  selected_variant TEXT DEFAULT 'primary', -- primary, quick, alt, reroll
  created_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, quest_date)
);

CREATE INDEX idx_quest_alts_user_date ON quest_alternatives(user_id, quest_date);

-- Quick quest variants table
CREATE TABLE quest_quick_variants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_template_id UUID NOT NULL REFERENCES quest_templates(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  steps JSONB NOT NULL, -- Reduced steps
  estimated_minutes INT NOT NULL CHECK (estimated_minutes <= 5),
  xp_multiplier FLOAT DEFAULT 0.5,

  UNIQUE(parent_template_id)
);

-- Reroll history for analytics
CREATE TABLE quest_reroll_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  quest_date DATE NOT NULL,
  from_quest_id UUID REFERENCES quest_templates(id),
  to_quest_id UUID REFERENCES quest_templates(id),
  reroll_number INT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_reroll_user ON quest_reroll_history(user_id, quest_date);

-- RLS
ALTER TABLE user_quest_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE quest_alternatives ENABLE ROW LEVEL SECURITY;
ALTER TABLE quest_quick_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE quest_reroll_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own preferences" ON user_quest_preferences
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users see own alternatives" ON quest_alternatives
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Anyone can read quick variants" ON quest_quick_variants
  FOR SELECT USING (true);

CREATE POLICY "Users see own reroll history" ON quest_reroll_history
  FOR SELECT USING (auth.uid() = user_id);

-- Function to get weighted quest selection
CREATE OR REPLACE FUNCTION get_weighted_quest_for_user(
  p_user_id UUID,
  p_exclude_type TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
  v_quest_id UUID;
BEGIN
  -- Get quest weighted by user preferences
  SELECT qt.id INTO v_quest_id
  FROM quest_templates qt
  LEFT JOIN user_quest_preferences uqp
    ON uqp.user_id = p_user_id AND uqp.quest_type = qt.type
  WHERE qt.is_active = TRUE
    AND (p_exclude_type IS NULL OR qt.type != p_exclude_type)
  ORDER BY
    -- Prefer types with higher completion rates
    COALESCE(uqp.completion_count::float / NULLIF(uqp.completion_count + uqp.skip_count, 0), 0.5) DESC,
    -- Prefer types with higher ratings
    COALESCE(uqp.total_rating_sum::float / NULLIF(uqp.rating_count, 0), 3) DESC,
    -- Add randomness
    RANDOM()
  LIMIT 1;

  RETURN v_quest_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to generate daily alternatives
CREATE OR REPLACE FUNCTION generate_quest_alternatives(p_user_id UUID, p_date DATE)
RETURNS quest_alternatives AS $$
DECLARE
  v_primary UUID;
  v_quick UUID;
  v_alt UUID;
  v_result quest_alternatives;
  v_is_premium BOOLEAN;
BEGIN
  -- Check if already generated
  SELECT * INTO v_result FROM quest_alternatives
  WHERE user_id = p_user_id AND quest_date = p_date;

  IF FOUND THEN RETURN v_result; END IF;

  -- Check premium status for reroll limit
  SELECT EXISTS (
    SELECT 1 FROM subscriptions
    WHERE user_id = p_user_id AND status = 'active'
  ) INTO v_is_premium;

  -- Get primary quest (weighted by preferences)
  v_primary := get_weighted_quest_for_user(p_user_id);

  -- Get quick variant of primary
  SELECT id INTO v_quick FROM quest_quick_variants
  WHERE parent_template_id = v_primary;

  -- Get alternative quest (different type)
  SELECT type INTO v_alt FROM quest_templates WHERE id = v_primary;
  v_alt := get_weighted_quest_for_user(p_user_id, v_alt);

  -- Insert and return
  INSERT INTO quest_alternatives (
    user_id, quest_date, primary_quest_id, quick_quest_id, alt_quest_id,
    rerolls_max
  ) VALUES (
    p_user_id, p_date, v_primary, v_quick, v_alt,
    CASE WHEN v_is_premium THEN 999 ELSE 1 END
  )
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### iOS Implementation

**New Models** (`Core/Models.swift`):

```swift
struct QuestAlternatives: Codable {
    let id: UUID
    let userId: UUID
    let questDate: Date
    let primaryQuestId: UUID
    let quickQuestId: UUID?
    let altQuestId: UUID
    let rerollsUsed: Int
    let rerollsMax: Int
    let selectedVariant: SelectedVariant

    // Joined data
    var primaryQuest: QuestTemplate?
    var quickQuest: QuestQuickVariant?
    var altQuest: QuestTemplate?

    enum SelectedVariant: String, Codable {
        case primary, quick, alt, reroll
    }

    var rerollsRemaining: Int {
        max(0, rerollsMax - rerollsUsed)
    }

    var canReroll: Bool {
        rerollsRemaining > 0 || rerollsMax == 999 // Premium unlimited
    }

    var isPremiumUnlimited: Bool {
        rerollsMax == 999
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case questDate = "quest_date"
        case primaryQuestId = "primary_quest_id"
        case quickQuestId = "quick_quest_id"
        case altQuestId = "alt_quest_id"
        case rerollsUsed = "rerolls_used"
        case rerollsMax = "rerolls_max"
        case selectedVariant = "selected_variant"
        case primaryQuest = "primary_quest_template"
        case quickQuest = "quest_quick_variant"
        case altQuest = "alt_quest_template"
    }
}

struct QuestQuickVariant: Identifiable, Codable {
    let id: UUID
    let parentTemplateId: UUID
    let title: String
    let description: String
    let steps: [String]
    let estimatedMinutes: Int
    let xpMultiplier: Double

    enum CodingKeys: String, CodingKey {
        case id
        case parentTemplateId = "parent_template_id"
        case title, description, steps
        case estimatedMinutes = "estimated_minutes"
        case xpMultiplier = "xp_multiplier"
    }
}

struct QuestPreference: Codable {
    let userId: UUID
    let questType: String
    let completionCount: Int
    let skipCount: Int
    let avgRating: Double?

    var preferenceScore: Double {
        let completionRate = Double(completionCount) / Double(max(1, completionCount + skipCount))
        let ratingScore = (avgRating ?? 3.0) / 5.0
        return (completionRate * 0.7) + (ratingScore * 0.3)
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case questType = "quest_type"
        case completionCount = "completion_count"
        case skipCount = "skip_count"
        case avgRating = "avg_rating"
    }
}
```

**Service Methods** (`Networking/Services/SupabaseDataService.swift`):

```swift
// MARK: - Quest Alternatives

func getTodayQuestAlternatives() async throws -> QuestAlternatives {
    let userId = try await getCurrentUserId()
    let today = Calendar.current.startOfDay(for: Date())

    // Generate or fetch alternatives
    let result: [QuestAlternatives] = try await supabase
        .rpc("generate_quest_alternatives", params: [
            "p_user_id": userId,
            "p_date": today.ISO8601Format()
        ])
        .execute()
        .value

    guard let alternatives = result.first else {
        throw APIError.notFound
    }

    // Fetch full quest data
    return try await fetchQuestAlternativesWithTemplates(alternatives)
}

private func fetchQuestAlternativesWithTemplates(_ alternatives: QuestAlternatives) async throws -> QuestAlternatives {
    async let primary: QuestTemplate = supabase
        .from("quest_templates")
        .select()
        .eq("id", alternatives.primaryQuestId)
        .single()
        .execute()
        .value

    async let alt: QuestTemplate = supabase
        .from("quest_templates")
        .select()
        .eq("id", alternatives.altQuestId)
        .single()
        .execute()
        .value

    var result = alternatives
    result.primaryQuest = try await primary
    result.altQuest = try await alt

    if let quickId = alternatives.quickQuestId {
        result.quickQuest = try await supabase
            .from("quest_quick_variants")
            .select()
            .eq("id", quickId)
            .single()
            .execute()
            .value
    }

    return result
}

func selectQuestVariant(_ variant: QuestAlternatives.SelectedVariant, alternativesId: UUID) async throws {
    try await supabase
        .from("quest_alternatives")
        .update(["selected_variant": variant.rawValue])
        .eq("id", alternativesId)
        .execute()
}

func rerollQuest(alternativesId: UUID) async throws -> QuestAlternatives {
    let userId = try await getCurrentUserId()

    // Get current alternatives
    let current: QuestAlternatives = try await supabase
        .from("quest_alternatives")
        .select()
        .eq("id", alternativesId)
        .single()
        .execute()
        .value

    guard current.canReroll else {
        throw APIError.custom("No rerolls remaining")
    }

    // Get new quest (excluding current types)
    let newQuestId: UUID = try await supabase
        .rpc("get_weighted_quest_for_user", params: [
            "p_user_id": userId,
            "p_exclude_type": current.primaryQuest?.type ?? ""
        ])
        .execute()
        .value

    // Log reroll
    try await supabase
        .from("quest_reroll_history")
        .insert([
            "user_id": userId.uuidString,
            "quest_date": current.questDate.ISO8601Format(),
            "from_quest_id": current.primaryQuestId.uuidString,
            "to_quest_id": newQuestId.uuidString,
            "reroll_number": current.rerollsUsed + 1
        ])
        .execute()

    // Update alternatives
    try await supabase
        .from("quest_alternatives")
        .update([
            "primary_quest_id": newQuestId.uuidString,
            "rerolls_used": current.rerollsUsed + 1,
            "selected_variant": "reroll"
        ])
        .eq("id", alternativesId)
        .execute()

    // Fetch and return updated alternatives
    return try await getTodayQuestAlternatives()
}

func updateQuestPreference(type: String, completed: Bool, rating: Int?) async throws {
    let userId = try await getCurrentUserId()

    // Upsert preference
    try await supabase
        .from("user_quest_preferences")
        .upsert([
            "user_id": userId.uuidString,
            "quest_type": type,
            "completion_count": completed ? 1 : 0, // Will be incremented by trigger
            "skip_count": completed ? 0 : 1,
            "total_rating_sum": rating ?? 0,
            "rating_count": rating != nil ? 1 : 0,
            "last_completed_at": completed ? Date().ISO8601Format() : nil,
            "updated_at": Date().ISO8601Format()
        ])
        .execute()
}
```

**New Views**:

```swift
// QuestChoiceView.swift
struct QuestChoiceView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var alternatives: QuestAlternatives?
    @State private var selectedQuest: QuestTemplate?
    @State private var isQuickVariant = false
    @State private var isLoading = true
    @State private var isRerolling = false
    @State private var showQuestDetail = false

    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
                ProgressView()
            } else if let alts = alternatives {
                // Recommended quest
                if let primary = alts.primaryQuest {
                    QuestOptionCard(
                        quest: primary,
                        badge: "Recommended",
                        badgeColor: .accentColor,
                        isSelected: selectedQuest?.id == primary.id && !isQuickVariant,
                        onSelect: { selectQuest(primary, isQuick: false) }
                    )
                }

                // Quick option
                if let quick = alts.quickQuest, let primary = alts.primaryQuest {
                    QuestOptionCard(
                        title: quick.title,
                        description: quick.description,
                        duration: quick.estimatedMinutes,
                        type: primary.type,
                        badge: "Quick • 50% XP",
                        badgeColor: .orange,
                        isSelected: selectedQuest?.id == primary.id && isQuickVariant,
                        onSelect: { selectQuest(primary, isQuick: true) }
                    )
                }

                // Alternative quest
                if let alt = alts.altQuest {
                    QuestOptionCard(
                        quest: alt,
                        badge: "Different Focus",
                        badgeColor: .purple,
                        isSelected: selectedQuest?.id == alt.id && !isQuickVariant,
                        onSelect: { selectQuest(alt, isQuick: false) }
                    )
                }

                Divider()

                // Reroll button
                RerollButton(
                    rerollsRemaining: alts.rerollsRemaining,
                    isPremium: alts.isPremiumUnlimited,
                    isLoading: isRerolling
                ) {
                    await reroll()
                }

                // Start button
                Button {
                    showQuestDetail = true
                } label: {
                    Text("Start Quest")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedQuest != nil ? Color.accentColor : Color.gray)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .disabled(selectedQuest == nil)
            }
        }
        .padding()
        .task { await loadAlternatives() }
        .sheet(isPresented: $showQuestDetail) {
            if let quest = selectedQuest {
                QuestDetailView(quest: quest, isQuickVariant: isQuickVariant)
            }
        }
    }

    func loadAlternatives() async {
        isLoading = true
        defer { isLoading = false }

        do {
            alternatives = try await container.supabaseDataService.getTodayQuestAlternatives()
            // Auto-select recommended
            selectedQuest = alternatives?.primaryQuest
        } catch {
            print("Failed to load alternatives: \(error)")
        }
    }

    func selectQuest(_ quest: QuestTemplate, isQuick: Bool) {
        withAnimation {
            selectedQuest = quest
            isQuickVariant = isQuick
        }

        Task {
            try? await container.supabaseDataService.selectQuestVariant(
                isQuick ? .quick : .primary,
                alternativesId: alternatives!.id
            )
        }
    }

    func reroll() async {
        guard let alts = alternatives else { return }
        isRerolling = true
        defer { isRerolling = false }

        do {
            alternatives = try await container.supabaseDataService.rerollQuest(alternativesId: alts.id)
            selectedQuest = alternatives?.primaryQuest
            isQuickVariant = false
        } catch {
            print("Reroll failed: \(error)")
        }
    }
}

// QuestOptionCard.swift
struct QuestOptionCard: View {
    var quest: QuestTemplate? = nil
    var title: String? = nil
    var description: String? = nil
    var duration: Int? = nil
    var type: String? = nil
    let badge: String
    let badgeColor: Color
    let isSelected: Bool
    let onSelect: () -> Void

    var displayTitle: String {
        title ?? quest?.title ?? ""
    }

    var displayDescription: String {
        description ?? quest?.description ?? ""
    }

    var displayDuration: Int {
        duration ?? quest?.estimatedMinutes ?? 0
    }

    var displayType: String {
        type ?? quest?.type ?? ""
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                // Type icon
                Image(systemName: typeIcon)
                    .font(.title2)
                    .foregroundStyle(typeColor)
                    .frame(width: 44, height: 44)
                    .background(typeColor.opacity(0.15))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 4) {
                    // Badge
                    Text(badge)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.2))
                        .foregroundStyle(badgeColor)
                        .cornerRadius(4)

                    Text(displayTitle)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(displayDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text("\(displayDuration) min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .accentColor : .secondary)
                    .font(.title2)
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    var typeIcon: String {
        switch displayType.lowercased() {
        case "breathing": return "wind"
        case "meditation": return "brain.head.profile"
        case "journaling": return "pencil.line"
        case "grounding": return "leaf"
        case "movement": return "figure.walk"
        default: return "star"
        }
    }

    var typeColor: Color {
        switch displayType.lowercased() {
        case "breathing": return .blue
        case "meditation": return .purple
        case "journaling": return .orange
        case "grounding": return .green
        case "movement": return .red
        default: return .accentColor
        }
    }
}

// RerollButton.swift
struct RerollButton: View {
    let rerollsRemaining: Int
    let isPremium: Bool
    let isLoading: Bool
    let onReroll: () async -> Void

    var body: some View {
        Button {
            Task { await onReroll() }
        } label: {
            HStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.clockwise")
                }

                Text("Different Quest")

                Spacer()

                if isPremium {
                    Text("∞")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.3))
                        .foregroundStyle(.orange)
                        .cornerRadius(4)
                } else {
                    Text("\(rerollsRemaining) left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .disabled(rerollsRemaining == 0 && !isPremium || isLoading)
        .opacity(rerollsRemaining == 0 && !isPremium ? 0.5 : 1)
    }
}
```

### Backend Implementation

**Update assign-quest cron** (`supabase/functions/assign-quest/index.ts`):

```typescript
// Modify existing quest assignment to use preference weighting

async function assignWeightedQuest(supabase: SupabaseClient, userId: string) {
  // Get user preferences
  const { data: preferences } = await supabase
    .from("user_quest_preferences")
    .select("*")
    .eq("user_id", userId);

  // Get available quest templates
  const { data: templates } = await supabase
    .from("quest_templates")
    .select("*")
    .eq("is_active", true);

  if (!templates?.length) return null;

  // Calculate weights
  const weighted = templates.map((template) => {
    const pref = preferences?.find((p) => p.quest_type === template.type);

    let weight = 1.0;

    if (pref) {
      // Higher completion rate = higher weight
      const completionRate =
        pref.completion_count /
        Math.max(1, pref.completion_count + pref.skip_count);
      weight *= 0.5 + completionRate; // 0.5 to 1.5

      // Higher rating = higher weight
      if (pref.rating_count > 0) {
        const avgRating = pref.total_rating_sum / pref.rating_count;
        weight *= 0.6 + (avgRating / 5) * 0.8; // 0.6 to 1.4
      }

      // Recency penalty (don't repeat same type too often)
      if (pref.last_completed_at) {
        const daysSince =
          (Date.now() - new Date(pref.last_completed_at).getTime()) /
          (1000 * 60 * 60 * 24);
        if (daysSince < 1) weight *= 0.5;
        else if (daysSince < 3) weight *= 0.8;
      }
    }

    return { template, weight };
  });

  // Weighted random selection
  const totalWeight = weighted.reduce((sum, w) => sum + w.weight, 0);
  let random = Math.random() * totalWeight;

  for (const { template, weight } of weighted) {
    random -= weight;
    if (random <= 0) {
      return template;
    }
  }

  return weighted[0]?.template;
}
```

---

## UI/UX

### Quest Choice Screen

```
┌─────────────────────────────────────────┐
│              Today's Quest              │
├─────────────────────────────────────────┤
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ 🧘 RECOMMENDED                  │    │
│  │                            [●] │    │
│  │ 5-Minute Breathing Reset       │    │
│  │ A quick breathing exercise to  │    │
│  │ center yourself                │    │
│  │ ⏱ 5 min                        │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ ⚡ QUICK • 50% XP              │    │
│  │                            [○] │    │
│  │ Quick Breath Reset             │    │
│  │ Same exercise, shorter         │    │
│  │ ⏱ 2 min                        │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ 🎯 DIFFERENT FOCUS             │    │
│  │                            [○] │    │
│  │ Gratitude Journaling           │    │
│  │ Write about three things...    │    │
│  │ ⏱ 8 min                        │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ────────────────────────────────────   │
│                                         │
│  [🔄 Different Quest       1 left]      │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │         Start Quest             │    │
│  └─────────────────────────────────┘    │
│                                         │
└─────────────────────────────────────────┘
```

### Reroll Animation

When user taps reroll:

1. Current cards fade out and slide left
2. Loading spinner appears briefly
3. New cards slide in from right
4. Recommended quest auto-selected

---

## Verification

### Manual Testing

1. **Quest Alternatives Generation:**
   - Open app for first time today
   - Verify 3 quest options shown
   - Verify recommended quest is weighted by history

2. **Quick Variant:**
   - Select quick variant
   - Complete quest
   - Verify reduced XP awarded (50%)
   - Verify streak still counts

3. **Reroll (Free User):**
   - Reroll once (should work)
   - Try to reroll again (should be disabled)
   - Verify "1 left" / "0 left" indicator

4. **Reroll (Premium):**
   - Subscribe to premium
   - Verify unlimited rerolls
   - Verify "∞" indicator

5. **Preference Learning:**
   - Complete several breathing quests, skip journaling
   - Verify breathing quests recommended more often
   - Check `user_quest_preferences` table data

---

## Dependencies

- Quest templates seeded
- User authentication working
- Subscription system for premium check

---

## Risks & Mitigations

| Risk                            | Likelihood | Impact | Mitigation                                  |
| ------------------------------- | ---------- | ------ | ------------------------------------------- |
| Users always pick quick         | Medium     | Medium | Lower XP makes it less optimal for leveling |
| Too many choices paralyze       | Low        | Medium | Default selection, only 3 options           |
| Reroll abuse by premium         | Low        | Low    | Different types encouraged by algorithm     |
| Preference creates echo chamber | Medium     | Low    | Some randomness always in selection         |

---

## Implementation Estimate

| Task                 | Effort       |
| -------------------- | ------------ |
| Database migration   | 2 hours      |
| iOS Models           | 1 hour       |
| Service methods      | 3 hours      |
| Quest choice UI      | 4 hours      |
| Reroll functionality | 2 hours      |
| Preference tracking  | 2 hours      |
| Backend weighting    | 2 hours      |
| Testing              | 2 hours      |
| **Total**            | **18 hours** |

---

## Success Metrics

| Metric                         | Current          | Target         |
| ------------------------------ | ---------------- | -------------- |
| Quest completion rate          | Measure baseline | +20%           |
| Quest skip rate                | Measure baseline | -30%           |
| Quick variant usage            | N/A              | 15-25%         |
| Reroll usage (free)            | N/A              | 40-60%         |
| Premium conversion from choice | N/A              | +5% conversion |
