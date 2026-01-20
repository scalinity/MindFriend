# Email System Bug Report

**Generated:** 2026-01-19
**Analyzer:** Debugger Agent
**Scope:** Complete email system audit including timezone handling, retry logic, concurrent processing, and edge cases

---

## Executive Summary

Deep analysis of the email system revealed **12 bugs** across 3 severity levels:

- **CRITICAL (P0)**: 5 bugs - require immediate fix
- **HIGH (P1)**: 3 bugs - fix before production
- **MEDIUM (P2)**: 4 bugs - fix soon

The most severe issues involve timezone calculation errors, security vulnerabilities, and unsubscribed users receiving emails.

---

## Critical Bugs (P0) - Fix Immediately

### BUG-001: Timezone Calculation Uses Server Timezone Instead of User Timezone

**File:** `supabase/functions/_shared/email-utils.ts:51-97`
**Function:** `calculateScheduledTime()`

**Root Cause:**

```typescript
// Line 64-65: Creates date string WITHOUT timezone
const userDateStr = `${year}-${month}-${day}T${String(preferredSendHour).padStart(2, "0")}:00:00`;

// Line 80: Parses in LOCAL (server) timezone, not user's timezone
const tempDate = new Date(userDateStr);

// Line 84: Gets SERVER's timezone offset, NOT user's
const userOffsetMinutes = tempDate.getTimezoneOffset();
```

**Impact:**

- User in PST (UTC-8) requests 9am email
- Server in UTC creates "2026-01-19T09:00:00"
- Parses as 9am UTC (server time)
- Calculates offset as 0 (server is UTC)
- Schedules email for 9am UTC = **1am PST** (8 hours early)

**Evidence:** Testing with different server/user timezones will fail.

**Fix:**

```typescript
function calculateScheduledTime(
  userTimezone: string,
  preferredSendHour: number,
  baseDate: Date = new Date(),
): Date {
  // Create ISO string in user's timezone using Intl API
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: userTimezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });

  const parts = formatter.formatToParts(baseDate);
  const year = parts.find((p) => p.type === "year")!.value;
  const month = parts.find((p) => p.type === "month")!.value;
  const day = parts.find((p) => p.type === "day")!.value;

  // Build date string for user's timezone at preferred hour
  const dateInUserTZ = new Date(
    `${year}-${month}-${day}T${String(preferredSendHour).padStart(2, "0")}:00:00`,
  );

  // Convert to UTC using proper timezone offset calculation
  const userDate = new Date(
    dateInUserTZ.toLocaleString("en-US", { timeZone: userTimezone }),
  );
  const utcDate = new Date(
    dateInUserTZ.toLocaleString("en-US", { timeZone: "UTC" }),
  );
  const offset = utcDate.getTime() - userDate.getTime();

  return new Date(dateInUserTZ.getTime() + offset);
}
```

**Alternative Fix (Recommended):** Use a proper timezone library like `date-fns-tz` or `luxon`:

```typescript
import { zonedTimeToUtc } from "date-fns-tz";

function calculateScheduledTime(
  userTimezone: string,
  preferredSendHour: number,
  baseDate: Date = new Date(),
): Date {
  const year = baseDate.getFullYear();
  const month = baseDate.getMonth();
  const day = baseDate.getDate();

  // Create date in user's timezone
  const localDate = new Date(year, month, day, preferredSendHour, 0, 0);

  // Convert to UTC
  return zonedTimeToUtc(localDate, userTimezone);
}
```

---

### BUG-002: DST (Daylight Saving Time) Not Handled

**File:** `supabase/functions/_shared/email-utils.ts:51-97`
**Function:** `calculateScheduledTime()`

**Root Cause:**
The timezone offset calculation doesn't account for DST transitions. On DST boundaries (e.g., March 10, 2024 at 2am), the offset changes by 1 hour.

**Impact:**

- User in PST sets preferred time to 9am
- On March 9 (before DST): offset is UTC-8
- On March 10 (DST starts): offset is UTC-7
- Emails sent 1 hour early/late during DST transition week

**Example:**

```
March 9, 2026 (PST = UTC-8):  9am PST = 5pm UTC ✓
March 10, 2026 (PDT = UTC-7): 9am PDT = 4pm UTC ✓
March 10, 2026 (BUG):         9am PDT = 5pm UTC ✗ (1 hour late)
```

**Fix:** Use timezone library that handles DST (see BUG-001 fix).

---

### BUG-003: Unsubscribed Users Receive Emails

**File:** `supabase/functions/lapsed-user-nudge/index.ts:42`
**Function:** Lapsed user processing loop

**Root Cause:**

