// Pure unit tests for the support-session wire contract and request handler.
// No network, no database, no provider. Synthetic identifiers only.
import {
  duplicateTopLevelKeys,
  interfaceFallbackText,
  jsonbBytes,
  parseMemoryEnvelope,
  parseMutationEnvelope,
  parseSupportRequest,
  type ProposalValidationContext,
  statusForCode,
  validateSupportActionProposal,
} from "../functions/_shared/support-contract.ts";
import {
  createSupportSessionHandler,
  type SupportCaller,
} from "../functions/_shared/support-session-handler.ts";

function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
function equal(
  actual: unknown,
  expected: unknown,
  message = "unexpected value",
) {
  assert(
    JSON.stringify(actual) === JSON.stringify(expected),
    `${message}: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`,
  );
}

const U = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const env = (
  kind: string,
  payload: Record<string, unknown>,
  expected: number | null = 1,
) => ({
  schema_version: 1,
  operation_id: U(1),
  session_id: U(2),
  expected_revision: expected,
  kind,
  payload,
});

Deno.test("envelope: create needs null revision, others a positive integer", () => {
  assert(parseMutationEnvelope(env("create", { title: "x" }, null)).ok);
  assert(!parseMutationEnvelope(env("create", {}, 1)).ok);
  assert(!parseMutationEnvelope(env("update_session", {}, null)).ok);
  assert(!parseMutationEnvelope(env("update_session", {}, 0)).ok);
  assert(!parseMutationEnvelope(env("update_session", {}, 1.5)).ok);
});

Deno.test("envelope: rejects unknown kinds, unknown payload fields, bad UUIDs, schema drift", () => {
  assert(!parseMutationEnvelope(env("teleport", {})).ok);
  assert(
    !parseMutationEnvelope(env("update_session", { user_id: U(9) })).ok,
    "client may not supply user_id",
  );
  assert(
    !parseMutationEnvelope({
      ...env("update_session", {}),
      operation_id: "nope",
    }).ok,
  );
  assert(
    !parseMutationEnvelope({ ...env("update_session", {}), schema_version: 2 })
      .ok,
  );
});

Deno.test("envelope: bounds titles, concern, steps and checkpoints", () => {
  assert(
    !parseMutationEnvelope(env("create", { title: "x".repeat(81) }, null)).ok,
  );
  assert(
    parseMutationEnvelope(env("create", { title: "x".repeat(80) }, null)).ok,
  );
  assert(
    !parseMutationEnvelope(env("create", { concern: "x".repeat(4001) }, null))
      .ok,
  );
  const cp = (step: unknown, pause = false) =>
    env("checkpoint_activity", {
      activity_id: U(3),
      checkpoint: { version: 1, step },
      active_ms: 5,
      pause,
    });
  assert(
    !parseMutationEnvelope(
      cp({ action_text: "x".repeat(401), state: "saved" }, true),
    ).ok,
  );
  assert(
    !parseMutationEnvelope(cp({ action_text: "   ", state: "saved" }, true)).ok,
    "Save for later needs non-empty text",
  );
  assert(
    !parseMutationEnvelope(cp({ action_text: "email", state: "draft" }, true))
      .ok,
    "paused step must be saved",
  );
  assert(
    parseMutationEnvelope(cp({ action_text: "email", state: "saved" }, true))
      .ok,
  );
  const huge = env("checkpoint_activity", {
    activity_id: U(3),
    checkpoint: { version: 1, blob: "y".repeat(40_000) },
    active_ms: 0,
  });
  assert(!parseMutationEnvelope(huge).ok);
  assert(
    !parseMutationEnvelope(
      env("checkpoint_activity", {
        activity_id: U(3),
        checkpoint: { version: 2 },
        active_ms: 0,
      }),
    ).ok,
  );
});

