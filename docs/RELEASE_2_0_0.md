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
