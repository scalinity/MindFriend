# Security Audit: Life Transition Pathways - Input/Output Security

**Audit Date:** 2026-01-24
**Auditor:** Claude Code Security Agent
**Scope:** Life Transition Pathways feature (F015)
**Focus Areas:** Input validation, output encoding, injection vulnerabilities, data sanitization, boundary validation

---

## Executive Summary

**Overall Security Score: 7.5/10**

The Life Transition Pathways implementation demonstrates **strong defense against SQL injection and XSS** through proper use of parameterized queries and SwiftUI's auto-escaping. However, **critical authorization gaps** exist in the phase advancement flow, and **input validation could be strengthened** with UUID format checks.

### Risk Classification

- **1 Critical Vulnerability** (IDOR in advance-pathway-phase)
- **2 High-Risk Issues** (plaintext data leakage, missing phase boundary validation)
- **3 Medium-Risk Issues** (UUID validation, error message verbosity, CORS wildcard)
- **5 Low-Risk Issues** (informational improvements)

---

## Critical Vulnerabilities

### VULN-001: Insecure Direct Object Reference (IDOR) in Phase Advancement

**Severity:** CRITICAL (CVSS 8.1)
**Location:** `supabase/functions/advance-pathway-phase/index.ts:48-56`
**CWE:** CWE-639 (Authorization Bypass Through User-Controlled Key)

#### Description

The `advance-pathway-phase` function fetches the user pathway without explicit ownership verification at the application level, relying solely on RLS policies.

```typescript
// VULNERABLE CODE (Line 48-56)
const { data: userPathway } = await supabaseClient
  .from("user_pathways")
  .select("*, pathway:transition_pathways(*)")
  .eq("id", userPathwayId)
  // MISSING: .eq("user_id", user.id)
  .single();

if (!userPathway) {
  return new Response(JSON.stringify({ error: "PATHWAY_NOT_FOUND" }), {
    status: 404,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
```

#### Impact

While RLS policies should prevent unauthorized access, **defense-in-depth requires explicit authorization checks**. If RLS is misconfigured or bypassed (e.g., service role key leak), an attacker could:

1. Enumerate pathway IDs via timing attacks
2. Advance another user's pathway phases
3. Trigger unearned milestones and celebrations

#### Exploitation

```bash
# Attacker discovers victim's pathway ID via leaked logs or predictable UUIDs
curl -X POST https://your-project.supabase.co/functions/v1/advance-pathway-phase \
  -H "Authorization: Bearer <attacker_jwt>" \
  -d '{"userPathwayId": "victim-pathway-uuid-here"}'

# If RLS fails, attacker advances victim's pathway
```

#### Remediation

Add explicit ownership verification (lines 48-62):

```typescript
const { data: userPathway } = await supabaseClient
  .from("user_pathways")
  .select("*, pathway:transition_pathways(*)")
  .eq("id", userPathwayId)
  .eq("user_id", user.id)  // ✅ CRITICAL: Verify ownership
  .single();

if (!userPathway) {
  return new Response(JSON.stringify({ error: "PATHWAY_NOT_FOUND" }), {
    status: 404,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
```

#### References

- OWASP Top 10 2021: A01 - Broken Access Control
- CWE-639: Authorization Bypass Through User-Controlled Key

---

## High-Risk Issues

### VULN-002: Plaintext Data Leakage in Encrypted Fields

**Severity:** HIGH (CVSS 7.2)
**Location:** `apps/ios/MindFriendApp/Features/Transitions/TransitionService.swift:150-177`
**CWE:** CWE-319 (Cleartext Transmission of Sensitive Information)

#### Description

The `completeCheckIn` function encrypts sensitive data (`notes`, `journalEntry`) but the request structure includes both plaintext and encrypted fields, creating risk of accidental plaintext exposure.

