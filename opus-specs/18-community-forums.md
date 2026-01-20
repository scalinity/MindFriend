# Community Forums

> Safe, moderated spaces for peer support and shared experiences at scale.

**Priority:** P3 - Nice to Have
**Effort:** High (6-8 weeks)
**Impact:** Peer support at scale; community engagement

---

## 1. Overview

### 1.1 What It Does

Public community forums for peer support:

- Topic-based discussion boards (anxiety, depression, relationships, etc.)
- Moderated posts and comments
- Upvote/helpful marking system
- Anonymous posting option
- Professional moderator and AI safety layer

### 1.2 Why It Exists

- **Scale Peer Support:** Circles are limited; forums scale infinitely
- **Shared Experience:** "I'm not alone" is powerful
- **Content Generation:** User-generated content for engagement
- **Community Building:** Creates stickiness and belonging

### 1.3 Success Metrics

| Metric               | Target       | Measurement        |
| -------------------- | ------------ | ------------------ |
| Forum participation  | 30% of users | Users with 1+ post |
| Daily active readers | 50% of DAU   | Forum views / DAU  |
| Post helpfulness     | 70%+ marked  | Helpful / Total    |
| Moderation accuracy  | 99%+         | Correct actions    |

---

## 2. Functional Requirements

### 2.1 Forum Structure

| Level    | Description                              |
| -------- | ---------------------------------------- |
| Category | High-level topic (Mental Health, Life)   |
| Board    | Specific discussion area (Anxiety, Work) |
| Thread   | Individual discussion topic              |
| Reply    | Response to thread or another reply      |

### 2.2 Core Features

| ID    | Requirement                        | Priority |
| ----- | ---------------------------------- | -------- |
| CF-01 | Browse forum categories and boards | Must     |
| CF-02 | Create new discussion threads      | Must     |
| CF-03 | Reply to threads                   | Must     |
| CF-04 | Upvote/mark as helpful             | Must     |
| CF-05 | Search forums                      | Should   |
| CF-06 | Sort by new/popular/helpful        | Should   |
| CF-07 | Save/bookmark threads              | Should   |
| CF-08 | Follow threads for updates         | Should   |
| CF-09 | Report inappropriate content       | Must     |
| CF-10 | Block users                        | Should   |

### 2.3 Anonymous Posting

| ID    | Requirement                           | Priority |
| ----- | ------------------------------------- | -------- |
| AP-01 | Option to post anonymously            | Must     |
| AP-02 | Anonymous avatar/name generated       | Must     |
| AP-03 | User identity hidden but tracked      | Must     |
| AP-04 | Anonymous users can still be reported | Must     |

### 2.4 Moderation

| ID    | Requirement                               | Priority |
| ----- | ----------------------------------------- | -------- |
| MD-01 | AI pre-screening for harmful content      | Must     |
| MD-02 | Human moderator review queue              | Must     |
| MD-03 | Remove/hide violating content             | Must     |
| MD-04 | Warn/ban repeat offenders                 | Must     |
| MD-05 | Crisis detection with automatic resources | Must     |
| MD-06 | Community guidelines enforcement          | Must     |

---

## 3. Technical Requirements

### 3.1 Data Models

