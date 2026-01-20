# Therapy App Integration

> Connect MindFriend data with therapy/EHR platforms for seamless care coordination.

**Priority:** P3 - Nice to Have
**Effort:** High (6-8 weeks)
**Impact:** Ecosystem positioning; therapist partnerships

---

## 1. Overview

### 1.1 What It Does

Integration layer connecting MindFriend with therapy platforms:

- Export mood/journal data to therapist portals
- Import assignments from therapists
- Sync with EHR systems (with consent)
- Therapist dashboard to view client progress
- Bidirectional data sharing with privacy controls

### 1.2 Why It Exists

- **Continuity of Care:** Bridge between sessions
- **Therapist Efficiency:** Pre-session insights save time
- **User Value:** "My therapist can see my progress"
- **B2B Opportunity:** Sell to therapy practices
- **Competitive Moat:** Deep integration = switching cost

### 1.3 Success Metrics

| Metric                 | Target       | Measurement           |
| ---------------------- | ------------ | --------------------- |
| Therapist connections  | 5% of users  | Users linked          |
| Data share rate        | 80%+ consent | Consented / Connected |
| Therapist satisfaction | 4.5+/5       | NPS survey            |
| Practice partnerships  | 50+ in Y1    | Signed agreements     |

---

## 2. Functional Requirements

### 2.1 User Features

| ID    | Requirement                   | Priority |
| ----- | ----------------------------- | -------- |
| UF-01 | Invite therapist to connect   | Must     |
| UF-02 | Choose what data to share     | Must     |
| UF-03 | Revoke access anytime         | Must     |
| UF-04 | View what therapist can see   | Must     |
| UF-05 | Receive therapist assignments | Should   |
| UF-06 | Export data as PDF report     | Should   |
| UF-07 | Connect to multiple providers | Should   |

### 2.2 Therapist Features

| ID    | Requirement                             | Priority |
| ----- | --------------------------------------- | -------- |
| TF-01 | Accept client connection requests       | Must     |
| TF-02 | View shared client data dashboard       | Must     |
| TF-03 | Assign exercises/prompts to clients     | Should   |
| TF-04 | Pre-session summaries                   | Should   |
| TF-05 | Crisis alerts for connected clients     | Must     |
| TF-06 | Manage multiple clients                 | Must     |
| TF-07 | Notes (private, not shared with client) | Should   |

### 2.3 Integration Features

| ID    | Requirement                   | Priority |
| ----- | ----------------------------- | -------- |
| IF-01 | API for EHR integration       | Should   |
| IF-02 | SimplePractice integration    | Should   |
| IF-03 | TherapyNotes integration      | Could    |
| IF-04 | FHIR-compliant data export    | Could    |
| IF-05 | Webhook for real-time updates | Should   |

---

## 3. Technical Requirements

### 3.1 Data Models