```swift
// CURRENT CODE (Lines 150-177)
struct EncryptedCheckInData: Codable {
    let mood: Int
    let energy: Int
    let notes: String?  // ⚠️ Plaintext field still defined
    let encryptedNotes: String?
    let responses: [String: String]?
}

let request = CheckInRequest(
    userPathwayId: userPathwayId.uuidString,
    checkInData: EncryptedCheckInData(
        mood: checkInData.mood,
        energy: checkInData.energy,
        notes: nil,  // ✅ Set to nil, but field exists
        encryptedNotes: encryptedNotes,
        responses: checkInData.responses
    ),
    exercisesCompleted: exercisesCompleted,
    journalEntry: nil,  // ✅ Set to nil, but field exists
    encryptedJournalEntry: encryptedJournalEntry
)
```

#### Impact

- **Backward compatibility confusion:** Developers might accidentally populate plaintext fields
- **API contract ambiguity:** Edge Function must handle both plaintext and encrypted
- **Audit trail complexity:** Logs may contain both field types
- **Future regression risk:** Code changes could reintroduce plaintext transmission

#### Remediation

**Option 1: Remove plaintext fields entirely (breaking change)**

```swift
struct EncryptedCheckInData: Codable {
    let mood: Int
    let energy: Int
    // REMOVED: let notes: String?
    let encryptedNotes: String?
    let responses: [String: String]?
}
```

**Option 2: Add compile-time checks (non-breaking)**

```swift
// Add debug assertion
#if DEBUG
if checkInData.notes != nil {
    assertionFailure("SECURITY: notes field must be nil - use encryptedNotes")
}
#endif
```

#### References

- OWASP Mobile Top 10: M2 - Insecure Data Storage
- CWE-319: Cleartext Transmission of Sensitive Information

---

### VULN-003: Missing Phase Boundary Validation

**Severity:** HIGH (CVSS 7.0)
**Location:** `supabase/functions/advance-pathway-phase/index.ts:63-68`
**CWE:** CWE-20 (Improper Input Validation)

#### Description

Documented in `submit-pathway-checkin/test-edge-cases.md`, the phase advancement logic does not validate against the maximum phase number, allowing progression to invalid phases.

```typescript
// VULNERABLE CODE (Lines 63-68)
if (userPathway.current_phase >= 4) {
  return new Response(JSON.stringify({ error: "ALREADY_FINAL_PHASE" }), {
    status: 400,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
```

**Problem:** Hardcoded `>= 4` assumes all pathways have exactly 4 phases. Database allows phases 1-4, but pathways may vary.

#### Impact

**Scenario:** User on final phase (day 63/63) completes check-in:

1. `submit_pathway_checkin` advances to phase 5
2. Database accepts `current_phase = 5` (constraint is `BETWEEN 1 AND 4` but UPDATE may bypass)
3. Next day's `get-pathway-content` queries for phase 5 → returns NULL
4. Pathway broken permanently, user cannot continue

#### Remediation

```typescript
// Query actual max phase for this pathway
const { data: maxPhaseData } = await supabaseClient
  .from("pathway_phases")
  .select("phase_number")
  .eq("pathway_id", userPathway.pathway_id)
  .order("phase_number", { ascending: false })
  .limit(1)
  .single();

const maxPhase = maxPhaseData?.phase_number || 4;

if (userPathway.current_phase >= maxPhase) {
  // Mark as completed instead of advancing
  await supabaseClient
    .from("user_pathways")
    .update({ status: "completed", completed_at: new Date().toISOString() })
    .eq("id", userPathwayId);
    
  return new Response(JSON.stringify({
    success: true,
    completed: true,
    message: "Pathway completed!"
  }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
```

#### References

- Test documentation: `supabase/functions/submit-pathway-checkin/test-edge-cases.md`
- CWE-20: Improper Input Validation

---

## Medium-Risk Issues

### VULN-004: Missing UUID Format Validation

**Severity:** MEDIUM (CVSS 5.3)
**Location:** All Edge Functions accepting UUID parameters
**CWE:** CWE-20 (Improper Input Validation)

#### Description

Edge Functions accept UUID strings without format validation, relying entirely on database type checking.

