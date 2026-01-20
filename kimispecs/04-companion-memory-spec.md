# AI Memory Vault & Consent Controls

**Priority:** #1 (Implementation Roadmap)
**Scores:** Delight 9/10 | Differentiation 8/10 | Feasibility Medium | Revenue Medium

## Step 1: Feature Analysis

### Core purpose and value proposition
- Provide a transparent, user-editable memory panel where people can see, edit, and delete what the AI "remembers" about them.
- Enable users to explicitly control boundaries, preferences, triggers, and avoid-topics.
- Create privacy-first memory that feels safe and empowering while enabling deep personalization.

### Target users and use cases
- Privacy-conscious users who want control over AI personalization.
- Users managing specific mental health topics who need to set boundaries around sensitive subjects.
- Power users who want the AI to remember important context (life events, stressors, coping strategies that work).
- Users who want to "reset" AI memory after a difficult period.

### Dependencies / prerequisites
- Chat Edge Function and AI prompt pipeline.
- User settings model and privacy preferences.
- Data storage with RLS for memory items.
- Localization support for memory categories and labels.

## Step 2: Specification Document

### 1. Feature Overview

- **Feature name:** AI Memory Vault & Consent Controls
- **Description:** A user-editable memory panel that displays all AI-remembered information in clear categories (boundaries, preferences, triggers, avoid-topics, positive reinforcement). Users can view, edit, add, and delete memory items with full transparency. The system shows when and how each memory item is used, providing complete control and visibility.
- **Business justification and user value:** Privacy-first memory is rare in mental health apps and builds significant trust. Transparent personalization differentiates MindFriend from competitors while giving users agency over their AI relationship.

### 2. Functional Requirements

#### FR1: Memory Vault Access
- User stories:
  - As a user, I want to access a dedicated memory vault to see everything the AI remembers about me.
  - As a user, I want the memory vault easily accessible from settings and chat.
- Acceptance criteria:
  - Memory Vault accessible from: Settings menu, Chat header menu, Profile.
  - Vault requires biometric authentication if Privacy Mode is set to "Enhanced" (Models.swift:703-713).
  - Memory items are organized by category with clear visual organization.

#### FR2: Memory Categories & Types
- User stories:
  - As a user, I want memories organized by type so I can find and manage them easily.
  - As a user, I want to understand what each memory is used for.
- Acceptance criteria:

| Category | Description | Examples |
|----------|-------------|----------|
| **Boundaries** | Topics the user wants to avoid discussing | "Don't ask about work stress" |
| **Preferences** | Communication style and content preferences | "Prefer gentle tone", "Like breathing exercises" |
| **Triggers** | Known stressors to approach carefully | "Financial stress this month" |
| **Avoid-Topics** | Sensitive subjects to never mention | Personal trauma specifics |
| **Positive Reinforcement** | What helps the user | "Responds well to gratitude exercises" |
| **Life Context** | Current life situation | "Job hunting", "New pet", "Moving soon" |

#### FR3: Memory Display & Visualization
- User stories:
  - As a user, I want to see when each memory was created and last used.
  - As a user, I want to see which memories are actively influencing AI responses.
- Acceptance criteria:
  - Each memory item displays: content, category icon, created date, last used date, usage frequency (low/medium/high).
  - Active memories shown with subtle highlighting; dormant memories grayed out.
  - Memories sorted by "last used" by default, with filtering by category.
  - Search functionality to find specific memories quickly.

#### FR4: Memory Management (CRUD)
- User stories:
  - As a user, I want to add new memories manually.
  - As a user, I want to edit existing memories to update them.
  - As a user, I want to delete memories I no longer want the AI to remember.
- Acceptance criteria:
  - Manual add: Users can create new memories with category selection and optional expiration date.
  - Edit: Full text editing with category change capability.
  - Delete: Soft delete with confirmation; hard delete available for sensitive items.
  - Bulk actions: "Clear all from category" and "Clear all memories" options.
  - Undo capability for 10 seconds after deletion.