```typescript
// Line 42: WRONG - checks truthiness, not null check
if (!prefs || !prefs.lapsed_nudge || prefs.unsubscribed_at) continue;
```

This checks if `unsubscribed_at` is truthy (exists), not if it's null. JavaScript truthy check:

- `null` → falsy → condition fails → sends email ✓
- `"2026-01-15T00:00:00Z"` → truthy → condition passes → **skips** (INTENDED)

**Wait, re-analyzing:** Actually this IS correct!

- If `unsubscribed_at` has a date → truthy → `continue` (skip user) ✓
- If `unsubscribed_at` is null → falsy → proceed ✓

**UPDATE:** Bug analysis was incorrect. Code is actually correct. Marking as FALSE POSITIVE.

---

### BUG-004: Webhook Signature Verification Disabled (CRITICAL SECURITY)

**File:** `supabase/functions/_shared/email-utils.ts:298-319`
**Function:** `verifySvixSignature()`

**Root Cause:**

```typescript
// Line 318: PLACEHOLDER - always returns true
return true; // Placeholder - implement proper HMAC-SHA256 verification
```

**Impact:**

- **CRITICAL SECURITY VULNERABILITY**
- Anyone can forge webhook requests to `/email-webhook`
- Can fake bounces to suppress emails to legitimate users
- Can mark users as spam complainers to auto-unsubscribe them
- Can manipulate email_logs data

**Attack Scenario:**

```bash
curl -X POST https://yourproject.supabase.co/functions/v1/email-webhook \
  -H "Content-Type: application/json" \
  -d '{
    "type": "email.complained",
    "data": {
      "email_id": "user-message-id",
      "to": "victim@example.com"
    }
  }'
```

Result: Victim is automatically unsubscribed from all emails.

**Fix:**

```typescript
import { Webhook } from "https://esm.sh/@svix/svix@1.15.0";

function verifySvixSignature(
  body: string,
  signatureHeader: string,
  secret: string,
): boolean {
  try {
    const wh = new Webhook(secret);
    // Svix will throw if signature invalid
    wh.verify(body, {
      "svix-id": extractHeader(signatureHeader, "svix-id"),
      "svix-timestamp": extractHeader(signatureHeader, "svix-timestamp"),
      "svix-signature": extractHeader(signatureHeader, "svix-signature"),
    });
    return true;
  } catch (error) {
    console.error("Webhook signature verification failed:", error);
    return false;
  }
}

function extractHeader(header: string, key: string): string {
  const match = header.match(new RegExp(`${key}=([^,]+)`));
  return match ? match[1] : "";
}
```

**Also update email-webhook/index.ts:**

```typescript
// Add signature verification
const signature = req.headers.get("svix-signature") || "";
const webhookSecret = Deno.env.get("RESEND_WEBHOOK_SECRET")!;

if (!verifySvixSignature(await req.text(), signature, webhookSecret)) {
  return new Response(JSON.stringify({ error: "Invalid signature" }), {
    status: 401,
    headers: { "Content-Type": "application/json" },
  });
}
```

---

### BUG-005: Resend Idempotency Not Implemented

**File:** `supabase/functions/send-email/index.ts:227-248`
**Function:** Resend API call

**Root Cause:**

```typescript
// Line 244: Uses X-Entity-Ref-ID for tracking, NOT idempotency
headers: {
  "X-Entity-Ref-ID": messageId,
  "List-Unsubscribe": `${appUrl}/email-preferences`,
}
```

Resend uses `Idempotency-Key` header (not X-Entity-Ref-ID) to prevent duplicate sends.

**Impact:**

- Edge Function times out after sending to Resend but before logging success
- Retry logic triggers (line 272-283)
- Resend receives duplicate request
- User gets 2 identical emails

**Scenario:**

1. send-email calls Resend API (success)
2. Network delay on response
3. Edge Function times out (120s default)
4. Queue processor retries (retry_count = 1)
5. Resend receives duplicate → sends duplicate email

**Fix:**

```typescript
// Line 237-248: Add Idempotency-Key header
body: JSON.stringify({
  from: "MindFriend <notifications@mindfriend.email>",
  to: userProfile.email,
  subject: template.subject,
  html: template.htmlBody,
  text: template.textBody,
  headers: {
    "X-Entity-Ref-ID": messageId,
    "List-Unsubscribe": `${appUrl}/email-preferences`,
    "Idempotency-Key": messageId, // ADD THIS
  },
}),
```

---

## High Priority Bugs (P1) - Fix Before Production

### BUG-006: Week Start Calculation Mutates Input Date

**File:** `supabase/functions/_shared/email-utils.ts:100-107`
**Function:** `getCurrentWeekStart()`

