# MindFriend Codebase Audit Report

**Date:** 2026-01-14  
**Auditor:** Claude Opus 4.5  
**Scope:** Full codebase audit (iOS App, Edge Functions, Database, Documentation)

---

## Executive Summary

| Metric | Count |
|--------|-------|
| **Critical Issues** | 1 |
| **High Issues** | 4 |
| **Medium Issues** | 8 |
| **Low Issues** | 6 |
| **Overall Health Score** | **78/100** |

The MindFriend codebase demonstrates solid architecture and security practices. Row Level Security is comprehensive, authentication is properly validated across all Edge Functions, and crisis detection is implemented correctly. The main areas requiring attention are: **test coverage gaps**, **excessive logging in production**, and **hardcoded credentials in SupabaseClient.swift**.

---

## Critical Findings (Immediate Action Required)

### 🔴 C1: Hardcoded Supabase Anon Key in Source Code

**Location:** `apps/ios/MindFriendApp/Networking/SupabaseClient.swift:7`

**Problem:**
The Supabase anon key is hardcoded directly in the source code and will be committed to version control.

```swift
static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

**Impact:**
- The anon key, while designed for public use, is exposed in the git history forever
- If the project becomes public, attackers have immediate access
- Cannot rotate credentials without app update

**Fix:**
Move to xcconfig or Info.plist with environment-specific builds:

```swift
// SupabaseConfig.swift
enum SupabaseConfig {
    static let projectURL: URL = {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: urlString) else {
            fatalError("SUPABASE_URL not configured in Info.plist")
        }
        return url
    }()
    
    static let anonKey: String = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String else {
            fatalError("SUPABASE_ANON_KEY not configured in Info.plist")
        }
        return key
    }()
}
```

**Severity:** CRITICAL (credentials exposure)

---

## High Priority Findings

### 🟠 H1: Minimal Test Coverage

**Location:** `apps/ios/MindFriendAppTests/`

**Problem:**
The test suite contains only 5 test files with minimal actual tests:

| Test File | Actual Test Cases |
|-----------|------------------|
| `MindFriendAppTests.swift` | 1 (placeholder `XCTAssertTrue(true)`) |
| `ModelsTests.swift` | Decoding tests only |
| `BillingServiceTests.swift` | ~3 tests |
| `NotificationTests.swift` | ~2 tests |
| `APIEndpointTests.swift` | ~3 tests |

**Missing Critical Tests:**
- ❌ `SupabaseAuthServiceTests.swift` - Auth flow testing
- ❌ `ChatViewModelTests.swift` - Quota enforcement testing
- ❌ `MoodViewModelTests.swift` - Mood entry persistence
- ❌ `QuestViewModelTests.swift` - Streak calculation testing
- ❌ Edge Function integration tests

**Impact:**
- Regressions go undetected until production
- No confidence in refactoring
- Critical flows like quota enforcement are untested

**Required Tests:**
```swift
// ChatViewModelTests.swift
func testFreeUserQuota_ReachesLimit_ShowsPaywall() async
func testPremiumUserQuota_NoLimitEnforced() async
func testCrisisDetection_ShowsResources() async

// SupabaseAuthServiceTests.swift  
func testSignInWithApple_ValidToken_CreatesSession() async
func testSignOut_ClearsAllTokens() async
func testSessionExpiry_RefreshesAutomatically() async
```

**Severity:** HIGH (quality assurance)

---

### 🟠 H2: Excessive Debug Logging in Production Code

**Location:** Multiple files (92 instances found)

**Problem:**
Production code contains extensive `print()` statements that:
- Log sensitive information (access tokens, user IDs)
- Impact performance
- Clutter device logs
- May expose information to jailbroken device users

**Examples:**
```swift
// SupabaseDataService.swift:506
print("[SupabaseDataService] Using access token: \(refreshedToken.prefix(20))...")

// SupabaseAuthService.swift:61
print("[Auth] User signed in: \(session?.user.id.uuidString ?? "unknown")")
```

**Fix:**
Replace with proper logging using OSLog or a logging framework with log levels:

```swift
import OSLog

