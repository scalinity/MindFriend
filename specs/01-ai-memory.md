# AI Memory That Matters

## Overview

**Goal:** The AI remembers context across conversations, making users feel genuinely understood.

**Why it matters:** This is MindFriend's biggest differentiation opportunity. Most AI apps don't remember anything between sessions. When MindFriend's AI asks "How did that presentation go?" a week after you mentioned it, users feel emotionally connected. This drives retention through personalization that competitors can't easily replicate.

**Impact:** P1 priority - Differentiation + emotional hook

---

## User Stories

- As a user, I want the AI to remember important things I've shared so that I don't have to repeat myself
- As a user, I want the AI to follow up on past events so that it feels like talking to a friend who cares
- As a user, I want to see and manage what the AI remembers about me so that I feel in control of my data
- As a user, I want the AI to remember my preferences so that responses feel personalized

---

## Product Requirements

### Must Have (MVP)

1. **Memory Extraction**: Automatically detect and store key facts from conversations
   - People: names of family, friends, pets, coworkers
   - Events: upcoming events, past experiences
   - Preferences: likes, dislikes, communication style
   - Facts: job, location, hobbies

2. **Memory Injection**: Include relevant memories in AI system prompt
   - Retrieve top 10 most relevant memories per conversation
   - Inject before user's message for context

3. **Memory Management UI**: Settings screen to view/delete memories
   - List all memories grouped by type
   - Delete individual memories
   - "Clear all memories" option

4. **Memory Types with Expiry**:
   - Events: auto-expire 7 days after the date
   - People/Facts: permanent unless deleted
   - Preferences: permanent unless deleted

### Nice to Have (V2)

- Memory confidence scoring (only inject high-confidence memories)
- Manual memory creation ("Remember that I...")
- Memory editing
- Memory export
- Conversation summaries as memory source
- Proactive memory-based suggestions

### Out of Scope

- Cross-device memory sync (handled by Supabase)
- Shared memories with circle members
- Memory-based AI personality changes

---

## Technical Design

### Data Model Changes

**New Table: `memory_fragments`**

```sql
-- Migration: 20260115_add_memory_fragments.sql

CREATE TABLE memory_fragments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  fragment_type TEXT NOT NULL CHECK (fragment_type IN ('person', 'event', 'preference', 'fact')),
  key TEXT NOT NULL,           -- e.g., 'dog_name', 'upcoming_presentation', 'favorite_exercise'
  value TEXT NOT NULL,         -- e.g., 'Max', 'Friday presentation at work', 'breathing'
  confidence FLOAT DEFAULT 0.8 CHECK (confidence >= 0 AND confidence <= 1),
  extracted_at TIMESTAMPTZ DEFAULT NOW(),
  source_conversation_id UUID REFERENCES conversations(id) ON DELETE SET NULL,
  source_message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
  expires_at TIMESTAMPTZ,      -- NULL for permanent, set for events
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, fragment_type, key)  -- Prevent duplicate memories
);

-- Indexes
CREATE INDEX idx_memory_fragments_user_id ON memory_fragments(user_id);
CREATE INDEX idx_memory_fragments_expires ON memory_fragments(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX idx_memory_fragments_type ON memory_fragments(user_id, fragment_type);

-- RLS Policies
ALTER TABLE memory_fragments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own memories"
  ON memory_fragments FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own memories"
  ON memory_fragments FOR DELETE
  USING (auth.uid() = user_id);

-- Only Edge Function can insert/update (via service role)
CREATE POLICY "Service role can manage memories"
  ON memory_fragments FOR ALL
  USING (auth.role() = 'service_role');
```

### iOS Implementation

**New Model** (`Core/Models.swift`):

```swift
struct MemoryFragment: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let fragmentType: MemoryType
    let key: String
    let value: String
    let confidence: Double
    let extractedAt: Date
    let expiresAt: Date?

    enum MemoryType: String, Codable, CaseIterable {
        case person
        case event
        case preference
        case fact

        var displayName: String {
            switch self {
            case .person: return "People"
            case .event: return "Events"
            case .preference: return "Preferences"
            case .fact: return "Facts"
            }
        }

        var icon: String {
            switch self {
            case .person: return "person.fill"
            case .event: return "calendar"
            case .preference: return "heart.fill"
            case .fact: return "info.circle.fill"
            }
        }
    }
}
```

**Service Methods** (`Networking/Services/SupabaseDataService.swift`):

```swift
// MARK: - Memory Management

func getMemories() async throws -> [MemoryFragment] {
    let memories: [MemoryFragment] = try await supabase
        .from("memory_fragments")
        .select()
        .order("extracted_at", ascending: false)
        .execute()
        .value
    return memories
}

func deleteMemory(id: UUID) async throws {
    try await supabase
        .from("memory_fragments")
        .delete()
        .eq("id", id)
        .execute()
}

func deleteAllMemories() async throws {
    try await supabase
        .from("memory_fragments")
        .delete()
        .eq("user_id", try await getCurrentUserId())
        .execute()
}
```