```typescript
// NO VALIDATION (enroll-pathway/index.ts:48)
const { pathwayKey, personalization } = await req.json();
// pathwayKey validated with regex, but no UUID validation anywhere
```

#### Impact

- **Database errors exposed:** Invalid UUIDs cause Postgres errors to bubble up
- **Timing attacks:** Error response times may differ for valid vs. invalid UUIDs
- **DoS potential:** Malformed UUIDs may cause excessive error logging

#### Remediation

Add UUID validation helper:

```typescript
function isValidUUID(uuid: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(uuid);
}

// Use in all functions
if (!isValidUUID(body.userPathwayId)) {
  return new Response(JSON.stringify({ error: "Invalid pathway ID format" }), {
    status: 400,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
```

---

### VULN-005: Verbose Error Messages Leak Implementation Details

**Severity:** MEDIUM (CVSS 4.3)
**Location:** Multiple Edge Functions
**CWE:** CWE-209 (Information Exposure Through Error Messages)

#### Description

Error messages expose internal implementation details:

```typescript
// enroll-pathway/index.ts:210-221
if (enrollError) {
  console.error("Enrollment error:", enrollError);
  return new Response(
    JSON.stringify({
      error: "ENROLLMENT_FAILED",
      details: enrollError.message,  // ⚠️ Exposes internal errors
    }),
    { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}
```

**Leaked information:**
- Database schema details (table names, column names)
- SQL constraint violations
- Internal function names
- Stack traces (in some error paths)

#### Remediation

Sanitize error messages:

```typescript
function sanitizeError(error: any): string {
  // Production: generic message
  if (Deno.env.get("ENVIRONMENT") === "production") {
    return "An internal error occurred";
  }
  
  // Development: full details
  return error?.message || "Unknown error";
}

// Usage
return new Response(
  JSON.stringify({
    error: "ENROLLMENT_FAILED",
    details: sanitizeError(enrollError),
  }),
  { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
);
```

---

### VULN-006: CORS Wildcard Allows Any Origin

**Severity:** MEDIUM (CVSS 4.0)
**Location:** All Edge Functions
**CWE:** CWE-346 (Origin Validation Error)

#### Description

All Edge Functions use wildcard CORS:

```typescript
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",  // ⚠️ Allows any origin
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
```

#### Impact

While JWT validation prevents unauthorized access, wildcard CORS:
- Allows malicious sites to make authenticated requests if user has valid token
- Enables CSRF-style attacks if user is logged in
- Violates principle of least privilege

#### Remediation

Restrict to known origins:

```typescript
const allowedOrigins = [
  "https://getmindfriend.app",
  "mindfriend://",  // iOS deep link
  "http://localhost:3000",  // Development
];

function getCorsHeaders(request: Request): Record<string, string> {
  const origin = request.headers.get("Origin") || "";
  const isAllowed = allowedOrigins.some(allowed => origin.startsWith(allowed));
  
  return {
    "Access-Control-Allow-Origin": isAllowed ? origin : allowedOrigins[0],
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Credentials": "true",
  };
}
```

---

## Low-Risk Issues (Informational)

### INFO-001: No Rate Limiting on Edge Functions

**Severity:** LOW (CVSS 3.1)
**Location:** All Edge Functions

Edge Functions lack application-level rate limiting. Supabase provides platform-level limits, but custom per-user limits would improve security.

**Recommendation:** Implement rate limiting for check-in submissions:

```typescript
// Use Supabase storage for rate limiting
const { data: recentCheckIns } = await supabaseClient
  .from("pathway_progress")
  .select("created_at")
  .eq("user_id", user.id)
  .gte("created_at", new Date(Date.now() - 60000).toISOString())  // Last minute
  .execute();

if (recentCheckIns && recentCheckIns.length >= 5) {
  return new Response(JSON.stringify({ error: "RATE_LIMIT_EXCEEDED" }), {
    status: 429,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
```

---

### INFO-002: Missing Input Normalization

**Severity:** LOW (CVSS 2.3)
**Location:** `enroll-pathway/index.ts:96-107`

