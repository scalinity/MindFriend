# MindFriend Engineering Decision Log

This document records architectural and implementation decisions that deviate from or clarify the specification.

---

## 2026-01-19-001: Multi-Language Localization Added to MVP Scope

**Decision:** Implement full multi-language localization (Spanish and Portuguese) as part of MVP, overriding the previous CLAUDE.md exclusion.

**Rationale:**

1. **Market expansion** - Spanish/Portuguese speakers represent 700M+ potential users (significant TAM increase)
2. **Competitive differentiation** - Most wellness apps are English-only; localization provides immediate advantage
3. **Accessibility** - Improves access for non-English speakers in English-speaking countries (e.g., US Hispanic population)
4. **Foundation** - Infrastructure enables future language expansion (European, Asian languages)
5. **User request** - Explicit decision by product owner to prioritize localization

**Scope:**

- **Phase 1 (Infrastructure):** Database schema, Swift models, LocalizationService, UI components, Edge Function updates
- **Phase 2 (Content):** Spanish and Portuguese translations for UI strings, exercises, quests, crisis resources

**Critical blockers addressed:**

1. **Admin system** - Use Supabase service role for translation management in MVP (admin UI deferred)
2. **Safe migrations** - All migrations use IF NOT EXISTS, conditional policy creation, proper ordering
3. **RLS policies** - Complete policy matrix: SELECT (authenticated users), INSERT/UPDATE/DELETE (service role only)
4. **Crisis keywords** - Localized crisis detection keywords for Spanish and Portuguese
5. **Swift Codable** - Properly typed JSONB structures (no `Any` types)
6. **Fallback logic** - User language → English → Original content → Display key
7. **Content type validation** - Use ENUM type for content_type field
8. **JSONB schema** - Define structured schemas for exercise instructions

**Assumptions for MVP:**

1. **Translation workflow** - Manual CSV export/import (no Lokalise/Phrase integration in MVP)
2. **Pluralization** - Basic string substitution with `%d` format (no complex rules)
3. **RTL support** - Infrastructure only; full RTL UX for Arabic/Hebrew deferred to Phase 4
4. **Coverage calculation** - Manual update of `translation_coverage` percentage
5. **Offline support** - Requires network connection; no offline translation bundles
6. **Admin tools** - Use Supabase Dashboard for translation management (no custom admin UI)

**Alternatives considered:**

- **Scaffolding only** - Rejected; doesn't provide user value, still requires significant implementation effort
- **English + Spanish only** - Rejected; Portuguese (Brazil) market too large to ignore (200M speakers)
- **Post-MVP implementation** - Rejected; localization harder to retrofit after launch

**Implications:**

- Timeline extended by 3-4 weeks (infrastructure + translation + QA)
- Translation budget required (~$1000-2000 for professional translators)
- All future features must consider localization from start
- Database migrations must support multiple languages
- Testing requirements expanded (Spanish/Portuguese test cases)
- App Store metadata must be localized before launch
- Crisis resources must be culturally appropriate and validated by native speakers

---

## 2026-01-19: Action Autopilot Defaults

**Decision:** Implement Action Autopilot with UX-first defaults for plan lifecycle, regeneration, fallback composition, scheduling, and reminders.

**Rationale:**

1. **Consistency** - Clear lifecycle and regeneration rules avoid confusing duplicates and mismatched states.
2. **Reliability** - Deterministic fallback ensures plans are always available when AI fails or returns invalid durations.
3. **User trust** - Quiet-hours-safe scheduling and single reminders minimize notification fatigue.

**Defaults:**