**New View** (`Features/Profile/MemorySettingsView.swift`):

```swift
struct MemorySettingsView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var memories: [MemoryFragment] = []
    @State private var isLoading = true
    @State private var showDeleteAllConfirmation = false

    var groupedMemories: [MemoryFragment.MemoryType: [MemoryFragment]] {
        Dictionary(grouping: memories, by: { $0.fragmentType })
    }

    var body: some View {
        List {
            ForEach(MemoryFragment.MemoryType.allCases, id: \.self) { type in
                if let typeMemories = groupedMemories[type], !typeMemories.isEmpty {
                    Section(header: Label(type.displayName, systemImage: type.icon)) {
                        ForEach(typeMemories) { memory in
                            MemoryRow(memory: memory)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task { await deleteMemory(memory) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle("AI Memory")
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Clear All") {
                    showDeleteAllConfirmation = true
                }
                .foregroundColor(.red)
            }
        }
        .confirmationDialog("Clear all memories?", isPresented: $showDeleteAllConfirmation) {
            Button("Clear All", role: .destructive) {
                Task { await deleteAllMemories() }
            }
        }
        .task { await loadMemories() }
    }
}
```

### Backend Implementation

**Edge Function Changes** (`supabase/functions/chat/index.ts`):

```typescript
// Add to chat function

interface MemoryFragment {
  id: string;
  fragment_type: string;
  key: string;
  value: string;
  confidence: number;
  expires_at: string | null;
}

// 1. Retrieve relevant memories before generating response
async function getRelevantMemories(
  supabase: SupabaseClient,
  userId: string,
  limit: number = 10,
): Promise<MemoryFragment[]> {
  const now = new Date().toISOString();

  const { data, error } = await supabase
    .from("memory_fragments")
    .select("*")
    .eq("user_id", userId)
    .or(`expires_at.is.null,expires_at.gt.${now}`)
    .order("confidence", { ascending: false })
    .limit(limit);

  if (error) {
    console.error("Error fetching memories:", error);
    return [];
  }

  return data || [];
}

// 2. Format memories for system prompt
function formatMemoriesForPrompt(memories: MemoryFragment[]): string {
  if (memories.length === 0) return "";

  const grouped = memories.reduce(
    (acc, m) => {
      if (!acc[m.fragment_type]) acc[m.fragment_type] = [];
      acc[m.fragment_type].push(`${m.key}: ${m.value}`);
      return acc;
    },
    {} as Record<string, string[]>,
  );

  let prompt = "\n\nHere is what you remember about this user:\n";

  if (grouped.person?.length) {
    prompt += `\nPeople in their life: ${grouped.person.join(", ")}`;
  }
  if (grouped.event?.length) {
    prompt += `\nRecent/upcoming events: ${grouped.event.join(", ")}`;
  }
  if (grouped.preference?.length) {
    prompt += `\nTheir preferences: ${grouped.preference.join(", ")}`;
  }
  if (grouped.fact?.length) {
    prompt += `\nFacts about them: ${grouped.fact.join(", ")}`;
  }

  prompt +=
    "\n\nUse this context naturally in conversation when relevant. Reference past events to show you remember.";

  return prompt;
}

// 3. Extract memories from user message
async function extractMemories(
  supabase: SupabaseClient,
  userId: string,
  conversationId: string,
  messageId: string,
  userContent: string,
  aiClient: any,
): Promise<void> {
  // Use AI to extract structured memories
  const extractionPrompt = `Extract key facts from this user message. Return JSON array of memories or empty array if none found.

Message: "${userContent}"

Extract:
- People mentioned (names of family, friends, pets, coworkers)
- Events (upcoming or past events with dates if mentioned)
- Preferences (likes, dislikes, favorites)
- Facts (job, location, hobbies)

Format: [{"type": "person|event|preference|fact", "key": "short_key", "value": "description", "expires_days": null|number}]

