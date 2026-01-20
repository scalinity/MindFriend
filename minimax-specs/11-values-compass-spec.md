# Values Compass & Decision Coach

**Priority:** #10 (Implementation Roadmap)
**Scores:** Delight 7/10 | Differentiation 6/10 | Feasibility High | Revenue Medium

## Step 1: Feature Analysis

### Core purpose and value proposition
- Help users clarify their core values and use them as a compass for decisions.
- Provide guided trade-off exercises when values conflict.
- Offer decision-making support that goes beyond feelings to principles.

### Target users and use cases
- Users facing life decisions who want to ground choices in values.
- Users who feel stuck and want clarity on what matters.
- Users in transition (career, relationships, life changes).

### Dependencies / prerequisites
- User profile with wellness focus (optional context).
- Simple exercises that can be completed in sessions.

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Values Compass & Decision Coach
- **Description:** A guided tool for values clarification and decision-making. Users explore their core values, visualize them, and use them as a compass for difficult choices. Includes trade-off exercises when values conflict.
- **Business justification and user value:** Expands MindFriend from "feelings" to "action." Positions as a life decision support tool, not just emotional support.

### 2. Functional Requirements

#### FR1: Values Discovery
- User stories:
  - As a user, I want to discover what I really value.
  - As a user, I want to see my values visually represented.
- Acceptance criteria:
  - Guided discovery exercise with 20+ value cards.
  - Three-phase selection: must-have, important, less important.
  - Visual values compass showing top 5-8 values.
  - Ability to name custom values.

#### FR2: Values Visualization
- User stories:
  - As a user, I want a visual representation of my values.
  - As a user, I want to share or remember my values.
- Acceptance criteria:
  - Compass visualization with values positioned by importance.
  - Categories: Personal, Relationships, Work, Growth.
  - Export as wallpaper or PDF.
  - Values reminder notifications (optional).

#### FR3: Decision Coach
- User stories:
  - As a user, I want help making a decision based on my values.
  - As a user, I want to see how my values apply to my choices.
- Acceptance criteria:
  - Decision input: What decision are you facing?
  - Values alignment check: Which of your values does this relate to?
  - Pros/cons with values lens: "This option aligns with X value but conflicts with Y."
  - Decision confidence score based on values alignment.

#### FR4: Trade-Off Exercises
- User stories:
  - As a user, I want to handle situations where values conflict.
  - As a user, I want to practice choosing between important things.
- Acceptance criteria:
  - Scenario-based trade-off exercises.
  - "Pick one" scenarios with values conflicts.
  - Reflection prompts for why certain values win.
  - Progress tracking on decision-making skills.

#### FR5: Values Journal
- User stories:
  - As a user, I want to track how I live my values.
  - As a user, I want to see my values in action.
- Acceptance criteria:
  - Log moments of living values.
  - "Values in action" weekly recap.
  - Gap analysis: "You're living X value less this month."
  - Celebration of values-aligned decisions.

### 3. Technical Specifications

#### Architecture and system design considerations
- Lightweight session-based flow (no heavy computation).
- Values stored in user profile for cross-feature use.
- Decision data private to user.

#### Data models and schemas (proposed)

```sql
-- User values profile
CREATE TABLE user_values (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    values_data JSONB NOT NULL,  -- Full values assessment results
    top_values TEXT[],  -- Array of top 5-8 values
    custom_values TEXT[],  -- User-named values
    values_categories JSONB,  -- Category mapping
    completed_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Values cards library
CREATE TABLE values_cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    value_key TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL,  -- 'personal', 'relationships', 'work', 'growth'
    icon TEXT,
    questions TEXT[],  -- Reflection questions for this value
    examples TEXT[]
);

-- User decisions
CREATE TABLE user_decisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    question TEXT NOT NULL,  -- The decision question
    options JSONB NOT NULL,  -- Array of option objects
    relevant_values TEXT[],  -- Which user values relate
    analysis JSONB,  -- Values-aligned analysis
    decision_made TEXT,  -- Which option chosen (or undecided)
    confidence_score FLOAT,  -- 0-1 scale
    outcome TEXT,  -- How did it go?
    reflection TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

-- Values journal entries
CREATE TABLE values_journal (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    value_key TEXT NOT NULL,
    entry_type TEXT NOT NULL,  -- 'action', 'conflict', 'alignment', 'growth'
    description TEXT NOT NULL,
    impact_level INTEGER,  -- 1-5
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Trade-off exercises
CREATE TABLE trade_off_scenarios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scenario_type TEXT NOT NULL,  -- 'work_life', 'honesty_kindness', etc.
    scenario_text TEXT NOT NULL,
    value_a TEXT NOT NULL,  -- First conflicting value
    value_b TEXT NOT NULL,  -- Second conflicting value
    questions TEXT[],  -- For reflection
    example_resolution TEXT
);

-- User trade-off history
CREATE TABLE user_trade_offs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    scenario_id UUID REFERENCES trade_off_scenarios(id),
    user_choice TEXT NOT NULL,  -- Which value they chose
    reasoning TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

#### API endpoints / interfaces

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/functions/v1/values-discovery` | POST | Complete values assessment |
| `/functions/v1/get-values` | GET | Retrieve user values |
| `/functions/v1/analyze-decision` | POST | Analyze decision with values |
| `/functions/v1/save-decision` | POST | Save decision outcome |
| `/functions/v1/values-journal` | POST | Add journal entry |
| `/functions/v1/get-journal` | GET | Retrieve journal entries |
| `/functions/v1/trade-off-scenario` | GET | Get random trade-off exercise |
| `/functions/v1/record-trade-off` | POST | Record user's choice |