```sql
-- Forum categories
CREATE TABLE forum_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    icon TEXT,
    color TEXT,
    order_index INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true
);

-- Forum boards within categories
CREATE TABLE forum_boards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id UUID NOT NULL REFERENCES forum_categories(id),
    name TEXT NOT NULL,
    description TEXT,
    icon TEXT,
    order_index INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,

    -- Stats (denormalized)
    thread_count INTEGER DEFAULT 0,
    reply_count INTEGER DEFAULT 0,
    last_post_at TIMESTAMPTZ
);

-- Discussion threads
CREATE TABLE forum_threads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    board_id UUID NOT NULL REFERENCES forum_boards(id),
    user_id UUID NOT NULL REFERENCES auth.users(id),

    -- Content
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    content_html TEXT, -- Rendered markdown

    -- Anonymity
    is_anonymous BOOLEAN DEFAULT false,
    anonymous_name TEXT, -- "Anonymous Otter"

    -- Status
    status TEXT DEFAULT 'active', -- 'active', 'locked', 'hidden', 'deleted'
    is_pinned BOOLEAN DEFAULT false,

    -- Moderation
    moderation_status TEXT DEFAULT 'approved', -- 'pending', 'approved', 'rejected'
    moderation_note TEXT,
    moderated_by UUID REFERENCES auth.users(id),
    moderated_at TIMESTAMPTZ,

    -- Stats
    view_count INTEGER DEFAULT 0,
    reply_count INTEGER DEFAULT 0,
    helpful_count INTEGER DEFAULT 0,
    last_reply_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Thread replies
CREATE TABLE forum_replies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id UUID NOT NULL REFERENCES forum_threads(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    parent_reply_id UUID REFERENCES forum_replies(id), -- For nested replies

    -- Content
    content TEXT NOT NULL,
    content_html TEXT,

    -- Anonymity (inherits from thread setting)
    is_anonymous BOOLEAN DEFAULT false,
    anonymous_name TEXT,

    -- Status
    status TEXT DEFAULT 'active', -- 'active', 'hidden', 'deleted'

    -- Moderation
    moderation_status TEXT DEFAULT 'approved',
    moderation_note TEXT,

    -- Stats
    helpful_count INTEGER DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Helpful marks (upvotes)
CREATE TABLE forum_helpful (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    thread_id UUID REFERENCES forum_threads(id),
    reply_id UUID REFERENCES forum_replies(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT one_target CHECK (
        (thread_id IS NOT NULL AND reply_id IS NULL) OR
        (thread_id IS NULL AND reply_id IS NOT NULL)
    ),
    UNIQUE(user_id, thread_id),
    UNIQUE(user_id, reply_id)
);

-- Saved threads
CREATE TABLE forum_saved (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    thread_id UUID NOT NULL REFERENCES forum_threads(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, thread_id)
);

-- Thread follows
CREATE TABLE forum_follows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    thread_id UUID NOT NULL REFERENCES forum_threads(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, thread_id)
);

-- Reports
CREATE TABLE forum_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL REFERENCES auth.users(id),
    thread_id UUID REFERENCES forum_threads(id),
    reply_id UUID REFERENCES forum_replies(id),

    reason TEXT NOT NULL, -- 'spam', 'harassment', 'harmful', 'crisis', 'other'
    details TEXT,

    status TEXT DEFAULT 'pending', -- 'pending', 'reviewed', 'actioned', 'dismissed'
    reviewed_by UUID REFERENCES auth.users(id),
    reviewed_at TIMESTAMPTZ,
    action_taken TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User bans
CREATE TABLE forum_bans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    banned_by UUID NOT NULL REFERENCES auth.users(id),

    reason TEXT NOT NULL,
    expires_at TIMESTAMPTZ, -- NULL for permanent

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE forum_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_boards ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_replies ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_helpful ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_saved ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_reports ENABLE ROW LEVEL SECURITY;

-- Public read access
CREATE POLICY "Categories readable" ON forum_categories FOR SELECT USING (is_active = true);
CREATE POLICY "Boards readable" ON forum_boards FOR SELECT USING (is_active = true);
CREATE POLICY "Approved threads readable"
    ON forum_threads FOR SELECT
    USING (moderation_status = 'approved' AND status = 'active');
CREATE POLICY "Approved replies readable"
    ON forum_replies FOR SELECT
    USING (moderation_status = 'approved' AND status = 'active');

-- User-specific write access
CREATE POLICY "Users create threads"
    ON forum_threads FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users create replies"
    ON forum_replies FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users manage own helpful"
    ON forum_helpful FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users manage own saved"
    ON forum_saved FOR ALL USING (auth.uid() = user_id);

-- Indexes
CREATE INDEX idx_threads_board ON forum_threads(board_id, created_at DESC) WHERE status = 'active';
CREATE INDEX idx_replies_thread ON forum_replies(thread_id, created_at ASC) WHERE status = 'active';
CREATE INDEX idx_reports_pending ON forum_reports(status, created_at) WHERE status = 'pending';
```

### 3.2 Edge Function: Content Moderation

