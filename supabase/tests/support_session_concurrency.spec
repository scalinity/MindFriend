Support session concurrency scenarios. NOT EXECUTED by their author.

Run ONLY in a disposable database, AFTER the three support migrations and AFTER
support_session.sql has populated its synthetic fixtures (ids below come from that file).
Use two psql connections, A and B. Both connect as the owner role and then, per step,
`SET ROLE authenticated|service_role` with request.jwt.claim.sub set exactly as
support_test.as_user(...) does in support_session.sql. Statements shown run inside
"BEGIN; ..." transactions that are deliberately left OPEN where stated. "B waits" means the
statement blocks (pg_stat_activity.wait_event_type = 'Lock'/'advisory') until A commits.
PASS for every scenario = no SQLSTATE 40P01 anywhere, both transactions finish, and the
stated end state holds.

Concurrency model (single-user app, deliberate coarse tradeoff):
  ONE transaction-scoped advisory mutex, public.support_acquire_write_mutex(), is taken
  FIRST by support_apply_mutation, support_memory_mutate, support_confirm_chat_turn,
  support_expire_candidates and by BEFORE STATEMENT triggers on companion_memory and
  memory_fragments (INSERT/UPDATE/DELETE) - before any row lock. All context-changing
  writes therefore queue behind each other; transactions are short because provider
  generation happens outside the database. This removes inverse-row-lock cycles, empty-set
  phantom inserts and legacy-vs-new interleavings. Reads (get/list/list_memory) do not take it.
  Not covered: manual external transactions that take arbitrary rows before issuing a
  supported statement; FK-cascade deletes (account deletion) may bypass the statement trigger.

STAGING (run first, on connection A as owner, then re-run the relevant block before EVERY
destructive scenario: Forget and message deletion are not repeatable). Each "pair" is a freshly
promoted fragment/canonical-memory pair created through the real approval RPC, with its own clean
source message. Nothing below reuses fragments already forgotten by support_session.sql.

  -- pair P(n): n in {1,2,3,4}; repeat with the next n for each new need
  INSERT INTO public.messages (id, conversation_id, role, content)
    VALUES ('f0000000-0000-4000-8000-0000000001a<n>', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'staging source <n>');
  INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, review_state, source_message_id)
    VALUES ('f1000000-0000-4000-8000-0000000001a<n>', 'aaaaaaaa-0000-4000-8000-000000000001', 'preference', 'stage<n>',
            'staged plaintext <n>', 'pending', 'f0000000-0000-4000-8000-0000000001a<n>');
  -- as authenticated (sub = aaaaaaaa-...-0001):
  SELECT public.support_memory_mutate('{"schema_version":1,"operation_id":"7a000000-0000-4000-8000-0000000001a<n>",
     "kind":"candidate_approve","payload":{"fragment_id":"f1000000-0000-4000-8000-0000000001a<n>"}}'::jsonb);
  -- verify:  SELECT value, review_state, promoted_memory_id FROM memory_fragments WHERE id='f1000000-...-1a<n>';
  --          expect '' , 'promoted', <memory id>   (record the memory id as M<n>)

Use P1 for S1 (forward), P2 for S1 (reverse), P3 and P4 together for S2 (both must still be
promoted: check review_state='promoted' immediately before S2 starts).

S1  promoted-fragment legacy update vs canonical Forget (S10-R2)
    Forward - uses P1 (F = f1000000-0000-4000-8000-0000000001a1, memory M1):
    A: BEGIN; UPDATE public.memory_fragments SET value='queued old plaintext' WHERE id=F;   -- takes mutex
    B: SELECT public.support_memory_mutate(<memory_forget of M1>);                           -- B waits at the mutex
    A: COMMIT.   B completes with ok:true.
    End state: SELECT value, review_state FROM memory_fragments WHERE id=F  ->  '' , 'dismissed';
               M1 absent; suppression rows for memory M1 and fragment F present.
    Reverse - uses P2 (F2 = ...01a2, memory M2):
    B: BEGIN; SELECT public.support_memory_mutate(<memory_forget of M2>);                    -- holds the mutex
    A: UPDATE public.memory_fragments SET value='late' WHERE id=F2;                          -- A waits (statement trigger)
    B: COMMIT.   A completes; SELECT value FROM memory_fragments WHERE id=F2 -> '' (guard keeps it blank).

