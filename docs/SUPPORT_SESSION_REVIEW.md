# Support-session review dispositions

The canonical acceptance criteria remain AC-01–AC-36 in `SUPPORT_SESSION_SPEC.md`. This ledger records source findings and their local verification. It does not turn a source review, synthetic check or simulator observation into physical-device, HTTP/provider, production or human acceptance. Those boundaries remain in `MINDFRIEND_IMPLEMENTATION_PROGRESS.md` and `SUPPORT_SESSION_ROLLOUT.md`.

All reports and earlier failed attempts are retained under the ignored `artifacts/support-session/` directory. The preceding ledger is retained as `review-ledger-before-final.md`. Claude authored the delegated implementation slices and reviewed the Codex foundation/integration; Codex independently reviewed Claude's exact named-file candidates. Read-only helper reviews that failed from file-descriptor exhaustion or revoked application-network access remain failed/unrun. Their results were not fabricated or counted as completed reviews.

IDs are namespaced because several reports reuse F001. `PF` means the parent foundation report; `OF` means the offline integration report; `RS-F` means root voice/sync; `M4-F` means the original chat report. These aliases preserve the original numeric IDs. Rereview suffixes remain attached to their originating finding.

## Consent and initial foundation

| ID | Disposition | Evidence / boundary |
|---|---|---|
| F001 | fixed and locally verified | Additive receipt/RPC; legacy onboarding completion remains valid without fabricating age consent |
| F002 | fixed and locally verified | Owner-read-only table; RPC validates captured owner, explicit confirmations, version, year and immutable first values |
| F003 | fixed and locally verified | Birth year is outside socially shared profiles; two-owner/anon/write-denial SQL controls |
| F004 | fixed and locally verified | Form captures payload and expected owner; SDK wire and server auth comparison reject account changes |
| F005 | fixed and locally verified | Gregorian reference year; invalid eligibility maps to review choices, not a connectivity claim |
| F006 | already satisfied and regression verified | Completed profile is cached before return; returning-user route test |
| F007 | fixed and locally verified | Entitlement update preserves confirmed quota evidence |
| F008 | fixed and locally verified | Unknown usage is distinct from zero; only a newer server quota period permits a reset |
| F009 | fixed; native controls inspected | Help remains available while consent saving disables form actions |
| F010 | fixed and locally verified | Existing account deletion path retained; captured-owner acknowledgement and local purge reviewed/tested with synthetic responses |
| F011 | satisfied by additive design | No global completion trigger breaks the older mock/client writer |
| F012 | fixed and locally verified | Memory fragments, intent and absence pass through the same privacy scope; source receipts propagated to Swift/UI |
| F013 | local SQL verified | Exact consent migration/fixture run in an empty owned synthetic database; real PostgREST remains a G3 check |
| F014 | rejected with evidence | No irreversible device lockout for a mistaken self-reported birth year; explicit birthday confirmation explains the boundary. This is not verified age certification |
| F015 | satisfied by additive design | Normal forward migration ledger; no global onboarding trigger |
| F016 | verified | Privacy-off and fragment-only legacy disclosure fixtures; no fabricated "no memory" claim |
| F017 | locally verified | Captured expected-owner wire/receipt tests and SQL calls; live HTTP decoding not run |
| F018 | fixed | AppURLs and one consent version per Swift/SQL layer |
| F019 | fixed and locally verified | Launch identification waits for completed onboarding; account-bound offline teardown and deletion acknowledgement are integrated |
| F020 | fixed and built | Simulated disclosure-gathering onboarding removed; optional choices do not silently set a wellness focus |
| F021 | fixed and SQL verified | Exact fixture row counts, UPDATE count and null-safe assertions |
| F022, F023, F024, F025, F026, F032 | proposal not executed; replacement verified | Proposed proxy/DNS/mount/listener route was abandoned. Executed route uses exact local image, network none, no host ports/mounts, read-only root, owned tmpfs and exact-ID teardown |
| F027 | fixed and verified within stated scope | Named empty synthetic DB plus hash-pinned schema-only fixtures and frozen baseline; storage/production parity is not inferred |
| F028 | fixed and locally verified | Owner travels from captured form through wire; 42501 and 22023 have distinct treatment |
| F029 | locally verified; HTTP boundary retained | Two-owner/read/delete/truncate/extreme-year/100-replay assertions plus simultaneous first submissions returning one immutable receipt. PostgREST acceptance remains unrun |
| F030 | retained compatibility boundary | Legacy completion is not proof of age consent; future consent-version/minimum-client changes require additive release sequencing |
| F031 | rejected with evidence | Owner-readable consent is necessary for inspection/export; write grants remain denied and owner isolation passes |

