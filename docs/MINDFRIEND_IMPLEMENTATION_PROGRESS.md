# MindFriend support-session implementation

Canonical specification: `docs/SUPPORT_SESSION_SPEC.md`, v1.0, 6 November 2026. Exact supplied file `/Users/danny/Downloads/spec(20261106-214540).md`, SHA-256 `f2c0ca1ac957e9dbc321ab838d3cc45d7cb7c81bec28e45f98d6f4196d5d2242`. No product amendment was made.

Repository: `scalinity/MindFriend`, GitHub ID `1135506345`, origin `https://github.com/scalinity/MindFriend.git`. Branch: `implementation/support-session-20261106`. Implementation base: `bba67bb6e059e32fe60765f0ed0c77697d71bc7b`; spec/baseline checkpoint: `8bdab5bbd63377313b5c3691a54a4ee2fad693c5`. Implementation revision is recorded in Git and the final close-out paragraph below. Root AGENTS.md and CLAUDE.md apply; no additional nested tracked instructions were found. The supplied canonical spec is unchanged.

The only inherited local file was untracked `supabase/operations/20261022_repair_cron.sql`, SHA-256 `5c1a6c8256331dd309708b8acf83c7516591efdda1720805330772602f6004cb`. It is excluded from this implementation's staging and must remain unchanged. Historical migration files and the merged provider baseline are preserved. Project registrations were added directly; xcodegen was not run because it drops the existing Watch targets.

Production data/schema/deployment, live configuration/billing/secrets and App Store actions were not performed. The existing Docker stack `stir`, its ports and unrelated simulators were not reset or modified.

## Integration with the app repair branch