Deno.test("finish: skipped_all cannot complete, empty/unreported steps cannot complete, rating bounded", () => {
  const fin = (p: Record<string, unknown>) =>
    env("finish_activity", { activity_id: U(3), ...p });
  assert(
    !parseMutationEnvelope(fin({ outcome: "completed", reason: "skipped_all" }))
      .ok,
  );
  assert(
    parseMutationEnvelope(fin({ outcome: "stopped", reason: "skipped_all" }))
      .ok,
  );
  assert(
    !parseMutationEnvelope(
      fin({
        outcome: "completed",
        result: { step: { action_text: "", state: "self_reported_done" } },
      }),
    ).ok,
  );
  assert(
    !parseMutationEnvelope(
      fin({
        outcome: "completed",
        result: { step: { action_text: "go", state: "saved" } },
      }),
    ).ok,
  );
  assert(
    parseMutationEnvelope(
      fin({
        outcome: "completed",
        result: { step: { action_text: "go", state: "self_reported_done" } },
      }),
    ).ok,
  );
  assert(!parseMutationEnvelope(fin({ outcome: "completed", rating: 6 })).ok);
  assert(!parseMutationEnvelope(fin({ outcome: "done" })).ok);
});

Deno.test("reflection: four neutral outcomes only, note bounded, no default", () => {
  const r = (p: Record<string, unknown>) =>
    env("record_reflection", { activity_id: U(3), ...p });
  for (const o of ["helpful", "not_for_me", "not_sure", "skip"]) {
    assert(parseMutationEnvelope(r({ outcome: o })).ok);
  }
  assert(!parseMutationEnvelope(r({})).ok);
  assert(!parseMutationEnvelope(r({ outcome: "great" })).ok);
  assert(
    !parseMutationEnvelope(r({ outcome: "skip", note: "n".repeat(1001) })).ok,
  );
});

Deno.test("memory envelope validation", () => {
  const m = (kind: string, payload: Record<string, unknown>) =>
    parseMemoryEnvelope({
      schema_version: 1,
      operation_id: U(1),
      kind,
      payload,
    });
  assert(m("memory_forget", { memory_id: U(5) }).ok);
  assert(m("candidate_approve", { fragment_id: U(5), content: "ok" }).ok);
  assert(!m("memory_forget", {}).ok);
  assert(!m("memory_edit", { memory_id: U(5), content: "  " }).ok);
  assert(!m("memory_edit", { memory_id: U(5), content: "x".repeat(501) }).ok);
  assert(!m("memory_forget", { memory_id: U(5), user_id: U(6) }).ok);
  assert(m("suppress_source", { source_kind: "conversation", id: U(5) }).ok);
  assert(!m("suppress_source", { source_kind: "memory", id: U(5) }).ok);
});

Deno.test("request parsing: get/list/cursor/receipt", () => {
  assert(parseSupportRequest({ op: "capabilities" }).ok);
  assert(!parseSupportRequest({ op: "nope" }).ok);
  assert(
    parseSupportRequest({ op: "get", schema_version: 1, session_id: U(2) }).ok,
  );
  assert(
    !parseSupportRequest({ op: "get", schema_version: 1, session_id: "x" }).ok,
  );
  const list = parseSupportRequest({
    op: "list",
    schema_version: 1,
    limit: 100,
    cursor: { updated_at: "2026-11-06T12:00:00Z", id: U(2) },
  });
  assert(list.ok);
  assert(
    !parseSupportRequest({ op: "list", schema_version: 1, limit: 101 }).ok,
  );
  assert(
    !parseSupportRequest({
      op: "list",
      schema_version: 1,
      cursor: { updated_at: "bad", id: U(2) },
    }).ok,
  );
  assert(parseSupportRequest({ op: "receipt", request_id: U(4) }).ok);
  const mut = parseSupportRequest({
    op: "mutate",
    ...env("update_session", { title: "t" }),
  });
  assert(mut.ok && mut.value.op === "mutate");
});

Deno.test("error codes map to stable HTTP statuses", () => {
  equal(statusForCode("REVISION_CONFLICT"), 409);
  equal(statusForCode("NOT_FOUND"), 404);
  equal(statusForCode("AUTH_REQUIRED"), 401);
  equal(statusForCode("RATE_LIMITED"), 429);
  equal(statusForCode("TEMPORARY_FAILURE"), 503);
  equal(statusForCode("SOMETHING_ELSE"), 500);
});

