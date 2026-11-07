# MindFriend support-session implementation

Canonical specification: `docs/SUPPORT_SESSION_SPEC.md`, v1.0, 6 November 2026. Exact supplied file `/Users/danny/Downloads/spec(20261106-214540).md`, SHA-256 `f2c0ca1ac957e9dbc321ab838d3cc45d7cb7c81bec28e45f98d6f4196d5d2242`. No product amendment was made.

Repository: `scalinity/MindFriend`, GitHub ID `1135506345`, origin `https://github.com/scalinity/MindFriend.git`. Branch: `implementation/support-session-20261106`. Implementation base: `bba67bb6e059e32fe60765f0ed0c77697d71bc7b`; spec/baseline checkpoint: `8bdab5bbd63377313b5c3691a54a4ee2fad693c5`. Implementation revision is recorded in Git and the final close-out paragraph below. Root AGENTS.md and CLAUDE.md apply; no additional nested tracked instructions were found. The supplied canonical spec is unchanged.

The only inherited local file was untracked `supabase/operations/20261022_repair_cron.sql`, SHA-256 `5c1a6c8256331dd309708b8acf83c7516591efdda1720805330772602f6004cb`. It is excluded from this implementation's staging and must remain unchanged. Historical migration files and the merged provider baseline are preserved. Project registrations were added directly; xcodegen was not run because it drops the existing Watch targets.

Production data/schema/deployment, live configuration/billing/secrets and App Store actions were not performed. The existing Docker stack `stir`, its ports and unrelated simulators were not reset or modified.

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
| M3 | implemented | Full new schema/RLS/RPC/privacy/memory/history/Generate/export chain passes both disposable paths; exact real environment ledger/HTTP behavior unverified |
| M4 | implemented | Strict Responses/handler/receipt/proposal fixtures pass; live Luna schema/stream smoke blocked on a nonproduction target |
| M5 | implemented | Three complete local loops, selected-answer preview/draft, reflection/Done/Close/Discard and reminder domain verified; OS notification delivery unrun |
| M6 | implemented | Voice/context/transcript/return/history source and focused fixtures verified; physical audio and live relay continuity unrun |
| M7 | implementation present; acceptance partial | Independent findings reconciled and local checks run. Device, complete system accessibility settings, performance and five-person checks remain incomplete |

| Gate | Result | Exact boundary |
|---|---|---|
| G0 | PASS, source/local | Verified checkout and preserved work, current toolchain/destinations, original consent requirement located and implemented |
| G1 | PASS, tested local scope | Durable owner-bound journal, immutable operation/result recovery, privacy suppression and no Home quota reset; physical protected-data behavior belongs to G4 |
| G2 | BLOCKED | No explicitly established nonproduction service/provider target with bounded credentials/budget. No real AI request was made; injected fetches are fixtures |
| G3 | PARTIAL | Fresh and modeled restoration-chain applicability, two-owner RLS/RPC, export/replay/locking pass. Production ledger, storage policy parity, PostgREST and released-client matrix are unverified |
| G4 | PARTIAL | Actual Xcode simulator builds, native journeys and selected accessibility audits. Final device inventory contains only simulators; physical Health/audio/permissions/protected-data checks NOT_RUN |
| G5 | NOT_RUN | Five representative first-use/context-comprehension participants were not available; no clinical usefulness claim |

## Executed checks

All logs, results, manifests, screenshots, review packets and retained failures are under the ignored `artifacts/support-session/` directory. Checks are not summed across overlapping runs.

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

The canonical full-suite baseline has an unrelated CircleFull wording failure (`m0-focused-tests-retry.log`, 40/41). A worker's broader backend run reported an unchanged image-generation test failure; that is not a parent whole-suite pass or a reason to modify the unrelated image feature.

## Acceptance ledger

PASS (local) means the listed local/automated/simulator criterion was demonstrated within that scope. PARTIAL and NOT_RUN are incomplete acceptance; a source implementation is not a substitute for the required environment.