## Journal, offline and reminder findings

| IDs | Disposition | Evidence / boundary |
|---|---|---|
| J01 | fixed and verified | Real-file delete/discard/suppression recovery tests prevent older backups restoring acknowledged private content |
| J02 | fixed and verified | Finish carries the final checkpoint atomically in its immutable payload |
| J03, J03-R1 | fixed and verified | Typed scrub covers terminal activities, unsent copies and conflict snapshots; remote resolution cannot undo it |
| J04, J04-R1 | fixed and verified | Conflicting remote terminal/text state requires a choice; choosing remote abandons definitely rejected local attempts |
| J05, J05-R1 | fixed and verified | Validated recovery is persisted; every primary-write fault retains the good backup for another launch |
| J06 | fixed and verified | File open/write/sync/close failures throw before publication |
| J07 | fixed and verified | Close ends unfinished work, dismisses saved-step state, clears draft/reminder; Save and leave remains distinct |
| J08 | fixed and verified | Unsupported template/checkpoint versions are retained as unavailable and never acknowledged as supported data |
| J09 | fixed and verified | Rejected redacted non-delete attempts cannot remove a required deletion tombstone |
| O01, O02, O03, O04, O05 | fixed and verified | Immutable owner/epoch cache/queue scopes, awaitable cancellation, deletion purge, auth-bound bootstrap; registered offline ownership tests |
| OR01, OR02, OR03, OR04, OR05, OR06, OR07, OR08 | fixed and locally verified | Retained event order/day, streak recompute, mood reward, integer overflow, atomic quest reward, actual exercise column, expected-owner guards and completed-quest metadata. Online/offline/synthetic checks remain distinct from released-client behavior |
| OF001, OF004 | fixed and verified | Device-local day captured at queue time with pinned Gregorian formatter; exact key-set wire tests and non-UTC SQL fixture |
| OF002 | fixed and SQL verified | Lock/deadlock/serialization failures abort rather than committing stale recompute; rollback/retry harness |
| OF003 | fixed and verified | Authentication/owner mismatch pauses retryable work instead of permanently rejecting valid queued items |
| OF005, OF009 | fixed and verified | Confirmed quest result survives later side-effect failure; kept-existing mood is not presented as newly saved |
| OF006 | fixed for anonymous/cross-owner calls; narrower suggestion rejected | New forward guard is required by the actual baseline. Generic same-owner reward remains for existing callers; a global reward API migration is outside this slice. Exactly-once claims are limited to the atomic routes; rollout records this explicitly |
| OF007 | fixed and verified | One-day future tolerance with timestamp clamp; immutable original hash; boundary/replay fixtures |
| OF008 | fixed and verified | Owner/epoch and strict receipt format/target/result checks; server rejects changed payload identity |
| OF010, OF011 | fixed and verified | Unused bypass completion path removed; reflection bound preserved before transmission |
| OF012, ORF001, ORF002, ORF003, ORF004, ORF006, ORF007 | fixed and locally verified | Distinct quest days, correct date type, exact baseline digest, online invoker/service-role controls, disabled synthetic cron, captured immutable dates/timestamps and actual lock observations. `offline-*-run-summary*.json` retains the executed outcomes |
| ORF005 | rejected as scope expansion, with explicit limit | Removing all retained same-owner generic reward callers is not needed for this support-session slice; no claim of global exactly-once behavior for older clients |
| RM001 | fixed and verified | Reminder fields are projected out of all wire payloads, including later resume/checkpoint/finish |
| RM002 | fixed and verified | Same-device reminder survives an eligible remote saved-step refresh; other-device scheduling is never inferred |
| RM003 | fixed and verified | Superseded generation cannot cancel the newer request sharing its identifier |
| RM004 | fixed and verified | Reconciliation checks authorization and elapsed time; no blind "Reminder set" status |
| RM005 | fixed and verified | Account-end prefix cancellation works even if the journal failed to load |