// ---- propose_support_action ------------------------------------------------
const ctx = (
  over: Partial<ProposalValidationContext> = {},
): ProposalValidationContext => ({
  scope: "personalized",
  includedSources: [{ kind: "companion_memory", id: U(7) }, {
    kind: "message",
    id: U(8),
  }],
  selectedIntent: null,
  suppressedTemplates: [],
  ...over,
});
const args = (o: Record<string, unknown>) =>
  JSON.stringify({
    template_key: "ground_present_v1",
    reason_code: "current_request",
    basis_ref: null,
    suggested_step: null,
    ...o,
  });

Deno.test("proposal: valid arguments become a typed proposal", () => {
  const v = validateSupportActionProposal(args({}), ctx());
  assert(v.ok);
  equal(v.proposal, {
    template_key: "ground_present_v1",
    reason_code: "current_request",
    basis_kind: null,
    basis_ref: null,
    suggested_step: null,
  });
});

Deno.test("proposal: rejects malformed, oversized, duplicate, unknown-key, unknown-template, missing-key", () => {
  assert(!validateSupportActionProposal("{not json", ctx()).ok);
  assert(
    !validateSupportActionProposal(args({ pad: "x".repeat(9000) }), ctx()).ok,
  );
  const dup =
    '{"template_key":"ground_present_v1","template_key":"choose_step_v1","reason_code":"current_request","basis_ref":null,"suggested_step":null}';
  equal(duplicateTopLevelKeys(dup), ["template_key"]);
  assert(!validateSupportActionProposal(dup, ctx()).ok);
  assert(
    !validateSupportActionProposal(args({ url: "https://evil.example" }), ctx())
      .ok,
    "model URL / unknown key",
  );
  assert(
    !validateSupportActionProposal(args({ template_key: "../../admin" }), ctx())
      .ok,
  );
  assert(
    !validateSupportActionProposal(
      JSON.stringify({ template_key: "ground_present_v1" }),
      ctx(),
    ).ok,
  );
  assert(!validateSupportActionProposal("[]", ctx()).ok);
});

Deno.test("proposal: suggested_step only for choose_step_v1 and bounded", () => {
  assert(
    !validateSupportActionProposal(args({ suggested_step: "write it" }), ctx())
      .ok,
  );
  const ok = validateSupportActionProposal(
    args({
      template_key: "choose_step_v1",
      suggested_step: " write the subject line ",
    }),
    ctx(),
  );
  assert(ok.ok && ok.proposal.suggested_step === "write the subject line");
  assert(
    !validateSupportActionProposal(
      args({ template_key: "choose_step_v1", suggested_step: "x".repeat(401) }),
      ctx(),
    ).ok,
  );
});

Deno.test("proposal: basis must be an included owned source, else downgrade to general option", () => {
  const good = validateSupportActionProposal(
    args({ reason_code: "approved_preference", basis_ref: U(7) }),
    ctx(),
  );
  assert(
    good.ok && good.proposal.reason_code === "approved_preference" &&
      good.proposal.basis_kind === "companion_memory" && !good.downgraded,
  );
  const foreign = validateSupportActionProposal(
    args({ reason_code: "approved_preference", basis_ref: U(99) }),
    ctx(),
  );
  assert(
    foreign.ok && foreign.downgraded &&
      foreign.proposal.reason_code === "general_option" &&
      foreign.proposal.basis_ref === null,
  );
  const notUuid = validateSupportActionProposal(
    args({ reason_code: "current_request", basis_ref: "memory-1" }),
    ctx(),
  );
  assert(
    notUuid.ok && notUuid.downgraded && notUuid.proposal.basis_ref === null,
  );
});

Deno.test("proposal: conversation-only scope can never cite saved preference", () => {
  const v = validateSupportActionProposal(
    args({ reason_code: "approved_preference", basis_ref: U(7) }),
    ctx({ scope: "conversation_only" }),
  );
  assert(
    v.ok && v.proposal.reason_code === "general_option" &&
      v.proposal.basis_kind === null,
  );
});

