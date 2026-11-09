# MindFriend 2.0.0 release record

This file records the release prepared as 1.0.6 and shipped as 2.0.0 (Phase 7): repository cleanup, the production-copy migration dry run, outstanding acceptance work, legal pages, compatibility with released clients, the production deployment, the version change, the 2.0.0 fix and UI pass, the Release archive and the physical-device test. Times are US Eastern.

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

Pending plan (50, filename order): `20261106000000` reconcile, then the 35 `20261106*` app-repair migrations and 13 support migrations through `20261107185417_reconcile_companion_canonical_actions.sql`, then `20261108230000_schedule_memory_candidate_expiry.sql` (daily SQL job that blanks unsaved memory suggestions after their 7-day window). The dry run after adding it: 50 of 50.

## Phase 3: Outstanding work

### Nonproduction target
Local Supabase stack, project id `mindfriend-release106`, API `http://127.0.0.1:55321`, database `127.0.0.1:55322`. It runs from a copy of `supabase/` under the ignored `artifacts/release-1.0.6/local-stack/` with shifted ports, so the unrelated `stir` stack on 54321–54327 is untouched. `supabase db reset --db-url postgresql://postgres:postgres@127.0.0.1:55322/postgres` applied the full chain (261 ledger versions including the reconciliation). Functions were served with `supabase functions serve` and the provider keys from the ignored `supabase/functions/.env`. Provider-bound HTTPS was recorded through a loopback-only mitmproxy (credentials dropped) to capture the actual payloads.

### G2 service checks (8 November, 9:17–9:45 PM EST, synthetic content)
| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Streaming terminal states | PARTIAL | Completed stream: deltas equal the confirmed text, `persistence: confirmed`. Refusal and incomplete could not be provoked live (the model declines in plain text and shortens its output); the AC-14 fixtures remain the evidence. A client disconnect keeps a non-retryable claim and never replays paid provider work, as pinned by `supabase/tests/issue15_chat_test.ts` |
| 2 | Confirmation reconciliation | PASS | Same `requestId` replays the identical response with no provider call, no new rows, no quota change; changed content 409; two concurrent sends give one 200 and one 409 with one provider call; `OPERATION_ID_REUSED` on a changed payload |
| 3 | Owner/epoch | PASS | `expected_owner` mismatch 409 before any claim; foreign conversation 403; stale privacy revision 409 without a debit; another user's session, memory, receipts and suggestions 404 |
| 4 | Quota and budget denial | PASS | At the free limit (5/day) new JSON, new SSE and the old request shape all get 429 `chat_quota_exhausted`; Memory Generate 402; zero provider calls |
| 5 | Old-client response shape | PASS | The 1.0.5 request body and a mirror of its decoders (`ee886e1`) accept both the streamed result and the replay |
| 6 | Memory preview, Generate, replay, review-before-use | PASS | Preview has no provider call; Generate sends only the selected message (captured payload); same-id replay has no second call; unreviewed suggestions are absent from later chat payloads and receipts |
| 7 | Context receipts | PASS | Receipt memory ids match the `(ref:)` markers in the captured OpenAI payload (3 of 3) and name the model actually sent; journal, mood, HRV, other conversations, stopped and forgotten memories and pending suggestions are absent |
| 8 | Text → voice → text and privacy lease | PARTIAL | Voice admission returns a 1,299-byte packet (limit 8,000), lease 5,000 ms, no health/vault/other-conversation data; client `instructions` rejected; text continues in the same session; a correction drops the stopped memory. The live relay socket and lease timing are NOT_RUN: WebSocket upgrades return 502 inside the local edge runtime |
| 9 | Live provider calls | PASS (text) | 44 OpenAI `gpt-6-luna` Responses calls (`store:false`, 500 output tokens) and 1 xAI `grok-4.3` call succeeded; the realtime voice socket was not reached |
| 10 | Latency | Non-streaming met; first token not met | See below |

Provider calls: 45 (44 OpenAI, 1 xAI), all synthetic. Fixed from these checks: voice admission for someone else's or a missing conversation now returns 404 instead of a retryable 503 (PR #68).