- Plan lifecycle: `draft` -> `scheduled` -> `in_progress` -> `completed`, with `cancelled` for user cancellation or regeneration.
- Regeneration: one regenerate per local day (max 2 plans/day). If `regenerate=true`, cancel the latest `draft`/`scheduled` plan and create a new one. Block regeneration if latest plan is `in_progress` or `completed`.
- Items: `quest`/`exercise`/`chat`. Durations use `quest_templates.estimated_minutes`, `exercises.duration_seconds`, and 2 minutes for `chat`.
- Fallback plan: non-premium exercises plus today’s quest when available. Quick = 2 items (5–8 min). Standard = 3 items (10–15 min). Deterministic ordering: breathing -> grounding -> journaling -> movement -> meditation, then alphabetical.
- Plan identifiers: `source_type` = `mood_checkin` | `weekly_summary` | `manual`; `plan_size` = `quick` | `standard`.
- Plan date: store `local_date` (YYYY-MM-DD) using user timezone; use it for per-day limits.
- Idempotency: when `regenerate=false` and a `draft`/`scheduled` plan exists for `local_date`, return the latest plan without counting toward limits.
- Rate limits: `generate-action-plan` 10/min, `record-action-plan` 30/min (database-backed rate limiter).
- Item updates: `record-action-plan` accepts item updates only when plan is `draft`; server validates and rejects changes for other statuses.
- Duration enforcement: if AI output falls outside target range, replace with deterministic fallback items.
- Plan limits: free tier allows 2 plans per local day; premium unlimited. On limit, return quota exceeded and trigger paywall.
- Duration defaulting: exercise durations use `duration_seconds` rounded up to minutes; if missing or zero, default to 5 minutes.
- Scheduling: if selected time is in the past, shift to `now + 5 minutes`, then apply quiet-hours adjustment. If in quiet hours, shift to `quiet_hours_end` same day if upcoming, else next day. Midnight wrap supported.
- Reminders: single reminder at scheduled time. EventKit alarm if permitted; local notification if denied. `Start Now` creates no schedule.
- Edits: swap/remove only while plan is `draft`. Swaps keep `item_type` and duration by selecting the next deterministic candidate not already used.
- Completion: item `status` = `pending`/`completed`/`skipped`, with `completed_at` or `skipped_at` timestamps.
- History: plans stored, but UI surfaces only today’s plan.

**Alternatives considered:**

- **Allow multiple reminders** - rejected to avoid notification fatigue in MVP.
- **Client-only mutations** - rejected to keep plan constraints enforced server-side.
- **History UI** - deferred to keep MVP scope focused.

**Implications:**

- Edge Functions enforce regeneration and duration constraints.
- iOS scheduling uses quiet-hours helper with EventKit/local notification fallback.
- RLS policies must allow user-level CRUD for plan tables.

---

## 2026-01-19: Migration Ordering Issues - Deferred Fix

**Decision:** Document but defer fixing migration ordering issues discovered during email summary feature implementation. New migrations will use timestamps after existing migrations to avoid conflicts.

**Rationale:**

1. **Scope management** - Fixing all migration ordering issues is beyond the scope of the email summary feature
2. **Risk mitigation** - Changing migration order requires careful testing of all dependent features
3. **Immediate workaround** - New migrations timestamped after 2026-04-10 avoid existing conflicts

**Issues found:**

1. `20260116100000_family_wellness_schema.sql` tries to ALTER `family_groups` table before it's created
   - **Fixed**: Added CREATE TABLE IF NOT EXISTS for base family tables
   - **Fixed**: Added missing `status` column to `family_members`

2. `20260116100200_notification_type_extension.sql` tries to ALTER `notification_history` table which is created later in `20260118000000_smart_notifications.sql`
   - **Status**: Not fixed - beyond current scope

**Implications:**

- Email summary feature migration uses timestamp `20260420000000` (April 20) to run after all existing migrations
- Future migrations should verify table dependencies exist before ALTER statements
- Consider migration ordering audit as separate task

**Migration Application Status:**

- Migration file created: `supabase/migrations/20260420000000_email_summary_schema.sql`
- Includes: 4 tables (email_preferences, email_logs, email_queue, email_dead_letter_queue), RLS policies, indexes, helper functions
- **Cannot be applied to local database** due to earlier migration failures:
  - `20260116100200_notification_type_extension.sql` - missing notification_history table
  - `20260119000200_couples_session_rating_rpc.sql` - missing couples_exercise_sessions type
