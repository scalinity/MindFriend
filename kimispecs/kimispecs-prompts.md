# Claude Code Implementation Prompts for MindFriend KimiSpecs

This file contains implementation prompts for every spec in `kimispecs/`.

---

## Prompt 1: Action Autopilot (Mood to Plan + Calendar)

**`/dev-pipeline`**

**Feature:** Action Autopilot (`kimispecs/01-action-autopilot-spec.md`)

**Context:** Generates a 5-15 minute micro-plan after mood check-ins, weekly summaries, or manual request, with optional scheduling and reminders.

**Implementation Focus:**
- Edge Functions `generate-action-plan` and `record-action-plan` with deterministic fallback and rate limiting.
- Database tables `action_plans`, `action_plan_items`, `action_plan_feedback` with RLS.
- iOS flow for plan sheet, quick vs standard selection, edit/swap/remove items, EventKit scheduling with local notification fallback.
- Completion tracking, summary, and feedback capture.
- Tests for plan generation rules, quiet-hour adjustment, and fallback handling.

**Constraints:**
- 2-4 items totaling 5-15 minutes; quick plan 5-8 minutes; regenerate once per day.
- Scheduling must avoid quiet hours and allow cancellation; fallback to local notifications if calendar access denied.

---

## Prompt 2: Coping Kits

**`/dev-pipeline`**

**Feature:** Coping Kits (`kimispecs/02-coping-kits-spec.md`)

**Context:** One-tap bundles of short steps for stress, overwhelm, sleep, or low energy with optional chat reflection.

**Implementation Focus:**
- Define kit templates plus `coping_kits` and `user_coping_kits` tables with RLS.
- Edge Functions `get-coping-kits` and `track-coping-kit`.
- Home card, kit detail, step flow, pinning, completion summary, and feedback UI.
- Resume mid-kit and create exercise sessions for completed steps.
- Tests for template parsing and pinned state persistence.

**Constraints:**
- 2-3 steps totaling 3-8 minutes; fallback to a generic breathing step if a reference is missing.
- Allow users to resume if they exit mid-kit.

---

## Prompt 3: Recovery Mode UX

**`/dev-pipeline`**

**Feature:** Recovery Mode UX (`kimispecs/03-recovery-mode-ux-spec.md`)

**Context:** A gentle, simplified mode triggered by mood trends or manual choice, reducing pressure and notifications.

**Implementation Focus:**
- Add `user_settings` fields for recovery mode state and source; store server-side with RLS.
- Edge Function `evaluate-recovery-mode` and data service `updateRecoveryMode`.
- Recovery banner and simplified Home layout with three primary actions; hide upsell messaging.
- Notification throttling logic with quiet-hour enforcement.
- Tests for trigger rules, layout selection, and throttling behavior.

**Constraints:**
- Reduce notification frequency by at least 50 percent while active.
- Minimum duration 24 hours; never block crisis resources.

---

## Prompt 4: Companion Memory (Daily Intent + Editable Memory)

**`/dev-pipeline`**

**Feature:** Companion Memory (`kimispecs/04-companion-memory-spec.md`)

**Context:** Daily intent capture and a user-controlled memory vault for transparent personalization.

**Implementation Focus:**
- Tables `companion_memory` and `daily_intents` with RLS and expiration logic.
- Edge Functions `get-companion-memory`, `update-companion-memory`, `delete-companion-memory`.
- Chat prompt assembly uses memory only when enabled and shows a "memory used" indicator.
- UI for daily intent banner and memory vault list with edit/delete actions.
- Tests for memory CRUD and intent expiration.

**Constraints:**
- Intent max 140 characters and expires after 24 hours.
- Cap memory items (suggested 20); if memory fetch fails, chat proceeds without memory.

---

## Prompt 5: Quest Arcs and Programs

**`/dev-pipeline`**

**Feature:** Quest Arcs (`kimispecs/05-quest-arcs-spec.md`)

**Context:** Multi-week quest programs with milestones and arc-based quest selection.

