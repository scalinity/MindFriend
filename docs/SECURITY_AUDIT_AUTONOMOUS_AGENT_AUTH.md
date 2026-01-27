# Security Audit: Autonomous Wellness Agent - AUTH/ACCESS CONTROL

**Audit Date:** 2026-01-24  
**Auditor:** Security Auditor Agent  
**Scope:** Authentication, Authorization, and Access Control for Feature F025 (Autonomous Wellness Agent)  
**Overall Score:** 6/10

---

## Executive Summary

The Autonomous Wellness Agent feature demonstrates **functional user isolation** for user-facing operations via RLS policies, but contains **critical gaps in service role authorization checks**. The primary concern is that service role operations lack runtime validation of user_id ownership, creating potential for data leakage if service role credentials are compromised or if there are logic bugs in Edge Functions.

**Critical Issues:** 1  
**High Risk:** 3  
**Medium Risk:** 2  
**Low Risk:** 1

---

## Findings

### CRITICAL VULNERABILITIES

#### 1. Unauthenticated User Filtering in agent-monitor Edge Function
**Severity:** CRITICAL (9.5/10)  
**CWE:** CWE-284 (Improper Access Control)  
**Location:** `supabase/functions/agent-monitor/index.ts:54-73`

**Description:**
The `agent-monitor` Edge Function accepts an optional `user_ids` array from the request body without authenticating the caller. If this function is exposed as an HTTP endpoint (not restricted to cron-only), a malicious actor could submit arbitrary user IDs to trigger signal detection and action creation for any user.

```typescript
// VULNERABLE CODE (lines 54-73)
let userIds: string[] | null = null;
try {
  const body = await req.json();
  userIds = body.user_ids || null;  // NO AUTHENTICATION CHECK
} catch {
  // No body, process all active users
}

let query = supabase
  .from("agent_settings")
  .select(...)
  .eq("is_enabled", true);

if (userIds && userIds.length > 0) {
  query = query.in("user_id", userIds);  // TRUSTS UNAUTHENTICATED INPUT
}
```

**Attack Vector:**
1. Attacker discovers the `/functions/v1/agent-monitor` endpoint
2. Sends POST request with `{"user_ids": ["target-user-uuid"]}`
3. Function processes target user, creating signals and scheduling actions
4. Attacker can trigger spam notifications, exhaust user's action quota, or probe user behavior

**Impact:**
- Unauthorized proactive monitoring of specific users
- Denial of service via quota exhaustion
- Information disclosure via timing attacks (different response times for active vs inactive users)
- Privacy violation (triggering agent analysis without user consent)

**Exploitation Difficulty:** Low (if endpoint is publicly accessible)

**Remediation:**

```typescript
// OPTION 1: Validate caller is authorized system service
const authHeader = req.headers.get("Authorization");
if (!authHeader) {
  return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
}

const { data: { user }, error: authError } = await supabase.auth.getUser(
  authHeader.replace("Bearer ", "")
);

// Only allow admin users or service accounts to specify user_ids
if (userIds && userIds.length > 0) {
  const { data: adminCheck } = await supabase
    .from("admin_users")
    .select("id")
    .eq("id", user.id)
    .single();
    
  if (!adminCheck) {
    return new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 });
  }
}

// OPTION 2: Restrict to cron-only in Supabase config
// Remove HTTP access entirely, only allow scheduled invocations
```

**CRITICAL:** If this function is intended for cron-only, verify it's not exposed via HTTP and document this restriction.

---

### HIGH RISK VULNERABILITIES

#### 2. Service Role RLS Policies Allow Unrestricted Cross-User Writes
**Severity:** HIGH (8.5/10)  
**CWE:** CWE-639 (Authorization Bypass Through User-Controlled Key)  
**Location:** `supabase/migrations/20260125000000_autonomous_wellness_agent.sql:136-206`

**Description:**
All agent tables have RLS policies that permit service role to insert/update records for ANY user_id via `WITH CHECK (true)`. This relies entirely on application logic to prevent cross-user data pollution. If service role credentials leak or if there's a bug in Edge Function code, an attacker could insert malicious signals, actions, or learnings for arbitrary users.

**Vulnerable Policies:**