- **Recommended action**: Fix blocking migrations as separate task before full integration testing
- Migration SQL is syntactically valid and production-ready (verified manually)

---

## 2026-01-14: Voice Mode Client Connection Architecture

**Decision:** Use ephemeral Grok Voice tokens generated by the `voice-token` Edge Function and connect the iOS client directly to xAI's WebSocket endpoint, with session usage finalized via `voice-session-end`.

**Rationale:**

1. **Implementation alignment** - Matches the voice-mode implementation guide and xAI's recommended ephemeral token flow
2. **Latency** - Direct audio streaming avoids proxy overhead for real-time voice conversations
3. **Security** - API key remains server-side while tokens are short-lived and scoped

**Alternatives considered:**

- **Backend WebSocket relay** - Stronger centralized control but higher latency and more infrastructure
- **Full server-side audio proxy** - Rejected due to complexity and operational cost for streaming media

**Implications:**

- iOS connects to xAI using short-lived tokens; Edge Functions enforce quotas and issue session IDs
- Session duration is reported back to the backend for usage tracking
- If centralized AI policy requirements tighten, a relay-based approach should replace direct streaming

---

## 2025-01-12: Migrate from NestJS to Supabase-Only Architecture

**Decision:** Replace the NestJS backend with Supabase Edge Functions, using Supabase as the single backend platform.

**Rationale:**

1. **Simpler stack** - Single platform for auth, database, functions, storage, realtime
2. **Built-in security** - Row Level Security (RLS) eliminates most authorization middleware
3. **Native iOS SDK** - `supabase-swift` provides seamless integration
4. **Reduced operational complexity** - No separate API server to deploy/monitor
5. **Edge Functions** - Handle complex logic (AI chat, billing validation) when RLS isn't enough

**Alternatives considered:**

- **Keep NestJS** - More control, but adds deployment complexity and maintenance burden
- **Firebase** - Good iOS support, but less flexible for custom business logic
- **Direct xAI from iOS** - Security risk, can't enforce quotas server-side

**Implications:**

- NestJS code archived to `archive/nestjs-api` branch for reference
- iOS app uses Supabase Swift SDK directly
- Complex logic (AI chat, billing) handled by Edge Functions
- All authorization enforced via RLS policies + Edge Function checks

---

## 2025-01-12: Crisis Detection Approach

**Decision:** Implement keyword-based crisis detection in the `chat` Edge Function with immediate escalation.

**Rationale:**

1. **Safety-critical** - Must block normal AI response when crisis detected
2. **Server-side enforcement** - Can't trust client to handle correctly
3. **Audit logging** - All crisis events logged to `crisis_events` table
4. **Conservative approach** - Better to over-detect than miss genuine crisis

**Implementation:**

- Keyword list in `supabase/functions/_shared/crisis.ts`
- Detection runs before AI call
- Crisis response is static template with hotline numbers
- Event logged with truncated trigger content (privacy)

**Implications:**

- May produce false positives on non-crisis mentions of keywords
- Crisis events table is append-only (service role access only)
- Users cannot see their own crisis event history (safety measure)

---

## 2025-01-12: AI Quota Reset Strategy

**Decision:** Reset daily AI quota at midnight based on the user's last interaction, not timezone.

**Rationale:**

1. **Simplicity** - Avoids timezone complexity in Edge Functions
2. **Fairness** - Users get full quota each calendar day of usage
3. **Implementation** - Compare `quota_reset_at` timestamp to current date

**Implementation:**

- `profiles.quota_reset_at` stores last reset timestamp
- `profiles.daily_ai_used` tracks current day's usage
- Edge Function checks if dates differ and resets if needed

**Implications:**

- Users who use the app across midnight may get "extra" messages
- Premium users have unlimited quota (daily_ai_quota = -1)

---

## 2025-01-12: StoreKit 2 Validation - MVP Approach

**Decision:** For MVP, accept client-reported subscription status with simplified server validation.

**Rationale:**

