# MindFriend 2.0.0 release record

This file records the 2.0.0 release work: the crisis-send fix, branch cleanup, three bugs reported on the App Store build (habit reminders, the Night Owl badge, buddy invites), the side-by-side audit against 1.0.5, the return of per-area color, release checks and the Release archive. Times are US Eastern.

## Phase 0: Inventory (13 November 2026, 8:09 PM EST)

### Repository
- `origin/main` head `aebbd71` (Merge PR #99, `chore/ios-build-202611091532`). CI run 42697488778 on that commit succeeded.
- `MARKETING_VERSION = 2.0.0`, `CURRENT_PROJECT_VERSION = 202611091532` (both app-target configurations; the other targets inherit).
- Open pull requests: none.
- Remote branches: `chore/ios-build-202611091532`, `fix/ios-device-round` (both fully merged), `fix/review-2.0.0` (one commit ahead, `6407cee`), and `wip/bound-pending-celebrations` (pushed by this run, see below).

### Uncommitted work found and preserved
The local checkout was on `fix/review-2.0.0` with uncommitted changes that existed nowhere else: `AppState.addCelebrations` presents only celebrations under 48 hours old and each id once, migration `20261111090000_bound_pending_celebrations.sql` marks the pre-2.0 backlog and streak milestones as shown and bounds `get_pending_celebrations` to the same window, plus `supabase/tests/pending_celebrations.sql` and a client test. Without it, the first 2.0 launch replays every milestone since sign-up, because no release before 2.0 marked one as shown. Committed unchanged as `2e864c2` on `wip/bound-pending-celebrations` and pushed.

### Earlier 2.0.0 record
An earlier release record with this filename exists only on the local branch `docs/release-2.0.0` (3 commits, 9 November, last `937a5a5` "docs: record the 2.0.0 device round (#98)"); it never reached `main`. It is preserved as tag `archive/docs/release-2.0.0` on GitHub and covers builds 202611091157 and 202611091532. This file records the 13 November run.

### The facts handed over, re-checked

| Fact | Result |
|---|---|
| PR #81 `feat/theme-foundation`, "one navy theme for every screen reached from the shell" | Confirmed (merged 9 Nov, 4:17 AM EST) |
| `SupportTheme` accent `0x3557B7` light / `0x9BB5FF` dark; one other hue, gold, for reward moments | Confirmed (`SupportShellComponents.swift:716`, `:730`). There is also a reward `glow` (`0xC9D7FF`/`0x3E5A9E`), a tint of the same blue |
| PRs #90 to #97 re-skinned Today, Explore, Chat, People, You and Settings | Confirmed (#90–#93 are the four lanes; #94–#97 are follow-ups) |
| Files using `Color.<name>` or a gradient: 231 at `ee886e1`, 75 on main; gradient uses 182 → 59; named color uses about 465 → 151 | Confirmed exactly with `Color\.(red|orange|…|brown)` and `(Linear|Radial|Angular|Elliptical)Gradient`. Counting shorthand `.blue`-style uses as well gives 430 → 236 files and 2,364 → 984 uses |
| Listed screens lost all or most color | Confirmed for every one named, e.g. `OrbView` 11 → 0, `VoiceModeView` 32 → 2, `QuestArcMilestoneView` 23 → 0, `WelcomeBackView` 17 → 0, `FeatureUnlockView` 17 → 0 (shorthand and `Color.` uses plus gradients). `ThoughtRecordView` counts 11 → 1 and `SafetyPlanCondensedView` 9 → 3 with that pattern |
| Legacy shell kept as rollback behind `mf.supportShell.enabled`, on by default | Confirmed (`SupportShellComponents.swift:13`) |
| `fix/review-2.0.0` at `6407cee`, 11 Nov, no PR, carries a `Co-Authored-By` trailer | Confirmed |
| Sentry has never received an event from 202611091532; newest 2.0.0 build seen is 202611091157 | Confirmed: the only 2.0.0 release is `com.mindfriend.app@2.0.0+202611091157` (events 9 Nov, 12:58–3:23 PM EST) |
| Archive and upload status of 202611091532 unknown | Differs in part: `~/Library/Developer/Xcode/Archives/2026-11-09/MindFriend 2.0.0 (202611091532).xcarchive` exists, so it was archived. Upload status is still unknown |

### Production facts for the three reported bugs (read-only, 13 November)
- `habits.reminder_time` is `time with time zone`; 0 of 2 habits have a reminder.
- `profiles.timezone` defaults to `'UTC'`; 22 of 24 profiles are `'UTC'`.
- Night Owl ("Complete an activity after midnight") was earned at 7:48:54 PM EST tonight by a `'UTC'` profile. Earlier awards on `'UTC'` profiles also fall in the evening Eastern (for example 10:04 PM, 9:42 PM, 7:13 PM), and Early Bird at 12:01 AM and 1:58 AM.
- Invite `CYK4GF` was created at 7:44 PM EST with `invite_method = sms`, status `pending`. Differs from the brief: there is one row for it, not two (see Phase 2).

### CI scope
CI's iOS job runs a fixed list of test classes; `DeepLinkNavigationTests` and the chat tests are not in it, so they are run locally for each change below.

### Local environment notes
- The `default` colima VM rejected its own SSH key and would not start (8:16 PM EST onward). It was left untouched; this run uses a separate colima profile, `mfci` (4 CPUs, 6 GiB, 30 GiB disk). Colima switched the default Docker context to `colima-mfci`.
- The internal disk was 98% full (22 GiB free). The three DerivedData folders left in `artifacts/release-1.0.6/` (15.6 GiB, regenerable build output) were removed, leaving 36 GiB.
- During Phase 3 the disk filled again (1.4 GiB free, 9:10 PM EST). Removed, all regenerable build output: this run's `build/dd-main` (5.7 GiB, a duplicate of `build/dd-audit20`), and two Xcode DerivedData folders whose source path no longer exists on this Mac (`MindFriendApp-dpnyttwf…`, no project path, 3.5 GiB; `MindFriendApp-ffzxvzcg…`, `/Users/danny/…`, 3.8 GiB). Kept: the DerivedData for this checkout and for `.worktrees/device`. 14 GiB free afterwards.

## Phase 1: Crisis send fix and cleanup

- `fix/crisis-send-when-quota-spent`: `6407cee` reapplied on `aebbd71` as `054ea90`, same diff, message without the trailer. PR #100.
- Local tests (iPhone 17 Pro simulator, iOS 27.0): `DeepLinkNavigationTests` 30 (including `testSendingStaysAvailableWhenTheFreeQuotaIsSpent`), `ChatViewModelTests` 14, `SafetyPlanTests` 2, `SupportNavigationTests` 21. 67 passed.

## Phase 2: The three reported bugs

### 1. Creating a habit with a reminder fails (PR #101)
- **Root cause.** Every released client (1.0.4, 1.0.5, 2.0; supabase-swift 2.55.4; `Habit` unchanged since 1.0.5) sends `reminder_time` as `"2026-11-13T13:30:00.000"`, a UTC date-time without a zone. Checked against production with a read-only `SELECT`: `timetz` and `time` both reject it. A `timetz` value (`13:30:00+00`) would not decode into a `Date` either, so the read path was broken too.
- **Choice.** `habits.reminder_time` and `routines.target_time` become `timestamptz`. It accepts the released payload unchanged (the database is in UTC, the zone the client wrote) and returns `2026-11-13T13:30:00+00:00`, which the released decoder reads. The app takes the hour and minute of that instant in the device zone, so the reminder keeps its local time across DST. A client-only `HH:mm:ss` encoding was rejected because 1.0.4 and 1.0.5 would stay broken until people update; changing to `time` was rejected because `time` rejects the payload as well. No server function or view reads these columns (checked `pg_proc` and views in production).
- **Other `Date` values in time columns.** `routines.target_time`: same migration (`createRoutine` has no callers; 0 rows). Left alone, with reasons: `routine_templates.target_time` (never fetched by the app); `coach_settings.silent_hours_*` (`CoachSettingsView` is only reached from a `#Preview`, 0 rows, and `chat` parses the column as `HH:MM:SS`). `sleep_goals` already encodes `HH:mm:ss`; every other time column is a `String` in the app.
- **Tests.** `supabase/tests/habit_reminders.sql` sends the exact 1.0.5 body through `json_populate_record`. Without the migration: `invalid input syntax for type time with time zone: "2026-11-13T13:30:00.000"`, the production error. With it: 15 of 15 suites pass and the reminder reads back as 08:30 New York. `HabitReminderWireTests`: encode with the client's PostgREST encoder, reload (the `timetz` body fails, the `timestamptz` body round-trips), daily trigger 8:25 AM New York, also in July.

### 2. Night Owl awarded at 7:48 PM EST (PR #102)
- **Root cause.** The app never wrote the device zone, so 22 of 24 profiles keep the `'UTC'` default, and `check-badge-progress` treated 00:48 UTC as after midnight. `_shared/time-badges.ts` used `getUTCHours`, but nothing imported it. A second bug: `Intl.DateTimeFormat(..., { hour12: false })` formats midnight as `"24"` in en-US, so 12:xx AM local missed Night Owl even with a correct zone.
- **Fix.** The app writes `TimeZone.current.identifier` at account start (launch and sign-in), on foreground and on `significantTimeChangeNotification` (posted on a zone change), only when it differs from the last value written. `_shared/local-time.ts` gives the hour 0 to 23 and treats `'UTC'` or an invalid zone as unknown; Night Owl and Early Bird are never awarded while unknown. Earned badges are not revoked. Released 1.x clients never sync, so they never get a time-of-day badge at the wrong hour.
- **Audit of other UTC day boundaries** (read-only sweep of `supabase/functions` and the latest definition of each SQL function). Fixed:
  - `update_journal_streak` (read its own `'UTC'` copy of the zone), `update_micro_streak`, `complete_recovery_quest`, `get_home_context(uuid)`, `get_buddy_widget_data` (`CURRENT_DATE`). The migration reads each live definition and replaces only the date expression, raising if the expected text is missing.
  - `user_settings.timezone` (all 24 rows `'UTC'`), read by `find_streak_risk_users`, `send-assessment-reminders`, `check-intervention-triggers` and `get_prediction_eligible_users`: now follows `profiles.timezone` through a trigger.
  - `assign-quest`: capacity lookup and milestone posts use the local date. `generate-daily-briefing`: mood prediction and last night's sleep use the request's `local_date`.
- **Left as is, on purpose:**
  - The free chat quota resets at UTC midnight. That is a documented contract mirrored in the client (`Constants.swift`, `EntitlementSnapshot.nextServerReset`, `testServerQuotaDayResetsAtUTCMidnight`), and changing it needs a coordinated client release.
  - Other UTC-day quotas and daily limits (creative, image, voice journal, synthesis, hugs, buddy invites), `award-xp` daily XP and week start, and UTC weekly stories (also mirrored in the client). These are consistent, low-impact counters.
  - `chat`'s relative-time parser ("tomorrow at 2pm") and the wisdom and preference time tags still use the UTC runtime clock. Fixing them means threading the zone through the chat pipeline; recorded as a follow-up.
- **Tests.** `_shared/local-time.test.ts`: 3 of 4 fail with the previous logic, 4 of 4 pass with the fix. `supabase/tests/local_day_boundaries.sql` picks UTC+14 or UTC-11 so the local date always differs from the UTC date; it fails without the migration and passes with it. `TimeZoneSyncTests`.

### 3. Buddy invite says sent, nothing arrives (PR #103)
- **Root cause.** Production has one row for `CYK4GF` (created 7:44 PM EST, `sms`), not two. The app inserts the invite, then calls `send-buddy-invite`, whose duplicate check finds that same row and returns before any send code runs. SMS was a log-only stub, and production has no `RESEND_API_KEY` (checked by secret name), so no invite of either kind was ever sent. A second row with a different code appears only when an email's letter case differs. The app ignored the function's result and showed "Invite Sent!". `getmindfriend.app/buddy/<code>` returned 404, the app had no place to type a code, and `accept_buddy_invite` returns one composite row, which PostgREST sends as an object while every released client decodes an array. Accepting linked both people and then reported failure.
- **Fix.** 2.0 sends the invite from the phone (Messages for text, Mail for email, the share sheet otherwise) and shows "Invite sent" only when it really went out; otherwise it offers to share the code. A code from a friend can be entered in the same sheet. `send-buddy-invite` uses the row the app passes (`relationshipId`, sent by every released client) instead of making a second one. `accept_buddy_invite` returns `SETOF`, so 1.0.4 and 1.0.5 accept successfully without an update, and accepting expires other pending invites from the same inviter to the same contact. The website gains `/buddy/<code>`.
- **Tests.** `supabase/tests/buddy_invites.sql` fails before the migration and passes after. `BuddyInviteMessageTests`.

### Production-copy dry run (13 November, 8:38 PM EST)
- Schema-only dumps of production taken 8:36 to 8:38 PM EST into `.recovery/release-2.0.0/` (zero `INSERT`/`COPY` lines; SHA-256 `78c4885b…` public, `b293f8b6…` managed).
- Runner: `artifacts/release-2.0.0/prod_copy_dryrun.py`, the 1.0.6 runner with tonight's dumps and the ledger head `20261109101500`. Network-isolated `supabase/postgres:17.11.0.006`, synthetic `NOLOGIN` roles.
- Local integration ref `dryrun/2.0.0-server` (`7a32c24`, PRs #101 to #103 on `main`): 3 of 3 pending migrations applied. On the copy, `habit_reminders.sql`, `local_day_boundaries.sql` and `buddy_invites.sql` pass. On a fresh chain, all 17 CI suites pass.

### Merged (Phases 1 and 2)
- PR #100 (`f307c16`), #101 (`70a3405`), #102 (`51237e0`). PR #102's first SQL job failed before running any SQL (the runner could not create the Postgres container); the rerun passed.
- Phase 1 cleanup: `archive/fix/review-2.0.0` pushed at `6407cee`; remote `fix/review-2.0.0`, `fix/ios-device-round` and `chore/ios-build-202611091532` deleted.

### Before the production deploy
- Logical backup of production (roles, schema, data, managed schema and managed data) into `.recovery/release-2.0.0/backup-20261113-220848-EST/`, with `SHA256SUMS`, taken 10:08 to 10:10 PM EST.
- Website: `getmindfriend.app/buddy/<code>` still returns 404. Release archive `artifacts/release-2.0.0/website-20261113.tar.gz` (SHA-256 `731c8d68…`, 11 files including `buddy/index.html`, manifest alongside) and the Caddy rewrite are ready. Connecting to the web server over SSH was denied by this session's permission policy, so the site deploy is left for the owner (steps in `landing-page/deploy/README.md`: verify the manifest, unpack to a new release folder, install the updated Caddyfile, `caddy validate`, switch `current`, restart `mindfriend-site.service`, then check `/buddy/CYK4GF`).

## Phase 3: Side-by-side audit against 1.0.5 (PR #104)
- 1.0.5 (`ee886e1`, worktree `.worktrees/v105`) and 2.0 (`main` at `f307c16`) were built for two separate iPhone 17 Pro simulators (iOS 27.0).
- Both pointed at a local Supabase stack (`supabase start`, all migrations including tonight's three) through command-line build settings; no project file changed.
- Test account: a local-only email account, credentials in the ignored `artifacts/release-2.0.0/audit-seed/credentials.env`. Seeded content: 14 days of moods, 3 journal entries, 6 completed quests, level 4 with 640 XP, a 6-day streak, 2 habits and a premium subscription row. 22 catalog tables (exercises, sleep content, coping kits, badges, programs and others; no user columns, checked per table) were copied read-only from production with `pg_dump --table`.
- Local-only fixes needed: the `auth.users` trigger that runs `handle_new_user` lives in the platform schema and is not in the migrations, so the account's `user_settings` row and profile `handle` were added by hand. Sentry was disabled in the audit builds.
- Navigation: a temporary, uncommitted XCUITest drives the app; a file handshake lets `xcrun simctl io screenshot` capture each stop in light and dark at the default size and at accessibility-large.
- Result: `docs/ux/2.0-vs-1.0.5/README.md`, 19 screens and 152 images.
- Findings beyond color:
  - Coping kits have no entry point in either version (`CopingKitsView` is only created in a `#Preview`).
  - 2.0's support shell never shows the welcome-back sheet; only the legacy `HomeView` calls `showWelcomeBackModal`.
  - Voice could not connect on the local stack (no voice provider keys).
  - 1.0.5's journal list could not read the synthetic entries.

### Production deploy (13 November, 10:21 PM EST)
- PR #103 merged (`5f378cf`), then PR #105 (`046a09b`, tokens only, no server change). Deployed from a clean worktree at `origin/main` `046a09b`.
- `supabase db push --linked --dry-run` listed exactly the three expected migrations. Applied 10:21:09 to 10:21:11 PM EST:
  - `20261113210000_habit_reminder_instant`
  - `20261113211000_local_day_boundaries`
  - `20261113212000_buddy_invite_accept_returns_rows`
- **Read-only checks afterwards:**
  - `habits.reminder_time` and `routines.target_time` are `timestamptz`, and the 1.0.5 payload reads back as 08:30 New York.
  - `accept_buddy_invite` returns a set; `authenticated` can execute it and `anon` cannot.
  - `user_time_zone` is not executable by `authenticated`.
  - The journal, micro-moment, recovery, home-context and buddy-widget functions use the local date, and `tr_mirror_profile_timezone` exists.
  - Ledger head is `20261113212000`.
- **Edge functions** (same `verify_jwt` as before: `false` for the first three, `true` for `send-buddy-invite`):
  - `check-badge-progress` v34 → v35
  - `assign-quest` v41 → v42
  - `generate-daily-briefing` v19 → v20
  - `send-buddy-invite` v26 → v27
  - All four answer `OPTIONS` with 200.
- **Live for people on 1.0.4 and 1.0.5 now:**
  - Habit reminders save and reload.
  - Night Owl and Early Bird are no longer awarded on the `'UTC'` default.
  - Accepting a buddy code no longer reports a failure after linking.
  - An email invite sent through the function, if a Resend key is ever configured, carries the on-screen code.
- **Ships with the 2.0 app:** the time zone sync, which makes local days and time-of-day badges personal, and sending invites from the phone.
- **Not live:** the `/buddy/<code>` web page (site deploy left for the owner, see above).

## Phase 4: Color and personality back, on 2.0's structure

### Tokens (PR #105, merged `046a09b`)
`SupportTheme.Area` holds ten areas with the hue 1.0.5 used for each (evidence: a read-only sweep of `ee886e1`).

| Area | Hue from 1.0.5 |
|---|---|
| sleep | indigo, with purple |
| copingKits | pink |
| journal | purple |
| voice | blue, with purple |
| exercises | cyan, with blue |
| quests | orange, with yellow |
| insights | green |
| people | pink, with purple |
| safety | blue, with cyan |
| sensory | teal |

- **Per area:** `ink` (icons, rings, chips and short text), `tint`/`tintEnd` (behind body text) and `deep`/`deepEnd` (hero gradients under white).
- **Shared:** `Status.positive/caution` and `Hero` gradients (level up, streak, badge, unlock, welcome back, calm).
- **Increase Contrast:** ink moves 25% toward black in light mode and 35% toward white in dark mode; hero stops darken 20%.
- **Reserved:** the accent stays the primary action color and red stays for crisis.
- **`AreaColorContrastTests`** (added to CI) resolves every token in light, dark and both with Increase Contrast:
  - ink on canvas, surface and tints: 4.5:1 or more;
  - primary and secondary text on tints: 4.5:1 or more;
  - field border on tints: 3:1 or more;
  - white on hero stops: 4.5:1 or more;
  - Increase Contrast strengthens ink, and no ink is in the crisis red band.
  
  The first run caught the border on the dark quests tint at 2.89:1, so that tint was deepened.

### Screens (PRs #106 to #109)
Four implementation lanes ran in parallel on disjoint files, each in its own worktree off the tokens commit, and none built on its own (disk). They were integrated and built together, then each rebased onto `main` as its own PR.
- **#106, hero moments:** orb state colors on tokens (error is caution, not red), the orb back on the Talk by voice panel, celebration styles per type, feature unlock, coping kit detail/step/completion, quest milestone and arc completion, welcome back.
- **#107, Today, Explore and destinations:** `SupportDestination.area`, area icon tiles, soft-gradient category cards, the quests tint on Today's quest card, and an area strip under destination headers.
- **#108, wellness:** sleep (night wash, story/soundscape/routine gradients, player), sensory, the exercise library and players (category and breathing-phase colors), generated stories, journal analysis.
- **#109, meaning and safety:**
  - Wellbeing debt deposits are positive and withdrawals caution.
  - Insights and reports use positive and caution plus the area palette.
  - Pattern severity no longer uses red; circles have their member colors.
  - Safety plan and SOS: color swaps on icons, progress and selection only. Reviewed line by line; no crisis action, label, order, size, hit target, red element, phone or SMS link, or entry point changed.
- **Reduce Motion:** no looping motion. **Reduce Transparency:** solid fills instead of glows and translucent layers.

### Tests
- **Integration build, full iOS unit suite plus `MindFriendAppUITests`:** 1,651 tests, 68 failures.
- **Unmodified `main` (`51237e0`), same command:** 1,649 tests, 68 failures, an identical failing set. These failures are pre-existing, outside CI's fixed list, and include a `fatalError` in `TransitionServiceTests`; they are for Phase 6.
- **Contrast tests:** pass.
- **Visual check:** the after captures at accessibility-large show no clipping on Today or Explore.
- Merged: #106 `a2beb9a`, #108 `d6d3231`, #107 `cfdd614`, #109 `800da60` (all checks green). The lanes touch disjoint files.
- Full suite on merged `main` (`800da60`): 1,654 tests, 1,583 passed, the same 68 pre-existing failures as the baseline, none new.

## Phase 5: Re-capture
- The "after" set was captured from `main` at `800da60` on the same simulator, account and content: `docs/ux/2.0-vs-1.0.5/after.md`, 18 screens in four variants each.

## Review follow-ups (PR #111, merged `545b9e7`)
The automated review on #102 and #103, which arrived after both had merged, raised eight findings. All eight were valid and fixed:
- Streaks treat a last date on or after local today as today, so the switch from the UTC default never resets one.
- `get_home_context` converts activity timestamps to local time before taking the date.
- `predict-mood` stores the local date the briefing asks for.
- The app compares its zone with the profile's current value, so two devices on one account can't leave the wrong zone.
- `local_day_boundaries.sql` picks its fixture zone by date, so it no longer fails from 11:00 to 11:59 UTC.
- The contact lookup escapes LIKE wildcards.
- Invite emails go only to the stored address, at most 10 a day through `check_rate_limit`.
- The buddy hub reloads after the sheet closes.

Tests and checks:
- Production-copy dry run on a schema-only dump taken after the first deploy (ledger head `20261113212000`): 1 of 1 applied, and both SQL suites pass on the copy.
- Fresh chain: 17 of 17. The new streak assertion fails without the migration.
- Deno 5 of 5; iOS 74 tests.
- Replies posted and all eight review threads resolved.

Deployed 11:59 PM EST: migration `20261114000000_local_day_follow_ups` (ledger head verified), `predict-mood` v22 → v23 and `send-buddy-invite` v27 → v28 (`verify_jwt` unchanged, `OPTIONS` 200). Read-only check: the journal, micro-moment and home-context definitions carry the changes.
- Review of #111 found that a future streak date counted as today but stayed stored, so the next local day's entry could not extend the streak. PR #112 (merged `ffc5b1e`) sets the stored date to `LEAST(stored, local today)` in that branch. The test now checks that the next day takes the streak from 5 to 6; it fails without the fix, and 17 of 17 suites pass with it. The production-copy dry run (ledger head `20261114000000`) applied 1 of 1 and passed. Migration `20261114010000_normalize_streak_dates` was applied to production at 12:23 AM EST on 14 November, and the ledger head and both definitions were verified.

## Phase 6: Release checks (26 November 2026, from 8:24 PM EST)
The run resumed from the Phase 5 stop with the go-ahead for Phases 6 and 7. `main` was at `ffc5b1e` (PR #112). The local checkout was 27 commits behind; its untracked copies of `docs/ux/` matched `main` byte for byte, and this file held the PR #111 and #112 section above, which existed only locally. The temporary audit navigator (an uncommitted UI test helper) was removed from the checkout and kept as `artifacts/release-2.0.0/handover/uitest-capture-helper.patch`.

### Environment
- The test simulator used through Phase 5 (`73EBCB3C…`) had lost its data folder, so every test ran on a new iPhone 17 Pro simulator, iOS 27.0 (`16F4BF13…`). `build/` was gone, so builds started cold.
- Docker: colima profile `mfci` restarted.

### Server parity (read-only)
- **Migrations.** Production's ledger has 269 versions, head `20261114010000`. Every `.sql` migration on `main` is in it. The four other files under `supabase/migrations` end in `.disabled` and are never applied.
- **Edge functions.** Of the 213 functions on `main`, 133 are referenced by the app. All 133 are deployed. `chat` (v56), `verify-purchase` (v37), `voice-token` (v51), `test-auth-diagnostic` (v25), `support-session` and `analyze-voice-journal` were deployed after their last change. 88 were deployed before their last change on `main`.
- **Why 88 were behind.** 1.0.6 deployed "functions changed since `ee886e1`" (65 functions). The 5 November restoration commits (`ed5e6ee9` `Deno.serve` and supabase-js 2.118.0, `ce839d51`, `c8f15953`, `201e4cb2`, `968d57fa`, `758a321d`, `04fa4bb7`) predate `ee886e1`, so the functions they touched were never deployed. 1.0.4 (`8564715f`) and 1.0.5 (`ee886e1`) both contain those commits, so every supported client was built against this function code.
- **Review of the 88.**
  - Each production copy was downloaded (`supabase functions download --use-api`) and diffed against `main`.
  - 4 are identical in production and on `main`: `manage-safety-plan`, `flag-content`, `generate-weekly-story` and `voice-session-end`.
  - In about 41, the function's own code differs only by the `serve` to `Deno.serve` switch and supabase-js 2.49.1 to 2.118.0; many of those also bundle a changed shared file.
  - The rest add types, use the shared CORS helper, drop `debug` fields from error bodies, or pick up shared changes: `auth.ts` validates tokens with the admin client, `isAuthorizedCronRequest` is async (every caller awaits it), and `rate-limit.ts` takes an optional window.
  - `ratelimit.ts` already failed closed on an RPC error in production. Only its empty-result branch changed, and that branch cannot be reached because `check_rate_limit(uuid, text, timestamptz, integer, integer)` always returns one row. Production has that RPC, executable by `service_role` only, and every caller passes the service-role client.
  - All 82 type-check (`deno check`) from a clean export of `ffc5b1e`. `config.toml` agrees with production's `verify_jwt` for all of them.
- **Not deployed, on purpose:**
  - `therapist-invite`: `main` writes `therapy_connections.invitation_token_hash`, which no migration creates, and requires `JWT_SECRET`, which production does not set. The deployed copy signs invitation tokens with the literal fallback `"your-secret-key"`. Recorded as open.
  - `get-session-history`: the app does not call it.
  - `match-support-session`: held by the owner's decision. It fails to start in production today, so peer support matching, including the `crisis_bridge` session type, has never run. Deploying it would turn matching on for every released client; that gets its own review and test first.

### Review of the deploy plan
- The cross-vendor review could not run: Codex was out of quota until 29 November, 9:04 AM EST, the Antigravity account needed verification, and Grok was not signed in. By the owner's decision, an independent Claude reviewer (fresh context, read-only, Sonnet; an Opus attempt was stopped by a safety filter) reviewed the exact plan, diffs, production schema, secret names and iOS call sites.
- Verdict: deploy with changes. It found no new table, column, RPC, bucket or secret dependency and no change that breaks a released client (every function folder is byte-identical at `8564715f`, `ee886e1` and `main`, apart from `check-badge-progress`). Changes adopted:
  - The post-deploy check compares each function with its own pre-deploy responses instead of a fixed status, because 17 functions answer `OPTIONS` with 401, 405, 500 or 503 today.
  - The rollback copies were completed (two type-only files were missing), each deploy first checks that production still runs the downloaded bundle, and the rollback was rehearsed on `public-config` (redeploying its production copy, v10 to v11, same responses).
  - Server-side bundling (`--use-api`) for deploy and rollback, since colima does not mount the scratch folder.
  - `send-notification-batch` deployed last, by the owner's decision: production compared Swift's uppercase ids with lowercase database ids, so circle and challenge pushes never went out. They start now.

### Function deploy (26 November 2026, 10:18 to 10:25 PM EST)
- Source: a clean worktree at `ffc5b1e`, one function per command, `--project-ref zfaucivtzfwnrijsbfug --use-api`, `--no-verify-jwt` for the 27 whose production setting is `false`. Order: least change first, a three-function canary, then the rest, then `send-notification-batch`.
- Checks per function: version advanced, `verify_jwt` unchanged, the bundle matched the downloaded copy before deploy, an `OPTIONS` request (and, for the 55 behind the JWT gateway, a signed-out `POST`) answered as before or became healthy. Functions without the gateway were not sent a `POST`, since several run scheduled work.
- Result: 81 of 81 deployed, none rolled back. Downloading the canaries and `send-notification-batch` back from production showed every file identical to `ffc5b1e`.
- Repaired by the deploy: `get-localized-strings`, `get-captions` (both failed to start: their copies imported `checkRateLimit` from a `cors.ts` that no longer exported it) now answer.
- Logs from 10:18 PM EST: no new errors, and no signed-in traffic yet by 10:45 PM EST, so the first real requests are worth a look the next day. The only errors are the two that existed before and are recorded as open: `submit-content` throws on a request without an `Authorization` header, and `contribute-wisdom` cannot start because `WISDOM_HASH_SALT` is not set in production.
- Audit afterwards: every function the app calls now runs `main`'s code, apart from `therapist-invite`, `get-session-history` and `match-support-session` (above). The four identical functions keep their older deploy dates.

### Security fix in production
- The deployed `b2b-stripe-webhook` (v27, `verify_jwt = false`) skipped Stripe signature verification when `TEST_WEBHOOK_BYPASS_AUTH` was `"true"`, and the secret's digest matched `"true"`. Anyone could post a forged event to change any of the 18 organizations' billing status or churn one, which revokes sponsored Premium (1 member had it). `main` had removed the bypass, but the function was never redeployed.
- By the owner's decision, the secret was removed at 10:16 PM EST (`supabase secrets unset TEST_WEBHOOK_BYPASS_AUTH`). An unsigned test event of an unhandled type now gets `400 Invalid signature`. Production has no Stripe secrets, so nothing legitimate used the endpoint. Removing a secret starts a new version of every function; bundle hashes and deploy times were checked unchanged.

### Sentry
`CrashReporter.initialize` names the release `com.mindfriend.app@<CFBundleShortVersionString>+<CFBundleVersion>` and reads the DSN from `SENTRY_DSN`, which `Release.xcconfig` sets through Info.plist. The environment comes from the install, on purpose: App Store installs report `production`, TestFlight `testflight`, and builds installed from Xcode, devicectl or an ad hoc export `development`. A device test from Xcode therefore appears under `development`.

### Tests (PR #113, merged `d000f77`)
- **SQL:** CI's runner, 17 of 17 suites (on `ffc5b1e`, and again on merged `main` `d000f77`).
- **Deno:** CI's two commands pass (80, and 18 for `verify-purchase`), on `ffc5b1e` and again on merged `main` (`d000f77`), where 49 of the 50 other test files pass. Of the 50 other test files, 45 passed on `main`; four were repaired in #113 (stale fixtures for `refresh_user_entitlement`, a placeholder image, wrong arithmetic). `_shared/distortion-detection.test.ts` stays failing on purpose (7 of 23, as since it was written): passing it means retuning the detector inside `chat`, which changes coach behavior for every user and redeploys the function that carries the crisis check.
- **iOS:** the 68 failures outside CI's fixed list were all addressed. Six were app defects and are fixed: mood predictions never decoded (`predicted_for` is a DATE), quest progress could exceed 100%, ritual countdowns floored ("1h" for 2 h), a skipped dose did not end a medication streak, recovery mode's "< 1h" never showed, and fixed promos dropped cents (family plans also gain family sharing). The rest were stale expectations, unrealistic fixtures and clock-dependent tests.
- Final run of the archived content (`main` plus the build number, 10:43 PM EST): 1,646 unit tests and 6 UI tests, 0 failures, with the five StoreKit purchase probes left out because this simulator routes them to an Apple Account sign-in.
- Full unit suite with the fixes, first run: 1,648 tests, 2 failures. Both are `StoreKitPurchaseRegressionTests` purchase probes: on the new simulator StoreKit routes their purchases to an Apple Account sign-in instead of the local test session, and the cancelled sign-in surfaces as `cancelled`. `BillingService` and its tests are unchanged since they last passed. `MindFriendAppUITests`: 6 of 6 on a rerun (the first run's failure came from the freshly erased simulator).

### What's New in 2.0.0 (App Store text)
MindFriend 2.0 is a fresh start, built around four places: Today, Chat, Explore and You.

• Color is back. Sleep, journaling, exercises, quests, circles and more each have their own colors again, and the voice orb, celebrations and milestones glow.
• Today greets you by name and gives you one easy way to begin.
• Voice and text continue in the same conversation, and you decide what MindFriend remembers.
• Invite a buddy right from Messages or Mail, or enter a code a friend sent you.
• Habit reminders now save and arrive at the time you chose.
• Badges like Night Owl and Early Bird now follow your own time zone.
• Free plan: 30 chat messages a day. If you're having a hard time, you can still reach out for support after they're used up.
• Easier to read, with better contrast in dark mode and at large text sizes.
• Plus fixes for subscriptions, sleep, journaling and sign-in.

## Phase 7: The build
- PR #114 set `CURRENT_PROJECT_VERSION` to 202611262226 (26 November 2026, 10:26 PM EST) in both app-target configurations; `MARKETING_VERSION` stays 2.0.0. Merged as `8aebfb4`.
- A trial archive from the PR branch confirmed signing first: team provisioning profiles for the app, widgets and the Watch app and its complications.
- Release archive from `main` at `8aebfb4`: `~/Library/Developer/Xcode/Archives/2026-11-26/MindFriend 2.0.0 (202611262226).xcarchive` (archived 10:51 to 10:57 PM EST, 314 MB; app, widgets and Watch app signed for team 25H5DDPKAC). The archived app reports version 2.0.0 and build 202611262226, and its `SENTRY_DSN` is set. `Release.xcconfig` points at `zfaucivtzfwnrijsbfug.supabase.co`.
- Not uploaded and not submitted.

### Rebuild for the Peer Support entry (27 November 2026)
- The review of peer support matching found 0 listeners and 0 sessions in production and no way in any client to become a listener, so a person who opened Peer Support would wait for no one. PR #117 hides the entry from Explore, search, Today pins and the rollback shell's More, and `match-support-session` stays undeployed.
- Build 202611262226 predates #117, so it is superseded. This PR sets `CURRENT_PROJECT_VERSION` to 202611270015 (27 November 2026, 12:15 AM EST); `MARKETING_VERSION` stays 2.0.0.
- The 2.0.0 archive is cut from `main` after #117 and this PR merge, to `~/Library/Developer/Xcode/Archives/2026-11-27/MindFriend 2.0.0 (202611270015).xcarchive`. The checklist below applies to it.

### Physical iPhone test checklist
To install the archive: Xcode, Window, Organizer, select 2.0.0 (202611262226), Distribute App, then either Debugging (install the exported app from the Devices window; Sentry reports it as `development`) or TestFlight (Sentry reports `testflight`).

1. **First launch.** A fresh install opens on sign-in. After signing in, Today greets you by name. At most one older celebration appears.
2. **Sign-in.** Email and Sign in with Apple both reach Today; sign out and back in.
3. **A chat message.** A reply arrives, and Chat shows how many free messages are left.
4. **A crisis phrase.** A message about wanting to hurt yourself brings up the crisis resources, with working call and text actions (do not place the call).
5. **The SOS sheet.** The lifepreserver opens SOS from Today and from Chat; every action is present and readable.
6. **Voice mode.** The orb shows color and motion; a spoken question gets a spoken reply; ending the call leaves its text in the conversation.
7. **Coping kit to completion.** Known: no screen links to coping kits in this build (or in 1.0.5). Skip, and note it.
8. **A celebration.** Finishing a quest or exercise shows a colorful celebration; with Reduce Motion on, nothing loops.
9. **Habit with a reminder.** Create one a few minutes ahead, close and reopen the app, confirm it kept the time, and wait for the notification at that local time.
10. **Buddy invite by text and by email.** Messages and Mail open prefilled with the code and link; "Invite sent" appears only after sending; cancelling offers to share the code. Entering a friend's code links both of you. The `/buddy/<code>` page is not live until the site deploy.
11. **No Night Owl in the evening.** After launch (which saves the phone's time zone), an activity before midnight does not award Night Owl.
12. **Sandbox purchase and restore.** With a sandbox Apple Account, buy a plan; Premium unlocks. Delete and reinstall, then Restore Purchases; Premium returns.
13. **Paywall.** Opening a Premium feature shows the paywall with the plans and prices; closing it returns to where you were.
14. **Dark mode and large text.** In dark mode at the largest accessibility text size, check Today and Explore: nothing is cut off and every area keeps its color.
15. **Circle pushes (new since tonight's deploy).** A post or completed challenge in a circle notifies the other members.

## Close-out (26 November 2026)

### Merged in this run
PRs #100 to #112 (Phases 1 to 5, above), #113 (test fixes and six app defects), #114 (build number) and #115 (this record). No pull requests are open.

### Production changes in Phases 6 and 7
- 10:16 PM EST: `TEST_WEBHOOK_BYPASS_AUTH` removed.
- 10:18 to 10:25 PM EST: 81 edge functions deployed from `ffc5b1e`, one by one, none rolled back.
- No migrations were needed; no other secret or setting changed.

### Still open
- **Peer support matching** (`match-support-session`): held, and its entry point is hidden in 2.0 (#117). It fails to start in production; production has no listeners and no way to become one. Turning it on needs listener onboarding and vetting, and a review of `crisis_bridge`, first.
- **`therapist-invite`**: resolved 27 November 2026. PR #116 (`218674b`) adds `therapy_connections.invitation_token_hash` and a check that keeps `invitation_token` NULL, so the old copy can no longer store a raw token. After a production-copy dry run (1 of 1 applied, `therapist_invitations.sql` passes), from 12:27 to 12:29 AM EST: migration `20261126234000` applied (ledger head verified), a random `JWT_SECRET` set (every function's version advanced by one, bundles unchanged), and `therapist-invite` deployed v27 to v28 from `218674b` (`verify_jwt` unchanged, responses as before, files identical to `main`). Invitation tokens are now signed with a real secret and only their SHA-256 hash is stored. The feature still cannot complete end to end: production has no therapist accounts and no `RESEND_API_KEY`, and neither `therapist-accept` nor the `/therapist/accept` page is deployed.
- **`therapy_connections` writes**: tightened 27 November 2026 (PR #120, migration `20261127073000`, applied 3:07 AM EST after a production-copy dry run; ledger head, policies and grants verified). A client can only change their own connection's sharing settings and revoke or end it; clients no longer insert connections, therapists no longer update them, and `anon` has no access. `therapist_assignments`, `therapist_notes` and `therapy_access_log` followed (PR #121, migration `20261127085500`, applied 4:34 AM EST after a production-copy dry run; verified read-only): `anon` has no access, a client updates only an assignment's status, completion time and notes, therapists write none of them directly, and the access log is read-only. Still open: completing an assignment fails in released builds because the app sends `completedAt`/`clientNotes`, which PostgREST rejects (`PGRST204`); skipping works.
- **`contribute-wisdom`** cannot start: `WISDOM_HASH_SALT` (and `WISDOM_HASH_PEPPER`) are not set. **`submit-content`** returns 500 instead of 401 without an `Authorization` header.
- **Missing tables and columns** referenced by deployed functions, identical before and after the deploy (from the review): `rewrite_history`, `sleep_logs`, `chat_action_cards`, `card_analytics`, `circadian_rhythm_data`, `healthkit_sleep_data`, `hsa_fsa_records`, `analytics_events`, `device_tokens`; columns such as `subscriptions.tier`, `vacation_mode.streak_on_activation`, `profiles.xp`, `messages.is_rewritten`, `family_alerts.family_group_id`. Each needs confirming before a fix.
- **33 functions the app does not call** are older in production than on `main` (including `log-crisis-event`, `b2b-stripe-webhook`, `email-webhook`, `validate-invite-code`); a separate audit.
- **Cross-vendor review of the deploy**: blocked tonight (Codex quota resets 29 November, 9:04 AM EST). Run it on the deployed set.
- **Website**: the `/buddy/<code>` page (package `artifacts/release-2.0.0/website-20261113.tar.gz`).
- **From Phase 5**: coping kits have no entry point; the welcome-back sheet is not shown in the 2.0 tabs; `wip/bound-pending-celebrations` is unmerged (production has 3 unseen old celebrations, one each for three people, so 2.0's first launch shows at most one).
- **Tests**: `_shared/distortion-detection.test.ts` (detector calibration inside `chat`); `DailySignals.signalDate` would fail on a Postgres DATE the same way `MoodPrediction` did, but `fetchDailySignals` has no caller; the purchase tests need a simulator whose StoreKit routes to the local test session; four repaired Deno files and most iOS classes are still outside CI's fixed list.
- **Defaults to decide**: prediction settings allow biometrics, sleep data and check-ins by default once someone turns predictions on (server and app agree).

### Workspace
- Removed: worktrees `p6`, `fndeploy`, `p7`, `archive`, `device`, `release-doc` (its commits are on GitHub as tag `archive/docs/release-2.0.0`), `final` and `v105`; their only uncommitted changes, the screenshot helpers, are kept in `artifacts/release-2.0.0/handover/`. Merged branches deleted locally and on GitHub. The `build/` caches from this run (about 12 GiB, rebuildable) were removed after the archive.
- Kept, because they exist only on this Mac: worktree `lanes-all` (branch `local/lanes-all`, 388 uncommitted files) and `p4-int` (branch `integrate/phase4`, not on GitHub). The four NativePeers worktrees are left to NativePeers.
- Simulators: `MF Test iPhone 17 Pro` is the test simulator for this run. `iPhone 17 Pro` (`73EBCB3C…`) has lost its data folder and cannot boot.
- Docker: colima profile `mfci` is stopped and the default context is `colima` again; the `default` colima VM still does not start.
