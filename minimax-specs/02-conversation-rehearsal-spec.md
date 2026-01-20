# Conversation Rehearsal Studio

**Priority:** #2 (Implementation Roadmap)
**Scores:** Delight 8/10 | Differentiation 7/10 | Feasibility High | Revenue Medium

## Step 1: Feature Analysis

### Core purpose and value proposition
- Provide a safe, AI-powered environment to practice difficult real-life conversations before they happen.
- Offer customizable scenarios, role-play modes, and "tone rewrite" features to build confidence.
- Reduce anxiety around challenging interactions by providing rehearsal opportunities with feedback.

### Target users and use cases
- Users preparing for difficult conversations (breaking bad news, setting boundaries, asking for raises).
- Users with social anxiety who want to practice before real interactions.
- Users learning to communicate more effectively in relationships.
- Users preparing for job interviews or important meetings.

### Dependencies / prerequisites
- Chat Edge Function with multi-turn conversation capability.
- Scenario templates database (pre-built conversation scenarios).
- Voice mode integration (optional for voice-based rehearsal).
- User preferences for tone and style settings.

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Conversation Rehearsal Studio
- **Description:** An interactive practice environment where users can rehearse difficult conversations with an AI that simulates realistic responses. Users can choose from pre-built scenarios or create custom scenarios, practice different approaches, receive real-time feedback on their communication, and use "tone rewrite" to see alternative phrasings.
- **Business justification and user value:** Practical utility beyond general emotional support differentiates MindFriend from competitors. Users get tangible preparation for real-world challenges, increasing app engagement and perceived value.

### 2. Functional Requirements

#### FR1: Scenario Selection
- User stories:
  - As a user, I want to browse pre-built conversation scenarios so I can practice common difficult situations.
  - As a user, I want to create a custom scenario with my own context so I can practice specific conversations.
- Acceptance criteria:
  - Minimum 20 pre-built scenarios covering common use cases (see Appendix A).
  - Custom scenario creation with: topic, other party's role, key points to convey, desired outcome.
  - Search and filter scenarios by category (work, relationships, social, family).
  - "Recommended for you" based on user's recent chat topics or mood patterns.

#### FR2: Role-Play Interface
- User stories:
  - As a user, I want to have a back-and-forth conversation with the AI playing another role.
  - As a user, I want to see context from the scenario while rehearsing.
- Acceptance criteria:
  - Chat-style interface with clear separation between user's messages and AI's responses.
  - Scenario context panel showing: situation summary, key points to cover, goal.
  - Ability to restart scenario from beginning at any time.
  - Ability to switch between "practice mode" (full conversation) and "focus mode" (specific phrase).

#### FR3: Tone Rewrite Feature
- User stories:
  - As a user, I want to see alternative ways to phrase something I'm planning to say.
  - As a user, I want to compare different tones for the same message.
- Acceptance criteria:
  - User inputs or selects their drafted message.
  - System generates 3-5 alternative phrasings at different tones:
    - More direct
    - More gentle
    - More assertive
    - More collaborative
  - User can select any alternative to use in the rehearsal.
  - "Why this works" explanation for each alternative.

#### FR4: Real-Time Feedback
- User stories:
  - As a user, I want feedback on how I'm communicating during rehearsal.
  - As a user, I want suggestions for improvement.
- Acceptance criteria:
  - After each exchange, optional feedback panel shows:
    - Communication style detected (assertive, passive, aggressive, collaborative).
    - Suggestions for improvement.
    - Encouragement for effective communication.
  - End-of-session summary with strengths and growth areas.
  - Tone consistency tracking across conversation.

#### FR5: Recording and Review
- User stories:
  - As a user, I want to review my rehearsal after completion.
  - As a user, I want to save successful approaches for future reference.
- Acceptance criteria:
  - Full conversation transcript available after session.
  - Ability to "bookmark" particularly effective messages.
  - Sessions saved to user's history (opt-in).
  - Ability to export transcript as PDF or text.