#### Integration points with existing systems
- **User Profile:** Store top values for cross-feature use.
- **Chat:** Reference values in conversation.
- **Goals:** Align goals with values.
- **Achievements:** Decision-making badges.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions

**Values Discovery Start**
```
┌─────────────────────────────────────────────────┐
│  Discover Your Core Values                      │
├─────────────────────────────────────────────────┤
│                                                 │
│  Your values are your inner compass—they       │
│  guide your choices and give your life         │
│  meaning. Let's discover what matters most     │
│  to you.                                        │
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │                                             ││
│  │     What matters most in life?              ││
│  │                                             ││
│  │     Tap to explore your values              ││
│  │                                             ││
│  │         [Start Journey →]                   ││
│  │                                             ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  ⏱️ Takes about 5-10 minutes                    │
│  📝 You can save and continue later             │
└─────────────────────────────────────────────────┘
```

**Values Cards Selection**
```
┌─────────────────────────────────────────────────┐
│  What Matters to You?                           │
│  Step 1 of 3 - Must Have                       │
├─────────────────────────────────────────────────┤
│  🃏 20 values remaining                        │
│                                                 │
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐                │
│  │ 🔴│ │ 🔵│ │ 🟢│ │ 🟡│ │ 🟣│                │
│  │Auth│ │Comp│ │Free│ │Kind│ │Grow│             │
│  │ ent│ │assion│ │dom │ │ness│ │th │            │
│  └───┘ └───┘ └───┘ └───┘ └───┘                │
│                                                 │
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐                │
│  │ 🟠│ │ ⚫│ │ ⬜│ │ 🔶│ │ 🟩│                │
│  │Fami│ │Hono│ │Inde│ │Just│ │Wisd│             │
│  │ ly │ │sty │ │pend│ │ice │ │om │
│  └── │             ─┘ └───┘ └───┘ └───┘ └───┘                │
│                                                 │
│  Tap 3-5 values that are essential to you.      │
└─────────────────────────────────────────────────┘
```

**Values Compass**
```
┌─────────────────────────────────────────────────┐
│  Your Values Compass                            │
├─────────────────────────────────────────────────┤
│                                                 │
│                    Growth                       │
│                      ↑                          │
│                       \\                        │
│                        \\                       │
│   Freedom ──────────────── Autonomy            │
│                         /                       │
│                        /                        │
│                      ↓                          │
│                   Family                        │
│                                                 │
│  Your Top 5:                                    │
│  1. 🧭 Growth (inner direction)                 │
│  2. 🏔️ Autonomy (self-determination)            │
│  3. 🤝 Connection (meaningful bonds)            │
│  4. 🏠 Security (stability)                     │
│  5. ✨ Creativity (expression)                  │
│                                                 │
│  [Export]  [Add Custom]  [Edit]                │
└─────────────────────────────────────────────────┘
```

**Decision Coach**
```
┌─────────────────────────────────────────────────┐
│  Decision Coach                                 │
├─────────────────────────────────────────────────┤
│                                                 │
│  What decision are you facing?                  │
│  ┌─────────────────────────────────────────────┐│
│  │                                             ││
│  │  "Should I take this job offer?"           ││
│  │                                             ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  Which of your values does this relate to?      │
│  ┌───────────────────────────────────────────┐ │
│  │ [🧭 Growth]  [🏔️ Autonomy]  [🤝 Connect] │ │
│  │ [🏠 Security]  [✨ Creativity]            │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  Analyze Options →                              │
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │ Current Job:                                ││
│  │ • Aligns with: Security, Connection         ││
│  │ • Conflicts with: Growth, Autonomy          ││
│  │                                             ││
│  │ New Offer:                                  ││
│  │ • Aligns with: Growth, Autonomy             ││
│  │ • Conflicts with: Security                  ││
│  └─────────────────────────────────────────────┘│
└─────────────────────────────────────────────────┘
```