S2  repeated approvals of two still-promoted fragments (S10-R1) - uses P3 and P4 (verify both
    review_state='promoted' first; DO NOT run S1 on them)
    A: BEGIN; SELECT support_memory_mutate(<candidate_approve F3>);   -- already-promoted -> no_op:true
    B: SELECT support_memory_mutate(<candidate_approve F4>);          -- waits at the mutex only
    A: COMMIT.  Both return no_op:true; neither takes unrelated memory-row locks; no deadlock.
    Repeat with B started first (swap roles).

S3  legacy INSERT vs confirmation with >= 2 active memories (S10-R1)
    Setup: two active memories M1<M2 by id, both cited by one confirm request.
    A: BEGIN; INSERT INTO companion_memory (...);     -- statement trigger takes mutex; limit trigger scans all rows
    B: SELECT support_confirm_chat_turn(<cites M1, M2>);   -- waits at the mutex
    A: COMMIT.  B returns PRIVACY_REVISION_STALE (the insert advanced the privacy revision).
    Repeat with the empty-account boundary (user has zero memories): A inserts the first memory
    concurrently with B approving a candidate; B must serialize, never observe a half-locked set.

S4  accept_proposal vs suppression (both orders; use the CURRENT expected_revision)
    A: BEGIN; support_apply_mutation(accept_proposal ...);
    B: support_memory_mutate(suppress_source ...)    -- waits at the mutex.   A: COMMIT -> B completes.
    Reverse: B: BEGIN; suppress_source (open);  A: accept_proposal with expected_revision read
    AFTER B commits (a pre-commit revision correctly returns REVISION_CONFLICT first) -> PROPOSAL_EXPIRED.

S5  confirm vs session delete / legacy memory edit (both orders)
    A: BEGIN; support_confirm_chat_turn(...);   B: support_apply_mutation(delete_session ...) waits;
    A: COMMIT -> B completes.   Reverse: B open delete, A confirm waits, B COMMIT -> A returns NOT_FOUND.
    Legacy edit: A: BEGIN; UPDATE companion_memory SET content='x' WHERE id=<cited>;  B: confirm waits;
    A: COMMIT -> B returns PRIVACY_REVISION_STALE.

S6  deadline crossed while waiting for a lock (S05-R2-R1) - wall clock, not transaction start
    Setup: memory E with expires_at = now() + interval '8 seconds' (edit it BEFORE the scenario,
    then read its current revision and the current privacy revision; they must not change below).
    A: BEGIN; SELECT public.support_acquire_write_mutex();     -- owner session; holds the mutex
    B (before the deadline): SELECT support_confirm_chat_turn(<cites E at its current revision,
       privacy_revision = current>);                          -- starts, then waits at the mutex
    wait 10 seconds (deadline passes).   A: COMMIT.
    Expect B returns PRIVACY_REVISION_STALE (source_changed:companion_memory) although B's
    transaction began before the deadline and E's revision never changed.
    Repeat with accept_proposal on an offered proposal whose basis is E (PROPOSAL_EXPIRED), and
    with candidate_approve on a pending fragment whose 7-day deadline passes during the wait.
    Control: an already-confirmed request id replays its stored response even after the deadline.

S7  historical message edit / delete vs confirmation (M4-R03; uses the f...0a? messages of the
    support_session.sql round-6 block, or stage a fresh assistant message per run)
    Edit:   A: BEGIN; UPDATE public.messages SET content='rewritten' WHERE id=<cited>;     -- statement trigger takes the mutex
            B: SELECT support_confirm_chat_turn(<cites <cited> at revision 0>);           -- waits at the mutex
            A: COMMIT.  B returns PRIVACY_REVISION_STALE (source_changed:message); no assistant row is written.
    Reverse: B: BEGIN; SELECT support_confirm_chat_turn(<cites <cited> at revision 0>);    -- holds the mutex
            A: UPDATE public.messages SET content='rewritten' WHERE id=<cited>;           -- A waits
            B: COMMIT.  The confirmation (correct at its time) is committed; A's edit then lands and bumps the
            revision, so any LATER confirm citing revision 0 is stale.
    Insert control: a plain INSERT of a new user message takes no mutex and does not bump any revision.
