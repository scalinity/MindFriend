# Security Audit: Mentorship Input/Output Validation

**Auditor:** Security Auditor Agent
**Date:** 2026-01-24
**Scope:** Mentorship messaging system (Swift client + PostgreSQL functions)
**Overall Score:** 4/10 - CRITICAL FAILURES IDENTIFIED

---

## Executive Summary

The mentorship messaging system has CRITICAL security vulnerabilities in input sanitization and authorization logic that could allow XSS attacks and prevent legitimate message decryption.

**Immediate Action Required:**
1. Fix event handler regex to catch space variations
2. Add sanitization to introduction messages
3. Fix decryption authorization (users cannot read received messages)
4. Add missing data: URI variants to sanitization

---

## Finding 1: Event Handler Regex Bypass (CRITICAL)

**Severity:** Critical
**Location:** `supabase/migrations/20260124150000_mentorship_security_fixes.sql:326-328`
**CWE:** CWE-79 (Cross-Site Scripting)

### Description
The event handler sanitization regex pattern `on\w+\s*=\s*"[^"]*"` requires word characters immediately after "on" with no spaces. This misses variations with spaces between "on" and the event name.

### Attack Vector
```sql
-- CURRENT PATTERN CATCHES:
'onclick="alert(1)"' → Removed ✓

-- BYPASSES WITH SPACE:
'on click="alert(1)"' → NOT removed ✗
'on load="alert(1)"' → NOT removed ✗
'on error="alert(1)"' → NOT removed ✗
```

### Impact
Attacker can inject event handlers that survive sanitization and could execute when content is rendered (though SwiftUI Text() provides some protection, defense-in-depth is violated).

### Reproduction
```swift
// Send this message:
let malicious = "Hello on click=\"alert(1)\" world"
try await service.sendMessage(matchId: matchId, content: malicious)

// Query database:
SELECT content FROM mentorship_messages WHERE id = <message_id>;
// Result: "Hello on click=\"alert(1)\" world" (not sanitized)
```

### Remediation
Replace the three event handler patterns (lines 326-328) with a single comprehensive pattern:

```sql
-- BEFORE (3 separate patterns):
NEW.content := regexp_replace(NEW.content, 'on\w+\s*=\s*"[^"]*"', '', 'gi');
NEW.content := regexp_replace(NEW.content, 'on\w+\s*=\s*''[^'']*''', '', 'gi');
NEW.content := regexp_replace(NEW.content, 'on\w+\s*=\s*[^\s>]*', '', 'gi');

-- AFTER (comprehensive pattern):
-- Match: on + optional spaces + word chars + optional spaces + = + value
NEW.content := regexp_replace(NEW.content, 'on\s*\w+\s*=\s*"[^"]*"', '', 'gi');
NEW.content := regexp_replace(NEW.content, 'on\s*\w+\s*=\s*''[^'']*''', '', 'gi');
NEW.content := regexp_replace(NEW.content, 'on\s*\w+\s*=\s*[^\s>]*', '', 'gi');
```

### References
- [OWASP XSS Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html)
- CWE-79: Improper Neutralization of Input During Web Page Generation

---

## Finding 2: Introduction Message - Zero Sanitization (CRITICAL)

**Severity:** Critical
**Location:** 
- `apps/ios/MindFriendApp/Features/Mentorship/MentorshipService.swift:186`
- `supabase/migrations/20260124150000_mentorship_security_fixes.sql:152-159`
**CWE:** CWE-79 (XSS), CWE-20 (Improper Input Validation)

### Description
The `introduction_message` field in mentorship requests receives NO sanitization. Only length validation (20-1000 chars) is performed. Messages are stored and displayed without HTML/script cleaning.

### Attack Vector
```swift
// User sends mentorship request with malicious intro:
let malicious = """
Hi! <script>alert('XSS')</script> I'd love your mentorship.
<img src=x onerror="alert('XSS')">
"""
try await service.requestMentorship(
    mentorId: mentorId, 
    introductionMessage: malicious
)

// Stored as-is in database
// Displayed to mentor in MentorshipMatchesView.swift:308 via Text(intro)
```

