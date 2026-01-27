# Security Audit: Biofeedback Adaptation System (Auth/Access Control)

**Date:** 2026-01-24
**Scope:** Authentication and Authorization Security
**Files Audited:**
- `/supabase/migrations/20260125120000_biofeedback_adaptation.sql`
- `/supabase/functions/biofeedback-analyze/index.ts`
- `/supabase/functions/calculate-baseline/index.ts`

**Security Score: 6.5/10**

---

## Executive Summary

The biofeedback adaptation implementation has **moderate security risks** that must be addressed before production deployment. While basic authentication and Row Level Security (RLS) are implemented, there are **critical vulnerabilities** in privilege escalation, incomplete access controls, and schema inconsistencies that could lead to unauthorized data access or manipulation.

**Critical Issues:** 2
**High Risk Issues:** 3
**Medium Risk Issues:** 2
**Low Risk Issues:** 1

---

## CRITICAL Vulnerabilities

### 1. SECURITY DEFINER Function Without Authorization Checks

**Severity:** CRITICAL (CVSS 8.1)
**Location:** `20260125120000_biofeedback_adaptation.sql:269-410`
**CWE:** CWE-269 (Improper Privilege Management)

**Description:**
The `calculate_biofeedback_summary()` trigger function runs with `SECURITY DEFINER`, meaning it executes with the privileges of the function owner (likely superuser), **not** the invoking user. The function performs reads and writes across multiple tables without any `auth.uid()` validation.

```sql
CREATE OR REPLACE FUNCTION calculate_biofeedback_summary()
RETURNS TRIGGER AS $$
-- Lines 286-340: No auth.uid() checks anywhere
-- Reads from biofeedback_readings, biofeedback_adaptations
-- Writes to biofeedback_summaries
-- All operations bypass RLS
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

**Impact:**
- An attacker who can trigger the function could manipulate any user's biofeedback summaries
- If an attacker can update `biofeedback_sessions.completed_at` for another user's session (via application bug or SQL injection), they could corrupt that user's summary data
- Function reads data from other tables without verifying session ownership within the function body
- Bypasses all RLS policies due to elevated privileges

**Attack Vector:**
```sql
-- Attacker finds or creates a session_id belonging to victim
UPDATE biofeedback_sessions 
SET completed_at = NOW() 
WHERE id = '<victim_session_id>';
-- Trigger fires, manipulates victim's summary with SECURITY DEFINER privileges
```

**Remediation:**
Remove `SECURITY DEFINER` or add explicit authorization checks:

```sql
CREATE OR REPLACE FUNCTION calculate_biofeedback_summary()
RETURNS TRIGGER AS $$
DECLARE
    v_session_owner UUID;
BEGIN
    -- Verify session belongs to current user
    SELECT user_id INTO v_session_owner
    FROM biofeedback_sessions
    WHERE id = NEW.id;
    
    IF v_session_owner != auth.uid() AND auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'Unauthorized: Cannot calculate summary for other users'' sessions';
    END IF;
    
    -- Rest of function logic...
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

**Better approach:** Remove `SECURITY DEFINER` entirely and rely on RLS:

```sql
$$ LANGUAGE plpgsql; -- No SECURITY DEFINER
```

---

### 2. Schema Column Mismatch in Edge Function Queries

**Severity:** CRITICAL (Data Integrity / Availability)
**Location:** `calculate-baseline/index.ts:79-103`
**CWE:** CWE-704 (Incorrect Type Conversion or Cast)

**Description:**
The `calculate-baseline` function queries columns that **do not exist** in the schema defined in the migration:

**Edge Function Query (Lines 79-84):**
```typescript
const { data: heartRateSamples, error: hrError } = await supabase
  .from("healthkit_heart_rate")
  .select("value, timestamp, context")  // ❌ Column "value" doesn't exist
  .eq("user_id", user.id)
```

**Actual Schema (Lines 122-131):**
```sql
CREATE TABLE healthkit_heart_rate (
    heart_rate DECIMAL(5,2),  -- Column is named "heart_rate", not "value"
    sample_date TIMESTAMPTZ,   -- Column is named "sample_date", not "timestamp"
    context TEXT,
    -- ...
);
```