#### FR6: Progress Tracking
- User stories:
  - As a user, I want to see my improvement over time.
  - As a user, I want to track which scenarios I've practiced.
- Acceptance criteria:
  - "Practice Log" showing: date, scenario, confidence rating.
  - Progress indicators for each scenario type (e.g., "You've practiced 3/5 boundary-setting scenarios").
  - Achievement badges for completion milestones.

### 3. Technical Specifications

#### Architecture and system design considerations
- Dedicated Edge Function for conversation rehearsal with specialized prompting.
- Scenario templates stored in database for easy updates and localization.
- Feedback system uses NLP analysis of user messages.
- Voice input/output integration for immersive practice.

#### Data models and schemas (proposed)

```sql
-- Pre-built scenario templates
CREATE TABLE conversation_scenarios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category TEXT NOT NULL CHECK (category IN ('work', 'relationships', 'social', 'family', 'health', 'financial')),
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    situation_context TEXT NOT NULL,
    other_party_role TEXT NOT NULL,
    key_points_to_convey TEXT[],
    desired_outcome TEXT NOT NULL,
    difficulty_level TEXT DEFAULT 'medium' CHECK (difficulty_level IN ('easy', 'medium', 'advanced')),
    estimated_minutes INTEGER DEFAULT 10,
    tips_for_user TEXT[],
    is_premium BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Custom scenarios created by users
CREATE TABLE custom_scenarios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    other_party_role TEXT NOT NULL,
    situation_summary TEXT NOT NULL,
    key_points TEXT NOT NULL,
    desired_outcome TEXT NOT NULL,
    is_public BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User rehearsal sessions
CREATE TABLE rehearsal_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    scenario_id UUID REFERENCES conversation_scenarios(id),
    custom_scenario_id UUID REFERENCES custom_scenarios(id),
    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    confidence_rating INTEGER,
    notes TEXT,
    transcript TEXT NOT NULL,
    feedback_summary TEXT,
    is_bookmarked BOOLEAN DEFAULT FALSE
);

-- Bookmarked messages from rehearsals
CREATE TABLE rehearsal_bookmarks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id UUID REFERENCES rehearsal_sessions(id) ON DELETE CASCADE,
    original_message TEXT NOT NULL,
    rewritten_message TEXT,
    tone_type TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Communication style patterns
CREATE TABLE communication_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_type TEXT NOT NULL,
    keywords TEXT[],
    example_phrases TEXT[],
    feedback_message TEXT NOT NULL
);
```

