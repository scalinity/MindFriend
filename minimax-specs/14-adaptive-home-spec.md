# Adaptive Home Layout & Ritual Surfaces

**Priority:** #8 (Implementation Roadmap)
**Scores:** Delight 7/10 | Differentiation 7/10 | Feasibility High | Revenue Low

## Step 1: Feature Analysis

### Core purpose and value proposition
- Home screen modules reorder and change based on time of day, recent behavior, and in-app signals.
- Create a sense of the app being "alive" and relevant without relying on notifications.
- Surface the right content at the right time based on context.

### Target users and use cases
- Users who want the app to feel personalized and contextual.
- Users who engage at different times of day (morning vs evening).
- Users with varying needs (sometimes want chat, sometimes exercises).

### Dependencies / prerequisites
- Home View existing structure (apps/ios/MindFriendApp/Features/Home/HomeView.swift).
- User behavior tracking (privacy-preserving).
- Time-based context service.

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Adaptive Home Layout & Ritual Surfaces
- **Description:** A dynamic home surface that reorganizes modules, adjusts copy, and highlights different features based on time of day, recent user behavior, and in-app signals. Creates a ritual-like experience that feels alive without notification spam.
- **Business justification and user value:** Adaptive UI that feels personalized and relevant. Reduces friction by surfacing what the user likely needs. Differentiates from static app experiences.

### 2. Functional Requirements

#### FR1: Time-Based Adaptation
- User stories:
  - As a user, I want the app to feel appropriate for the time of day.
  - As a user, I want different greetings and suggestions morning vs evening.
- Acceptance criteria:
  - Time-of-day modules:
    - Morning (5-11am): Focus on daily intent, quick check-in, gentle wake-up.
    - Afternoon (11am-5pm): Productivity focus, progress check, mid-day check-in.
    - Evening (5-9pm): Wind-down, reflection, preparation for sleep.
    - Night (9pm-5am): Minimal disruption, next-day preview.
  - Greeting adapts: "Good morning" → "Good afternoon" → "Good evening" → "Late night?"
  - Module order shifts based on typical time-of-day engagement.

#### FR2: Behavior-Based Adaptation
- User stories:
  - As a user, I want the app to remember what I've been doing.
  - As a user, I want relevant suggestions based on my recent activity.
- Acceptance criteria:
  - Recent activity signals:
    - Haven't checked mood today → Mood prompt elevated.
    - Missed yesterday's quest → Gentle reminder.
    - Completed exercises → Exercise completion celebration.
    - Struggling (low mood, chat distress) → Support-focused layout.
  - "Ritual surfaces" for different states:
    - "Check-in ritual" when mood needs attention.
    - "Completion ritual" after quest/exercise.
    - "Support ritual" when in distress.
    - "Welcome back ritual" after absence.

#### FR3: Dynamic Module Ordering
- User stories:
  - As a user, I want the most relevant things to be prominent.
  - As a user, I want to customize what I see first.
- Acceptance criteria:
  - Priority slots (1-3) dynamically filled based on context.
  - User can pin favorite modules to maintain position.
  - Drag-and-drop reordering (persisted).
  - "Suggested for you" section based on patterns.

#### FR4: Ritual Moments
- User stories:
  - As a user, I want meaningful moments when I complete things.
  - As a user, I want the app to acknowledge my progress.
- Acceptance criteria:
  - Completion animations and micro-celebrations.
  - Transition moments (quest complete → well done → suggest next).
  - Daily completion ritual (all daily tasks done → summary + celebration).
  - Weekly ritual (Sunday reflection + preview).

#### FR5: Personalization Controls
- User stories:
  - As a user, I want to control what the app shows me.
  - As a user, I want to opt out of adaptations.
- Acceptance criteria:
  - "Adapt my home" settings:
    - Enable/disable time-based changes.
    - Enable/disable behavior-based changes.
    - Pin modules to prevent reordering.
    - Hide specific modules.
  - Clear explanation of what's adapted and why.

### 3. Technical Specifications

#### Architecture and system design considerations
- Home layout computed client-side based on rules.
- User preferences for pinning and customization.
- Behavior signals from analytics service.
- Time-based rules configurable.

#### Data models and schemas (proposed)