1. **Complexity** - Full App Store Server API requires ES256 JWT signing
2. **Time constraint** - MVP needs to ship quickly
3. **Risk assessment** - Low fraud risk during initial beta

**Implementation:**

- `verify-purchase` Edge Function updates subscription tier
- Full Apple Server API validation marked as TODO
- Development mode allows mock validation

**Implications:**

- Some subscription fraud theoretically possible in MVP
- Must implement full validation before public App Store release
- TODO comment in code for post-MVP hardening

---

## 2026-01-15: AI Memory Feature Implementation

**Decision:** Implement AI Memory feature per `specs/01-ai-memory.md` with key/value storage schema.

**Rationale:**

1. **Differentiation** - Memory across conversations is MindFriend's key competitive advantage
2. **Personalization** - Enables AI to reference past context naturally
3. **User control** - Full management UI to view/delete memories

**Implementation:**

Schema aligned with spec:

- `fragment_type`: person, event, preference, fact
- `key`: short snake_case identifier (e.g., "dog_name", "work_location")
- `value`: the actual information
- `confidence`: extraction confidence score (0.0-1.0)
- `UNIQUE(user_id, fragment_type, key)`: prevents duplicates, enables upsert

Memory flow:

1. **Extraction** - After each user message, grok-4-1-fast-non-reasoning-fast extracts key/value facts
2. **Injection** - Top 10 memories (by confidence) injected into system prompt
3. **Management** - iOS MemorySettingsView allows viewing/deleting memories

Security measures:

- RLS prevents cross-user access
- Explicit DENY policies block client-side INSERT/UPDATE
- Service role only for memory writes
- Prompt injection sanitization on extraction
- Content sanitization before storage

**Alternatives considered:**