```sql
-- Lines 136-143: agent_signals
CREATE POLICY "Service role inserts agent signals"
    ON agent_signals FOR INSERT
    WITH CHECK (true);  -- NO USER_ID VALIDATION

-- Lines 164-170: agent_actions
CREATE POLICY "Service role manages agent actions"
    ON agent_actions FOR ALL
    WITH CHECK (true);  -- NO USER_ID VALIDATION

-- Lines 182-188: agent_learnings
CREATE POLICY "Service role manages agent learnings"
    ON agent_learnings FOR ALL
    WITH CHECK (true);  -- NO USER_ID VALIDATION

-- Lines 200-206: agent_decisions
CREATE POLICY "Service role inserts agent decisions"
    ON agent_decisions FOR INSERT
    WITH CHECK (true);  -- NO USER_ID VALIDATION
```

**Attack Vector:**
1. Attacker obtains `SUPABASE_SERVICE_ROLE_KEY` (via leaked .env, compromised CI/CD, insider threat)
2. Connects directly to Supabase with service role key
3. Inserts malicious records:
   ```sql
   INSERT INTO agent_signals (user_id, signal_type, severity, confidence, evidence)
   VALUES ('victim-uuid', 'stress_spike', 'critical', 0.99, '{"fake": "data"}');
   
   INSERT INTO agent_actions (user_id, action_type, content, status, scheduled_for)
   VALUES ('victim-uuid', 'check_in', '{"title": "Phishing", "body": "Click here"}', 'scheduled', NOW());
   ```
4. Victim receives unsolicited notifications, sees falsified wellness data, or has learning model poisoned

**Impact:**
- Data integrity compromise (false signals/actions injected)
- Privacy violation (attacker can read all user wellness data via service role)
- Model poisoning (malicious learnings corrupt personalization)
- Phishing vector (craft malicious action content with deep links)

**Remediation:**

```sql
-- Add runtime validation via CHECK constraints
-- Option 1: Validate via session variable (set by Edge Functions)
ALTER TABLE agent_signals ADD CONSTRAINT check_signal_user_context 
CHECK (
  current_setting('app.current_user_id', true) IS NULL 
  OR user_id::text = current_setting('app.current_user_id', true)
);

-- Option 2: More permissive policy with audit logging
CREATE POLICY "Service role inserts agent signals with audit"
    ON agent_signals FOR INSERT
    WITH CHECK (
      -- Allow service role but log to audit table
      (SELECT log_service_role_write('agent_signals', user_id)) IS NOT NULL
    );

-- Option 3: Separate service account with restricted grants
-- Create dedicated role with INSERT-only on specific user_id
REVOKE ALL ON agent_signals FROM service_role;
GRANT SELECT, INSERT ON agent_signals TO agent_worker_role;
-- Implement user_id filter at connection pool level
```

**Recommended Fix:** Add a session variable check:

```typescript
// In Edge Functions, before writes:
await supabase.rpc('set_user_context', { user_id: userId });

// Then the CHECK constraint validates:
// user_id::text = current_setting('app.current_user_id', true)
```

---

#### 3. agent-act Reschedules Actions Without Ownership Re-validation
**Severity:** HIGH (7.5/10)  
**CWE:** CWE-862 (Missing Authorization)  
**Location:** `supabase/functions/agent-act/index.ts:77-86`

**Description:**
When an action is in quiet hours, `agent-act` reschedules it without verifying that the action still belongs to the correct user. If there's a race condition or database corruption, an action intended for User A could be rescheduled under User B's quiet hours.

```typescript
// VULNERABLE CODE (lines 77-86)
if (inQuietHours) {
  const tomorrow9am = new Date();
  tomorrow9am.setDate(tomorrow9am.getDate() + 1);
  tomorrow9am.setHours(9, 0, 0, 0);

  await supabase
    .from("agent_actions")
    .update({ scheduled_for: tomorrow9am.toISOString() })
    .eq("id", action.id);  // NO USER_ID CHECK IN WHERE CLAUSE
  
  skipped++;
  continue;
}
```

**Attack Vector:**
1. User A has action ID `abc-123` scheduled
2. Race condition: action ownership changes due to bug
3. User B's quiet hours check applies to User A's action
4. Action rescheduled based on wrong user's preferences

