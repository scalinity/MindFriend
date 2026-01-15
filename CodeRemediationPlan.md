# Code Remediation Plan

## Executive Summary

### Goal
Stabilize **MindFriend** (iOS + Supabase) by fixing critical security/compliance gaps, reconciling schema mismatches, and restoring end-to-end feature correctness (quests, circles, purchases, quota, notifications, settings).

### Key Assumptions
- **Canonical backend schema is the repo’s Supabase migrations** in `supabase/migrations/` (not the iOS client’s legacy table names).
- The app is **pre-launch or early-launch** (schema changes are acceptable). If you already have production data/clients, see the **Rollback Plan** and migration notes for compatibility options.
- Supabase Edge Functions are the **only backend compute** required for purchases, chat, and account deletion (the `apps/api` service appears unused for the current iOS app).

### Severity Breakdown
- **CRITICAL**: 3
- **HIGH**: 7
- **MEDIUM**: 4
- **LOW**: 1

### Effort (Complexity)
Overall: **Large** (multi-file iOS refactor + multiple DB migrations + purchase verification hardening).

---

## Issues Index

| ID | Severity | Category | File(s) | Brief Description |
|----|----------|----------|---------|-------------------|
| 001 | CRITICAL | Security/Revenue | `supabase/functions/verify-purchase/index.ts`, `apps/ios/.../BillingService.swift` | Purchase verification is effectively bypassed; any client can unlock premium. |
| 002 | CRITICAL | Compliance/Trust | `apps/ios/AppStoreMetadata.yaml` | Claims “end-to-end encryption” while chats are stored server-side in plaintext. |
| 003 | CRITICAL | Data/Runtime | `apps/ios/.../SupabaseClient.swift`, `SupabaseAuthService.swift`, `supabase/migrations/*.sql` | iOS table/column assumptions don’t match migrations (profiles/settings/stats), causing fetch/insert failures. |
| 004 | HIGH | Privacy/Data Deletion | `supabase/functions/delete-account/index.ts` | References non-existent tables + invalid deletion query; account deletion can fail or be incomplete. |
| 005 | HIGH | Backend Feature Bug | `apps/ios/.../SupabaseDataService.swift`, `supabase/migrations/*.sql` | Daily quest assignment expects missing RPC + wrong table name (`user_quests` vs `quests`). |
| 006 | HIGH | Social Feature Bug | `apps/ios/.../SupabaseDataService.swift`, `supabase/migrations/*circle*.sql` | Circles join/create flows break under current RLS + wrong table name (`circle_checkins` vs `circle_posts`). |
| 007 | HIGH | Monetization/UX Bug | `apps/ios/.../ChatView.swift`, `Models.swift`, `supabase/functions/chat/index.ts` | Premium/unlimited quota (-1) mishandled; quota banner/paywall can trigger incorrectly. |
| 008 | HIGH | iOS Runtime/Correctness | `apps/ios/.../BillingService.swift` | Entitlements refresh decodes into wrong model; StoreKit listener task type is inconsistent. |
| 009 | HIGH | RLS/Correctness | `apps/ios/.../SupabaseAuthService.swift`, `supabase/migrations/*.sql` | Handle availability check can’t work with current RLS (select-own-profile only). |
| 010 | HIGH | Push Notifications | `apps/ios/.../NotificationManager.swift`, `MindFriendApp.swift`, `AppDelegate.swift` | NotificationManager never receives DependencyContainer; device token registration never runs. |
| 011 | MEDIUM | UX/Consistency | `apps/ios/.../ProfileView.swift` | Settings screens don’t persist changes to backend or update AppState. |
| 012 | MEDIUM | Robustness | `apps/ios/.../SupabaseDataService.swift` | Invite code collisions not handled; circles join/create return inaccurate counts. |
| 013 | MEDIUM | Security | `supabase/functions/*/index.ts`, `_shared/cors.ts` | Some Edge Functions use permissive CORS (`*`) rather than shared allowlist logic. |
| 014 | MEDIUM | DevEx/CI | `apps/ios/MindFriendAppTests/*` | Unit tests are stale and likely fail to compile (old APIEndpoint types, outdated enums). |
| 015 | LOW | Repo Hygiene | `apps/api/.env`, `apps/api/node_modules`, `apps/api/dist` | Committed env/artifacts increase risk and repo bloat; secrets hygiene needs tightening. |

---

## Detailed Fixes

### Issue #001: Purchase verification is bypassed (premium unlock can be faked)
**Severity**: CRITICAL  
**Category**: Security/Revenue  
**Location**: `supabase/functions/verify-purchase/index.ts` (lines 66–134) cite(local)

#### Current State
If Apple keys aren’t configured, the function **falls back to mock validation** and still upgrades the user to premium.

**Before (excerpt):**
```ts
// supabase/functions/verify-purchase/index.ts (lines 66–116)
if (!issuerId || !keyId || !privateKey) {
  console.warn("App Store Server API keys not configured, using mock validation")
  isValid = true
  subscriptionStatus = "active"
  expiresDate = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
} else {
  console.log("App Store verification not implemented yet")
  isValid = true
  subscriptionStatus = "active"
}
...
await supabaseAdmin.from("profiles").update({
  subscription_tier: "premium",
  daily_ai_quota: -1
}).eq("id", user.id)
```
(See full file for details.)

#### Root Cause
- Verification is intentionally stubbed but **not gated** behind a build-time or env flag.
- The server trusts client-provided `originalTransactionId`/`productId` with no cryptographic proof.

#### Solution
- Change the contract: iOS must send **StoreKit 2 signed transaction JWS** (`Transaction.signedData`).
- Verify the JWS server-side using Apple’s **StoreKit JWS keys**.
- Only then update `subscriptions` and set `profiles.subscription_tier = 'premium'`.
- Remove the automatic `daily_ai_quota = -1` write (treat unlimited quota as a function of tier in the app).

#### Implementation Details

##### A) iOS: send signed transaction
**Location**: `apps/ios/MindFriendApp/Networking/Services/BillingService.swift` (lines 117–143)

**Before:**
```swift
let request = VerifyPurchaseRequest(
    originalTransactionId: transaction.originalID,
    productId: transaction.productID,
    environment: transaction.environment.rawValue
)

let response: VerifyPurchaseResponse = try await supabase.functions.invoke(
    "verify-purchase",
    options: .init(body: request)
)
```