**Implementation Focus:**
- Tables `quest_arcs`, `quest_arc_steps`, `user_quest_arcs` with RLS.
- Edge Functions `get-quest-arcs`, `start-quest-arc`, `pause-quest-arc`.
- Update quest assignment to select arc steps and advance arc day on completion.
- Milestone rewards via badges or bonus XP, plus celebration UI.
- Tests for arc progression and milestone triggers.

**Constraints:**
- Only one active arc at a time; user can pause or exit.
- If an arc step is missing, fall back to normal quest selection.

---

## Prompt 6: Insight Lab Experiments

**`/dev-pipeline`**

**Feature:** Insight Lab (`kimispecs/06-insight-lab-spec.md`)

**Context:** 7-day experiments comparing habits with adherence tracking and outcome reports.

**Implementation Focus:**
- Tables `insight_experiments` and `insight_experiment_days` with RLS.
- Edge Functions `start-insight-experiment`, `record-experiment-day`, `generate-experiment-report`.
- UI for experiment catalog, daily check-in card, and report card with share/save.
- Baseline comparison against prior week and reminder notifications.
- Tests for adherence tracking and report generation.

**Constraints:**
- Only one active experiment; default duration 7 days.
- If baseline data missing, generate a reduced report and allow early exit for missed days.

---

## Prompt 7: Progress Stories (Shareable Weekly Recap)

**`/dev-pipeline`**

**Feature:** Progress Stories (`kimispecs/07-progress-stories-spec.md`)

**Context:** Weekly recap transformed into swipeable story cards that can be saved or shared.

**Implementation Focus:**
- Table `weekly_stories` with JSON card payloads and RLS.
- Edge Function `generate-weekly-story` using weekly summary data.
- Full-screen story viewer with swipe progress, save to Photos, and share sheet.
- Circle share option with optional caption; privacy controls for sharing.
- Tests for card rendering and image export.

**Constraints:**
- Generate 3-5 cards; if data insufficient, create a minimal two-card story.
- If generation fails, fall back to the weekly summary; avoid sensitive details in share output.

---

## Prompt 8: Ritual Circles

**`/dev-pipeline`**

**Feature:** Ritual Circles (`kimispecs/08-ritual-circles-spec.md`)

**Context:** Synchronized 3-5 minute rituals with shared timer, prompts, and recap posts.

**Implementation Focus:**
- Tables `circle_rituals`, `circle_ritual_attendees`, `circle_ritual_reflections` with RLS.
- Edge Functions `create-circle-ritual`, `join-circle-ritual`, `complete-circle-ritual`.
- Realtime updates or polling for ritual state; push invites via `send-notification`.
- UI for ritual scheduling card, shared timer screen, and recap post with reflection input.
- Tests for prompt sequencing, attendance tracking, and recap creation.

**Constraints:**
- Members can join within 2 minutes of start and jump to current step.
- Reflection text max 140 characters; if no attendees, skip recap.

---

## Prompt 9: Partner Mode UX

**`/dev-pipeline`**

**Feature:** Partner Mode UX (`kimispecs/09-partner-mode-ux-spec.md`)

**Context:** User-facing partner linking, sharing preferences, and shared activities built on existing buddy data.

**Implementation Focus:**
- Use RPCs `generate_buddy_code` and `accept_buddy_invite` for onboarding.
- UI for invite/accept flow, partner dashboard, and sharing toggles (mood, streaks, quests).
- Shared exercise sessions and encouragement messages with notification delivery.
- Handle already-linked state and placeholders for non-shared data.
- Tests for invite validation, sharing persistence, and notification payloads.

**Constraints:**
- Invite codes must be time-limited and single-use.
- Never expose data without explicit sharing consent.

---

## Prompt 10: Private Vault Journal

**`/dev-pipeline`**

**Feature:** Private Vault Journal (`kimispecs/10-private-vault-journal-spec.md`)