**Impact:**
- Timing leakage (user A's action timing influenced by user B's settings)
- Denial of service (actions stuck in reschedule loop if user IDs mismatched)
- Privacy violation (quiet hours inference across users)

**Remediation:**

```typescript
// FIX: Add user_id to WHERE clause
await supabase
  .from("agent_actions")
  .update({ scheduled_for: tomorrow9am.toISOString() })
  .eq("id", action.id)
  .eq("user_id", action.user_id);  // ADD THIS

// Verify update succeeded
const { count } = await supabase
  .from("agent_actions")
  .select("id", { count: 'exact', head: true })
  .eq("id", action.id)
  .eq("user_id", action.user_id);

if (count === 0) {
  console.error(`Action ${action.id} ownership mismatch, skipping`);
  continue;
}
```

---

#### 4. No Audit Logging for Service Role Data Modifications
**Severity:** HIGH (7.0/10)  
**CWE:** CWE-778 (Insufficient Logging)  
**Location:** All Edge Functions using service role

**Description:**
Service role operations (signal detection, action creation, learning updates) lack comprehensive audit trails. If a security incident occurs, it's impossible to determine:
- Which Edge Function modified which user's data
- What the before/after states were
- Whether modifications were authorized

**Impact:**
- No forensic capability after breach
- Cannot detect logic bugs causing cross-user data pollution
- Compliance risk (GDPR Article 30 requires processing logs)

**Remediation:**

Create audit log table:

```sql
CREATE TABLE IF NOT EXISTS service_role_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    function_name TEXT NOT NULL,
    operation TEXT NOT NULL,
    table_name TEXT NOT NULL,
    target_user_id UUID NOT NULL,
    record_id UUID,
    before_state JSONB,
    after_state JSONB,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audit_user_time ON service_role_audit(target_user_id, created_at DESC);
CREATE INDEX idx_audit_function ON service_role_audit(function_name, created_at DESC);

-- Retention policy: auto-delete after 90 days
```

Update Edge Functions:

```typescript
async function auditWrite(
  supabase: SupabaseClient,
  operation: string,
  tableName: string,
  userId: string,
  recordId: string | null,
  metadata: Record<string, unknown>
) {
  await supabase.from('service_role_audit').insert({
    function_name: 'agent-monitor',
    operation,
    table_name: tableName,
    target_user_id: userId,
    record_id: recordId,
    metadata,
  });
}

// Before writes:
await auditWrite(supabase, 'INSERT', 'agent_signals', userId, null, { signal_type: signal.type });
```

---

### MEDIUM RISK VULNERABILITIES

#### 5. Realtime Subscription Filter Validation Missing
**Severity:** MEDIUM (6.0/10)  
**CWE:** CWE-601 (URL Redirection to Untrusted Site)  
**Location:** `apps/ios/MindFriendApp/Core/Services/AgentService.swift:263-292`

**Description:**
The iOS client subscribes to realtime updates using a filter constructed from `currentUser?.id`, but there's no validation that the server-side RLS policies are enforcing this filter. If RLS policies are misconfigured or disabled, the client could receive updates for other users.

```swift
// Line 273: Filter constructed client-side
filter: "user_id=eq.\(userId.uuidString)"
```

**Impact:**
- If RLS bypassed, client receives other users' action updates
- Information disclosure (wellness signals, action content)

**Remediation:**

1. **Server-side validation:** Ensure RLS policies are tested in CI:

```typescript
// Test: supabase/functions/_tests/rls-validation.test.ts
Deno.test("agent_actions RLS prevents cross-user reads", async () => {
  const userAClient = createClient(url, anonKey, { 
    global: { headers: { Authorization: `Bearer ${userAToken}` } }
  });
  
  const userBClient = createClient(url, anonKey, { 
    global: { headers: { Authorization: `Bearer ${userBToken}` } }
  });
  
  // Create action for User B
  await userBClient.from('agent_actions').insert({ ... });
  
  // Try to read as User A
  const { data, error } = await userAClient
    .from('agent_actions')
    .select()
    .eq('user_id', userBId);  // Explicit cross-user query
    
  assertEquals(data.length, 0, "User A should not see User B's actions");
});
```