**Impact:**
- Function will fail at runtime with "column does not exist" errors
- Users cannot calculate baselines
- Feature is completely broken
- No authentication bypass, but complete feature failure

**Remediation:**
Fix column names in Edge Function:

```typescript
// Line 79-84
const { data: heartRateSamples, error: hrError } = await supabase
  .from("healthkit_heart_rate")
  .select("heart_rate, sample_date, context")  // ✓ Correct column names
  .eq("user_id", user.id)
  .gte("sample_date", lookbackDate.toISOString())  // ✓ Use sample_date
  .order("sample_date", { ascending: true });

// Line 98-103
const { data: hrvSamples, error: hrvError } = await supabase
  .from("healthkit_hrv")
  .select("hrv_sdnn, hrv_rmssd, sample_date")  // ✓ Use actual column names
  .eq("user_id", user.id)
  .gte("sample_date", lookbackDate.toISOString())
  .order("sample_date", { ascending: true });

// Lines 129-159: Update all references to use correct field names
```

---

## HIGH RISK Issues

### 3. Missing UPDATE and DELETE Policies on Biofeedback Tables

**Severity:** HIGH (CVSS 7.4)
**Location:** `20260125120000_biofeedback_adaptation.sql:169-264`
**CWE:** CWE-862 (Missing Authorization)

**Description:**
Four critical tables only have SELECT and INSERT policies, but no UPDATE or DELETE policies:
- `biofeedback_readings`
- `biofeedback_adaptations`
- `biofeedback_summaries`
- `healthkit_heart_rate`
- `healthkit_hrv`

**Impact:**
- If application code attempts UPDATE/DELETE operations, they will fail (default deny)
- **Good for security** (fail-closed), **bad for functionality**
- May block legitimate operations like correcting erroneous readings or deleting sessions
- Future features may need these operations and developers might disable RLS to "fix" the issue

**Current State:**
```sql
-- Only SELECT and INSERT policies exist
CREATE POLICY users_read_own_biofeedback_readings ON biofeedback_readings
    FOR SELECT USING (...);
CREATE POLICY users_insert_own_biofeedback_readings ON biofeedback_readings
    FOR INSERT WITH CHECK (...);
-- ❌ No UPDATE policy
-- ❌ No DELETE policy
```

**Remediation:**
Add UPDATE and DELETE policies if these operations are intended:

```sql
-- biofeedback_readings
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_update_own_biofeedback_readings') THEN
        CREATE POLICY users_update_own_biofeedback_readings ON biofeedback_readings
            FOR UPDATE USING (
                session_id IN (SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid())
            )
            WITH CHECK (
                session_id IN (SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid())
            );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_delete_own_biofeedback_readings') THEN
        CREATE POLICY users_delete_own_biofeedback_readings ON biofeedback_readings
            FOR DELETE USING (
                session_id IN (SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid())
            );
    END IF;
END $$;

-- Repeat for biofeedback_adaptations, biofeedback_summaries, healthkit tables
```

**If these operations are NOT intended**, document explicitly:

```sql
-- biofeedback_readings: UPDATE/DELETE intentionally disabled (immutable audit log)
-- If future requirements change, add policies with strict time-window constraints
```

---

### 4. No Rate Limiting on Biometric Data Insertion

**Severity:** HIGH (CVSS 6.8)
**Location:** `biofeedback-analyze/index.ts:140-150`
**CWE:** CWE-770 (Allocation of Resources Without Limits or Throttling)

**Description:**
The `biofeedback-analyze` Edge Function allows unlimited insertion of biometric readings. An attacker could:
- Spam requests to insert thousands of readings per second
- Exhaust database storage
- Increase hosting costs
- Degrade performance for legitimate users

**Current Implementation:**
```typescript
// Line 140-150: No rate limiting, no batch size checks
await supabase.from("biofeedback_readings").insert({
  session_id: body.session_id,
  heart_rate: body.heart_rate,
  // ... direct insert on every request
});
```

**Attack Vector:**
```bash
# Attacker floods function with requests
for i in {1..10000}; do
  curl -X POST https://project.supabase.co/functions/v1/biofeedback-analyze \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"session_id":"<valid_session>","heart_rate":75,"elapsed_seconds":10}' &
done
```