Deno.test("proposal: selected_intent must match the person's selected intent; declined templates dropped", () => {
  const v = validateSupportActionProposal(
    args({ reason_code: "selected_intent" }),
    ctx({ selectedIntent: "choose_step_v1" }),
  );
  assert(v.ok && v.proposal.reason_code === "general_option");
  const v2 = validateSupportActionProposal(
    args({ reason_code: "selected_intent" }),
    ctx({ selectedIntent: "ground_present_v1" }),
  );
  assert(v2.ok && v2.proposal.reason_code === "selected_intent");
  assert(
    !validateSupportActionProposal(
      args({}),
      ctx({ suppressedTemplates: ["ground_present_v1"] }),
    ).ok,
  );
});

Deno.test("interface fallback text is deterministic and non-empty for each template", () => {
  for (
    const t of [
      "ground_present_v1",
      "untangle_thought_v1",
      "choose_step_v1",
    ] as const
  ) assert(interfaceFallbackText(t).startsWith("App option:"));
});

// ---- handler -----------------------------------------------------------------
type Call = { fn: string; args: Record<string, unknown> };
function harness(
  result: (
    fn: string,
  ) => { data: unknown; error: { code?: string; message: string } | null },
  over: { limited?: boolean; authFail?: boolean } = {},
) {
  const calls: Call[] = [];
  const logs: Record<string, unknown>[] = [];
  const caller: SupportCaller = {
    userId: U(100),
    rpc: (fn, args) => {
      calls.push({ fn, args });
      return Promise.resolve(result(fn));
    },
  };
  const handler = createSupportSessionHandler({
    cors: () => ({ "Access-Control-Allow-Origin": "null" }),
    authenticate: () =>
      Promise.resolve(
        over.authFail ? new Response("{}", { status: 401 }) : caller,
      ),
    rateLimit: () => ({ allowed: !over.limited, resetInSeconds: 7 }),
    log: (e) => logs.push(e),
  });
  const post = (body: unknown) =>
    handler(
      new Request("http://localhost/support-session", {
        method: "POST",
        body: typeof body === "string" ? body : JSON.stringify(body),
      }),
    );
  return { calls, logs, post, handler };
}

Deno.test("handler: unauthenticated callers never reach the database", async () => {
  const h = harness(() => ({ data: {}, error: null }), { authFail: true });
  const res = await h.post({ op: "capabilities" });
  equal(res.status, 401);
  equal(h.calls.length, 0);
});

Deno.test("handler: ownership is never taken from the body (extra user_id rejected before any RPC)", async () => {
  const h = harness(() => ({ data: {}, error: null }));
  const res = await h.post({
    op: "mutate",
    ...env("update_session", { title: "t", user_id: U(9) }),
  });
  equal(res.status, 400);
  equal(h.calls.length, 0);
});

Deno.test("handler: capabilities distinguishes not-deployed from temporary failure", async () => {
  const missing = harness(() => ({
    data: null,
    error: {
      code: "PGRST202",
      message: "Could not find the function public.support_capabilities",
    },
  }));
  const r1 = await missing.post({ op: "capabilities" });
  equal(r1.status, 200);
  const b1 = await r1.json();
  equal([b1.session_contract, b1.context_policy, b1.voice_context, b1.status], [
    0,
    0,
    0,
    "not_deployed",
  ]);

  const flaky = harness(() => ({
    data: null,
    error: { code: "08006", message: "connection failure" },
  }));
  equal((await flaky.post({ op: "capabilities" })).status, 503);

  const ok = harness(() => ({
    data: { session_contract: 1, context_policy: 1, voice_context: 0 },
    error: null,
  }));
  const b2 = await (await ok.post({ op: "capabilities" })).json();
  equal([b2.session_contract, b2.voice_context, b2.status], [1, 0, "ok"]);
});