User-provided text fields (specificContext, supportPeople) are not normalized:
- No Unicode normalization (NFC vs NFD)
- No whitespace trimming
- No control character filtering

**Recommendation:**

```typescript
function normalizeText(text: string): string {
  return text
    .normalize("NFC")  // Unicode normalization
    .trim()
    .replace(/\s+/g, " ")  // Collapse whitespace
    .replace(/[\x00-\x1F\x7F]/g, "");  // Remove control characters
}

// Apply to all text inputs
if (personalization.specificContext) {
  personalization.specificContext = normalizeText(personalization.specificContext);
}
```

---

### INFO-003: No Content-Security-Policy Headers

**Severity:** LOW (CVSS 2.0)
**Location:** All Edge Functions

While not applicable to JSON APIs, adding CSP headers provides defense-in-depth:

```typescript
const securityHeaders = {
  "Content-Security-Policy": "default-src 'none'",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
};
```

---

### INFO-004: Plaintext Logging of Sensitive Context

**Severity:** LOW (CVSS 2.1)
**Location:** `enroll-pathway/index.ts:195-199`

Context content is logged in plaintext:

```typescript
const contextContent =
  `User is going through: ${pathway.name}. ` +
  `Context: ${personalization?.specificContext || "Not specified"}. ` +  // ⚠️ Logged
  `Started: ${new Date().toISOString().split("T")[0]}. ` +
  `Goals: ${personalization?.goals?.join(", ") || "Not specified"}.`;
```

**Recommendation:** Sanitize logs to redact sensitive data:

```typescript
const contextContent = `User is going through: ${pathway.name}. Context: [REDACTED]. Started: ...`;
```

---

### INFO-005: No Audit Trail for State Changes

**Severity:** LOW (CVSS 2.0)
**Location:** `pause-pathway/`, `resume-pathway/`, `abandon-pathway/`

Pathway state changes (pause, resume, abandon) are not logged to an audit table.

**Recommendation:** Create `pathway_state_history` table:

```sql
CREATE TABLE pathway_state_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_pathway_id UUID NOT NULL REFERENCES user_pathways(id),
    old_status TEXT NOT NULL,
    new_status TEXT NOT NULL,
    reason TEXT,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    changed_by UUID NOT NULL REFERENCES auth.users(id)
);
```

---

## Positive Security Findings

### SQL Injection Prevention: EXCELLENT (10/10)

All database queries use parameterized inputs:

```typescript
// ✅ CORRECT: Parameterized query
const { data: pathway } = await supabaseClient
  .from("transition_pathways")
  .select("*")
  .eq("key", pathwayKey)  // Parameterized
  .single();
```

**No string concatenation found in SQL queries.**

---

### Stored Procedure Hardening: EXCELLENT (10/10)

`supabase/migrations/20260124192700_security_hardening_pathways.sql`:

```sql
CREATE OR REPLACE FUNCTION enroll_user_in_pathway(...)
LANGUAGE plpgsql
SECURITY DEFINER  -- ✅ Prevents privilege escalation
SET search_path = public  -- ✅ Prevents schema injection
AS $$
BEGIN
    -- ✅ CRITICAL: Ownership verification
    IF p_user_id != auth.uid() THEN
        RAISE EXCEPTION 'Unauthorized: Cannot enroll pathway for another user';
    END IF;
    ...
END;
$$;
```

**Key protections:**
- `SECURITY DEFINER` with explicit auth checks
- `SET search_path = public` prevents schema injection
- `auth.uid()` verification prevents privilege escalation

---

### Race Condition Protection: EXCELLENT (10/10)

Duplicate check-in prevention uses `FOR UPDATE NOWAIT`:

```sql
-- security_hardening_pathways.sql:166-175
SELECT id INTO v_existing_checkin_id
FROM pathway_progress
WHERE user_pathway_id = p_user_pathway_id
AND day_number = v_current_day
FOR UPDATE NOWAIT;  -- ✅ Prevents concurrent inserts

IF v_existing_checkin_id IS NOT NULL THEN
    RAISE EXCEPTION 'CHECK_IN_ALREADY_COMPLETED';
END IF;
```