Registered journal/coordinator/reminder/offline tests pass in the final 333-test run. Earlier failure logs remain retained. OS notification delivery and locked-device file protection remain unrun physical/runtime checks.

## Parent foundation and server contracts

| IDs | Disposition | Evidence / boundary |
|---|---|---|
| PF001, PF004 | fixed and verified | Reachable owner-bound corrupt-journal recovery with explicit recovery-copy choice; repository retained and old shape decoded |
| PF002, PF003 | fixed and verified | Ambiguous deletes replay across relaunch; definite conflicts rebase, rejected deletions remain visible and require deliberate retry |
| PF005 | fixed and verified | Orphan atomic-write temporary files are removed without restoring deleted text |
| PF006, PF010 | fixed and verified | Confirmed account removal awaits exact offline teardown and purges all owner-local work; logout preserves resumable work |
| PF007, PF012, PF015 | fixed and verified | Duplicate equal binding, partial failure and same-owner replacement preserve the current lease and await earlier invalidation |
| PF008, PF011, PF014 | fixed and verified | Actual app binds offline handlers before data views; unused live-account cache paths removed; Safety Plan uses captured owner |
| PF009 | fixed and verified | Safe unsent checkpoints coalesce; finish/close/discard are not permanently blocked by the event cap |
| PF013 | fixed and verified | Coordinator refresh reconciles presentation/draft state; unknown explicit session IDs throw |
| SR01–SR13 | fixed in final shell integration | Source registry/rereview, stable-route tests and native compact/iPad journeys; full authenticated route matrix remains unrun |
| S01–S11 and their rereview suffixes | fixed and locally verified | Canonical catalog/XP, transitive scrub and foreign-session revision markers, reserved discard marker, full receipt-source expiry/revision checks, historical replay ordering, promotion/Forget, owner constraints and one write-lock order. Final r5 review plus full SQL fixtures and concurrent schedules |
| C01–C06 | fixed and locally verified | Strict server context policy/receipt and privacy/source classification; final backend fixtures pass, real provider request capture remains G2 |
| R5-001, R5-T01, R4-T01 | fixed and locally verified | Acceptance revalidates every captured receipt source; fixture setups reach intended guards; actual two-connection harness replaces unexecuted placeholders |
| CS01–CS07 | fixed and verified | Exact wire/receipt/state conversion, erased terminal data, strict memory acknowledgements, historical privacy revision handling; registered cloud tests |
| CS-R2-DEP01 | fixed and SQL/contract verified | Decline-template now has an allowlisted parser/RPC path and durable Not now suppression |
| CS-R2-DOC01 | fixed | Convenience-factory comment matches the actual enum |
| M4-F001–M4-F008, M4-R01–M4-R04 | fixed and locally verified | Legacy/new privacy revalidation, ambiguous atomic confirmation, message revisions, bounded logs, tagged safety/interface origins, strict terminal proposal and unchanged provider limits. Final 230-test backend run includes the continuation that previously reproduced F006 |

The final SQL runs also test 100 identical create/start/finish/chat-confirm calls, changed payload rejection, exactly one canonical completion/30 XP, another owner's forged support/canonical completion and reward denial, simultaneous completion retries, 126 tied-cursor sessions, and 26-dataset owner-safe export. Historical applied migrations were not edited.

## Voice, history, Health and final integration