**After:**
```swift
struct VerifyPurchaseRequest: Encodable {
    let signedTransaction: String
    let environment: String   // "sandbox" | "production"
}

let request = VerifyPurchaseRequest(
    signedTransaction: transaction.signedData, // StoreKit2 JWS
    environment: transaction.environment == .sandbox ? "sandbox" : "production"
)

let response: VerifyPurchaseResponse = try await supabase.functions.invoke(
    "verify-purchase",
    options: .init(body: request)
)
```

##### B) Edge Function: verify JWS instead of trusting IDs
Create/replace implementation in `supabase/functions/verify-purchase/index.ts`.

**After (full replacement sketch, Deno + npm jose):**
```ts
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"
import { createRemoteJWKSet, jwtVerify } from "npm:jose@5.2.4"
import { getCorsHeaders } from "../_shared/cors.ts"

type Env = "sandbox" | "production"

interface VerifyPurchaseRequest {
  signedTransaction: string
  environment?: Env
}

const STOREKIT_JWKS = {
  production: "https://api.storekit.itunes.apple.com/inApps/v1/jwsKeys",
  sandbox: "https://api.storekit-sandbox.itunes.apple.com/inApps/v1/jwsKeys",
} as const

const ALLOWED_PRODUCT_IDS = new Set([
  "mindfriend_premium_monthly",
  "mindfriend_premium_yearly",
])

Deno.serve(async (req) => {
  const origin = req.headers.get("origin") ?? ""
  const cors = getCorsHeaders(origin)

  if (req.method === "OPTIONS") return new Response("ok", { headers: cors })
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers: cors })

  const authHeader = req.headers.get("Authorization")
  if (!authHeader) return new Response(JSON.stringify({ error: "Missing Authorization header" }), { status: 401, headers: cors })

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } })

  // Authenticate caller
  const token = authHeader.replace("Bearer ", "")
  const { data: userData, error: userError } = await supabaseAdmin.auth.getUser(token)
  if (userError || !userData?.user) {
    return new Response(JSON.stringify({ error: "Invalid token" }), { status: 401, headers: cors })
  }
  const user = userData.user

  let body: VerifyPurchaseRequest
  try {
    body = await req.json()
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), { status: 400, headers: cors })
  }

  const env: Env = body.environment === "sandbox" ? "sandbox" : "production"
  if (!body.signedTransaction) {
    return new Response(JSON.stringify({ error: "Missing signedTransaction" }), { status: 400, headers: cors })
  }

  // Verify transaction JWS using Apple's StoreKit JWKS
  const jwks = createRemoteJWKSet(new URL(STOREKIT_JWKS[env]))
  let payload: any
  try {
    const verified = await jwtVerify(body.signedTransaction, jwks, {
      // Optional: validate audience/issuer if you enforce them
      // issuer: "...",
      // audience: "...",
    })
    payload = verified.payload
  } catch (e) {
    return new Response(JSON.stringify({ error: "Invalid signed transaction", details: String(e) }), { status: 400, headers: cors })
  }

  const productId = payload?.productId as string | undefined
  const originalTransactionId = payload?.originalTransactionId as string | undefined
  const expiresDateMs = payload?.expiresDate as number | undefined // Apple often uses ms since epoch

  if (!productId || !originalTransactionId) {
    return new Response(JSON.stringify({ error: "Missing required transaction fields" }), { status: 400, headers: cors })
  }
  if (!ALLOWED_PRODUCT_IDS.has(productId)) {
    return new Response(JSON.stringify({ error: "Unknown productId" }), { status: 400, headers: cors })
  }

  const currentPeriodEnd = expiresDateMs ? new Date(expiresDateMs).toISOString() : null

  // Upsert subscription row
  const { error: subError } = await supabaseAdmin
    .from("subscriptions")
    .upsert({
      user_id: user.id,
      provider: "app_store",
      provider_customer_id: originalTransactionId,
      provider_subscription_id: String(payload?.transactionId ?? ""),
      product_id: productId,
      status: "active",
      current_period_end: currentPeriodEnd,
      cancel_at_period_end: false,
    }, { onConflict: "user_id,provider" })

  if (subError) {
    return new Response(JSON.stringify({ error: "Failed to upsert subscription", details: subError.message }), { status: 500, headers: cors })
  }

  // Update entitlements (tier only; quota handled by tier client-side)
  const { error: profError } = await supabaseAdmin
    .from("profiles")
    .update({ subscription_tier: "premium" })
    .eq("id", user.id)

  if (profError) {
    return new Response(JSON.stringify({ error: "Failed to update profile", details: profError.message }), { status: 500, headers: cors })
  }

  return new Response(JSON.stringify({ valid: true, status: "active", tier: "premium" }), { headers: cors })
})
```

> Notes:
> - The exact payload keys can vary; confirm against Apple’s StoreKit transaction JWS schema and adjust `expiresDate` parsing accordingly.
> - If you need renewal/cancel support, add App Store Server Notifications v2 handling later.

#### Testing Requirements
- [ ] **Edge unit test**: invalid/missing `signedTransaction` → 400
- [ ] **Edge unit test**: invalid signature → 400
- [ ] **Edge integration**: valid sandbox purchase → subscription row upserted, profile tier set to premium
- [ ] **iOS integration**: purchase flow triggers verify-purchase call with `signedData`

#### Acceptance Criteria
- [ ] Premium cannot be unlocked without a valid Apple-signed transaction.
- [ ] Subscriptions are recorded in `subscriptions` with expected fields.
- [ ] `profiles.subscription_tier` updates correctly and is reflected in the app.

---

### Issue #002: App Store copy claims end-to-end encryption (not true)
**Severity**: CRITICAL  
**Category**: Compliance/Trust  
**Location**: `apps/ios/AppStoreMetadata.yaml` (line 34)

#### Current State
Metadata claims “Your data is protected with end-to-end encryption”.

**Before:**
```yaml
# apps/ios/AppStoreMetadata.yaml (line 34)
- "Your data is protected with end-to-end encryption"
```

#### Root Cause
- Chat messages are stored in `messages.content` server-side and processed by an external model provider via Edge Functions. This is not E2E.