```typescript
// supabase/functions/moderate-forum-content/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const XAI_API_KEY = Deno.env.get("XAI_API_KEY")!;

interface ModerationRequest {
  contentType: "thread" | "reply";
  contentId: string;
  content: string;
  title?: string;
}

interface ModerationResult {
  approved: boolean;
  flags: string[];
  isCrisis: boolean;
  confidence: number;
}

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { contentType, contentId, content, title }: ModerationRequest =
    await req.json();

  // AI moderation check
  const moderationResult = await checkContent(content, title);

  const table = contentType === "thread" ? "forum_threads" : "forum_replies";

  if (moderationResult.isCrisis) {
    // Crisis detected - approve but flag for follow-up
    await supabase
      .from(table)
      .update({
        moderation_status: "approved",
        moderation_note: "Crisis content detected - resources shown",
      })
      .eq("id", contentId);

    // Log crisis event
    const { data: contentData } = await supabase
      .from(table)
      .select("user_id")
      .eq("id", contentId)
      .single();

    if (contentData) {
      await supabase.from("crisis_events").insert({
        user_id: contentData.user_id,
        source: "forum",
        content_preview: content.substring(0, 200),
      });
    }

    return new Response(
      JSON.stringify({
        approved: true,
        showCrisisResources: true,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  if (!moderationResult.approved) {
    // Content rejected
    await supabase
      .from(table)
      .update({
        moderation_status: "rejected",
        moderation_note: `Flagged: ${moderationResult.flags.join(", ")}`,
      })
      .eq("id", contentId);

    return new Response(
      JSON.stringify({
        approved: false,
        reason: "Content violates community guidelines",
        flags: moderationResult.flags,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  // Content approved
  await supabase
    .from(table)
    .update({ moderation_status: "approved" })
    .eq("id", contentId);

  // Update board stats
  if (contentType === "thread") {
    const { data: thread } = await supabase
      .from("forum_threads")
      .select("board_id")
      .eq("id", contentId)
      .single();

    if (thread) {
      await supabase.rpc("increment_board_thread_count", {
        board_id: thread.board_id,
      });
    }
  }

  return new Response(JSON.stringify({ approved: true }), {
    headers: { "Content-Type": "application/json" },
  });
});

async function checkContent(
  content: string,
  title?: string,
): Promise<ModerationResult> {
  const fullText = title ? `${title}\n\n${content}` : content;

  const response = await fetch("https://api.x.ai/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${XAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "grok-3-mini",
      messages: [
        {
          role: "system",
          content: `You are a content moderator for a mental health support forum. Analyze the following post and return a JSON object with:
- approved: boolean (true if content is safe and appropriate)
- flags: string[] (any concerning elements: 'spam', 'harassment', 'harmful_advice', 'graphic_content', 'personal_info', 'promotion')
- isCrisis: boolean (true if user expresses self-harm, suicide ideation, or immediate danger)
- confidence: number 0-1

Be lenient with people sharing struggles - the forum is for support. Flag only clear violations.`,
        },
        {
          role: "user",
          content: fullText,
        },
      ],
      response_format: { type: "json_object" },
    }),
  });

  const data = await response.json();
  return JSON.parse(data.choices[0].message.content);
}
```

### 3.3 Swift Models

```swift
struct ForumCategory: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String?
    let icon: String?
    let color: String?
    let orderIndex: Int
}

struct ForumBoard: Codable, Identifiable {
    let id: UUID
    let categoryId: UUID
    let name: String
    let description: String?
    let icon: String?
    let threadCount: Int
    let replyCount: Int
    let lastPostAt: Date?
}

struct ForumThread: Codable, Identifiable {
    let id: UUID
    let boardId: UUID
    let userId: UUID
    let title: String
    let content: String
    let contentHtml: String?
    let isAnonymous: Bool
    let anonymousName: String?
    let status: ThreadStatus
    let isPinned: Bool
    let viewCount: Int
    let replyCount: Int
    let helpfulCount: Int
    let lastReplyAt: Date?
    let createdAt: Date

    // Joined data
    var author: ForumAuthor?
    var isHelpfulByMe: Bool?
    var isSavedByMe: Bool?
}

struct ForumReply: Codable, Identifiable {
    let id: UUID
    let threadId: UUID
    let userId: UUID
    let parentReplyId: UUID?
    let content: String
    let contentHtml: String?
    let isAnonymous: Bool
    let anonymousName: String?
    let helpfulCount: Int
    let createdAt: Date

    // Joined data
    var author: ForumAuthor?
    var isHelpfulByMe: Bool?
}

struct ForumAuthor: Codable {
    let id: UUID
    let displayName: String?
    let avatarUrl: String?
    let isAnonymous: Bool
    let anonymousName: String?

    var displayedName: String {
        if isAnonymous {
            return anonymousName ?? "Anonymous"
        }
        return displayName ?? "User"
    }
}

enum ThreadStatus: String, Codable {
    case active
    case locked
    case hidden
    case deleted
}

enum ReportReason: String, Codable, CaseIterable {
    case spam
    case harassment
    case harmful = "harmful"
    case crisis
    case other

    var description: String {
        switch self {
        case .spam: return "Spam or advertising"
        case .harassment: return "Harassment or bullying"
        case .harmful: return "Harmful advice or content"
        case .crisis: return "User may need immediate help"
        case .other: return "Other concern"
        }
    }
}
```

---

## 4. UI/UX Specifications

### 4.1 Forum Home