| IDs | Disposition | Evidence / boundary |
|---|---|---|
| MF-M6S-001–MF-M6S-004 | fixed and locally verified | Reviewed r4 context/relay integration; server-owned packet, actual route label, claim identity, source revalidation and lease frame gates. Provider smoke remains unrun |
| MF-VS-001–MF-VS-008, MF-VS-004-R4, MF-VS-008-R5a, MF-VS-008-R5b | fixed and locally verified | Reviewed r6 Swift integration; capture generations, explicit resume/leave, truthful callbacks/status, bounded cleanup and no automatic mic restart. Earlier 202-test voice run plus later focused lifecycle/journal checks; physical audio is unrun |
| TR-R01–TR-R04 | fixed and SQL verified | Server transcript owner/provenance/call-order identity, immutable event replay, Close/Delete and pinned conversation-delete races |
| EX01 | fixed and registered tests verified | Export controller generation and exact file/share-ticket ownership prevent old task completion overwriting a new run |
| HST-R01–HST-R04, SA-P01, SA-P02 | fixed and verified | Cursor-backed History with tombstone-safe local/cloud merge, detail refresh, saved/completed metadata, concern/results/reflection and rename/delete/continue-as-new. Native compact History flow passes |
| SA-P03 | fixed and verified | Unknown provenance is explicitly unknown; known origin labels are not invented |
| SA-P04, SA-P05 | fixed and verified | Health sample/no-data/query-failure states and per-account sync pause are separate from permission-request completion |
| H001–H006 | fixed and locally verified | Strict complete-or-absent summary metadata, correct unfinished Saved-step count, unknown canonical IDs retained, private helper grants and reverse-owner list controls |
| RS-F001–RS-F012 | fixed and verified | Root sync/transcript/access generation, lazy attachment, fail-closed capability, owner-proof and actual request-count corrections; same-id retries preserve uncertain work |
| N001 | fixed and verified | Export distinguishes saved/pending/rejected finals and accurate saved counts |
| N002 | fixed and verified | All unsaved finals count toward the cap; explicit retry/remove and confirmed conversation deletion clear local copies. Silent aging-out of unsynced text is rejected because it loses acknowledged work |
| N003–N005 | fixed and verified | Transcript pause cannot starve structured outbox; target-pending/auth outcomes stay retryable; capability failure preserves bounded retry scheduling |
| N006 | fixed and verified | Server/local final merge preserves chronology/provider order and acknowledgement dedup; clipboard copies are local-only with expiry |
| N007 | fixed and verified | Explicit voice retry may requeue a rejected event; ordinary background work never acquires that permission |
| D001–D009 | fixed and verified | Done/owner-safe dismissal, truthful context-unavailable state, pending/rejected recovery, immutable explicit retry, held error race, merge matrix, same-ID retry, reachable recovery controls and real cross-owner SQL fixture |
| D010 / E007 | service race fixed; extra injection seam rejected with evidence | Actual owner→nil→same-owner held-query test passes. Container's direct nil/owner calls and settings owner/epoch guards were inspected. A new production injection abstraction solely to test those two calls was not added; container-level runtime test remains unrun |
| E001 | fixed and verified | Exact visible bounded answer/note excerpt is persisted atomically and sent only under deliberate sharing; full original answers remain local/session data and scrub removes queued copies |
| E002 | fixed and verified | Explicit retry IDs are immutable to one drain; interrupted explicit pass cannot mark later automatic work as explicit. Pending entries remain eligible because background sync can reject before the voice journal updates |
| E003 | fixed and verified | Observer test asserts update_session before explicit synchronization; independent mutation reproduction detects the old global pause |
| E004, E005 | fixed and verified | UTF-16 chat limit, original oversized draft preservation, closed-snapshot revalidation and lazy linked continuation |
| E006 | fixed and verified | Exhaustion test remains quiet beyond the next possible backoff, then explicit recovery succeeds |
| E008 | fixed and SQL verified | Both owner directions hide foreign list/helper summaries |
| E009 | fixed | Discard copy explains that an already prepared Chat draft remains separate |
| G001 | rejected with native evidence | Removing text selection did not fix the old tap. The test must target the observed nested native switch rather than its combined outer accessibility row. Selectable answers retained; deliberate-sharing journey passes |
| MS001 | fixed and SQL verified | Claim/expiry/finish/status take the write mutex first; guarded schedule completes and old-order mutation reproduces a deadlock |
| MS002 | fixed and SQL/fixture verified | Existing quota debit and dispatch CAS share one transaction after revalidation; replay/lost-response/denial/stale cases do not double debit or regenerate |
| MS003 | fixed and SQL/Swift verified | New content-free request receipts are the 26th fixed owner-filtered export dataset |
| MS004 | fixed and fixture verified | Plain/escaped duplicate candidate keys rejected per object; repeated field names across different candidates remain valid |
| K001 | resolved by settled rerun | Earlier 149-test run failed against changing test expectations; settled rerun passes 149, then final registered set passes 333. The earlier failure remains retained |
| K002 | fixed and SQL verified | Export fixtures reuse the same request UUID across owners without leaking or changing owner totals |
| K003 | fixed and SQL verified | Actual-chain test pins the complete content-free request export key set |
| K004 | fixed and SQL verified | Missing new table returns unavailable/incomplete; rollout names the catalog-size and draft-migration boundary |
| K005 | fixed/tested where requested; existing budget boundary retained | Legacy note-only fallback test; preview stops at whole graphemes within 1,000 UTF-16 units. Exact preview is shown. Existing 8,000-byte session context budget still applies; no claim that every displayed field fits every provider packet |
| K006 | fixed | Confirmation dialog has one Text containing the complete draft-scope explanation |
| K007 | fixed and built | Preview task is keyed by session and availability; dead localOnly gate removed |
| K008 | fixed and built/UI verified | DEBUG URLProtocol answers only prepare; other operations fail without network/provider/account access |
| PR01 | fixed and source verified | Explore first maps to the actual Explore shell destination |