| ID | Result | Evidence / remaining boundary |
|---|---|---|
| AC-01 | PARTIAL until close-out | Identity/base/inherited file recorded; final named-path commit and preservation check below |
| AC-02 | PARTIAL | All 26 legacy routes mapped and focused navigation tests pass; exhaustive authenticated native route matrix unrun |
| AC-03 | PASS (local/simulator) | Real atomic file fault/recovery tests and acknowledged Untangle termination/relaunch restoration |
| AC-04 | PASS (synthetic DB) | 100 exact replays, changed payload rejection, simultaneous completion cases and one 30 XP reward |
| AC-05 | PARTIAL | Owner/epoch/cache/queue/cloud/voice delayed-callback tests pass; real streaming/account-switch service/device scenario unrun |
| AC-06 | PARTIAL | Local immediate suppression and server source/closure/revision tests pass; two-device HTTP scenario unrun |
| AC-07 | PARTIAL | Conversation-only payload/receipt fixtures exclude all prohibited domains; actual nonproduction provider-bound request capture unrun |
| AC-08 | PARTIAL | Transitive Forget/scrub/tombstone/conflict tests pass; complete live correction/receipt UI walkthrough unrun |
| AC-09 | PARTIAL | Fixed four destinations and old routes in source/tests/native fixtures; every entitlement/account runtime combination unrun |
| AC-10 | PARTIAL | One Today card inspected; three-pin/explicit replacement source and domain checks. Full native pin replacement matrix unrun |
| AC-11 | PARTIAL | Direct retained hubs, Chat and offline Help verified in source/selected native checks; every root's exact Circles tap task unrun |
| AC-12 | PARTIAL | Consent wire/SQL/first-run controls and public legal content pass; real consent HTTP/browser handoff and human wording review unrun |
| AC-13 | PARTIAL | Unified state/provenance/contracts and explicit Generate preview implemented/tested; full native memory-state correction matrix unrun |
| AC-14 | PARTIAL | Strict terminal parser and ambiguous-confirmation fixtures pass; bounded real-provider smoke unrun |
| AC-15 | PASS (local/synthetic) | One user acceptance creates one activity; proposal/chooser/Not now never generate automatically; untrusted URLs/IDs rejected |
| AC-16 | PASS (source/fixtures) | 4,000 UTF-16 input, 128,000-byte prompt, 500-token main chat, budget/quota/cancellation/claim and safety/key/provider boundaries retained; live configuration not inferred |
| AC-17 | PARTIAL | Authoritative usage/period/entitlement fixtures and daily quota SQL pass; StoreKit sandbox and complete runtime entitlement matrix unrun |
| AC-18 | PASS (synthetic DB) | Two-owner RLS/RPC, direct-write/anon denial, forged attachment/completion/reward and zero-row classification |
| AC-19 | PARTIAL | Both exact disposable paths and missing-capability/legacy fixtures pass; actual selected-environment ledger/storage/client parity unverified |
| AC-20 | PASS (source/local/synthetic) | Bounded content-free logs; new records covered by explicit export/delete with owner/epoch and pending/rejected states; Private Vault boundary retained |
| AC-21 | PASS (local/simulator/synthetic) | Grounding checkpoints, silent/Skip/Finish semantics, canonical registry and exactly-once completion/reward |
| AC-22 | PASS (local/simulator) | Original Untangle answers retained; deliberate field preview/draft; no implicit journal/XP; discard scrubs queued/conflict copies |
| AC-23 | PASS (source/local/selected native) | Immediate Simpler reversal; actual offline resources; existing professional/crisis opt-in scope retained |
| AC-24 | PASS (local/simulator) | Nonempty practical step, saved vs self-reported done vs dismiss, duplicate completion guard and native Saved-step journey |
| AC-25 | PASS (local/fixtures/selected native) | Neutral reflection/no default, sharing off, exact approved excerpt and editable deliberate Chat handoff; no automatic paid return |
| AC-26 | PARTIAL | Done/Close/reminder generation/projection/reconcile/cancel tests pass; real OS permission/delivery/clock behavior unrun |
| AC-27 | PARTIAL | Server packet/lease/claim/relay and Swift lifecycle fixtures pass; live text→voice→text/provider continuity unrun |
| AC-28 | NOT_RUN | No physical iPhone available; interruption/background/lock/Bluetooth/permission/audio acceptance requires one |
| AC-29 | PARTIAL | Durable order/finality/retry/acknowledgement and SQL transcript races pass; real device/service interruptions unrun |
| AC-30 | PASS (synthetic/local/selected native) | Cursor >100/tied dates, meaningful cloud summaries, preserved names, closed inspect/rename/delete/new linked continuation |
| AC-31 | PARTIAL | Compact/full iPad/real landscape and selected native audits; actual-appearance matrix passed. Split/window resizing, VoiceOver, Reduce Transparency and Increase Contrast unrun |
| AC-32 | PARTIAL | Distinct Health query/sample states, owner race and opt-out tests; physical permission/no-data cases unrun |
| AC-33 | NOT_RUN | Five-person first-use study unavailable |
| AC-34 | NOT_RUN | Five-person context-comprehension study unavailable |
| AC-35 | NOT_RUN | Named physical device/network/provider timing and 30-sample captures unavailable; targets not relaxed |
| AC-36 | PARTIAL until final report | Independent review dispositions recorded; final report must retain these separate evidence layers and no-release boundary |

## Review, rollout and remaining work

`SUPPORT_SESSION_REVIEW.md` accounts for every collected finding, including rejected suggestions with concrete evidence. Review parser correspondence warnings were reconciled locally. Accepted/uncertain NativePeers inputs were not replayed; timeouts and collection failures remain failures even when source was recovered and independently qualified later.

`SUPPORT_SESSION_ROLLOUT.md` prepares the exact future order and recovery boundary. Issues 56 and 57 were read again on 7 November 2026 and remain OPEN. No live `AI_PROVIDER` value, function body, production migration ledger or processor-disclosure parity is inferred. Released-client HTTP 426 relay and HTTP 428 PCM gates remain explicit; private-media operations stay separate.

The only work that can establish the remaining service/device/human criteria requires the missing environment or participants. Do not mark the whole specification accepted from this local branch. Do not deploy or submit to the App Store from this implementation authorization.

## Local reproduction and retained state

Open `apps/ios/MindFriendApp.xcodeproj`, scheme `MindFriendApp`. The DEBUG-only launch argument `--support-session-ui-test` opens the production support presenters with a separate synthetic journal and denied network; `--support-fixture-run` accepts a UUID for reproducible relaunch. This does not simulate successful generation or real account sync. Tests set their own isolated fixture identities and assert actual state.

Focused commands are recorded in the logs/acceptance scripts. The SQL harness is `artifacts/support-session/validate_support_sql.py fresh|modeled`, with hash-pinned schema-only fixtures and exact local image; it creates no host ports/mounts and always records exact-container teardown. Its source inputs are pinned in `candidate-reviewed-inputs.json`. Do not replace this with a reset of the existing `stir` stack.

Close-out remains in progress: reconcile owned test processes, inspect final worktree/branch/artifact sizes, retain NativePeers workspaces refused by its cleanup planner, remove only regenerable task build caches, verify the inherited file hash, commit/push named intended paths, and close notifications QUIET immediately before the final report. No unrelated simulator or shared helper may be stopped.