**Impact:**
- Database bloat (millions of readings per user)
- Financial cost (Supabase charges by storage/compute)
- Performance degradation (queries on massive tables)

**Remediation:**
Implement rate limiting using Supabase edge function headers or Redis:

```typescript
// Option 1: Rate limit per session (max N readings per session)
const { count } = await supabase
  .from("biofeedback_readings")
  .select("*", { count: "exact", head: true })
  .eq("session_id", body.session_id);

if (count && count > 300) { // Max 300 readings per session (5 min @ 1/sec)
  return new Response(
    JSON.stringify({ error: "Session reading limit exceeded" }),
    { status: 429, headers: corsHeaders }
  );
}

// Option 2: Time-based rate limit (max 1 reading per 2 seconds)
const { data: lastReading } = await supabase
  .from("biofeedback_readings")
  .select("timestamp")
  .eq("session_id", body.session_id)
  .order("timestamp", { ascending: false })
  .limit(1)
  .single();

if (lastReading) {
  const timeSinceLastReading = Date.now() - new Date(lastReading.timestamp).getTime();
  if (timeSinceLastReading < 2000) {
    return new Response(
      JSON.stringify({ error: "Rate limit: Wait 2 seconds between readings" }),
      { status: 429, headers: corsHeaders }
    );
  }
}
```

---

### 5. Insufficient Session Ownership Validation in Biofeedback-Analyze

**Severity:** HIGH (CVSS 7.1)
**Location:** `biofeedback-analyze/index.ts:100-115`
**CWE:** CWE-639 (Authorization Bypass Through User-Controlled Key)

**Description:**
While the function does check `session.user_id = user.id`, the validation could be bypassed if the query returns no results. The code uses `.single()` which throws if no rows match, but error handling is minimal.

**Current Implementation:**
```typescript
// Lines 100-115
const { data: session } = await supabase
  .from("biofeedback_sessions")
  .select("id, user_id, adaptation_mode, started_at")
  .eq("id", body.session_id)
  .eq("user_id", user.id)  // ✓ Good: filters by user_id
  .single();

if (!session) {  // ✓ Good: checks for null
  return new Response(
    JSON.stringify({ error: "Session not found or unauthorized" }),
    { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}
```

**Issue:**
If `.single()` throws an error (e.g., Supabase client issue), the try-catch at line 171 catches it and returns a generic "Internal server error" without proper logging. This could mask authorization bypass attempts.

**Remediation:**
Add explicit error differentiation:

```typescript
let session;
try {
  const { data, error } = await supabase
    .from("biofeedback_sessions")
    .select("id, user_id, adaptation_mode, started_at")
    .eq("id", body.session_id)
    .eq("user_id", user.id)
    .single();

  if (error) {
    console.warn("Session query error:", error, { userId: user.id, sessionId: body.session_id });
    return new Response(
      JSON.stringify({ error: "Session not found or unauthorized" }),
      { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  session = data;
} catch (err) {
  console.error("Unexpected session query error:", err);
  return new Response(
    JSON.stringify({ error: "Session validation failed" }),
    { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

if (!session) {
  return new Response(
    JSON.stringify({ error: "Session not found or unauthorized" }),
    { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}
```

---

## MEDIUM RISK Issues

### 6. Privacy Leak via Biofeedback Session JOIN in Calculate-Baseline

**Severity:** MEDIUM (CVSS 5.3)
**Location:** `calculate-baseline/index.ts:166-181`
**CWE:** CWE-200 (Exposure of Sensitive Information)

**Description:**
The baseline calculation function performs a JOIN query on `biofeedback_sessions` and `biofeedback_readings` without explicitly filtering by `user_id` on the readings table:

```typescript
// Lines 166-181
const { data: sessions } = await supabase
  .from("biofeedback_sessions")
  .select(`
    id,
    biofeedback_readings (
      heart_rate,
      timestamp
    )
  `)
  .eq("user_id", user.id)  // ✓ Filters sessions by user_id
  // ❌ But biofeedback_readings join relies on RLS
```