```
┌─────────────────────────────────┐
│ Community                   🔍  │
├─────────────────────────────────┤
│                                 │
│ Welcome to the MindFriend       │
│ Community! Share, support, grow.│
│                                 │
│ Mental Health                   │
│ ┌─────────────────────────────┐ │
│ │ 😰 Anxiety & Stress         │ │
│ │    1.2k threads • Active now│ │
│ ├─────────────────────────────┤ │
│ │ 😢 Depression               │ │
│ │    890 threads • 2m ago     │ │
│ ├─────────────────────────────┤ │
│ │ 🧠 General Mental Health    │ │
│ │    654 threads • 5m ago     │ │
│ └─────────────────────────────┘ │
│                                 │
│ Life & Relationships            │
│ ┌─────────────────────────────┐ │
│ │ 💼 Work & Career            │ │
│ │    432 threads • 15m ago    │ │
│ ├─────────────────────────────┤ │
│ │ ❤️ Relationships            │ │
│ │    567 threads • 8m ago     │ │
│ └─────────────────────────────┘ │
│                                 │
│ [+ Start New Discussion]        │
│                                 │
└─────────────────────────────────┘
```

### 4.2 Board View

```
┌─────────────────────────────────┐
│ ← Anxiety & Stress          +   │
├─────────────────────────────────┤
│                                 │
│ [New] [Popular] [Helpful]       │
│                                 │
│ 📌 Welcome & Community Rules    │
│    Pinned • 234 replies         │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Does anyone else feel worse │ │
│ │ in the morning?             │ │
│ │                             │ │
│ │ I wake up with this heavy   │ │
│ │ feeling every day...        │ │
│ │                             │ │
│ │ Anonymous Otter • 2h ago    │ │
│ │ 💬 23 replies  ❤️ 45 helpful │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Tips that helped my panic   │ │
│ │ attacks                     │ │
│ │                             │ │
│ │ After 2 years of struggling │ │
│ │ I finally found what works..│ │
│ │                             │ │
│ │ Sarah • 5h ago              │ │
│ │ 💬 67 replies  ❤️ 128 helpful│ │
│ └─────────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

### 4.3 Thread View

```
┌─────────────────────────────────┐
│ ← Thread                    ⋮   │
├─────────────────────────────────┤
│                                 │
│ Does anyone else feel worse     │
│ in the morning?                 │
│                                 │
│ I wake up with this heavy       │
│ feeling every day. It's like    │
│ dread before I even get out of  │
│ bed. By evening I feel better   │
│ but mornings are so hard.       │
│                                 │
│ Anyone relate?                  │
│                                 │
│ 🐻 Anonymous Otter • 2h ago     │
│ 💬 23  ❤️ 45  🔖 Save  ⚑ Report │
│                                 │
│ ─────────────────────────────── │
│                                 │
│ 23 Replies                      │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Sarah                       │ │
│ │ Yes! Morning anxiety is so  │ │
│ │ real. I started doing 5 min │ │
│ │ of breathing before getting │ │
│ │ up and it helps a lot.      │ │
│ │                             │ │
│ │ 1h ago • ❤️ 28 helpful      │ │
│ │           [Reply] [Helpful] │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 🦊 Anonymous Fox            │ │
│ │ Same here. My therapist     │ │
│ │ said cortisol peaks in the  │ │
│ │ morning which can cause...  │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Write a reply...            │ │
│ │              [Post Reply]   │ │
│ └─────────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

---

## 5. Acceptance Criteria

- [ ] Users can browse categories and boards
- [ ] Users can create threads (with optional anonymity)
- [ ] Users can reply to threads
- [ ] Helpful marking system works
- [ ] Search returns relevant results
- [ ] Content moderation catches violations
- [ ] Crisis content triggers resources
- [ ] Report system works
- [ ] Users can save/follow threads

---

## 6. Community Guidelines

```markdown
# MindFriend Community Guidelines

## Be Kind & Supportive

- Share your experiences with compassion
- Validate others' feelings
- Avoid judgment or criticism

## Stay Safe

- Never share personal identifying information
- Don't ask for or give medical advice
- Use the anonymous option if needed

## No Harmful Content

- No promotion of self-harm or harmful behaviors
- No harassment, bullying, or discrimination
- No spam or self-promotion

## Get Help When Needed

- If you're in crisis, use our crisis resources
- Report content that concerns you
- Reach out to professionals for medical advice

Violations may result in content removal or account restrictions.
```

---

## 7. Rollout Plan

### Phase 1 (Week 1-2)

- Forum data model
- Categories and boards
- Basic threading

### Phase 2 (Week 3-4)

- AI moderation integration
- Report system
- Anonymous posting

### Phase 3 (Week 5-6)

- Search functionality
- Helpful/save/follow features
- Notifications

### Phase 4 (Week 7-8)

- Moderator tools
- Ban system
- Analytics dashboard