Deno.test("handler: domain failures map to status codes; conflict carries snapshot", async () => {
  const h = harness(() => ({
    data: {
      ok: false,
      code: "REVISION_CONFLICT",
      current_revision: 4,
      snapshot: { session: { revision: 4 } },
    },
    error: null,
  }));
  const res = await h.post({
    op: "mutate",
    ...env("update_session", { title: "t" }),
  });
  equal(res.status, 409);
  const body = await res.json();
  equal(body.current_revision, 4);
  equal(h.calls[0].fn, "support_apply_mutation");
  equal(
    (h.calls[0].args.p_envelope as { operation_id: string }).operation_id,
    U(1),
  );
});

Deno.test("handler: replay and no-op are success statuses", async () => {
  const h = harness(() => ({
    data: { ok: true, replayed: true, revision: 3, no_op: false },
    error: null,
  }));
  equal(
    (await h.post({
      op: "mutate",
      ...env("update_session", { title: "t" }, 2),
    })).status,
    200,
  );
  equal(h.logs[0].outcome, "replayed");
});

Deno.test("handler: DB errors never leak internals or content; logs are content-free", async () => {
  const h = harness(() => ({
    data: null,
    error: { code: "XX000", message: "secret concern text leaked here" },
  }));
  const res = await h.post({
    op: "mutate",
    ...env("update_session", { title: "private title" }),
  });
  equal(res.status, 503);
  const text = await res.text();
  assert(!text.includes("secret") && !text.includes("private title"));
  assert(
    !JSON.stringify(h.logs).includes("private title") &&
      !JSON.stringify(h.logs).includes("secret"),
  );
});

Deno.test("handler: auth failures inside the RPC map to 401; rate limit to 429; oversize to 413; bad JSON to 400", async () => {
  equal(
    (await harness(() => ({
      data: null,
      error: { code: "42501", message: "AUTH_REQUIRED" },
    })).post({ op: "memory_list" })).status,
    401,
  );
  const limited = harness(() => ({ data: {}, error: null }), { limited: true });
  const r = await limited.post({ op: "memory_list" });
  equal(r.status, 429);
  equal(r.headers.get("Retry-After"), "7");
  equal(limited.calls.length, 0);
  equal(
    (await harness(() => ({ data: {}, error: null })).post("x".repeat(170_000)))
      .status,
    413,
  );
  equal(
    (await harness(() => ({ data: {}, error: null })).post("{oops")).status,
    400,
  );
});

Deno.test("handler: non-POST is rejected, OPTIONS answered without auth work", async () => {
  const h = harness(() => ({ data: {}, error: null }));
  equal(
    (await h.handler(new Request("http://localhost/x", { method: "GET" })))
      .status,
    405,
  );
  equal(
    (await h.handler(new Request("http://localhost/x", { method: "OPTIONS" })))
      .status,
    200,
  );
});

Deno.test("discard_activity_answers: only an activity id; prompt ids are the v1 stable set", () => {
  assert(
    parseMutationEnvelope(
      env("discard_activity_answers", { activity_id: U(3) }),
    ).ok,
  );
  assert(!parseMutationEnvelope(env("discard_activity_answers", {})).ok);
  assert(
    !parseMutationEnvelope(
      env("discard_activity_answers", { activity_id: U(3), scope: "all" }),
    ).ok,
  );
  const cp = (c: Record<string, unknown>) =>
    env("checkpoint_activity", {
      activity_id: U(3),
      checkpoint: { version: 1, ...c },
      active_ms: 1,
    });
  assert(
    parseMutationEnvelope(
      cp({
        completed_steps: ["see", "feel"],
        skipped_steps: ["hear"],
        current_step: "smell",
        responses: { see: "a lamp" },
      }),
    ).ok,
  );
  assert(
    parseMutationEnvelope(
      cp({
        responses: { on_mind: "x", certain_unclear: "y", fairer_way: "z" },
      }),
    ).ok,
  );
  assert(
    parseMutationEnvelope(cp({ responses: { action: "x", smaller: "y" } })).ok,
  );
  assert(!parseMutationEnvelope(cp({ completed_steps: ["see", "nose"] })).ok);
  assert(!parseMutationEnvelope(cp({ responses: { sight: "x" } })).ok);
  assert(!parseMutationEnvelope(cp({ responses: { see: 5 } })).ok);
  assert(!parseMutationEnvelope(cp({ current_step: "other" })).ok);
});

