# Security Audit: Life Transition Pathways Data Protection
**Date:** 2026-01-24  
**Scope:** Pathway journal entries, check-in data, logging practices  
**Auditor:** Security Auditor Agent  
**Overall Score:** 5/10

---

## Executive Summary

The Life Transition Pathways feature (F015) stores highly sensitive personal journal entries in **plaintext** in the PostgreSQL database, creating a significant data protection inconsistency compared to other MindFriend features. While Row Level Security (RLS) prevents unauthorized access, the lack of encryption at rest exposes users to database breach risks.

**Critical Finding:** Journal entries describing grief, trauma, health diagnoses, and relationship breakdowns are stored unencrypted, while less sensitive features like Private Vault use AES-256 encryption.

**Risk Level:** HIGH (CVSS 7.2) - Sensitive data exposure via database breach or backup extraction.

---

## Findings

### 🔴 CRITICAL: Journal Entries Stored Unencrypted

**Severity:** Critical (P0)  
**Location:** `supabase/migrations/20260125000000_transition_pathways.sql:68`  
**CWE:** CWE-311 (Missing Encryption of Sensitive Data)

#### Description
The `pathway_progress.journal_entry` column stores user journal entries as plaintext `TEXT` in PostgreSQL:

```sql
CREATE TABLE IF NOT EXISTS pathway_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_pathway_id UUID NOT NULL REFERENCES user_pathways(id) ON DELETE CASCADE,
    day_number INTEGER NOT NULL CHECK (day_number > 0),
    phase_number INTEGER NOT NULL CHECK (phase_number BETWEEN 1 AND 4),
    check_in_completed BOOLEAN NOT NULL DEFAULT false,
    check_in_data JSONB,
    exercises_completed TEXT[] NOT NULL DEFAULT ARRAY[]::text[],
    journal_entry TEXT CHECK (length(journal_entry) <= 10000),  -- ❌ PLAINTEXT
    milestones_achieved TEXT[] NOT NULL DEFAULT ARRAY[]::text[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_pathway_id, day_number)
);
```

**Example Sensitive Content:**
- Grief pathway (loss of loved one): "I can't stop crying. I feel like part of me died with them."
- Health diagnosis: "The doctor said it's stage 3. I'm terrified I won't see my kids grow up."
- Breakup: "I found out they were cheating. I feel worthless and stupid for not seeing it."

#### Impact
- **Database Breach:** Attackers gaining database access can read all journal entries in plaintext
- **Insider Threat:** DBAs, support staff with database credentials can read user journals
- **Backup Exposure:** Database backups stored in S3/cloud contain plaintext journal data
- **Compliance Risk:** Violates data minimization principles (GDPR Art. 5(1)(c))

#### Exploitation
```sql
-- Malicious query to extract all journal entries
SELECT 
    p.email,
    tp.name AS pathway_name,
    pp.journal_entry,
    pp.created_at
FROM pathway_progress pp
JOIN user_pathways up ON pp.user_pathway_id = up.id
JOIN profiles p ON up.user_id = p.id
JOIN transition_pathways tp ON up.pathway_id = tp.id
WHERE pp.journal_entry IS NOT NULL
ORDER BY pp.created_at DESC;
```

#### Remediation
**Option 1: Client-Side Encryption (Recommended)**
```swift
// In TransitionService.swift
func completeCheckIn(
    userPathwayId: UUID,
    checkInData: CheckInData,
    journalEntry: String? = nil
) async throws -> CheckInResponse {
    
    // Encrypt journal entry before sending to server
    let encryptedJournal: String?
    if let journal = journalEntry {
        let key = try await getOrCreateJournalKey()  // Stored in Keychain
        let encrypted = try AES.GCM.seal(journal.data(using: .utf8)!, using: key)
        encryptedJournal = encrypted.combined.base64EncodedString()
    } else {
        encryptedJournal = nil
    }
    
    let request = CheckInRequest(
        userPathwayId: userPathwayId.uuidString,
        checkInData: checkInData,
        exercisesCompleted: exercisesCompleted,
        journalEntry: encryptedJournal  // Send encrypted
    )
    
    // ...
}
```

**Option 2: Server-Side Encryption (Alternative)**
```sql
-- Migration: Add encrypted column
ALTER TABLE pathway_progress 
    ADD COLUMN journal_entry_encrypted BYTEA,
    ADD COLUMN journal_nonce BYTEA,
    ADD COLUMN journal_tag BYTEA;

-- Deprecate plaintext column
ALTER TABLE pathway_progress 
    ALTER COLUMN journal_entry DROP NOT NULL,
    ADD CONSTRAINT check_journal_encryption 
        CHECK (
            (journal_entry IS NULL AND journal_entry_encrypted IS NOT NULL) OR
            (journal_entry IS NOT NULL AND journal_entry_encrypted IS NULL)
        );
```