private let logger = Logger(subsystem: "app.mindfriend", category: "Auth")

// Replace print() with:
logger.debug("User signed in: \(session?.user.id.uuidString ?? "unknown", privacy: .private)")
```

Also configure to strip debug logs in release builds.

**Severity:** HIGH (security/performance)

---

### 🟠 H3: Missing DELETE Policy on User Badges

**Location:** `supabase/migrations/20260113000000_initial_schema.sql:303`

**Problem:**
The `user_badges` table only has a SELECT policy, meaning:
- Users cannot delete their own badges through the client
- No INSERT policy for client-side badge awarding

This may be intentional (badges awarded server-side only), but should be documented.

```sql
CREATE POLICY "Users can view own badges" ON user_badges
  FOR SELECT USING (auth.uid() = user_id);
-- No INSERT/UPDATE/DELETE policies
```

**Impact:**
If client needs to interact with badges, it will fail silently.

**Fix:**
Either add policies or document that badge operations are service-role only:

```sql
-- If badges should only be awarded server-side (recommended):
COMMENT ON TABLE user_badges IS 'Badge assignments are managed server-side only via service role';

-- Or if client needs to insert:
CREATE POLICY "Users can earn badges" ON user_badges
  FOR INSERT WITH CHECK (auth.uid() = user_id);
```

**Severity:** HIGH (data integrity)

---

### 🟠 H4: Edge Function Console.log Statements in Production

**Location:** Multiple Edge Functions (19 instances)

**Problem:**
Production Edge Functions contain `console.log()` statements that may leak information:

```typescript
// delete-account/index.ts:53
console.log(`Deleting account for user: ${userId}`);

// verify-purchase/index.ts:162
console.log("[DEV MODE] App Store credentials not configured...");
```

**Impact:**
- Logs are visible in Supabase dashboard
- May contain sensitive user information
- Performance overhead

**Fix:**
Use structured logging with log levels:

```typescript
// Create a logger utility
const log = {
  debug: (msg: string, data?: object) => {
    if (Deno.env.get("LOG_LEVEL") === "debug") {
      console.log(JSON.stringify({ level: "debug", msg, ...data }));
    }
  },
  error: (msg: string, data?: object) => {
    console.error(JSON.stringify({ level: "error", msg, ...data }));
  }
};
```

**Severity:** HIGH (security/observability)

---

## Medium Priority Findings

### 🟡 M1: Missing Weak Self in Potential Retain Cycle

**Location:** `apps/ios/MindFriendApp/Features/Chat/ChatView.swift:133`

**Problem:**
The `sendTask` stored property captures `self` in the Task closure:

```swift
sendTask = Task {
    defer { isSending = false }  // Captures self implicitly
    // ...
    messages.removeAll { $0.id == tempMessageId }  // Captures self
    messages.append(response.userMessage)  // Captures self
}
```

While Swift's Task doesn't create traditional retain cycles, storing the Task as a property and capturing self can lead to unexpected behavior if the view is dismissed.

**Impact:** Potential memory issues if view is rapidly dismissed/recreated.

**Fix:**
```swift
sendTask = Task { [weak appState, weak container] in
    guard let appState = appState, let container = container else { return }
    // Use captured references
}
```

**Severity:** MEDIUM (memory management)

---

### 🟡 M2: App Store Validation Not Fully Implemented

**Location:** `supabase/functions/verify-purchase/index.ts:166-169`

**Problem:**
The verify-purchase function has a TODO for full App Store Server API validation:

```typescript
// TODO: Implement full App Store Server API validation when credentials configured
// For now, trust the client-side StoreKit 2 validation in dev/sandbox
```

While the function correctly rejects requests in production without credentials, the actual receipt validation logic is not implemented.

**Impact:**
- Cannot validate purchases in production without manual credential setup
- No JWS signature verification
- No receipt replay attack protection

**Fix:**
Implement full App Store Server API integration using the SignedDataVerifier pattern.

**Severity:** MEDIUM (payment security)

---

### 🟡 M3: delete-account Function Has Redundant Query

**Location:** `supabase/functions/delete-account/index.ts:63-70`

**Problem:**
There's a redundant/broken query attempt:

```typescript
const { error: messagesError } = await adminClient
  .from("messages")
  .delete()
  .eq(
    "conversation_id",
    adminClient.from("conversations").select("id").eq("user_id", userId),
  );