**Plus unique constraint for defense-in-depth:**

```sql
ALTER TABLE pathway_progress
ADD CONSTRAINT unique_pathway_day_checkin
UNIQUE (user_pathway_id, day_number);
```

---

### Database Constraints: STRONG (9/10)

Comprehensive CHECK constraints:

```sql
-- String length validation
name TEXT NOT NULL CHECK (length(name) BETWEEN 3 AND 50),
description TEXT NOT NULL CHECK (length(description) BETWEEN 10 AND 200),
journal_entry TEXT CHECK (length(journal_entry) <= 10000),

-- Enum validation
category TEXT NOT NULL CHECK (category IN ('career', 'relationship', 'loss', 'family', 'health', 'life_stage')),
status TEXT NOT NULL CHECK (status IN ('active', 'paused', 'completed', 'abandoned')),

-- Range validation
phase_number INTEGER NOT NULL CHECK (phase_number BETWEEN 1 AND 4),
duration_weeks INTEGER NOT NULL CHECK (duration_weeks BETWEEN 4 AND 12),
mood/energy: validated 1-10 in Edge Function
```

**Minor gap:** JSONB size limits enforced in Edge Functions (10KB, 20KB) but not database constraints.

---

### Client-Side Encryption: GOOD (7/10)

```swift
// PathwayEncryptionService.swift
func encryptString(_ text: String?) throws -> String? {
    guard let text = text, !text.isEmpty else { return nil }
    let encryptedData = try secureStorage.encrypt(text)
    return encryptedData.base64EncodedString()
}
```

**Strengths:**
- Uses SecureStorage (iOS Keychain-backed)
- Base64 encoding for transport
- Applied to sensitive fields (notes, journalEntry)

**Weaknesses:**
- Backward compatibility with plaintext fields (VULN-002)
- Key management not documented (SecureStorage implementation unclear)

---

### Row-Level Security: STRONG (9/10)

All tables have RLS enabled with `auth.uid()` enforcement:

```sql
-- RLS: Users can manage own pathways
CREATE POLICY "Users can manage own pathways" ON user_pathways
    FOR ALL USING (auth.uid() = user_id);

-- RLS: Users can manage own progress
CREATE POLICY "Users can manage own progress" ON pathway_progress
    FOR ALL USING (
        user_pathway_id IN (
            SELECT id FROM user_pathways WHERE user_id = auth.uid()
        )
    );
```

**Minor gap:** Advance-phase function doesn't add explicit `.eq("user_id", user.id)` check (VULN-001).

---

## Remediation Priority

### Immediate (Deploy within 24 hours)

1. **[VULN-001] IDOR in advance-pathway-phase**
   - Add `.eq("user_id", user.id)` to query (1 line change)
   - Test with unauthorized user JWT

2. **[VULN-003] Phase boundary validation**
   - Query max phase from `pathway_phases`
   - Mark pathway as `completed` instead of advancing past max

### Short-term (Deploy within 1 week)

3. **[VULN-002] Remove plaintext fields**
   - Update Edge Functions to only accept encrypted fields
   - Coordinate iOS app update (version gating)

4. **[VULN-004] UUID format validation**
   - Add `isValidUUID()` helper function
   - Apply to all Edge Functions

5. **[VULN-005] Sanitize error messages**
   - Implement `sanitizeError()` function
   - Use environment-based verbosity

### Medium-term (Deploy within 1 month)

6. **[VULN-006] Restrict CORS origins**
   - Implement origin allowlist
   - Test with iOS app and web client

7. **[INFO-001] Add rate limiting**
   - Implement per-user rate limits
   - Add monitoring/alerting

### Long-term (Nice to have)

8. **[INFO-002-005]** Input normalization, CSP headers, audit logging

---

## Testing Recommendations

### Penetration Testing Checklist