The complete feature implementation was committed as `5122419ba043edf477e131bc126406a60c8b94b8`; its GitHub Actions run [42400202390](https://github.com/scalinity/MindFriend/actions/runs/42400202390) succeeded. The feature branch integrates pinned `main` revision `66633ef440bf82e07f71d4205b1b3aba70bd9109`, preserving its SDK authentication/logout fixes, account-service lifecycle, chat keyset paging, observed-speech handling, Health sleep import, companion ingestion and authorization migrations. The separately owned privacy worktree is unchanged by this task.

The pre-integration checks below apply to `5122419`. Current combined-source checks are recorded separately; they are not inferred from those earlier results. Fourteen merge conflicts were reconciled without regenerating the Xcode project or removing Watch targets. Memory suggestions now verify current entitlement through the same `refresh_user_entitlement` authority as Chat and reject stale cached premium flags.

| Combined-source check | Result | Evidence / limits |
|---|---|---|
| Final combined Swift selection | PASS: 569 tests, 0 failures | `integrated-final-swift-tests-r2.log`; complete union of the Support/auth/data/voice/history/Health/offline and main lifecycle/sleep selections, plus actual SDK credential-failure/deleted-owner restore and page-boundary voice regressions. Earlier separate 379/184 runs are retained and are not added again |
| Backend handler fixtures | PASS: 228 tests / 143 steps | `integrated-backend-fixtures-r2.log`; no network permission. R1 failed because the Chat fixture still modeled the older entitlement RPC; the corrected fixture is retained alongside that failure |
| Backend entrypoint typecheck | PASS | `integrated-backend-typecheck-r1.log`; four affected entrypoints |
| Fresh combined forward SQL chain | PASS | `integrated-support-fresh-summary-r2.json`; 212 unchanged frozen baseline migrations, then all 48 sorted forward files (12 support, 35 app-repair and one integration correction). All seven additional overlap fixtures and 45 recorded concurrency/trigger checks pass; exact container removed |
| Modeled combined forward SQL chain | FAIL; restoration promotion blocked | `integrated-support-modeled-summary-r1.json`; stops in inherited `20261106225731_repair_mentorship_discovery_contract.sql` before the new feature contract checks: the October schema has `calculate_timezone_overlap(tz1 text,tz2 text)`, while the migration declares `p_tz1`/`p_tz2`. PostgreSQL refuses the parameter-name change. No destructive drop or historical rewrite was attempted; exact container removed |
| Integration regression reproduction | EXPECTED FAIL on the prior 47-file chain | `integration-negative-control-summary.json`; the new cross-path fixture rejects the old arrival-clock result. This is defect reproduction, not a feature PASS |
| Combined native journeys | PASS: 7 selected tests | `current-main-integrated-ui-r1.log`; auth rejection, consent/Help, selected-answer editable draft, memory default-off/dark preview, termination/relaunch, grounding and saved-step History rename/search/delete. Synthetic account/network-denied fixture; captures exported and selected Chat/memory/History screens inspected |
| Integration independent review | Collected and reconciled | Three native Claude Sonnet phases returned INT001–INT012. The bounded SQL proposal was approved for synthetic execution. Final fixes follow the reviewed day-lock/warning/dependency/fixture remedies and are verified by the parent; see `SUPPORT_SESSION_REVIEW.md` |

## Current usable implementation

Today, Chat, Explore and You are stable destinations. Today has one local start/resume card, optional mood entry, at most three explicit pins, and direct crisis resources. Simpler view is immediately reversible. First-run setup captures the original 13+ and consent requirements without a simulated conversation or compulsory wellness taxonomy.

The protected per-account journal and ordered outbox preserve acknowledged checkpoints, unsent editable chat drafts, pending/rejected transcript finals and immutable operations. Recovery, deletion and conflict choices are explicit. Grounding has canonical exercise completion/reward; Untangle keeps original session-owned answers; a practical step distinguishes saved from self-reported done. Reflection has no default and answer sharing defaults off. Ask for help/Talk about this show selected fields and prepare an editable durable Chat draft; returning never generates automatically.

Memory controls unify confirmed, pending, stale, disabled and deletion-pending records with actual provenance. Explicit Suggest memories from this session opens a read-only exact-source preview, starts with no selected messages, and requires a separate Generate choice. The bounded backend produces review-only candidates under one durable request identity, atomic quota admission and existing budget checks. Private Vault remains device-only and outside AI context.

Chat retains one strict terminal proposal, actual context receipts, ambiguous-save reconciliation and the deterministic chooser. Voice uses a claim-bound server context packet, bounded privacy lease, explicit resume and truthful transcript acknowledgement. Unified History loads older work with cursor paging, search/filters, meaningful saved/completed metadata, inspectable detail and rename/delete/linked continuation. Export includes the 26 fixed cloud datasets and protected local support data with incomplete/pending/rejected states explicit. Health distinguishes permission-request completion, samples available, no recent data, query failure and unavailable capability, with account-bound sync pause.

These are implemented development paths. Authenticated service/provider acceptance requires the separately established nonproduction target below; missing new privacy capability fails closed rather than silently using an older context route.

## Milestones and gates

| Milestone | Implementation status | Validation boundary |
|---|---|---|
| M0 | implemented | Exact source/instructions/baseline/inherited-file and 26-route inventory; consent SQL/wire/native controls; full authenticated route matrix and human first-use wording unrun |
| M1 | implemented | Journal, owner/epoch, quota, offline handler and transcript foundations pass focused registered tests and synthetic failure/race checks |
| M2 | implemented | Four-destination shell and actual compact/iPad journeys; final actual-appearance matrix passed and is recorded below; full device/settings matrix remains partial |
| M3 | implemented; restoration gate remains | Current fresh combined chain and all contract fixtures pass. The modeled combined chain stops at the inherited mentorship parameter-name conflict; its later feature checks are NOT_RUN. Exact real environment ledger/HTTP behavior remains unverified |
| M4 | implemented | Strict Responses/handler/receipt/proposal fixtures pass; live Luna schema/stream smoke blocked on a nonproduction target |
| M5 | implemented | Three complete local loops, selected-answer preview/draft, reflection/Done/Close/Discard and reminder domain verified; OS notification delivery unrun |
| M6 | implemented | Voice/context/transcript/return/history source and focused fixtures verified; physical audio and live relay continuity unrun |
| M7 | implementation present; acceptance partial | Independent findings reconciled and local checks run. Device, complete system accessibility settings, performance and five-person checks remain incomplete |

| Gate | Result | Exact boundary |
|---|---|---|
| G0 | PASS, source/local | Verified checkout and preserved work, current toolchain/destinations, original consent requirement located and implemented |
| G1 | PASS, tested local scope | Durable owner-bound journal, immutable operation/result recovery, privacy suppression and no Home quota reset; physical protected-data behavior belongs to G4 |
| G2 | PARTIAL (8 Nov) | Local nonproduction stack `mindfriend-release106` with real OpenAI/xAI calls and captured provider payloads: confirmation, owner/epoch, quota, old-client shape, memory and receipts PASS; live voice relay NOT_RUN (local WebSocket upgrades fail). See `docs/RELEASE_1_0_6.md` Phase 3 |
| G3 | PARTIAL; release blocked | Fresh combined chain, two-owner RLS/RPC, export/replay/locking pass. Modeled combined chain fails at the inherited mentorship argument-name conflict. Production ledger, storage policy parity, PostgREST and released-client matrix are unverified |
| G4 | PARTIAL | Actual Xcode simulator builds, native journeys and selected accessibility audits. No physical iPhone is available in the final inventory; accessible destinations are simulators. Physical Health/audio/permissions/protected-data checks NOT_RUN |
| G5 | WAIVED by owner for 1.0.6 | The five-person studies are not required for this release; no clinical usefulness claim |

## Executed checks

All logs, results, manifests, screenshots, review packets and retained failures are under the ignored `artifacts/support-session/` directory. The table above is the current combined-source evidence. The following table retains component/pre-integration evidence at `5122419`; those passes do not override the current modeled-chain failure. Checks are not summed across overlapping runs.

| Check | Result | Evidence / limits |
|---|---|---|
| Final registered Swift selection | PASS: 333 tests, 0 failures | `final-registered-support-tests.log`; repository/coordinator/cloud/export/history/memory/chat/reminder/offline/Health/transcript/navigation classes. Actual app/test targets, iOS simulator, parallel testing disabled |
| Earlier voice integration | PASS: 202 selected tests | `voice-integrated-tests-r1.log`; later lifecycle/journal corrections have their own focused results (`final-root-d-remediation-tests-r1.log`, 99; final journal cases are in the 333 selection). Hardware is faked |
| Settled E/client/export check | PASS: 149 selected tests | `final-e-memory-client-export-tests-r2.log`. Earlier r1 had two export assertions against changing test expectations and remains failed/retained |
| Final backend fixtures | PASS: 230 tests / 141 steps, 0 failures | `final-backend-fixtures.log`; real handlers/parsers with fake REST/RPC/provider, cached dependencies, read/env permissions, no network permission. This is a focused set, not the whole backend suite |
| Final backend entrypoint typecheck | PASS | `final-backend-typecheck.log`; chat, support-session, support-memory-suggestions, voice-token |
| Fresh migration/contract path | PASS | `settled-support-fresh-summary.json`; 212 hash-pinned active frozen baseline migrations plus all new migrations through 080000; no real accounts or network; owned container removed |
| Modeled restoration path | PASS | `settled-support-modeled-summary.json`; exact October 22 schema-only fixtures plus 28 later frozen migrations and full new chain; not an observed production ledger; owned container removed |
| SQL replay/reward/history/privacy/export | PASS in both paths | 100 identical create/start/finish/chat-confirm calls, changed payload rejection, one canonical completion/30 XP, forged cross-owner support/canonical completion and reward denial, 126 tied-cursor sessions, metadata and 26-dataset owner-safe pagination |
| SQL concurrent/trigger checks | PASS: 35 checks per path | 34 real competing-connection schedules and one FK statement-trigger observation. Includes simultaneous first consent, completion retries, correction/Forget/approval/confirmation/deletion order, final transcript races and expected-deadlock negative controls |
| Earlier offline SQL/receipt qualification | PASS, separately attributed | `offline-fresh-run-summary-r2.json`, `offline-modeled-run-summary.json`; exact frozen baseline/retained-day/online-offline reward/rollback and timeout checks. New support runs do not replace these claims |
| Actual consent controls/Help | PASS, synthetic native fixture | `ui-history-consent-r3.log`; 13+ boundary/explicit confirmations/optional choices and actual Crisis Resources screen. No real consent saved |
| Public Terms/Privacy pages | PASS: HTTP 200 and expected page content | `.firecrawl/legal-terms.json`, `.firecrawl/legal-privacy.json` under artifacts; not processor-disclosure or browser-handoff acceptance |
| Grounding / termination-relaunch Untangle | PASS, synthetic native fixture | Earlier local journey logs and captured journal recovery; production presenters, isolated fixture owner, denied network |
| Saved step / closed History rename-search-delete | PASS, compact native fixture | `ui-history-discussion-r1.log`; input, save, resume, self-reported done, reflection, Done, closed rename, search and Delete |
| Deliberate selected-answer Chat draft | PASS on compact iPhone and iPad | `ui-sharing-ipad-audit-r3.log` records mixed test outcomes; individual chosen-answer journeys passed. `ui-memory-reflection-r2.log` repeats that journey successfully on compact after later reflection changes; its separate memory-preview test failed only its scroll bound |
| Landscape / iPad controls and captions | PASS for named fixture cases | `ui-landscape-r3.log`, `ui-ipad-core-r2.log`; assertions verify actual width > height; long partial caption value and End/Text/Unmute controls. No microphone/service is created |
| Largest-text Chat | PASS, selected audits | `ui-compact-chat-title-r4.log` and iPad r3 result. Compact accessibility title uses short Chat in navbar and preserves the full original title in wrapping body |
| Memory full-source/default-off preview | PASS, compact native fixture | `ui-memory-preview-r4.log`; full source label, disabled Generate, native accessibility audit. That capture revealed an appearance-fixture override; replacement actual-appearance run below supersedes its dark label |
| Full Today text sizes / actual appearance | PASS: 24 combinations plus 3 compact journeys | `ui-actual-appearance-matrix-r1.log`; 4 selected tests pass: 12 Dynamic Type sizes × light/dark, memory preview, grounding and largest-text Chat; actual rendered scheme asserted. Earlier named appearance runs did not prove the enclosing scheme and are not counted for dark-mode acceptance |

The final iPad actual-appearance run also passes all 3 selected tests (`ui-ipad-actual-appearance-r1.log`): real landscape/four destinations, dark full-source memory preview and largest-text Chat accessibility audit. Actual dark compact captures were inspected after export; earlier light captures mislabeled dark are retained as failed validation evidence.

The historical pre-integration full-suite baseline recorded an unrelated CircleFull wording failure (`m0-focused-tests-retry.log`, 40/41). A worker's broader backend run reported an unchanged image-generation test failure; that is not a parent whole-suite pass or a reason to modify the unrelated image feature.

## Acceptance ledger

PASS (local) means the listed local/automated/simulator criterion was demonstrated within that scope. PARTIAL and NOT_RUN are incomplete acceptance; a source implementation is not a substitute for the required environment.

| ID | Result | Evidence / remaining boundary |
|---|---|---|
| AC-01 | PASS (local close-out) | Identity/base/inherited file recorded; exact spec and all 212 baseline files preserved; implementation and integration commits are recorded in Git/final report |
| AC-02 | PARTIAL | All 26 legacy routes mapped and focused navigation tests pass; exhaustive authenticated native route matrix unrun |
| AC-03 | PASS (local/simulator) | Real atomic file fault/recovery tests and acknowledged Untangle termination/relaunch restoration |
| AC-04 | PASS (synthetic DB) | 100 exact replays, changed payload rejection, simultaneous completion cases and one 30 XP reward |
| AC-05 | PARTIAL; device part scheduled for Phase 9 | Service owner/epoch checks PASS on the local stack (8 Nov, release 1.0.6 G2 check 3): `expected_owner` mismatch 409 before any claim, stale privacy revision 409 without a debit, another account 404. Real-device account switch during streaming is scheduled for the Phase 9 physical-iPhone run |
| AC-06 | PARTIAL | Server suppression, Forget and cross-account denial PASS over HTTP on the local stack (G2 checks 3 and 7). A second physical device was not used |
| AC-07 | PASS (local service, captured provider payloads) | G2 check 7: the captured OpenAI request contains exactly the receipt's sources; journal, mood, HRV, other conversations, stopped/forgotten memories and pending suggestions are absent; `conversation_only` sends no saved memory |
| AC-08 | PARTIAL | Transitive Forget/scrub/tombstone/conflict tests pass; complete live correction/receipt UI walkthrough unrun |
| AC-09 | PARTIAL | Fixed four destinations and old routes in source/tests/native fixtures; every entitlement/account runtime combination unrun |
| AC-10 | PARTIAL | One Today card inspected; three-pin/explicit replacement source and domain checks. Full native pin replacement matrix unrun |
| AC-11 | PARTIAL | Direct retained hubs, Chat and offline Help verified in source/selected native checks; every root's exact Circles tap task unrun |
| AC-12 | PARTIAL | Consent wire/SQL/first-run controls and public legal content pass; real consent HTTP/browser handoff and human wording review unrun |
| AC-13 | PARTIAL | Unified state/provenance/contracts and explicit Generate preview implemented/tested; full native memory-state correction matrix unrun |
| AC-14 | PARTIAL | Live completed stream PASS (G2 check 1): streamed text equals the confirmed text. Refusal and incomplete terminals could not be provoked live and remain fixture-only. Cancelled streams keep a non-retryable claim by design (`issue15_chat_test.ts`) |
| AC-15 | PASS (local/synthetic) | One user acceptance creates one activity; proposal/chooser/Not now never generate automatically; untrusted URLs/IDs rejected |
| AC-16 | PASS (source/fixtures) | 4,000 UTF-16 input, 128,000-byte prompt, 500-token main chat, budget/quota/cancellation/claim and safety/key/provider boundaries retained; live configuration not inferred |
| AC-17 | PARTIAL | Authoritative usage/period/entitlement fixtures and daily quota SQL pass; StoreKit sandbox and complete runtime entitlement matrix unrun |
| AC-18 | PASS (synthetic DB) | Two-owner RLS/RPC, direct-write/anon denial, forged attachment/completion/reward and zero-row classification |
| AC-19 | PASS (copy of production); production apply in Phase 6 | All 49 pending migrations, including `20261106000000_reconcile_production_drift.sql`, apply to a restore of production's 8 November schema; the post-push catalog converges with the fresh chain (release record, Phase 2) |
| AC-20 | PASS (source/local/synthetic) | Bounded content-free logs; new records covered by explicit export/delete with owner/epoch and pending/rejected states; Private Vault boundary retained |
| AC-21 | PASS (local/simulator/synthetic) | Grounding checkpoints, silent/Skip/Finish semantics, canonical registry and exactly-once completion/reward |
| AC-22 | PASS (local/simulator) | Original Untangle answers retained; deliberate field preview/draft; no implicit journal/XP; discard scrubs queued/conflict copies |
| AC-23 | PASS (source/local/selected native) | Immediate Simpler reversal; actual offline resources; existing professional/crisis opt-in scope retained |
| AC-24 | PASS (local/simulator) | Nonempty practical step, saved vs self-reported done vs dismiss, duplicate completion guard and native Saved-step journey |
| AC-25 | PASS (local/fixtures/selected native) | Neutral reflection/no default, sharing off, exact approved excerpt and editable deliberate Chat handoff; no automatic paid return |
| AC-26 | PARTIAL | Done/Close/reminder generation/projection/reconcile/cancel tests pass; real OS permission/delivery/clock behavior unrun |
| AC-27 | PARTIAL | Voice admission, packet, correction and text continuity PASS (G2 check 8); Enhanced Privacy now narrows voice like text (PR #68). The live relay socket and five-second lease could not run: WebSocket upgrades fail inside the local edge runtime. Scheduled for the Phase 9 device run against production |
| AC-28 | Scheduled for Phase 9 | Physical iPhone: interruption, background/lock, Bluetooth/headphone loss, permissions and audio |
| AC-29 | PARTIAL; device part scheduled for Phase 9 | Durable order/finality/retry and SQL transcript races pass; real device/service interruptions run in Phase 9 |
| AC-30 | PASS (synthetic/local/selected native) | Cursor >100/tied dates, meaningful cloud summaries, preserved names, closed inspect/rename/delete/new linked continuation |
| AC-31 | PARTIAL | 8 Nov: every destination at every Dynamic Type size in light and dark on a compact iPhone, plus the full system accessibility audit (`.all`) per destination under default, dark, Increase Contrast and Reduce Motion + Reduce Transparency, on compact iPhone and iPad. Fixed: support-palette tint and prominent headers, Chat empty state scrolling, profile row stacking, on-accent button labels, "Not yet" placeholders. Open audit findings: "Plans and Premium" row reported clipped (not visible at AX5); text under the translucent tab bar and iPad sidebar vibrancy/offscreen panes. iPad window resizing and a live VoiceOver walkthrough are not automatable here and remain for the device run |
| AC-32 | PARTIAL; device part scheduled for Phase 9 | Distinct Health query/sample states, owner race and opt-out tests pass; real permission/no-data/query-failure cases run in Phase 9 |
| AC-33 | WAIVED by owner for 1.0.6 | The five-person first-use study is not required for this release |
| AC-34 | WAIVED by owner for 1.0.6 | The five-person context-comprehension study is not required for this release |
| AC-35 | PARTIAL; target not met | 8 Nov, Mac to local functions, providers over this Mac's connection, 10 samples each: non-streaming p95 2,361 ms (target ≤3,500, met); first text delta p95 1,662 ms (target ≤1,000, not met). Targets not relaxed. Named-device 30-sample capture scheduled for Phase 9 |
| AC-36 | PASS (reporting scope) | Independent review dispositions, current fresh PASS/modeled FAIL, and all unrun service/device/human/performance gates are recorded separately; no production or App Store action |

## Review, rollout and remaining work

`SUPPORT_SESSION_REVIEW.md` accounts for every collected finding, including rejected suggestions with concrete evidence. Review parser correspondence warnings were reconciled locally. Accepted/uncertain NativePeers inputs were not replayed; timeouts and collection failures remain failures even when source was recovered and independently qualified later.

`SUPPORT_SESSION_ROLLOUT.md` prepares the exact future order and recovery boundary. Issues 56 and 57 were read again on 7 November 2026 and remain OPEN. No live `AI_PROVIDER` value, function body, production migration ledger or processor-disclosure parity is inferred. Released-client HTTP 426 relay and HTTP 428 PCM gates remain explicit; private-media operations stay separate.

The only work that can establish the remaining service/device/human criteria requires the missing environment or participants. Do not mark the whole specification accepted from this local branch. Do not deploy or submit to the App Store from this implementation authorization.

## Local reproduction and retained state

Open `apps/ios/MindFriendApp.xcodeproj`, scheme `MindFriendApp`. The DEBUG-only launch argument `--support-session-ui-test` opens the production support presenters with a separate synthetic journal and denied network; `--support-fixture-run` accepts a UUID for reproducible relaunch. This does not simulate successful generation or real account sync. Tests set their own isolated fixture identities and assert actual state.

Focused commands are recorded in the logs/acceptance scripts. The SQL harness is `artifacts/support-session/validate_support_sql.py fresh|modeled`, with hash-pinned schema-only fixtures and exact local image; it creates no host ports/mounts and always records exact-container teardown. Its source inputs are pinned in `candidate-reviewed-inputs.json`. Do not replace this with a reset of the existing `stir` stack.

The implementation and integration are recorded on `implementation/support-session-20261106`; the final report records the exact pushed revision and CI state. The inherited cron SQL and supplied specification are unchanged, and all 212 frozen baseline migrations match byte for byte. All owned test processes and disposable containers have finished. The earlier three task simulators and the later combined-acceptance simulator were removed; the unrelated booted simulator was observed unchanged.

Cleanup retained the exact compiled app/dylib/Info hashes and verified all 15 package checkouts clean before deleting regenerated task build/package/module caches. The final cleanup removed 6,189,641,728 allocated bytes of caches and 2,781,880,320 allocated bytes from the last owned simulator; these measurements are not a volume free-space delta and are separate from the earlier cleanup. Reports/logs/manifests/xcresults remain under `artifacts/support-session` (about 105 MiB). Ten tool-owned NativePeers worktrees remain (about 483 MiB): its fresh planner refuses retirement of resumed histories. Exact paths, sizes and reasons are in `artifacts/support-session/retained-native-workspaces.json`; they were not force-removed. The existing CodeGraph index, other branches and shared services are preserved.

No production SQL/deployment/configuration/billing/secret or App Store action occurred. G2–G5 and the modeled restoration prerequisite remain as stated above; this branch is not approval to release.