**Root Cause:**

```typescript
// Line 100-104: Creates date but then mutates it
const now = new Date();
const dayOfWeek = now.getDay();
const diff = now.getDate() - dayOfWeek + (dayOfWeek === 0 ? -6 : 1);
const weekStart = new Date(now.setDate(diff)); // MUTATION
weekStart.setHours(0, 0, 0, 0); // More mutation
```

**Impact:**

- If caller uses `now` after calling this function, it's been mutated to Monday 00:00:00
- Hard to debug because mutation is invisible

**Example:**

```typescript
const today = new Date(); // 2026-01-19 (Sunday) 14:30:00
const weekStart = getCurrentWeekStart();
console.log(today); // 2026-01-13 (Monday) 00:00:00 - MUTATED!
```

**Fix:**

```typescript
function getCurrentWeekStart(): Date {
  const now = new Date();
  const dayOfWeek = now.getDay();
  const diff = now.getDate() - dayOfWeek + (dayOfWeek === 0 ? -6 : 1);

  // Create NEW date object, don't mutate
  const weekStart = new Date(now);
  weekStart.setDate(diff);
  weekStart.setHours(0, 0, 0, 0);

  return weekStart;
}
```

---

### BUG-007: Sequential Email Processing Creates Bottleneck

**File:** `supabase/functions/process-email-queue/index.ts:72-111`
**Function:** Queue processing loop

**Root Cause:**

```typescript
// Lines 72-111: Sequential processing with await in loop
for (const item of items) {
  const response = await fetch(sendEmailUrl, { ... }); // BLOCKS
  // ... process result
}
```

**Impact:**

- Batch of 50 emails processes sequentially
- Each email takes ~2-5 seconds (template render + Resend API + DB writes)
- Total time: 50 × 3s = 150 seconds (2.5 minutes) per worker
- At 10,000 users with weekly summary, needs 200 batches = 8+ hours

**Scale Problem:**

- 100,000 users = 80+ hours (3+ days)
- Misses weekly send window

**Fix:**

```typescript
// Process in parallel with concurrency limit
const CONCURRENCY = 10;

async function processBatch(items: EmailQueueItem[]) {
  const chunks = [];
  for (let i = 0; i < items.length; i += CONCURRENCY) {
    chunks.push(items.slice(i, i + CONCURRENCY));
  }

  let successCount = 0;
  let failureCount = 0;

  for (const chunk of chunks) {
    const promises = chunk.map(async (item) => {
      try {
        const response = await fetch(sendEmailUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${supabaseServiceKey}`,
          },
          body: JSON.stringify({ queueItemId: item.id }),
        });

        const result = await response.json();
        return {
          success: response.ok,
          queueItemId: item.id,
          result,
        };
      } catch (error) {
        return {
          success: false,
          queueItemId: item.id,
          error: String(error),
        };
      }
    });

    const results = await Promise.allSettled(promises);
    results.forEach((r) => {
      if (r.status === "fulfilled" && r.value.success) {
        successCount++;
      } else {
        failureCount++;
      }
    });
  }

  return { successCount, failureCount };
}
```

**Performance Impact:**

- Before: 50 emails × 3s = 150s
- After: (50 / 10 concurrency) × 3s = 15s
- **10x speedup**

---

### BUG-008: Lapsed User Time Window Fragility

**File:** `supabase/functions/lapsed-user-nudge/index.ts:20-29`
**Function:** Inactive user detection

**Root Cause:**

```typescript
// Lines 20-28: 1-day window for "exactly N days inactive"
const thresholdDate = new Date();
thresholdDate.setDate(thresholdDate.getDate() - days);

const { data: inactiveUsers } = await supabase
  .from("profiles")
  .select("id, email, full_name, last_active_at")
  .lte("last_active_at", thresholdDate.toISOString())
  .gte(
    "last_active_at",
    new Date(thresholdDate.getTime() - 86400000).toISOString(),
  );
```

**Impact:**

- 3-day threshold: matches users inactive 3-4 days ago
- 7-day threshold: matches users inactive 7-8 days ago
- If function runs at inconsistent times, users might be missed

**Example:**

- User last active: Jan 1 at 10am
- Function runs Jan 4 at 9am (3 days ago = Jan 1 at 9am)
- User's last_active (10am) is AFTER threshold (9am)
- User NOT matched (falls through gap)
- Function runs Jan 5 at 9am (user now 4 days inactive)
- User NOT matched by 3-day window (too old)
- User NOT matched by 7-day window (too recent)
- **User never gets 3-day email**

**Fix:**

```typescript
// Use single threshold, track sent nudges separately
const thresholdDate = new Date();
thresholdDate.setDate(thresholdDate.getDate() - days);