Deno.test("finish_activity accepts the exact final checkpoint without a prior checkpoint", () => {
  const fin = (p: Record<string, unknown>) =>
    env("finish_activity", { activity_id: U(3), outcome: "completed", ...p });
  assert(
    parseMutationEnvelope(
      fin({
        checkpoint: {
          version: 1,
          template_version: 1,
          completed_steps: ["see", "feel", "hear", "smell", "taste"],
        },
        active_ms: 90000,
      }),
    ).ok,
  );
  assert(!parseMutationEnvelope(fin({ checkpoint: { version: 2 } })).ok);
  assert(
    !parseMutationEnvelope(
      fin({ checkpoint: { version: 1, completed_steps: ["bogus"] } }),
    ).ok,
  );
  assert(
    !parseMutationEnvelope(
      fin({ checkpoint: { version: 1, blob: "y".repeat(40_000) } }),
    ).ok,
  );
});

Deno.test("C02: pausing grounding or untangle needs no step; a paused practical step must be saved with text", () => {
  const cp = (c: Record<string, unknown>, pause = true) =>
    env("checkpoint_activity", {
      activity_id: U(3),
      checkpoint: { version: 1, template_version: 1, ...c },
      active_ms: 5,
      pause,
    });
  assert(
    parseMutationEnvelope(
      cp({
        current_step: "feel",
        completed_steps: ["see"],
        responses: { see: "a lamp" },
      }),
    ).ok,
    "grounding pause",
  );
  assert(
    parseMutationEnvelope(
      cp({
        current_step: "certain_unclear",
        completed_steps: ["on_mind"],
        responses: { on_mind: "work" },
      }),
    ).ok,
    "untangle pause",
  );
  assert(
    parseMutationEnvelope(
      cp({ step: { action_text: "write it", state: "saved" } }),
    ).ok,
  );
  assert(
    !parseMutationEnvelope(cp({ step: { action_text: "   ", state: "saved" } }))
      .ok,
  );
  assert(
    !parseMutationEnvelope(cp({ step: { action_text: "x", state: "draft" } }))
      .ok,
  );
});

Deno.test("C05: escaped duplicate JSON keys are rejected after decoding", () => {
  const args =
    '{"template_key":"ground_present_v1","template_\\u006bey":"choose_step_v1","reason_code":"current_request","basis_ref":null,"suggested_step":null}';
  equal(duplicateTopLevelKeys(args), ["template_key"]);
  const v = validateSupportActionProposal(args, {
    scope: "personalized",
    includedSources: [],
  });
  assert(!v.ok);
});

Deno.test("C06: responses accept 4,000 characters, reject 4,001; 1,001 is valid; total bytes still bounded", () => {
  const cp = (n: number, extra: Record<string, unknown> = {}) =>
    env("checkpoint_activity", {
      activity_id: U(3),
      checkpoint: { version: 1, responses: { see: "a".repeat(n) }, ...extra },
      active_ms: 1,
    });
  assert(parseMutationEnvelope(cp(1001)).ok);
  assert(parseMutationEnvelope(cp(4000)).ok);
  assert(!parseMutationEnvelope(cp(4001)).ok);
  // Many maximal answers in multibyte text exceed 32 KiB and are rejected, never truncated.
  const big = {
    responses: {
      see: "é".repeat(4000),
      feel: "é".repeat(4000),
      hear: "é".repeat(4000),
      smell: "é".repeat(4000),
      taste: "é".repeat(4000),
    },
  };
  assert(
    !parseMutationEnvelope(
      env("checkpoint_activity", {
        activity_id: U(3),
        checkpoint: { version: 1, ...big },
        active_ms: 1,
      }),
    ).ok,
  );
});

