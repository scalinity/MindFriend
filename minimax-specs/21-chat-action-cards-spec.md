# Chat Action Cards

**Quick Win:** Low Effort / High Perceived Value

## Overview

- **Feature name:** Chat Action Cards
- **Description:** Convert AI suggestions into one-tap action cards that appear in chat. Instead of just suggesting "try a breathing exercise," show a tappable card that starts it immediately.
- **Business justification and user value:** Reduces friction between insight and action. Higher engagement with suggested activities.

## Functional Requirements

### FR1: Action Card Display
- As a user, I want to see AI suggestions as tappable cards.
- As a user, I want to quickly act on suggestions without navigating away.

**Acceptance criteria:**
- AI suggestions that imply action trigger an action card
- Card shows: title, brief description, estimated time, icon
- One-tap to initiate the action
- Cards inline with chat flow

### FR2: Card Types
- As a user, I want different actions for different suggestion types.
- As a user, I want to know what will happen when I tap.

**Acceptance criteria:**
- Exercise cards: "Start breathing exercise (2 min)"
- Journaling cards: "Write about this (5 min)"
- Quest cards: "Complete quest: X"
- Mood cards: "Log how you're feeling"
- Resource cards: "View crisis resources"
- Chat cards: "Let's talk more about X"

### FR3: Card Actions
- As a user, I want to take action directly from the card.
- As a user, I want to dismiss cards I don't want.

**Acceptance criteria:**
- Tap card → Opens relevant feature in modal or navigates
- Long-press or swipe → Dismiss card
- "Dismiss All" for multiple cards
- Completed cards show checkmark, then fade

### FR4: Contextual Suggestions
- As a user, I want relevant suggestions based on the conversation.
- As a user, I want the AI to know when an action is appropriate.

**Acceptance criteria:**
- Cards only appear when suggestion is actionable
- Context preserved when opening action
- Example: Suggesting breathing after "I feel anxious" → opens breathing with "Feeling anxious" context

## Technical Specifications

### Action Card Data Model

```sql
-- Action card templates (configurable)
CREATE TABLE action_card_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trigger_type TEXT NOT NULL,  -- 'exercise', 'journal', 'quest', 'mood', 'resource', 'chat'
    card_title TEXT NOT NULL,
    card_description TEXT NOT NULL,
    action_destination TEXT NOT NULL,  -- 'exercise:{id}', 'journal:{prompt}', etc.
    icon TEXT,
    estimated_minutes INTEGER DEFAULT 1,
    priority INTEGER DEFAULT 5,
    is_premium BOOLEAN DEFAULT FALSE,
    conditions JSONB  -- When to show this card
);

-- Card display records (session-scoped)
CREATE TABLE chat_action_cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL,
    message_id UUID NOT NULL,
    card_type TEXT NOT NULL,
    card_data JSONB NOT NULL,
    is_dismissed BOOLEAN DEFAULT FALSE,
    is_completed BOOLEAN DEFAULT FALSE,
    displayed_at TIMESTAMPTZ DEFAULT NOW(),
    action_taken_at TIMESTAMPTZ
);
```

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/functions/v1/generate-action-cards` | POST | Generate cards for chat context |
| `/functions/v1/card-action-taken` | POST | Record when user acts on card |
| `/functions/v1/dismiss-card` | POST | Dismiss a card |

### Integration Points
- **Chat View:** Render action cards inline
- **Exercise Service:** Launch exercises with context
- **Journal Service:** Pre-fill journal prompts
- **Quest Service:** Complete quests directly

## User Interface

### Chat with Action Card
```
┌─────────────────────────────────────────────────┐
│  MindFriend:                                    │
│  "That sounds stressful. Taking a few deep     │
│  breaths can help calm your nervous system."   │
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │ 🌬️ 2-Minute Breathing Exercise            ││
│  │                                              │
│  │   [Start Now]                               ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  You: "Thanks, I'll try that"                  │
└─────────────────────────────────────────────────┘
```

### Multiple Action Cards
```
┌─────────────────────────────────────────────────┐
│  MindFriend:                                    │
│  "I hear how overwhelmed you're feeling.       │
│  Here are some things that might help:"        │
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │ 🌬️ Quick Breathing (2 min)          [Start]││
│  └─────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────┐│
│  │ 📝 Write It Out (5 min)              [Write]││
│  └─────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────┐│
│  │ ✅ Today's Quest                      [Do It]││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  [Dismiss All]                                  │
└─────────────────────────────────────────────────┘
```

### Completed Card State
```
┌─────────────────────────────────────────────┐
│  ✅ 2-Minute Breathing Exercise           Done│
│       Completed at 2:34 PM                  │
└─────────────────────────────────────────────┘
```

## Action Card Types

| Trigger | Example | Card Shows |
|---------|---------|------------|
| Exercise suggestion | "Try a breathing exercise" | Card with exercise preview + Start button |
| Journal prompt | "Want to write about this?" | Card with prompt preview + Write button |
| Quest mention | "There's a quest for this" | Card with quest details + Complete button |
| Mood logging | "How are you feeling?" | Card with mood options + Log button |
| Resource mention | "Here are resources" | Card with resource category + View button |
| Chat continuation | "Want to talk more?" | Card prompting continued conversation |

## Edge Cases

| Scenario | Handling |
|----------|----------|
| User already completed action | Show completed state, not action card |
| Action not available (premium) | Show card with upgrade prompt |
| Multiple similar cards | Consolidate or show "View all" |
| User dismisses card | Don't show again in this session |
| Action fails | Show error, allow retry |

## Testing Requirements

- Card generation from various chat contexts
- Card tap actions navigate correctly
- Dismiss functionality works
- Completed state displays properly
- Premium gating works correctly

## Implementation Notes

- Start with 3-4 card types (exercise, journal, mood, quest)
- Use existing navigation patterns
- Card templates configurable server-side
- A/B test effectiveness

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Card CTR | 40% tap rate | Taps / displayed |
| Action completion | 70% of taps complete | Completed / tapped |
| Engagement lift | +15% exercise starts | Exercise starts / baseline |
| User satisfaction | 4.3/5.0 rating | Post-action survey |