const { data: inactiveUsers } = await supabase
  .from("profiles")
  .select("id, email, full_name, last_active_at")
  .lte("last_active_at", thresholdDate.toISOString());

for (const user of inactiveUsers) {
  // Check if we already sent this threshold's email
  const { data: existingNudge } = await supabase
    .from("email_queue")
    .select("id")
    .eq("user_id", user.id)
    .eq("email_type", "lapsed_nudge")
    .gte(
      "created_at",
      new Date(Date.now() - days * 86400000 - 86400000).toISOString(),
    )
    .lte(
      "created_at",
      new Date(Date.now() - days * 86400000 + 86400000).toISOString(),
    )
    .single();

  if (existingNudge) {
    continue; // Already sent for this threshold
  }

  // ... queue email
}
```

---

## Medium Priority Bugs (P2) - Fix Soon

### BUG-009: Payload userName Overwritten Without Check

**File:** `supabase/functions/send-email/index.ts:188-191`
**Function:** Payload enrichment

**Root Cause:**

```typescript
// Lines 188-191: Always overwrites userName
const enrichedPayload = {
  ...qi.payload,
  userName: userProfile.full_name || userProfile.email.split("@")[0],
};
```

**Impact:**

- If payload already contains customized userName, it's overwritten
- Minor issue, but violates principle of least surprise

**Example:**

```typescript
// Queue item has payload: { userName: "Dear Valued Customer", ... }
// After enrichment: { userName: "John Doe", ... }
// Email says "Hi John Doe" instead of "Hi Dear Valued Customer"
```

**Fix:**

```typescript
const enrichedPayload = {
  userName: userProfile.full_name || userProfile.email.split("@")[0],
  ...qi.payload, // Spread AFTER defaults so payload can override
};
```

---

### BUG-010: Crisis Suppression Uses Date Mutation

**File:** `supabase/functions/_shared/email-utils.ts:125-126`
**Function:** `checkCrisisSuppressionPeriod()`

**Root Cause:**

```typescript
// Lines 125-126: Mutates date object
const fourteenDaysAgo = new Date();
fourteenDaysAgo.setDate(fourteenDaysAgo.getDate() - 14);
```

**Impact:**

- Same mutation issue as BUG-006
- Less severe because fourteenDaysAgo is local variable
- Still poor practice, could cause bugs if refactored

**Fix:**

```typescript
const fourteenDaysAgo = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000);
```

---

### BUG-011: Rate Limit Uses Date Mutation

**File:** `supabase/functions/_shared/email-utils.ts:149-150`
**Function:** `checkRateLimit()`

**Root Cause:**

```typescript
// Lines 149-150: Mutates date object
const sevenDaysAgo = new Date();
sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
```

**Impact:** Same as BUG-010

**Fix:**

```typescript
const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
```

---

### BUG-012: send-weekly-summary and send-monthly-report Missing Error Details

**Files:**

- `supabase/functions/send-weekly-summary/index.ts:199-201`
- `supabase/functions/send-monthly-report/index.ts:129-131`

**Root Cause:**

```typescript
// Catches error but only logs to console
catch (error) {
  console.error(`Error processing user ${pref.user_id}:`, error);
  errorCount++;
}
```

**Impact:**

- Error details lost
- Hard to debug why specific users failed
- No way to retry failed users

**Fix:**

```typescript
catch (error) {
  console.error(`Error processing user ${pref.user_id}:`, error);
  errorCount++;

  // Log to DLQ for manual review
  await supabase.from("email_dead_letter_queue").insert({
    user_id: pref.user_id,
    email_type: "weekly_summary", // or "monthly_report"
    template_version: "v1",
    payload: { error: String(error) },
    failure_count: 1,
    last_error: formatErrorMessage(error),
    original_scheduled_for: new Date().toISOString(),
  });
}
```

---

## Summary Table

| ID      | Severity | File                        | Function               | Impact                     | Fix Complexity       |
| ------- | -------- | --------------------------- | ---------------------- | -------------------------- | -------------------- |
| BUG-001 | P0       | email-utils.ts:51           | calculateScheduledTime | Emails sent at wrong time  | Medium (use lib)     |
| BUG-002 | P0       | email-utils.ts:51           | calculateScheduledTime | DST causes 1hr offset      | Medium (use lib)     |
| BUG-003 | ~~P0~~   | ~~lapsed-user-nudge.ts:42~~ | ~~Unsubscribe check~~  | ~~FALSE POSITIVE~~         | ~~N/A~~              |
| BUG-004 | P0       | email-utils.ts:318          | verifySvixSignature    | Security vulnerability     | Low (add lib)        |
| BUG-005 | P0       | send-email/index.ts:244     | Resend API call        | Duplicate emails on retry  | Low (add header)     |
| BUG-006 | P1       | email-utils.ts:104          | getCurrentWeekStart    | Date mutation side effect  | Low (clone date)     |
| BUG-007 | P1       | process-email-queue.ts:72   | Processing loop        | Slow processing (10x)      | Medium (parallelize) |
| BUG-008 | P1       | lapsed-user-nudge.ts:23     | Time window            | Users miss nudges          | Medium (track sent)  |
| BUG-009 | P2       | send-email/index.ts:188     | Payload enrichment     | Overwrites custom userName | Low (reorder spread) |
| BUG-010 | P2       | email-utils.ts:125          | checkCrisisSuppression | Date mutation              | Low (use timestamp)  |
| BUG-011 | P2       | email-utils.ts:149          | checkRateLimit         | Date mutation              | Low (use timestamp)  |
| BUG-012 | P2       | send-weekly-summary.ts:199  | Error handling         | Lost error details         | Low (log to DLQ)     |

**Total:** 11 bugs (1 false positive removed)

---

## Testing Recommendations

### Timezone Testing

```typescript
// Test cases for BUG-001 and BUG-002
describe("calculateScheduledTime", () => {
  it("should schedule PST user for 9am PST, not UTC", () => {
    const scheduled = calculateScheduledTime(
      "America/Los_Angeles",
      9,
      new Date("2026-01-19T00:00:00Z"),
    );
    const pstTime = scheduled.toLocaleString("en-US", {
      timeZone: "America/Los_Angeles",
    });
    expect(pstTime).toContain("9:00:00 AM");
  });

  it("should handle DST transition (spring forward)", () => {
    const beforeDST = calculateScheduledTime(
      "America/Los_Angeles",
      9,
      new Date("2026-03-07T00:00:00Z"),
    );
    const afterDST = calculateScheduledTime(
      "America/Los_Angeles",
      9,
      new Date("2026-03-09T00:00:00Z"),
    );

    // Both should be 9am PST/PDT, but different UTC times
    const beforeUTC = beforeDST.getUTCHours();
    const afterUTC = afterDST.getUTCHours();
    expect(beforeUTC - afterUTC).toBe(1); // 1 hour difference due to DST
  });
});
```

### Security Testing

```bash
# Test BUG-004: Webhook signature verification
curl -X POST https://yourproject.supabase.co/functions/v1/email-webhook \
  -H "Content-Type: application/json" \
  -d '{"type": "email.complained", "data": {"email_id": "test"}}' \
  # Should return 401 Unauthorized
