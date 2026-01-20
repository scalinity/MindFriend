# GDPR Email Security Audit - Quick Reference

## Overall Score: 5/10 (FAIL - BLOCK PRODUCTION)

```
┌─────────────────────────────────────────────────────────┐
│  GDPR COMPLIANCE SCORECARD                              │
├─────────────────────────────────────────────────────────┤
│  ✅ Retention Policies (Article 5)          9/10        │
│  ✅ Cascade Deletion (Article 17)          10/10        │
│  ✅ Rate Limiting (TOCTOU Fix)             10/10        │
│  ⚠️  PII Protection (Article 32)            6/10        │
│  ❌ Encryption (Article 32)                 2/10 FAIL   │
│  ❌ Audit Trail (Article 30)                2/10 FAIL   │
├─────────────────────────────────────────────────────────┤
│  AVERAGE:                                   5.0/10      │
└─────────────────────────────────────────────────────────┘
```

## Critical Blockers (P0)

### 1. Encryption Infrastructure Exists But Unused ❌

**File:** `/supabase/functions/_shared/encryption.ts`
**Status:** Dead code - never imported or called

```typescript
// EXISTS BUT NEVER USED:
export async function encryptPayload(payload) { ... }
export async function decryptPayload(encrypted) { ... }

// ACTUAL USAGE IN CODEBASE:
// grep -r "import.*encryption" → NO RESULTS
// grep -r "encryptPayload" → NO RESULTS
```

**Impact:** All health data stored in plaintext `payload` column.

**Fix Required:**
```typescript
// In send-email/index.ts (line ~235)
import { encryptPayload } from "../_shared/encryption.ts";

const encryptedPayload = await encryptPayload(qi.payload);
await supabase.from("email_queue").insert({
  encrypted_payload: encryptedPayload,
  payload: null // Deprecate plaintext
});
```

**Environment:**
```bash
supabase secrets set EMAIL_ENCRYPTION_KEY="$(openssl rand -base64 32)"
```

---

### 2. Audit Log Created After It's Used ❌

**Migration Order Bug:**
```
20260129000001_email_retention_policies.sql
  ↓ References audit_log (line 72)
  ↓ CREATE FUNCTION log_data_deletion()
  ↓   INSERT INTO audit_log ...
  ↓
20260129000002_audit_log_table.sql
  ↓ CREATE TABLE audit_log  ← TOO LATE!
```

**Impact:** Trigger `audit_email_logs_deletion` will fail on first deletion.

**Fix Required:**
```bash
# Renumber migrations to fix dependency order
mv 20260129000002_audit_log_table.sql 20260129000000_audit_log_table.sql
# (renumber others accordingly)
```

---

### 3. PII Leaked in Logs ⚠️

**Violations Found:**

```typescript
// process-email-queue/index.ts:86
console.log(`Worker ${workerId} claimed ${batch.length} emails`);
// EXPOSES: workerId = "worker-1737398400000-abc123" (timestamp + random)

// process-email-queue/index.ts:124
console.error(`Email send failed for queue item ${queueItemId}`, error);
// EXPOSES: queueItemId = UUID correlating to user_id

// send-email/index.ts:357
return new Response(JSON.stringify({
  messageId,     // Correlates to user
  queueItemId,   // Correlates to user
  emailType
}));
// EXPOSES: Internal IDs in HTTP responses
```

**Fix Required:**
```typescript
// Remove PII from logs
console.log(`Worker claimed ${batch.length} emails`); // No workerId
console.error(`Email send failed: ${error.name}`);     // No queueItemId

// Redact from responses
return new Response(JSON.stringify({
  success: true,
  emailType  // Only non-identifying data
}));
```

---

## What's Working Well ✅

### Retention Policies (9/10)
```sql
-- Automatic cleanup via pg_cron
email_logs              → 90 days
email_dead_letter_queue → 30 days
email_queue (stale)     → 7 days
audit_log               → 2 years
```

### Cascade Deletion (10/10)
```sql
-- All tables have ON DELETE CASCADE
email_preferences       → ON DELETE CASCADE
email_queue            → ON DELETE CASCADE
email_logs             → ON DELETE CASCADE
email_dead_letter_queue → ON DELETE CASCADE
email_suppression_list → ON DELETE CASCADE
```

When `DELETE FROM auth.users WHERE id = '...'` runs, all email data is automatically purged.

### Rate Limiting (10/10)
```sql
-- Atomic check prevents TOCTOU race condition
CREATE FUNCTION insert_email_log_with_rate_limit_check(...)
  -- Uses FOR UPDATE SKIP LOCKED
```

---

## Implementation Checklist

### Before Production Launch

- [ ] Import encryption functions in send-email/index.ts
- [ ] Import encryption functions in process-email-queue/index.ts
- [ ] Set EMAIL_ENCRYPTION_KEY in Supabase secrets
- [ ] Renumber migrations to fix audit_log dependency
- [ ] Remove workerId from console.log statements
- [ ] Remove queueItemId from console.error statements
- [ ] Redact PII from HTTP responses
- [ ] Write encryption test (see GDPR_EMAIL_SECURITY_AUDIT.md)
- [ ] Write cascade deletion test
- [ ] Write audit log test
- [ ] Run `supabase db push` to apply migrations
- [ ] Verify all pg_cron jobs scheduled

### Post-Launch (Within 1 Week)

- [ ] Make audit_log append-only (REVOKE UPDATE/DELETE)
- [ ] Add access logging (track reads to email_logs)
- [ ] Document encryption setup in EMAIL_CONFIGURATION.md
- [ ] Implement structured logging (replace console.log)

---

## File Locations

| Concern | File |
|---------|------|
| Encryption (unused) | `/supabase/functions/_shared/encryption.ts` |
| Send email | `/supabase/functions/send-email/index.ts` |
| Process queue | `/supabase/functions/process-email-queue/index.ts` |
| PII sanitization | `/supabase/functions/_shared/email-utils.ts:399-404` |
| Email schema | `/supabase/migrations/20260420000000_email_summary_schema.sql` |
| Retention policies | `/supabase/migrations/20260129000001_email_retention_policies.sql` |
| Audit log | `/supabase/migrations/20260129000002_audit_log_table.sql` |
| Encryption support | `/supabase/migrations/20260129000003_encrypted_payload_support.sql` |

---

## Quick Verification Commands

```bash
# Check if encryption is imported (should return 0 results = BAD)
grep -r "import.*encryption" supabase/functions

# Check if encrypted_payload is used (should return 0 results = BAD)
grep -rn "encrypted_payload" supabase/functions --include="*.ts"

# Verify migration order (audit_log should come BEFORE email_retention_policies)
ls -la supabase/migrations/202601290000*.sql

# Check for PII in logs
grep -rn "console.log\|console.error" supabase/functions/send-email supabase/functions/process-email-queue

# Verify cascade constraints exist
psql $DATABASE_URL -c "
SELECT conname, conrelid::regclass, pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conname LIKE '%email%_user_id_fkey%';
"
```

---

## Summary

**Good News:**
- Strong GDPR foundation (retention, cascade deletion, rate limiting)
- Infrastructure for encryption exists (just not connected)
- PII sanitization in error messages

**Bad News:**
- Encryption implemented but never called (0% usage)
- Audit log will fail on first deletion (migration order bug)
- PII leaked in console logs and HTTP responses

**Verdict:** **DO NOT DEPLOY TO PRODUCTION** until P0 issues resolved.

**Estimated Fix Time:** 2-3 days for senior engineer.

---

**See Full Report:** `GDPR_EMAIL_SECURITY_AUDIT.md`