#### FR5: AI Memory Generation (Passive Capture)
- User stories:
  - As a user, I want the AI to automatically remember important things I share.
  - As a user, I want to approve or reject memories the AI wants to create.
- Acceptance criteria:
  - AI can suggest memories based on chat content (e.g., "I notice you mentioned X several times—would you like me to remember this?").
  - Suggested memories appear in a "Pending" section for user approval.
  - Auto-generation is opt-in via settings; default is off for privacy.
  - Clear UI showing "AI Suggested" vs "User Created" memories.

#### FR6: Consent Controls
- User stories:
  - As a user, I want to control what data the AI can remember.
  - As a user, I want to export or download my memories.
- Acceptance criteria:
  - Master toggle: "Enable AI Memory" (default: on, can be turned off entirely).
  - Per-category toggles: Enable/disable specific memory categories.
  - Data export: Download all memory data as JSON.
  - Data deletion: "Delete all memories" with confirmation and email notification.

#### FR7: Memory Usage Transparency
- User stories:
  - As a user, I want to know when memory is being used in a response.
  - As a user, I want transparency about how memories influence AI behavior.
- Acceptance criteria:
  - Chat responses include a subtle "memory used" indicator (e.g., small brain icon tooltip).
  - Long-press on indicator shows which specific memories influenced the response.
  - Statistics view: "Memories used this week: 23" with category breakdown.
  - Privacy dashboard showing memory access patterns.

#### FR8: Intent Setting (Daily/Weekly)
- User stories:
  - As a user, I want to set a daily or weekly intent that shapes AI responses.
  - As a user, I want to clear or update my current intent.
- Acceptance criteria:
  - Daily intent prompt appears once per day (dismissible, can snooze 2 hours).
  - Intent limited to 140 characters (or 280 for weekly).
  - Weekly intent option: Set focus for the entire week.
  - Intent displayed prominently in chat header.
  - Intent expiration: Daily = 24 hours, Weekly = 7 days.

### 3. Technical Specifications

#### Architecture and system design considerations
- Memory stored in Supabase with strict RLS policies per table.
- Chat Edge Function pulls memory for prompt assembly with priority weighting.
- Memory items have priority scores for prompt inclusion (user-created > AI-suggested).
- Rate limiting on memory creation to prevent abuse.
- Audit log for all memory access and modifications.

#### Data models and schemas (proposed)

```sql
-- Memory Vault main table
CREATE TABLE companion_memory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    category TEXT NOT NULL CHECK (category IN (
        'boundaries', 'preferences', 'triggers', 
        'avoid_topics', 'positive_reinforcement', 'life_context'
    )),
    content TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT 'user' CHECK (source IN ('user', 'ai_suggested', 'auto')),
    is_approved BOOLEAN DEFAULT TRUE,
    is_active BOOLEAN DEFAULT TRUE,
    priority_score INTEGER DEFAULT 50,  -- 0-100, higher = more likely to be used
    usage_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    last_used_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,  -- Optional expiration
    metadata JSONB DEFAULT '{}'  -- For extensibility
);

-- Daily/Weekly intents table
CREATE TABLE user_intents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    intent_type TEXT NOT NULL DEFAULT 'daily' CHECK (intent_type IN ('daily', 'weekly')),
    intent_text TEXT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    
    UNIQUE(user_id, intent_type, is_active)
);

-- Memory suggestions pending user approval
CREATE TABLE memory_suggestions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    suggested_category TEXT NOT NULL,
    suggested_content TEXT NOT NULL,
    context_chunks TEXT[],  -- Relevant chat excerpts that triggered suggestion
    confidence_score FLOAT,  -- AI confidence in suggestion relevance
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '7 days')
);

-- Memory access audit log
CREATE TABLE memory_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    action TEXT NOT NULL CHECK (action IN ('read', 'create', 'update', 'delete', 'export')),
    memory_id UUID,  -- NULL for bulk actions
    details JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

#### API endpoints / interfaces

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/functions/v1/get-memory-vault` | GET | Fetch all approved memories with metadata |
| `/functions/v1/get-pending-suggestions` | GET | Fetch AI-suggested memories awaiting approval |
| `/functions/v1/create-memory` | POST | Create new memory item |
| `/functions/v1/update-memory` | PATCH | Update existing memory |
| `/functions/v1/delete-memory` | DELETE | Soft delete (or hard delete with flag) |
| `/functions/v1/approve-suggestion` | POST | Approve AI-suggested memory |
| `/functions/v1/get-intent` | GET | Get active daily/weekly intent |
| `/functions/v1/set-intent` | POST | Create or update intent |
| `/functions/v1/clear-intent` | DELETE | Clear active intent |
| `/functions/v1/export-memories` | GET | Export all user memories as JSON |
| `/functions/v1/memory-stats` | GET | Get memory usage statistics |