Phase12 has eight readable K IDs and eight structured findings; phase10 has nine E IDs. Correspondence warnings were reconciled locally rather than spending a formatting-only model turn. Initial memory worker timeout, phase2 collection failure, and reviewer collection failures remain failed attempts; retained source was inspected independently and actual integrated target tests were run.

The final visual inspection found a test-only appearance override above the fixture. The root now chooses the fixture theme at that same outer preference; a DEBUG label reads the actual color-scheme environment and tests assert it. Earlier appearance names alone do not count as dark-mode evidence. The replacement matrix is recorded separately in the progress file.

The pre-integration finding set has a recorded disposition. External/physical/human checks remain incomplete acceptance. The later integration and restoration boundary is recorded below. No production or App Store action occurred.


## Integration with pinned main `66633ef`

The feature commit `5122419` is reconciled with the independently advanced app repair branch. Native Claude Sonnet review task `0df3862e-a3b0-41bb-afaa-f7ca9de95139` returned seven actionable IDs; follow-up `8c74593c-e2ee-42b6-a63c-6cd69ed0b82b` refined INT001 and added INT008. Remediation review `74b14881-324a-441b-93bd-0d71dae3d999` accepted six dispositions, approved the bounded synthetic execution, and returned INT009–INT012. All twelve readable IDs were matched to the structured findings locally despite parser correspondence warnings. Reviewer file/hash observations remain attributed; the parent ran the actual builds, fixtures and SQL checks.

The final fixes for INT009–INT012 implement the review's day-lock, shell-warning, fixture-seed and dependency-guard proposals. The current combined Swift run passes 569 tests; the backend run passes 228 tests/143 steps; seven repeated native journeys pass. The fresh 48-file SQL chain passes all overlap/contract fixtures and 45 recorded concurrency/trigger checks. The modeled chain fails earlier at an inherited mentorship migration; its later feature tests are not reported passed.