### Impact
- Malicious HTML/JavaScript stored in database
- Potential XSS when displayed (SwiftUI provides some protection but not guaranteed)
- Social engineering attacks via formatted messages
- Database pollution with unclean data

### Remediation

**Option 1: Apply sanitization in database function**
```sql
CREATE OR REPLACE FUNCTION create_mentorship_request(
    p_mentor_id UUID,
    p_introduction_message TEXT
) RETURNS UUID AS $$
DECLARE
    v_sanitized_intro TEXT;
BEGIN
    -- SANITIZE introduction message
    v_sanitized_intro := p_introduction_message;
    
    -- Remove HTML tags
    v_sanitized_intro := regexp_replace(v_sanitized_intro, '<[^>]*>', '', 'g');
    
    -- Remove javascript: protocol
    v_sanitized_intro := regexp_replace(v_sanitized_intro, 'javascript:', '', 'gi');
    
    -- Remove event handlers (use fixed pattern from Finding 1)
    v_sanitized_intro := regexp_replace(v_sanitized_intro, 'on\s*\w+\s*=\s*"[^"]*"', '', 'gi');
    v_sanitized_intro := regexp_replace(v_sanitized_intro, 'on\s*\w+\s*=\s*''[^'']*''', '', 'gi');
    v_sanitized_intro := regexp_replace(v_sanitized_intro, 'on\s*\w+\s*=\s*[^\s>]*', '', 'gi');
    
    -- Remove data: and vbscript: protocols
    v_sanitized_intro := regexp_replace(v_sanitized_intro, 'data:', '', 'gi');
    v_sanitized_intro := regexp_replace(v_sanitized_intro, 'vbscript:', '', 'gi');
    
    -- Trim
    v_sanitized_intro := trim(v_sanitized_intro);
    
    -- Validate length AFTER sanitization
    IF length(v_sanitized_intro) < 20 THEN
        RAISE EXCEPTION 'Introduction message too short';
    END IF;
    
    IF length(v_sanitized_intro) > 1000 THEN
        RAISE EXCEPTION 'Introduction message too long';
    END IF;
    
    -- Continue with sanitized message...
    -- Use v_sanitized_intro instead of p_introduction_message in INSERT
```

**Option 2: Create reusable sanitization function**
```sql
CREATE OR REPLACE FUNCTION sanitize_text_content(p_text TEXT)
RETURNS TEXT AS $$
BEGIN
    -- Remove HTML, scripts, event handlers, dangerous protocols
    -- (Same logic as above)
    RETURN cleaned_text;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Then use in multiple places:
v_sanitized_intro := sanitize_text_content(p_introduction_message);
v_sanitized_bio := sanitize_text_content(p_bio);
```

### References
- CWE-20: Improper Input Validation
- OWASP A03:2021 – Injection

---

## Finding 3: Broken Decryption Authorization (CRITICAL)

**Severity:** Critical (Availability)
**Location:** `supabase/migrations/20260124150000_mentorship_security_fixes.sql:1001`
**CWE:** CWE-863 (Incorrect Authorization)

### Description
The `decrypt_messages_batch()` function checks if `sender_id = auth.uid()`, which means users can ONLY decrypt messages THEY sent. Users cannot decrypt messages they RECEIVED from the other party. This breaks the entire messaging system.

### Attack Vector
```sql
-- User A sends message to User B
-- Message encrypted and stored with sender_id = A

-- User B tries to read the message:
SELECT * FROM decrypt_messages_batch(ARRAY[<message_id>]);
-- Returns: "Message not found or access denied"
-- Because the check is: m.sender_id = auth.uid()
-- But auth.uid() = B, and sender_id = A
```

### Impact
- Users cannot read messages sent to them
- Complete failure of messaging functionality
- Users can only see their own sent messages (one-sided conversation)

### Current Code (BROKEN)
```sql
-- Line 1001:
SELECT m.encrypted_content, m.iv, m.encryption_key_id
INTO v_encrypted, v_iv, v_key_id
FROM mentorship_messages m
WHERE m.id = v_message_id AND m.sender_id = auth.uid();  -- WRONG!
```