#### Solution
- Update App Store copy to a truthful statement:
  - “Encrypted in transit and at rest” (true for TLS + managed DB encryption).
  - “You can delete chats and your account at any time” (once Issue #004 is fixed).
- If you *want* stronger privacy, add a “Privacy Mode: don’t store chat history” option (future enhancement; requires chat function changes).

**After (example):**
```yaml
- "Your data is encrypted in transit and at rest"
- "You can delete your data at any time from Settings"
```

#### Testing Requirements
- [ ] Manual: App Store metadata review for accuracy.
- [ ] Manual: Verify the in-app privacy text matches actual behavior.

#### Acceptance Criteria
- [ ] No claims of E2E encryption unless implemented end-to-end.
- [ ] Privacy claims match storage + processing realities.

---

### Issue #003: Profiles/settings/stats schema mismatch between iOS and migrations
**Severity**: CRITICAL  
**Category**: Data/Runtime  
**Location**:
- `apps/ios/MindFriendApp/Networking/SupabaseClient.swift` (lines 21–101)  
- `apps/ios/MindFriendApp/Networking/Services/SupabaseAuthService.swift` (lines 339–484)  
- `supabase/migrations/20260113000000_initial_schema.sql` (profiles + user_settings + user_stats)

#### Current State
iOS expects settings/stats columns to live on `profiles`, and it references non-existent tables (`devices`, `user_quests`, `circle_checkins`).

**Before (tables):**
```swift
// SupabaseClient.swift (lines 21–37)
enum Tables {
    static let profiles = "profiles"
    static let devices = "devices"
    ...
    static let userQuests = "user_quests"
    ...
    static let circleCheckins = "circle_checkins"
}
```

**Before (profile model expects many columns on profiles):**
```swift
// SupabaseClient.swift (lines 46–101)
struct DBProfile: Codable {
  ...
  // Settings + Stats are assumed to be in profiles
  var dailyQuestTimeLocal: String
  var remindersEnabled: Bool
  ...
  var currentStreakDays: Int
  var totalQuestsCompleted: Int
  ...
}
```

But the migration defines:
- `profiles`: identity + subscription quota fields
- `user_settings`: settings fields
- `user_stats`: stats fields

#### Root Cause
- iOS client was authored for an older/denormalized schema.
- Supabase trigger `handle_new_user()` creates separate `user_settings` and `user_stats` rows, so client-side “create default profile” fallback is both unnecessary and dangerous.

#### Solution
- Treat `supabase/migrations` as source of truth.
- Update iOS DB models and fetch logic to **compose** `UserProfile` from:
  1) `profiles` row
  2) `user_settings` row
  3) `user_stats` row
- Remove the broad catch-all fallback insertion in `fetchProfile()`; only create missing rows if truly absent.

#### Implementation Details

##### A) Update table names in iOS
**Location**: `apps/ios/MindFriendApp/Networking/SupabaseClient.swift`

**After:**
```swift
enum Tables {
    static let profiles = "profiles"
    static let userSettings = "user_settings"
    static let userStats = "user_stats"

    static let moods = "moods"
    static let questTemplates = "quest_templates"
    static let quests = "quests"

    static let exercises = "exercises"
    static let exerciseSessions = "exercise_sessions"

    static let conversations = "conversations"
    static let messages = "messages"

    static let circles = "circles"
    static let circleMembers = "circle_members"
    static let circlePosts = "circle_posts"

    static let badges = "badges"
    static let userBadges = "user_badges"

    static let pushTokens = "push_tokens"
}
```

##### B) Replace `DBProfile` with schema-correct rows
Create new structs (new file recommended):  
`apps/ios/MindFriendApp/Networking/DBModels.swift`

```swift
import Foundation

struct DBProfileRow: Codable {
    let id: UUID
    let handle: String
    let displayName: String
    let email: String?
    let timezone: String
    let subscriptionTier: String
    let dailyAiQuota: Int
    let dailyAiUsed: Int
    let quotaResetAt: Date
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, handle, email, timezone
        case displayName = "display_name"
        case subscriptionTier = "subscription_tier"
        case dailyAiQuota = "daily_ai_quota"
        case dailyAiUsed = "daily_ai_used"
        case quotaResetAt = "quota_reset_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DBUserSettingsRow: Codable {
    let userId: UUID
    let dailyQuestTimeLocal: String
    let quietHoursStartLocal: String?
    let quietHoursEndLocal: String?
    let remindersEnabled: Bool
    let nudgeAfterDaysInactive: Int
    let shareMoodInCircles: Bool
    let aiTone: String
    let privacyMode: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case dailyQuestTimeLocal = "daily_quest_time_local"
        case quietHoursStartLocal = "quiet_hours_start_local"
        case quietHoursEndLocal = "quiet_hours_end_local"
        case remindersEnabled = "reminders_enabled"
        case nudgeAfterDaysInactive = "nudge_after_days_inactive"
        case shareMoodInCircles = "share_mood_in_circles"
        case aiTone = "ai_tone"
        case privacyMode = "privacy_mode"
    }
}

struct DBUserStatsRow: Codable {
    let userId: UUID
    let currentStreakDays: Int
    let longestStreakDays: Int
    let totalQuestsCompleted: Int
    let totalExercisesCompleted: Int
    let lastQuestDate: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case currentStreakDays = "current_streak_days"
        case longestStreakDays = "longest_streak_days"
        case totalQuestsCompleted = "total_quests_completed"
        case totalExercisesCompleted = "total_exercises_completed"
        case lastQuestDate = "last_quest_date"
    }
}
```

##### C) Rework `fetchProfile()` to compose user model
**Location**: `SupabaseAuthService.fetchProfile()` (lines 339–402)