```sql
-- Therapist verification (extends profiles)
CREATE TABLE therapist_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,

    -- Verification
    is_verified BOOLEAN DEFAULT false,
    license_number TEXT,
    license_state TEXT,
    license_verified_at TIMESTAMPTZ,
    npi_number TEXT, -- National Provider Identifier

    -- Practice info
    practice_name TEXT,
    practice_address TEXT,
    specialties TEXT[],

    -- Settings
    accepts_invites BOOLEAN DEFAULT true,
    max_clients INTEGER DEFAULT 100,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Client-therapist connections
CREATE TABLE therapy_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    therapist_id UUID NOT NULL REFERENCES therapist_accounts(id) ON DELETE CASCADE,

    -- Status
    status TEXT DEFAULT 'pending', -- 'pending', 'active', 'revoked', 'ended'
    invited_by TEXT NOT NULL, -- 'client' or 'therapist'

    -- Data sharing permissions (client controls)
    share_mood BOOLEAN DEFAULT true,
    share_journal BOOLEAN DEFAULT false,
    share_assessments BOOLEAN DEFAULT true,
    share_exercises BOOLEAN DEFAULT false,
    share_chat_summary BOOLEAN DEFAULT false,

    -- Crisis handling
    crisis_alerts_enabled BOOLEAN DEFAULT true,

    -- Dates
    connected_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(client_id, therapist_id)
);

-- Therapist assignments to clients
CREATE TABLE therapist_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id UUID NOT NULL REFERENCES therapy_connections(id) ON DELETE CASCADE,

    -- Assignment details
    title TEXT NOT NULL,
    description TEXT,
    assignment_type TEXT, -- 'exercise', 'journal_prompt', 'mood_tracking', 'custom'

    -- Linked content
    exercise_id UUID REFERENCES exercises(id),
    journal_prompt TEXT,

    -- Schedule
    due_date DATE,
    frequency TEXT, -- 'once', 'daily', 'weekly'

    -- Status
    status TEXT DEFAULT 'assigned', -- 'assigned', 'completed', 'skipped', 'expired'
    completed_at TIMESTAMPTZ,
    client_notes TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Therapist notes (private to therapist)
CREATE TABLE therapist_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id UUID NOT NULL REFERENCES therapy_connections(id) ON DELETE CASCADE,
    therapist_id UUID NOT NULL REFERENCES therapist_accounts(id),

    content TEXT NOT NULL,
    session_date DATE,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- API access for integrations
CREATE TABLE integration_api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    therapist_id UUID NOT NULL REFERENCES therapist_accounts(id) ON DELETE CASCADE,

    api_key_hash TEXT NOT NULL, -- Hashed key
    name TEXT NOT NULL,
    permissions TEXT[], -- ['read_mood', 'read_assessments', 'write_assignments']

    -- Rate limiting
    rate_limit_per_hour INTEGER DEFAULT 1000,

    -- Status
    is_active BOOLEAN DEFAULT true,
    last_used_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Audit log for data access
CREATE TABLE therapy_access_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id UUID NOT NULL REFERENCES therapy_connections(id),
    therapist_id UUID NOT NULL,

    action TEXT NOT NULL, -- 'view_mood', 'view_journal', 'export_data'
    resource_type TEXT,
    resource_id UUID,

    ip_address TEXT,
    user_agent TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE therapist_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE therapy_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE therapist_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE therapist_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE therapy_access_log ENABLE ROW LEVEL SECURITY;

-- Therapists manage own account
CREATE POLICY "Therapists manage own account"
    ON therapist_accounts FOR ALL USING (auth.uid() = user_id);

-- Connection visibility
CREATE POLICY "Users see own connections"
    ON therapy_connections FOR SELECT
    USING (
        auth.uid() = client_id OR
        auth.uid() IN (SELECT user_id FROM therapist_accounts WHERE id = therapist_id)
    );

CREATE POLICY "Clients can update sharing settings"
    ON therapy_connections FOR UPDATE
    USING (auth.uid() = client_id);

-- Assignments visible to both parties
CREATE POLICY "Assignments visible to connection"
    ON therapist_assignments FOR SELECT
    USING (connection_id IN (
        SELECT id FROM therapy_connections
        WHERE client_id = auth.uid() OR
        therapist_id IN (SELECT id FROM therapist_accounts WHERE user_id = auth.uid())
    ));

-- Therapist notes only visible to therapist
CREATE POLICY "Therapist notes private"
    ON therapist_notes FOR ALL
    USING (therapist_id IN (SELECT id FROM therapist_accounts WHERE user_id = auth.uid()));

-- Indexes
CREATE INDEX idx_connections_client ON therapy_connections(client_id) WHERE status = 'active';
CREATE INDEX idx_connections_therapist ON therapy_connections(therapist_id) WHERE status = 'active';
CREATE INDEX idx_assignments_connection ON therapist_assignments(connection_id, status);
```

### 3.2 Edge Function: Therapist API

