# MindFriend 1.0.6 release record

This file records the 1.0.6 release work: repository cleanup, the production-copy migration dry run, outstanding acceptance work, legal pages, compatibility with released clients, the production deployment, the version bump, the Release archive and the physical-device test. Times are US Eastern.

## Phase 0: Inventory (8 November 2026, 8:37 PM EST)

### Released builds
- 1.0.5 (202611061625), built from `ee886e1` ("chore(ios): set release defaults to 1.0.5 (202611061625)"). 1.0.4 (202611052110) is still in use.
- `origin/main` head `850a058` (Merge PR #61, Sentry kept out of test runs) still declares 1.0.5.

### Branches against `origin/main` (`behind`/`ahead`)

| Branch | Where | Behind | Ahead | Disposition |
|---|---|---|---|---|
| `implementation/support-session-20261106` | local + remote | 2 | 2 (`5122419`, `e499062`) | Merge to main (PR #62) |
| `repair/17-apple-verifier` | local + remote | 240 | 1 (`0429d5c`) | Superseded by PR #40/#41; archive tag, delete |
| `issue-evidence/2026-10-23` | remote | 255 | 1 (`fc28c54`, 13 screenshots) | Move screenshots to `docs/evidence/2026-10-23/`, delete |
| `website/umami-analytics` | local only, worktree `.worktrees/website-umami` | 2 | 1 (`df06589`) | Not in the original plan. Its commit says the change matches the release already live on getmindfriend.app, and the live home page does load Umami. Merge to main so a website deploy from main does not remove live analytics or its privacy disclosure |
| `worktree-feat-ai-consent-compliance` | local only | 256 | 61 (April, last `b8a8373`) | Not in the original plan. Its `AIConsent*` client files never reached main (`git log --all -- '**/AIConsentService.swift'` shows only this branch). Archive tag, delete |
| `repair/screenshot-issues-12-23` | local `c7db968`, remote `35a6440` | 213 / 224 | 0 | Merged; delete |
| `fix/ci-ios-build`, `fix/moods-source-column`, `fix/sentry-install-environment`, `fix/sentry-skip-test-runs` | remote | 1–198 | 0 | Merged; delete |
| `npeer/<id>` × 10 | local, worktrees `.worktrees/<id>` | 144 | 0 | Committed tip is `8bdab5b`; each worktree holds uncommitted worker output (2–93 changed paths). Archive the dirty state, then remove |

### Pull requests and issues
- Open PRs before this work: none. PR #62 opened by this release for the support-session merge.
- Open issues: #17 (Premium purchase "Product not found"; blocked on Apple's Paid Apps Agreement and a sandbox purchase), #56 (`get_moods_for_pattern_analysis` parity), #57 (restoration deploy gates), #58 (client calls four backends that do not exist).

### CI
- `main` at `850a058`: run 42543896543 succeeded.
- `implementation/support-session-20261106`: runs 42400202390 (`5122419`) and 42406947638 (`e499062`) succeeded.

### Local leftovers
- Untracked `supabase/operations/20261022_repair_cron.sql` (SHA-256 `5c1a6c8256331dd309708b8acf83c7516591efdda1720805330772602f6004cb`). Production check (read-only, 8 November): `public.invoke_mindfriend_cron` does not exist, and jobs 58, 59, 60, 67, 68, 69, 76 and 77 are active with the exact pre-repair command hashes the script guards on. The script has never been applied.
- Ten NativePeers worktrees, about 483 MiB, listed in `artifacts/support-session/retained-native-workspaces.json`, plus `.worktrees/website-umami` (clean).

### Production (project `zfaucivtzfwnrijsbfug`, read-only)
- Migration ledger: 212 versions, last `20261105210400` (`honor_presence_privacy`).
- Repository: 251 migrations on `origin/main`, 264 on the support branch. Pending against production: every file newer than `20261105210400` (35 dated `20261106*` on main, plus 13 from the support branch).
- Edge functions: 210 deployed. Updated on 6 November: the provider-switch set (`chat` v54, `analyze-*`, `generate-*`, `test-auth-diagnostic` v24 and others). `voice-token` is v50 from 30 January (the legacy, non-relay deployment). `verify-purchase` v33 from 25 October. `remove-family-member`, `support-session` and `support-memory-suggestions` are not deployed.

### Known blocker carried in
`20261106225731_repair_mentorship_discovery_contract.sql` runs `CREATE OR REPLACE FUNCTION public.calculate_timezone_overlap(p_tz1 text, p_tz2 text)`; production's function is `(tz1 text, tz2 text)`, so PostgreSQL rejects it with "cannot change name of input parameter". A fresh `supabase db reset` hides this.

## Phase 1: Branch cleanup

### Deleted (fully merged, zero commits ahead of main)
Remote: `fix/ci-ios-build`, `fix/moods-source-column`, `fix/sentry-install-environment`, `fix/sentry-skip-test-runs`, `repair/screenshot-issues-12-23`. Local: `repair/screenshot-issues-12-23`.

### Archived, then deleted
| Tag | Points at | Why |
|---|---|---|
| `archive/repair/17-apple-verifier` | `0429d5c` | Superseded; see below |
| `archive/worktree-feat-ai-consent-compliance` | `b8a8373` | April AI-consent client work (61 commits, never on main). Main's consent path is now the support-session sign-up consent (`20261106220203_support_session_consent.sql`) |
| `archive/issue-evidence/2026-10-23` | `fc28c54` | Screenshots moved to `docs/evidence/2026-10-23/` |
| `archive/website/umami-analytics` | `df06589` | Cherry-picked unchanged onto main through PR #63 |
| `archive/npeer/<worker-id>` × 10 | one snapshot commit each | Uncommitted worker output in each NativePeers worktree |

### `repair/17-apple-verifier` is fully superseded
The draft (`0429d5c`, draft PR #31) verified StoreKit transactions with Apple's certificate-chain library, but the issue #17 record shows that library lacked X509 raw/infoAccess/verify APIs on Supabase Edge Runtime 1.77.8. Main's `supabase/functions/verify-purchase` (PR #40 `c7d7ce3`, PR #41 `040d37e`, deployed as v27 and later v33) keeps the draft's `apple-roots.ts` byte for byte and the same checks in `apple-transaction.ts` (revocation, signed expiry, no manufactured expiry, environment), and adds the bundled Apple verifier (`apple-verifier.js`, MIT notice retained) with Edge adapters (`edge-crypto.ts`, `edge-jsonwebtoken.ts`) and OCSP test transport. Nothing in the draft is missing from main.

### NativePeers worktrees
For each of the ten worktrees, the uncommitted files were compared with the support branch head `4f349c1`:

| Worker | Changed paths | Same as integrated | Differ |
|---|---|---|---|
| 442a849b | 95 | 60 | 35 |
| 54d7da16 | 71 | 29 | 42 |
| 5f1fab9a | 72 | 36 | 36 |
| 62bbb97e | 16 | 3 | 13 |
| 7f4c3acf | 45 | 17 | 28 |
| 8801fa07 | 73 | 33 | 40 |
| 91e67b6d | 30 | 14 | 16 |
| a1800a8e | 69 | 32 | 37 |
| cf163b37 | 3 | 0 | 3 |
| e790eb4c | 73 | 26 | 47 |

The differing files are intermediate worker states that the parent session edited further during integration. Each worktree's full state was committed on its `npeer/<id>` branch and pushed as `archive/npeer/<id>`. Each tag was confirmed on GitHub before `git worktree remove` (without `--force`), `git branch -D npeer/<id>` and `git worktree prune`. NativePeers' cleanup planner had refused retirement because the histories were resumed; its own records still list these worker IDs.

### Untracked cron operation
`supabase/operations/20261022_repair_cron.sql` is committed byte for byte (SHA-256 unchanged), with `supabase/operations/README.md` saying what it is and that it was never applied (evidence in Phase 0). It embeds the project's anon key, which is the publishable key shipped in the app binary.

### Screenshot evidence (`docs/evidence/2026-10-23/`)
The two filenames that contained `:` now use `_`. "Fixed" means the repair is on `origin/main` (head `850a058`) and, where noted, verified in hosted checks recorded on the issue.

| Screenshot | Issue | Shows | On main |
|---|---|---|---|
| Astronaut Profile Picture prefailure | #12, #14 | Partial avatar under a spinner, "Refining your image..." | Fixed: PR #33, #35; `AIProfileGeneratorView.swift:23-41`, `:215-221` |
| Chat Message Quota UI | #15 | Three sent messages with no replies and no quota feedback | Fixed: PR #36; `SupabaseDataService.swift:53`, `ChatView.swift:135-136`, `:337-358` |
| Debt Score Program Completely Broken | #21 | Stale January "Social Isolation −5 · inferred" withdrawals | Fixed: PR #25, #26; isolation penalty removed from `detect-transactions`, tested at `detect-transactions/test.ts:99` |
| Debt Score Progress - outdated_unfounded | #20 | Stale score and unfounded trend/projection | Fixed: PR #26, #27, #29; `WellbeingDebtDashboardView.swift:587-589`, `:306-323` |
| Debt Score Recalculation Hang | #22 | Modal "Scanning mood history..." with no cancel | Fixed: PR #28; non-blocking inset with Cancel, 25-second bound |
| Debt Score Recalculation Success | #23 | Manual recalculation, negative projection | Fixed: PR #30, #44, #46; automatic refresh on activation, day change and source change. Latency not measured |
| Global Subscription Error | #17 | "Product not found in the App Store" alert | Partly fixed: client PR #32, #42 and verifier PR #40/#41. #17 stays open: Paid Apps Agreement "Pending User Info", sandbox purchase not yet possible |
| Image mid-gen needs UI improvement | #14 | Lone spinner with no stage information | Fixed: PR #35; `AIProfileGeneratorView.swift:57-88` |
| MindFriend Site needs to be reconfigured on Hostinger | #18 | Blank black getmindfriend.app page | Fixed: PR #38, #39 (website and Caddy); live pages return 200 on 8 November |
| Profile Pic Generation failed - partly rendered | #12 | "No data received" after a partial preview | Fixed: PR #33, #34; `SSEStreamingHelper.swift:26`, `:113-117`, `:210-226` |
| Profile Picture Generation Failed-Storing Error | #13 | "Decoding error: Failed to store image" | Fixed: PR #34 (bucket format mismatch); deployed v21 |
| Remove Stop Response option | #16 | "Stop response" link in chat | Fixed: PR #37; no "Stop response" in any Swift file |
| Sleep Tracking Chart Completely made up_no health data | #19 | Score 55 / 9h 15m with no Health or manual data | Fixed: PR #24, #43, #45, #47–#49, #51; `SleepDashboardView.swift:612-618`, `:465-469`, `SleepTrackingModels.swift:94-97` |

The support-session branch (PR #62) reverts none of these fixes; it keeps the quota banner and has no "Stop response".

## Phase 2: Database readiness against a copy of production

### Copy of production
- Link confirmed with `supabase projects list` (only `zfaucivtzfwnrijsbfug`, MindFriend, `linked: true`).
- Schema-only dumps, 8 November 2026, 8:42–8:43 PM EST, no data (zero `INSERT`/`COPY` lines): `supabase db dump --linked` for `public`, and `-s auth,storage,supabase_migrations` for the managed schemas. They are kept in the ignored `.recovery/release-1.0.6/` folder.
- Restored into a disposable `supabase/postgres:17.11.0.006` container with no network, synthetic `NOLOGIN` roles, and the two auth hooks attached after `public`. Each pending migration runs in its own transaction, in filename order, as `postgres` (production's migration role, so its default privileges apply), stopping at the first failure.
- Ledger check (`CHECK_REMOTE_MIGRATIONS=1 scripts/check-migrations.sh` plus a version comparison): production has no version missing from the repository, and the repository has no unrecorded version older than `20261105210400`. Exactly the pending set below will be applied. The script's six name-only differences are at versions already applied; `db push` matches on version.

### First run: the known blocker
11 of 48 pending migrations applied. Then `20261106225731_repair_mentorship_discovery_contract.sql` failed with `cannot change name of input parameter "tz1"`.

### Drift found and fixed
- **`calculate_timezone_overlap`** (`20261106225731`, never applied anywhere, edited):
  - Production names the parameters `tz1`/`tz2`; a fresh chain names them `p_tz1`/`p_tz2` (`20260124150000`).
  - The function is now created through a `DO` block that keeps whichever names exist, so `CREATE OR REPLACE` succeeds on both and keeps the existing grants. No `DROP FUNCTION`.
  - Every caller passes the arguments positionally: `find_mentor_matches` and `supabase/tests/mentorship_matching.sql`. No `p_tz1 =>` or `p_tz2 =>` exists anywhere.
- **A catalog-wide audit found more.** The fresh chain at `20261105210400` was compared with production's dump. Production's ledger records several January migrations whose objects it never received:
  - the wellness-score columns;
  - predictive mood intelligence (`prediction_models` and its functions);
  - `20260124150000` mentorship security fixes (`encrypt_message_content`, `report_mentorship_issue`, `mark_messages_read` and others);
  - progressive disclosure caller checks;
  - capacity, circadian, vulnerable-window and mentorship policies, and 14 indexes.

  Pending `20261106230635` installs a trigger that calls `encrypt_message_content()`, so without a fix every mentorship message insert in production would fail.
- **New migration `20261106000000_reconcile_production_drift.sql`**, sorted before the other pending migrations. It is generated from the fresh chain's catalog with `search_path = ''`, every statement is guarded or idempotent, and it is a no-op on a fresh chain.
- **Where production was less safe, the safer definition wins.** `get_social_vitality_dashboard`, `check_activation_status` and the three `record_first_*` functions were `SECURITY DEFINER`, executable by `anon`, and had no caller check. They now reject anonymous callers and other users' ids. Released clients always pass their own id (`ActivationService.swift:98-198`, `SocialVitalityEngine.swift:48`).
- **Where production was the safer one, production's definition wins** (`increment_shield_count`, `get_active_encryption_key`).
- **Deliberately not changed:**
  - production's extra objects from repository-disabled migrations;
  - storage policies (they stay with the private-media operation);
  - `submit_pathway_checkin` (service-role only).

### Independent review (GPT-6.1 Sol, xhigh, read-only) and dispositions
| Finding | Severity | Disposition |
|---|---|---|
| F001: the restored "Delete own match" policy let either participant delete an active match, cascading through both participants' messages and safety escalations | critical | Fixed: delete only by the mentor, only while pending (the released app's only delete, `rejectMentorshipRequest`) |
| F002: the restored unconditional insert policy bypassed the rate-limited one (permissive policies combine with OR) | warning | Fixed: dropped; the rate-limited policy is the only direct insert path |
| F003/F004: the update guards missed `id`, `mentor_response` and `started_at` | warning | Fixed |
| F005: `get_prediction_features` referenced columns that exist nowhere | warning | Fixed: reads `date`, `sleep_duration_minutes`, `steps_count`, session durations and `current_streak_days` |
| F006: the prediction trigger doubled 6–10 mood scores past its 1–10 range, rolling back the mood insert | warning | Fixed: clamped, and wrapped so bookkeeping can never reject a mood |

**Automated security review.** It flagged anon-executable definer functions and broad message policies. Prediction, decryption and capacity-cleanup functions are now service-role only. `encrypt_message_content` stays callable by `authenticated`, because the message trigger runs as the sender. Released clients update matches directly (accept, end), so the match UPDATE policy stays, with a trigger limiting API callers to the status and end-detail columns.

**A running test found one more.** The old "Users can mark own messages as read" policy recursed into its own table on every update, and "Update message flags" let a participant rewrite any field. Clients use the owner-run RPCs, so neither is restored, and both are dropped on fresh chains.

### Issue 56
- Production's live `get_moods_for_pattern_analysis(uuid,integer)` (read-only, 8 November) is the `NULL::text AS source` body with `EXECUTE` for `postgres` and `service_role` only (definition MD5 `fe58f5f163cc07e6c03e21c054b4ff82`).
- A fresh `supabase db reset` produces the identical MD5 and ACL. Parity already holds, so no migration is needed.

### Issue 57 gates
| Gate | Status |
|---|---|
| Reconcile the ledger and inspect the pending plan | Done. `20261105210000`–`20261105210400` were already applied in production; 49 files are pending, listed below |
| Verify the pending migrations and recovery on a disposable production-shaped database | Done, this phase. Recovery: Phase 6 records a fresh logical backup before the push |
| Resolve #56 | Done; parity confirmed above |
| Deploy with an explicit function list | Phase 5 list (65 functions) |
| voice-token relay-only 426 | 1.0.4 and 1.0.5 never call `voice-token`. They POST `{"transport":"relay"}` to `test-auth-diagnostic` and open its WebSocket (`GrokVoiceService.swift:723-729`, `VoiceWebSocketManager.swift:29-46` at `ee886e1`), and that path is kept. `test-auth-diagnostic` keeps `verify_jwt = false` (PR #65) |
| analyze-voice-journal 428 | Not in the deploy list. Released clients already send PCM WAV (`CreativeExpressionService.swift:395-411`) |
| Private media stays separate | `20261106223813` (never applied, edited) no longer changes bucket visibility. `operations/20261022_private_media.sql` is still unapplied |

### Final results (branch head at the time of the run)
- **Copy of production:** 49 of 49 pending migrations apply.
- **Post-deploy catalog vs fresh chain:** they converge. What remains is the intended differences above, plus constraint renderings that are equivalent.
- **CI's SQL runner** (`supabase/tests/ci/run_sql.py`, now 13 suites including `mentorship_messages.sql` and the new `drift_reconciliation.sql`): PASS.
- **Every `supabase/tests` SQL file**, each in its own clone named as the file requires:
  - Fresh chain: 63/68 pass. Copy of production: 59/68 pass. `rate_limit_concurrency_test.sql` passes on the running local stack: 4 concurrent requests give 3 allowed and 1 denied, and the verify phase holds.
  - Failing in both: `b2b/test_metrics_privacy_threshold.sql`, `b2b/test_organizations_schema.sql` and `b2b/test_saml_replay_prevention.sql`. These are test-first specs for an enterprise SAML feature that was never built: they expect `saml_assertions`/`organizations.saml_enabled`, and one says "ALL TESTS FAIL until saml_assertions table is created".
  - Fresh only: `restoration_journeys.sql`, a limit of CI's storage stub. It passes against production's real storage schema.
  - Copy of production only:
    - `assessment_submission.sql`, `support_voice_context.sql` and `private_creative_media.sql` need reference rows a schema-only dump does not carry. Production has them (all four assessment templates, the voice budget row `daily_seconds=600`, and the buckets), checked read-only.
    - `bounded_voice.sql` and `provider_cost_limits.sql` open a second `dblink` connection that the socket-only copy does not accept. Both are self-contained fixtures on an empty database and pass on the fresh chain.
- **Test repairs made while running every file:**
  - `get_stress_signature.test.sql`: removed column, unqualified `gen_salt`, short `VALUES` lists, top-level `PERFORM`.
  - `sleep_recorded_periods.sql`: missing synthetic user; RLS assertion.
  - Apple identities: CI fixture now has the real `provider_id NOT NULL`.

Pending plan (50, filename order): `20261106000000` reconcile, then the 35 `20261106*` app-repair migrations and 13 support migrations through `20261107185417_reconcile_companion_canonical_actions.sql`, then `20261108230000_schedule_memory_candidate_expiry.sql` (daily SQL job that blanks unsaved memory suggestions after their 7-day window). The dry run after adding it: 50 of  50.