**After:**
```swift
func fetchProfile() async throws -> UserProfile {
    guard let userId = userId else { throw AuthError.userNotFound }

    let profile: DBProfileRow = try await supabase
        .from(Tables.profiles)
        .select()
        .eq("id", value: userId)
        .single()
        .execute()
        .value

    let settings: DBUserSettingsRow = try await supabase
        .from(Tables.userSettings)
        .select()
        .eq("user_id", value: userId)
        .single()
        .execute()
        .value

    let stats: DBUserStatsRow = try await supabase
        .from(Tables.userStats)
        .select()
        .eq("user_id", value: userId)
        .single()
        .execute()
        .value

    return UserProfile(
        id: profile.id.uuidString,
        handle: profile.handle,
        displayName: profile.displayName,
        email: profile.email,
        timezone: profile.timezone,
        createdAt: profile.createdAt,
        settings: UserSettings(
            dailyQuestTimeLocal: settings.dailyQuestTimeLocal,
            quietHoursStartLocal: settings.quietHoursStartLocal,
            quietHoursEndLocal: settings.quietHoursEndLocal,
            remindersEnabled: settings.remindersEnabled,
            nudgeAfterDaysInactive: settings.nudgeAfterDaysInactive,
            shareMoodInCircles: settings.shareMoodInCircles,
            aiTone: AITone(rawValue: settings.aiTone) ?? .friendly,
            privacyMode: PrivacyMode(rawValue: settings.privacyMode) ?? .standard
        ),
        stats: UserStats(
            currentStreakDays: stats.currentStreakDays,
            longestStreakDays: stats.longestStreakDays,
            totalQuestsCompleted: stats.totalQuestsCompleted,
            totalExercisesCompleted: stats.totalExercisesCompleted
        ),
        entitlements: Entitlements(
            tier: profile.subscriptionTier == "premium" ? .premium : .free,
            dailyAiQuota: profile.dailyAiQuota,
            dailyAiUsed: profile.dailyAiUsed
        ),
        badges: []
    )
}
```

##### D) Remove unsafe “create profile with defaults” fallback
- Keep fallback only if `profiles` row is genuinely missing (shouldn’t happen with trigger).
- If you keep a fallback for local dev, insert into **profiles + user_settings + user_stats** in a single transaction via an Edge Function using service role.

#### Testing Requirements
- [ ] Unit test: composing `UserProfile` from DB rows
- [ ] Integration: sign-up → trigger creates rows → `fetchProfile()` succeeds with no fallback
- [ ] Integration: sign-in from a fresh device works

#### Acceptance Criteria
- [ ] App can sign in and load Home/Profile without schema decode errors.
- [ ] Settings/stats are sourced from correct tables.
- [ ] No client attempts to insert schema-invalid columns into `profiles`.

---

### Issue #004: delete-account Edge Function is incorrect/outdated
**Severity**: HIGH  
**Category**: Privacy/Data Deletion  
**Location**: `supabase/functions/delete-account/index.ts` (lines 45–178)

#### Current State
- Deletes from tables that don’t exist in migrations (`circle_checkins`, `user_quests`, `devices`).
- Contains an invalid delete attempt (query builder inside `.eq()`), then re-implements deletion via a second pass.

**Before (invalid attempt):**
```ts
// delete-account/index.ts (lines 66–72)
const { error: messagesError } = await supabaseAdmin
  .from("messages")
  .delete()
  .eq("conversation_id", adminClient.from("conversations") ... )
```
…and uses legacy tables later.

#### Root Cause
- Schema drift between function and migrations.
- Over-deletion logic duplicates what DB foreign keys already provide (`ON DELETE CASCADE`).

#### Solution
- Use **auth admin delete** as the primary operation.
- Rely on DB `ON DELETE CASCADE` for dependent rows.
- Explicitly delete rows from any tables that lack FKs (e.g., `rate_limits`).

#### Implementation Details

**After (simplified delete-account):**
```ts
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"
import { getCorsHeaders } from "../_shared/cors.ts"

Deno.serve(async (req) => {
  const origin = req.headers.get("origin") ?? ""
  const cors = getCorsHeaders(origin)

  if (req.method === "OPTIONS") return new Response("ok", { headers: cors })
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers: cors })

  const authHeader = req.headers.get("Authorization")
  if (!authHeader) return new Response(JSON.stringify({ error: "Missing Authorization header" }), { status: 401, headers: cors })

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } })

  const token = authHeader.replace("Bearer ", "")
  const { data: userData, error: userError } = await supabaseAdmin.auth.getUser(token)
  if (userError || !userData?.user) {
    return new Response(JSON.stringify({ error: "Invalid token" }), { status: 401, headers: cors })
  }
  const user = userData.user

  // Cleanup non-FK tables (if any)
  await supabaseAdmin.from("rate_limits").delete().eq("user_id", user.id)

  const { error: delError } = await supabaseAdmin.auth.admin.deleteUser(user.id)
  if (delError) {
    return new Response(JSON.stringify({ error: "Failed to delete auth user", details: delError.message }), { status: 500, headers: cors })
  }

  return new Response(JSON.stringify({ success: true, message: "Account deleted successfully" }), { headers: cors })
})
```

#### Testing Requirements
- [ ] Integration: create user, insert sample rows (moods, quests, messages, circle_members), call delete-account → verify rows gone.
- [ ] Manual: in-app “Delete Account” flows to signed-out state and cannot sign back in.

#### Acceptance Criteria
- [ ] delete-account deletes the auth user and all dependent data.
- [ ] No references to legacy tables remain.
- [ ] Function returns error codes appropriately.

---

### Issue #005: Daily quest assignment relies on missing RPC and wrong table name
**Severity**: HIGH  
**Category**: Backend Feature Bug  
**Location**: `apps/ios/.../SupabaseDataService.swift` (lines 94–167)

#### Current State
Client queries `user_quests` and then calls a non-existent RPC `assign_daily_quest` that returns a quest id.

**Before:**
```swift
let existingQuests: [DBUserQuestWithTemplate] = try await supabase
  .from(Tables.userQuests)
  .select("*, quest_templates(*)")
  .eq("user_id", value: userId)
  .eq("assigned_date", value: today)
  .execute()
  .value

let result: [String: String] = try await supabase
  .rpc("assign_daily_quest", params: ["p_user_id": userId.uuidString, "p_date": today])
  .execute()
  .value
```
But migrations define `quests` with `local_date` and already include a uniqueness constraint on `(user_id, local_date)`.

#### Root Cause
- Client is built against `user_quests/assigned_date` schema, while DB defines `quests/local_date`.

#### Solution
- Update iOS to use `quests` + `local_date`.
- Add a Postgres RPC `assign_daily_quest(p_local_date text)` that is idempotent (uses unique constraint).
- Optionally add a server-side trigger to update `user_stats` on quest completion (recommended; see below).

#### Implementation Details