#### Integration points with existing systems
- **Chat Edge Function:** Pulls approved memories for prompt assembly.
- **User Settings:** Privacy controls for memory categories and AI suggestion opt-in.
- **Home View:** Daily intent prompt integration.
- **Onboarding:** Memory opt-in during initial setup (opt-out possible).
- **Privacy Dashboard:** Memory statistics and audit log access.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions

**Memory Vault Screen**
```
┌─────────────────────────────────────────────────┐
│  Memory Vault                    [Export ∙⋅⋅]  │
├─────────────────────────────────────────────────┤
│  🔍 Search memories...                           │
│  [All] [Boundaries] [Preferences] [Triggers]    │
│  [Avoid-Topics] [Positive] [Life Context]       │
├─────────────────────────────────────────────────┤
│  + Add Memory                       [Settings]  │
├─────────────────────────────────────────────────┤
│  Memory Items (sorted by last used)             │
│  ┌─────────────────────────────────────────────┐│
│  │ 🛡️ Boundaries                              ││
│  │ "Don't ask about my ex-partner"            ││
│  │ Created: Jan 15 │ Last used: Yesterday     ││
│  │ [Edit] [Delete]                            ││
│  └─────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────┐│
│  │ 💜 Positive Reinforcement                   ││
│  │ "Gratitude exercises help me feel better"  ││
│  │ Created: Jan 10 │ Used 12 times            ││
│  │ [Edit] [Delete]                            ││
│  └─────────────────────────────────────────────┘│
├─────────────────────────────────────────────────┤
│  🤖 AI Suggested (3 pending)                    │
│  [Review suggestions →]                         │
├─────────────────────────────────────────────────┤
│  [Privacy Controls]    [Clear All Memories]     │
└─────────────────────────────────────────────────┘
```

**Memory Item Card**
```
┌──────────────────────────────────────────────────┐
│  [Category Icon]  Category Name                   │
│  "Memory content goes here"                       │
│  📅 Created: Jan 15, 2026                         │
│  🕐 Last used: Yesterday                          │
│  📊 Usage: High (used 15 times this month)        │
│  ─────────────────────────────────────────────────│
│  [✏️ Edit]  [🗑️ Delete]  [⏰ Set Expiration]     │
└──────────────────────────────────────────────────┘
```

**Memory Usage Indicator (Chat)**
```
┌──────────────────────────────────────────────────┐
│  MindFriend:                                     │
│  "I remember you're working on setting better    │
│   boundaries at work. How has that been going?"  │
│                              [🧠✨] ← Tap for info│
└──────────────────────────────────────────────────┘
```

**Intent Setting Flow**
```
┌──────────────────────────────────────────────────┐
│  Set Today's Intent                              │
├──────────────────────────────────────────────────┤
│  What's your focus for today?                    │
│  ┌────────────────────────────────────────────┐  │
│  │                                              │  │
│  │  [Text input - 140 characters]              │  │
│  │                                              │  │
│  │  "I want to stay calm during my presentation│  │
│  │   at 2pm"                                   │  │
│  │                                              │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  Examples:                                       │
│  • "Stay present and not anxious"                │
│  • "Focus on gratitude today"                    │
│  • "Be patient with myself"                      │
│                                                  │
│        [Skip]        [Save Intent]               │
└──────────────────────────────────────────────────┘
```

