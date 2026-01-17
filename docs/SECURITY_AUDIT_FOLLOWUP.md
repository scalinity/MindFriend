# Security Audit Remediation - Follow-Up Issues

**Date:** 2026-01-17
**Status:** 3 of 8 issues fixed in this PR; 5 critical issues remaining
**Priority:** All must be addressed before next production release

---

## Summary

The comprehensive 10-agent security review identified critical vulnerabilities. This PR fixes **Issues #001, #003, #008** (RLS hardening, search_path, token logging). The following **5 critical issues** require immediate follow-up:

---

## Critical Issues (Must Fix ASAP)

### 1. [CRITICAL] IDOR in `add_family_member` RPC Function

**File:** `/supabase/migrations/20260228000000_atomic_family_member_add.sql` (lines 9-127)
**Severity:** P0 - Privilege Escalation
**CVSS:** 8.5 / Critical

**Problem:**
The function accepts `p_user_id` parameter and is executable by authenticated users, but does not validate that `auth.uid() = p_user_id`. Any authenticated user can add ANY other user to ANY family group.

**Impact:**

- Add victim users to families without consent
- Escalate own privileges (assign 'parent'/'admin' roles)
- Privacy violations and social engineering

**Fix:**

```sql
IF p_user_id != auth.uid() THEN
  RAISE EXCEPTION 'Unauthorized: can only add yourself to a family';
END IF;
```

**Effort:** Low (15 minutes)
**Risk:** Medium (requires testing family member operations)
**Status:** Open - Requires new PR

---

### 2. [CRITICAL] Rate Limiter Fail-Open Behavior

**File:** `/supabase/functions/_shared/ratelimit.ts` (lines 46-54)
**Severity:** P0 - Security Bypass
**CWE:** 754 (Improper Check for Exceptional Conditions)

**Problem:**
When rate limit check fails (DB outage, RPC error), the function returns `allowed: true`, bypassing all rate limiting.

**Impact:**

- Brute-force attacks on invite codes during DB outages
- Account enumeration attacks
- AI quota exhaustion

**Fix:**
Change fail behavior based on endpoint sensitivity:

```typescript
if (error) {
  // For security-sensitive endpoints, fail closed
  return { allowed: false, remaining: 0, resetAt: Date.now() + 60000 };
}
```

**Effort:** Medium (2-3 hours to identify all security-sensitive endpoints)
**Risk:** Medium (could break legitimate traffic during DB outages)
**Status:** Open - Requires new PR with careful consideration

---

### 3. [HIGH] Error Message Information Disclosure

**Files:**

- `supabase/functions/delete-account/index.ts` (line 172)
- `supabase/functions/get-audio-recommendations/index.ts` (line 136)
- `supabase/functions/record-playback/index.ts` (line 66)
- `supabase/functions/voice-token/index.ts` (line 241)
- And 3+ other Edge Functions

**Severity:** P1 - Information Disclosure
**CWE:** 209 (Sensitive Information in Error Message)

**Problem:**
Raw `error.message` returned to clients, exposing:

- Database schema details
- SQL syntax and table names
- Stack traces with internal paths

**Impact:**

- Reconnaissance for follow-up attacks
- Information leakage about system architecture

**Fix:**
Replace all:

```typescript
return new Response(JSON.stringify({ error: error.message }), ...);
```

With:

```typescript
log.error("Detailed error:", error);  // Server-side logging
return new Response(JSON.stringify({ error: "Request failed" }), ...);
```

**Effort:** Low (30 minutes - global find-replace)
**Risk:** Low
**Status:** Open - Requires new PR

---

### 4. [HIGH] Missing INSERT Column Protection in Profiles

**File:** `/supabase/migrations/20260317000000_security_audit_profiles_hardening.sql`
**Severity:** P1 - Revenue Bypass

**Problem:**
The UPDATE trigger protects against quota/tier modifications, but INSERT operations have no protection. A malicious user could INSERT a profile row with `subscription_tier='premium'` directly.

**Impact:**

- Users can create premium accounts without payment (INSERT path)
- Different from UPDATE path which is blocked by trigger

**Fix:**
Add BEFORE INSERT trigger:

```sql
CREATE OR REPLACE FUNCTION enforce_profiles_insert_defaults()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (SELECT auth.role() = 'authenticated') THEN
    NEW.subscription_tier := 'free';
    NEW.daily_ai_quota := 10;
    NEW.daily_ai_used := 0;
    NEW.quota_reset_at := NOW();
    NEW.premium_badge := FALSE;
  END IF;
  RETURN NEW;
END;
$$;
```