##### A) Supabase migration: add assign_daily_quest RPC
Create: `supabase/migrations/20260115000100_assign_daily_quest.sql`
```sql
CREATE OR REPLACE FUNCTION public.assign_daily_quest(p_local_date TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_existing UUID;
  v_template UUID;
  v_new_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT id INTO v_existing
  FROM public.quests
  WHERE user_id = v_user_id AND local_date = p_local_date
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  SELECT id INTO v_template
  FROM public.quest_templates
  ORDER BY random()
  LIMIT 1;

  IF v_template IS NULL THEN
    RAISE EXCEPTION 'No quest templates available';
  END IF;

  INSERT INTO public.quests (user_id, template_id, local_date, status)
  VALUES (v_user_id, v_template, p_local_date, 'assigned')
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.assign_daily_quest(TEXT) TO authenticated;
```

##### B) iOS: update getTodayQuest to use `quests`
```swift
// 1) query quests with local_date
let existing: [DBQuestWithTemplate] = try await supabase
  .from(Tables.quests)
  .select("*, quest_templates(*)")
  .eq("user_id", value: userId)
  .eq("local_date", value: today)
  .execute()
  .value

// 2) call assign_daily_quest if missing
if existing.isEmpty {
  let questId: UUID = try await supabase
    .rpc("assign_daily_quest", params: ["p_local_date": today])
    .execute()
    .value

  let quests: [DBQuestWithTemplate] = try await supabase
    .from(Tables.quests)
    .select("*, quest_templates(*)")
    .eq("id", value: questId)
    .execute()
    .value

  guard let quest = quests.first else { throw SupabaseError.noData }
  return quest.toQuest()
}
```

##### C) Recommended: server trigger to update stats on completion
Create: `supabase/migrations/20260115000200_quest_completion_stats_trigger.sql`
```sql
CREATE OR REPLACE FUNCTION public.on_quest_completed_update_stats()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  prev_date TEXT;
  new_streak INT;
BEGIN
  IF NEW.status = 'completed' AND OLD.status <> 'completed' THEN
    -- total quests
    UPDATE public.user_stats
      SET total_quests_completed = total_quests_completed + 1
      WHERE user_id = NEW.user_id;

    -- streak: compare to last_quest_date
    SELECT last_quest_date INTO prev_date
    FROM public.user_stats
    WHERE user_id = NEW.user_id;

    IF prev_date IS NULL THEN
      new_streak := 1;
    ELSE
      -- compare NEW.local_date to prev_date - naive: assumes dates are YYYY-MM-DD
      IF NEW.local_date = to_char((to_date(prev_date, 'YYYY-MM-DD') + interval '1 day')::date, 'YYYY-MM-DD') THEN
        SELECT current_streak_days + 1 INTO new_streak
        FROM public.user_stats WHERE user_id = NEW.user_id;
      ELSE
        new_streak := 1;
      END IF;
    END IF;

    UPDATE public.user_stats
      SET current_streak_days = new_streak,
          longest_streak_days = GREATEST(longest_streak_days, new_streak),
          last_quest_date = NEW.local_date,
          updated_at = NOW()
      WHERE user_id = NEW.user_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_quest_completed_stats ON public.quests;
CREATE TRIGGER trg_quest_completed_stats
AFTER UPDATE OF status ON public.quests
FOR EACH ROW
EXECUTE FUNCTION public.on_quest_completed_update_stats();
```

#### Testing Requirements
- [ ] DB test: calling `assign_daily_quest` twice same day returns same quest id
- [ ] iOS integration: Home loads today’s quest reliably
- [ ] DB test: completing quest increments stats and updates streak

#### Acceptance Criteria
- [ ] “Today’s Quest” loads without errors on a fresh account.
- [ ] Exactly one quest per day is assigned (idempotent).
- [ ] Stats/streak update correctly on completion.

---

### Issue #006: Circles join/create flows break under RLS + wrong table name
**Severity**: HIGH  
**Category**: Social Feature Bug  
**Location**:
- `apps/ios/.../SupabaseDataService.swift` (circle functions around lines 481–704)
- `supabase/migrations/20260113225736_fix_circle_members_rls_recursion.sql` (circles SELECT policy; lines 39–47)

#### Current State
- iOS references `circle_checkins` but DB defines `circle_posts`.
- Circles SELECT policy requires membership, so joining by invite code via `.select().eq("invite_code", ...)` is blocked for non-members.

#### Root Cause
- Schema drift + RLS policy design: “must be member to see circle” conflicts with “look up by invite code to join”.

#### Solution
- Update iOS to use `circle_posts` and treat “check-ins” as `kind='checkin'`.
- Add circles **INSERT** policy (missing in migrations).
- Add `join_circle_by_invite_code` SECURITY DEFINER RPC to join without broadening SELECT policies.

#### Implementation Details

##### A) DB migration: circles insert policy + join RPC
Create: `supabase/migrations/20260115000300_circle_join_rpc.sql`
```sql
-- Allow users to create circles they own
CREATE POLICY IF NOT EXISTS "Users can create circles" ON public.circles
  FOR INSERT WITH CHECK (auth.uid() = owner_id);

-- Join by invite code without granting broad SELECT access
CREATE OR REPLACE FUNCTION public.join_circle_by_invite_code(p_invite_code TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_circle_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT id INTO v_circle_id
  FROM public.circles
  WHERE invite_code = p_invite_code
  LIMIT 1;

  IF v_circle_id IS NULL THEN
    RAISE EXCEPTION 'Invalid invite code';
  END IF;

  INSERT INTO public.circle_members (circle_id, user_id, role)
  VALUES (v_circle_id, v_user_id, 'member')
  ON CONFLICT (circle_id, user_id) DO NOTHING;

  RETURN v_circle_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.join_circle_by_invite_code(TEXT) TO authenticated;
```

##### B) iOS: update joinCircle to call RPC (no circles select required)
```swift
let circleId: UUID = try await supabase
  .rpc("join_circle_by_invite_code", params: ["p_invite_code": inviteCode.uppercased()])
  .execute()
  .value

let circles: [DBCircle] = try await supabase
  .from(Tables.circles)
  .select()
  .eq("id", value: circleId)
  .execute()
  .value

guard let circle = circles.first else { throw SupabaseError.noData }
return circle.toFriendCircle(role: .member, memberCount: nil)
```