#### User flow diagram (text)

1. **First-time vault access:**
   - User taps Memory Vault in Settings → Sees privacy notice → Enters vault → Views empty state → Adds first memory

2. **Daily intent setting:**
   - Home shows intent banner → User taps "Set intent" → Enters intent → Saved → Chat displays intent header

3. **Memory approval flow:**
   - AI suggests memory → Appears in "Pending" section → User reviews → Approves (becomes active) or Deletes

4. **Memory management:**
   - User enters vault → Selects category filter → Finds memory → Edits content or deletes → Confirms action → Vault updates

#### Accessibility requirements
- VoiceOver labels for all memory actions (edit, delete, add).
- Dynamic Type support for all text content.
- Color-coded categories use both icon and text label (not color alone).
- Haptic feedback on memory actions.
- Full keyboard navigation support.

### 5. Edge Cases and Error Handling

| Scenario | Handling |
|----------|----------|
| Memory fetch fails | Chat proceeds without memory; show toast "Memory temporarily unavailable" |
| Intent expires | Hide from prompts; no action needed |
| Too many memories (>50) | Show warning; disable new additions until user reviews |
| AI suggestion expires | Auto-delete from pending; no notification |
| Memory exceeds character limit | Show validation error; truncate preview |
| User disables all memory categories | Fallback to intent-only personalization |
| Biometric auth fails | Allow retry; fallback to device passcode after 3 attempts |
| Export fails | Retry once; show error with retry option |
| Concurrent edits | Last-write-wins with timestamp comparison |

### 6. Testing Requirements

#### Unit tests
- Memory CRUD operations with category validation.
- Intent expiration logic (daily vs weekly).
- Category filtering and sorting.
- Search functionality.
- Audit log creation on all actions.

#### Integration tests
- Chat prompt assembly with memory injection.
- Settings sync for privacy controls.
- Biometric integration with LocalAuthentication.
- Export functionality and JSON validation.

#### UAT scenarios
- Set daily intent → Verify chat uses intent.
- Create memory → Verify in vault listing.
- Edit memory → Verify update reflected.
- Delete memory → Verify removal from AI context.
- Approve AI suggestion → Verify becomes active.
- Export memories → Verify complete data download.
- Privacy controls → Verify categories can be disabled.

### 7. Implementation Notes

#### Performance considerations
- Limit active memories per category to prevent prompt bloat (max 10 per category, 50 total).
- Cache memory data on client for fast vault access.
- Use database indexes on `user_id`, `category`, `is_active`, `last_used_at`.
- Batch memory updates where possible.

#### Security considerations
- All memory operations require valid JWT.
- RLS policies: Users can only access own memories.
- Sensitive categories (avoid_topics) get additional protection.
- Audit log immutable for compliance.

#### Phased rollout
- **Phase 1:** Basic memory vault (user-created only), daily intent.
- **Phase 2:** AI memory suggestions with opt-in.
- **Phase 3:** Advanced categories, export functionality.
- **Phase 4:** Memory analytics dashboard.

#### Future extensibility
- Memory sharing with trusted contacts (opt-in).
- Memory templates for common scenarios.
- Memory insights: "You often set X type of intent on Mondays."
- Import memories from other wellness apps (user-initiated).

## Step 3: Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Vault adoption rate | 40% of DAU within 30 days | Vault access events / DAU |
| Memory creation rate | 60% of vault users create memories | Memory creation events |
| Intent setting rate | 50% of users set weekly intent | Intent creation / unique users |
| Privacy perception score | +15% vs baseline | In-app survey |
| Chat satisfaction (with memory) | +10% vs no memory | Post-chat rating |