```typescript
// supabase/functions/therapist-api/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createHash } from "https://deno.land/std@0.177.0/hash/mod.ts";

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Authenticate API key
  const apiKey = req.headers.get("X-API-Key");
  if (!apiKey) {
    return new Response("Unauthorized", { status: 401 });
  }

  const keyHash = createHash("sha256").update(apiKey).toString();

  const { data: apiKeyRecord } = await supabase
    .from("integration_api_keys")
    .select("*, therapist_accounts(*)")
    .eq("api_key_hash", keyHash)
    .eq("is_active", true)
    .single();

  if (!apiKeyRecord) {
    return new Response("Invalid API key", { status: 401 });
  }

  // Check expiration
  if (
    apiKeyRecord.expires_at &&
    new Date(apiKeyRecord.expires_at) < new Date()
  ) {
    return new Response("API key expired", { status: 401 });
  }

  const therapistId = apiKeyRecord.therapist_id;
  const url = new URL(req.url);
  const path = url.pathname.replace("/therapist-api", "");

  // Update last used
  await supabase
    .from("integration_api_keys")
    .update({ last_used_at: new Date().toISOString() })
    .eq("id", apiKeyRecord.id);

  // Route handling
  switch (true) {
    case path === "/clients" && req.method === "GET":
      return getClients(supabase, therapistId);

    case path.match(/^\/clients\/[\w-]+\/mood$/) && req.method === "GET":
      const clientId = path.split("/")[2];
      return getClientMood(
        supabase,
        therapistId,
        clientId,
        apiKeyRecord.permissions,
      );

    case path.match(/^\/clients\/[\w-]+\/assessments$/) && req.method === "GET":
      const assessClientId = path.split("/")[2];
      return getClientAssessments(
        supabase,
        therapistId,
        assessClientId,
        apiKeyRecord.permissions,
      );

    case path.match(/^\/clients\/[\w-]+\/assignments$/) &&
      req.method === "POST":
      const assignClientId = path.split("/")[2];
      const body = await req.json();
      return createAssignment(
        supabase,
        therapistId,
        assignClientId,
        body,
        apiKeyRecord.permissions,
      );

    default:
      return new Response("Not found", { status: 404 });
  }
});

async function getClients(supabase: any, therapistId: string) {
  const { data: connections } = await supabase
    .from("therapy_connections")
    .select(
      `
      id,
      client_id,
      share_mood,
      share_journal,
      share_assessments,
      connected_at,
      profiles!therapy_connections_client_id_fkey (
        display_name,
        avatar_url
      )
    `,
    )
    .eq("therapist_id", therapistId)
    .eq("status", "active");

  return new Response(JSON.stringify({ clients: connections }), {
    headers: { "Content-Type": "application/json" },
  });
}

async function getClientMood(
  supabase: any,
  therapistId: string,
  clientId: string,
  permissions: string[],
) {
  if (!permissions.includes("read_mood")) {
    return new Response("Permission denied", { status: 403 });
  }

  // Verify connection and permission
  const { data: connection } = await supabase
    .from("therapy_connections")
    .select()
    .eq("therapist_id", therapistId)
    .eq("client_id", clientId)
    .eq("status", "active")
    .eq("share_mood", true)
    .single();

  if (!connection) {
    return new Response("No access to this client's mood data", {
      status: 403,
    });
  }

  // Get mood data (last 30 days)
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  const { data: moods } = await supabase
    .from("moods")
    .select("id, score, emotions, notes, logged_at")
    .eq("user_id", clientId)
    .gte("logged_at", thirtyDaysAgo.toISOString())
    .order("logged_at", { ascending: false });

  // Log access
  await supabase.from("therapy_access_log").insert({
    connection_id: connection.id,
    therapist_id: therapistId,
    action: "view_mood",
    resource_type: "mood",
  });

  return new Response(JSON.stringify({ moods }), {
    headers: { "Content-Type": "application/json" },
  });
}

async function getClientAssessments(
  supabase: any,
  therapistId: string,
  clientId: string,
  permissions: string[],
) {
  if (!permissions.includes("read_assessments")) {
    return new Response("Permission denied", { status: 403 });
  }

  const { data: connection } = await supabase
    .from("therapy_connections")
    .select()
    .eq("therapist_id", therapistId)
    .eq("client_id", clientId)
    .eq("status", "active")
    .eq("share_assessments", true)
    .single();

  if (!connection) {
    return new Response("No access", { status: 403 });
  }

  const { data: assessments } = await supabase
    .from("assessment_responses")
    .select(
      `
      *,
      assessment_types (code, name)
    `,
    )
    .eq("user_id", clientId)
    .order("completed_at", { ascending: false })
    .limit(20);

  await supabase.from("therapy_access_log").insert({
    connection_id: connection.id,
    therapist_id: therapistId,
    action: "view_assessments",
    resource_type: "assessment",
  });

  return new Response(JSON.stringify({ assessments }), {
    headers: { "Content-Type": "application/json" },
  });
}

async function createAssignment(
  supabase: any,
  therapistId: string,
  clientId: string,
  body: any,
  permissions: string[],
) {
  if (!permissions.includes("write_assignments")) {
    return new Response("Permission denied", { status: 403 });
  }

  const { data: connection } = await supabase
    .from("therapy_connections")
    .select()
    .eq("therapist_id", therapistId)
    .eq("client_id", clientId)
    .eq("status", "active")
    .single();

  if (!connection) {
    return new Response("No connection", { status: 403 });
  }

  const { data: assignment } = await supabase
    .from("therapist_assignments")
    .insert({
      connection_id: connection.id,
      title: body.title,
      description: body.description,
      assignment_type: body.type,
      exercise_id: body.exerciseId,
      journal_prompt: body.journalPrompt,
      due_date: body.dueDate,
      frequency: body.frequency || "once",
    })
    .select()
    .single();

  return new Response(JSON.stringify({ assignment }), {
    headers: { "Content-Type": "application/json" },
    status: 201,
  });
}
```