**Issue:**
This relies **entirely** on RLS policies for `biofeedback_readings` to prevent leakage. While RLS is enabled (audit confirmed), if:
- RLS is accidentally disabled
- Service role key is leaked and used
- Future code bypasses RLS

The query could return readings from other users' sessions.

**Mitigation:**
RLS is correctly configured, but defense-in-depth is missing. Add explicit user_id filtering:

```typescript
// Add redundant user_id check in application layer
const { data: sessions } = await supabase
  .from("biofeedback_sessions")
  .select(`
    id,
    user_id,
    biofeedback_readings!inner (
      heart_rate,
      timestamp
    )
  `)
  .eq("user_id", user.id)
  .not("completed_at", "is", null)
  .gte("created_at", lookbackDate.toISOString())
  .order("created_at", { ascending: false })
  .limit(10);

// Then validate in code:
if (sessions && sessions.some(s => s.user_id !== user.id)) {
  console.error("SECURITY: Session user_id mismatch detected", { userId: user.id });
  throw new Error("Authorization violation");
}
```

---

### 7. No Input Validation on Adaptation Parameters

**Severity:** MEDIUM (CVSS 5.0)
**Location:** `biofeedback-analyze/index.ts:152-165`
**CWE:** CWE-20 (Improper Input Validation)

**Description:**
The function inserts adaptation records with `new_value: a.params` directly from the `analyzeCurrentState()` function without validating the parameter structure or values:

```typescript
// Lines 152-165
const adaptationRecords = analysis.adaptations.map((a) => ({
  session_id: body.session_id,
  adaptation_type: a.type,  // ✓ Type-checked by DB enum constraint
  new_value: a.params,       // ❌ No validation of params structure
  trigger_reason: a.reason,
  biometric_trigger: {       // ❌ No validation of biometric values
    heart_rate: body.heart_rate,
    hrv_rmssd: body.hrv_rmssd,
    stress_level: stressLevel,
  },
}));
```

**Risk:**
- `a.params` could contain malicious JSON (though impact is limited to JSONB storage)
- Future code reading this JSON might be vulnerable to injection if it interprets values as code
- No schema validation means garbage data could be stored

**Remediation:**
Add JSON schema validation:

```typescript
// Define adaptation param schemas
const ADAPTATION_SCHEMAS = {
  breathing_pace: {
    required: ['inhale', 'hold', 'exhale', 'pause'],
    types: { inhale: 'number', hold: 'number', exhale: 'number', pause: 'number' }
  },
  intensity_reduction: {
    required: ['visual_intensity', 'audio_volume'],
    types: { visual_intensity: 'number', audio_volume: 'number' }
  },
  // ... other types
};

function validateAdaptationParams(type: string, params: Record<string, unknown>): boolean {
  const schema = ADAPTATION_SCHEMAS[type];
  if (!schema) return false;
  
  for (const key of schema.required) {
    if (!(key in params) || typeof params[key] !== schema.types[key]) {
      return false;
    }
  }
  return true;
}

// Use in code:
const adaptationRecords = analysis.adaptations
  .filter(a => validateAdaptationParams(a.type, a.params))
  .map(a => ({ /* ... */ }));
```

---

## LOW RISK Issues

### 8. Service Role Grants Are Overly Permissive

**Severity:** LOW (CVSS 3.1)
**Location:** `20260125120000_biofeedback_adaptation.sql:414-419`
**CWE:** CWE-250 (Execution with Unnecessary Privileges)

**Description:**
The migration grants `ALL` privileges to `service_role` on all biofeedback tables:

```sql
GRANT ALL ON biofeedback_readings TO service_role;
GRANT ALL ON biofeedback_adaptations TO service_role;
GRANT ALL ON biofeedback_summaries TO service_role;
GRANT ALL ON healthkit_heart_rate TO service_role;
GRANT ALL ON healthkit_hrv TO service_role;
```

**Issue:**
- `ALL` includes SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
- Service role only needs SELECT, INSERT, UPDATE for Edge Functions
- If service role key is compromised, attacker has full control

**Remediation:**
Use principle of least privilege:

```sql
-- Revoke ALL and grant only needed permissions
REVOKE ALL ON biofeedback_readings FROM service_role;
GRANT SELECT, INSERT ON biofeedback_readings TO service_role;

REVOKE ALL ON biofeedback_adaptations FROM service_role;
GRANT SELECT, INSERT ON biofeedback_adaptations TO service_role;

REVOKE ALL ON biofeedback_summaries FROM service_role;
GRANT SELECT, INSERT, UPDATE ON biofeedback_summaries TO service_role; -- UPDATE for trigger

REVOKE ALL ON healthkit_heart_rate FROM service_role;
GRANT SELECT ON healthkit_heart_rate TO service_role; -- Read-only for baseline calc

REVOKE ALL ON healthkit_hrv FROM service_role;
GRANT SELECT ON healthkit_hrv TO service_role; -- Read-only for baseline calc
```

---

## Remediation Priority

### Immediate (Before Deployment)
1. Remove `SECURITY DEFINER` from `calculate_biofeedback_summary()` or add auth checks
2. Fix schema column mismatches in `calculate-baseline` Edge Function
3. Add UPDATE/DELETE policies or document why they're intentionally omitted

### High Priority (Within 1 Sprint)
4. Implement rate limiting on biofeedback-analyze
5. Improve session ownership validation error handling
6. Reduce service role grants to minimum required

### Medium Priority (Within 2 Sprints)
7. Add defense-in-depth user_id checks in baseline calculation JOIN
8. Implement JSON schema validation for adaptation parameters

---

## Testing Recommendations

### Authorization Tests
```typescript
// Test: User cannot analyze another user's session
it('should reject analysis of other users sessions', async () => {
  const victimSession = await createSession(victimUserId);
  const response = await analyzeWithAuth(attackerToken, victimSession.id, { heart_rate: 75 });
  expect(response.status).toBe(404); // Not 500, not 200
});

// Test: User cannot calculate baseline with forged user_id
it('should use auth.uid() not request user_id for baseline', async () => {
  const response = await calculateBaselineWithAuth(attackerToken, { user_id: victimUserId });
  const baseline = await getBaseline(attackerToken);
  expect(baseline.user_id).toBe(attackerUserId); // Not victimUserId
});
```

### Privilege Escalation Tests
```sql
-- Test: SECURITY DEFINER function cannot be exploited
BEGIN;
  SET ROLE authenticated;
  SET request.jwt.claims.sub = '<attacker_user_id>';
  
  -- Attempt to trigger summary calculation for victim's session
  UPDATE biofeedback_sessions 
  SET completed_at = NOW() 
  WHERE user_id = '<victim_user_id>' AND id = '<victim_session_id>';
  
  -- Should fail due to RLS on biofeedback_sessions
ROLLBACK;
```

### Rate Limiting Tests
```typescript
// Test: Biometric readings are rate limited
it('should reject rapid reading insertion', async () => {
  const promises = Array(100).fill(null).map(() => 
    analyzeSession(sessionId, { heart_rate: 75, elapsed_seconds: 10 })
  );
  const results = await Promise.all(promises);
  const rejected = results.filter(r => r.status === 429);
  expect(rejected.length).toBeGreaterThan(50); // At least half should be rate limited
});
```

---

## Conclusion

The biofeedback adaptation system has a **solid foundation** with RLS enabled and basic authentication in place, but suffers from **critical gaps** in privilege management and schema consistency. The `SECURITY DEFINER` function without authorization checks is a **high-severity vulnerability** that could lead to data manipulation attacks.

The **schema mismatch** between Edge Functions and database is a **show-stopper bug** that will prevent the feature from working in production.

**Recommendation:** **DO NOT DEPLOY** until Critical Issues #1 and #2 are resolved. High-risk issues should be addressed within the next sprint to prevent future security incidents.

---

## References
- [OWASP Top 10 2021: A01 Broken Access Control](https://owasp.org/Top10/A01_2021-Broken_Access_Control/)
- [CWE-269: Improper Privilege Management](https://cwe.mitre.org/data/definitions/269.html)
- [PostgreSQL SECURITY DEFINER Best Practices](https://www.postgresql.org/docs/current/sql-createfunction.html)
- [Supabase Row Level Security Guide](https://supabase.com/docs/guides/auth/row-level-security)