```

This subquery syntax is incorrect for Supabase. The function then correctly implements the deletion using a separate query.

**Impact:** Dead code, potential confusion.

**Fix:**
Remove the broken query block (lines 63-71).

**Severity:** MEDIUM (code quality)

---

### 🟡 M4: Missing Rate Limit on Voice Token Generation

**Location:** `supabase/functions/voice-token/index.ts`

**Problem:**
The voice-token endpoint checks quota but doesn't implement rate limiting. A malicious user could rapidly request tokens to exhaust xAI API quota.

**Impact:** Potential API abuse, cost overruns.

**Fix:**
Add rate limiting similar to the chat function:

```typescript
const rateLimitResult = await checkRateLimit(supabase, user.id, "voice-token");
if (!rateLimitResult.allowed) {
  return errorResponse(corsHeaders, "Too many requests", "RATE_LIMITED", 429);
}
```

**Severity:** MEDIUM (abuse prevention)

---

### 🟡 M5: Inconsistent Error Response Formats

**Location:** Various Edge Functions

**Problem:**
Error responses use inconsistent formats across functions:

```typescript
// chat/index.ts
{ error: "Missing authorization" }

// voice-token/index.ts  
{ error: "message", code: "CODE" }

// send-notification/index.ts
{ error: "message", success: false }
```

**Impact:** Client must handle multiple error formats.

**Fix:**
Standardize on a single error format:

```typescript
interface ErrorResponse {
  error: string;
  code: string;
  message?: string;
  details?: object;
}
```

**Severity:** MEDIUM (developer experience)

---

### 🟡 M6: No Pagination on Exercise/Quest Fetches

**Location:** `apps/ios/MindFriendApp/Features/Exercises/ExerciseLibraryView.swift`

**Problem:**
Exercise and quest fetches don't implement pagination:

```swift
// Fetches all exercises at once
let exercises = try await container.supabaseDataService.fetchExercises()
```

With 45 exercises (and growing), this isn't critical but could become an issue.

**Impact:** Increased load times as content grows.

**Fix:**
Implement cursor-based pagination or limit initial fetch.

**Severity:** MEDIUM (performance)

---

### 🟡 M7: Missing Index on notification_history.metadata

**Location:** `supabase/functions/send-notification/index.ts:70`

**Problem:**
Rate limiting queries filter on `metadata->>senderId`:

```typescript
query = query.filter("metadata->>senderId", "eq", userId);
```

Without a GIN index on the metadata column, this query will perform a full table scan as notification_history grows.

**Impact:** Slow rate limit checks at scale.

**Fix:**
```sql
CREATE INDEX idx_notification_history_sender 
ON notification_history USING GIN (metadata);
```

**Severity:** MEDIUM (scalability)

---

### 🟡 M8: Prompt Injection Mitigation Could Be Stronger

**Location:** `supabase/functions/chat/index.ts:498-516`

**Problem:**
The `sanitizeForPrompt` function is defined but only used for memory extraction, not for the main chat flow. While the main flow has length limits, it doesn't sanitize role impersonation attempts.

**Current sanitization (only for memory extraction):**
```typescript
.replace(/^(system|assistant|user):/gi, "[redacted]:")
.replace(/\[INST\]/gi, "[redacted]")
```

**Impact:** Main chat messages could contain prompt injection patterns.

**Fix:**
Apply sanitization to all user messages before sending to AI:

```typescript
// In the main chat flow before building messageHistory:
const sanitizedContent = sanitizeForPrompt(trimmedContent);
```

**Severity:** MEDIUM (security)

---

## Low Priority Findings

### 🟢 L1: Deprecated Column in crisis_events

**Location:** `supabase/migrations/20260114062000_chat_security_hardening.sql:8-9`

**Problem:**
The `trigger_content` column is marked as deprecated but not removed:

```sql
COMMENT ON COLUMN crisis_events.trigger_content IS 'DEPRECATED: No longer populated for PII protection';
```

**Impact:** Schema clutter, potential confusion.

**Fix:**
In a future migration, drop the column:
```sql
ALTER TABLE crisis_events DROP COLUMN IF EXISTS trigger_content;
```

**Severity:** LOW (cleanup)

---

### 🟢 L2: Magic Numbers in Code

**Location:** Various files

**Problem:**
Several magic numbers appear in the code:

```swift
// ChatView.swift:17
private let quotaWarningThreshold = 3

