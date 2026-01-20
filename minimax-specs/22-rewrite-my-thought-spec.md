# One-Tap "Rewrite My Thought"

**Quick Win:** Medium Effort / Medium Perceived Value

## Overview

- **Feature name:** One-Tap "Rewrite My Thought"
- **Description:** Instant cognitive reframing for a selected sentence in chat. Users can select their own message and get AI-generated alternative phrasings.
- **Business justification and user value:** Empowers users to see their thoughts from different perspectives. Bridges chat and cognitive coaching.

## Functional Requirements

### FR1: Text Selection
- As a user, I want to select my own message in chat.
- As a user, I want a clear option to rewrite what I said.

**Acceptance criteria:**
- Long-press on user's own message to select
- Selection handles show "Rewrite" option
- Works on single-sentence and multi-sentence selections
- Visual feedback when selection is active

### FR2: Rewrite Generation
- As a user, I want alternative ways to phrase my message.
- As a user, I want to see multiple options.

**Acceptance criteria:**
- Tap "Rewrite" → Generate 3-5 alternative phrasings
- Alternatives use different cognitive frameworks:
  - Less catastrophic (if applicable)
  - More balanced
  - More actionable
  - More self-compassionate
- Generation completes in <1 second

### FR3: Selection and Apply
- As a user, I want to easily choose and use a reframe.
- As a user, I want to see why a rewrite might help.

**Acceptance criteria:**
- Tap any alternative to select it
- Selected alternative highlighted
- "Apply" replaces original message
- "Why this helps" explanation for each rewrite (expandable)

### FR4: History and Learning
- As a user, I want to see my rewrite history.
- As a user, I want to learn from my patterns.

**Acceptance criteria:**
- Rewrites saved to user's history
- Optional: "Did this help?" feedback
- Stats: "You've rewritten X thoughts this week"
- Patterns: Common rewrite types used

## Technical Specifications

### Data Model

```sql
-- Rewrite history
CREATE TABLE rewrite_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id UUID NOT NULL,
    original_message TEXT NOT NULL,
    rewrite_type TEXT NOT NULL,  -- 'less_catastrophic', 'more_balanced', 'more_actionable', 'more_compassionate'
    rewritten_message TEXT NOT NULL,
    was_applied BOOLEAN DEFAULT FALSE,
    feedback_rating INTEGER,  -- 1-5, optional
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Rewrite type configurations
CREATE TABLE rewrite_types (
    type_key TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    description TEXT NOT NULL,
    system_prompt_suffix TEXT NOT NULL,  -- Added to AI prompt
    icon TEXT
);
```

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/functions/v1/generate-rewrites` | POST | Generate rewrite options |
| `/functions/v1/apply-rewrite` | POST | Record when rewrite is applied |
| `/functions/v1/rewrite-history` | GET | Get user's rewrite history |
| `/functions/v1/rewrite-feedback` | POST | Record feedback on rewrite |

### Integration Points
- **Chat View:** Text selection and rewrite UI
- **Chat Edge Function:** Rewrite generation logic
- **Cognitive Bias Coach:** Shared framework types

## User Interface

### Selection Menu
```
┌─────────────────────────────────────────────────┐
│  You: "I always mess everything up."           │
│                   ┌───────────┐                │
│                   │  Copy     │                │
│                   │  Rewrite  │ ← New option  │
│                   │  Delete   │                │
│                   └───────────┘                │
└─────────────────────────────────────────────────┘
```

### Rewrite Options Panel
```
┌─────────────────────────────────────────────────┐
│  Rewrite Your Thought                          │
├─────────────────────────────────────────────────┤
│  Original: "I always mess everything up."      │
│                                                 │
│  💭 Less Catastrophic:                         │
│  "I've made some mistakes lately, but         │
│   not everything goes wrong."                  │
│  [Apply]  [Why?]                               │
│                                                 │
│  💭 More Balanced:                             │
│  "Some things haven't gone well, and some     │
│   have. I'm working on it."                    │
│  [Apply]  [Why?]                               │
│                                                 │
│  💭 More Actionable:                           │
│  "I want to improve. What can I do            │
│   differently next time?"                      │
│  [Apply]  [Why?]                               │
│                                                 │
│  💭 More Self-Compassionate:                   │
│  "I'm struggling right now, but that          │
│   doesn't define my worth."                    │
│  [Apply]  [Why?]                               │
│                                                 │
│  [Keep Original]                               │
└─────────────────────────────────────────────────┘
```

### Applied Rewrite
```
┌─────────────────────────────────────────────────┐
│  💭 You: "Some things haven't gone well,       │
│         and some have. I'm working on it."     │
│         (rewritten 2m ago)                     │
│                                                 │
│  MindFriend: "That's a more balanced          │
│  perspective. What specific things do          │
│  you want to work on?"                         │
└─────────────────────────────────────────────────┘
```

### "Why This Helps" Expansion
```
┌─────────────────────────────────────────────────┐
│  💭 Less Catastrophic:                         │
│  "I've made some mistakes lately, but         │
│   not everything goes wrong."                  │
│  [Apply]  [▼ Why?]                             │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ 💡 This reframe challenges "always"       │ │
│  │ and "everything" by introducing           │ │
│  │ exceptions. It reduces emotional          │ │
│  │ intensity while staying honest.           │ │
│  └───────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

## Rewrite Types

| Type | When Used | Example Input | Example Output |
|------|-----------|---------------|----------------|
| Less Catastrophic | "Always/never" thinking | "I always fail" | "Some things haven't worked out" |
| More Balanced | All-or-nothing | "This is terrible" | "Some parts are challenging" |
| More Actionable | Vague distress | "Everything is wrong" | "What can I address first?" |
| More Self-Compassionate | Self-criticism | "I'm such a failure" | "I'm struggling but I'm trying" |
| More Curious | Assumptions | "They hate me" | "I wonder how they're feeling" |

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Empty or very short selection | Show "Select more text" prompt |
| Non-text content (images) | Hide rewrite option |
| Privacy-sensitive content | Warn before rewriting |
| Rewrite generation fails | Show error, offer retry |
| User applies then regrets | Allow undo for 30 seconds |

## Testing Requirements

- Selection and menu display
- Rewrite generation for various message types
- Apply replaces original correctly
- "Why this helps" expansion
- History recording and display
- Feedback collection

## Implementation Notes

- Reuse tone rewrite logic from Conversation Rehearsal
- Start with 4 rewrite types
- Cache rewrite types client-side
- Rate limit rewrites per session to prevent overuse

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Rewrite usage | 15% of messages eligible | Rewrites / eligible messages |
| Apply rate | 50% of rewrites applied | Applied / generated |
| User satisfaction | 4.2/5.0 rating | Post-rewrite survey |
| Repeat usage | 40% rewrite again within 7 days | Return users |