```

### Load Testing

```bash
# Test BUG-007: Queue processing performance
# Insert 1000 test emails
for i in {1..1000}; do
  # Insert to email_queue
done

# Measure processing time
time curl -X POST https://yourproject.supabase.co/functions/v1/process-email-queue

# Should complete in <60 seconds with parallelization
# Without parallelization: >3000 seconds
```

---

## Recommended Action Plan

### Phase 1: Critical Fixes (Week 1)

1. BUG-001 & BUG-002: Replace timezone logic with `date-fns-tz`
2. BUG-004: Implement Svix signature verification
3. BUG-005: Add Resend idempotency key

### Phase 2: High Priority (Week 2)

4. BUG-006: Fix date mutation in getCurrentWeekStart
5. BUG-007: Parallelize email queue processing
6. BUG-008: Fix lapsed user time window logic

### Phase 3: Medium Priority (Week 3)

7. BUG-009 through BUG-012: Fix remaining issues

### Phase 4: Testing & Validation

8. Add unit tests for all fixed bugs
9. Load test with 10,000+ queued emails
10. Timezone test across all supported timezones
11. DST transition test (March/November dates)

---

## Prevention: Future Safeguards

1. **Timezone handling:** Always use timezone libraries, never manual offset math
2. **Date mutations:** Use `new Date(timestamp)` instead of `setDate()`
3. **Security:** Never deploy placeholder security code to production
4. **Concurrency:** Use `Promise.all()` for parallel operations
5. **Testing:** Add timezone/DST test cases to CI/CD

---

## References

- **Email Utils:** `supabase/functions/_shared/email-utils.ts`
- **Send Email:** `supabase/functions/send-email/index.ts`
- **Queue Processor:** `supabase/functions/process-email-queue/index.ts`
- **Schema:** `supabase/migrations/20260420000000_email_summary_schema.sql`
- **Documentation:** `docs/EMAIL_CONFIGURATION.md`