- [ ] Attempt IDOR with valid JWT but wrong pathway ID (VULN-001)
- [ ] Fuzz pathwayKey with SQL injection payloads (`'; DROP TABLE--`)
- [ ] Send oversized personalization JSONB (>10KB, >20KB, >1MB)
- [ ] Submit check-in with mood/energy out of range (-1, 0, 11, 999)
- [ ] Concurrent check-in requests (race condition test)
- [ ] Advance phase beyond max (phase 5, 6, 100)
- [ ] Enumerate pathway UUIDs via timing attacks
- [ ] CSRF test with wildcard CORS
- [ ] Send malformed UUIDs (empty, null, "not-a-uuid")
- [ ] Unicode normalization attacks (NFD vs NFC)

### Automated Security Testing

```bash
# SQL Injection Test
curl -X POST https://your-project.supabase.co/functions/v1/enroll-pathway \
  -H "Authorization: Bearer <jwt>" \
  -d '{"pathwayKey": "career_change'; DROP TABLE user_pathways;--", "personalization": {}}'

# Oversized Input Test
curl -X POST https://your-project.supabase.co/functions/v1/enroll-pathway \
  -H "Authorization: Bearer <jwt>" \
  -d "{\"pathwayKey\": \"career_change\", \"personalization\": {\"specificContext\": \"$(python -c 'print("A" * 100000)')\" }}"

# IDOR Test
curl -X POST https://your-project.supabase.co/functions/v1/advance-pathway-phase \
  -H "Authorization: Bearer <victim_jwt>" \
  -d '{"userPathwayId": "<different_users_pathway_id>"}'
```

---

## Conclusion

The Life Transition Pathways implementation demonstrates **strong foundational security** in SQL injection prevention, race condition handling, and database-level constraints. However, **authorization gaps** (IDOR in phase advancement) and **data leakage risks** (plaintext fields) require immediate remediation.

**Key Strengths:**
- Parameterized queries throughout
- SECURITY DEFINER with auth checks in stored procedures
- Race condition protection with `FOR UPDATE NOWAIT`
- Comprehensive database constraints

**Critical Gaps:**
- Missing ownership verification in advance-phase (IDOR)
- Plaintext field exposure despite encryption
- Hardcoded phase limits without validation

**Recommended Next Steps:**
1. Deploy immediate fixes (VULN-001, VULN-003)
2. Conduct penetration testing before production release
3. Implement automated security regression tests
4. Schedule quarterly security audits

**Final Score: 7.5/10**

---

## Appendix: Code Review Checklist

### Input Validation
- [x] pathwayKey format validation (regex)
- [x] Personalization size limits (10KB)
- [x] Field whitelisting (allowedFields array)
- [x] String length validation (specificContext: 500 chars)
- [x] Array length validation (supportPeople: 10, goals: 5)
- [x] Numeric range validation (mood/energy: 1-10)
- [ ] UUID format validation (missing)
- [x] JSONB size constraints (database level)

### SQL Injection
- [x] Parameterized queries (Supabase client)
- [x] No string concatenation in SQL
- [x] SECURITY DEFINER with search_path
- [x] Prepared statements in stored procedures
- [x] RLS policies enabled

### Authorization
- [x] JWT validation in all functions
- [x] auth.uid() checks in stored procedures
- [x] User ownership verification (enroll, check-in, get-content)
- [ ] User ownership verification (advance-phase) ← CRITICAL GAP
- [x] RLS policies enforce ownership

### Output Encoding
- [x] JSON auto-encoding (Deno)
- [x] SwiftUI Text auto-escaping
- [x] No innerHTML usage
- [x] Base64 encoding for encrypted data

### Encryption
- [x] Client-side encryption implemented
- [x] SecureStorage usage
- [ ] Plaintext field removal (backward compat issue)
- [ ] Key rotation strategy (not documented)

### Race Conditions
- [x] FOR UPDATE NOWAIT in check-in
- [x] Unique constraint for deduplication
- [x] Atomic operations in stored procedures

### Error Handling
- [ ] Error message sanitization (exposes details)
- [x] No stack traces in responses
- [x] Proper HTTP status codes
- [ ] Environment-based verbosity (missing)

---

**Audit Complete**