**Trade-Off Exercise**
```
┌─────────────────────────────────────────────────┐
│  Values in Conflict                             │
├─────────────────────────────────────────────────┤
│                                                 │
│  Scenario:                                      │
│  "Your friend asks for advice, but you're      │
│   feeling exhausted and need time alone.        │
│   What do you prioritize?"                      │
│                                                 │
│  Values at stake:                               │
│  ┌───────────────────────────────────────────┐ │
│  │ 💛 Kindness                              │ │
│  │ Supporting others, being helpful          │ │
│  └───────────────────────────────────────────┘ │
│                         vs                      │
│  ┌───────────────────────────────────────────┐ │
│  │ 🔋 Self-Care                             │ │
│  │ Protecting your own energy                │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  Which value guides your choice?                │
│  [Kindness]    [Self-Care]    [Both Possible]  │
│                                                 │
│  💭 Reflection:                                 │
│  "Kindness can also mean setting boundaries    │
│   so you can show up better later."             │
└─────────────────────────────────────────────────┘
```

**Values Journal**
```
┌─────────────────────────────────────────────────┐
│  Values Journal                                 │
├─────────────────────────────────────────────────┤
│                                                 │
│  This Week in Values                           │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ ✨ Creativity                             │ │
│  │ "Spent 2 hours painting just for fun"    │ │
│  │ 📅 2 days ago                            │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ 🤝 Connection                            │ │
│  │ "Called my sister, had a great talk"     │ │
│  │ 📅 3 days ago                            │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  📊 Weekly Insight                             │
│  "You're living Security less this week.      │
│   Consider: What's making things feel unstable?"│
│                                                 │
│  [Add Entry]  [View All]                       │
└─────────────────────────────────────────────────┘
```

#### User flow diagram (text)

1. **First-time user:**
   - Starts values discovery → Selects through cards → Sees compass → Exports or shares.

2.:**
   - Opens **Decision moment decision coach → Enters question → Selects relevant values → Gets analysis → Makes choice → Logs outcome.

3. **Regular reflection:**
   - Opens values journal → Adds entry → Reads weekly insight → Adjusts behavior → Tracks progress.

#### Accessibility requirements
- All text content accessible to VoiceOver.
- Values cards have clear focus states.
- Compass visualization has list alternative.
- Touch targets meet accessibility guidelines.

### 5. Edge Cases and Error Handling

| Scenario | Handling |
|----------|----------|
| User can't decide on values | Offer "come back later" option; save progress |
| Decision with no relevant values | Prompt for broader values exploration |
| Values conflict in decision | Offer trade-off exercise; don't force resolution |
| User abandons assessment | Save progress; allow resumption |
| Journal entries exceed storage | Archive old entries; keep recent |

### 6. Testing Requirements

#### Unit tests
- Values scoring algorithm.
- Decision analysis logic.
- Trade-off scenario randomization.
- Journal entry storage.

#### Integration tests
- End-to-end values discovery flow.
- Decision save and retrieval.
- Cross-feature values integration.
- Export functionality.

#### UAT scenarios
- Complete values discovery → See accurate compass.
- Use decision coach → Get helpful analysis.
- Practice trade-off → Understand conflict resolution.
- Add journal entries → See weekly insights.

### 7. Implementation Notes

#### Suggested implementation approach
- **Phase 1:** Values discovery + compass visualization.
- **Phase 2:** Basic decision coach.
- **Phase 3:** Trade-off exercises + values journal.
- **Phase 4:** Advanced analysis, integration with goals.

#### Potential challenges and mitigations
- **Challenge:** Values are abstract. **Mitigation:** Use concrete examples and reflection questions.
- **Challenge:** Users don't know what they want. **Mitigation:** Progressive disclosure; don't overwhelm.
- **Challenge:** Decision coaching quality. **Mitigation:** Start simple; gather feedback; iterate.

#### Performance considerations
- Values assessment cached on completion.
- Decision analysis runs server-side for complexity.
- Journal data local-first with sync.
- Compass visualization lightweight.

## Appendix A: Values Cards Library

| Category | Values |
|----------|--------|
| Personal | Autonomy, Growth, Security, Freedom, Creativity, Adventure, Stability, Achievement |
| Relationships | Connection, Love, Kindness, Support, Trust, Belonging, Community, Intimacy |
| Work | Purpose, Mastery, Recognition, Balance, Impact, Independence, Contribution, Excellence |
| Growth | Learning, Wisdom, Reflection, Challenge, Curiosity, Evolution, Self-awareness, Health |

## Step 3: Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Discovery completion | 50% of starters complete | Completed / started |
| Compass export | 30% export their compass | Export events / completions |
| Decision coach usage | 25% use for a decision | Decisions created / users |
| Decision confidence | 4.0/5.0 average rating | Post-decision survey |
| Trade-off completion | 60% of started exercises | Completed / started |
| Journal engagement | 20% add entries weekly | Weekly entries / users |
| Values in conversation | 15% of chat references values | Value mentions / messages |