// SupabaseAuthService.swift:389
"daily_ai_quota": AnyEncodable(10),  // Should be constant
```

```typescript
// chat/index.ts:15
const MAX_MESSAGE_LENGTH = 4000;  // Good - but others aren't constants
```

**Impact:** Harder to maintain, values scattered across codebase.

**Fix:**
Centralize constants in a configuration file.

**Severity:** LOW (maintainability)

---

### 🟢 L3: Missing README in Feature Directories

**Location:** `apps/ios/MindFriendApp/Features/*/`

**Problem:**
Feature directories lack README files explaining their purpose and architecture.

**Impact:** Onboarding new developers is slower.

**Fix:**
Add brief README.md to each feature directory.

**Severity:** LOW (documentation)

---

### 🟢 L4: Unused sanitizeForPrompt Function in Main Flow

**Location:** `supabase/functions/chat/index.ts:498`

**Problem:**
The `sanitizeForPrompt` function is defined but only used in the memory extraction path, not the main chat path where it would also be beneficial.

**Impact:** Inconsistent security application.

**Severity:** LOW (covered in M8 with more detail)

---

### 🟢 L5: No Keychain Usage Visible in iOS Code

**Location:** Entire iOS codebase

**Problem:**
Despite the spec mentioning KeychainManager, no keychain usage is visible in the codebase. The Supabase SDK handles session storage internally, but it's not clear if it uses Keychain.

**Impact:** Should verify Supabase SDK's storage mechanism.

**Fix:**
Verify Supabase Swift SDK uses Keychain for session storage, or implement explicit Keychain storage for sensitive data.

**Severity:** LOW (needs verification)

---

### 🟢 L6: Missing Content-Type Validation on Request Bodies

**Location:** Various Edge Functions

**Problem:**
Edge Functions parse JSON without validating Content-Type header:

```typescript
const body: NotificationRequest = await req.json();
```

**Impact:** Potential for content-type confusion attacks.

**Fix:**
```typescript
const contentType = req.headers.get("Content-Type");
if (!contentType?.includes("application/json")) {
  return new Response(JSON.stringify({ error: "Content-Type must be application/json" }), {
    status: 415, headers
  });
}
```

**Severity:** LOW (defense in depth)

---

## Security Audit Summary

### ✅ Security Controls Implemented

| Control | Status | Notes |
|---------|--------|-------|
| Row Level Security | ✅ Complete | All tables have RLS with appropriate policies |
| JWT Validation | ✅ Complete | All Edge Functions validate auth header |
| Rate Limiting | ✅ Implemented | Database-backed sliding window rate limiting |
| Crisis Detection | ✅ Implemented | Keyword detection with PII protection |
| Prompt Injection Prevention | ⚠️ Partial | Implemented for memory extraction only |
| Quota Enforcement | ✅ Atomic | Uses DB function to prevent race conditions |
| CORS | ✅ Configured | Dynamic origin handling |
| Input Validation | ✅ Good | UUID regex, length limits, type checks |
| Constant-Time Comparison | ✅ Implemented | For service role key comparison |

### ⚠️ Security Concerns

| Issue | Severity | Status |
|-------|----------|--------|
| Hardcoded credentials | CRITICAL | Needs immediate fix |
| Excessive logging | HIGH | PII in logs |
| No receipt validation | MEDIUM | TODO in production |
| Missing rate limit on voice | MEDIUM | Abuse potential |

---

## Performance Audit Summary

### ✅ Good Practices Found

- LazyVStack used in ChatView for message list
- Pagination indices on database tables
- Async/await properly used throughout
- Task cancellation handled in ChatView

### ⚠️ Performance Concerns

| Issue | Impact | Priority |
|-------|--------|----------|
| No GIN index on notification metadata | Slow rate limit queries at scale | MEDIUM |
| No pagination on exercise fetch | Growing load times | LOW |
| Many print() calls | Minor overhead | MEDIUM |

---

## Test Coverage Summary

### Current Coverage

| Area | Files | Coverage |
|------|-------|----------|
| iOS Unit Tests | 5 | ~5% (placeholder) |
| Edge Function Tests | 5 | ~40% (basic tests) |
| Integration Tests | 0 | 0% |
| UI Tests | 2 | Placeholder only |

### Required Test Cases (Priority Order)

1. **Authentication Flow Tests**
   - Sign in with Apple token validation
   - Session refresh on expiry
   - Sign out clears all state

2. **Quota Enforcement Tests**
   - Free user reaches limit → paywall shown
   - Premium user bypasses limit
   - Quota resets at midnight

3. **Crisis Detection Tests**
   - Keyword detection triggers response
   - Crisis event logged without PII
   - Resources shown to user

4. **Billing Tests**
   - Purchase verification flow
   - Family plan seat management
   - Subscription status checks

---

## Recommendations

### Immediate (This Week)

1. **[CRITICAL]** Move Supabase credentials to xcconfig/Info.plist
2. **[HIGH]** Replace print() with OSLog
3. **[HIGH]** Add SupabaseAuthServiceTests.swift
4. **[HIGH]** Add ChatViewModelTests.swift with quota tests

### Short-term (This Month)

5. Implement full App Store receipt validation
6. Add rate limiting to voice-token endpoint
7. Standardize Edge Function error responses
8. Add GIN index on notification_history.metadata
9. Apply prompt sanitization to main chat flow

### Long-term (Backlog)

10. Add pagination to exercise/quest fetches
11. Drop deprecated trigger_content column
12. Add README files to feature directories
13. Centralize magic numbers into constants
14. Implement structured logging in Edge Functions

---

## Files Audited

### iOS (49 Swift files)
- `App/` - 4 files
- `Core/` - 6 files  
- `Features/` - 34 files
- `Networking/` - 5 files

### Edge Functions (28 TypeScript files)
- 15 function directories
- 8 shared utilities
- 5 test files

### Database (17 SQL migrations)
- Initial schema + 16 incremental migrations
- All tables have RLS enabled

---

## Appendix A: RLS Policy Coverage

| Table | SELECT | INSERT | UPDATE | DELETE |
|-------|--------|--------|--------|--------|
| profiles | ✅ | ✅ | ✅ | ❌ (cascade) |
| user_settings | ✅ | ✅ | ✅ | ❌ |
| moods | ✅ | ✅ | ✅ | ❌ |
| conversations | ✅ | ✅ | ✅ | ✅ |
| messages | ✅ | ✅ | ❌ | ❌ |
| circles | ✅ | ✅ | ✅ | ❌ |
| circle_members | ✅ | ✅ | ❌ | ✅ |
| user_badges | ✅ | ❌ | ❌ | ❌ |
| subscriptions | ✅ | ❌ | ❌ | ❌ |
| memory_fragments | ✅ | ❌ (service only) | ❌ | ✅ |
| crisis_events | ✅ | ❌ (service only) | ❌ | ❌ |
| push_tokens | ✅ (ALL policy) | ✅ | ✅ | ✅ |

---

## Appendix B: Edge Function Auth Validation

| Function | Auth Required | Rate Limited | Validated |
|----------|---------------|--------------|-----------|
| chat | ✅ | ✅ | ✅ |
| verify-purchase | ✅ | ❌ | ✅ |
| send-notification | Optional | ✅ | ✅ |
| voice-token | ✅ | ❌ | ⚠️ Missing |
| delete-account | ✅ | ❌ | ✅ |
| assign-quest | ✅/Cron | ❌ | ✅ |
| accept-family-invite | ✅ | ❌ | ✅ |
| send-family-invite | ✅ | ❌ | ✅ |

---

*Audit completed 2026-01-14. Findings logged to docs/PROGRESS.md.*