**Effort:** Low (30 minutes)
**Risk:** Low
**Status:** Open - Requires new PR

---

### 5. [HIGH] Incorrect Table Reference in Exercise Completion

**File:** `/apps/ios/MindFriendApp/Networking/Services/SupabaseDataService.swift` (lines 627-631)
**Severity:** P1 - Data Integrity Bug

**Problem:**
Exercise completion code tries to update `total_exercises_completed` on `profiles` table, but this column only exists in `user_stats` table. Updates silently fail.

**Impact:**

- Exercise stats never increment
- User progression metrics incorrect
- No errors (silent failure)

**Fix:**

```swift
// Change from Tables.profiles to Tables.userStats
try await supabase
    .from(Tables.userStats)  // Correct table
    .update(["total_exercises_completed": AnyEncodable("total_exercises_completed + 1")])
    .eq("user_id", value: try userId)  // Note: user_id not id
    .execute()
```

**Effort:** Low (10 minutes)
**Risk:** Low
**Status:** Open - Requires new PR + tests

---

## Medium Priority Issues (Should Fix Before Release)

### 6. [MEDIUM] iOS print() Statements in Production Code

**File:** `/apps/ios/MindFriendApp/Core/Services/GrokVoiceService.swift` (lines 468, 474, 483, 488, etc.)
**Severity:** P2 - Privacy

**Problem:**
`print()` statements appear in device logs on release builds, not using structured `Log` system.

**Fix:**
Replace with `Log` framework:

```swift
Log.voice.debug("[VoiceToken] Got token successfully (token redacted)")
```

**Effort:** Low (15 minutes)
**Status:** Open - Requires new PR

---

### 7. [MEDIUM] Invite Code Enumeration via Timing

**File:** `/supabase/functions/join-family/index.ts` (lines 219-232)
**Severity:** P2 - Enumeration Attack

**Problem:**
Different error messages for invalid vs. expired codes, plus timing side-channel from DB lookups.

**Fix:**

- Use constant-time comparison
- Return identical error message for all failure modes
- Add random jitter to response time

**Effort:** Medium (1-2 hours)
**Status:** Open - Requires new PR

---

### 8. [MEDIUM] Missing Audit Trail for Security Events

**Severity:** P2 - Monitoring Gap

**Problem:**
Blocked profile modification attempts (trigger exceptions) are not logged to audit table.

**Fix:**
Create security audit table and log all privilege escalation attempts.

**Effort:** Medium (2-3 hours)
**Status:** Open - Requires new PR + audit infrastructure

---

## Migration Verification Checklist

- [x] Run `supabase db push --dry-run` to verify migrations
- [x] Check for syntax errors
- [x] Verify idempotency (use IF NOT EXISTS patterns)
- [ ] Test on staging database
- [ ] Run full test suite against migrations
- [ ] Verify Edge Functions work with new RLS/triggers
- [ ] Performance test with production-scale data

---

## PR Sequence Recommendation

1. **This PR (2026-01-17)**: Issues #001, #003, #008 (RLS hardening, search_path, token logging)
2. **PR #2 (Urgent)**: Issue #1 (IDOR in add_family_member)
3. **PR #3 (High)**: Issue #3 (Error disclosure cleanup)
4. **PR #4 (High)**: Issue #4 (INSERT protection) + Issue #5 (Exercise stats fix)
5. **PR #5 (Medium)**: Issue #6 (iOS logging) + Issue #7 (Timing attacks)
6. **PR #6 (Medium)**: Issue #8 (Audit logging)

---

## Testing Checklist

Before deploying each fix:

```bash
# Test database migrations
supabase db push --dry-run

# Test iOS app compiles
cd apps/ios
xcodebuild build -scheme MindFriendApp -destination 'platform=iOS Simulator,name=iPhone 15'

# Test Edge Functions
supabase functions serve

# Run test suites
deno test supabase/functions/**/*.test.ts
cd apps/ios && xcodebuild test -scheme MindFriendApp
```

---

## Learning Points for Future Audits

1. **Always check INSERT paths** for privilege-bypass vulnerabilities (not just UPDATE)
2. **Error handling must be consistent** across all Edge Functions (single template)
3. **Database transactions must be atomic** for race-condition safety
4. **All SECURITY DEFINER functions need search_path** protection
5. **Test coverage gaps** in exercise completion flow need immediate attention

---

**Owner:** Security Team
**Last Updated:** 2026-01-17
**Next Review:** After all follow-up PRs merged