### Remediation
```sql
-- Check if user is a PARTICIPANT in the match (mentor OR mentee):
SELECT m.encrypted_content, m.iv, m.encryption_key_id
INTO v_encrypted, v_iv, v_key_id
FROM mentorship_messages m
JOIN mentorship_matches mm ON m.match_id = mm.id
WHERE m.id = v_message_id 
AND (mm.mentor_id = auth.uid() OR mm.mentee_id = auth.uid());  -- FIXED!

IF v_encrypted IS NULL THEN
    RETURN QUERY SELECT v_message_id, NULL::TEXT, FALSE, 
        'Message not found or you are not a participant in this mentorship'::TEXT;
    CONTINUE;
END IF;
```

### Test Case
```swift
// Setup: User A (mentor) and User B (mentee) matched
// User A sends message
try await serviceA.sendMessage(matchId: matchId, content: "Hello mentee")

// User B should be able to read it
let messages = try await serviceB.fetchMessages(matchId: matchId)
XCTAssertEqual(messages.first?.content, "Hello mentee")  // Currently FAILS!
```

### References
- CWE-863: Incorrect Authorization
- OWASP A01:2021 – Broken Access Control

---

## Finding 4: Missing data: URI Variants (HIGH)

**Severity:** High
**Location:** `supabase/migrations/20260124150000_mentorship_security_fixes.sql:331`
**CWE:** CWE-79 (XSS)

### Description
Sanitization removes `data:text/html` but misses other dangerous data URI MIME types that can execute JavaScript.

### Attack Vectors
```javascript
// CURRENT SANITIZATION CATCHES:
data:text/html,<script>alert(1)</script>  ✓ Removed

// BYPASSES:
data:text/javascript,alert(1)  ✗ NOT removed
data:application/javascript,alert(1)  ✗ NOT removed
data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==  ✗ NOT removed (base64 variant)
```

### Remediation
```sql
-- BEFORE:
NEW.content := regexp_replace(NEW.content, 'data:text/html', '', 'gi');

-- AFTER (comprehensive):
-- Remove ALL data: URIs (broad protection)
NEW.content := regexp_replace(NEW.content, 'data:[^,\s]+', '', 'gi');

-- OR if you need to allow some data URIs (like images):
-- Remove only executable data: URIs
NEW.content := regexp_replace(NEW.content, 'data:text/(html|javascript)', '', 'gi');
NEW.content := regexp_replace(NEW.content, 'data:application/javascript', '', 'gi');
```

### References
- [OWASP - Dangerous Data URI Schemes](https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html)

---

## Finding 5: No Defense-in-Depth on Decrypted Output (MEDIUM)

**Severity:** Medium
**Location:** `apps/ios/MindFriendApp/Features/Mentorship/MentorshipService.swift:314`
**CWE:** CWE-116 (Improper Encoding or Escaping of Output)

### Description
Decrypted message content is used directly without re-sanitization. If encryption is bypassed or keys compromised, malicious content flows through.

### Attack Vector
```swift
// IF encryption key is compromised:
// 1. Attacker encrypts malicious payload with stolen key
// 2. Inserts directly into database (bypassing trigger)
// 3. Content decrypts successfully
// 4. Malicious content displayed without sanitization check

// Current flow:
let content = decryptResult.decrypted_content ?? ""  // No sanitization!
return DBMentorshipMessage(..., content: content, ...)
```

### Impact
- Single point of failure (encryption)
- No validation that decrypted content matches expected format
- Potential for injection if encryption is ever weakened

### Remediation
```swift
// Add post-decryption sanitization:
private func sanitizeMessageContent(_ content: String) -> String {
    var sanitized = content
    
    // Remove HTML tags
    sanitized = sanitized.replacingOccurrences(
        of: "<[^>]+>", 
        with: "", 
        options: .regularExpression
    )
    
    // Remove javascript: protocol
    sanitized = sanitized.replacingOccurrences(
        of: "javascript:", 
        with: "", 
        options: [.regularExpression, .caseInsensitive]
    )
    
    // Limit length as defense against overflow
    if sanitized.count > MAX_MESSAGE_LENGTH {
        sanitized = String(sanitized.prefix(MAX_MESSAGE_LENGTH))
    }
    
    return sanitized
}

// Use in decryption:
return DBMentorshipMessage(
    ...
    content: sanitizeMessageContent(decryptResult.decrypted_content ?? ""),
    ...
)
```