```sql
-- Home module definitions
CREATE TABLE home_modules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    module_key TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    category TEXT NOT NULL,  -- 'quest', 'mood', 'exercise', 'chat', 'progress'
    priority_default INTEGER NOT NULL DEFAULT 5,
    time_slots JSONB,  -- When this module is relevant: {'morning': [1,2], 'afternoon': [3,4]}
    is_pinnable BOOLEAN DEFAULT TRUE,
    icon TEXT,
    min_importance INTEGER DEFAULT 1,  -- Minimum visibility tier
    max_importance INTEGER DEFAULT 3,  -- Maximum visibility tier
    config JSONB  -- Module-specific configuration
);

-- User home layout preferences
CREATE TABLE home_layout_preferences (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    pinned_modules TEXT[],  -- Module keys pinned to top
    hidden_modules TEXT[],  -- Module keys hidden
    custom_order TEXT[],  -- Custom order if different from default
    adaptation_enabled BOOLEAN DEFAULT TRUE,
    time_adaptation_enabled BOOLEAN DEFAULT TRUE,
    behavior_adaptation_enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Behavior signals (for adaptation decisions)
CREATE TABLE behavior_signals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    signal_type TEXT NOT NULL,  -- 'mood_pending', 'quest_missed', 'exercise_completed', 'distress_detected'
    priority INTEGER NOT NULL DEFAULT 5,
    expires_at TIMESTAMPTZ NOT NULL,
    acknowledged_at TIMESTAMPTZ,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Ritual definitions
CREATE TABLE rituals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ritual_key TEXT NOT NULL UNIQUE,
    trigger_type TEXT NOT NULL,  -- 'completion', 'time', 'return', 'checkin'
    trigger_config JSONB NOT NULL,  -- Conditions for triggering
    display_name TEXT NOT NULL,
    description TEXT NOT NULL,
    animation_config JSONB,
    duration_seconds INTEGER DEFAULT 5,
    is_premium BOOLEAN DEFAULT FALSE
);

-- User ritual state (for one-time-per-day rituals)
CREATE TABLE user_ritual_state (
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    ritual_key TEXT NOT NULL,
    last_completed_at TIMESTAMPTZ,
    completion_count INTEGER DEFAULT 0,
    PRIMARY KEY (user_id, ritual_key)
);
```