##### C) iOS: replace `circle_checkins` with `circle_posts`
- Rename `Tables.circleCheckins` → `Tables.circlePosts`
- Replace `DBCircleCheckin` with `DBCirclePost` mapping to:
  - `kind`, `mood_emoji`, `body_text`, `local_date`, `created_at`, `profiles(display_name, avatar_url)`

#### Testing Requirements
- [ ] DB integration: non-member can join by invite code (via RPC), and then can SELECT circle
- [ ] iOS integration: join flow works on a clean account
- [ ] iOS integration: circle feed loads posts/check-ins

#### Acceptance Criteria
- [ ] Creating a circle works (INSERT policy exists).
- [ ] Joining by invite code works without weakening circles SELECT policy.
- [ ] Circle feed uses `circle_posts` consistently.

---

### Issue #007: Premium/unlimited quota mishandled; quota banner/paywall triggers incorrectly
**Severity**: HIGH  
**Category**: Monetization/UX Bug  
**Location**:
- `apps/ios/.../ChatView.swift` (lines 145–147, 291–339)
- `apps/ios/.../Models.swift` (Entitlements computed properties; lines 40–47)
- `supabase/functions/chat/index.ts` (returns `quotaLimit = -1` for premium)

#### Current State
- Chat Edge Function returns `quota_limit = -1` for premium users.
- iOS computes `quotaRemaining = -1`, and then:
  - `showQuotaWarning = response.quotaRemaining <= 3` (true for -1)
  - Banner renders “Only -1 messages left today”
- `Entitlements.isQuotaExceeded` becomes incorrect if `dailyAiQuota` is <= 0 or if the app treats -1 as a real limit.
- Banner is not tappable (not a `Button`), hurting conversions.

#### Root Cause
- Negative quota values are used as “unlimited” sentinel but treated as literal numbers in UI/logic.

#### Solution
- Interpret unlimited via **tier** rather than numeric sentinel.
- Prevent warnings for unlimited.
- Make quota banner actionable (tap → paywall).

#### Implementation Details

##### A) Fix Entitlements math
**Before:**
```swift
var remaining: Int { dailyAiQuota - dailyAiUsed }
var isQuotaExceeded: Bool { dailyAiUsed >= dailyAiQuota }
```

**After:**
```swift
var remaining: Int {
    if tier == .premium { return Int.max }
    return max(0, dailyAiQuota - dailyAiUsed)
}

var isQuotaExceeded: Bool {
    if tier == .premium { return false }
    return dailyAiUsed >= dailyAiQuota
}
```

##### B) Fix quota warning logic in ChatView
**Before:**
```swift
showQuotaWarning = response.quotaRemaining <= quotaWarningThreshold
```
**After:**
```swift
if appState.entitlements.tier == .premium {
    showQuotaWarning = false
} else {
    showQuotaWarning = (response.quotaRemaining >= 0 && response.quotaRemaining <= quotaWarningThreshold)
}
```

##### C) Make banner tappable
**Before:** `QuotaWarningBanner` is a plain `HStack`.
**After:** wrap content in `Button` and pass an action:

```swift
struct QuotaWarningBanner: View {
    let remaining: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Only \(remaining) messages left today")
                Spacer()
                Text("Upgrade").fontWeight(.semibold)
                Image(systemName: "chevron.right")
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Only \(remaining) messages left today. Tap to upgrade.")
        .accessibilityAddTraits(.isButton)
    }
}
```

In `ChatView`:
```swift
QuotaWarningBanner(remaining: appState.entitlements.remaining) {
    appState.showPaywall = true
}
```

##### D) Keep entitlements usage in sync with server response (recommended)
- Extend `SendMessageResponse` to include `quotaUsed` and `quotaLimit`.
- For free tier, set `appState.entitlements.dailyAiUsed = quotaUsed` after each send.

#### Testing Requirements
- [ ] Unit test: premium tier never shows quota banner and never blocks sending.
- [ ] Unit test: free tier banner shows at threshold and is tappable.
- [ ] Manual: premium users don’t see “-1 remaining”.

#### Acceptance Criteria
- [ ] Premium users never see quota warnings/paywall due to quota.
- [ ] Banner accurately reflects remaining free messages.
- [ ] Banner tap opens paywall.

---

### Issue #008: BillingService entitlements refresh decodes into wrong model; task type mismatch
**Severity**: HIGH  
**Category**: iOS Runtime/Correctness  
**Location**: `apps/ios/.../BillingService.swift` (lines 13–18, 155–178)

#### Current State
- `transactionListener` is declared `Task<Void, Error>?`, but the created Task doesn’t throw.
- `refreshEntitlements()` selects only `subscription_tier, daily_ai_quota, daily_ai_used` but decodes into `DBProfile` (which requires many missing keys).

**Before:**
```swift
private var transactionListener: Task<Void, Error>?

let profile: DBProfile = try await supabase
  .from(Tables.profiles)
  .select("subscription_tier, daily_ai_quota, daily_ai_used")
  .eq("id", value: userId)
  .single()
  .execute()
  .value
```

#### Root Cause
- Model misuse: partial selects must decode into partial structs.
- Incorrect Task failure type.

#### Solution
- Change listener to `Task<Void, Never>?`.
- Decode entitlements into a minimal struct `DBEntitlementsRow`.

#### Implementation Details
```swift
@MainActor
class BillingService: ObservableObject {
    private var transactionListener: Task<Void, Never>?

    private struct DBEntitlementsRow: Codable {
        let subscriptionTier: String
        let dailyAiQuota: Int
        let dailyAiUsed: Int
        enum CodingKeys: String, CodingKey {
            case subscriptionTier = "subscription_tier"
            case dailyAiQuota = "daily_ai_quota"
            case dailyAiUsed = "daily_ai_used"
        }
    }

    func refreshEntitlements() async throws {
        guard let userId = try await supabase.auth.session.user.id as UUID? else { return }

        let row: DBEntitlementsRow = try await supabase
            .from(Tables.profiles)
            .select("subscription_tier, daily_ai_quota, daily_ai_used")
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        let tier: Entitlements.Tier = (row.subscriptionTier == "premium") ? .premium : .free
        await MainActor.run {
            self.entitlements = Entitlements(tier: tier, dailyAiQuota: row.dailyAiQuota, dailyAiUsed: row.dailyAiUsed)
        }
    }
}
```

#### Testing Requirements
- [ ] Unit test: refreshEntitlements decodes with a mocked JSON payload (no missing-key errors)
- [ ] Manual: purchase flow updates UI entitlements

