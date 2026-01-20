# Real-Time Cognitive Bias Coach

**Priority:** #3 (Implementation Roadmap)
**Scores:** Delight 8/10 | Differentiation 7/10 | Feasibility Medium | Revenue Medium

## Step 1: Feature Analysis

### Core purpose and value proposition
- Detect cognitive distortions in real-time during chat conversations.
- Offer gentle, educational reframes without requiring separate journaling.
- Help users develop awareness of their thought patterns in the moment.

### Target users and use cases
- Users who engage in chat and want immediate insight into their thinking patterns.
- Users new to CBT concepts who benefit from learning in context.
- Users who want to improve self-awareness without formal journaling.

### Dependencies / prerequisites
- Chat Edge Function with message analysis capability.
- Cognitive distortion taxonomy and reframe templates.
- User settings for coach sensitivity level.

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Real-Time Cognitive Bias Coach
- **Description:** An intelligent system that analyzes chat messages for common cognitive distortions (all-or-nothing thinking, catastrophizing, mind-reading, etc.) and offers gentle, educational reframes in the moment. The coach is optional, non-intrusive, and designed to teach rather than correct.
- **Business justification and user value:** Unique conversational CBT layer that provides immediate insight without extra work. Differentiates MindFriend as an educational tool, not just a venting platform.

### 2. Functional Requirements

#### FR1: Distortion Detection
- User stories:
  - As a user, I want the AI to recognize when I'm thinking in distorted patterns.
  - As a user, I want to understand what cognitive distortion my message might contain.
- Acceptance criteria:
  - System analyzes each user message for cognitive distortions.
  - Detects minimum 12 common distortion types (see Appendix A).
  - Confidence threshold of 70% before offering observation.
  - Detection runs entirely client-side for privacy (or Edge Function with privacy safeguards).

#### FR2: Gentle Reframe Suggestions
- User stories:
  - As a user, I want suggestions for how to think about things differently.
  - As a user, I want to learn why a reframe might be helpful.
- Acceptance criteria:
  - When distortion is detected, offer optional reframe card.
  - Reframe includes: identified distortion name, explanation, alternative perspective.
  - User can dismiss card or request more information.
  - "Why is this helpful?" expand for educational content.

#### FR3: Coach Sensitivity Levels
- User stories:
  - As a user, I want to control how often the coach intervenes.
  - As a user who is in crisis, I want the coach to be quiet.
- Acceptance criteria:
  - Three sensitivity levels: Minimal (rarely intervenes), Balanced (default), Frequent (more interventions).
  - Crisis mode: Coach completely silent during crisis detection.
  - Time-based restrictions: User can set "coach-free hours."

#### FR4: Educational Framework
- User stories:
  - As a user, I want to learn about cognitive distortions over time.
  - As a user, I want to track which distortions I experience most.
- Acceptance criteria:
  - Distortion Library: In-app reference explaining each distortion type.
  - Personal Pattern Tracking: Which distortions user sees most (anonymized).
  - Weekly Insight: "This week you encountered X distortions, most common was Y."
  - No data is used for AI training without explicit consent.

#### FR5: Integration with Chat Flow
- User stories:
  - As a user, I want the coach to feel like part of the conversation, not a pop-up.
  - As a user, I want to be able to ignore the coach easily.
- Acceptance criteria:
  - Coach intervention appears as inline suggestion, not blocking modal.
  - One-tap to dismiss, swipe to archive.
  - Coach respects conversation flow; doesn't interrupt emotional expression.
  - Coach can be toggled off per conversation.

### 3. Technical Specifications

#### Architecture and system design considerations
- Lightweight NLP model or keyword-based detection for low latency.
- Privacy-first: Distortion analysis runs client-side if possible.
- Educational content cached locally.
- Clear separation between chat (emotional support) and coach (cognitive education).

#### Data models and schemas (proposed)

```sql
-- Cognitive distortion taxonomy
CREATE TABLE cognitive_distortions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,  -- e.g., 'all_or_nothing'
    name TEXT NOT NULL,
    short_description TEXT NOT NULL,
    full_description TEXT NOT NULL,
    examples TEXT[],
    questions_to_challenge TEXT[],  -- Socratic questions
    reframe_templates TEXT[],  -- Template variations
    severity_weight INTEGER DEFAULT 1,  -- For sensitivity adjustment
    display_order INTEGER NOT NULL
);

-- User distortion encounters (stored locally on device)
CREATE TABLE local_distortion_encounters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    distortion_code TEXT NOT NULL,
    original_message_preview TEXT NOT NULL,
    reframe_offered BOOLEAN DEFAULT TRUE,
    reframe_accepted BOOLEAN DEFAULT FALSE,
    encounter_type TEXT DEFAULT 'chat',  -- 'chat', 'journal', 'voice'
    occurred_at TIMESTAMPTZ DEFAULT NOW(),
    client_generated_id TEXT NOT NULL  -- For local-first sync
);

-- Coach settings (per-user)
CREATE TABLE coach_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    is_enabled BOOLEAN DEFAULT TRUE,
    sensitivity_level TEXT DEFAULT 'balanced' CHECK (sensitivity_level IN ('minimal', 'balanced', 'frequent')),
    silent_hours_start TIME,
    silent_hours_end TIME,
    disabled_distortions TEXT[],  -- Codes user doesn't want to see
    show_patterns BOOLEAN DEFAULT TRUE,
    last_sync_at TIMESTAMPTZ
);

-- Educational content translations
CREATE TABLE distortion_education (
    distortion_id UUID REFERENCES cognitive_distortions(id),
    locale TEXT NOT NULL,
    name_translated TEXT NOT NULL,
    description_translated TEXT NOT NULL,
    examples_translated TEXT[],
    reframe_templates_translated TEXT[],
    PRIMARY KEY (distortion_id, locale)
);
```