2. **Client-side validation:** After receiving realtime event, verify user_id matches:

```swift
// Add validation in subscription handler
.onPostgresChange(
    InsertAction.self,
    table: "agent_actions",
    filter: "user_id=eq.\(userId.uuidString)"
) { [weak self] payload in
    // VALIDATE
    guard let action = payload.new as? AgentAction,
          action.userId == self?.supabase.auth.currentUser?.id else {
        print("ERROR: Received action for different user, RLS breach!")
        return
    }
    
    Task { @MainActor in
        _ = try? await self?.fetchRecentActions()
    }
}
```

---

#### 6. Edge Function JWT Validation Inconsistency
**Severity:** MEDIUM (5.5/10)  
**CWE:** CWE-306 (Missing Authentication for Critical Function)  
**Location:** 
- `supabase/functions/agent-monitor/index.ts` (NO validation)
- `supabase/functions/agent-act/index.ts` (NO validation)
- `supabase/functions/agent-learn/index.ts:43-61` (HAS validation)

**Description:**
Only `agent-learn` validates JWT tokens, while `agent-monitor` and `agent-act` use service role keys without authentication. This creates confusion about security model and increases risk of misconfiguration.

**Impact:**
- Inconsistent security posture
- If `agent-monitor` is accidentally exposed as HTTP endpoint, no auth barrier
- Future developers may copy non-validating pattern

**Remediation:**

**For `agent-learn`:** Already correct ✅

**For `agent-monitor` and `agent-act`:** Add explicit access control:

```typescript
// Option 1: Validate caller is cron service (via header signature)
const cronSecret = Deno.env.get("CRON_SECRET_KEY");
const providedSecret = req.headers.get("X-Cron-Secret");

if (providedSecret !== cronSecret) {
  return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
}

// Option 2: Restrict via Supabase Edge Function JWT policies
// In config.toml:
[functions.agent-monitor]
verify_jwt = false  # Still false for cron
allowed_origins = []  # Block HTTP, only allow scheduled

[functions.agent-act]
verify_jwt = false
allowed_origins = []
```

**Document in code:**

```typescript
// Agent Monitor - CRON ONLY
// This function MUST NOT be exposed as HTTP endpoint.
// Scheduled via Supabase Cron (every 30 min).
// If HTTP access needed, add JWT validation.
```

---

### LOW RISK / INFORMATIONAL

#### 7. Missing Rate Limiting on agent-learn
**Severity:** LOW (3.0/10)  
**CWE:** CWE-770 (Allocation of Resources Without Limits)  
**Location:** `supabase/functions/agent-learn/index.ts`

**Description:**
The `agent-learn` endpoint lacks rate limiting. A malicious user could spam response submissions to poison their learning model or exhaust database resources.

**Impact:**
- Self-inflicted model poisoning
- Database write amplification
- Minimal cross-user impact (RLS prevents affecting others)

**Remediation:**

```typescript
import { checkRateLimit } from "../_shared/rateLimiter.ts";

// After JWT validation
const rateLimitOk = await checkRateLimit(
  supabase,
  user.id,
  'agent_learn',
  { maxRequests: 100, windowMinutes: 60 }
);

if (!rateLimitOk) {
  return new Response(JSON.stringify({ error: "Rate limit exceeded" }), { 
    status: 429 
  });
}
```

---

## Positive Security Controls

### What's Working Well

1. **RLS Enabled on All Tables** (lines 107-111) ✅
   - All agent tables have `ENABLE ROW LEVEL SECURITY`
   - Foundation for defense-in-depth

2. **User-Scoped SELECT Policies** ✅
   - Users can only SELECT their own data via `auth.uid() = user_id`
   - Prevents horizontal privilege escalation for reads

3. **agent-learn JWT Validation** (lines 43-61) ✅
   - Properly validates JWT before processing
   - Verifies action ownership (line 81: `eq("user_id", user.id)`)
   - Good model for other functions

4. **iOS Client Auth Checks** ✅
   - All service methods check `currentUser?.id` before operations
   - Throws `notAuthenticated` error if no session
   - Proper use of Supabase authenticated client