### Simulator journeys and accessibility (8 November, iOS 27.0 simulators created for this release)
- **Devices:** compact iPhone 17e, iPad Air 11-inch (M4), and a third iPhone 17e for re-checks.
- **New tests** (PR #70):
  - every destination at every Dynamic Type size, with captures;
  - the full system audit (`performAccessibilityAudit(for: .all)`) on every destination.
- **Audit runs:** default, dark, Increase Contrast, and Reduce Motion + Reduce Transparency, set on the simulator with `simctl ui` and the Accessibility defaults.
- **Existing support UI suite:** 11/11 pass on the compact iPhone (all 12 text sizes in light and dark, landscape, voice captions, grounding, Untangle relaunch, history, memory preview, onboarding consent).
- **Fixed** (PR #70):
  - support lists use the support palette's accent and prominent headers (app-wide accent and default gray headers were under 4.5:1);
  - Chat's empty state scrolls instead of truncating;
  - the profile row stacks at accessibility sizes;
  - "Not yet" replaces bare dashes;
  - prominent buttons use the palette's `onAccent` label (white on the dark-mode accent failed).
- **Fixture bug:** the UI fixture pinned text size, which made the Dynamic Type audit report false positives. Fixed.
- **Open audit findings:**
  - "Plans and Premium" row reported clipped in every configuration. It is fully visible at AX5 in captures; the cause was not found.
  - Text scrolled under the translucent system tab bar.
  - iPad: sidebar label vibrancy, and destinations kept alive offscreen by the split view.
- **Not automatable here:** iPad window resizing (no XCUITest API) and a live VoiceOver walkthrough (audits cover labels, traits and hit regions). Both are listed for the device run.
- **Enhanced Privacy in voice** (PR #68): the legal comparison found voice admission ignored Privacy Mode. Fixed so voice narrows exactly like text.

### Latency (from this Mac to the local functions; providers over this Mac's internet connection; 10 samples each)
| Measure | p50 | p95 | Target |
|---|---|---|---|
| Streaming: first text delta | 1,074 ms | 1,662 ms | p95 ≤ 1,000 ms: not met |
| Non-streaming: total | 1,577 ms | 2,361 ms | p95 ≤ 3,500 ms: met |
| Provider first bytes (streaming) | 344 ms | 520 ms | |
| Server work before the provider request | about 70 ms | | |

Most of the first-token time is between the provider's `response.created` event and its first text delta. The targets are not relaxed; AC-35 stays open. The spec's 30-sample, named-device capture remains for the physical iPhone.

## Phase 4: Privacy policy, terms and App Store privacy answers

### Legal text (PR #71)
- Both copies were compared with the code: the published pages (`landing-page/privacy`, `landing-page/terms`) and `docs/legal/*` (which were stale January copies). Both now carry the same content, effective and last updated 9 November 2026.
- **Corrected:**
  - **AI processors:** OpenAI is primary, xAI is a backup and serves live voice in app versions ≤1.0.3, and Google provides TTS.
  - **Removed** the nonexistent "AI & Data Sharing" screen and first-launch AI choice.
  - **AI data flows:** what each AI feature sends, including automatic memory extraction; memory suggestions; Stop using and Forget; context records; voice transcripts.
  - **Data sources:** Apple Health sleep imports; calendar use; Private Vault.
  - **Sentry:** described accurately, with no analytics SDK.
  - **Processors added:** Resend, Google Sign-In, Apple.
  - **Account data:** what deletion and export include; sign-up birth year and 13+ confirmation.
  - **Retention:** claims that nothing implements were removed.
- **Code changes from the comparison:**
  - voice now honors Enhanced Privacy Mode (PR #68);
  - unsaved memory suggestions are erased after 7 days by a scheduled job (PR #69);
  - the privacy manifest and Health permission strings match the app (PR #67).
- **Not changed:** the sign-up consent version string is still `2026-11-06` (`20261106220203_support_session_consent.sql`); the documents are dated 9 November.

### Website deployment (getmindfriend.app, VPS `hostinger`)
Followed `landing-page/deploy/README.md`, 8 November 2026:
- **Preflight (read-only):**
  - `current` → `releases/umami-bridge-20261107`; `mindfriend-site.service` active, the only listener on 80/443.
  - The live Caddyfile also serves `getstir.app` and the analytics dashboards and is newer than `landing-page/deploy/Caddyfile`. It was validated with the pinned Caddy binary (`Valid configuration`) and **not changed**.
- **Live vs main:** every live file matched `main` except `index.html`, where `main` is newer (reduced-motion support); the Umami parts are identical.
- **Build:** CSS rebuilt from a clean export of `main` (`3d6cc1d`) with Tailwind 3.4.17; byte-identical to the committed CSS.
- **Package:** `package.py` (10-file allowlist); manifest verified locally and again on the server after extraction into `releases/legal-106-20261108-2258` (root-owned, 755/644).
- **Switch:** atomic `ln -sfn` + `mv -T` at **10:59 PM EST**, then restarted only `mindfriend-site.service` (active). Rollback target kept: `releases/umami-bridge-20261107`.
- **Verified:**

  | Route | Result |
  |---|---|
  | `https://getmindfriend.app/` | 200 |
  | `https://www.getmindfriend.app/` | 308 → apex |
  | `/privacy/`, `/terms/`, `/support/`, `/accessibility/` | 200 |
  | `/privacy` (no trailing slash) | 308 → `/privacy/` |
  | `http://` | 308 → `https://` |
  | Unknown path | 404 |
  | `/_p/p.js` (Umami tracker) | 200 |
  | TLS | Verifies |

- **Content and layout:** the new text is served (dated 9 November, Resend listed, You → Settings paths, no "AI & Data Sharing"). At 390 px width there is no horizontal overflow, including the three tables.

### App Store Connect App Privacy answers for 2.0.0
Data used to track you: none. MindFriend has no advertising SDK, no IDFA or App Tracking Transparency prompt, and no data-broker sharing; Sentry and the AI providers act as processors. Every collected type below is **linked to the user** (the account ID) and **not used for tracking**.

"Changed" compares with the 1.0.5 privacy manifest (`PrivacyInfo.xcprivacy` at `ee886e1`); the values currently saved in App Store Connect were not read and should be compared there.

| Category | Data type | Purposes | Changed since 1.0.5 |
|---|---|---|---|
| Contact Info | Name | App Functionality | No |
| Contact Info | Email Address | App Functionality | No |
| Contact Info | Phone Number | App Functionality (a number you type to invite a buddy) | **New** |
| Health & Fitness | Health | App Functionality, Product Personalization | **Purpose added** (personalizes replies and generated exercises) |
| Health & Fitness | Fitness | App Functionality | **New** (steps, distance, energy, exercise and mindful minutes, workouts synced from Apple Health) |
| User Content | Audio Data | App Functionality | **New** (voice-journal recordings) |
| User Content | Photos or Videos | App Functionality | **New** (profile pictures you upload) |
| User Content | Customer Support | App Functionality | **New** (the in-app enterprise inquiry form) |
| User Content | Other User Content | App Functionality, Product Personalization | **Purpose added**; now includes saved voice transcripts and memory suggestions |
| Identifiers | User ID | App Functionality, Analytics | **Analytics added** (attached to crash reports) |
| Identifiers | Device ID | App Functionality (push token only; no IDFA/IDFV) | No |
| Purchases | Purchase History | App Functionality | No |
| Usage Data | Product Interaction | Analytics, App Functionality | **New** (feature events, interaction traces and masked session replays sent to Sentry) |
| Diagnostics | Crash Data | Analytics | **Now linked** |
| Diagnostics | Performance Data | Analytics | **Now linked** |
| Diagnostics | Other Diagnostic Data | Analytics | **New** (breadcrumbs, network timing) |
| Other Data | Other Data Types | App Functionality | **New** (birth year and sign-up consent record; calendar event titles, times and locations for the daily briefing) |

Not collected: Financial Info, Location (coordinates stay on the device), Sensitive Info (mental-health data is declared under Health), Contacts, Emails or Text Messages, Browsing History, Search History, Advertising Data, Gameplay Content, Other Usage Data.

## Phase 5: Compatibility with 1.0.5 and 1.0.4

### Deploy list (65 functions)
The union of:
- functions changed since `ee886e1`;
- functions importing a changed `_shared` file, transitively: `entitlement.ts`, `staff-auth.ts`, `recovery-points.ts`, `notification-utils.ts`, `email-utils.ts`, `openai-chat.ts`, `support-*.ts`, `voice-relay.ts`, `reframe-templates.ts`;
- `remove-family-member`;
- the rollout list: `support-session`, `support-memory-suggestions`, `chat`, `voice-token`, `delete-account`, `test-auth-diagnostic`.

`verify_jwt` comes from `supabase/config.toml`. Two differ from production today:
- `sign-in-with-apple-notifications` becomes `false`. Apple's server notifications carry no Supabase JWT, and the function verifies Apple's signed payload itself.
- `test-auth-diagnostic` (the voice relay) stays `false`. Before PR #65, config had no entry, which would have switched it to `true`. The shared code rejects unauthenticated requests with 401 (`voice-relay.ts:693-699`, verified locally).

Order: migrations first, then functions. Eight functions call `refresh_user_entitlement`, and three need the new `measurement_status` columns.

### Compatibility table (client evidence at `ee886e1`)
| Area | Verdict | Evidence |
|---|---|---|
| voice-token 426 / relay | Compatible | 1.0.4/1.0.5 never call `voice-token`. They POST `{"transport":"relay"}` to `test-auth-diagnostic` (`GrokVoiceService.swift:723-729`) and open its WebSocket (`VoiceWebSocketManager.swift:29-46`). The new code keeps the legacy prepare/claim path (`voice-relay.ts:719-830`), and the response satisfies `VoiceTokenResponse` (`Models.swift:705-733`) |
| analyze-voice-journal 428 | Not deployed | Released clients already send PCM WAV (`CreativeExpressionService.swift:395-411`) |
| Case-sensitive partnership invitations | Compatible (not reached) | Old clients use buddy codes: `accept_buddy_invite(code.uppercased())` (`SupabaseDataService.swift:2156-2159`), compared with `UPPER()` on the server. They never call `couples-partner-links*` |
| `partner_links` direct update revoked | Breaking in code, unreachable | Old sharing toggles update `partner_links` directly (`SupabaseDataService.swift:2363-2386`). Production has 0 active partner links and 1.0.5 cannot create one, so no released-client user can reach this. No shim |
| Family RLS changes | Compatible | Admins and active members still read; the admin's direct `status: removed` update still passes; join/accept responses decode (`Models.swift:980-992`) |
| Device registration transfer | Compatible | Old clients upsert `push_tokens` directly (`SupabaseDataService.swift:2658-2671`); its grants and policies are unchanged |
| `refresh_current_premium_access` | Compatible | Production has 1 premium profile, with an active subscription, so the entitlement refresh downgrades nobody |
| Apple account notifications | Compatible | Server-to-server only |
| Invitation reader restrictions | Compatible | Old clients read `family_invitations` only as the family admin (`BillingService.swift:580-596`) |
| Mentorship repairs | Compatible; match updates now work | Accept, end and decline updates pass the new guard (decline = mentor deleting a pending request). Old message writes use columns that never existed (`is_read`, `is_flagged`) and fail before and after |
| `award_xp` reward guards | Compatible | Old clients always pass their own id (`SupabaseDataService.swift:3363-3368`) |
| Private creative media | Compatible | Bucket visibility is no longer changed (PR #69). 1.0.4/1.0.5 already use signed URLs (`SupabaseClient.swift:40-73`) |
| delete-account | **Was breaking, fixed (PR #65)** | Old clients send an empty POST (`SupabaseAuthService.swift:847-850`), which the new function rejected with 400 before deleting anything. Reproduced locally; after the fix, 200 and the account is removed |
| calculate-efficacy | **Was degraded, fixed (PR #65)** | Swift sends uppercase UUIDs; the function compared them to lowercase with `!==`, so every submission failed |
| Chat memory from auto-extracted fragments | Degraded by design | With the support schema, chat reads only reviewed memories. 1.0.5 has no review UI, so its users keep their own saved memories but not new automatic ones |
| Every other migration and function | Compatible | Additive objects, owner-scoped checks that old clients satisfy, or no old-client caller |

Already broken for 1.0.5 before and after (not regressions): mentorship message writes, `find-mentor-matches` decoding, `join-family` birth-date format, `create-gift`/`redeem-gift`.

## Phase 6: Production deploy

### Target and backup
- Target confirmed with `supabase projects list` before every write: `zfaucivtzfwnrijsbfug` (MindFriend, us-east-1, `linked: true`). Every function command passed `--project-ref zfaucivtzfwnrijsbfug` explicitly.
- Logical backup, 8 November 2026, 11:57–11:59 PM EST: `roles.sql`, `schema.sql`, `managed-schema.sql`, `data.sql`, `managed-data.sql` with `SHA256SUMS`, mode 600, in the ignored `.recovery/release-1.0.6/backup-20261108-235729-EST/`. Restored into a disposable network-isolated container; table row counts match production.

### Migrations
- `supabase db push --linked --dry-run` listed exactly the 50 planned files, in order.
- `supabase db push --linked` applied all 50, 9 November 2026, 12:01:13–12:01:43 AM EST.
- Verified: ledger 262 versions, last `20261108230000`; the reconciliation objects, the seven new RPCs and the `support-expire-memory-candidates` cron job exist; `creative-works` and `generated-audio` visibility unchanged.

### Functions
- 51 of the 65 listed functions deployed 12:02–12:03 AM EST (`supabase functions deploy <name> --project-ref zfaucivtzfwnrijsbfug --use-api`, one at a time, stop on first failure).
- The 52nd, `remove-family-member`, a function production did not yet have, failed with HTTP 402 `Max number of functions reached for project`. Deploys stopped.
- Cause: the organization is on the Free plan, whose limit is 100 functions per project. Production had 210, kept from before the limit; existing functions can be updated but no new one can be created while the project is over 100.
- Unused functions deleted, 12:20:39–12:20:48 AM EST, 13 in total. None is called by the app at `main`, by released builds (`ee886e1`, `8564715`) or by any other function, migration or cron job, and none had a request in the previous 24 hours. Their source stays in the repository.
  - Named for deletion: `get-patterns`, `get-ui-preferences`, `update-ui-preferences`, `save-session`.
  - Found unreferenced: `couples-appreciations`, `couples-appreciations-get`, `couples-partners`, `couples-sessions-get`, `couples-sessions-patch`, `enterprise-provision`, `mix-audio`, `monitor-session-safety`, `therapist-accept`.
- Production now has 197 functions, still above 100, so `remove-family-member` failed again with the same 402 (12:20:56 AM EST).
- The 11 remaining listed functions that already existed deployed 12:21:43–12:21:55 AM EST: `request-mentorship`, `send-assessment-reminders`, `send-email`, `send-monthly-report`, `send-notification`, `send-weekly-summary`, `sign-in-with-apple-notifications`, `synthesize-voice`, `test-auth-diagnostic`, `verify-purchase`, `voice-token`.
- 62 of 65 were deployed at that point. Missing: `remove-family-member`, `support-session`, `support-memory-suggestions`. All three are new in 1.0.6; no released build calls them.
- Deleting more could not get the project under 100: the released 1.0.4 and 1.0.5 apps call 130 distinct functions by name. Every live function was created between 13 January and 4 February 2026, which is why the limit had not come up before.
- Resolution: MindFriend was moved to its own organization, "Apps" (`rvzkpuwcvdugdjtzlvyf`), on the Pro plan (limit 1,000 functions; no inactivity pausing; daily backups kept 7 days). Stir stays on Free in `scalinity.bio`. Verified after the move, using the CLI because the claude.ai Supabase connector is not yet authorized for the new org:
  - same project ref and host;
  - the app's anon key matches a live key, and Auth health returns 200;
  - 197 functions, 25 secret names, 21 cron jobs and the 262-version ledger are all unchanged.
- The three new functions deployed 12:45:50–12:45:52 AM EST.
- **65 of 65 deployed**, 200 functions live. `verify_jwt` matches `supabase/config.toml` for all 65, and their update times all fall within this deploy.
- CORS preflight on each of the three returns 200 from `supabase-edge-runtime` with the functions' own headers, so each module boots. `remove-family-member` also rejects an anon token from its own code (401 `Unauthorized`). The signed-in paths are exercised in the Phase 9 device test.

### Verification
- The seven new RPCs, each called once as a synthetic `authenticated` user inside one transaction that ends in an exception, so nothing persists (12:23 AM EST). Afterwards: no synthetic user, conversation or companion action remains.

  | RPC | Result |
  |---|---|
  | `save_voice_transcript` | returned a conversation id |
  | `submit_outcome_assessment` (PHQ-9, all zero) | returned the scored response and goal |
  | `register_current_device` | owner equals caller |
  | `mark_messages_read` (random match) | rejected: not a participant (expected) |
  | `ingest_companion_action` (mood) | `status: applied` |
  | `get_shared_partner_activity` (no link) | `null` (expected) |
  | `get_companion_day_summary` | zeroed summary |
- Logs from 12:00 AM EST: no 5xx edge responses and no Postgres ERROR entries outside the deploy statements.
- Sentry: no MindFriend issue first or last seen after the deploy; the newest event predates it (MINDFRIEND-1A, 7 November).

### Found during verification (not caused by this release)
13 of the 21 production cron jobs have failed on every run since 31 January 2026 (first recorded failure, 3:00 PM EST). The 7 days before the deploy show the same.
- Nine of them read `app.settings.supabase_url`, which is not set on the hosted project: the notification queue, streak risk and protection, the agent jobs, the proactive scheduler, lapsed users and the weekly summary.
- `send-assessment-reminders-daily` builds a NULL URL from the same setting.
- `calculate-debt-score-daily` and `detect-transactions-daily` need an `app.service_role_key` setting.
- `cleanup-email-dlq-30days` and `cleanup-email-logs-90days` reference columns that do not exist.

This is out of scope for 1.0.6. The fix needs a Vault secret, and re-enabling the jobs starts notifications and emails users have not received since January, which is a product decision. It is tracked for a follow-up release; the issue text is in `artifacts/release-1.0.6/phase6/cron-issue.md`.

## Phase 7: Version 2.0.0
- The release was prepared as 1.0.6 (PR #74, closed; preserved at tag `archive/release/1.0.6`). The Today / Chat / Explore / You shell changes the app's navigation and look enough to warrant a major version, so it ships as 2.0.0 (PR #75).
- `MARKETING_VERSION` 1.0.5 → 2.0.0 and `CURRENT_PROJECT_VERSION` 202611091157 (America/New_York `yyyyMMddHHmm`; PR #75, merged 9 November 2026, 12:28 PM EST), in the app target's Debug and Release configurations of `project.pbxproj`.
- No client or server code compares version numbers. The version is only displayed (Profile, You) and attached to analytics, crash reports and data exports, so the major version changes no behavior.

## 2.0.0 fix and UI pass (9 November 2026)
A device test of the 2.0.0 redesign found failed purchases, a free quota below the intended 30 messages, and screens outside the new shell still drawn in the old style. This pass fixes those and brings every screen reached from the shell onto the support theme.

### Fixes
| Item | PRs |
|---|---|
| Purchases and restores: the vendored verifier's certificate shim threw a bare string ("Signature: unsupported public key alg: ecdsa") when it tried an RSA root against Apple's EC-signed chain, so every transaction failed with `JWS_VERIFICATION_FAILED`. A failed root comparison now means "not the signer" and the next root is tried. Also: failure causes logged with their step, crossgrades honoured, transactions ordered by purchase time, and seats released when a shared plan shrinks. | #76, #86, #88, #89 |
| 30 free chat messages a day: server quota, website copy, and an in-app banner and Send state that follow the server's day | #77, #85, #87 |
| Confirmations as centred alerts with every option visible | #78 |
| Activity fields readable on the canvas, a keyboard-safe layout, and "Make it smaller" rewriting the step in place | #80 |
| One navy theme for every screen reached from the shell; launch screen restored to the icon on the dark background | #81 |
| Greeting by name, one reward layer at the shell root, and no streaks in the UI | #83 |
| First-run tutorials on the support theme | #84 |
| CI: Swift package resolution retried after GitHub 504s | #79 |

### UI/UX pass in four lanes
Walkthrough 1 (`artifacts/ui-pass/walkthrough-1.md`, 2.0.0 build at that time, dark and light at the default text size plus `accessibility3`) logged 59 defects: 6 cross-cutting, fixed before the lanes started, and 53 assigned to four lanes by file ownership. Four GPT-6.1 Sol workers drafted the lanes in isolated worktrees that could not build or run tests; each lane was compiled, corrected, tested and reviewed here before its PR.

| Lane | Scope | PR |
|---|---|---|
| 1 | Today (greeting, quick ways in, progress card, pin editing), sessions, check-in, quests and reward moments | #90 |
| 2 | Explore categories and the practice destinations (programs, sleep, library, live sessions, insights, therapists) | #91 |
| 3 | Chat, voice and people features (circles, mentorship, peer support, partner, family, buddy) | #92 |
| 4 | You, settings, help, achievements, certificates and the paywall | #93 |
| Sweep | Primary buttons outside the lanes, the home tutorial, and selected chips in lane 3's files | #94, #95 |
| Follow-ups | Row subtitles at accessibility sizes, whole-word mood choices, Today tiles at large text, symbol weights, the privacy banner | #96 |
| Icon columns | 70 SF Symbol columns widen with Dynamic Type instead of overlapping their labels | #97 |

### Second walkthrough and accessibility audit
- Walkthrough 2 (combined build, dark at the default text size, 95 captures; `artifacts/ui-pass/walk5-dark-large/`) found 9 defects, all fixed:
  - Explore rows on a category page did not navigate: the page sat outside the stack's typed path. Explore's path is now a `NavigationPath` holding category pages and destinations (#91).
  - Explore lists drew the system cell colour on the navy canvas (#91).
  - Filter chips selected in system blue (#91).
  - The For You selectors overflowed a phone's width (#91, review).
  - Five near-white backgrounds had become solid accent, hiding text and a progress bar (#91, review).
  - Mood choices split words ("Goo / d") (#96).
  - The privacy banner hugged its text (#96).
  - At accessibility sizes every row subtitle started mid-row: the list's label style indents each title text under the icon (#96).
  - Today's quick tiles hyphenated their labels at xxLarge and xxxLarge (#96).
- The light accessibility3 walkthrough (`artifacts/ui-pass/walk6-light-a11y3/`) found one more: on Appearance the theme symbols ran into their labels. Seventy rows pinned an SF Symbol to `.frame(width: N)`; they now use `minWidth` (#97). With the simulator's own text size at accessibility3, every session flow (activities, reflection, pause and close alerts, mood check-in, chat) scales and stays usable (`artifacts/ui-pass/flows-system-ax3.xcresult`).
- Every destination at all 12 text sizes, light and dark, iPhone 17 Pro and iPad Pro 11-inch: no clipping or overlap (`artifacts/ui-pass/sizes-light/`, `sizes-dark/`, `ipad-sizes.xcresult`).
- Full accessibility audit (`testEveryDestinationPassesTheFullAccessibilityAudit`), iPhone 17 Pro:
  - Today: no findings, light and dark (before: contrast on the "1-minute breathing" tile, fixed by matching the symbol weight to the label).
  - You: no findings in light, and one finding without an element in dark (before: clipped text on "Plans and Premium", caused by the label indentation above).
  - Explore: three findings in light, two in dark (before: seven). The category grid now switches layouts with `AnyLayout`, so changing the text size no longer replaces the tiles. Still reported: the "Browse by category" header (Dynamic Type), one clipped-text finding without an element, and in light a "nearly passed" contrast on the "Choose one next step" row, whose colours measure 6.6:1. The header renders correctly at all 12 sizes.
- iPad Pro 11-inch: the sidebar's "Explore" item is reported for Dynamic Type, as on `main` before this pass. The audit under You also sees Explore's content fading out of the split view's detail column.

### Production changes
- Supabase "Deploy to production" and "Automatic branching" were confirmed off before any merge that touched `supabase/` (5:30 AM EST).
- Logical backup: `.recovery/release-1.0.6/backup-20261109-063638-EST` (five dumps, `SHA256SUMS` verified).
- Target confirmed with `supabase projects list` (`zfaucivtzfwnrijsbfug`). The dry run listed exactly `20261109074000_free_chat_quota_30.sql` and `20261109101500_subscription_transaction_order.sql`; both applied at 6:39 AM EST. Verified: `profiles.daily_ai_quota` defaults to 30; 23 of 23 free profiles at 30; the six functions that write the free limit use 30; `check_and_increment_ai_quota` returns `quota_day`; `subscriptions.last_transaction_purchased_at` exists. A synthetic sign-up inside a block ending in an exception got quota 30 and `{allowed, quota_used 1, quota_limit 30, quota_day 2026-11-09}`; nothing persisted.
- `chat` v56 deployed at 6:40 AM EST.
- Website release `releases/quota30-20261109-0640` switched at 6:41 AM EST (only `index.html` differs; routes 200, unknown paths 404, `www` and `http` 308; "30 AI chat messages/day" live). Rollback target: `releases/legal-106-20261108-2258`.
- `verify-purchase` v36 at 6:53 AM EST (#86 and the #88 diagnostic), then v37 at 7:26 AM EST (#89).
- The owner's Restore Purchases succeeded at 8:00 AM EST on v37: `public.subscriptions` has the App Store row (`com.mindfriend.premium.monthly`, individual, monthly, active, `last_transaction_purchased_at` set), the profile is `premium` with an unlimited quota, and the app shows Premium Active.

### Found during this pass (not changed here)
- Production has no `community_wisdom` table (Sentry MINDFRIEND-1N). Peer support's wisdom section loads empty; the other sections are unaffected.
- 62 unit tests in 16 classes outside CI's list fail on `main` before and after this pass (`artifacts/ui-pass/main-baseline-failures.txt`), for example `PromoCodeFieldTests`, which reads `@State` from an `XCTestCase`.
- The failing cron jobs (Phase 6) are unchanged.

## Phase 8: Release archive and Sentry symbols
- Archived from `main` at `b106c39` (after #75 and #97), 9 November 2026, 12:28:59–12:33:01 PM EST: `xcodebuild archive -scheme MindFriendApp -configuration Release -destination generic/platform=iOS`. Result: `** ARCHIVE SUCCEEDED **` (`artifacts/release-2.0.0/archive.log`).
- Archive: `~/Library/Developer/Xcode/Archives/2026-11-09/MindFriend 2.0.0 (202611091157).xcarchive`, left in Xcode Organizer (312 MB). Info.plist: `com.mindfriend.app`, 2.0.0, 202611091157. The superseded `MindFriend 1.0.6 (202611090048).xcarchive` was moved to the Trash.
- Sentry, from the "[Sentry] Upload Debug Symbols" build phase: "Found 12 debug information files", "Uploaded 8 missing debug information files", then "Sentry debug-symbol upload completed." The phase runs before Xcode generates the app's dSYM, so it uploads the executables' symbol tables (MindFriendApp `2a9efd54-10ba-36e1-bfa0-6fb0442891e3`, the watch app, complications, widgets, Sentry).
- The archive's dSYMs were then uploaded with the same `sentry-cli debug-files upload --type dsym --no-sources --wait-for 60`: "Uploaded 5 missing debug information files", including the MindFriendApp debug companion with the same UUID (`artifacts/release-2.0.0/sentry-dsym-upload.log`). A later release should give the build phase the dSYM as an input file, so the dSYMs are uploaded in one pass.
- Development export (`ExportDevelopment.plist`, debugging method, automatic signing): `** EXPORT SUCCEEDED **`, `MindFriend.ipa` 28 MB (`artifacts/release-2.0.0/device/export/`).
- Installed on the owner's iPhone 16 Pro Max (`00008140-000214C41A01801C`) as an upgrade at 12:34 PM EST: 1.0.6 (202611090048) → 2.0.0 (202611091157), with the app's data kept (`before-install.txt`, `after-install.txt`).

## Device round on 202611091157 (#98)
The owner tested build 202611091157 on the iPhone after the Phase 8 install. PR #98 fixes what that test found, one commit per item, and merged at 3:25 PM EST (`4b8d342`) after CI passed on `af4d105` (iOS, SQL and Deno jobs).

| Found on the device | Cause | Fix |
|---|---|---|
| Chat would not send | Chat started its activity with the Today origin. Ending it offered "Done for now", which closes a session with no draft and no unfinished work: `activity_stopped` at 1:42:01 PM EST, `session_closed` at 1:42:02. The Send tap at 1:42:05 made no request (Sentry replay). | `SupportEntryOrigin.chatDraft`; `SupportSessionCoordinator.leaveActivity(_:)` keeps a Chat session open and keeps "Done for now" for Today, Explore and onboarding. |
| "Context" took the conversation title's space | A text toolbar button | The `brain.head.profile` symbol, labelled "Context" for VoiceOver |
| "Voice isn't available for this conversation right now" | The same closed session: voice accepted only open sessions | From the new-chat screen, voice continues a closed session in a new linked session with a conversation of its own. On a closed conversation, voice stays unavailable: a conversation belongs to one session (`support_do_create`, `support_work_sessions_conversation_uidx`, and SUPPORT_SESSION_SPEC's "Continue as a new session"). |
| Voice close button under the Dynamic Island, controls too high, uneven spacing | `.ignoresSafeArea()` on the whole screen; full-width button style | Only the background ignores the safe area; compact controls, close on the left, captions and voice on the right |
| Microphone prompt only after closing voice | Permission was requested at Start voice | The mic button asks when access is undecided; the microphone stays off until Start voice |
| Today's quick tiles wrapped mid-word, "Check in" sat at the top | Fixed three columns | Three across only while every word fits at the current text size, otherwise stacked; centred content |
| Activity response field hidden behind the keyboard toolbar | The floating toolbar reserves no space | A bottom inset while typing, and the field scrolls into view |
| Locking the phone during an activity returned to Today | Backgrounding paused and dismissed the activity | The activity stays open; locking saves the step and stops the practice clock. If the app ends, Today offers to continue (SUPPORT_SESSION_SPEC §7.2). |

- Codex reviewed each push. Its findings changed the voice continuation (the first version reused the closed conversation, which the server rejects) and the practice clock: it stops before the background save rather than after, and saves that finish in the background no longer restart it.
- Tests: `testLeavingAnActivityStartedFromChatKeepsTheConversationSessionOpen` and `testVoiceOnAClosedConversationIsUnavailable` failed before their fixes and pass after; `SupportSessionCoordinatorTests` and `SupportSessionCloudServiceTests` pass 93/93. The two clock changes have no automated test, because the timing lives in the view's scene-phase handling.
- Apple Health: the owner could not leave Apple's "Health Access" sheet after turning on all seven topics. Sentry replay `21652133` shows the sheet opening at 96.6 s and no request or navigation for the rest of the session (about 160 s), and no `healthkit_connections` row was written, so `requestAuthorization` never returned. On iOS 27 the sheet has no buttons at the top (owner's screenshot, 3:29 PM EST); whether Allow sits below the topic list is not yet confirmed on the device.
- Restore Purchases was not tested on 2.0.0 and was dropped from the checks: the owner's account is premium, and `SubscriptionView` shows Restore Purchases only without an active subscription. The restore path was last verified at 8:00 AM EST on 1.0.6 against `verify-purchase` v37 (Production changes, above).

## What's New in 2.0.0 (App Store text)
MindFriend 2.0 is calmer and more personal, built around four places: Today, Chat, Explore and You.

Today
• A greeting by name and one clear way to begin: pick up where you left off, or start a conversation.
• Quick ways in: check in with yourself, a 1-minute breathing exercise, or untangle a thought.
• A little progress: today's quest, your level and how close you are to the next one.
• Pin up to three favorites and reorder them with Edit.

Chat
• Voice and text continue in the same conversation. MindFriend keeps the confirmed text of a voice call, not a recording.
• You decide what MindFriend remembers. See which messages a memory suggestion would use, review every suggestion before it's saved, and stop using or forget any memory at any time.
• Each reply can show which saved context it used.
• History keeps your sessions together. Search, rename, continue or delete them.

Explore
• Browse by category, with suggestions for you at the top.
• Try one small thing on your own: a grounding exercise, untangling a thought, or choosing one next step. Your progress is saved on your device, so you can stop and come back.

You
• Your progress, history, settings and help in one place.

Made for you
• One calm navy theme on every screen, in light and dark mode, with better contrast and no cut-off text at large text sizes.
• Reward moments: XP, level-ups, badges and milestones, plus a quiet confirmation when you finish an activity, save a reflection or close a session.
• Streak counts no longer appear in the app.

Free plan
• 30 AI chat messages a day. Chat shows how many you have left and when more arrive.

Fixes and improvements
• Subscriptions: switching plans is recognized right away, and Restore Purchases confirms Premium reliably.
• Mentorship: messages, read receipts, reports and safety checks save reliably, and ending a mentorship asks you to confirm.
• Family and partner: invitations go to the intended person, removing a member keeps their own purchases, and partner sharing respects each person's choices.
• Peer support sessions connect to real conversations.
• Journal: edits and prompt choices are kept while you write.
• Sleep: nights are grouped by the day you wake up, and bedtimes after midnight score correctly.
• Voice: drafts are kept and transcripts save reliably when you're interrupted.
• Apple Watch: today's data refreshes at the start of each day.
• Sign-in, sign-out and account deletion finish their cleanup before you continue.
• Chat history loads completely, page by page.