| ID | Disposition | Current evidence / boundary |
|---|---|---|
| INT001 | fixed and locally verified | Confirmed deletion independently attempts every owner-local erase after a credential failure, forces only the deleted owner's teardown, and reports incomplete cleanup. Actual SDK + URLProtocol fixtures verify one server request, published logout, journal callback and no resend; each failed erase lets later erases run |
| INT002 | fixed and fresh SQL verified | New `20261107185417_reconcile_companion_canonical_actions.sql` writes both mood clocks from the original event and routes companion mood/quest effects through the canonical reward transaction. Prior committed migrations remain unchanged. Four sequential cross-path cases and four actual competing cross-device schedules preserve event ordering, phone fields and one reward |
| INT003 | fixed and fresh SQL verified | All seven overlapping main/offline/cross-path SQL fixtures execute on the combined chain; the offline helper runs ten actual concurrent/timeout cases in its own clone. All imported helpers are hash-pinned. The modeled chain stops at the separate prerequisite below |
| INT004 | fixed and verified | Every createdb result is checked immediately, including support and offline concurrency clones; successful fresh run records exact-container removal |
| INT005 | rejected as a released-data migration requirement; comment corrected | The format first appeared in `86af997` on 6 November at 5:53 PM EST, after Apple's current public 1.0.4 release at 1:22 PM EST. The public app cannot have written it. Experimental encrypted bytes/keys remain untouched by logout and are erased by explicit account deletion. No TestFlight inventory claim is made; no importer for unshipped data is added |
| INT006 | fixed with INT001; tests verified | Confirmed account deletion skips push unregister for the already removed server account; ordinary logout retains its handler and serialization |
| INT007 | fixed and verified | Real keyset traversal puts a voice call across the first-page boundary. Provider order, unique IDs, 100 combined rows and the captured scroll-anchor row are asserted in the 569-test run |
| INT008 | fixed and locally verified | Persisted owner-specific failed-credential-removal mark blocks auth events, startup and explicit restore; only that owner's SDK removal is retried, and the mark clears only after verification. Actual unexpired-session, relaunch and other-account-during-deletion fixtures pass |
| INT009 | fixed and fresh concurrent SQL verified | The day lock is taken inside `apply_mood_checkin`, so offline, online and companion writers share it. Companion status uses the canonical outcome. The held phone-first schedule includes note/anxiety/energy and asserts their retention under a newer Watch score |
| INT010 | fixed and verified | Cleanup failure also publishes `signOutWarning`, which the shell observes after Profile disappears. Actual deletion-failure test asserts the published warning as well as the thrown error; final 569-test run passes |
| INT011 | fixture prerequisites fixed; fresh verified | Static language/XP metadata is seeded inside rollback fixtures. Fresh r1 exposed a missing `en` FK prerequisite in the inherited authorization fixture before its assertions; authorization, current-entitlement and legacy-transcript fixtures now carry their own prerequisites. Fresh r2 passes. The modeled run cannot reach them because of its earlier inherited migration conflict |
| INT012 | fixed and source/fresh verified | A DO precondition requires the existing companion/canonical helpers and both mood time columns before any replacement. Missing dependencies abort the migration transaction; the complete fresh chain passes |

INT005 uses [Apple's current public app lookup](https://itunes.apple.com/lookup?id=6758198271), retained as `artifacts/support-session/current-public-app-store.json`, and direct Git provenance. This is a public-release boundary, not a submission or TestFlight check.

One inherited restoration defect remains outside the support implementation: the modeled October snapshot defines `calculate_timezone_overlap(tz1 text,tz2 text)`; `20261106225731_repair_mentorship_discovery_contract.sql:119` attempts `p_tz1`/`p_tz2`. PostgreSQL rejects that replacement before the feature fixtures execute. `integrated-support-modeled-summary-r1.json` retains the FAIL and exact-container removal. The source snapshot and prior committed migrations are preserved; resolving the selected environment's restoration plan remains a dependency of issue 57 and G3. No full modeled/production compatibility claim is made.