**Context:** Local-only, encrypted journaling protected by biometrics and excluded from AI usage.

**Implementation Focus:**
- Local encrypted storage using CryptoKit AES.GCM with Keychain-managed keys.
- LocalAuthentication gating (Face ID/Touch ID with passcode fallback).
- UI for settings toggle, vault list, entry editor, and local search.
- Ensure vault entries never leave device and are excluded from AI prompts/analytics.
- Tests for encrypt/decrypt and key handling.

**Constraints:**
- No cloud sync or backups; if key missing, prompt reset with data loss warning.

---

## Prompt 11: Smart Notifications With Context

**`/dev-pipeline`**

**Feature:** Smart Notifications With Context (`kimispecs/11-smart-notifications-context-spec.md`)

**Context:** On-device prediction and context-aware notification timing with adaptive learning.

**Implementation Focus:**
- On-device ML model for engagement prediction with weekly updates.
- Context engine using calendar, location, biometrics, and focus modes.
- Notification queue, bundling, suppression, and scheduling logic.
- Settings UI for frequency, types, quiet hours, max per day, and beta opt-in.
- Engagement logging and feedback loop; tests for thresholding and bundling.

**Constraints:**
- Deliver only if predicted engagement >60 percent.
- On-device processing for context/biometrics; respect quiet hours and Sleep Focus.
- Crisis or urgent notifications bypass bundling and suppression.

---

## Prompt 12: Dynamic Content + Generative Audio

**`/dev-pipeline`**

**Feature:** Dynamic Content + Generative Audio (`kimispecs/12-dynamic-generative-content-spec.md`)

**Context:** AI-generated wellness content with voice synthesis, safety filters, and fast delivery.

**Implementation Focus:**
- Edge Function `generate-content` for text generation and orchestration.
- Voice synthesis integrations (ElevenLabs/Play.ht) and audio assembly/mixing.
- Content validation filters, clinical review workflow, and user flagging.
- SwiftUI request UI, content library, and playback integration with caching/rate limits.
- Tests for latency, audio quality, and safety guardrails.

**Constraints:**
- Label AI content and show disclaimers.
- 44.1kHz minimum audio quality; generation under 30 seconds.
- Clinical review required before publication; fallback to curated content if generation fails.

---

## Prompt 13: Community-Driven Content + Creator Economy

**`/dev-pipeline`**

**Feature:** Community-Driven Content + Creator Economy (`kimispecs/13-community-driven-content-creator-economy-spec.md`)

**Context:** Verified creators publish content with marketplace discovery and revenue sharing.

**Implementation Focus:**
- Creator onboarding and verification, including credential checks and background screening.
- Data models for creators, content pieces, subscriptions, reviews, and payouts with RLS.
- Creator portal for uploads, analytics, payout settings; marketplace discovery UI.
- Clinical review queue and rating system; Stripe Connect payouts.
- Tests for onboarding, review workflows, and revenue calculations.

**Constraints:**
- Verified creators only; clinical review SLA 7-14 days.
- 70/30 revenue split; proper licensing and attribution required.

---

## Prompt 14: Advanced Integrations

**`/dev-pipeline`**

**Feature:** Advanced Integrations (`kimispecs/14-advanced-integrations-spec.md`)

**Context:** Deep ecosystem integrations across calendar, email, smart home, travel, wearables, APIs, and FHIR.

**Implementation Focus:**
- Integration manager with OAuth flows for calendars, email, TripIt, and smart home vendors.
- On-device email tone analysis and calendar-based stress prediction.
- Smart home automations (HomeKit/Nest/Ecobee) with explicit user confirmation.
- Public REST API with OAuth2, rate limits, and developer docs; FHIR R4 mapping.
- Tests for OAuth flows, stress predictions, and API rate limiting.

**Constraints:**
- HIPAA compliance for FHIR endpoints and audit logging.
- OAuth vendor verification required; rate limits free 100/day, paid 10k/day.
- On-device processing for email tone; user confirmation before smart home actions.