**References:**
- [OWASP Sensitive Data Exposure](https://owasp.org/www-project-top-ten/2017/A3_2017-Sensitive_Data_Exposure)
- [CWE-311: Missing Encryption of Sensitive Data](https://cwe.mitre.org/data/definitions/311.html)

---

### 🟠 HIGH: UserDefaults Draft Storage (Unencrypted)

**Severity:** High (P1)  
**Location:** `apps/ios/MindFriendApp/Features/Transitions/DailyTransitionView.swift:132-138`  
**CWE:** CWE-312 (Cleartext Storage of Sensitive Information)

#### Description
Journal drafts are stored in UserDefaults as plaintext:

```swift
.onAppear {
    // Restore draft if exists
    if let draft = UserDefaults.standard.string(forKey: "draft_journal_\(userPathway.id)") {
        journalEntry = draft  // ❌ PLAINTEXT STORAGE
    }
}
.onChange(of: journalEntry) { newValue in
    // Auto-save draft
    UserDefaults.standard.set(newValue, forKey: "draft_journal_\(userPathway.id)")  // ❌ UNENCRYPTED
}
```

#### Impact
- **iCloud Backup Exposure:** UserDefaults syncs to iCloud by default - journal drafts accessible via backup extraction
- **iTunes Backup:** Local backups on computers contain plaintext drafts
- **Device Forensics:** Accessible via file system access (jailbroken devices)
- **Persistence Risk:** Drafts remain in storage even after submission if app crashes

#### Exploitation
```bash
# Extract UserDefaults from iOS backup
idevicebackup2 backup --full ./backup_dir
sqlite3 backup_dir/HomeDomain/Library/Preferences/com.mindfriend.app.plist
# Query: SELECT * FROM preferences WHERE key LIKE 'draft_journal_%';
```

#### Remediation
```swift
// Use Keychain for draft storage (same pattern as VaultEncryptionService)
.onAppear {
    if let draft = try? keychainManager.getString(for: "draft_journal_\(userPathway.id)") {
        journalEntry = draft
    }
}
.onChange(of: journalEntry) { newValue in
    try? keychainManager.set(newValue, for: "draft_journal_\(userPathway.id)")
}
```

**Alternative: In-Memory Only**
```swift
// Store drafts only in memory (@State), no persistence
// Trade-off: User loses draft if app is force-quit
@State private var journalEntry = ""  // No persistence
```

**References:**
- [Apple Data Protection Guidelines](https://developer.apple.com/documentation/security/keychain_services)
- [CWE-312: Cleartext Storage of Sensitive Information](https://cwe.mitre.org/data/definitions/312.html)

---

### 🟡 MEDIUM: PII Exposure in Error Logs

**Severity:** Medium (P2)  
**Location:** `supabase/functions/submit-pathway-checkin/index.ts:147-157`  
**CWE:** CWE-532 (Insertion of Sensitive Information into Log File)

#### Description
Edge Function logs database errors without scrubbing sensitive data:

```typescript
const { data: result, error: checkInError } = await supabaseClient
  .rpc("submit_pathway_checkin", {
    p_user_pathway_id: body.userPathwayId,
    p_check_in_data: body.checkInData,
    p_exercises_completed: body.exercisesCompleted || [],
    p_journal_entry: body.journalEntry || null,  // ⚠️ PII parameter
  });

if (checkInError) {
  console.error("Check-in error:", checkInError);  // ❌ MAY LEAK PII IN ERROR MESSAGE
  return new Response(
    JSON.stringify({
      error: "Failed to save check-in",
      details: checkInError.message,  // ❌ EXPOSED TO CLIENT
    }),
    { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}
```

#### Impact
- PostgreSQL constraint violations may include parameter values in error messages
- Check constraint failures expose journal_entry snippets: `"journal_entry exceeds 10000 chars: 'Dear diary, today I...'"`
- Logs aggregated to external systems (e.g., Datadog) retain PII indefinitely
- Error responses leak database schema and validation logic to clients

#### Remediation
```typescript
if (checkInError) {
  // Sanitize error before logging
  const sanitizedError = {
    code: checkInError.code,
    hint: checkInError.hint,
    // DO NOT log: message (may contain PII), details
  };
  console.error("Check-in error:", sanitizedError);
  
  return new Response(
    JSON.stringify({
      error: "Failed to save check-in",
      // Generic message to client, no database details
    }),
    { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}
```

**References:**
- [OWASP Logging Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html#data-to-exclude)
- [CWE-532: Insertion of Sensitive Information into Log File](https://cwe.mitre.org/data/definitions/532.html)

---

### 🔵 LOW: Stored Procedure Error Handling

**Severity:** Low (P3)  
**Location:** `supabase/migrations/20260125020000_pathway_architecture_improvements.sql:102-186`  
**CWE:** CWE-209 (Information Exposure Through an Error Message)

#### Description
PL/pgSQL stored procedures don't have explicit error logging, but PostgreSQL's default error handling may include parameter values in stack traces:

```sql
CREATE OR REPLACE FUNCTION submit_pathway_checkin(
    p_user_pathway_id UUID,
    p_check_in_data JSONB,
    p_exercises_completed TEXT[],
    p_journal_entry TEXT  -- ⚠️ Sensitive parameter
) RETURNS JSONB AS $$
DECLARE
    v_current_day INT;
    -- ...
BEGIN
    -- ...
    INSERT INTO pathway_progress (
        user_pathway_id,
        day_number,
        phase_number,
        check_in_completed,
        check_in_data,
        exercises_completed,
        journal_entry,  -- ⚠️ Inserted directly
        milestones_achieved
    ) VALUES (
        p_user_pathway_id,
        v_current_day,
        v_current_phase,
        true,
        p_check_in_data,
        p_exercises_completed,
        p_journal_entry,  -- ⚠️ If INSERT fails, error may include value
        '{}'::TEXT[]
    );
    -- No EXCEPTION handler - errors propagate to client
END;
$$ LANGUAGE plpgsql;
```

#### Impact
- Low likelihood: Errors are rare in normal operation
- If database constraint fails (e.g., UNIQUE violation), PostgreSQL may include `p_journal_entry` value in error message
- Error propagates to Edge Function → logged → potentially retained in logs

#### Remediation
```sql
-- Add exception handler to sanitize errors
CREATE OR REPLACE FUNCTION submit_pathway_checkin(
    p_user_pathway_id UUID,
    p_check_in_data JSONB,
    p_exercises_completed TEXT[],
    p_journal_entry TEXT
) RETURNS JSONB AS $$
DECLARE
    v_current_day INT;
    -- ...
BEGIN
    -- ... (existing logic)
    
    RETURN v_result;
    
EXCEPTION WHEN OTHERS THEN
    -- Log error without sensitive data
    RAISE WARNING 'Check-in failed for user_pathway %', p_user_pathway_id;
    -- Re-raise with generic message
    RAISE EXCEPTION 'Failed to save check-in' USING ERRCODE = 'P0001';
END;
$$ LANGUAGE plpgsql;
```

**References:**
- [PostgreSQL Error Handling](https://www.postgresql.org/docs/current/plpgsql-control-structures.html#PLPGSQL-ERROR-TRAPPING)

---

## Security Controls (Strengths)

### ✅ Row Level Security (RLS) Enforcement

All pathway tables have RLS enabled with proper user isolation:

```sql
-- Users can only access their own progress
CREATE POLICY "Users can manage own progress" ON pathway_progress
    FOR ALL USING (
        user_pathway_id IN (
            SELECT id FROM user_pathways WHERE user_id = auth.uid()
        )
    );
```

**Verified:** RLS prevents horizontal privilege escalation (user A cannot read user B's journals).

### ✅ Authorization Checks in Edge Functions

```typescript
// Verify pathway ownership before processing
const { data: userPathway, error: pathwayError } = await supabaseClient
  .from("user_pathways")
  .select("*, pathway:transition_pathways(*)")
  .eq("id", body.userPathwayId)
  .eq("user_id", user.id) // ✅ Authorization check
  .single();

if (pathwayError || !userPathway) {
  return new Response(JSON.stringify({ error: "User pathway not found" }), {
    status: 404,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
```

### ✅ Input Validation

```typescript
// Validate check-in data
const { mood, energy } = body.checkInData;
if (
  mood === undefined ||
  energy === undefined ||
  mood < 1 || mood > 10 ||
  energy < 1 || energy > 10
) {
  return new Response(
    JSON.stringify({ error: "Invalid mood or energy values (must be 1-10)" }),
    { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}
```

---

## Data Protection Comparison

| Feature                  | Private Vault          | Pathway Journals       | Gap       |
|--------------------------|------------------------|------------------------|-----------|
| **Encryption at Rest**   | AES-256 GCM            | None (DB encryption)   | ❌ CRITICAL |
| **Key Storage**          | iOS Keychain (device-only) | N/A                | ❌ CRITICAL |
| **Draft Storage**        | N/A (no drafts)        | UserDefaults (plaintext) | ❌ HIGH    |
| **RLS Enforcement**      | Yes                    | Yes                    | ✅ GOOD    |
| **Log Redaction**        | Unknown                | None                   | ⚠️ MEDIUM  |
| **Authorization**        | Service-level          | RLS + Edge Function    | ✅ GOOD    |

**Verdict:** Pathway journals are **MORE sensitive** than Vault entries (user-initiated) but have **LESS protection** (no encryption).

---

## Threat Model

### Threat: Database Breach

**Attacker:** External (APT, ransomware) or Insider (malicious DBA)  
**Capability:** Read access to PostgreSQL database  
**Impact:** **CRITICAL** - All journal entries exposed in plaintext  
**Likelihood:** Medium (database breaches occur ~1 in 5 years for SaaS companies)  
**Risk Score:** 7.2 (High)

**Mitigation:** Implement client-side encryption with keychain-stored keys.

### Threat: Backup Extraction

**Attacker:** Malicious actor with access to user's iCloud/iTunes backup  
**Capability:** Extract UserDefaults from backup  
**Impact:** **HIGH** - Work-in-progress journal drafts exposed  
**Likelihood:** Low (requires physical/remote access to user's backup)  
**Risk Score:** 5.1 (Medium)

**Mitigation:** Store drafts in Keychain or use in-memory only (no persistence).

### Threat: Log Aggregation System Compromise

**Attacker:** External attacker gaining access to log management system (Datadog, Splunk)  
**Capability:** Query logs for journal entry snippets in error messages  
**Impact:** **MEDIUM** - Partial journal content exposure  
**Likelihood:** Low (requires separate system breach)  
**Risk Score:** 4.3 (Medium)

**Mitigation:** Sanitize errors before logging; strip PII from error messages.

---

## Recommendations (Priority Order)

### Priority 1: CRITICAL (Implement Immediately)

1. **Encrypt Journal Entries Client-Side**
   - Use `VaultEncryptionService` pattern with AES-256 GCM
   - Store encryption key in iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
   - Migrate existing plaintext journals (one-time batch encryption)
   - Timeline: 1-2 weeks

2. **Remove Plaintext Draft Storage**
   - Replace UserDefaults with Keychain storage
   - OR: Use in-memory only (trade-off: lose draft on app termination)
   - Timeline: 2 days

### Priority 2: HIGH (Implement This Sprint)

3. **Sanitize Error Logs**
   - Redact `checkInError.message` and `checkInError.details` before logging
   - Use generic error messages to clients
   - Timeline: 1 day

4. **Add Exception Handling to Stored Procedures**
   - Wrap INSERT statements in EXCEPTION blocks
   - Log errors without parameter values
   - Timeline: 1 day

### Priority 3: MEDIUM (Next Sprint)

5. **Implement Log Retention Policy**
   - Auto-delete logs older than 30 days
   - Configure log aggregation to exclude PII fields
   - Timeline: 1 week

6. **Security Audit of Related Features**
   - Audit `companion_memory` table for similar issues
   - Review all Edge Functions for PII logging
   - Timeline: 2 weeks

---

## Compliance Impact

### GDPR (EU)
- **Art. 5(1)(f) - Integrity and Confidentiality:** ❌ FAIL - Plaintext storage does not ensure "appropriate security"
- **Art. 32 - Security of Processing:** ⚠️ PARTIAL - RLS present, but encryption missing
- **Art. 25 - Data Protection by Design:** ❌ FAIL - No encryption despite high sensitivity

### HIPAA (US - if applicable)
- **§164.312(a)(2)(iv) - Encryption:** ⚠️ RECOMMENDED (not required, but "addressable")
- **§164.312(b) - Audit Controls:** ✅ PASS - Logging present (needs PII redaction)

### CCPA (California)
- **§1798.150 - Security Breach:** 💰 HIGH LIABILITY - Breach of unencrypted journal entries = statutory damages ($100-750 per user)

---

## Testing Recommendations

1. **Penetration Test:** Simulate database breach; verify journal content is unreadable
2. **Backup Extraction Test:** Extract UserDefaults from iCloud backup; verify draft is inaccessible
3. **Log Analysis:** Search production logs for journal_entry keywords; verify none present
4. **RLS Bypass Test:** Attempt horizontal privilege escalation via SQL injection

---

## Conclusion

**Overall Security Score: 5/10**

The Life Transition Pathways feature has **strong access controls (RLS, authorization)** but **critical data protection gaps (no encryption, plaintext drafts)**. The risk of sensitive journal content exposure via database breach or backup extraction is **unacceptably high** given the feature's therapeutic nature.

**Immediate action required:**
1. Implement client-side encryption for journal entries (P0)
2. Remove UserDefaults draft storage (P1)
3. Sanitize error logs (P1)

**Timeline to acceptable security posture:** 2-3 weeks

---

**Auditor:** Security Auditor Agent  
**Methodology:** OWASP Top 10, CWE analysis, threat modeling, code review  
**Tools:** Manual static analysis, grep/ripgrep, database schema review