#### API endpoints / interfaces

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/functions/v1/get-home-layout` | GET | Get computed home layout for user |
| `/functions/v1/update-layout-preferences` | PUT | Update layout customization |
| `/functions/v1/get-behavior-signals` | GET | Get active behavior signals |
| `/functions/v1/acknowledge-signal` | POST | Mark signal as seen |
| `/functions/v1/trigger-ritual` | POST | Check and trigger ritual |
| `/functions/v1/complete-ritual` | POST | Record ritual completion |

#### Integration points with existing systems
- **Home View:** Consume layout configuration.
- **Quest Service:** Quest completion signals.
- **Mood Service:** Mood logging signals.
- **Chat Service:** Distress detection signals.
- **Analytics:** Behavior tracking.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions

**Morning Layout**
```
┌─────────────────────────────────────────────────┐
│  Good morning, Danny! ☀️                         │
│  Monday, January 20                              │
├─────────────────────────────────────────────────┤
│                                                 │
│  🌅 Today's Ritual                              │
│  ┌─────────────────────────────────────────────┐│
│  │ "Good morning! Let's start today with      ││
│  │  intention. What's your focus for today?"  ││
│  │                                             ││
│  │  [Set Intent]  [Skip for now]              ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  📋 Today's Quest                               │
│  [🌟 Morning Gratitude - 5 min] →               │
│                                                 │
│  😊 How are you feeling this morning?           │
│  [Quick Check-in →]                             │
│                                                 │
│  💪 Suggested for you                           │
│  [🌬️ 2-min breathing]  [📝 Journal prompt]     │
└─────────────────────────────────────────────────┘
```

**Afternoon Layout**
```
┌─────────────────────────────────────────────────┐
│  Good afternoon, Danny! 🌤️                        │
│  Monday, January 20                              │
├─────────────────────────────────────────────────┤
│                                                 │
│  📈 Mid-Day Check-In                            │
│  ┌─────────────────────────────────────────────┐│
│  │ "How's your day going so far?"             ││
│  │                                             ││
│  │  😊 🙂 😐 😔 😢                            ││
│  │                                             ││
│  │  [Log Mood]  [I'm doing great]             ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  ✅ Progress This Week                          │
│  • 4/5 quests completed                         │
│  • 12 min exercise today                        │
│  • 5-day streak! 🎉                             │
│                                                 │
│  💬 Ready for a chat?                           │
│  [Talk to MindFriend →]                         │
└─────────────────────────────────────────────────┘
```

**Evening Layout**
```
┌─────────────────────────────────────────────────┐
│  Good evening, Danny! 🌙                         │
│  Monday, January 20                              │
├─────────────────────────────────────────────────┤
│                                                 │
│  🌆 Wind-Down Time                              │
│  ┌─────────────────────────────────────────────┐│
│  │ "Today is almost done. Let's reflect and  ││
│  │  prepare for restful sleep."               ││
│  │                                             ││
│  │  [Evening Reflection]  [Sleep Prep]        ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  📝 Today's Journal Prompt                      │
│  "What went well today?"                        │
│  [Write →]                                      │
│                                                 │
│  🌬️ Relax Before Bed                           │
│  [🌙 Sleep meditation]  [📖 Calming reading]    │
│                                                 │
│  📋 Tomorrow's Preview                           │
│  Quest: "Acts of Kindness"                      │
│  [Preview →]                                    │
└─────────────────────────────────────────────────┘
```

**Completion Ritual**
```
┌─────────────────────────────────────────────────┐
│                                                 │
│                                                 │
│           ✨  ✨  ✨                             │
│                                                 │
│        Quest Complete!                          │
│                                                 │
│         🌟  🎉  🌟                             │
│                                                 │
│     "Wonderful job today!                       │
│      You've completed 4 quests                  │
│      this week."                               │
│                                                 │
│        [See My Progress]                        │
│                                                 │
│           ✨  ✨  ✨                             │
│                                                 │
└─────────────────────────────────────────────────┘
```

**Layout Customization**
```
┌─────────────────────────────────────────────────┐
│  Customize Your Home                            │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │ 🧠 Adaptive Home                        │   │
│  │ [ON] App adjusts based on time and      │   │
│  │     your activity                       │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  📌 Pinned (stay at top)                       │
│  ┌─────────────────────────────────────────┐   │
│  │ [✓] Today's Quest   [✓] Quick Actions   │   │
│  │ [ ] Mood Check-in    [ ] Progress        │   │
│  │ [ ] Chat             [ ] Exercises       │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  🙈 Hidden (don't show)                        │
│  ┌─────────────────────────────────────────┐   │
│  │ [ ] Weekly Stats    [ ] Badges          │   │
│  │ [ ] Streak          [ ] Buddies         │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  [Reset to Default]                             │
└─────────────────────────────────────────────────┘
```

#### User flow diagram (text)

1. **Daily open:**
   - Opens app → Time-based layout loads → Behavior signals applied → Personalization applied → User engages with modules.

2. **Module interaction:**
   - User taps module → Interaction recorded → Behavior signal created → Future layouts adapt.

3. **Completion moment:**
   - User completes quest → Ritual triggers → Celebration shown → Suggestion for next action.

4. **Customization:**
   - User opens settings → Adjusts pinned/hidden modules → Preferences saved → Future layouts respect choices.

#### Accessibility requirements
- All modules have logical reading order.
- Dynamic changes announced (e.g., "Layout updated for evening").
- Reduced motion option for transitions.
- VoiceOver compatible with all module content.

### 5. Edge Cases and Error Handling

| Scenario | Handling |
|----------|----------|
| No behavior signals | Show default time-based layout |
| Multiple high-priority signals | Show multiple; limit to 3 per session |
| All modules pinned | Show in pinned order; skip adaptation |
| User on new device | Apply default layout; learn from behavior |
| Time zone travel | Detect time zone change; adapt accordingly |
| Performance issues | Fallback to simple static layout |

### 6. Testing Requirements

#### Unit tests
- Time-of-day detection and module selection.
- Behavior signal priority sorting.
- Layout computation with various configurations.
- Ritual trigger conditions.

#### Integration tests
- Full home view rendering with adaptations.
- Module tap tracking and signal creation.
- Ritual animation and completion flow.
- Settings persistence.

#### UAT scenarios
- Open in morning → See morning-specific content.
- Complete quest → See celebration ritual.
- Skip mood for 2 days → See elevated mood prompt.
- Pin quest to top → It stays at top.
- Disable adaptation → Layout stays static.

### 7. Implementation Notes

#### Suggested implementation approach
- **Phase 1:** Time-of-day adaptation only, basic layouts.
- **Phase 2:** Behavior signals and dynamic ordering.
- **Phase 3:** Ritual moments and celebrations.
- **Phase 4:** Full customization controls.

#### Potential challenges and mitigations
- **Challenge:** Too much change feels jarring. **Mitigation:** Gradual changes; keep core elements stable.
- **Challenge:** User feels surveilled. **Mitigation:** Clear communication; show "why" for adaptations; opt-out available.
- **Challenge:** Layout computation complexity. **Mitigation:** Simple rule-based system; cache computed layout.

#### Performance considerations
- Layout computed once per session (or on foreground).
- Animations optimized for 60fps.
- Module data loaded in parallel.
- No network calls for layout computation.

## Appendix A: Time-of-Day Module Priorities

| Module | Morning | Afternoon | Evening | Night |
|--------|---------|-----------|---------|-------|
| Intent/Quest | 1 | 3 | 2 | 4 |
| Mood Check-in | 2 | 1 | 2 | 4 |
| Exercise | 2 | 2 | 3 | 5 |
| Chat | 4 | 3 | 2 | 3 |
| Progress | 3 | 2 | 2 | 5 |
| Wind-down | 5 | 5 | 1 | 1 |
| Reflection | 4 | 4 | 1 | 2 |

## Step 3: Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Adaptation usage | 70% keep enabled | Adaptation enabled / users |
| Ritual engagement | 60% complete rituals | Ritual completions / triggers |
| Customization usage | 40% customize layout | Modified preferences / users |
| Time-of-day engagement | +15% morning/evening opens | Opens by time / baseline |
| User perception | "Feels personalized" 4/5 | Survey response |
| Return rate | +10% vs static home | Weekly return rate |