### 3.3 Swift Models

```swift
struct TherapyConnection: Codable, Identifiable {
    let id: UUID
    let clientId: UUID
    let therapistId: UUID
    let status: ConnectionStatus
    let invitedBy: String

    // Sharing permissions
    let shareMood: Bool
    let shareJournal: Bool
    let shareAssessments: Bool
    let shareExercises: Bool
    let shareChatSummary: Bool
    let crisisAlertsEnabled: Bool

    let connectedAt: Date?
    let endedAt: Date?

    // Joined data
    var therapist: TherapistInfo?
}

enum ConnectionStatus: String, Codable {
    case pending
    case active
    case revoked
    case ended
}

struct TherapistInfo: Codable {
    let id: UUID
    let userId: UUID
    let practiceName: String?
    let specialties: [String]?
    let isVerified: Bool

    // From profile
    var displayName: String?
    var avatarUrl: String?
}

struct TherapistAssignment: Codable, Identifiable {
    let id: UUID
    let connectionId: UUID
    let title: String
    let description: String?
    let assignmentType: AssignmentType
    let exerciseId: UUID?
    let journalPrompt: String?
    let dueDate: Date?
    let frequency: String
    let status: AssignmentStatus
    let completedAt: Date?
    let clientNotes: String?
    let createdAt: Date
}

enum AssignmentType: String, Codable {
    case exercise
    case journalPrompt = "journal_prompt"
    case moodTracking = "mood_tracking"
    case custom
}

enum AssignmentStatus: String, Codable {
    case assigned
    case completed
    case skipped
    case expired
}
```

---

## 4. UI/UX Specifications

### 4.1 User: Connected Therapists

```
┌─────────────────────────────────┐
│ ← My Therapists                 │
├─────────────────────────────────┤
│                                 │
│ Connected Providers             │
│ ┌─────────────────────────────┐ │
│ │ 👤 Dr. Sarah Johnson        │ │
│ │    Mindful Therapy Center   │ │
│ │    ✓ Verified               │ │
│ │                             │ │
│ │    Sharing:                 │ │
│ │    ✓ Mood  ✓ Assessments    │ │
│ │    ○ Journal  ○ Exercises   │ │
│ │                             │ │
│ │    [Manage Sharing]         │ │
│ │    [Disconnect]             │ │
│ └─────────────────────────────┘ │
│                                 │
│ Pending Invites                 │
│ ┌─────────────────────────────┐ │
│ │ Dr. Mike Chen wants to      │ │
│ │ connect with you            │ │
│ │                             │ │
│ │    [Accept]    [Decline]    │ │
│ └─────────────────────────────┘ │
│                                 │
│ [+ Invite a Therapist]          │
│                                 │
└─────────────────────────────────┘
```

### 4.2 User: Sharing Settings