Only extract clear, specific facts. Ignore vague statements. Return [] if nothing concrete.`;

  try {
    const extraction = await aiClient.chat.completions.create({
      model: "grok-3-mini-fast",
      messages: [{ role: "user", content: extractionPrompt }],
      max_tokens: 500,
      temperature: 0.3,
    });

    const content = extraction.choices[0]?.message?.content || "[]";
    const memories = JSON.parse(content);

    for (const memory of memories) {
      const expiresAt = memory.expires_days
        ? new Date(
            Date.now() + memory.expires_days * 24 * 60 * 60 * 1000,
          ).toISOString()
        : null;

      // Upsert to handle duplicates
      await supabase.from("memory_fragments").upsert(
        {
          user_id: userId,
          fragment_type: memory.type,
          key: memory.key,
          value: memory.value,
          confidence: 0.8,
          source_conversation_id: conversationId,
          source_message_id: messageId,
          expires_at: expiresAt,
          updated_at: new Date().toISOString(),
        },
        {
          onConflict: "user_id,fragment_type,key",
          ignoreDuplicates: false,
        },
      );
    }
  } catch (error) {
    console.error("Memory extraction error:", error);
    // Non-blocking - don't fail chat if memory extraction fails
  }
}

// 4. Integrate into main chat flow
// In the main handler, before calling AI:
const memories = await getRelevantMemories(supabaseAdmin, user.id);
const memoryContext = formatMemoriesForPrompt(memories);
const systemPromptWithMemory = SYSTEM_PROMPT + memoryContext;

// After saving user message, extract memories (async, non-blocking)
extractMemories(
  supabaseAdmin,
  user.id,
  conversationId,
  userMessageId,
  content,
  aiClient,
).catch((err) => console.error("Background memory extraction failed:", err));
```

### API Contract

**Get Memories:**

```
GET /rest/v1/memory_fragments
Authorization: Bearer <jwt>

Response: MemoryFragment[]
```

**Delete Memory:**

```
DELETE /rest/v1/memory_fragments?id=eq.<uuid>
Authorization: Bearer <jwt>

Response: 204 No Content
```

**Delete All Memories:**

```
DELETE /rest/v1/memory_fragments?user_id=eq.<user_id>
Authorization: Bearer <jwt>

Response: 204 No Content
```

---

## UI/UX

### Memory Settings Screen

```
┌─────────────────────────────────────┐
│ < Settings     AI Memory    Clear All│
├─────────────────────────────────────┤
│                                     │
│ 👤 PEOPLE                           │
│ ┌─────────────────────────────────┐ │
│ │ Dog: Max                    ← × │ │
│ │ Partner: Sarah              ← × │ │
│ │ Boss: Michael               ← × │ │
│ └─────────────────────────────────┘ │
│                                     │
│ 📅 EVENTS                           │
│ ┌─────────────────────────────────┐ │
│ │ Presentation: Friday work   ← × │ │
│ │ Vacation: Beach trip in Feb ← × │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ❤️ PREFERENCES                      │
│ ┌─────────────────────────────────┐ │
│ │ Favorite exercise: Breathing← × │ │
│ │ Prefers: Morning check-ins  ← × │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ℹ️ FACTS                            │
│ ┌─────────────────────────────────┐ │
│ │ Job: Software engineer      ← × │ │
│ │ Location: San Francisco     ← × │ │
│ └─────────────────────────────────┘ │
│                                     │
└─────────────────────────────────────┘
```

### Navigation Path

```
Profile → Settings → AI Memory
```

---

## Verification

### Manual Testing

1. **Memory Extraction:**
   - Send chat message: "I have a big presentation on Friday"
   - Check `memory_fragments` table for new entry
   - Send another message in new conversation
   - Verify AI references the presentation

2. **Memory Injection:**
   - Create memories manually in DB for test user
   - Start new chat conversation
   - Verify AI uses memory context naturally

3. **Memory Management:**
   - Navigate to Profile → Settings → AI Memory
   - Verify all memories appear grouped by type
   - Delete individual memory, verify removed
   - "Clear All" → verify all memories deleted

4. **Event Expiry:**
   - Create event memory with `expires_at` in past
   - Verify it's not injected into new conversations

### Automated Tests

```swift
// MemoryServiceTests.swift
func testGetMemories() async throws {
    let memories = try await service.getMemories()
    XCTAssertTrue(memories.count >= 0)
}

func testDeleteMemory() async throws {
    // Create test memory
    let memoryId = UUID()
    // Delete it
    try await service.deleteMemory(id: memoryId)
    // Verify deleted
}
```

---

## Dependencies

- Chat Edge Function must be working
- Profiles table must exist
- Conversations/messages tables must exist

---

## Risks & Mitigations

| Risk                         | Likelihood | Impact | Mitigation                                                      |
| ---------------------------- | ---------- | ------ | --------------------------------------------------------------- |
| Memory extraction inaccurate | Medium     | Low    | Conservative extraction, user can delete mistakes               |
| Privacy concerns             | Medium     | High   | Clear UI to view/delete all memories, transparent about storage |
| Memory bloat over time       | Low        | Medium | Implement memory limits (e.g., 100 per user), expire old events |
| AI extraction costs          | Low        | Low    | Use fast/cheap model for extraction, batch process              |
| Memories feel creepy         | Medium     | Medium | Only reference memories naturally, don't over-personalize       |

---

## Implementation Estimate

| Task                   | Effort       |
| ---------------------- | ------------ |
| Database migration     | 1 hour       |
| iOS Models + Service   | 2 hours      |
| iOS MemorySettingsView | 3 hours      |
| Edge Function changes  | 4 hours      |
| Testing                | 2 hours      |
| **Total**              | **12 hours** |