#### API endpoints / interfaces

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/functions/v1/analyze-message` | POST | Analyze message for distortions (if not client-side) |
| `/functions/v1/get-reframe` | POST | Generate contextual reframe |
| `/functions/v1/coach-settings` | GET/PUT | Get or update user settings |
| `/functions/v1/distortion-library` | GET | Get all distortion types and education |
| `/functions/v1/my-patterns` | GET | Get user's distortion pattern summary |
| `/functions/v1/record-encounter` | POST | Record user interaction with coach |

#### Integration points with existing systems
- **Chat Edge Function:** Inject reframe suggestions into responses.
- **Journal:** Optional coach integration for journaling mode.
- **User Settings:** Coach sensitivity controls.
- **Analytics:** Track coach engagement without storing message content.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions

**Inline Coach Intervention**
```
┌─────────────────────────────────────────────────┐
│  MindFriend:                                    │
│  I always mess everything up. Nothing ever      │
│  goes right for me.                             │
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │ 💭 Noticed something                        ││
│  │                                             ││
│  │ "Always" and "nothing ever" can signal     ││
│  │ "all-or-nothing thinking" — seeing things  ││
│  │ as completely good or bad, with no middle  ││
│  │ ground.                                     ││
│  │                                             ││
│  │ 💡 Reframe:                                 ││
│  │ "Some things went wrong, and some went     ││
│  │ right. What went well today?"              ││
│  │                                             ││
│  │ [This helps]  [Not right now]  [Learn more]││
│  └─────────────────────────────────────────────┘│
└─────────────────────────────────────────────────┘
```

**Coach Toggle in Chat**
```
┌─────────────────────────────────────────────────┐
│  MindFriend:     [💭 Coach: ON ▼]      [•••]   │
│  ─────────────────────────────────────────────  │
│  Thinking Coach helps you recognize thought     │
│  patterns. Tap to adjust settings.              │
└─────────────────────────────────────────────────┘
```

**Sensitivity Settings**
```
┌─────────────────────────────────────────────────┐
│  Thinking Coach Settings                        │
├─────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────┐   │
│  │ Coach Enabled                           │   │
│  │ [ON]                                     │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  How often to intervene?                        │
│  ┌─────────────────────────────────────────┐   │
│  │ ○ Minimal    (rare suggestions)         │   │
│  │ ● Balanced   (default) ← SELECTED       │   │
│  │ ○ Frequent   (more frequent)            │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  Silent Hours                                   │
│  From: [09:00 PM ▼]   To: [09:00 AM ▼]         │
│                                                 │
│  Distortions to ignore                          │
│  [Manage excluded distortions →]                │
│                                                 │
│  Show me my thinking patterns                   │
│  [ON]                                           │
└─────────────────────────────────────────────────┘
```

**Distortion Library**
```
┌─────────────────────────────────────────────────┐
│  Thinking Patterns Library                      │
├─────────────────────────────────────────────────┤
│  🔍 Search patterns...                          │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ ⚫ All-or-Nothing Thinking                 │ │
│  │ Seeing things in black and white          │ │
│  │ categories. "If I'm not perfect, I'm a    │ │
│  │ failure."                                  │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ ⚫ Catastrophizing                        │ │
│  │ Expecting the worst-case scenario.        │ │
│  │ "This small mistake means everything      │ │
│  │ will fall apart."                         │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ ⚫ Mind Reading                           │ │
│  │ Assuming you know what others are         │ │
│  │ thinking. "They must think I'm stupid."   │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  [My Patterns →]                                │
└─────────────────────────────────────────────────┘
```

**Weekly Pattern Summary**
```
┌─────────────────────────────────────────────────┐
│  Your Thinking Patterns This Week               │
├─────────────────────────────────────────────────┤
│  📊 You encountered 12 thinking patterns        │
│                                                 │
│  Most Common:                                   │
│  ┌───────────────────────────────────────────┐ │
│  │ ⚫ All-or-Nothing Thinking  (5 times)     │ │
│  │ ↑ +2 from last week                       │ │
│  │                                            │ │
│  │ 💡 Tips: Look for shades of gray. Instead │ │
│  │ of "always/never", try "sometimes/often". │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  🆕 New Pattern This Week:                      │
│  • Catastrophizing (first appearance)           │
│                                                 │
│  [Practice Reframes →]  [View Library]         │
└─────────────────────────────────────────────────┘
```

#### User flow diagram (text)

1. **User sends message containing distortion:**
   - Message analyzed → Distortion detected above threshold → Coach card appears below AI response → User engages (learns, dismisses, or ignores).

2. **User adjusts settings:**
   - Opens settings → Adjusts sensitivity → Sets silent hours → Excludes certain distortions.

3. **User reviews patterns:**
   - Opens distortion library → Views "My Patterns" → Sees weekly summary → Explores learning resources.

#### Accessibility requirements
- Screen reader announces distortion name and reframe.
- All coach cards have accessible close button.
- Educational content uses clear language, avoids jargon.
- Reduced motion option for coach animations.

### 5. Edge Cases and Error Handling

| Scenario | Handling |
|----------|----------|
| Low confidence detection | Don't show intervention; log for model improvement |
| User in emotional distress | Crisis detection takes precedence; coach silent |
| User repeatedly dismisses coach | Reduce frequency of interventions |
| False positive (normal message flagged) | Easy dismiss; no negative feedback |
| Coach interrupts emotional expression | Never intervene in first 3 exchanges of new topic |
| Multi-language message | Default to English or show in user's language |

### 6. Testing Requirements

#### Unit tests
- Distortion detection accuracy >85%.
- False positive rate <10%.
- Sensitivity level filtering works correctly.
- Silent hours enforcement.

#### Integration tests
- Coach card displays correctly in chat flow.
- Settings persist and apply correctly.
- Distortion library loads all entries.
- Pattern tracking accumulates correctly.

#### UAT scenarios
- Send message with clear distortion → See helpful reframe.
- Dismiss coach repeatedly → Frequency decreases.
- Change sensitivity to "Minimal" → Fewer interventions.
- Set silent hours → No interventions during that time.
- View weekly patterns → See accurate summary.

### 7. Implementation Notes

#### Suggested implementation approach
- **Phase 1:** Keyword-based detection for top 5 distortions, simple reframe templates.
- **Phase 2:** ML model for detection, expand to 12 distortions.
- **Phase 3:** Pattern tracking, library, weekly insights.
- **Phase 4:** Advanced features (voice, integration with exercises).

#### Potential challenges and mitigations
- **Challenge:** Detection accuracy. **Mitigation:** Start conservative (high threshold), iterate with user feedback.
- **Challenge:** User annoyance. **Mitigation:** Strong controls, defaults to "balanced" not "frequent."
- **Challenge:** Privacy concerns. **Mitigation:** Run analysis client-side, store only aggregate patterns.

#### Performance considerations
- Detection should complete in <100ms.
- Coach cards lazy-loaded.
- Library content cached after first load.
- Pattern data stored locally, synced periodically.

## Appendix A: Cognitive Distortion Taxonomy

| Code | Name | Example | Reframe Template |
|------|------|---------|------------------|
| AON | All-or-Nothing Thinking | "If I don't do this perfectly, I'm a complete failure." | "Perfection isn't possible. What went well?" |
| CAT | Catastrophizing | "I made a mistake. Everything is going to fall apart." | "One mistake doesn't determine the outcome." |
| MIND | Mind Reading | "They probably think I'm stupid." | "I don't actually know what they're thinking." |
| FORT | Fortune Telling | "This will never work out." | "I can prepare for different outcomes." |
| LAB | Labeling | "I'm such an idiot." | "I made a mistake, but that doesn't define me." |
| SHO | Should Statements | "I should be doing better." | "I want to improve, and that's okay." |
| EMF | Emotional Reasoning | "I feel like a failure, so I must be one." | "Feelings aren't facts. What evidence do I have?" |
| MINS | Minimizing | "My success doesn't count because it was easy." | "My effort matters, regardless of difficulty." |
| BLAME | Blame | "This is all their fault." | "I can acknowledge others' actions while taking responsibility." |
| COMP | Comparison | "Everyone else has this figured out." | "I don't know their full story. My journey is my own." |
| RG | Regret Orientation | "I shouldn't have done that." | "I made the best choice I could at the time." |
| WHAT | What-If | "What if something goes wrong?" | "I can handle challenges as they come." |

## Step 3: Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Coach intervention rate | 20% of messages trigger detection | Interventions / user messages |
| User engagement with reframes | 40% click "This helps" | Positive responses / interventions |
| Weekly pattern review rate | 25% of users view patterns | Pattern views / DAU |
| User satisfaction with coach | 4.0/5.0 average rating | Post-interaction survey |
| Distortion awareness improvement | +15% in 30-day follow-up | Pre/post quiz scores |