```
┌─────────────────────────────────┐
│ ← Sharing with Dr. Johnson      │
├─────────────────────────────────┤
│                                 │
│ What can Dr. Johnson see?       │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Mood Check-ins       [====] │ │
│ │ Your daily mood scores      │ │
│ ├─────────────────────────────┤ │
│ │ Assessment Results   [====] │ │
│ │ PHQ-9, GAD-7 scores         │ │
│ ├─────────────────────────────┤ │
│ │ Journal Entries      [    ] │ │
│ │ Your written reflections    │ │
│ ├─────────────────────────────┤ │
│ │ Exercise Activity    [    ] │ │
│ │ Completed exercises         │ │
│ ├─────────────────────────────┤ │
│ │ Chat Summaries       [    ] │ │
│ │ AI conversation themes      │ │
│ └─────────────────────────────┘ │
│                                 │
│ Crisis Alerts                   │
│ ┌─────────────────────────────┐ │
│ │ Alert my therapist if I     │ │
│ │ trigger crisis resources    │ │
│ │                      [====] │ │
│ └─────────────────────────────┘ │
│                                 │
│ Your therapist can NEVER see:   │
│ • Your password or login        │
│ • Your private circle posts     │
│ • Individual chat messages      │
│                                 │
│          [Save Changes]         │
│                                 │
└─────────────────────────────────┘
```

### 4.3 Therapist: Client Dashboard

```
┌─────────────────────────────────┐
│ ← Sarah M.              ⋮       │
├─────────────────────────────────┤
│                                 │
│ Connected since Jan 15, 2024    │
│                                 │
│ Pre-Session Summary             │
│ ┌─────────────────────────────┐ │
│ │ Since last session (7 days):│ │
│ │ • Avg mood: 3.2/5 (↓ from 3.8)│
│ │ • PHQ-9: 12 (moderate)      │ │
│ │ • Logged mood 5/7 days      │ │
│ │ • Completed 3 exercises     │ │
│ │                             │ │
│ │ AI themes detected:         │ │
│ │ [work stress] [sleep issues]│ │
│ └─────────────────────────────┘ │
│                                 │
│ Mood Trend (30 days)            │
│ ┌─────────────────────────────┐ │
│ │  5 ─                        │ │
│ │  4 ─  ●                     │ │
│ │  3 ─●───●───●               │ │
│ │  2 ─          ●──●          │ │
│ │  1 ─                        │ │
│ └─────────────────────────────┘ │
│                                 │
│ Active Assignments              │
│ ┌─────────────────────────────┐ │
│ │ ○ Daily gratitude journal   │ │
│ │   Assigned Mar 1 • 2/7 done │ │
│ └─────────────────────────────┘ │
│                                 │
│ [+ Assign Exercise]             │
│ [📝 Session Notes]              │
│                                 │
└─────────────────────────────────┘
```

---

## 5. Acceptance Criteria

- [ ] Users can invite therapists via email/code
- [ ] Therapists can accept/decline connections
- [ ] Users control exactly what is shared
- [ ] Users can revoke access anytime
- [ ] Therapists see shared data on dashboard
- [ ] Therapists can assign exercises
- [ ] Crisis alerts are sent to connected therapists
- [ ] API works for EHR integration
- [ ] All access is logged for audit

---

## 6. Security & Compliance

| Requirement            | Implementation                         |
| ---------------------- | -------------------------------------- |
| HIPAA compliance       | BAA with practices, encrypted data     |
| Audit logging          | All data access logged with timestamp  |
| Consent management     | Explicit opt-in for each data type     |
| Data minimization      | Only share what's explicitly consented |
| Access revocation      | Immediate effect, no cached data       |
| Therapist verification | License number validation required     |

---

## 7. Rollout Plan

### Phase 1 (Week 1-2)

- Connection data model
- Invite/accept flow
- Sharing permissions UI

### Phase 2 (Week 3-4)

- Therapist dashboard
- Data views (mood, assessments)
- Assignment system

### Phase 3 (Week 5-6)

- API for integrations
- Webhook support
- Audit logging

### Phase 4 (Week 7-8)

- SimplePractice integration
- Crisis alerts
- Pre-session summaries