#### Acceptance Criteria
- [ ] BillingService compiles (Task type correct).
- [ ] Entitlements refresh succeeds without decoding exceptions.

---

### Issue #009: Handle availability check cannot work with current RLS
**Severity**: HIGH  
**Category**: RLS/Correctness  
**Location**: `SupabaseAuthService.isHandleAvailable` (lines 446–462) + RLS policy in migration (`profiles` SELECT: own-profile only)

#### Current State
`isHandleAvailable` selects from `profiles` by handle, but RLS prevents seeing other users’ rows; it will often return “available” even if taken.

**Before:**
```swift
let results: [DBProfileId] = try await supabase
  .from(Tables.profiles)
  .select("id")
  .eq("handle", value: handle.lowercased())
  .execute()
  .value
return results.isEmpty
```

#### Root Cause
RLS policy `FOR SELECT USING (auth.uid() = id)` blocks global handle queries.

#### Solution
Add SECURITY DEFINER RPC `is_handle_available(p_handle text, p_exclude uuid)` and call it from iOS.

#### Implementation Details

##### A) DB migration: RPC
Create: `supabase/migrations/20260115000400_is_handle_available.sql`
```sql
CREATE OR REPLACE FUNCTION public.is_handle_available(p_handle TEXT, p_exclude UUID DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE lower(handle) = lower(p_handle)
      AND (p_exclude IS NULL OR id <> p_exclude)
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_handle_available(TEXT, UUID) TO authenticated;
```

##### B) iOS: call RPC
```swift
struct HandleAvailableResponse: Decodable { let value: Bool } // if wrapped; otherwise decode Bool directly

let available: Bool = try await supabase
  .rpc("is_handle_available", params: ["p_handle": normalizedHandle, "p_exclude": userId.uuidString])
  .execute()
  .value
return available
```

#### Testing Requirements
- [ ] DB test: taken handle returns false
- [ ] iOS integration: profile update shows “handle taken” correctly

#### Acceptance Criteria
- [ ] Users cannot set duplicate handles.
- [ ] UI returns correct error without leaking raw DB error messages.

---

### Issue #010: NotificationManager never registers device tokens (DependencyContainer not injected)
**Severity**: HIGH  
**Category**: Push Notifications  
**Location**:
- `apps/ios/.../NotificationManager.swift` (lines 6–17, 97–118)
- `apps/ios/.../MindFriendApp.swift` (lines 10–23)
- `apps/ios/.../AppDelegate.swift` (lines 15–34)

#### Current State
`NotificationManager.shared` is initialized with `container = nil`, so `registerDeviceWithBackend` returns early and never stores the token.

**Before:**
```swift
static let shared = NotificationManager(container: nil)

private let container: DependencyContainer?

private func registerDeviceWithBackend(token: Data) async {
    guard let container = container else { return }
    try await container.supabaseDataService.registerDevice(...)
}
```

#### Root Cause
Singleton created before app DI container exists; no late binding.

#### Solution
- Allow late configuration of container and re-register pending token.
- Align token storage to `push_tokens` table (not `devices`).

#### Implementation Details

**After:**
```swift
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    private var container: DependencyContainer?
    private var pendingToken: Data?

    func configure(container: DependencyContainer) {
        self.container = container
        if let token = pendingToken {
            Task { await registerDeviceWithBackend(token: token) }
        }
    }

    func didReceiveDeviceToken(_ token: Data) {
        pendingToken = token
        Task { await registerDeviceWithBackend(token: token) }
    }

    private func registerDeviceWithBackend(token: Data) async {
        guard let container else { return }
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        do {
            try await container.supabaseDataService.registerPushToken(token: tokenString, platform: "ios")
        } catch {
            print("Failed to register push token: \(error)")
        }
    }
}
```

In `MindFriendApp.swift`:
```swift
.task {
  NotificationManager.shared.configure(container: container)
  ...
}
```

#### Testing Requirements
- [ ] Unit test: token received before configure → registers after configure
- [ ] Manual: push token appears in `push_tokens` for the signed-in user

#### Acceptance Criteria
- [ ] Token registration happens reliably after sign-in.
- [ ] No silent early-return prevents registration.

---

### Issue #011: Settings screens do not persist changes
**Severity**: MEDIUM  
**Category**: UX/Consistency  
**Location**: `apps/ios/.../ProfileView.swift` (lines 225–321)

#### Current State
Settings views store local state but do not save to backend (`updateSettings`) or update AppState.

#### Root Cause
Settings subviews aren’t wired to `appState.currentUser.settings` and do not call `SupabaseAuthService.updateSettings`.

#### Solution
- Initialize local state from AppState on appear.
- Add “Save” action that:
  1) updates AppState
  2) calls `container.supabaseAuthService.updateSettings(...)`
- For notification toggles, optionally request permissions when enabling.

#### Implementation Details (example for AI Preferences)
```swift
struct AIPreferencesView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var selectedTone: AITone = .friendly
    @State private var isSaving = false

    var body: some View {
        Form { ... }
        .toolbar {
            Button("Save") {
                Task {
                    guard var user = appState.currentUser else { return }
                    isSaving = true
                    user.settings.aiTone = selectedTone
                    do {
                        try await container.supabaseAuthService.updateSettings(user.settings)
                        await MainActor.run { appState.currentUser = user }
                    } catch {
                        appState.showError(.apiError(error.localizedDescription))
                    }
                    isSaving = false
                }
            }.disabled(isSaving)
        }
        .onAppear {
            selectedTone = appState.currentUser?.settings.aiTone ?? .friendly
        }
    }
}
```

#### Testing Requirements
- [ ] Manual: change AI tone → relaunch app → setting persists
- [ ] Integration: DB row `user_settings.ai_tone` updates

#### Acceptance Criteria
- [ ] Settings changes persist across app restarts.
- [ ] AppState reflects changes immediately.

---

### Issue #012: Circles invite code collision not handled; counts inaccurate
**Severity**: MEDIUM  
**Category**: Robustness  
**Location**: `SupabaseDataService.createCircle` (lines ~481–540)

#### Current State
Invite code is generated once; if unique constraint collides, insert fails with no retry.

#### Solution
- Retry invite code generation on unique violation (bounded attempts).
- Return accurate `memberCount` by querying membership count (optional).