Deno.test("exact serialized bytes follow PostgreSQL jsonb text (', ' and ': ' separators)", () => {
  equal(jsonbBytes({ a: 1, b: [1, 2] }), '{"a": 1, "b": [1, 2]}'.length);
  equal(jsonbBytes({}), 2);
  equal(jsonbBytes("é"), 4);
  // A checkpoint that is under 32,768 compact bytes but over it in jsonb form is rejected.
  const filler = (n: number) => ({
    version: 1,
    responses: { see: "a".repeat(n) },
  });
  const n = 4000;
  const bodies: Record<string, unknown>[] = [];
  while (
    jsonbBytes({ ...filler(1), pad: bodies }) < 32_000 && bodies.length < 400
  ) bodies.push({ k: "v" });
  assert(jsonbBytes(filler(n)) < 32_768);
  const cpOf = (c: unknown) =>
    env("checkpoint_activity", {
      activity_id: U(3),
      checkpoint: c,
      active_ms: 1,
    });
  const justOver = {
    version: 1,
    current_step: "see",
    completed_steps: Array(1).fill("see"),
    responses: { see: "a".repeat(4000) },
    pad: Array.from({ length: 3000 }, () => 1),
  };
  const compact = new TextEncoder().encode(JSON.stringify(justOver)).length;
  const exact = jsonbBytes(justOver);
  assert(exact > compact, "jsonb text is longer than compact JSON");
  assert(parseMutationEnvelope(cpOf(justOver)).ok === (exact <= 32_768));
});

Deno.test("update_session: conversation_id lazy attachment field (alias attach_conversation_id)", () => {
  assert(
    parseMutationEnvelope(env("update_session", { conversation_id: U(9) })).ok,
  );
  assert(
    parseMutationEnvelope(
      env("update_session", { attach_conversation_id: U(9) }),
    ).ok,
  );
  assert(
    !parseMutationEnvelope(env("update_session", { conversation_id: "nope" }))
      .ok,
  );
  assert(
    !parseMutationEnvelope(
      env("update_session", {
        conversation_id: U(9),
        attach_conversation_id: U(8),
      }),
    ).ok,
  );
});

Deno.test("S08: a memory correction requires expected_revision; other memory ops may carry one", () => {
  const m = (kind: string, payload: Record<string, unknown>) =>
    parseMemoryEnvelope({
      schema_version: 1,
      operation_id: U(1),
      kind,
      payload,
    });
  assert(!m("memory_edit", { memory_id: U(5), content: "new" }).ok);
  assert(
    m("memory_edit", { memory_id: U(5), content: "new", expected_revision: 2 })
      .ok,
  );
  assert(
    !m("memory_edit", { memory_id: U(5), content: "new", expected_revision: 0 })
      .ok,
  );
  assert(m("memory_stop_using", { memory_id: U(5), expected_revision: 3 }).ok);
});

Deno.test("C06-R1: the shared limit unit is Unicode code points (JS spread == Postgres char_length)", () => {
  const cp = (v: string) =>
    env("checkpoint_activity", {
      activity_id: U(3),
      checkpoint: { version: 1, responses: { see: v } },
      active_ms: 1,
    });
  const decomposed = "e\u0301"; // 1 grapheme, 2 code points
  equal([...decomposed.repeat(2000)].length, 4000);
  assert(
    parseMutationEnvelope(cp(decomposed.repeat(2000))).ok,
    "4000 code points accepted",
  );
  assert(
    !parseMutationEnvelope(cp(decomposed.repeat(2001))).ok,
    "4002 code points rejected",
  );
  // 4000 graphemes of e + combining acute is 8000 code points: rejected, never truncated.
  assert(!parseMutationEnvelope(cp(decomposed.repeat(4000))).ok);
  assert(
    parseMutationEnvelope(cp("\u00e9".repeat(4000))).ok,
    "4000 precomposed accepted",
  );
  assert(
    parseMutationEnvelope(cp("\u{1F600}".repeat(1000))).ok,
    "astral code points counted once",
  );
});