#### API endpoints / interfaces

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/functions/v1/list-scenarios` | GET | List available scenarios with filters |
| `/functions/v1/get-scenario` | GET | Get detailed scenario content |
| `/functions/v1/create-custom-scenario` | POST | Create custom scenario |
| `/functions/v1/start-rehearsal` | POST | Initialize rehearsal session |
| `/functions/v1/rehearsal-message` | POST | Send message in rehearsal |
| `/functions/v1/tone-rewrite` | POST | Generate alternative phrasings |
| `/functions/v1/get-feedback` | POST | Get feedback for a message or session |
| `/functions/v1/complete-rehearsal` | POST | End session and save summary |
| `/functions/v1/session-history` | GET | Get user's rehearsal history |
| `/functions/v1/export-session` | GET | Export session transcript |

#### Integration points with existing systems
- **Chat Edge Function:** Shared conversation handling logic.
- **User Settings:** Tone preferences carried over from `AITone` enum.
- **Voice Mode:** Reusable voice token and audio session handling.
- **Achievements:** Track rehearsal completions for badges.
- **Analytics:** Track engagement and outcomes.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions

**Scenario Selection Screen**
```
┌─────────────────────────────────────────────────┐
│  Conversation Rehearsal                         │
│  Practice difficult conversations safely        │
├─────────────────────────────────────────────────┤
│  🔍 Search scenarios...                         │
│                                                 │
│  ┌─── Work ───┐  ┌─── Relationships ───┐       │
│  │ 💼 Ask for │  │ 💔 Break bad │       │
│  │    raise   │  │    news     │       │
│  └────────────┘  └─────────────────┘       │
│                                                 │
│  ┌─── Social ───┐ ┌─── Family ────┐         │
│  │ 👥 Navigate │ │ 👨‍👩‍👧 Set bound-│         │
│  │  conflict   │ │    aries     │         │
│  └─────────────┘ └───────────────┘         │
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │ 🆕 Create Custom Scenario               │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  [History & Progress →]                        │
└─────────────────────────────────────────────────┘
```

**Rehearsal Interface**
```
┌─────────────────────────────────────────────────┐
│  ← Back     Ask for Raise     [Restart] [Tips] │
├─────────────────────────────────────────────────┤
│  📋 Context                           [Show/Hide]│
│  ┌─────────────────────────────────────────────┐│
│  │ Situation: Annual review next week          ││
│  │ Goal: Request 15% raise based on performance││
│  │ Key points: [✓] Achieved all targets        ││
│  │              [✓] Took on extra projects     ││
│  │              [ ] Market rate research       ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │ 👤 Manager:                                 ││
│  │ "Thanks for sharing your thoughts. That's   ││
│  │ great to hear. Let me think about it."      ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │ You:                                        ││
│  │ "I'd like to discuss my compensation..."    ││
│  └─────────────────────────────────────────────┘│
│  [Rewrite]                          [Send →]   │
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │ 💡 Feedback (optional)                      ││
│  │ ✓ Clear and confident                       ││
│  └─────────────────────────────────────────────┘│
└─────────────────────────────────────────────────┘
```

**Tone Rewrite Panel**
```
┌─────────────────────────────────────────────────┐
│  Rewrite Your Message                           │
├─────────────────────────────────────────────────┤
│  Original: "I want a raise."                    │
│                                                 │
│  More Direct:                                   │
│  "Based on my performance this year, I'm        │
│  requesting a 15% salary increase..."           │
│  [Use This]                                     │
│                                                 │
│  More Gentle:                                   │
│  "I've really valued my time here..."           │
│  [Use This]                                     │
│                                                 │
│  [Keep Original]                                │
└─────────────────────────────────────────────────┘
```

**Session Summary**
```
┌─────────────────────────────────────────────────┐
│  Session Complete!                              │
├─────────────────────────────────────────────────┤
│  ✅ Great practice session!                     │
│                                                 │
│  📊 Your Performance                            │
│  ┌─────────────────────────────────────────────┐│
│  │ Communication Style: Collaborative ✓        ││
│  │ Key Points Covered: 2/3                     ││
│  │ Confidence: ★★★★☆ (4/5)                    ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  💡 Growth Areas                                │
│  • Consider adding specific data points         │
│                                                 │
│  📝 Session saved to your history               │
│  [View Transcript]  [Bookmark This]             │
│                                                 │
│         [Practice Another Scenario]             │
└─────────────────────────────────────────────────┘
```

#### User flow diagram (text)

1. **First-time user:** Sees onboarding → Selects scenario category → Browses scenarios → Picks scenario → Completes rehearsal → Sees summary → Encouraged to practice more.

2. **Returning user:** Opens studio → Sees "Continue where you left off" or browses → Selects scenario → Practices → Reviews → Tracks progress.

3. **Custom scenario creation:** Taps "Create Custom" → Enters topic, role, situation → Adds key points → Defines goal → Saves → Starts rehearsal.

#### Accessibility requirements
- Voice input for hands-free practice.
- Voice output for hearing responses.
- Full keyboard navigation for chat interface.
- Screen reader compatibility for all feedback text.
- Haptic feedback for message send and feedback receipt.

### 5. Edge Cases and Error Handling

| Scenario | Handling |
|----------|----------|
| AI response timeout | Show loading state; allow retry or skip |
| User goes idle during session | Save progress; offer resume on return |
| Custom scenario is too vague | Prompt for more details before starting |
| Voice input fails | Fallback to text input with clear error |
| User wants to change scenario mid-session | Offer to restart with new scenario |
| Sensitive content detected | Stop rehearsal; offer crisis resources |
| Session exceeds time limit (60 min) | Prompt to save and continue or end |

### 6. Testing Requirements

#### Unit tests
- Scenario template loading and filtering.
- Tone rewrite generation for various input lengths.
- Feedback calculation logic.
- Session saving and retrieval.

#### Integration tests
- End-to-end rehearsal flow with mock scenario.
- Voice mode integration with rehearsal.
- Achievement unlocking on scenario completion.
- Analytics event tracking.

#### UAT scenarios
- Practice setting a boundary → See feedback → Improve → Complete session.
- Create custom scenario → Practice → Review transcript.
- Use tone rewrite → Compare options → Select one → Continue.
- Complete multiple scenarios → Verify progress tracking.

### 7. Implementation Notes

#### Suggested implementation approach
- **Phase 1:** Core rehearsal with 10 scenarios, text-only, basic feedback.
- **Phase 2:** Tone rewrite feature, progress tracking.
- **Phase 3:** Voice mode integration, custom scenarios.
- **Phase 4:** Advanced feedback (NLP analysis), community scenarios.

#### Potential challenges and mitigations
- **Challenge:** AI role-playing realistic responses. **Mitigation:** Use few-shot prompting with detailed persona descriptions.
- **Challenge:** Feedback quality. **Mitigation:** Start with simple heuristics; iterate based on user feedback.
- **Challenge:** Voice mode latency. **Mitigation:** Use streaming responses; pre-warm voice tokens.

#### Performance considerations
- Scenario data can be cached client-side.
- Tone rewrite should be fast (<500ms response).
- Session transcripts stored compressed.
- Limit concurrent voice sessions.

## Appendix A: Pre-Built Scenarios

| Category | Title | Difficulty | Est. Time |
|----------|-------|------------|-----------|
| Work | Ask for a raise | Medium | 10 min |
| Work | Request time off | Easy | 5 min |
| Work | Address workload concerns | Medium | 10 min |
| Work | Negotiate job offer | Advanced | 15 min |
| Work | Quit job professionally | Medium | 10 min |
| Work | Give difficult feedback to peer | Medium | 10 min |
| Work | Handle micromanagement | Medium | 10 min |
| Relationships | Break bad news to partner | Advanced | 15 min |
| Relationships | Have "the talk" about relationship | Advanced | 15 min |
| Relationships | Address trust issues | Medium | 10 min |
| Relationships | Ask for space | Easy | 5 min |
| Relationships | Apologize sincerely | Medium | 10 min |
| Social | Navigate group conflict | Medium | 10 min |
| Social | Decline invitation gracefully | Easy | 5 min |
| Social | Address uncomfortable joke | Medium | 10 min |
| Social | Make new friends at event | Easy | 5 min |
| Family | Set boundaries with parent | Medium | 10 min |
| Family | Discuss sensitive topic with sibling | Medium | 10 min |
| Family | Ask for help | Easy | 5 min |
| Health | Discuss symptoms with doctor | Medium | 10 min |
| Financial | Discuss finances with partner | Advanced | 15 min |
| Financial | Ask for payment extension | Easy | 5 min |

## Step 3: Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Rehearsal completion rate | 70% of sessions started | Completed sessions / started sessions |
| Return user rate | 40% practice again within 7 days | Repeat users / first-time users |
| Custom scenario creation | 20% of users create at least one | Custom scenarios / unique users |
| Confidence rating average | 4.0/5.0 or higher | Average session rating |
| Scenario variety | 60% try 3+ different categories | Category diversity per user |