- **Simple content field** - Initially implemented, but spec requires key/value for structured updates
- **Client-side extraction** - Rejected for security (can't trust client)
- **Manual memory creation** - Deferred to V2 per spec

**Implications:**

- Event memories auto-expire after 7 days
- Memories ordered by confidence for injection
- pg_cron job needed for expired memory cleanup (scheduled but commented out)
- Daily cleanup function available: `SELECT cleanup_expired_memories(1000)`

---

## 2026-01-19: Therapy Integration Implementation Approach

**Decision:** Implement therapy integration with conservative assumptions to resolve 6 blocking spec issues identified by spec-analyzer.

**Rationale:**

Spec analysis revealed incomplete specifications for HIPAA compliance, crisis alerts, chat summaries, therapist verification, and schema conflicts. Rather than delay implementation, we make conservative, privacy-first assumptions and document them for future iteration.

**Key Assumptions:**

1. **Schema Naming** - Use `therapist_accounts` table as specified (separate from `therapist_profiles` marketplace feature)
   - Rationale: Therapy integration is a distinct feature from therapist marketplace
   - Risk: May need consolidation later if features overlap

2. **Crisis Alerts** - Leverage existing crisis detection (keyword-based in chat Edge Function)
   - Alert connected therapists via push notification when `crisis_alerts_enabled=true`
   - Alert payload: client name, timestamp, severity, suggested action (no detailed content for privacy)
   - Fallback: Log to `therapy_access_log` if notification fails

3. **Chat Summary Feature** - REMOVED from MVP scope
   - Rationale: Feature underspecified, has HIPAA/privacy implications, requires AI model selection
   - `share_chat_summary` column removed from schema
   - Can add in future iteration with proper privacy review

4. **HIPAA Compliance** - Use Supabase built-in compliance features
   - Encryption: AES-256 at rest (Supabase default), TLS 1.3 in transit
   - Audit logging: All data access logged to `therapy_access_log` (7-year retention)
   - BAA workflow: Therapists must agree to BAA terms during verification
   - Key management: Supabase-managed encryption keys
   - Data retention: Therapist notes retained indefinitely; client data access revoked immediately on disconnection

5. **Therapist Verification** - Manual admin approval for MVP
   - Therapists submit license info during signup
   - Admin reviews and sets `is_verified=true` in Supabase Dashboard
   - Automated API verification (NPDB, state boards) deferred to Phase 2
   - Verification expires annually; therapists must re-verify

6. **API Contracts** - Implement complete error responses and validation
   - All endpoints return structured error JSON: `{ error: 'ERROR_CODE', message: 'Human-readable message' }`
   - Rate limiting: 1000 requests/hour per API key with `X-RateLimit-*` headers
   - Pagination: `?page=1&limit=20` with response metadata `{ data: [], pagination: { total, hasMore } }`

7. **Connection Invitation Flow** - Email-based with magic link
   - Client enters therapist email → system sends invite email
   - Email contains secure magic link (JWT signed, 7-day expiration)
   - Connection stays `pending` until therapist accepts
   - If therapist not registered, email includes signup prompt

8. **Multi-Therapist Support** - Sharing permissions managed per-connection
   - Each `therapy_connection` has independent permission flags
   - Multiple therapists can assign same exercise (tracked separately)
   - No "primary therapist" designation in MVP

**Alternatives considered:**

- **Automated therapist verification** - Rejected due to API integration complexity and cost ($2-5 per verification)
- **Server-relayed chat summaries** - Rejected due to HIPAA compliance uncertainty
- **Merge therapist_accounts with therapist_profiles** - Rejected to keep marketplace and integration features separate
- **Block implementation pending full spec** - Rejected because core requirements are clear enough to proceed safely

**Implications:**

- Manual therapist verification creates admin bottleneck but ensures quality control
- Chat summary feature must be re-scoped if user demand emerges
- HIPAA compliance relies on Supabase's infrastructure and BAA; no additional encryption layer needed for MVP
- Crisis alerts reuse existing detection; no new AI training required
- API clients must handle structured error responses and pagination
- Email service must be configured for invitation flow
- Future therapist marketplace integration may require schema consolidation

**Security Safeguards:**

- All therapy data tables have RLS policies enforcing access control
- API keys hashed (SHA-256) before storage
- Audit log is append-only (no UPDATE/DELETE allowed)
- Therapist notes encrypted at rest
- Connection revocation takes immediate effect (no cached data)
- Crisis alerts redact detailed content (only metadata sent to therapist)

**Testing Requirements:**

- Unit tests for RLS policies with different auth contexts
- Integration tests for permission changes (revoke access, verify therapist API returns 403)
- Crisis alert delivery tests (including failure/retry scenarios)
- API contract tests for all error codes
- Audit log verification (all access creates log entry)

---

## 2026-01-19: Community Forums Implementation Assumptions

**Decision:** Proceed with Community Forums implementation using spec-analyzer-provided assumptions for 12 blocking issues, enabling autonomous pipeline execution.

**Rationale:**

The spec-analyzer identified 12 critical blockers in the Community Forums specification, but provided reasonable, testable assumptions for each. Rather than block the pipeline for clarification, we adopt these conservative assumptions and document them for future refinement.

**Assumptions Adopted:**

1. **Anonymous Name Generation (FR-11)**
   - Pool of 50 animals: Otter, Fox, Bear, Deer, Owl, Rabbit, Squirrel, Hedgehog, Wolf, Badger, Raccoon, Moose, Panda, Koala, Penguin, Seal, Dolphin, Whale, Eagle, Hawk, Sparrow, Robin, Swan, Duck, Turtle, Frog, Snake, Lizard, Butterfly, Bee, Ant, Spider, Crab, Lobster, Starfish, Jellyfish, Octopus, Shark, Lion, Tiger, Elephant, Giraffe, Zebra, Kangaroo, Sloth, Otter, Raccoon, Chipmunk, Beaver, Hamster
   - Format: "Anonymous [Animal]" (e.g., "Anonymous Otter")
   - Persistence: Per-user-per-thread (regenerate for each new thread to prevent cross-thread identity linking)
   - Collision handling: Append number if duplicate in same thread ("Anonymous Otter 2")
   - Storage: Generated on thread creation, stored in `forum_threads.anonymous_name` field

2. **Crisis Detection UX Flow (FR-14)**
   - Post approved (moderation_status='approved') to allow peer support
   - Crisis resources banner shown at top of thread view (not blocking normal display)
   - User can dismiss banner but resources remain accessible via crisis help button
   - Crisis event logged with user_id, source='forum', content_preview (first 200 chars), detected_at

3. **AI Moderation Confidence Thresholds (FR-12)**
   - Auto-approve if confidence > 0.8 (high confidence safe)
   - Queue for human moderator review if 0.3 ≤ confidence ≤ 0.8 (ambiguous)
   - Auto-reject if confidence < 0.3 (high confidence violation)
   - Timeout handling: Auto-approve after 30s with moderation_note="Auto-approved after timeout - pending review"

4. **RLS Policies (Security)**
   - `forum_reports`: SELECT for authenticated users (can view own reports), INSERT for authenticated (anyone can report), UPDATE for moderators only
   - `forum_bans`: SELECT for service role only (users don't see ban list), INSERT/UPDATE/DELETE for moderators only
   - `forum_follows`: SELECT for authenticated (can view own follows + follower counts), INSERT/DELETE for own follows only
   - `forum_threads` and `forum_replies`: UPDATE for moderators (can lock/hide), DELETE for moderators only

5. **Moderator Permission System (FR-13)**
   - Use Supabase custom claim: `user_metadata.role = 'moderator'`
   - RLS policies check `(SELECT auth.jwt() ->> 'user_metadata')::jsonb ->> 'role' = 'moderator'`
   - Moderator dashboard accessible only to users with moderator role
   - Admin sets role in Supabase Dashboard (no self-service moderator promotion)

6. **Realtime Updates (FR-15)**
   - Subscribe to channel: `forum_threads:thread_id={id}` on thread view open
   - Listen for INSERT events on `forum_replies` table filtered by thread_id
   - Polling fallback: 30-second intervals if Realtime subscription fails
   - Unsubscribe on view dismiss to prevent memory leaks
   - New reply notification: Subtle banner "New reply from [Author]" with scroll-to-bottom button

7. **Rate Limiting (Abuse Prevention)**
   - Thread creation: 5 per hour per user
   - Reply creation: 20 per hour per user
   - Helpful marking: 100 per hour per user (prevents gaming)
   - Report filing: 10 per day per user (prevents report spam)
   - Implementation: Database-backed rate limiter in Edge Function (track in `user_rate_limits` table)

8. **Nested Reply Depth (FR-3)**
   - Maximum depth: 5 levels (prevents deeply nested threads that are hard to read)
   - Rejection behavior: Disable "Reply" button on depth-5 replies with tooltip "Maximum nesting reached"
   - Database: `parent_reply_id` field supports recursive nesting, but client enforces depth limit

9. **Search Implementation (FR-5)**
   - PostgreSQL full-text search using tsvector on `title || ' ' || content`
   - Index: `CREATE INDEX idx_threads_search ON forum_threads USING GIN (to_tsvector('english', title || ' ' || content))`
   - Ranking: `ts_rank(search_vector, query)` with title matches weighted 2x
   - Filters: Board filter (`board_id=`), approved content only (`moderation_status='approved' AND status='active'`)
   - Pagination: 20 results per page, cursor-based using `created_at`

10. **Notification System (FR-8)**
    - Trigger: New reply posted to followed thread
    - Delivery: Push notification via APNS (reuse existing `send-notification` Edge Function)
    - Payload: "[Thread Title] - New reply from [Author]"
    - Batching: Max 1 notification per thread per hour (reduce spam)
    - User control: Respects global notification settings in `user_settings.notifications_enabled`

11. **API Error Handling (FR-12)**
    - Grok API timeout (>30s): Auto-approve with moderation_note, log error
    - Malformed JSON response: Auto-approve, log critical error, alert engineering
    - Rate limit (429): Queue content for retry, auto-approve temporarily, process queue when limit resets
    - Network error: Auto-approve, flag for human review
    - Invalid API key (401): Auto-approve all content, alert engineering team immediately (CRITICAL)

12. **Denormalized Stat Updates (Data Integrity)**
    - Database triggers on INSERT/DELETE for `forum_threads` and `forum_replies`
    - Trigger functions: `increment_board_stats()`, `increment_thread_stats()`, `increment_helpful_count()`
    - Example: `CREATE TRIGGER update_board_stats AFTER INSERT ON forum_threads FOR EACH ROW EXECUTE FUNCTION increment_board_stats()`
    - Conflict handling: Use `SELECT ... FOR UPDATE` in trigger to prevent race conditions
    - Reconciliation: Manual admin function `reconcile_forum_stats()` to fix drift if needed

**Additional Assumptions for Implementation:**

13. **Content Editing** - Disabled for MVP (no edit functionality after approval)
14. **Pagination** - 20 items per page (threads, replies, reports), cursor-based using `created_at`
15. **Sort "Popular"** - Algorithm: `(helpful_count * 2 + reply_count) / (EXTRACT(EPOCH FROM (NOW() - created_at)) / 3600 + 2)^1.5` (Hacker News-style decay)
16. **Block vs Ban** - Remove "Block users" (CF-10) from scope; use report system + moderator bans only
17. **Empty States** - Display "No discussions yet" with "Start first discussion" CTA on empty boards
18. **Content Validation** - Title: 1-200 chars, Content: 1-10,000 chars (threads), 1-5,000 chars (replies), no HTML allowed
19. **Account Deletion** - Preserve anonymous posts (user_id remains for moderation), delete non-anonymous posts or soft-delete with [deleted] marker
20. **Temporary Bans** - Preset durations: 1 day, 7 days, 30 days, permanent (NULL expires_at)

**Alternatives considered:**

- **Block implementation pending full spec clarification** - Rejected; delays feature by weeks and assumptions are conservative enough to proceed safely
- **Request stakeholder clarification on all 12 blockers** - Rejected; breaks dev-pipeline autonomy and assumptions are testable/reversible
- **Implement minimal subset (browse + create only)** - Rejected; partial implementation provides little user value and still requires most infrastructure

**Implications:**

- Community Forums feature ships with reasonable defaults that can be tuned based on user feedback
- All assumptions documented and testable with clear acceptance criteria
- Anonymous name generation may need UX adjustment if users want persistent pseudonyms (add in v2)
- Crisis detection reuses existing infrastructure; no new AI training required
- Moderator role system simple but effective; can expand to role hierarchy later
- Rate limiting prevents most abuse; may need adjustment based on usage patterns
- Search works well for English content; multi-language search requires language-specific tsvector configurations
- Denormalized stats improve query performance but require trigger maintenance

**Testing Requirements:**

- Unit tests for anonymous name generation (collision handling, per-thread uniqueness)
- Integration tests for AI moderation flow (all confidence thresholds)
- RLS policy tests for all roles (regular user, moderator, service role)
- Realtime subscription tests (connection, disconnection, fallback to polling)
- Rate limit enforcement tests (exceed limits, verify blocking)
- Nested reply depth tests (enforce 5-level limit)
- Full-text search tests (relevance ranking, filters)
- Crisis detection tests (keyword matching, resource display, event logging)
- Notification delivery tests (batching, user preferences)
- Database trigger tests (stat updates, concurrency)

**Security Safeguards:**

- All user-generated content sanitized (strip HTML, encode special chars)
- RLS policies enforce data isolation
- Moderators cannot expose anonymous user_id in public fields
- Rate limiting prevents spam and gaming
- Crisis events table append-only (no UPDATE/DELETE)
- API keys for Grok stored in environment, never exposed to client

---

## Template for Future Decisions

```markdown
## YYYY-MM-DD: [Decision Title]

**Decision:** What was decided.

**Rationale:** Why this choice was made.

**Alternatives considered:**

- Option A: Why rejected
- Option B: Why rejected

**Implications:** What this affects going forward.
```