### References
- Defense in Depth principle
- CWE-116: Improper Encoding or Escaping of Output

---

## Finding 6: Incomplete Audit Logging (MEDIUM)

**Severity:** Medium
**Location:** `supabase/migrations/20260124150000_mentorship_security_fixes.sql:1022-1023`
**CWE:** CWE-778 (Insufficient Logging)

### Description
Message decryption audit logs capture only `auth.uid()` but miss critical forensic data like IP address, user agent, and rate limiting.

### Missing Data
```sql
-- CURRENT:
INSERT INTO mentorship_message_audit (message_id, accessor_id, action, reason)
VALUES (v_message_id, auth.uid(), 'decrypt_read', 'Batch decryption');

-- MISSING:
-- - IP address (for geolocation/suspicious access)
-- - User agent (device fingerprinting)
-- - Timestamp (already captured via DEFAULT)
-- - Rate limiting (allow unlimited decryption attempts)
```

### Impact
- Difficult to investigate security incidents
- Cannot detect brute-force decryption attempts
- Limited forensic capabilities

### Remediation
```sql
-- Add columns to audit table:
ALTER TABLE mentorship_message_audit
ADD COLUMN IF NOT EXISTS ip_address INET,
ADD COLUMN IF NOT EXISTS user_agent TEXT;

-- Update audit logging to capture request metadata:
INSERT INTO mentorship_message_audit (
    message_id, 
    accessor_id, 
    action, 
    reason,
    ip_address,
    user_agent
)
VALUES (
    v_message_id, 
    auth.uid(), 
    'decrypt_read', 
    'Batch decryption',
    inet_client_addr(),  -- PostgreSQL built-in
    current_setting('request.headers', true)::json->>'user-agent'
);

-- Add rate limiting on decryption:
CREATE OR REPLACE FUNCTION check_decrypt_rate_limit(p_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_decrypt_count INTEGER;
BEGIN
    -- Max 100 decryptions per minute per user
    SELECT COUNT(*) INTO v_decrypt_count
    FROM mentorship_message_audit
    WHERE accessor_id = p_user_id
    AND action = 'decrypt_read'
    AND accessed_at > NOW() - INTERVAL '1 minute';
    
    RETURN v_decrypt_count < 100;
END;
$$ LANGUAGE plpgsql;

-- Use in decrypt function:
IF NOT check_decrypt_rate_limit(auth.uid()) THEN
    RAISE EXCEPTION 'Decryption rate limit exceeded';
END IF;
```

### References
- OWASP Logging Cheat Sheet
- CWE-778: Insufficient Logging

---

## Finding 7: ReDoS Risk - Sequential Regex (LOW)

**Severity:** Low
**Location:** `supabase/migrations/20260124150000_mentorship_security_fixes.sql:320-334`
**CWE:** CWE-1333 (Inefficient Regular Expression Complexity)

### Description
Multiple sequential regex operations on the same input with patterns like `[^"]*` could cause performance issues with large inputs containing many quotes.

### Attack Vector
```sql
-- Input with 10,000 nested quotes:
SELECT sanitize_mentorship_message(repeat('"', 10000) || 'onclick="' || repeat('a', 10000));
-- Runs 7 sequential regex_replace operations
-- Time complexity: O(n * m) where n=input length, m=pattern count
```

### Impact
- Not catastrophic (PostgreSQL regex engine is efficient)
- Could slow down message processing on pathological inputs
- Unlikely to cause DOS but inefficient