5. **Deduplication Logic** ✅
   - `isDuplicateSignal()` prevents signal spam (signal-detectors.ts:461-480)
   - 24-hour window prevents redundant actions

6. **Foreign Key Constraints** ✅
   - All tables use `REFERENCES auth.users(id) ON DELETE CASCADE`
   - Ensures referential integrity

---

## Threat Model

### Assets
- User wellness data (moods, signals, learnings)
- Agent action content (potentially sensitive interventions)
- User preferences (autonomy levels, quiet hours)
- ML learning models (personalization data)

### Threats
1. **Service Role Key Compromise** → Cross-user data manipulation
2. **Malicious Edge Function Invocation** → Unauthorized monitoring
3. **RLS Policy Misconfiguration** → Data leakage
4. **Insider Threat** → Service role abuse for surveillance
5. **Logic Bugs** → Accidental cross-user data pollution

### Mitigations Needed
- [ ] Add service role write validation (CHECK constraints or session variables)
- [ ] Implement audit logging for all service role operations
- [ ] Restrict agent-monitor to cron-only (no HTTP access)
- [ ] Add rate limiting to agent-learn
- [ ] Create RLS policy tests in CI

---

## Compliance Notes

### GDPR Article 32 (Security of Processing)
- **Gap:** No encryption at rest validation for learnings table (may contain inferred sensitive data)
- **Gap:** Insufficient logging for "personal data breach" detection (Article 33)

### HIPAA (if applicable)
- **Gap:** No access controls audit (§164.312(b))
- **Gap:** Agent actions may contain PHI, need encryption validation

---

## Recommendations Summary

| Priority | Issue | Effort | Risk Reduction |
|----------|-------|--------|----------------|
| P0 | Add auth to agent-monitor user_ids param | 2h | HIGH |
| P0 | Restrict agent-monitor to cron-only | 1h | HIGH |
| P1 | Add service role CHECK constraints | 4h | MEDIUM |
| P1 | Implement audit logging | 6h | MEDIUM |
| P1 | Add user_id to agent-act WHERE clause | 1h | LOW |
| P2 | Create RLS policy tests | 8h | MEDIUM |
| P2 | Add rate limiting to agent-learn | 2h | LOW |
| P3 | Client-side realtime validation | 2h | LOW |

**Total Estimated Effort:** 26 hours  
**Expected Score After Fixes:** 9/10

---

## Testing Checklist

### Manual Tests
- [ ] Attempt to call agent-monitor with arbitrary user_ids (should fail)
- [ ] Verify agent-act only updates actions for correct user
- [ ] Confirm agent-learn rejects requests for other users' actions
- [ ] Test RLS policies prevent cross-user reads
- [ ] Verify service role can't insert with mismatched user_id

### Automated Tests
```typescript
// supabase/functions/_tests/agent-security.test.ts
Deno.test("agent-monitor rejects unauthenticated user_ids", async () => {
  const response = await fetch(`${FUNCTION_URL}/agent-monitor`, {
    method: 'POST',
    body: JSON.stringify({ user_ids: ['fake-uuid'] }),
  });
  assertEquals(response.status, 401);
});

Deno.test("agent-learn rejects cross-user actions", async () => {
  const userAToken = await getAuthToken(userAEmail);
  
  const response = await fetch(`${FUNCTION_URL}/agent-learn`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${userAToken}` },
    body: JSON.stringify({ 
      action_id: userBActionId,  // User B's action
      user_response: { response_type: 'dismissed' }
    }),
  });
  assertEquals(response.status, 404);  // Should not find action
});
```

---

## Conclusion

The Autonomous Wellness Agent demonstrates good foundational security with RLS policies and user-scoped reads. However, **critical gaps in service role authorization** create significant risk. The primary concern is the lack of runtime validation when service role performs writes, which could allow cross-user data manipulation if service credentials are compromised.

**Key Actions:**
1. **Immediately** restrict `agent-monitor` to cron-only access
2. **High priority** implement service role write validation
3. **Medium priority** add comprehensive audit logging

With these fixes, the feature would achieve a **9/10 security score** and align with production security best practices.

---

**Report Generated:** 2026-01-24  
**Next Audit:** After remediation implementation (estimated 2026-01-26)