#### Implementation Details
```swift
func createCircle(name: String, description: String?) async throws -> FriendCircle {
    guard let userId = userId else { throw SupabaseError.unauthorized }

    for _ in 0..<5 {
        let inviteCode = generateInviteCode()
        do {
            let circle = try await supabase.from(Tables.circles)
              .insert(["name": name, "description": description, "owner_id": userId.uuidString, "invite_code": inviteCode])
              .select()
              .single()
              .execute()
              .value as DBCircle

            // insert membership...

            return circle.toFriendCircle(role: .owner, memberCount: 1)
        } catch {
            if String(describing: error).contains("duplicate key") {
                continue
            }
            throw error
        }
    }

    throw SupabaseError.unknown("Failed to generate unique invite code")
}
```

#### Testing Requirements
- [ ] Unit: simulate duplicate insert error and retry path
- [ ] Integration: create circle repeatedly; no collisions escape retry loop

#### Acceptance Criteria
- [ ] Circle creation succeeds even under rare invite-code collisions.

---

### Issue #013: Edge Function CORS is overly permissive in some functions
**Severity**: MEDIUM  
**Category**: Security  
**Location**: `supabase/functions/verify-purchase/index.ts`, `delete-account/index.ts` (CORS headers defined as `*`)

#### Current State
Some functions use:
```ts
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  ...
}
```
instead of shared allowlist logic in `_shared/cors.ts`.

#### Root Cause
Inconsistent CORS usage across functions.

#### Solution
Use `getCorsHeaders(origin)` everywhere, and only fall back to `*` when origin is absent (mobile clients).

#### Implementation Details
- Replace inline cors headers with:
```ts
import { getCorsHeaders } from "../_shared/cors.ts"
const cors = getCorsHeaders(req.headers.get("origin") ?? "")
```
- Ensure OPTIONS responses mirror the same header set.

#### Testing Requirements
- [ ] Manual: browser calls from allowed origin succeed; disallowed origin blocked
- [ ] Mobile: calls without origin still succeed

#### Acceptance Criteria
- [ ] CORS behavior is consistent and documented.

---

### Issue #014: iOS unit tests are stale and likely fail to compile
**Severity**: MEDIUM  
**Category**: DevEx/CI  
**Location**: `apps/ios/MindFriendAppTests/*`

#### Current State
Tests reference types/enums that do not exist in the app target (e.g., `APIEndpoint`, `Entitlements.rawValue`, `AITone.casual`).

#### Root Cause
Architecture moved from custom API endpoints to Supabase services; tests weren’t updated.

#### Solution
- Delete or quarantine obsolete tests, then replace with tests aligned to current code:
  - `Entitlements` math (Issue #007)
  - `assign_daily_quest` integration can be mocked at service layer
  - model decoding tests for `DBProfileRow`/`DBUserSettingsRow`/`DBUserStatsRow`

#### Implementation Details
- Remove these files or update them to reflect current models:
  - `MindFriendAppTests/APIEndpointTests.swift` (no longer applicable)
  - Update `ModelsTests.swift` to use existing enums/cases and correct ranges (mood 1–5).

#### Testing Requirements
- [ ] `xcodebuild test` passes on CI
- [ ] At least 5 core unit tests cover entitlements + basic model decoding

#### Acceptance Criteria
- [ ] Test target compiles and runs.
- [ ] Tests reflect current architecture and prevent regressions.

---

### Issue #015: Repo hygiene (committed env + artifacts)
**Severity**: LOW  
**Category**: Repo Hygiene  
**Location**: `apps/api/.env`, `apps/api/node_modules`, `apps/api/dist`

#### Current State
Large artifacts and a `.env` file are committed. Even if placeholders, this pattern increases risk of accidentally committing real secrets.

#### Solution
- Add `.env` to `.gitignore` and keep only `.env.example`.
- Remove `node_modules/` and `dist/` from version control; rely on package manager and build steps.
- Add secret scanning in CI (e.g., gitleaks) (future enhancement).

#### Testing Requirements
- [ ] CI builds from clean checkout without committed artifacts

#### Acceptance Criteria
- [ ] No secrets or env files committed.
- [ ] Repo size reduced; builds are reproducible.

---

## Implementation Order

1. **CRITICAL security/compliance**
   - Issue #001 (purchase verification) + iOS request update
   - Issue #002 (App Store copy)
2. **Backend correctness**
   - Issue #004 (delete-account rewrite)
   - Issue #013 (CORS consistency)
3. **Schema alignment + core features**
   - Issue #003 (profiles/settings/stats composition)
   - Issue #005 (quests + assign_daily_quest + stats trigger)
   - Issue #006 (circles join RPC + table rename)
   - Issue #009 (is_handle_available RPC + client call)
4. **Client UX stability**
   - Issue #007 (quota logic + banner CTA)
   - Issue #010 (notification DI + push_tokens)
   - Issue #011 (settings persistence)
   - Issue #012 (invite code retry)
5. **DevEx**
   - Issue #014 (fix test suite)
   - Issue #015 (repo hygiene)

---

## Rollback Plan

### Database
- Each fix is delivered as a **forward-only migration**; for rollback:
  - Create explicit down-migrations only for changes that are safe to revert (policies/functions).
  - Prefer **feature-flagging** new RPC usage on client rather than removing DB objects.
- For production with existing clients:
  - Consider **compatibility views** (e.g., view `user_quests` → `quests`) and INSTEAD-OF triggers to support old clients temporarily.

### iOS
- Guard schema-dependent changes behind a **remote config flag** (e.g., “useNewSchema”) if you have existing installs.
- Keep paywall/quota fixes always-on (safe).

### Edge Functions
- Version functions by deployment tag; keep previous build available for rapid revert.
- Add server-side logging + alerts for verification and deletion errors before rollout.

---

## Post-Implementation Checklist
- [ ] All iOS targets build (app + tests + UI tests)
- [ ] Supabase migrations apply cleanly on a fresh local Supabase instance
- [ ] Edge functions deployed and tested (chat, verify-purchase, delete-account)
- [ ] Purchase flow verified in sandbox with real StoreKit transactions
- [ ] Account deletion verified (data truly removed)
- [ ] App Store metadata reviewed for truthfulness
- [ ] Security pass: CORS, auth checks, RLS policies, and service-role key handling reviewed