### Remediation
```sql
-- Combine patterns where possible:
-- BEFORE (7 operations):
NEW.content := regexp_replace(NEW.content, '<[^>]*>', '', 'g');
NEW.content := regexp_replace(NEW.content, 'javascript:', '', 'gi');
NEW.content := regexp_replace(NEW.content, 'on\w+\s*=\s*"[^"]*"', '', 'gi');
NEW.content := regexp_replace(NEW.content, 'on\w+\s*=\s*''[^'']*''', '', 'gi');
NEW.content := regexp_replace(NEW.content, 'on\w+\s*=\s*[^\s>]*', '', 'gi');
NEW.content := regexp_replace(NEW.content, 'data:text/html', '', 'gi');
NEW.content := regexp_replace(NEW.content, 'vbscript:', '', 'gi');

-- AFTER (3 operations using alternation):
-- Strip HTML tags and event handlers
NEW.content := regexp_replace(NEW.content, '<[^>]*>|on\s*\w+\s*=\s*("[^"]*"|''[^'']*''|[^\s>]*)', '', 'gi');

-- Strip dangerous protocols
NEW.content := regexp_replace(NEW.content, '(javascript|vbscript|data):', '', 'gi');

-- Final trim and length check
NEW.content := trim(NEW.content);
```

### References
- CWE-1333: Inefficient Regular Expression Complexity
- OWASP Regular Expression Denial of Service (ReDoS)

---

## Summary of Findings

| Finding | Severity | CVSS Score | Status |
|---------|----------|------------|--------|
| 1. Event handler regex bypass | Critical | 7.5 | OPEN |
| 2. Introduction message unsanitized | Critical | 7.5 | OPEN |
| 3. Broken decryption authorization | Critical | 9.1 | OPEN |
| 4. Missing data: URI variants | High | 6.5 | OPEN |
| 5. No defense-in-depth on output | Medium | 4.3 | OPEN |
| 6. Incomplete audit logging | Medium | 3.1 | OPEN |
| 7. ReDoS risk (sequential regex) | Low | 2.0 | OPEN |

---

## Remediation Priority

**CRITICAL (Fix Immediately):**
1. **Finding 3:** Fix decryption authorization (blocks ALL messaging)
2. **Finding 1:** Fix event handler regex (XSS vulnerability)
3. **Finding 2:** Sanitize introduction messages (XSS vulnerability)

**HIGH (Fix This Sprint):**
4. **Finding 4:** Add missing data: URI variants

**MEDIUM (Fix Next Sprint):**
5. **Finding 5:** Add defense-in-depth sanitization
6. **Finding 6:** Enhance audit logging

**LOW (Backlog):**
7. **Finding 7:** Optimize regex patterns

---

## Secure Coding Recommendations

1. **Always sanitize at multiple layers:**
   - Client-side (basic validation)
   - API layer (business logic validation)
   - Database layer (defense-in-depth)
   - Output layer (encoding/escaping)

2. **Test sanitization with edge cases:**
   - Mixed case variations
   - Space/tab/newline variations
   - Unicode variations
   - Base64 encoding
   - URL encoding

3. **Use allowlists over denylists:**
   - Instead of blocking "javascript:", "data:", etc.
   - Allow only safe protocols: "http:", "https:"

4. **Regular security testing:**
   - Add XSS test cases to test suite
   - Fuzz test input validation
   - Penetration testing before launch

---

## Test Plan

Create these test cases in `MindFriendAppTests/MentorshipSecurityTests.swift`:

```swift
class MentorshipSecurityTests: XCTestCase {
    
    func testEventHandlerWithSpaceBlocked() async throws {
        let malicious = "Hello on click=\"alert(1)\" world"
        // Should be sanitized to: "Hello  world"
    }
    
    func testIntroductionMessageSanitized() async throws {
        let malicious = "<script>alert(1)</script>Hi mentor!"
        // Should be sanitized to: "Hi mentor!"
    }
    
    func testUserCanDecryptReceivedMessages() async throws {
        // User A sends to User B
        // User B MUST be able to decrypt and read
    }
    
    func testDataURIBlocked() async throws {
        let malicious = "data:text/javascript,alert(1)"
        // Should be sanitized
    }
}
```

---

**End of Audit Report**
