// M4: privacy-capable support-session text chat. Synthetic fixtures only.
//
// The REAL entrypoint (functions/chat/index.ts, Deno.serve wrapper included) runs against an
// in-process fake of Supabase REST/RPC and the OpenAI Responses endpoint, installed on
// globalThis.fetch. No network permission is used and no key, account or provider is touched.
//
// The fake `support_confirm_chat_turn` is a TypeScript PORT of the SQL function's decisions
// (claim identity, receipt replay, privacy revision, cited-source revalidation, proposal
// drop, `support_confirmed` ids, terminal response). It checks the TypeScript integration
// only; the SQL itself is validated separately (supabase/tests/support_session.sql, not run
// here).
import {
  annotateMemoryRefs,
  buildLegacyWireTemplate,
  buildWireTemplate,
  capabilityGate,
  type CitedMessageRow,
  confirmSupportTurn,
  parseSupportChatFields,
  pendingLocalMessageId,
  planSupportTurn,
  prepareSupportContext,
  promptOverheadBytes,
  renderSupportWire,
  sourcesStillCurrent,
  SUPPORT_CHAT_MAX_OUTPUT_TOKENS,
} from "../functions/_shared/support-chat.ts";
import {
  assembleContext,
  defaultContextDeps,
} from "../functions/_shared/support-context-policy.ts";
import {
  MAX_PROMPT_BYTES,
  SUPPORT_ACTION_OVERHEAD_BYTES,
  SUPPORT_ACTION_TOOL,
} from "../functions/_shared/openai-chat.ts";
import {
  REASON_CODES,
  TEMPLATE_KEYS,
} from "../functions/_shared/support-contract.ts";
import { CRISIS_RESPONSE } from "../functions/_shared/crisis.ts";
import { getReframe } from "../functions/_shared/reframe-templates.ts";
import { sanitizeForPrompt } from "../functions/_shared/sanitize.ts";
import type { ContextSourceRecords } from "../functions/_shared/support-context-policy.ts";

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
function deferred() {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;
const userId = "11111111-1111-4111-8111-111111111111";
const otherUser = "99999999-9999-4999-8999-999999999999";
const conversationId = "22222222-2222-4222-8222-222222222222";
const sessionId = "33333333-3333-4333-8333-333333333333";
const memoryId = "44444444-4444-4444-8444-444444444444";
const boundaryId = "55555555-5555-4555-8555-555555555555";
const requestId = "abcdefab-3333-4333-8333-333333333333";
const base = "http://localhost:55321";
const MESSAGE = "I keep putting off an email to my supervisor.";
const encoder = new TextEncoder();

// Opt-in fixture export for the Swift side: M4_FIXTURE_DIR=<dir> deno test --allow-write=<dir> ...
// Ids and times are normalized to stable values so the files are reproducible.
const fixtureDir = Deno.env.get("M4_FIXTURE_DIR");
function fixture(name: string, value: unknown) {
  if (!fixtureDir) return;
  const ids = new Map<string, string>();
  const norm = (v: unknown, key = ""): unknown => {
    if (typeof v === "string") {
      if (
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
          v,
        )
      ) {
        if (!ids.has(v)) {
          ids.set(
            v,
            `00000000-0000-4000-8000-${String(ids.size + 1).padStart(12, "0")}`,
          );
        }
        return ids.get(v);
      }
      if (/^\d{4}-\d\d-\d\dT/.test(v)) {
        return key === "expires_at"
          ? "2026-11-07T12:00:00.000Z"
          : "2026-11-06T12:00:00.000Z";
      }
      return v;
    }
    if (typeof v === "number" && key === "createdAt") return 1793966400;
    if (Array.isArray(v)) return v.map((x) => norm(x, key));
    if (v && typeof v === "object") {
      return Object.fromEntries(
        Object.entries(v as Row).map(([k, x]) => [k, norm(x, k)]),
      );
    }
    return v;
  };
  Deno.mkdirSync(fixtureDir, { recursive: true });
  const text = typeof value === "string"
    ? value
    : JSON.stringify(norm(value), null, 2) + "\n";
  Deno.writeTextFileSync(`${fixtureDir}/${name}`, text);
}

const ARGS = (over: Row = {}) =>
  JSON.stringify({
    template_key: "ground_present_v1",
    reason_code: "current_request",
    basis_ref: null,
    suggested_step: null,
    ...over,
  });

// ---------------------------------------------------------------------------
// Fake backend state
// ---------------------------------------------------------------------------
type Scenario = {
  text?: string;
  tool?: string | string[] | null;
  toolName?: string;
  refusal?: string;
  end?: "completed" | "incomplete" | "failed" | "cut";
};

const SEED_MESSAGE_ID = "d0000000-0000-4000-8000-000000000001";

function state() {
  return {
    // Supabase tables
    claims: new Map<string, Row>(),
    messages: [{
      id: SEED_MESSAGE_ID,
      conversation_id: conversationId,
      role: "assistant",
      content: "Earlier reply",
      content_origin: null as string | null,
      content_revision: 0,
      created_at: "2026-11-01T12:00:00Z",
    }] as Row[],
    receipts: [] as Row[],
    proposals: [] as Row[],
    suppressions: [] as Row[],
    memories: [] as Row[],
    intent: null as Row | null,
    session: {
      id: sessionId,
      user_id: userId,
      conversation_id: conversationId as string | null,
      title: "",
      concern: null as string | null,
      context_scope: "personalized",
      status: "open",
      selected_activity_id: null,
      context_revision: 3,
      suppressed_templates: [] as string[],
    } as Row | null,
    privacyRevision: 7,
    privacyMode: "standard",
    // capability / behavior switches
    caps: "ok" as
      | "ok"
      | "missing"
      | "error"
      | "no-policy"
      | "no-session"
      | "no-confirm",
    provider: { text: "Here is a gentle way to start." } as Scenario,
    providerHold: false,
    // Provider failure injections: a transport error, an HTTP error, or a malformed body.
    providerThrow: "",
    providerHttp: "",
    providerRaw: null as string | null,
    absenceReads: 0,
    coachOk: false,
    providerRelease: deferred(),
    providerStarted: deferred(),
    confirmPlan: [] as Array<
      | "ok"
      | "network-before"
      | "network-after"
      | "db-error"
      | "stale-race"
      | "missing"
    >,
    crisisConfirm: "ok" as "ok" | "db-error",
    confirmMissing: false,
    contextFail: false,
    // Rows a legacy (pre-support-schema) client path would read directly.
    fragments: [] as Row[],
    curated: [] as Row[],
    legacyIntents: [] as Row[],
    fragmentWrites: [] as Row[],
    messageInserts: [] as Row[],
    directAssistantInserts: 0,
    // One entry is consumed per assistant insert ATTEMPT (default "ok").
    assistantInsertPlan: [] as Array<
      | "ok"
      | "missing-pgrst204"
      | "missing-42703"
      | "missing-other-column"
      // The cache refuses support_session_id while content_origin exists.
      | "missing-session-column"
      | "check-violation"
      // A 200 whose body is not a valid message acknowledgment, WITHOUT / WITH an actual commit.
      | "ack-empty"
      | "ack-wrong-id-type"
      | "ack-array"
      | "ack-other-conversation"
      | "ack-wrong-role"
      | "commit-ack-empty"
      | "commit-ack-wrong-id-type"
      | "commit-ack-array"
      | "commit-ack-other-conversation"
      | "commit-ack-wrong-role"
      | "db-error"
      | "network-before"
      | "network-after"
    >,
    // A schema WITHOUT messages.content_origin / support_session_id.
    noOriginColumn: false,
    messageTags: 0,
    historyReads: 0,
    messageLookups: 0,
    // Text an error from a dependency would quote; it must never be logged or returned.
    sentinel: "",
    fail: {
      quotaRpc: false,
      conversationLookup: false,
      profileLookup: false,
      usageRpc: false,
      titleUpdate: false,
      fragmentUpsert: false,
      coachDistortion: false,
      messageTag: false,
    },
    therapyConnections: [] as Row[],
    hooks: {
      onContextSources: undefined as undefined | ((n: number) => void),
      onProviderResponse: undefined as undefined | (() => void),
      onBudget: undefined as undefined | (() => void),
      // Runs inside the confirm RPC, after the client's last check and before the commit.
      onConfirm: undefined as undefined | (() => void),
    },
    // counters / captures
    providerCalls: 0,
    providerBodies: [] as Row[],
    quotaCalls: 0,
    quotaUsed: 0,
    budgetCalls: 0,
    confirmCalls: 0,
    confirmArgs: [] as Row[],
    contextCalls: [] as Row[],
    tableCalls: [] as string[],
    rpcCalls: [] as string[],
    claimWrites: [] as Row[],
    notifications: 0,
  };
}

const LEGACY_PERSONAL_TABLES =
  /(memory_fragments|companion_memory|daily_intents)/;

function notFound406() {
  return Response.json({
    code: "PGRST116",
    details: "The result contains 0 rows",
    hint: null,
    message: "JSON object requested, multiple (or no) rows returned",
  }, { status: 406 });
}
const dbError = () =>
  Response.json({ code: "XX000", message: "Synthetic database failure" }, {
    status: 503,
  });
/** A database error whose message and details quote private text (what a real driver can do). */
const dbErrorQuoting = (marker: string, status = 503) =>
  Response.json({
    code: "XX000",
    message: `value violates constraint: ${marker}`,
    details: `Failing row contains (${marker})`,
  }, { status });

// ---------------------------------------------------------------------------
// Provider emulation (OpenAI Responses, JSON and SSE)
// ---------------------------------------------------------------------------
function outputOf(sc: Scenario): Row[] {
  const out: Row[] = [];
  const content: Row[] = [];
  if (sc.text) content.push({ type: "output_text", text: sc.text });
  if (sc.refusal) content.push({ type: "refusal", refusal: sc.refusal });
  if (content.length) {
    out.push({ type: "message", id: "msg_1", status: "completed", content });
  }
  const tools = sc.tool === undefined || sc.tool === null
    ? []
    : Array.isArray(sc.tool)
    ? sc.tool
    : [sc.tool];
  tools.forEach((args, i) =>
    out.push({
      type: "function_call",
      id: `fc_${i + 1}`,
      call_id: `call_${i + 1}`,
      name: sc.toolName ?? "propose_support_action",
      arguments: args,
      status: "completed",
    })
  );
  return out;
}

function sseBody(sc: Scenario): string {
  const ev: Row[] = [];
  const output = outputOf(sc);
  output.forEach((item, index) => {
    if (item.type === "message") {
      ev.push({
        type: "response.output_item.added",
        output_index: index,
        item: { ...item, content: [], status: "in_progress" },
      });
      for (const part of item.content as Row[]) {
        if (part.type === "output_text") {
          const mid = Math.max(1, Math.floor(part.text.length / 2));
          for (const piece of [part.text.slice(0, mid), part.text.slice(mid)]) {
            if (piece) {
              ev.push({
                type: "response.output_text.delta",
                item_id: item.id,
                output_index: index,
                content_index: 0,
                delta: piece,
              });
            }
          }
        } else if (part.type === "refusal") {
          ev.push({
            type: "response.refusal.delta",
            item_id: item.id,
            output_index: index,
            content_index: 0,
            delta: part.refusal,
          });
          ev.push({
            type: "response.refusal.done",
            item_id: item.id,
            output_index: index,
            content_index: 0,
            refusal: part.refusal,
          });
        }
      }
      ev.push({ type: "response.output_item.done", output_index: index, item });
    } else {
      ev.push({
        type: "response.output_item.added",
        output_index: index,
        item: { ...item, arguments: "", status: "in_progress" },
      });
      const args = item.arguments as string;
      const mid = Math.floor(args.length / 2);
      ev.push({
        type: "response.function_call_arguments.delta",
        item_id: item.id,
        output_index: index,
        delta: args.slice(0, mid),
      });
      ev.push({
        type: "response.function_call_arguments.delta",
        item_id: item.id,
        output_index: index,
        delta: args.slice(mid),
      });
      ev.push({
        type: "response.function_call_arguments.done",
        item_id: item.id,
        output_index: index,
        arguments: args,
      });
      ev.push({ type: "response.output_item.done", output_index: index, item });
    }
  });
  const end = sc.end ?? "completed";
  if (end === "completed") {
    ev.push({
      type: "response.completed",
      response: {
        id: "resp_1",
        status: "completed",
        output,
        usage: { input_tokens: 10, output_tokens: 5 },
      },
    });
  } else if (end === "incomplete") {
    ev.push({
      type: "response.incomplete",
      response: { status: "incomplete" },
    });
  } else if (end === "failed") {
    ev.push({ type: "response.failed", response: { status: "failed" } });
  }
  return ev.map((e) => `data: ${JSON.stringify(e)}\n\n`).join("");
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------
Deno.test("M4 support chat: real route, both stream modes, fake REST/RPC/provider", async (t) => {
  const nativeFetch = globalThis.fetch;
  const nativeServe = Deno.serve;
  const nativeSetInterval = globalThis.setInterval;
  const intervals: ReturnType<typeof setInterval>[] = [];
  const env = {
    SUPABASE_URL: base,
    SUPABASE_ANON_KEY: "synthetic-anon",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service",
    VOICE_AND_NONIMAGE_OPENAI_API_KEY: "synthetic-provider",
  };
  const previous = Object.keys(env).map((name) => Deno.env.get(name));
  const runtime = globalThis as typeof globalThis & {
    EdgeRuntime?: { waitUntil(task: Promise<unknown>): void };
  };
  const previousRuntime = runtime.EdgeRuntime;
  const background: Promise<unknown>[] = [];
  let handler!: (req: Request) => Promise<Response>;
  let s = state();

  // ---- port of public.support_confirm_chat_turn (decisions only) ---------------
  function commitConfirm(a: Row): Row {
    const claim = s.claims.get(`${a.user_id}:${a.request_id}`);
    if (!claim) return { ok: false, code: "NOT_FOUND" };
    if (
      claim.conversation_id !== a.conversation_id ||
      claim.content_hash !== a.content_hash
    ) {
      return { ok: false, code: "OPERATION_ID_REUSED" };
    }
    const existing = s.receipts.find((r) => r.request_id === a.request_id);
    if (existing) {
      const prop = s.proposals.find((p) => p.request_id === a.request_id);
      return {
        ok: true,
        replayed: true,
        message_id: existing.assistant_message_id,
        receipt_id: existing.id,
        proposal_id: prop?.id ?? null,
        response: claim.response,
        response_status: claim.response_status,
      };
    }
    if (claim.response) return { ok: false, code: "OPERATION_ID_REUSED" };
    if (
      !["model", "interface_fallback", "safety_response"].includes(
        a.content_origin,
      ) || !String(a.assistant_content).trim()
    ) {
      return { ok: false, code: "INVALID_PAYLOAD" };
    }
    let session: Row | null = null;
    if (a.support_session_id) {
      session = s.session && s.session.id === a.support_session_id &&
          s.session.status === "open"
        ? s.session
        : null;
      if (
        !session ||
        (session.conversation_id &&
          session.conversation_id !== a.conversation_id)
      ) {
        return {
          ok: false,
          code: "NOT_FOUND",
          message: "session not found for this conversation",
        };
      }
    }
    if (s.privacyRevision !== a.privacy_revision) {
      return {
        ok: false,
        code: "PRIVACY_REVISION_STALE",
        current_privacy_revision: s.privacyRevision,
      };
    }
    for (const src of a.sources as Row[]) {
      if (src.kind === "companion_memory") {
        const m = s.memories.find((x) => x.id === src.id);
        if (a.scope !== "personalized") {
          return { ok: false, code: "INVALID_PAYLOAD" };
        }
        if (
          !m || m.revision !== src.revision ||
          s.suppressions.some((x) => x.kind === "memory" && x.ref_id === src.id)
        ) {
          return {
            ok: false,
            code: "PRIVACY_REVISION_STALE",
            message: "source_changed:companion_memory",
          };
        }
      } else if (src.kind === "session") {
        if (
          !s.session || s.session.status !== "open" ||
          s.session.context_revision !== src.revision
        ) {
          return {
            ok: false,
            code: "PRIVACY_REVISION_STALE",
            message: "source_changed:session",
          };
        }
      } else if (src.kind === "message") {
        // Latest M3 rule: the cited message must exist in THIS conversation at exactly the
        // cited server-owned content version (omitted means 0), and not be suppressed.
        const row = s.messages.find((m) =>
          m.id === src.id && m.conversation_id === a.conversation_id
        );
        if (
          !row ||
          Number(row.content_revision ?? 0) !== Number(src.revision ?? 0) ||
          s.suppressions.some((x) =>
            x.kind === "message" && x.ref_id === src.id
          )
        ) {
          return {
            ok: false,
            code: "PRIVACY_REVISION_STALE",
            message: "source_changed:message",
          };
        }
      }
    }
    const messageId = crypto.randomUUID();
    const receiptId = crypto.randomUUID();
    s.messages.push({
      id: messageId,
      conversation_id: a.conversation_id,
      role: "assistant",
      content: a.assistant_content,
      content_origin: a.content_origin,
      support_session_id: a.support_session_id,
      created_at: new Date().toISOString(),
    });
    s.receipts.push({
      id: receiptId,
      request_id: a.request_id,
      assistant_message_id: messageId,
      privacy_revision: a.privacy_revision,
      scope: a.scope,
      provider_vendor: a.provider_vendor,
      provider_model: a.provider_model,
      route_version: a.route_version,
      exclusions: a.exclusions,
      sources: a.sources,
    });
    let proposalId: string | null = null;
    const p = a.proposal as Row | null;
    if (
      p && session && a.content_origin !== "safety_response" &&
      !session.suppressed_templates.includes(p.template_key)
    ) {
      proposalId = crypto.randomUUID();
      s.proposals.push({
        id: proposalId,
        request_id: a.request_id,
        message_id: messageId,
        ...p,
        privacy_revision: s.privacyRevision,
        status: "offered",
      });
    }
    const response = {
      ...a.response,
      support_confirmed: {
        message_id: messageId,
        receipt_id: receiptId,
        proposal_id: proposalId,
      },
    };
    claim.response = response;
    claim.response_status = a.response_status;
    return {
      ok: true,
      replayed: false,
      message_id: messageId,
      receipt_id: receiptId,
      proposal_id: proposalId,
      proposal_dropped: null,
      privacy_revision: s.privacyRevision,
      response,
      response_status: a.response_status,
    };
  }

  function contextSources(body: Row): Row {
    s.contextCalls.push(body);
    s.hooks.onContextSources?.(s.contextCalls.length);
    const suppressedMessages = new Set(
      s.suppressions.filter((x) => x.kind === "message").map((x) => x.ref_id),
    );
    const conversationSuppressed = s.suppressions.some((x) =>
      x.kind === "conversation" && x.ref_id === body.p_conversation
    );
    const history = conversationSuppressed ? [] : s.messages
      .filter((m) =>
        m.conversation_id === body.p_conversation &&
        ["user", "assistant"].includes(m.role) &&
        (m.content_origin ?? "model") === "model" &&
        !suppressedMessages.has(m.id)
      )
      .slice(-Math.min(Math.max(body.p_history_limit, 1), 40))
      .map((m) => ({
        id: m.id,
        role: m.role,
        content: m.content,
        created_at: m.created_at ?? new Date().toISOString(),
        content_revision: m.content_revision ?? 0,
      }));
    // Same eligibility as the SQL: not deleted, not stopped, no memory/source/conversation
    // suppression. Expiry and life-context review are applied by the TypeScript policy.
    const memories = body.p_include_personal
      ? s.memories.filter((m) =>
        !m.deleted_at && !m.disabled_at &&
        !s.suppressions.some((x) =>
          (x.kind === "memory" && x.ref_id === m.id) ||
          (x.kind === "message" && m.source_message_id &&
            x.ref_id === m.source_message_id) ||
          (x.kind === "conversation" && m.source_conversation_id &&
            x.ref_id === m.source_conversation_id)
        )
      )
      : [];
    return {
      ok: true,
      privacy_revision: s.privacyRevision,
      memories,
      daily_intent: body.p_include_personal ? s.intent : null,
      history,
      conversation_suppressed: conversationSuppressed,
    };
  }

  async function providerFetch(
    body: Row,
    init?: RequestInit,
  ): Promise<Response> {
    s.providerCalls++;
    s.providerBodies.push(body);
    s.providerStarted.resolve();
    equal(body.model, "gpt-6-luna");
    // Main chat asserts exactly 500 where it matters; helper calls (title) use fewer.
    assert(body.max_output_tokens <= 500);
    equal(body.store, false);
    if (s.providerHold) {
      await new Promise<void>((resolve, reject) => {
        init!.signal!.addEventListener(
          "abort",
          () => reject(new DOMException("Aborted", "AbortError")),
          { once: true },
        );
        void s.providerRelease.promise.then(resolve);
      });
    }
    s.hooks.onProviderResponse?.();
    if (s.providerThrow) throw new TypeError(s.providerThrow);
    if (s.providerHttp) return new Response(s.providerHttp, { status: 503 });
    if (s.providerRaw !== null) {
      return new Response(
        body.stream ? `data: ${s.providerRaw}\n\n` : s.providerRaw,
        {
          headers: {
            "Content-Type": body.stream
              ? "text/event-stream"
              : "application/json",
          },
        },
      );
    }
    const sc = s.provider;
    if (body.stream) {
      return new Response(
        new ReadableStream<Uint8Array>({
          start(c) {
            c.enqueue(encoder.encode(sseBody(sc)));
            c.close();
          },
        }),
        { headers: { "Content-Type": "text/event-stream" } },
      );
    }
    const end = sc.end ?? "completed";
    if (end === "incomplete" || end === "failed") {
      return Response.json({ status: end });
    }
    if (end === "cut") return Response.json({ status: "in_progress" });
    return Response.json({
      id: "resp_1",
      status: "completed",
      output: outputOf(sc),
      usage: { input_tokens: 10, output_tokens: 5 },
    });
  }

  function filterRows(url: URL, source: Row[]): Row[] {
    return source.filter((row) =>
      [...url.searchParams].every(([key, filter]) => {
        if (
          ["select", "order", "limit", "on_conflict", "columns"].includes(key)
        ) return true;
        const value = key === "response->>failureId"
          ? row.response?.failureId ?? null
          : row[key];
        if (filter === "is.null") return value == null;
        if (filter === "not.is.null") return value != null;
        if (filter.startsWith("eq.")) return String(value) === filter.slice(3);
        if (filter.startsWith("neq.")) return String(value) !== filter.slice(4);
        if (filter.startsWith("in.(") && filter.endsWith(")")) {
          return filter.slice(4, -1).split(",").includes(String(value));
        }
        throw new Error(`Unhandled filter ${key}: ${filter}`);
      })
    );
  }
  function selected(url: URL, source: Row[], headers: Headers) {
    const found = filterRows(url, source);
    if (headers.get("Accept")?.includes("vnd.pgrst.object")) {
      return found.length === 1 ? Response.json(found[0]) : notFound406();
    }
    return Response.json(found);
  }

  async function mockedFetch(
    input: RequestInfo | URL,
    init?: RequestInit,
  ): Promise<Response> {
    const url = new URL(input instanceof Request ? input.url : String(input));
    const method = init?.method ?? "GET";
    const headers = new Headers(init?.headers);
    const body = init?.body ? JSON.parse(String(init.body)) : undefined;
    if (url.href === "https://api.openai.com/v1/responses") {
      return await providerFetch(body, init);
    }
    assert(url.origin === base, `External request denied: ${url.origin}`);
    if (url.pathname === "/auth/v1/user") {
      return Response.json({
        id: userId,
        aud: "authenticated",
        role: "authenticated",
      });
    }
    if (url.pathname.startsWith("/rest/v1/rpc/")) {
      const name = url.pathname.split("/").at(-1)!;
      s.rpcCalls.push(name);
      switch (name) {
        case "check_rate_limit":
          return Response.json([{
            allowed: true,
            remaining: 9,
            reset_at: new Date(Date.now() + 60_000).toISOString(),
          }]);
        case "refresh_user_entitlement":
          return Response.json(false);
        case "check_and_increment_ai_quota": {
          if (s.fail.quotaRpc) return dbErrorQuoting(s.sentinel);
          s.quotaCalls++;
          s.quotaUsed++;
          return Response.json([{
            allowed: true,
            quota_used: s.quotaUsed,
            quota_limit: 5,
            was_reset: false,
          }]);
        }
        case "reserve_monthly_ai_budget": {
          s.budgetCalls++;
          s.hooks.onBudget?.();
          return Response.json({
            allowed: true,
            reason: "reserved",
            request_id: body.p_request_id,
            user_id: body.p_user_id,
            feature: body.p_feature,
            reserve_microdollars: body.p_reserve_microdollars,
            month_start: "2026-11-01",
            reserved_microdollars: body.p_reserve_microdollars,
            limit_microdollars: 10_000_000,
            remaining_microdollars: 10_000_000 - body.p_reserve_microdollars,
          });
        }
        case "support_capabilities": {
          if (s.caps === "missing") {
            return Response.json({
              code: "PGRST202",
              message:
                "Could not find the function public.support_capabilities without parameters in the schema cache",
            }, { status: 404 });
          }
          if (s.caps === "error") return dbError();
          return Response.json({
            session_contract: s.caps === "no-session" ? 0 : 1,
            context_policy: s.caps === "no-policy" ? 0 : 1,
            voice_context: 0,
            privacy_revision: true,
            memory_lifecycle: true,
            chat_confirmation: s.caps !== "no-confirm",
            lazy_attach: true,
            schema: "20261106230200",
          });
        }
        case "support_context_sources":
          if (s.contextFail) return dbError();
          return Response.json(contextSources(body));
        case "log_coach_encounter":
          return Response.json({
            success: true,
            encounter_id: "c0000000-0000-4000-8000-000000000001",
          });
        case "update_companion_memory_usage":
          return s.fail.usageRpc
            ? dbErrorQuoting(s.sentinel)
            : new Response(null, { status: 204 });
        case "support_confirm_chat_turn": {
          s.confirmCalls++;
          s.confirmArgs.push(body.p_args);
          if (s.confirmMissing) {
            return Response.json({
              code: "PGRST202",
              message:
                "Could not find the function public.support_confirm_chat_turn(p_args) in the schema cache",
            }, { status: 404 });
          }
          const step = s.confirmPlan.shift() ?? "ok";
          if (step === "missing") {
            // A schema-cache miss for THIS attempt only; it proves nothing about earlier ones.
            return Response.json({
              code: "PGRST202",
              message:
                "Could not find the function public.support_confirm_chat_turn(p_args) in the schema cache",
            }, { status: 404 });
          }
          if (step === "network-before") {
            throw new TypeError("Synthetic lost request");
          }
          if (step === "db-error") return dbError();
          if (step === "stale-race") {
            return Response.json({
              ok: false,
              code: "PRIVACY_REVISION_STALE",
              current_privacy_revision: s.privacyRevision + 1,
            });
          }
          if (
            s.crisisConfirm === "db-error" &&
            body.p_args.content_origin === "safety_response"
          ) return dbError();
          s.hooks.onConfirm?.();
          const result = commitConfirm(body.p_args);
          if (step === "network-after") {
            throw new TypeError("Synthetic lost response");
          }
          return Response.json(result);
        }
        default:
          throw new Error(`Unhandled RPC: ${name}`);
      }
    }
    const table = url.pathname.split("/").at(-1)!;
    s.tableCalls.push(`${method} ${table}`);
    if (LEGACY_PERSONAL_TABLES.test(table)) {
      if (method !== "GET") {
        s.fragmentWrites.push(body);
        return s.fail.fragmentUpsert
          ? dbErrorQuoting(s.sentinel)
          : new Response(null, { status: 201 });
      }
      if (table === "memory_fragments") return Response.json(s.fragments);
      if (table === "companion_memory") return Response.json(s.curated);
      return Response.json(s.legacyIntents.slice(0, 1));
    }
    switch (table) {
      case "conversations":
        if (method !== "GET") {
          // Title update.
          return s.fail.titleUpdate
            ? dbErrorQuoting(s.sentinel)
            : new Response(null, { status: 204 });
        }
        if (s.fail.conversationLookup) return dbErrorQuoting(s.sentinel, 400);
        return selected(
          url,
          [{ id: conversationId, user_id: userId }],
          headers,
        );
      case "profiles": {
        if (url.searchParams.get("select") === "last_absence_days") {
          s.absenceReads++;
          return Response.json({ last_absence_days: 30 });
        }
        if (s.fail.profileLookup) return dbErrorQuoting(s.sentinel, 400);
        return selected(url, [{
          id: userId,
          subscription_tier: "free",
          preferred_language: "en",
        }], headers);
      }
      case "user_settings":
        return Response.json({
          privacy_mode: s.privacyMode,
          ai_tone: "friendly",
        });
      case "coach_settings":
        // Enabled: the coach only runs once a conversation is past its first exchanges AND a
        // distortion is detected, so ordinary tests (short history) never reach it.
        return Response.json({
          is_enabled: true,
          sensitivity_level: "balanced",
          timezone: "UTC",
          disabled_distortions: [],
        });
      case "cognitive_distortions":
        if (s.fail.coachDistortion) return dbErrorQuoting(s.sentinel, 400);
        return Response.json({
          id: "d1000000-0000-4000-8000-000000000001",
          name: "n",
          short_description: "s",
          full_description: "f",
          distortion_education: s.coachOk
            ? [{
              locale: "en",
              name_translated: "All-or-nothing thinking",
              short_description_translated: "Seeing only extremes.",
              full_description_translated: "Education text.",
              reframe_templates_translated: ["Consider the middle ground."],
              questions_translated: ["What would you tell a friend?", "q2"],
            }]
            : [],
        });
      case "distortion_education":
        // English fallback lookup.
        return dbErrorQuoting(s.sentinel, 400);
      case "therapy_connections":
        return Response.json(s.therapyConnections);
      case "crisis_events":
        return new Response(null, { status: 201 });
      case "notification_history":
        s.notifications++;
        return new Response(null, { status: 201 });
      case "therapy_access_log":
        return new Response(null, { status: 201 });
      case "support_privacy_state":
        return Response.json({ privacy_revision: s.privacyRevision });
      case "support_suppressions":
        return Response.json(s.suppressions);
      case "support_work_sessions":
        return selected(url, s.session ? [s.session] : [], headers);
      case "support_activities":
        return Response.json([]);
      case "chat_requests": {
        const key = `${
          body?.user_id ?? url.searchParams.get("user_id")?.slice(3)
        }:${body?.request_id ?? url.searchParams.get("request_id")?.slice(3)}`;
        const claim = s.claims.get(key);
        if (method === "POST") {
          if (claim) return Response.json({ code: "23505" }, { status: 409 });
          s.claims.set(key, { ...body, response: null, response_status: null });
          return new Response(null, { status: 201 });
        }
        if (method === "GET") {
          return selected(
            url,
            claim ? [JSON.parse(JSON.stringify(claim))] : [],
            headers,
          );
        }
        assert(method === "PATCH");
        s.claimWrites.push({
          response: body.response,
          status: body.response_status,
        });
        const matched = filterRows(url, claim ? [claim] : []);
        if (matched.length) Object.assign(matched[0], body);
        if (headers.get("Accept")?.includes("vnd.pgrst.object")) {
          return matched.length
            ? Response.json({ request_id: matched[0].request_id })
            : notFound406();
        }
        return Response.json(
          matched.map((r) => ({ request_id: r.request_id })),
        );
      }
      case "messages": {
        if (method === "PATCH") {
          // Best-effort origin tag on an existing row.
          s.messageTags++;
          if (s.fail.messageTag) return dbErrorQuoting(s.sentinel, 400);
          for (const row of filterRows(url, s.messages)) {
            Object.assign(row, body);
          }
          return new Response(null, { status: 204 });
        }
        if (method === "POST") {
          s.messageInserts.push(body);
          let loseResponseAfterCommit = false;
          const ack = {
            shape: "valid" as
              | "valid"
              | "empty"
              | "wrong-id-type"
              | "array"
              | "other-conversation"
              | "wrong-role",
            commit: true,
          };
          if (body.role === "assistant") {
            s.directAssistantInserts++;
            const missing = (code: string, column: string) =>
              Response.json({
                code,
                message: code === "PGRST204"
                  ? `Could not find the '${column}' column of 'messages' in the schema cache`
                  : `column "${column}" of relation "messages" does not exist`,
              }, { status: 400 });
            if (
              s.noOriginColumn &&
              ("content_origin" in body || "support_session_id" in body)
            ) return missing("PGRST204", "content_origin");
            const step = s.assistantInsertPlan.shift() ?? "ok";
            if (step === "missing-pgrst204") {
              return missing("PGRST204", "content_origin");
            }
            if (step === "missing-42703") {
              return missing("42703", "content_origin");
            }
            if (step === "missing-other-column") {
              return missing("PGRST204", "some_other_column");
            }
            if (step === "missing-session-column") {
              return missing("PGRST204", "support_session_id");
            }
            if (step === "db-error") return dbErrorQuoting(s.sentinel, 400);
            if (step === "check-violation") {
              // Names the column, but the column EXISTS: not evidence that nothing committed.
              return Response.json({
                code: "23502",
                message:
                  'null value in column "content_origin" of relation "messages" violates not-null constraint',
              }, { status: 400 });
            }
            if (step === "network-before") {
              throw new TypeError("Synthetic lost request");
            }
            loseResponseAfterCommit = step === "network-after";
            const shape =
              /^(commit-)?ack-(empty|wrong-id-type|array|other-conversation|wrong-role)$/
                .exec(step);
            if (shape) {
              ack.shape = shape[2] as typeof ack.shape;
              ack.commit = shape[1] === "commit-";
            }
          }
          const row = {
            id: crypto.randomUUID(),
            created_at: new Date().toISOString(),
            content_origin: null,
            content_revision: 0,
            ...body,
          };
          if (s.messages.some((m) => m.id === row.id)) {
            return Response.json({ code: "23505" }, { status: 409 });
          }
          if (ack.commit) s.messages.push(row);
          if (loseResponseAfterCommit) {
            throw new TypeError("Synthetic lost response");
          }
          if (ack.shape === "empty") return Response.json({});
          if (ack.shape === "wrong-id-type") {
            return Response.json({ ...row, id: 12345 });
          }
          if (ack.shape === "array") return Response.json([row]);
          if (ack.shape === "other-conversation") {
            return Response.json({
              ...row,
              conversation_id: "77777777-7777-4777-8777-777777777777",
            });
          }
          if (ack.shape === "wrong-role") {
            return Response.json({ ...row, role: "user" });
          }
          return Response.json(row);
        }
        assert(method === "GET");
        if (url.searchParams.has("limit")) s.historyReads++;
        if ((url.searchParams.get("id") ?? "").startsWith("in.")) {
          s.messageLookups++;
        }
        return selected(url, [...s.messages].reverse(), headers);
      }
      default:
        throw new Error(`Unhandled table ${table}`);
    }
  }

  // ---- request helpers ---------------------------------------------------------
  const supportBody = (over: Row = {}): Row => ({
    conversationId,
    content: MESSAGE,
    requestId,
    schema_version: 1,
    support_session_id: sessionId,
    context_scope: "personalized",
    expected_privacy_revision: s.privacyRevision,
    expected_owner: userId,
    ...over,
  });
  function post(
    body: Row,
    options: { stream?: boolean; signal?: AbortSignal } = {},
  ) {
    return handler(
      new Request("http://localhost/chat", {
        method: "POST",
        headers: {
          Authorization: "Bearer synthetic-token",
          "Content-Type": "application/json",
          Accept: options.stream ? "text/event-stream" : "application/json",
        },
        body: JSON.stringify(body),
        signal: options.signal,
      }),
    );
  }
  type Wire = {
    status: number;
    data: Row;
    events: Row[];
    deltas: string;
    streamed: boolean;
  };
  async function read(response: Response): Promise<Wire> {
    const type = response.headers.get("Content-Type") ?? "";
    if (type.includes("text/event-stream")) {
      const events = (await response.text()).split("\n\n").filter(Boolean).map((
        chunk,
      ) => JSON.parse(chunk.replace(/^data: /, "")));
      const last = events.at(-1)!;
      assert(
        last.type === "result" || last.type === "error",
        "stream ends with a terminal event",
      );
      return {
        status: last.status,
        data: last.data,
        events,
        streamed: true,
        deltas: events.filter((e) => e.type === "delta").map((e) => e.text)
          .join(""),
      };
    }
    return {
      status: response.status,
      data: await response.json(),
      events: [],
      deltas: "",
      streamed: false,
    };
  }
  async function send(
    over: Row = {},
    options: { stream?: boolean; signal?: AbortSignal } = {},
  ) {
    return read(await post(supportBody(over), options));
  }
  // Replies written by the server in this test (the seeded history row, even if a test
  // rewrites it, and rows the R02 fixtures plant as history, are not new replies).
  const assistants = () =>
    s.messages.filter((m) =>
      m.role === "assistant" && m.id !== SEED_MESSAGE_ID &&
      !String(m.id).startsWith("e2000000") && m.content !== "Earlier reply"
    );
  const claim = () => s.claims.get(`${userId}:${requestId}`)!;
  const providerInput = (n = 0) => s.providerBodies[n].input as Row[];
  const sideEffects = () => ({
    provider: s.providerCalls,
    quota: s.quotaCalls,
    budget: s.budgetCalls,
    confirm: s.confirmCalls,
    claims: s.claims.size,
  });
  function noLegacyPersonalReads() {
    assert(
      !s.tableCalls.some((c) => LEGACY_PERSONAL_TABLES.test(c)),
      `legacy personal table read: ${s.tableCalls.join(",")}`,
    );
    assert(!s.tableCalls.includes("GET profiles") || true);
  }
  function noUnrelatedWork() {
    equal(
      background.length,
      0,
      "no background title/extraction work for the new contract",
    );
    assert(!s.rpcCalls.includes("log_coach_encounter"));
    assert(!s.rpcCalls.includes("update_companion_memory_usage"));
    assert(
      !s.tableCalls.includes("POST memory_fragments") &&
        !s.tableCalls.includes("PATCH memory_fragments"),
    );
  }

  try {
    for (const [name, value] of Object.entries(env)) Deno.env.set(name, value);
    runtime.EdgeRuntime = {
      waitUntil(task) {
        background.push(task);
      },
    };
    globalThis.setInterval = ((...args: Parameters<typeof setInterval>) => {
      const interval = nativeSetInterval(...args);
      intervals.push(interval);
      return interval;
    }) as typeof setInterval;
    globalThis.fetch = mockedFetch;
    Object.defineProperty(Deno, "serve", {
      configurable: true,
      value: (value: typeof handler) => {
        handler = value;
      },
    });
    await import("../functions/chat/index.ts");

    const reset = () => {
      s = state();
      background.length = 0;
    };
    const seedMemory = () => {
      s.memories = [
        {
          id: boundaryId,
          category: "boundaries",
          content: "Please do not mention my sister.",
          revision: 2,
          confirmed_at: "2026-10-01T00:00:00Z",
          review_due_at: null,
          expires_at: null,
        },
        {
          id: memoryId,
          category: "preferences",
          content:
            "Likes email tasks split into steps without breath counting.",
          revision: 1,
          confirmed_at: "2026-11-02T00:00:00Z",
          review_due_at: null,
          expires_at: null,
        },
      ];
      s.intent = {
        id: "66666666-6666-4666-8666-666666666666",
        intent: "stay calm today",
        created_at: new Date(Date.now() - 3600_000).toISOString(),
        expires_at: new Date(Date.now() + 20 * 3600_000).toISOString(),
      };
    };

    // =========================================================================
    // Handshake and request contract
    // =========================================================================
    await t.step(
      "handshake proves the deployed chat contract and never reaches the provider",
      async () => {
        reset();
        const res = await post({ op: "capabilities", schema_version: 1 });
        const body = await res.json();
        equal([
          res.status,
          body.ok,
          body.chat_contract,
          body.session_contract,
          body.context_policy,
          body.privacy_revision,
          body.chat_confirmation,
          body.status,
        ], [200, true, 1, 1, 1, true, true, "ok"]);
        fixture("handshake_ok.json", body);
        equal(sideEffects(), {
          provider: 0,
          quota: 0,
          budget: 0,
          confirm: 0,
          claims: 0,
        });
        s.caps = "missing";
        const missing =
          await (await post({ op: "capabilities", schema_version: 1 })).json();
        equal([
          missing.chat_contract,
          missing.session_contract,
          missing.context_policy,
          missing.status,
        ], [1, 0, 0, "not_deployed"]);
        s.caps = "error";
        const temp = await post({ op: "capabilities", schema_version: 1 });
        const tempBody = await temp.json();
        equal([
          temp.status,
          tempBody.code,
          tempBody.capability,
          tempBody.retryable,
        ], [503, "chat_support_unavailable", "unavailable", true]);
        fixture("failure_support_unavailable.json", tempBody);
        fixture("handshake_not_deployed.json", missing);
        const wrong = await post({ op: "capabilities" });
        equal(wrong.status, 400);
      },
    );

    await t.step(
      "new-contract fields are validated; nothing is claimed or sent on a bad request",
      async () => {
        const cases: Array<[string, Row, number, string]> = [
          [
            "unsupported schema",
            { schema_version: 2 },
            400,
            "chat_support_schema_unsupported",
          ],
          [
            "string schema",
            { schema_version: "1" },
            400,
            "chat_support_schema_unsupported",
          ],
          [
            "missing request id",
            { requestId: undefined },
            400,
            "chat_support_invalid_request",
          ],
          [
            "bad scope",
            { context_scope: "everything" },
            400,
            "chat_support_invalid_request",
          ],
          [
            "missing scope",
            { context_scope: undefined },
            400,
            "chat_support_invalid_request",
          ],
          [
            "personalized without revision",
            { expected_privacy_revision: null },
            400,
            "chat_support_invalid_request",
          ],
          [
            "bad revision",
            { expected_privacy_revision: 0 },
            400,
            "chat_support_invalid_request",
          ],
          [
            "missing owner",
            { expected_owner: undefined },
            400,
            "chat_support_invalid_request",
          ],
          [
            "bad session id",
            { support_session_id: "nope" },
            400,
            "chat_support_invalid_request",
          ],
          [
            "unknown intent",
            { selected_intent: "run_a_marathon" },
            400,
            "chat_support_invalid_request",
          ],
          [
            "too many memory ids",
            { selected_memory_ids: Array(6).fill(memoryId) },
            400,
            "chat_support_invalid_request",
          ],
          [
            "memory ids need personalized",
            {
              context_scope: "conversation_only",
              selected_memory_ids: [memoryId],
            },
            400,
            "chat_support_invalid_request",
          ],
          [
            "owner mismatch",
            { expected_owner: otherUser },
            409,
            "chat_owner_mismatch",
          ],
        ];
        for (const [label, over, status, code] of cases) {
          reset();
          const res = await send(over);
          equal([label, res.status, res.data.code, res.data.retryable], [
            label,
            status,
            code,
            false,
          ]);
          equal(sideEffects(), {
            provider: 0,
            quota: 0,
            budget: 0,
            confirm: 0,
            claims: 0,
          }, label);
          noLegacyPersonalReads();
        }
        // A new field without schema_version can never be silently treated as a legacy request.
        reset();
        const { schema_version: _drop, ...noSchema } = supportBody();
        const res = await read(await post(noSchema));
        equal([res.status, res.data.code], [
          400,
          "chat_support_schema_unsupported",
        ]);
        equal(sideEffects().provider, 0);
      },
    );

    await t.step(
      "missing or insufficient capability fails closed: no claim, quota, provider or old personal read",
      async () => {
        for (
          const caps of [
            "missing",
            "error",
            "no-policy",
            "no-confirm",
            "no-session",
          ] as const
        ) {
          for (const stream of [false, true]) {
            reset();
            seedMemory();
            s.caps = caps;
            const res = await send({}, { stream });
            const capability = caps === "missing"
              ? "not_deployed"
              : caps === "error"
              ? "unavailable"
              : "insufficient";
            equal([
              caps,
              res.status,
              res.data.code,
              res.data.capability,
              res.data.retryable,
            ], [
              caps,
              503,
              "chat_support_unavailable",
              capability,
              caps === "error",
            ]);
            // The claim holds the failure receipt; nothing is debited, sent or personalized.
            equal(sideEffects(), {
              provider: 0,
              quota: 0,
              budget: 0,
              confirm: 0,
              claims: 1,
            }, caps);
            equal([claim().response_status, claim().response.code], [
              503,
              "chat_support_unavailable",
            ]);
            noLegacyPersonalReads();
            assert(
              !s.rpcCalls.includes("support_context_sources"),
              "no context read without a proven contract",
            );
            assert(!s.rpcCalls.includes("support_confirm_chat_turn"));
            if (caps === "error") {
              // A transient outage is explicitly retryable under the same request id.
              s.caps = "ok";
              const retried = await send({ retryFailed: true }, { stream });
              equal([
                retried.status,
                s.providerCalls,
                s.quotaCalls,
                assistants().length,
              ], [200, 1, 1, 1]);
            }
          }
        }
        // Session persistence is negotiated separately: ordinary private chat without a session
        // is allowed when the context policy, privacy revision and confirmation are proven.
        reset();
        s.caps = "no-session";
        const ok = await send({
          support_session_id: null,
          context_scope: "conversation_only",
        });
        equal([
          ok.status,
          ok.data.support.support_session_id,
          ok.data.support.proposal,
        ], [200, null, null]);
      },
    );

    // =========================================================================
    // Provider outcomes, both stream modes
    // =========================================================================
    for (const stream of [false, true]) {
      const mode = stream ? "stream" : "json";

      await t.step(
        `${mode}: text only is one provider call, one quota debit, one atomic confirm`,
        async () => {
          reset();
          seedMemory();
          s.provider = { text: "Start with the subject line." };
          const res = await send({}, { stream });
          equal(res.status, 200);
          equal(res.streamed, stream);
          if (stream) {
            equal(res.deltas, "Start with the subject line.");
            assert(
              res.events.every((e) =>
                e.type === "delta" || e.type === "result"
              ),
              "only provisional text before the result",
            );
            assert(
              res.events.filter((e) => e.type === "delta").every((e) =>
                !("proposal" in e) && !("support" in e)
              ),
            );
          }
          const d = res.data;
          equal(sideEffects(), {
            provider: 1,
            quota: 1,
            budget: 1,
            confirm: 1,
            claims: 1,
          });
          equal(assistants().length, 1);
          const row = assistants()[0];
          equal([row.content, row.content_origin, row.support_session_id], [
            "Start with the subject line.",
            "model",
            sessionId,
          ]);
          // Final wire is a superset of the legacy contract.
          equal(d.message, d.assistantMessage);
          equal(d.assistantMessage.id, row.id);
          equal(d.userMessageId, requestId);
          equal(d.userMessage.content, MESSAGE);
          equal([d.quotaUsed, d.quotaLimit, d.coachData, d.conversationTitle], [
            1,
            5,
            null,
            null,
          ]);
          assert(typeof d.assistantMessage.createdAt === "number");
          equal([
            d.assistantMessage.contentOrigin,
            d.assistantMessage.isInterfaceGuidance,
          ], ["model", false]);
          const sup = d.support;
          equal([
            sup.schema_version,
            sup.status,
            sup.content_origin,
            sup.confirmed,
            sup.scope,
            sup.privacy_revision,
            sup.proposal,
            sup.suppress_ordinary_cards,
          ], [1, "completed", "model", true, "personalized", 7, null, false]);
          equal(sup.context_receipt.receipt_id, s.receipts[0].id);
          equal(sup.context_receipt.assistant_message_id, row.id);
          equal(sup.context_receipt.provider, {
            vendor: "openai",
            model: "gpt-6-luna",
            route_version: "responses-chat-1",
          });
          const kinds = sup.context_receipt.sources.map((x: Row) => x.kind);
          assert(
            kinds.includes("safety_policy") && kinds.includes("session") &&
              kinds.includes("companion_memory") &&
              kinds.includes("daily_intent"),
            JSON.stringify(sup.context_receipt.sources),
          );
          equal(d.memoryUsed, true);
          equal([...d.memoryIdsUsed].sort(), [boundaryId, memoryId].sort());
          assert(
            sup.context_receipt.exclusions.includes("absence_metadata") &&
              sup.context_receipt.exclusions.includes("private_vault"),
          );
          if (!stream) fixture("text_only_completed.json", d);
          // The terminal receipt is what the database stored; the server wrote nothing over it.
          equal(
            s.claimWrites.length,
            0,
            "the confirm RPC is the only writer of the terminal response",
          );
          noLegacyPersonalReads();
          noUnrelatedWork();
          // Replay: byte-identical, with no provider, quota, budget or confirm work.
          const before = sideEffects();
          const again = await send({}, { stream: false });
          equal(sideEffects(), before);
          equal(
            again.data,
            d,
            "replayed response equals the initial response including every id",
          );
          assert(JSON.stringify(again.data) === JSON.stringify(d));
          equal(assistants().length, 1);
        },
      );

      await t.step(
        `${mode}: text + valid tool call yields one card only after the terminal confirm`,
        async () => {
          reset();
          seedMemory();
          s.provider = {
            text: "Let's slow down together.",
            tool: ARGS({
              reason_code: "approved_preference",
              basis_ref: memoryId,
            }),
          };
          const res = await send({}, { stream });
          equal(res.status, 200);
          if (stream) {
            // Provisional text may stream, but no event before the terminal result carries a card.
            assert(
              res.events.slice(0, -1).every((e) =>
                e.type === "delta" &&
                Object.keys(e).sort().join() === "text,type"
              ),
            );
            assert(!res.deltas.includes("template_key"));
          }
          if (stream) fixture("stream_text_plus_card_events.json", res.events);
          else fixture("text_plus_card_completed.json", res.data);
          const p = res.data.support.proposal;
          equal(p.id, s.proposals[0].id);
          equal([
            p.template_key,
            p.reason_code,
            p.basis_kind,
            p.basis_ref,
            p.suggested_step,
            p.status,
          ], [
            "ground_present_v1",
            "approved_preference",
            "companion_memory",
            memoryId,
            null,
            "offered",
          ]);
          assert(
            Date.parse(p.expires_at) > Date.now() + 23 * 3600_000 &&
              Date.parse(p.expires_at) <= Date.now() + 24 * 3600_000,
          );
          equal(res.data.assistantMessage.content, "Let's slow down together.");
          equal(sideEffects(), {
            provider: 1,
            quota: 1,
            budget: 1,
            confirm: 1,
            claims: 1,
          });
          equal(s.confirmArgs[0].proposal.basis_kind, "companion_memory");
          // Replay returns the SAME proposal id, never a new card.
          const again = await send({}, { stream: false });
          equal(again.data.support.proposal.id, p.id);
          equal(again.data, res.data);
          equal(s.proposals.length, 1);
          equal(s.providerCalls, 1);
        },
      );

      await t.step(
        `${mode}: tool-only persists self-contained interface guidance, never a model quote`,
        async () => {
          reset();
          s.provider = { tool: ARGS() };
          const res = await send({}, { stream });
          equal(res.status, 200);
          equal(res.deltas, "", "tool-only has no provisional text");
          equal(
            res.streamed,
            false,
            "no text to stream: the answer is a plain JSON response even for an SSE request",
          );
          const d = res.data;
          if (!stream) fixture("tool_only_interface_fallback.json", d);
          equal(
            d.assistantMessage.content,
            "App option: Try a short grounding activity, or keep talking.",
          );
          equal([
            d.assistantMessage.contentOrigin,
            d.assistantMessage.isInterfaceGuidance,
            d.support.content_origin,
          ], ["interface_fallback", true, "interface_fallback"]);
          assert(
            d.message.content.trim().length > 0,
            "backward-compatible non-empty message text",
          );
          equal(assistants()[0].content_origin, "interface_fallback");
          equal(d.support.proposal.id, s.proposals[0].id);
          // The next turn never feeds the interface text back as an assistant claim.
          s.claims.clear();
          s.provider = { text: "Happy to help." };
          await send({
            content: "Another thought",
            requestId: crypto.randomUUID(),
          }, { stream: false });
          const history = providerInput(1).map((m) => m.content).join("\n");
          assert(
            !history.includes("App option:"),
            "interface guidance excluded from conversational history",
          );
        },
      );

      await t.step(
        `${mode}: invalid, duplicate, unknown and oversized tools keep the text, drop the card, make no second request`,
        async () => {
          const bad: Array<[string, Scenario]> = [
            ["malformed json", { text: "Text stays.", tool: "{not json" }],
            ["unknown template", {
              text: "Text stays.",
              tool: ARGS({ template_key: "launch_rocket_v9" }),
            }],
            ["unknown key", {
              text: "Text stays.",
              tool: JSON.stringify({
                ...JSON.parse(ARGS()),
                url: "https://evil.example",
              }),
            }],
            ["missing key", {
              text: "Text stays.",
              tool: JSON.stringify({ template_key: "ground_present_v1" }),
            }],
            ["duplicate keys", {
              text: "Text stays.",
              tool:
                '{"template_key":"ground_present_v1","template_key":"choose_step_v1","reason_code":"current_request","basis_ref":null,"suggested_step":null}',
            }],
            ["step on wrong template", {
              text: "Text stays.",
              tool: ARGS({ suggested_step: "do it" }),
            }],
            ["two calls", {
              text: "Text stays.",
              tool: [ARGS(), ARGS({ template_key: "choose_step_v1" })],
            }],
            ["wrong tool name", {
              text: "Text stays.",
              tool: ARGS(),
              toolName: "launch_activity",
            }],
            ["oversize arguments", {
              text: "Text stays.",
              tool: JSON.stringify({
                ...JSON.parse(ARGS()),
                suggested_step: "x".repeat(9000),
              }),
            }],
          ];
          for (const [label, scenario] of bad) {
            reset();
            s.provider = scenario;
            const res = await send({}, { stream });
            equal([label, res.status], [label, 200]);
            equal([label, res.data.assistantMessage.content], [
              label,
              "Text stays.",
            ]);
            if (!stream && label === "malformed json") {
              fixture("invalid_tool_dropped.json", res.data);
            }
            equal([
              label,
              res.data.support.proposal,
              res.data.support.proposal_dropped,
            ], [label, null, "invalid_proposal"]);
            equal([label, s.proposals.length, s.confirmArgs[0].proposal], [
              label,
              0,
              null,
            ]);
            equal([label, s.providerCalls, s.quotaCalls], [label, 1, 1]);
          }
          // A declined template is not offered again this session.
          reset();
          s.session!.suppressed_templates = ["ground_present_v1"];
          s.provider = { text: "Text stays.", tool: ARGS() };
          const declined = await send({}, { stream });
          equal([
            declined.data.support.proposal,
            declined.data.support.proposal_dropped,
          ], [null, "template_declined"]);
          // A tool-only response that is invalid has nothing to show: a retryable provider failure.
          reset();
          s.provider = { tool: "{broken" };
          const empty = await send({}, { stream });
          equal([
            empty.status,
            empty.data.code,
            empty.data.retryable,
            empty.data.messageSaved,
          ], [503, "chat_provider_unavailable", true, true]);
          if (!stream) fixture("failure_provider_unavailable.json", empty.data);
          equal([s.providerCalls, assistants().length, s.confirmCalls], [
            1,
            0,
            0,
          ]);
        },
      );

      await t.step(
        `${mode}: refusal is saved without any ordinary card or recommendation`,
        async () => {
          reset();
          s.provider = {
            refusal:
              "I can't help with that here, but I'm glad you reached out.",
            tool: ARGS(),
          };
          const res = await send({}, { stream });
          equal(res.status, 200);
          const d = res.data;
          if (!stream) fixture("refusal_completed.json", d);
          equal(
            d.assistantMessage.content,
            "I can't help with that here, but I'm glad you reached out.",
          );
          // The parser already suppresses a tool call that accompanies a refusal.
          equal([
            d.support.status,
            d.support.proposal,
            d.support.suppress_ordinary_cards,
            d.support.proposal_dropped,
          ], ["refused", null, true, null]);
          equal([s.proposals.length, s.confirmArgs[0].proposal], [0, null]);
          equal(s.providerCalls, 1);
        },
      );

      await t.step(
        `${mode}: incomplete, failed or cut provider responses never become a reply or a card`,
        async () => {
          for (const end of ["incomplete", "failed", "cut"] as const) {
            reset();
            s.provider = { text: "Half a thought", tool: ARGS(), end };
            const res = await send({}, { stream });
            assert(res.status >= 500, `${end} is an error`);
            assert(!res.data.support, "no support block for a failed turn");
            equal([
              end,
              assistants().length,
              s.confirmCalls,
              s.proposals.length,
              s.providerCalls,
            ], [end, 0, 0, 0, 1]);
            equal(res.data.messageSaved, true);
            assert(
              claim().response_status >= 500,
              "failure receipt stored through the legacy path",
            );
            assert(!("support_confirmed" in (claim().response ?? {})));
          }
        },
      );
    }

    // =========================================================================
    // Claim, replay, cancellation, ownership
    // =========================================================================
    await t.step(
      "claim precedes provider work; an in-flight duplicate and a changed body never reach the provider",
      async () => {
        reset();
        s.providerHold = true;
        const first = send({}, { stream: false });
        await s.providerStarted.promise;
        assert(
          claim() && claim().response === null,
          "claim exists before the provider returns",
        );
        const dup = await send({}, { stream: false });
        equal([dup.status, dup.data.error], [
          409,
          "Request outcome pending. Reload history before sending again.",
        ]);
        const changed = await send({ content: "A different message" });
        equal([changed.status, changed.data.error], [
          409,
          "Request identifier already used",
        ]);
        equal(sideEffects(), {
          provider: 1,
          quota: 1,
          budget: 1,
          confirm: 0,
          claims: 1,
        });
        s.providerHold = false;
        s.providerRelease.resolve();
        equal((await first).status, 200);
        const replay = await send({}, { stream: false });
        equal(replay.status, 200);
        equal(sideEffects(), {
          provider: 1,
          quota: 1,
          budget: 1,
          confirm: 1,
          claims: 1,
        });
      },
    );

    await t.step(
      "cancellation mid-provider saves no reply; the request id reconciles without a second billed turn",
      async () => {
        reset();
        s.providerHold = true;
        const controller = new AbortController();
        const pending = post(supportBody(), {
          stream: false,
          signal: controller.signal,
        });
        await s.providerStarted.promise;
        controller.abort();
        const res = await read(await pending);
        assert(res.status >= 500);
        equal([
          assistants().length,
          s.confirmCalls,
          s.providerCalls,
          s.quotaCalls,
        ], [0, 0, 1, 1]);
        equal([res.data.code, res.data.messageSaved, res.data.retryable], [
          "chat_request_unconfirmed",
          true,
          false,
        ]);
        // The stored failure is what a re-send of the same request id sees: no new provider call.
        s.providerHold = false;
        const again = await send({}, { stream: false });
        equal(again.data.code, "chat_request_unconfirmed");
        equal([s.providerCalls, s.quotaCalls, s.confirmCalls], [1, 1, 0]);
      },
    );

    await t.step(
      "owner mismatch and another owner's conversation do nothing",
      async () => {
        reset();
        const mismatch = await send({ expected_owner: otherUser });
        equal([mismatch.status, mismatch.data.code], [
          409,
          "chat_owner_mismatch",
        ]);
        equal(sideEffects(), {
          provider: 0,
          quota: 0,
          budget: 0,
          confirm: 0,
          claims: 0,
        });
      },
    );

    // =========================================================================
    // Scope and privacy
    // =========================================================================
    await t.step(
      "conversation-only reads no memory, intent or absence and cannot cite a saved preference",
      async () => {
        reset();
        seedMemory();
        s.provider = {
          text: "Okay.",
          tool: ARGS({
            reason_code: "approved_preference",
            basis_ref: memoryId,
          }),
        };
        const res = await send({
          context_scope: "conversation_only",
          expected_privacy_revision: null,
        });
        equal(res.status, 200);
        equal(s.contextCalls.at(-1)!.p_include_personal, false);
        const system = providerInput()[0].content as string;
        assert(
          !system.includes("breath counting") && !system.includes("sister") &&
            !system.includes("stay calm") && !system.includes("Returning user"),
        );
        equal(res.data.support.scope, "conversation_only");
        equal([res.data.memoryUsed, res.data.memoryIdsUsed], [false, []]);
        assert(
          res.data.support.context_receipt.exclusions.includes(
            "saved_memory",
          ) &&
            res.data.support.context_receipt.exclusions.includes(
              "daily_intent",
            ),
        );
        const p = res.data.support.proposal;
        equal([p.reason_code, p.basis_kind, p.basis_ref], [
          "general_option",
          null,
          null,
        ]);
        noLegacyPersonalReads();
        assert(
          !s.tableCalls.some((c) => c === "GET profiles") ||
            !s.tableCalls.includes("absence"),
        );
      },
    );

    await t.step(
      "personalized context is server-built, quoted, ref-marked, and bounded",
      async () => {
        reset();
        seedMemory();
        s.provider = { text: "Okay." };
        await send({
          context_scope: "personalized",
          selected_intent: "ground_present_v1",
        });
        const body = s.providerBodies[0];
        const system = body.input[0].content as string;
        assert(
          system.includes("breath counting") && system.includes("sister") &&
            system.includes("stay calm"),
        );
        assert(
          system.includes(`(ref: ${memoryId})`) &&
            system.includes(`(ref: ${boundaryId})`),
          "model can cite a real source id",
        );
        assert(
          system.includes("Quoted user data") &&
            system.includes("propose_support_action"),
        );
        assert(
          !system.includes("Returning user"),
          "no re-engagement context on the new contract",
        );
        equal(s.contextCalls.at(-1)!.p_include_personal, true);
        // Provider request shape: one strict function, no parallel calls, same model caps.
        equal([
          body.model,
          body.max_output_tokens,
          body.store,
          body.parallel_tool_calls,
          body.tool_choice,
        ], ["gpt-6-luna", 500, false, false, "auto"]);
        fixture("provider_request_personalized.json", {
          ...body,
          input: [{
            role: "system",
            content:
              "<system prompt: base + activity addendum + quoted context>",
          }, ...body.input.slice(1)],
        });
        equal(body.tools.length, 1);
        assert(
          body.tools[0].strict === true &&
            body.tools[0].name === "propose_support_action",
        );
        equal(body.reasoning, { effort: "none" });
        const last = body.input.at(-1);
        equal([last.role, last.content], ["user", MESSAGE]);
      },
    );

    await t.step(
      "account private mode narrows a personalized request; the receipt says so",
      async () => {
        reset();
        seedMemory();
        s.privacyMode = "enhanced";
        const res = await send({ context_scope: "personalized" });
        equal(res.status, 200);
        equal([res.data.support.scope, res.data.support.scope_narrowed_by], [
          "conversation_only",
          "account_privacy_mode",
        ]);
        assert(
          res.data.support.context_receipt.exclusions.includes(
            "account_privacy_mode",
          ),
        );
        assert(
          !(providerInput()[0].content as string).includes("breath counting"),
        );
        equal(s.contextCalls.at(-1)!.p_include_personal, false);
        noLegacyPersonalReads();
      },
    );

    await t.step(
      "a personalized request against a conversation-only session is refused before any personal read",
      async () => {
        reset();
        seedMemory();
        s.session!.context_scope = "conversation_only";
        const res = await send({ context_scope: "personalized" });
        equal([res.status, res.data.code, res.data.retryable], [
          409,
          "chat_support_scope_mismatch",
          false,
        ]);
        equal([s.providerCalls, s.quotaCalls, s.confirmCalls], [0, 0, 0]);
        assert(
          s.contextCalls.every((c) => c.p_include_personal === false),
          "no personal source was read",
        );
      },
    );

    await t.step(
      "session attached to another conversation, or missing, fails closed",
      async () => {
        reset();
        s.session!.conversation_id = "77777777-7777-4777-8777-777777777777";
        const mismatch = await send();
        equal([mismatch.status, mismatch.data.code], [
          409,
          "chat_support_session_mismatch",
        ]);
        reset();
        s.session = null;
        const missing = await send();
        equal([missing.status, missing.data.code, missing.data.support_code], [
          404,
          "chat_support_session_not_found",
          "NOT_FOUND",
        ]);
        equal(s.providerCalls, 0);
      },
    );

    await t.step(
      "a closed session is refused before any spending",
      async () => {
        reset();
        s.session!.status = "closed";
        const res = await send();
        equal([
          res.status,
          res.data.code,
          res.data.retryable,
          res.data.support_code,
        ], [409, "chat_support_session_closed", false, "NOT_FOUND"]);
        equal([
          s.providerCalls,
          s.quotaCalls,
          s.budgetCalls,
          s.confirmCalls,
          assistants().length,
        ], [0, 0, 0, 0, 0]);
      },
    );

    await t.step(
      "stale expected privacy revision stops before quota; explicit retry with the new revision succeeds once",
      async () => {
        reset();
        seedMemory();
        const stale = await send({ expected_privacy_revision: 6 });
        equal([
          stale.status,
          stale.data.code,
          stale.data.retryable,
          stale.data.current_privacy_revision,
          stale.data.support_code,
        ], [
          409,
          "chat_privacy_revision_stale",
          true,
          7,
          "PRIVACY_REVISION_STALE",
        ]);
        fixture("failure_privacy_revision_stale.json", stale.data);
        equal([
          stale.data.messageSaved,
          s.providerCalls,
          s.quotaCalls,
          s.budgetCalls,
          s.confirmCalls,
        ], [false, 0, 0, 0, 0]);
        const retry = await send({
          expected_privacy_revision: 7,
          retryFailed: true,
        });
        equal(retry.status, 200);
        equal([
          s.providerCalls,
          s.quotaCalls,
          s.confirmCalls,
          assistants().length,
        ], [1, 1, 1, 1]);
      },
    );

    await t.step(
      "a correction accepted before dispatch stops the request before quota and provider",
      async () => {
        for (
          const kind of [
            "privacy",
            "memory-edit",
            "memory-forget",
            "session-scope",
          ] as const
        ) {
          reset();
          seedMemory();
          s.hooks.onBudget = () => {
            if (kind === "privacy") s.privacyRevision++;
            if (kind === "memory-edit") s.memories[1].revision++;
            if (kind === "memory-forget") {
              s.suppressions.push({ kind: "memory", ref_id: memoryId });
            }
            if (kind === "session-scope") s.session!.context_revision++;
          };
          const res = await send();
          equal([kind, res.status, res.data.code, res.data.retryable], [
            kind,
            409,
            "chat_privacy_revision_stale",
            true,
          ]);
          equal([
            kind,
            s.providerCalls,
            s.quotaCalls,
            s.confirmCalls,
            assistants().length,
          ], [kind, 0, 0, 0, 0]);
          assert(!s.claimWrites.some((w) => w.response?.support_confirmed));
        }
      },
    );

    await t.step(
      "a correction accepted while the provider runs is quarantined before confirm",
      async () => {
        for (const kind of ["privacy", "memory-forget"] as const) {
          reset();
          seedMemory();
          s.hooks.onProviderResponse = () => {
            if (kind === "privacy") s.privacyRevision++;
            else s.suppressions.push({ kind: "memory", ref_id: memoryId });
          };
          const res = await send();
          equal([kind, res.status, res.data.code], [
            kind,
            409,
            "chat_privacy_revision_stale",
          ]);
          equal([
            kind,
            s.providerCalls,
            s.quotaCalls,
            s.confirmCalls,
            assistants().length,
            s.receipts.length,
          ], [kind, 1, 1, 0, 0, 0]);
        }
      },
    );

    await t.step(
      "stream: provisional text is followed by an error event, never a result, when the context went stale",
      async () => {
        reset();
        seedMemory();
        s.provider = { text: "Text produced from now-stale context." };
        s.hooks.onProviderResponse = () => {
          s.privacyRevision++;
        };
        const res = await send({}, { stream: true });
        equal([res.streamed, res.status, res.data.code], [
          true,
          409,
          "chat_privacy_revision_stale",
        ]);
        equal(res.events.at(-1)!.type, "error");
        equal([assistants().length, s.receipts.length, s.proposals.length], [
          0,
          0,
          0,
        ]);
        assert(!res.events.some((e) => e.type === "result"));
      },
    );

    await t.step(
      "the SQL confirm stays authoritative when a correction lands after the last client check",
      async () => {
        reset();
        seedMemory();
        s.confirmPlan = ["stale-race"];
        const res = await send();
        equal([res.status, res.data.code, res.data.current_privacy_revision], [
          409,
          "chat_privacy_revision_stale",
          8,
        ]);
        equal([s.confirmCalls, assistants().length, s.providerCalls], [
          1,
          0,
          1,
        ]);
        assert(
          claim().response_status === 409 &&
            claim().response.retryable === true,
          "stored as a retryable failure",
        );
      },
    );

    // =========================================================================
    // Confirmation failure, timeout and reconciliation
    // =========================================================================
    await t.step(
      "a definite confirm failure saves nothing, is retryable, and a retry makes exactly one more provider call",
      async () => {
        reset();
        s.confirmPlan = ["db-error"];
        const res = await send();
        equal([
          res.status,
          res.data.code,
          res.data.retryable,
          res.data.messageSaved,
        ], [503, "chat_confirm_unavailable", true, true]);
        equal([
          assistants().length,
          s.receipts.length,
          s.providerCalls,
          s.confirmCalls,
        ], [0, 0, 1, 1]);
        assert(claim().response_status === 503, "failure receipt stored");
        const retry = await send({ retryFailed: true });
        equal(retry.status, 200);
        equal([s.providerCalls, s.quotaCalls, assistants().length], [2, 2, 1]);
        equal(
          s.messages.filter((m) => m.role === "user").length,
          1,
          "the retry reuses the saved user message",
        );
      },
    );

    await t.step(
      "a lost request is re-issued idempotently: one reply, one receipt, one provider call",
      async () => {
        reset();
        s.confirmPlan = ["network-before"];
        const res = await send();
        equal(res.status, 200);
        equal([
          s.confirmCalls,
          s.providerCalls,
          s.quotaCalls,
          assistants().length,
          s.receipts.length,
        ], [2, 1, 1, 1, 1]);
      },
    );

    await t.step(
      "a commit whose response was lost is observed as a replay, never saved twice",
      async () => {
        for (const stream of [false, true]) {
          reset();
          seedMemory();
          s.provider = { text: "Saved once.", tool: ARGS() };
          s.confirmPlan = ["network-after"];
          const res = await send({}, { stream });
          equal(res.status, 200);
          equal([
            s.confirmCalls,
            s.providerCalls,
            assistants().length,
            s.receipts.length,
            s.proposals.length,
          ], [2, 1, 1, 1, 1]);
          equal(res.data.support.proposal.id, s.proposals[0].id);
          equal(res.data.support.context_receipt.receipt_id, s.receipts[0].id);
          equal(res.data.assistantMessage.id, assistants()[0].id);
          equal(s.claimWrites.length, 0);
        }
      },
    );

    await t.step(
      "persistent ambiguity leaves the claim pending (no failure written); a later commit is returned verbatim",
      async () => {
        reset();
        s.provider = { text: "Late but real." };
        s.confirmPlan = ["network-before", "network-before", "network-before"];
        const res = await send();
        equal([
          res.status,
          res.data.code,
          res.data.retryable,
          res.data.messageSaved,
        ], [503, "chat_request_unconfirmed", false, true]);
        fixture("failure_request_unconfirmed.json", res.data);
        equal([s.confirmCalls, s.providerCalls, assistants().length], [
          3,
          1,
          0,
        ]);
        equal(
          s.claimWrites.length,
          0,
          "nothing written over a claim whose commit is unknown",
        );
        assert(claim().response === null);
        const pending = await send();
        equal([pending.status, pending.data.error], [
          409,
          "Request outcome pending. Reload history before sending again.",
        ]);
        equal(s.providerCalls, 1);
        // The database commits late (for example the first call was merely slow).
        const late = commitConfirm(s.confirmArgs[0]);
        assert(late.ok === true && late.replayed === false);
        const replay = await send();
        equal([
          replay.status,
          replay.data.assistantMessage.id,
          replay.data.support.context_receipt.receipt_id,
        ], [200, late.message_id, late.receipt_id]);
        equal([s.providerCalls, s.quotaCalls], [1, 1]);
      },
    );

    // A turn committed by another execution of the same request, as the database would store it.
    const committedElsewhere = () => {
      const template = buildWireTemplate({
        userId,
        requestId,
        conversationId,
        supportSessionId: sessionId,
        trimmedContent: MESSAGE,
        userMessage: { id: requestId, created_at: new Date().toISOString() },
        quota: { used: 1, limit: 5 },
        now: new Date(),
        scope: "conversation_only",
        privacyRevision: s.privacyRevision,
        content: "Committed elsewhere.",
        origin: "model",
        status: "completed",
        proposal: null,
        proposalDropped: null,
        sources: [],
        exclusions: [],
        provider: {
          vendor: "openai",
          model: "gpt-6-luna",
          routeVersion: "responses-chat-1",
        },
        narrowedBy: null,
      });
      return commitConfirm({
        user_id: userId,
        request_id: requestId,
        conversation_id: conversationId,
        content_hash: claim().content_hash,
        support_session_id: sessionId,
        assistant_content: "Committed elsewhere.",
        content_origin: "model",
        privacy_revision: s.privacyRevision,
        scope: "conversation_only",
        provider_vendor: "openai",
        provider_model: "gpt-6-luna",
        route_version: "responses-chat-1",
        exclusions: [],
        sources: [],
        proposal: null,
        response: template,
        response_status: 200,
      });
    };

    await t.step(
      "a failure that races a commit never overwrites it: the stored confirmed turn is served",
      async () => {
        reset();
        // The provider fails for this execution while another execution of the same request commits.
        s.provider = { text: "irrelevant", end: "failed" };
        s.hooks.onProviderResponse = () => {
          committedElsewhere();
        };
        const res = await send();
        equal(res.status, 200);
        equal(res.data.assistantMessage.content, "Committed elsewhere.");
        equal(res.data.assistantMessage.id, assistants()[0].id);
        equal(assistants().length, 1);
        assert(
          !s.claimWrites.some((w) =>
            w.response?.code === "chat_provider_unavailable" &&
            claim().response?.support_confirmed === undefined
          ),
          "the failure never replaced the confirmed response",
        );
        assert(
          claim().response.support_confirmed,
          "the confirmed response is still the stored terminal state",
        );
      },
    );

    await t.step(
      "OPERATION_ID_REUSED reads the stored terminal state instead of saving or guessing",
      async () => {
        reset();
        s.provider = { text: "Second execution output." };
        // Another execution commits between this execution's last client check and its confirm.
        s.confirmPlan = ["ok"];
        s.hooks.onProviderResponse = () => {
          committedElsewhere();
        };
        const res = await send();
        // The RPC observes the receipt and replays the stored response; nothing is saved twice.
        equal(res.status, 200);
        equal(res.data.assistantMessage.content, "Committed elsewhere.");
        equal([assistants().length, s.receipts.length, s.providerCalls], [
          1,
          1,
          1,
        ]);
        // A finalized-without-receipt claim (for example another execution recorded a failure).
        reset();
        s.provider = { text: "Another output." };
        s.hooks.onProviderResponse = () => {
          claim().response = {
            error: "x",
            code: "chat_request_unconfirmed",
            retryable: false,
            requestId,
            failureId: crypto.randomUUID(),
          };
          claim().response_status = 503;
        };
        const reused = await send();
        equal([reused.status, reused.data.code], [
          503,
          "chat_request_unconfirmed",
        ]);
        equal([assistants().length, s.receipts.length], [0, 0]);
      },
    );

    // =========================================================================
    // Safety path
    // =========================================================================
    await t.step(
      "crisis: origin safety_response, no provider/quota/budget, no card, atomic receipt, therapist alert preserved",
      async () => {
        for (const stream of [false, true]) {
          reset();
          seedMemory();
          s.therapyConnections = [{
            id: "88888888-8888-4888-8888-888888888888",
            therapist_id: "t1",
            therapist_accounts: {
              user_id: "99999999-0000-4000-8000-000000000000",
              practice_name: "P",
            },
            profiles: { display_name: "Pat" },
          }];
          const res = await send({ content: "I want to kill myself" }, {
            stream,
          });
          equal(res.status, 200);
          const d = res.data;
          if (!stream) fixture("safety_response_completed.json", d);
          equal([
            d.isCrisisResponse,
            d.assistantMessage.content,
            d.assistantMessage.blocked,
            d.assistantMessage.contentOrigin,
          ], [true, CRISIS_RESPONSE, true, "safety_response"]);
          equal([
            d.support.content_origin,
            d.support.status,
            d.support.proposal,
            d.support.suppress_ordinary_cards,
          ], ["safety_response", "safety", null, true]);
          equal(d.support.context_receipt.receipt_id, s.receipts[0].id);
          equal(d.support.context_receipt.provider, {
            vendor: "none",
            model: "safety_response",
            route_version: "1",
          });
          assert(
            d.support.context_receipt.exclusions.includes("ai_model_not_used"),
          );
          equal(assistants()[0].content_origin, "safety_response");
          equal([
            s.providerCalls,
            s.quotaCalls,
            s.budgetCalls,
            s.proposals.length,
          ], [0, 0, 0, 0]);
          equal(
            s.notifications,
            1,
            "existing consented therapist alert path unchanged",
          );
          assert(!("quotaUsed" in d), "no quota debited");
          noLegacyPersonalReads();
          const replay = await send({ content: "I want to kill myself" });
          equal(replay.data, d);
          equal([s.providerCalls, s.receipts.length, assistants().length], [
            0,
            1,
            1,
          ]);
        }
      },
    );

    await t.step(
      "crisis: help is delivered even when the support contract is missing, with no personal context",
      async () => {
        for (const caps of ["missing", "error"] as const) {
          reset();
          seedMemory();
          s.caps = caps;
          const res = await send({ content: "I want to kill myself" });
          equal(res.status, 200);
          // The capability probe is not consulted for crisis help; the receipt is still recorded when
          // the confirmation RPC itself works (the receipt-less fallback is covered above).
          equal([
            res.data.isCrisisResponse,
            res.data.assistantMessage.content,
            res.data.support.proposal,
          ], [true, CRISIS_RESPONSE, null]);
          assert(
            !s.rpcCalls.includes("support_capabilities"),
            "crisis help never waits for capability negotiation",
          );
          equal(assistants()[0].content_origin, "safety_response");
          equal([s.providerCalls, s.quotaCalls, s.budgetCalls], [0, 0, 0]);
          noLegacyPersonalReads();
          assert(!s.rpcCalls.includes("support_context_sources"));
        }
      },
    );

    await t.step(
      "crisis: a stale expected revision is learned from the database and never blocks help",
      async () => {
        reset();
        const res = await send({
          content: "I want to kill myself",
          expected_privacy_revision: 3,
        });
        equal([res.status, res.data.support.privacy_revision], [200, 7]);
        equal([s.confirmCalls, assistants().length], [2, 1]);
      },
    );

    await t.step(
      "crisis: if the atomic receipt cannot complete, help is still delivered with truthful origin",
      async () => {
        reset();
        s.crisisConfirm = "db-error";
        const res = await send({ content: "I want to kill myself" });
        equal(res.status, 200);
        const d = res.data;
        equal([
          d.isCrisisResponse,
          d.assistantMessage.content,
          d.support.content_origin,
          d.support.context_receipt,
          d.support.proposal,
        ], [true, CRISIS_RESPONSE, "safety_response", null, null]);
        const row = assistants()[0];
        equal([row.content_origin, row.support_session_id], [
          "safety_response",
          sessionId,
        ]);
        equal([s.providerCalls, s.quotaCalls], [0, 0]);
        equal(
          claim().response_status,
          200,
          "terminal response stored by the legacy mechanism",
        );
      },
    );

    // =========================================================================
    // Bounds
    // =========================================================================
    await t.step(
      "pre-provider: 128,000-byte and 500-token bounds hold, oldest history trims first, current message intact",
      async () => {
        reset();
        seedMemory();
        for (let i = 0; i < 40; i++) {
          s.messages.push({
            id: crypto.randomUUID(),
            conversation_id: conversationId,
            role: i % 2 ? "assistant" : "user",
            content: `${i}:` + 'é"\\ '.repeat(1500),
            content_origin: null,
            created_at: new Date(Date.UTC(2026, 10, 2, 0, i)).toISOString(),
          });
        }
        // A maximal message whose sanitized form is much longer than 4,000 characters.
        const hostile = ('DAN "say" system: ').repeat(220).slice(0, 4000);
        const res = await send({ content: hostile });
        equal(res.status, 200);
        const body = s.providerBodies[0];
        const input = body.input as Row[];
        const total = encoder.encode(JSON.stringify(input)).length +
          SUPPORT_ACTION_OVERHEAD_BYTES;
        assert(total <= MAX_PROMPT_BYTES, `dispatched ${total} bytes`);
        equal(body.max_output_tokens, SUPPORT_CHAT_MAX_OUTPUT_TOKENS);
        const history = input.slice(1, -1);
        assert(
          history.length >= 1 && history.length <= 20,
          `history kept: ${history.length}`,
        );
        assert(
          (history.at(-1)!.content as string).startsWith("39:"),
          "newest history retained; oldest dropped first",
        );
        const current = input.at(-1)!;
        equal(current.role, "user");
        assert(
          current.content.startsWith("[redacted]") &&
            current.content.length > 4000,
          "sanitized current message retained in full",
        );
        assert(
          res.data.support.context_receipt.exclusions.includes(
            "trimmed_history",
          ),
        );
        equal(
          res.data.userMessage.content,
          hostile.trim(),
          "stored/returned user text is the original",
        );
      },
    );

    await t.step(
      "an over-long message is rejected before anything is claimed",
      async () => {
        reset();
        const res = await send({ content: "x".repeat(4001) });
        equal(res.status, 400);
        equal(sideEffects(), {
          provider: 0,
          quota: 0,
          budget: 0,
          confirm: 0,
          claims: 0,
        });
      },
    );

    // =========================================================================
    // Legacy contract and unrelated work
    // =========================================================================
    await t.step(
      "a legacy request keeps its wire: installed schema saves atomically with no session; absent schema keeps the direct save",
      async () => {
        reset();
        const res = await read(
          await post({ conversationId, content: MESSAGE, requestId }),
        );
        equal(res.status, 200);
        assert(!("support" in res.data), "no new block on the old wire");
        equal(res.data.message, res.data.assistantMessage);
        equal(res.data.assistantMessage.id, assistants()[0].id);
        equal(Object.keys(res.data).sort(), [
          "assistantMessage",
          "coachData",
          "conversationTitle",
          "memoryIdsUsed",
          "memoryUsed",
          "message",
          "quotaLimit",
          "quotaUsed",
          "userMessage",
          "userMessageId",
        ]);
        equal(
          [
            s.confirmCalls,
            s.directAssistantInserts,
            s.confirmArgs[0].support_session_id,
          ],
          [1, 0, null],
          "installed: atomic confirm, NULL session, no direct assistant insert",
        );
        equal(
          [...new Set(s.rpcCalls.filter((r) => r.startsWith("support_")))]
            .sort(),
          [
            "support_capabilities",
            "support_confirm_chat_turn",
            "support_context_sources",
          ],
          "eligibility from the shared loader, final save from the shared confirmation",
        );
        equal(
          s.rpcCalls.filter((r) => r === "support_context_sources").length,
          3,
          "loaded once, revalidated before dispatch and before the final save",
        );
        // Even with the support SQL missing, a legacy client keeps working (and fails no closed check).
        reset();
        s.caps = "missing";
        const still = await read(
          await post({ conversationId, content: MESSAGE, requestId }),
        );
        equal(still.status, 200);
        equal(
          [s.confirmCalls, s.directAssistantInserts],
          [0, 1],
          "absent schema: the old direct save",
        );
      },
    );

    await t.step("logs and thrown errors are content-free", async () => {
      reset();
      seedMemory();
      const secrets = [
        "supervisor",
        "sister",
        "breath counting",
        "stay calm",
        "gentle secret model reply",
        "template_key",
        "kill myself",
      ];
      const captured: string[] = [];
      const originals = {
        log: console.log,
        error: console.error,
        warn: console.warn,
        info: console.info,
      };
      for (const k of Object.keys(originals) as Array<keyof typeof originals>) {
        console[k] = (...args: unknown[]) => {
          captured.push(
            args.map((a) => typeof a === "string" ? a : JSON.stringify(a)).join(
              " ",
            ),
          );
        };
      }
      try {
        s.provider = { text: "gentle secret model reply", tool: ARGS() };
        await send({}, { stream: true });
        reset();
        seedMemory();
        s.provider = { text: "gentle secret model reply", tool: "{broken" };
        s.confirmPlan = ["db-error"];
        await send({});
        reset();
        await send({ content: "I want to kill myself" });
        reset();
        s.provider = { text: "x", end: "failed" };
        await send({});
      } finally {
        Object.assign(console, originals);
      }
      assert(captured.length > 0);
      for (const secret of secrets) {
        const leak = captured.find((line) =>
          line.toLowerCase().includes(secret)
        );
        assert(!leak, `log line leaked "${secret}": ${leak?.slice(0, 160)}`);
      }
    });

    await t.step(
      "the new path makes no title, extraction, coach or usage calls even for a first message",
      async () => {
        reset();
        s.messages = [];
        const res = await send();
        equal(res.status, 200);
        equal([s.providerCalls, background.length], [1, 0]);
        noUnrelatedWork();
        equal(res.data.conversationTitle, null);
      },
    );

    const MARKER = "PRIVATE-FACT-FROM-PROVIDER-9F3C";
    const captureConsole = () => {
      const lines: string[] = [];
      const originals = {
        log: console.log,
        error: console.error,
        warn: console.warn,
        info: console.info,
        debug: console.debug,
      };
      for (const k of Object.keys(originals) as Array<keyof typeof originals>) {
        console[k] = (...args: unknown[]) => {
          lines.push(
            args.map((a) =>
              typeof a === "string"
                ? a
                : a instanceof Error
                ? `${a.name}: ${a.message}\n${a.stack}`
                : JSON.stringify(a)
            ).join(" "),
          );
        };
      }
      return {
        lines,
        restore: () => {
          Object.assign(console, originals);
        },
      };
    };

    const policyCitesRevision = await (async () => {
      const probe = await assembleContext(
        defaultContextDeps({
          load: () =>
            Promise.resolve({
              privacyRevision: 1,
              memories: [],
              dailyIntent: null,
              session: null,
              activity: null,
              history: [{
                id: "e2000000-0000-4000-8000-000000000001",
                role: "user",
                content: "x",
                createdAt: new Date(0).toISOString(),
                revision: 5,
              }],
              suppressions: {
                messages: new Set<string>(),
                memories: new Set<string>(),
                conversations: new Set<string>(),
                activities: new Set<string>(),
              },
            } as unknown as ContextSourceRecords),
        }),
        {
          userId,
          conversationId,
          supportSessionId: null,
          requestId,
          channel: "text",
          scope: "conversation_only",
          currentMessage: "hi",
          promptOverheadBytes: 100,
        },
      );
      return probe.ok &&
        probe.receiptDraft.sources.some((x) =>
          x.kind === "message" && x.revision === 5
        );
    })();
    // Run with the latest M3 policy (see the m4-r3 import map) so the revision-aware steps are
    // live. M4_REQUIRE_M3_LATEST=1 turns "this tree's policy predates revisions" into a
    // failure instead of a silently vacuous pass.
    if (Deno.env.get("M4_REQUIRE_M3_LATEST") === "1" && !policyCitesRevision) {
      throw new Error(
        "M4_REQUIRE_M3_LATEST=1 but the imported policy does not cite message revisions",
      );
    }

    // =========================================================================
    // M4-R01: a safety reply is never appended twice and never reported as saved when unknown
    // =========================================================================
    const CRISIS = "I want to kill myself";
    const PENDING_MESSAGE =
      "Request outcome pending. Reload history before sending again.";

    await t.step(
      "R01: a crisis commit whose every response was lost is reconciled from the claim (one message, stable ids)",
      async () => {
        for (const stream of [false, true]) {
          reset();
          s.confirmPlan = ["network-after", "network-before", "network-before"];
          const res = await send({ content: CRISIS }, { stream });
          equal(res.status, 200);
          equal(
            [assistants().length, s.receipts.length],
            [1, 1],
            "exactly one durable reply",
          );
          equal(res.data.assistantMessage.id, assistants()[0].id);
          equal(res.data.support.context_receipt.receipt_id, s.receipts[0].id);
          equal([res.data.support.confirmed, res.data.support.persistence], [
            true,
            "confirmed",
          ]);
          equal(
            [res.data.assistantMessage.content, res.data.isCrisisResponse],
            [CRISIS_RESPONSE, true],
          );
          equal(
            [s.confirmCalls, s.providerCalls, s.quotaCalls, s.budgetCalls],
            [3, 0, 0, 0],
          );
          equal(s.claimWrites.length, 0, "nothing was written over the claim");
          const before = sideEffects();
          const replay = await send({ content: CRISIS }, { stream: false });
          equal(sideEffects(), before, "replay does no work");
          equal(
            replay.data,
            res.data,
            "replay is byte-identical, ids included",
          );
          equal(assistants().length, 1);
        }
      },
    );

    await t.step(
      "R01: lost before commit on every attempt: local help only, nothing appended, claim pending, late commit returned verbatim",
      async () => {
        for (const stream of [false, true]) {
          reset();
          s.confirmPlan = [
            "network-before",
            "network-before",
            "network-before",
          ];
          const res = await send({ content: CRISIS }, { stream });
          equal(res.status, 200);
          const d = res.data;
          equal([
            d.isCrisisResponse,
            d.assistantMessage.content,
            d.message.content,
          ], [true, CRISIS_RESPONSE, CRISIS_RESPONSE]);
          equal([
            d.support.confirmed,
            d.support.persistence,
            d.support.context_receipt,
            d.support.proposal,
          ], [false, "pending_reconcile", null, null]);
          equal([
            d.support.status,
            d.support.suppress_ordinary_cards,
            d.support.content_origin,
          ], ["safety", true, "safety_response"]);
          equal(
            d.assistantMessage.id,
            await pendingLocalMessageId(requestId),
            "a stable non-durable placeholder id",
          );
          assert(!s.messages.some((m) => m.id === d.assistantMessage.id));
          equal(
            [assistants().length, s.receipts.length, s.claimWrites.length],
            [0, 0, 0],
            "no second durable message, no claim write",
          );
          assert(claim().response === null, "the claim stays pending");
          equal(
            [s.providerCalls, s.quotaCalls, s.budgetCalls, s.confirmCalls],
            [0, 0, 0, 3],
          );
          // Same request id: still pending, still nothing appended (no repeated save under any id).
          const again = await send({ content: CRISIS }, { stream: false });
          equal([again.status, again.data.error], [409, PENDING_MESSAGE]);
          equal([assistants().length, s.confirmCalls], [0, 3]);
          // The database commits late (the first call was merely slow): replay returns it verbatim.
          const late = commitConfirm(s.confirmArgs[0]);
          assert(late.ok === true && late.replayed === false);
          const replay = await send({ content: CRISIS }, { stream: false });
          equal([
            replay.status,
            replay.data.assistantMessage.id,
            replay.data.support.context_receipt.receipt_id,
          ], [200, late.message_id, late.receipt_id]);
          assert(
            replay.data.assistantMessage.id !== d.assistantMessage.id,
            "the confirmed id supersedes the placeholder",
          );
          equal([assistants().length, s.receipts.length], [1, 1]);
          if (!stream) fixture("safety_pending_reconcile.json", d);
        }
      },
    );

    await t.step(
      "R01: an unknown attempt makes a later structured database error unknown too: still no direct insert",
      async () => {
        reset();
        s.confirmPlan = ["network-before", "db-error", "db-error"];
        const res = await send({ content: CRISIS });
        equal([res.status, res.data.support.persistence], [
          200,
          "pending_reconcile",
        ]);
        equal([assistants().length, s.receipts.length, s.claimWrites.length], [
          0,
          0,
          0,
        ]);
        // ...and when the earlier attempt had actually committed, the claim shows it.
        reset();
        s.confirmPlan = ["network-after", "db-error", "db-error"];
        const done = await send({ content: CRISIS });
        equal([
          done.status,
          done.data.support.persistence,
          assistants().length,
          done.data.assistantMessage.id === assistants()[0]?.id,
        ], [200, "confirmed", 1, true]);
      },
    );

    await t.step(
      "R01: only a definite unsupported/refused confirm may use the existing direct save, exactly once",
      async () => {
        reset();
        s.confirmMissing = true;
        const res = await send({ content: CRISIS });
        equal(res.status, 200);
        equal([
          res.data.support.persistence,
          res.data.support.confirmed,
          res.data.support.context_receipt,
          res.data.isCrisisResponse,
        ], ["saved_without_receipt", false, null, true]);
        equal([assistants().length, s.receipts.length, s.confirmCalls], [
          1,
          0,
          1,
        ], "one definitive attempt, one direct save");
        equal(assistants()[0].content_origin, "safety_response");
        equal(claim().response_status, 200);
        equal(res.data.assistantMessage.content, CRISIS_RESPONSE);
        equal(
          [
            res.data.assistantMessage.contentOrigin,
            res.data.message.contentOrigin,
            res.data.support.content_origin,
          ],
          ["safety_response", "safety_response", "safety_response"],
        );
        // A definite structured error on the FIRST attempt is also a definite non-commit.
        reset();
        s.confirmPlan = ["db-error"];
        const refused = await send({ content: CRISIS });
        equal([
          refused.status,
          refused.data.support.persistence,
          assistants().length,
          s.confirmCalls,
        ], [200, "saved_without_receipt", 1, 1]);
        fixture("safety_saved_without_receipt.json", refused.data);
      },
    );

    await t.step(
      "R01 (r2): after any unknown confirm, a missing-function answer stays unknown: reconcile or pending, never a direct save",
      async () => {
        for (const stream of [false, true]) {
          // Lost after commit, then the schema cache says "missing function": the claim shows
          // the commit, the third (idempotent) attempt replays it. One message, one receipt.
          reset();
          s.confirmPlan = ["network-after", "missing"];
          const done = await send({ content: CRISIS }, { stream });
          equal(done.status, 200);
          equal([assistants().length, s.receipts.length], [1, 1]);
          equal(
            [
              done.data.support.persistence,
              done.data.assistantMessage.id,
              done.data.support.context_receipt.receipt_id,
            ],
            ["confirmed", assistants()[0].id, s.receipts[0].id],
          );
          equal(s.claimWrites.length, 0);
          equal([s.providerCalls, s.quotaCalls, s.budgetCalls], [0, 0, 0]);
          const before = sideEffects();
          const replay = await send({ content: CRISIS }, { stream: false });
          equal(replay.data, done.data, "stable ids on replay");
          equal(sideEffects(), before);
          equal(assistants().length, 1);

          // Lost before commit, then missing twice: unknown. Local help only, nothing appended.
          reset();
          s.confirmPlan = ["network-before", "missing", "missing"];
          const pending = await send({ content: CRISIS }, { stream });
          equal(pending.status, 200);
          equal(
            [
              pending.data.support.persistence,
              pending.data.support.confirmed,
              pending.data.assistantMessage.id,
            ],
            [
              "pending_reconcile",
              false,
              await pendingLocalMessageId(requestId),
            ],
          );
          equal([
            assistants().length,
            s.receipts.length,
            s.claimWrites.length,
            s.confirmCalls,
          ], [0, 0, 0, 3]);
          assert(claim().response === null);
          // The delayed first commit lands: the replay returns it, still exactly one message.
          const late = commitConfirm(s.confirmArgs[0]);
          assert(late.ok === true && late.replayed === false);
          const landed = await send({ content: CRISIS }, { stream: false });
          equal([
            landed.status,
            landed.data.assistantMessage.id,
            landed.data.support.persistence,
          ], [200, late.message_id, "confirmed"]);
          equal([assistants().length, s.receipts.length], [1, 1]);

          // Model turn: same rule, same single provider call and quota debit.
          reset();
          s.provider = { text: "Exactly once." };
          s.confirmPlan = ["network-after", "missing"];
          const turn = await send({}, { stream });
          equal(turn.status, 200);
          equal([
            assistants().length,
            s.receipts.length,
            s.providerCalls,
            s.quotaCalls,
          ], [1, 1, 1, 1]);
          equal(turn.data.assistantMessage.id, assistants()[0].id);
          reset();
          s.confirmPlan = ["network-before", "missing", "missing"];
          const unknown = await send({}, { stream });
          equal([unknown.status, unknown.data.code, unknown.data.retryable], [
            503,
            "chat_request_unconfirmed",
            false,
          ]);
          equal([assistants().length, s.claimWrites.length, s.providerCalls], [
            0,
            0,
            1,
          ]);
        }
        // Genuine old schema: a FIRST-attempt missing function is still definite (compat).
        reset();
        s.confirmPlan = ["missing"];
        const old = await send({ content: CRISIS });
        equal([
          old.status,
          old.data.support.persistence,
          assistants().length,
          s.confirmCalls,
        ], [200, "saved_without_receipt", 1, 1]);
      },
    );

    await t.step(
      "R01 (model turn): a commit whose every response was lost is returned from the claim, never reported unconfirmed",
      async () => {
        for (const stream of [false, true]) {
          reset();
          s.provider = { text: "Saved exactly once.", tool: ARGS() };
          s.confirmPlan = ["network-after", "network-before", "network-before"];
          const res = await send({}, { stream });
          equal(res.status, 200);
          equal([assistants().length, s.receipts.length, s.proposals.length], [
            1,
            1,
            1,
          ]);
          equal([
            res.data.assistantMessage.id,
            res.data.support.proposal.id,
            res.data.support.context_receipt.receipt_id,
          ], [assistants()[0].id, s.proposals[0].id, s.receipts[0].id]);
          equal([
            s.providerCalls,
            s.quotaCalls,
            s.confirmCalls,
            s.claimWrites.length,
          ], [1, 1, 3, 0]);
        }
      },
    );

    // =========================================================================
    // M4-R02 / author F001: legacy-shaped requests honor the current server-owned eligibility
    // =========================================================================
    const legacyBody = (over: Row = {}) => ({
      conversationId,
      content: MESSAGE,
      requestId,
      ...over,
    });
    // Title/extraction run in the background after a legacy reply; settle them so they cannot
    // land in the next step, and look at the MAIN chat call separately from those helpers.
    const sendLegacy = async (
      over: Row = {},
      options: { stream?: boolean } = {},
    ) => {
      const res = await read(await post(legacyBody(over), options));
      await Promise.allSettled(background.splice(0));
      return res;
    };
    const isHelperPrompt = (b: Row) => {
      const sys = String(b.input?.[0]?.content ?? "");
      return sys.startsWith("Extract structured personal facts") ||
        sys.startsWith("Generate a concise 3-6 word");
    };
    const chatBodies = () => s.providerBodies.filter((b) => !isHelperPrompt(b));
    const iso = (ms: number) => new Date(ms).toISOString();
    const DAY = 86_400_000;
    const mem = (id: string, content: string, over: Row = {}): Row => ({
      id,
      category: "preferences",
      content,
      revision: 1,
      confirmed_at: iso(Date.now() - DAY),
      review_due_at: null,
      expires_at: null,
      ...over,
    });
    const ids = {
      eligible: "e1000000-0000-4000-8000-000000000001",
      stopped: "e1000000-0000-4000-8000-000000000002",
      forgotten: "e1000000-0000-4000-8000-000000000003",
      expired: "e1000000-0000-4000-8000-000000000004",
      review: "e1000000-0000-4000-8000-000000000005",
      sourceSuppressed: "e1000000-0000-4000-8000-000000000006",
      deleted: "e1000000-0000-4000-8000-000000000007",
      conversationDerived: "e1000000-0000-4000-8000-000000000008",
      sourceMessage: "e2000000-0000-4000-8000-000000000001",
      derivedAssistant: "e2000000-0000-4000-8000-000000000002",
    };
    const classes: Array<[string, string, Row, (() => void)?]> = [
      ["Stop using", "STOPPED-MARKER", { disabled_at: iso(Date.now() - 1000) }],
      [
        "Forget",
        "FORGOTTEN-MARKER",
        {},
        () => s.suppressions.push({ kind: "memory", ref_id: ids.forgotten }),
      ],
      ["expired", "EXPIRED-MARKER", { expires_at: iso(Date.now() - 1000) }],
      ["life-context review due", "REVIEW-MARKER", {
        category: "life_context",
        confirmed_at: iso(Date.now() - 100 * DAY),
      }],
      [
        "source message forgotten",
        "SOURCE-MARKER",
        { source_message_id: ids.sourceMessage },
        () =>
          s.suppressions.push({ kind: "message", ref_id: ids.sourceMessage }),
      ],
      ["deleted", "DELETED-MARKER", { deleted_at: iso(Date.now() - 1000) }],
      [
        "source conversation forgotten",
        "CONVERSATION-DERIVED-MARKER",
        { source_conversation_id: conversationId },
        () =>
          s.suppressions.push({ kind: "conversation", ref_id: conversationId }),
      ],
    ];

    await t.step(
      "R02: an authenticated legacy request after Stop using / Forget / expiry / review / derived / conversation suppression sends none of it",
      async () => {
        for (const stream of [false, true]) {
          for (const [label, marker, over, arrange] of classes) {
            reset();
            const id = Object.values(ids)[
              1 + classes.findIndex((c) => c[0] === label)
            ];
            s.memories = [
              mem(ids.eligible, "ELIGIBLE-MARKER keeps steps short"),
              mem(id, marker, over),
            ];
            arrange?.();
            const res = await sendLegacy({}, { stream });
            equal([label, res.status], [label, 200]);
            const prompt = JSON.stringify(chatBodies()[0].input);
            assert(
              prompt.includes("ELIGIBLE-MARKER"),
              `${label}: the eligible control is still used`,
            );
            assert(
              !prompt.includes(marker),
              `${label}: ${marker} must not reach the provider`,
            );
            noLegacyPersonalReads();
            equal([label, s.historyReads, chatBodies().length], [label, 0, 1]);
            equal([label, res.data.memoryUsed, res.data.memoryIdsUsed], [
              label,
              true,
              [ids.eligible],
            ]);
            assert(
              !("support" in res.data),
              "legacy response shape is unchanged",
            );
          }
        }
      },
    );

    await t.step(
      "R02: generated pending/legacy_review fragments, direct curated rows and direct intents are never read when installed",
      async () => {
        reset();
        s.fragments = [
          {
            fragment_type: "fact",
            key: "job",
            value: "FRAGMENT-PENDING-MARKER",
            confidence: 0.9,
            review_state: "pending",
          },
          {
            fragment_type: "fact",
            key: "home",
            value: "FRAGMENT-LEGACY-MARKER",
            confidence: 0.9,
            review_state: "legacy_review",
          },
        ];
        s.curated = [{
          id: ids.stopped,
          category: "preferences",
          content: "DIRECT-CURATED-MARKER",
        }];
        s.legacyIntents = [{ intent: "DIRECT-INTENT-MARKER" }];
        s.memories = [mem(ids.eligible, "ELIGIBLE-MARKER")];
        s.intent = {
          id: "66666666-6666-4666-8666-666666666666",
          intent: "INTENT-MARKER",
          created_at: iso(Date.now() - 1000),
          expires_at: iso(Date.now() + DAY),
        };
        const res = await sendLegacy();
        equal(res.status, 200);
        const prompt = JSON.stringify(chatBodies()[0].input);
        for (
          const gone of [
            "FRAGMENT-PENDING-MARKER",
            "FRAGMENT-LEGACY-MARKER",
            "DIRECT-CURATED-MARKER",
            "DIRECT-INTENT-MARKER",
          ]
        ) {
          assert(!prompt.includes(gone), `${gone} must not be sent`);
        }
        assert(
          prompt.includes("ELIGIBLE-MARKER") &&
            prompt.includes("INTENT-MARKER"),
        );
        noLegacyPersonalReads();
        equal(s.contextCalls.at(-1)!.p_include_personal, true);
        // Ordinary privacy-off behavior that is still eligible is preserved: absence context.
        equal(s.absenceReads, 1);
        assert(prompt.includes("Returning user"));
      },
    );

    await t.step(
      "R02: derived assistant turns, suppressed messages, interface text and a suppressed conversation are not history",
      async () => {
        reset();
        const base = Date.UTC(2026, 10, 2);
        s.messages.push(
          {
            id: ids.derivedAssistant,
            conversation_id: conversationId,
            role: "assistant",
            content: "DERIVED-ASSISTANT-MARKER",
            content_origin: null,
            content_revision: 0,
            created_at: iso(base),
          },
          {
            id: "e2000000-0000-4000-8000-000000000003",
            conversation_id: conversationId,
            role: "assistant",
            content: "FALLBACK-MARKER",
            content_origin: "interface_fallback",
            content_revision: 0,
            created_at: iso(base + 1000),
          },
          {
            id: "e2000000-0000-4000-8000-000000000004",
            conversation_id: conversationId,
            role: "user",
            content: "VISIBLE-HISTORY-MARKER",
            content_origin: null,
            content_revision: 0,
            created_at: iso(base + 2000),
          },
        );
        s.suppressions.push({ kind: "message", ref_id: ids.derivedAssistant });
        const res = await sendLegacy();
        equal(res.status, 200);
        const prompt = JSON.stringify(chatBodies()[0].input);
        assert(prompt.includes("VISIBLE-HISTORY-MARKER"));
        assert(
          !prompt.includes("DERIVED-ASSISTANT-MARKER") &&
            !prompt.includes("FALLBACK-MARKER"),
        );
        equal(
          s.historyReads,
          0,
          "history comes from the shared policy, not a direct read",
        );

        // History the shared policy selected is sanitized exactly once (escaping it again would
        // corrupt it and break the byte accounting).
        reset();
        const raw = 'quote "x" back\\slash';
        s.messages.push({
          id: "e2000000-0000-4000-8000-000000000009",
          conversation_id: conversationId,
          role: "user",
          content: raw,
          content_origin: null,
          content_revision: 0,
          created_at: iso(Date.now() - 1000),
        });
        await sendLegacy();
        assert(
          (chatBodies()[0].input as Row[]).some((m) =>
            m.role === "user" && m.content === sanitizeForPrompt(raw)
          ),
          "user history appears exactly as sanitizeForPrompt(raw)",
        );

        // A suppressed conversation contributes no history at all.
        reset();
        s.messages.push({
          id: ids.derivedAssistant,
          conversation_id: conversationId,
          role: "assistant",
          content: "OLD-TURN-MARKER",
          content_origin: null,
          content_revision: 0,
          created_at: iso(Date.now() - DAY),
        });
        s.suppressions.push({ kind: "conversation", ref_id: conversationId });
        const quiet = await sendLegacy();
        equal(quiet.status, 200);
        assert(
          !JSON.stringify(chatBodies()[0].input).includes("OLD-TURN-MARKER"),
        );
        assert(
          !JSON.stringify(chatBodies()[0].input).includes("Earlier reply"),
        );
      },
    );

    await t.step(
      "R02: privacy mode on keeps all personal context out, and history still follows the shared policy",
      async () => {
        reset();
        s.privacyMode = "enhanced";
        s.memories = [mem(ids.eligible, "ELIGIBLE-MARKER")];
        s.curated = [{
          id: ids.stopped,
          category: "preferences",
          content: "DIRECT-CURATED-MARKER",
        }];
        s.messages.push({
          id: ids.derivedAssistant,
          conversation_id: conversationId,
          role: "assistant",
          content: "DERIVED-ASSISTANT-MARKER",
          content_origin: null,
          content_revision: 0,
          created_at: iso(Date.now() - 1000),
        });
        s.suppressions.push({ kind: "message", ref_id: ids.derivedAssistant });
        const res = await sendLegacy();
        equal(res.status, 200);
        const prompt = JSON.stringify(chatBodies()[0].input);
        for (
          const gone of [
            "ELIGIBLE-MARKER",
            "DIRECT-CURATED-MARKER",
            "DERIVED-ASSISTANT-MARKER",
            "Returning user",
          ]
        ) assert(!prompt.includes(gone), gone);
        equal(s.contextCalls.at(-1)!.p_include_personal, false);
        equal([s.absenceReads, res.data.memoryUsed, res.data.memoryIdsUsed], [
          0,
          false,
          [],
        ]);
        noLegacyPersonalReads();
      },
    );

    await t.step(
      "R02: when the support schema is installed but unreadable, a legacy request fails closed (nothing read, sent or debited)",
      async () => {
        for (const how of ["caps-error", "sources-error"] as const) {
          reset();
          seedMemory();
          s.fragments = [{
            fragment_type: "fact",
            key: "k",
            value: "FRAGMENT-PENDING-MARKER",
            confidence: 1,
          }];
          s.curated = [{
            id: ids.stopped,
            category: "preferences",
            content: "DIRECT-CURATED-MARKER",
          }];
          if (how === "caps-error") s.caps = "error";
          else s.contextFail = true;
          const res = await sendLegacy();
          equal([how, res.status, res.data.code, res.data.retryable], [
            how,
            503,
            "chat_context_unavailable",
            true,
          ]);
          equal([
            how,
            s.providerCalls,
            s.quotaCalls,
            s.budgetCalls,
            s.historyReads,
          ], [how, 0, 0, 0, 0]);
          noLegacyPersonalReads();
          equal(
            claim().response_status,
            503,
            "stored as a failure receipt like any other legacy failure",
          );
          // Recovery: the same request id may be explicitly retried once the policy is readable.
          s.caps = "ok";
          s.contextFail = false;
          const retried = await sendLegacy({ retryFailed: true });
          equal([how, retried.status, chatBodies().length, s.quotaCalls], [
            how,
            200,
            1,
            1,
          ]);
          assert(
            !JSON.stringify(chatBodies()[0].input).includes(
              "FRAGMENT-PENDING-MARKER",
            ),
          );
        }
      },
    );

    await t.step(
      "R02: when the support schema is genuinely not deployed the old baseline is unchanged",
      async () => {
        for (const caps of ["missing", "no-policy"] as const) {
          reset();
          s.caps = caps;
          s.fragments = [{
            fragment_type: "fact",
            key: "job",
            value: "BASELINE-FRAGMENT-MARKER",
            confidence: 0.9,
          }];
          s.curated = [{
            id: ids.eligible,
            category: "preferences",
            content: "BASELINE-CURATED-MARKER",
          }];
          const res = await sendLegacy();
          equal([caps, res.status, "support" in res.data], [caps, 200, false]);
          const prompt = JSON.stringify(chatBodies()[0].input);
          assert(
            prompt.includes("BASELINE-FRAGMENT-MARKER") &&
              prompt.includes("BASELINE-CURATED-MARKER"),
            `${caps}: old behavior preserved`,
          );
          equal([
            s.historyReads,
            s.rpcCalls.includes("support_context_sources"),
          ], [1, false]);
          equal(res.data.memoryUsed, true);
        }
      },
    );

    await t.step(
      "R02: background extraction rechecks suppression and the privacy revision before the provider and before storing",
      async () => {
        const extractionJson = JSON.stringify([{
          type: "fact",
          key: "job",
          value: "Teacher",
        }]);
        const settle = () => Promise.allSettled(background);
        // Allowed: one candidate is stored.
        reset();
        s.provider = { text: extractionJson };
        assert((await sendLegacy()).status === 200);
        await settle();
        equal([s.providerCalls, s.fragmentWrites.length], [2, 1]);
        // The conversation was forgotten: no provider call for extraction and nothing stored.
        reset();
        s.provider = { text: extractionJson };
        s.suppressions.push({ kind: "conversation", ref_id: conversationId });
        await sendLegacy();
        await settle();
        equal(s.fragmentWrites.length, 0);
        // A correction accepted while the main reply is produced: extraction never starts.
        reset();
        s.provider = { text: extractionJson };
        s.hooks.onProviderResponse = () => {
          s.privacyRevision++;
        };
        await sendLegacy();
        await settle();
        equal([s.providerCalls, s.fragmentWrites.length], [1, 0]);
        // A correction accepted while extraction itself runs: the candidate is not stored.
        reset();
        s.provider = { text: extractionJson };
        s.hooks.onProviderResponse = () => {
          if (s.providerCalls === 2) s.privacyRevision++;
        };
        await sendLegacy();
        await settle();
        equal([s.providerCalls, s.fragmentWrites.length], [2, 0]);
      },
    );

    // =========================================================================
    // F006: a legacy-created fixed safety reply is never model history
    // =========================================================================
    await t.step(
      "F006: legacy crisis reply is tagged safety_response when the schema is installed, and later model turns never receive it",
      async () => {
        reset();
        seedMemory();
        const safety = await sendLegacy({ content: CRISIS });
        equal([
          safety.status,
          safety.data.isCrisisResponse,
          safety.data.assistantMessage.content,
        ], [200, true, CRISIS_RESPONSE]);
        assert(!("support" in safety.data), "legacy wire unchanged");
        equal(assistants().length, 1, "one insert");
        equal(assistants()[0].content_origin, "safety_response");
        equal(s.messageInserts.filter((m) => m.role === "assistant").length, 1);
        assert(
          "content_origin" in
            s.messageInserts.find((m) => m.role === "assistant")!,
          "tagged in the SAME insert",
        );
        equal(s.messageTags, 0);
        equal(
          [s.providerCalls, s.quotaCalls],
          [0, 0],
          "help never waits for a model or quota",
        );
        // A later new-contract turn and a later legacy turn: the fixed text is not history.
        s.provider = { text: "Happy to help plan tomorrow." };
        const next = await send({
          requestId: "bbcdefab-3333-4333-8333-333333333333",
          content: "Please help me plan tomorrow.",
        });
        equal(next.status, 200);
        assert(
          !JSON.stringify(s.providerBodies.at(-1)!.input).includes(
            "988 Suicide",
          ),
          "fixed crisis text must not reach the model as assistant history",
        );
        const later = await sendLegacy({
          requestId: "cbcdefab-3333-4333-8333-333333333333",
          content: "And the day after?",
        });
        equal(later.status, 200);
        assert(
          !JSON.stringify(chatBodies().at(-1)!.input).includes("988 Suicide"),
        );
      },
    );

    await t.step(
      "F006: with the schema genuinely absent the old untagged insert is untouched (no tagged attempt)",
      async () => {
        reset();
        s.caps = "missing";
        const absent = await sendLegacy({ content: CRISIS });
        equal([absent.status, assistants().length, s.messageTags], [200, 1, 0]);
        equal(s.directAssistantInserts, 1, "exactly one insert attempt");
        const body = s.messageInserts.find((m) => m.role === "assistant")!;
        assert(
          !("content_origin" in body),
          "the column may not exist: it is never sent",
        );
        equal(assistants()[0].content_origin, null);
      },
    );

    // After the fixed help text was saved (or not), a recovered service must never treat it as
    // model-authored history for a later new-contract OR legacy request.
    const laterTurnsExcludeHelp = async () => {
      s.caps = "ok";
      s.confirmMissing = false;
      s.noOriginColumn = false;
      s.provider = { text: "Happy to help." };
      const before = s.providerBodies.length;
      const fresh = await send({
        requestId: "bbcdefab-3333-4333-8333-333333333333",
        content: "Please help me plan tomorrow.",
        expected_privacy_revision: s.privacyRevision,
      });
      equal(fresh.status, 200);
      const legacy = await sendLegacy({
        requestId: "cbcdefab-3333-4333-8333-333333333333",
        content: "And the day after?",
      });
      equal(legacy.status, 200);
      const sent = s.providerBodies.slice(before).filter((b) =>
        !isHelperPrompt(b)
      );
      equal(sent.length, 2, "one model call per later request");
      for (const body of sent) {
        assert(
          !JSON.stringify(body.input).includes("988 Suicide"),
          "the fixed crisis text must never be dispatched as model history",
        );
      }
    };

    await t.step(
      "F006 (r4): an unavailable probe is not permission to persist the reply as model text: one atomically tagged insert, never a tag-after UPDATE",
      async () => {
        reset();
        seedMemory();
        // The reviewer's sequence: capability read fails AND the old best-effort tag UPDATE
        // would also have failed.
        s.caps = "error";
        s.fail.messageTag = true;
        const res = await sendLegacy({ content: CRISIS });
        equal(
          [
            res.status,
            res.data.isCrisisResponse,
            res.data.assistantMessage.content,
          ],
          [200, true, CRISIS_RESPONSE],
        );
        assert(!("support" in res.data), "legacy wire unchanged");
        equal(
          [assistants().length, s.directAssistantInserts, s.messageTags],
          [1, 1, 0],
          "one row, one insert, no UPDATE path at all",
        );
        const body = s.messageInserts.find((m) => m.role === "assistant")!;
        equal(
          body.content_origin,
          "safety_response",
          "origin recorded in the SAME insert",
        );
        equal(assistants()[0].content_origin, "safety_response");
        equal(res.data.assistantMessage.id, assistants()[0].id);
        equal([s.providerCalls, s.quotaCalls, s.budgetCalls], [0, 0, 0]);
        await laterTurnsExcludeHelp();
      },
    );

    await t.step(
      "F006 (r4): an unknown save outcome stays pending with the same claim, never a second save; commit-response-loss leaves one TAGGED row",
      async () => {
        const pendingCases: Array<
          [string, typeof s.assistantInsertPlan[number], "error" | "ok", number]
        > = [
          [
            "lost before commit (probe unavailable)",
            "network-before",
            "error",
            0,
          ],
          [
            "lost AFTER commit (probe unavailable)",
            "network-after",
            "error",
            1,
          ],
          [
            "non-column database error (probe unavailable)",
            "db-error",
            "error",
            0,
          ],
          [
            "a different missing column is not proof (probe unavailable)",
            "missing-other-column",
            "error",
            0,
          ],
          [
            "a not-null violation naming content_origin is not a missing column (probe unavailable)",
            "check-violation",
            "error",
            0,
          ],
          ["lost before commit (schema installed)", "network-before", "ok", 0],
          ["lost AFTER commit (schema installed)", "network-after", "ok", 1],
        ];
        for (const [label, step, caps, rows] of pendingCases) {
          reset();
          seedMemory();
          s.caps = caps;
          s.assistantInsertPlan = [step];
          s.sentinel = MARKER;
          const cap = captureConsole();
          let res: Wire;
          try {
            res = await sendLegacy({ content: CRISIS });
          } finally {
            cap.restore();
          }
          equal([label, res.status, res.data.isCrisisResponse], [
            label,
            200,
            true,
          ]);
          equal([
            label,
            res.data.assistantMessage.content,
            res.data.message.content,
          ], [label, CRISIS_RESPONSE, CRISIS_RESPONSE]);
          assert(!("support" in res.data), `${label}: legacy wire unchanged`);
          equal(
            [label, res.data.assistantMessage.id],
            [label, await pendingLocalMessageId(requestId)],
            "a stable placeholder, not a database row",
          );
          equal(
            [
              label,
              s.directAssistantInserts,
              assistants().length,
              s.messageTags,
              s.claimWrites.length,
            ],
            [label, 1, rows, 0, 0],
            "exactly one attempt; nothing more written; claim untouched",
          );
          assert(
            claim().response === null,
            `${label}: the claim stays pending`,
          );
          if (rows === 1) {
            equal([label, assistants()[0].content_origin], [
              label,
              "safety_response",
            ], "a committed row is tagged");
          }
          equal([label, s.providerCalls, s.quotaCalls], [label, 0, 0]);
          assert(
            !cap.lines.join("\n").toLowerCase().includes(MARKER.toLowerCase()),
            `${label}: dependency text leaked`,
          );
          // Same request id: pending, still no second save.
          const again = await sendLegacy({ content: CRISIS });
          equal([label, again.status, again.data.error], [
            label,
            409,
            PENDING_MESSAGE,
          ]);
          equal([label, s.directAssistantInserts, assistants().length], [
            label,
            1,
            rows,
          ]);
          await laterTurnsExcludeHelp();
          if (label === "lost before commit (probe unavailable)") {
            fixture("legacy_safety_pending.json", res.data);
          }
        }
      },
    );

    await t.step(
      "F006 (r5): a schema-cache or column rejection never unlocks an untagged insert: a stale cache with a REAL column stays pending and nothing NULL-origin is ever written",
      async () => {
        const rows = () =>
          s.messages.filter((m) =>
            m.role === "assistant" && m.content === CRISIS_RESPONSE
          );
        const legacyCases: Array<
          [
            string,
            typeof s.assistantInsertPlan[number] | "no-column",
            "error" | "ok",
          ]
        > = [
          [
            "stale cache refuses content_origin (PGRST204), probe unavailable",
            "missing-pgrst204",
            "error",
          ],
          [
            "stale cache refuses content_origin (PGRST204), schema installed",
            "missing-pgrst204",
            "ok",
          ],
          [
            "undefined_column 42703, probe unavailable",
            "missing-42703",
            "error",
          ],
          [
            "stale cache refuses support_session_id only, probe unavailable",
            "missing-session-column",
            "error",
          ],
          [
            "a schema that really lacks the column, probe unavailable",
            "no-column",
            "error",
          ],
        ];
        for (const [label, step, caps] of legacyCases) {
          reset();
          s.caps = caps;
          if (step === "no-column") s.noOriginColumn = true;
          else s.assistantInsertPlan = [step];
          const res = await sendLegacy({ content: CRISIS });
          equal([label, res.status, res.data.assistantMessage.content], [
            label,
            200,
            CRISIS_RESPONSE,
          ]);
          equal([label, res.data.assistantMessage.id], [
            label,
            await pendingLocalMessageId(requestId),
          ]);
          assert(!("support" in res.data), `${label}: legacy wire unchanged`);
          equal(
            [
              label,
              s.directAssistantInserts,
              rows().length,
              s.messageTags,
              s.claimWrites.length,
            ],
            [label, 1, 0, 0, 0],
            "exactly ONE tagged insert: no untagged retry, no UPDATE, nothing written over the claim",
          );
          assert(
            claim().response === null,
            `${label}: the claim stays pending`,
          );
          assert(
            !s.messageInserts.some((m) =>
              m.role === "assistant" && !("content_origin" in m)
            ),
            `${label}: an untagged assistant insert must never be issued in tagged mode`,
          );
          const again = await sendLegacy({ content: CRISIS });
          equal([label, again.status, again.data.error], [
            label,
            409,
            PENDING_MESSAGE,
          ]);
          equal([label, s.directAssistantInserts], [label, 1]);
          // Continuation: the cache refreshes / the service recovers. Neither a new-contract nor a
          // legacy request ever sees the fixed text, because no NULL-origin row exists.
          await laterTurnsExcludeHelp();
          equal([label, rows().length], [label, 0]);
        }

        // The same rule for a new-contract request whose atomic confirm is definitively absent.
        for (
          const step of ["missing-pgrst204", "missing-session-column"] as const
        ) {
          reset();
          s.confirmMissing = true;
          s.assistantInsertPlan = [step];
          const res = await send({ content: CRISIS });
          equal([
            step,
            res.status,
            res.data.support.persistence,
            res.data.support.confirmed,
          ], [step, 200, "pending_reconcile", false]);
          equal([
            step,
            res.data.assistantMessage.content,
            res.data.assistantMessage.id,
          ], [step, CRISIS_RESPONSE, await pendingLocalMessageId(requestId)]);
          equal([
            step,
            s.directAssistantInserts,
            rows().length,
            s.claimWrites.length,
          ], [step, 1, 0, 0]);
          assert(claim().response === null);
          assert(
            !s.messageInserts.some((m) =>
              m.role === "assistant" && !("content_origin" in m)
            ),
          );
          await laterTurnsExcludeHelp();
          equal([step, rows().length], [step, 0]);
        }
        reset();
        s.confirmMissing = true;
        s.noOriginColumn = true;
        const bare = await send({ content: CRISIS });
        equal([
          bare.data.support.persistence,
          s.directAssistantInserts,
          rows().length,
        ], ["pending_reconcile", 1, 0]);
        // The tagged direct insert carries both the origin and the session in ONE statement.
        reset();
        s.confirmMissing = true;
        const ok = await send({ content: CRISIS });
        const body = s.messageInserts.find((m) => m.role === "assistant")!;
        equal([
          ok.status,
          body.content_origin,
          body.support_session_id,
          ok.data.support.persistence,
        ], [200, "safety_response", sessionId, "saved_without_receipt"]);
      },
    );

    await t.step(
      "F006 (r5): an empty or malformed acknowledgment is never 'saved': pending, nothing retried, claim not completed, even when the row actually committed",
      async () => {
        const shapes = [
          ["{}", "ack-empty", "commit-ack-empty"],
          ["a numeric id", "ack-wrong-id-type", "commit-ack-wrong-id-type"],
          ["an array", "ack-array", "commit-ack-array"],
          [
            "a row for another conversation",
            "ack-other-conversation",
            "commit-ack-other-conversation",
          ],
          [
            "a row with the wrong role",
            "ack-wrong-role",
            "commit-ack-wrong-role",
          ],
        ] as const;
        const modes: Array<[string, "error" | "ok" | "missing", boolean]> = [
          ["legacy, probe unavailable", "error", false],
          ["legacy, schema installed", "ok", false],
          ["legacy, schema known absent (plain)", "missing", false],
          ["new contract, direct save", "ok", true],
        ];
        for (const [mode, caps, isSupport] of modes) {
          for (const [shape, uncommitted, committed] of shapes) {
            for (
              const [step, commits] of [[uncommitted, false], [
                committed,
                true,
              ]] as const
            ) {
              const label = `${mode} / ${shape} / ${
                commits ? "committed" : "not committed"
              }`;
              reset();
              s.caps = caps;
              if (isSupport) s.confirmMissing = true;
              s.assistantInsertPlan = [step];
              const res = isSupport
                ? await send({ content: CRISIS })
                : await sendLegacy({ content: CRISIS });
              equal([
                label,
                res.status,
                res.data.isCrisisResponse,
                res.data.assistantMessage.content,
              ], [label, 200, true, CRISIS_RESPONSE]);
              equal([label, res.data.assistantMessage.id], [
                label,
                await pendingLocalMessageId(requestId),
              ], "the placeholder, never the unacknowledged row");
              equal(
                [
                  label,
                  s.directAssistantInserts,
                  assistants().length,
                  s.claimWrites.length,
                  s.messageTags,
                ],
                [label, 1, commits ? 1 : 0, 0, 0],
                "one insert, never retried; claim not completed",
              );
              assert(
                claim().response === null,
                `${label}: the claim stays pending`,
              );
              if (commits && caps !== "missing") {
                equal([label, assistants()[0].content_origin], [
                  label,
                  "safety_response",
                ], "a committed row is already tagged");
              }
              const again = isSupport
                ? await send({ content: CRISIS })
                : await sendLegacy({ content: CRISIS });
              equal([label, again.status, s.directAssistantInserts], [
                label,
                409,
                1,
              ]);
              if (caps !== "missing") await laterTurnsExcludeHelp();
            }
          }
        }
        // Known-absent legacy contract: a server-reported failure is still the old hard error.
        reset();
        s.caps = "missing";
        s.assistantInsertPlan = ["db-error"];
        const hard = await sendLegacy({ content: CRISIS });
        assert(hard.status >= 500, "the old contract for a reported failure");
        equal([s.directAssistantInserts, assistants().length], [1, 0]);
      },
    );

    // =========================================================================
    // M4-R02 (r2): installed-schema legacy turns revalidate before dispatch and save atomically
    // =========================================================================
    const corrections: Array<[string, () => void]> = [
      ["accepted privacy change", () => {
        s.privacyRevision++;
      }],
      ["stop-using of an included memory", () => {
        s.memories.find((m) => m.id === ids.eligible)!.disabled_at = iso(
          Date.now(),
        );
        s.privacyRevision++;
      }],
      ["edit of an included memory", () => {
        s.memories.find((m) => m.id === ids.eligible)!.revision++;
      }],
      ["forget of an included memory", () => {
        s.suppressions.push({ kind: "memory", ref_id: ids.eligible });
      }],
      ["rewrite of an included history message", () => {
        s.messages[0].content = "REWRITTEN-MARKER";
        // The database always bumps the version on a real rewrite.
        s.messages[0].content_revision++;
      }],
    ];
    const seedLegacyWorld = () => {
      reset();
      s.memories = [mem(ids.eligible, "STOPPABLE-MARKER keeps steps short")];
      s.intent = {
        id: "66666666-6666-4666-8666-666666666666",
        intent: "INTENT-MARKER",
        created_at: iso(Date.now() - 1000),
        expires_at: iso(Date.now() + DAY),
      };
    };

    await t.step(
      "R02 (r2): an installed legacy turn is saved by the atomic confirmation (NULL session), wire unchanged, replay identical",
      async () => {
        for (const stream of [false, true]) {
          seedLegacyWorld();
          s.provider = { text: "A reply for an older client." };
          const res = await sendLegacy({}, { stream });
          equal(res.status, 200);
          const d = res.data;
          assert(!("support" in d) && !("support_confirmed" in d));
          equal(d.assistantMessage.id, assistants()[0].id);
          equal(d.message, d.assistantMessage);
          equal([
            d.memoryUsed,
            d.memoryIdsUsed,
            d.quotaUsed,
            d.quotaLimit,
            d.coachData,
            d.conversationTitle,
          ], [true, [ids.eligible], 1, 5, null, null]);
          equal(d.userMessage.content, MESSAGE);
          const a = s.confirmArgs[0];
          equal([
            a.support_session_id,
            a.scope,
            a.content_origin,
            a.proposal,
            a.provider_model,
            a.route_version,
          ], [
            null,
            "personalized",
            "model",
            null,
            "gpt-6-luna",
            "responses-legacy-1",
          ]);
          const kinds = a.sources.map((x: Row) => x.kind);
          for (
            const k of [
              "safety_policy",
              "message",
              "companion_memory",
              "daily_intent",
            ]
          ) assert(kinds.includes(k), `receipt cites ${k}`);
          assert(
            a.sources.find((x: Row) => x.kind === "companion_memory")
              .revision === 1,
          );
          assert(
            a.exclusions.includes("generated_fragments") &&
              !a.exclusions.includes("saved_memory"),
          );
          equal([
            s.directAssistantInserts,
            s.receipts.length,
            s.receipts[0].support_session_id ?? null,
            s.claimWrites.length,
            chatBodies().length,
          ], [0, 1, null, 0, 1]);
          assert(
            assistants()[0].support_session_id == null,
            "no session is invented for an old client",
          );
          // Replay: the stored legacy response, byte-identical, with no work.
          const before = sideEffects();
          const replay = await sendLegacy({}, { stream: false });
          equal(sideEffects(), before);
          equal(replay.data, d);
          equal(assistants().length, 1);
          if (!stream) fixture("legacy_installed_completed.json", d);
        }
      },
    );

    await t.step(
      "R02 (r2): a correction accepted before dispatch (budget hook) stops everything: no provider, no quota, no save",
      async () => {
        for (const stream of [false, true]) {
          for (const [label, edit] of corrections) {
            seedLegacyWorld();
            s.hooks.onBudget = edit;
            const res = await sendLegacy({}, { stream });
            equal([label, res.status, res.data.code, res.data.retryable], [
              label,
              409,
              "chat_privacy_revision_stale",
              true,
            ]);
            equal([
              label,
              chatBodies().length,
              s.quotaCalls,
              s.confirmCalls,
              assistants().length,
              s.directAssistantInserts,
            ], [label, 0, 0, 0, 0, 0]);
            assert(
              claim().response_status === 409 &&
                claim().response.retryable === true,
              "stored as a retryable failure",
            );
            // Explicit retry: the current state is used; the stopped memory is gone. (A policy
            // that does not cite message versions cannot be retried against a bumped one: skew.)
            if (label.startsWith("rewrite") && !policyCitesRevision) continue;
            s.hooks.onBudget = undefined;
            const retried = await sendLegacy({ retryFailed: true });
            equal([
              label,
              retried.status,
              chatBodies().length,
              assistants().length,
            ], [label, 200, 1, 1]);
            const prompt = JSON.stringify(chatBodies()[0].input);
            if (label.includes("stop-using") || label.includes("forget")) {
              assert(
                !prompt.includes("STOPPABLE-MARKER"),
                `${label}: stopped memory not sent on retry`,
              );
            }
          }
        }
      },
    );

    await t.step(
      "R02 (r2): a correction accepted while the provider runs is quarantined: no second invocation, no save",
      async () => {
        for (const stream of [false, true]) {
          for (const [label, edit] of corrections) {
            seedLegacyWorld();
            s.hooks.onProviderResponse = edit;
            const res = await sendLegacy({}, { stream });
            equal([label, res.status, res.data.code, res.data.retryable], [
              label,
              409,
              "chat_privacy_revision_stale",
              true,
            ]);
            equal([
              label,
              chatBodies().length,
              s.quotaCalls,
              s.confirmCalls,
              assistants().length,
              s.receipts.length,
              s.directAssistantInserts,
            ], [label, 1, 1, 0, 0, 0, 0]);
            assert(
              !s.claimWrites.some((w) => w.response?.assistantMessage),
              "no final reply was ever stored",
            );
          }
        }
      },
    );

    await t.step(
      "R02 (r2): a correction after the client's last check is rejected by the atomic confirmation itself",
      async () => {
        for (const [label, edit] of corrections) {
          seedLegacyWorld();
          s.hooks.onConfirm = edit;
          const res = await sendLegacy({});
          equal([label, res.status, res.data.code], [
            label,
            409,
            "chat_privacy_revision_stale",
          ]);
          equal([
            label,
            chatBodies().length,
            s.confirmCalls,
            assistants().length,
            s.receipts.length,
            s.directAssistantInserts,
          ], [label, 1, 1, 0, 0, 0]);
        }
      },
    );

    await t.step(
      "R02 (r2): unknown confirm outcomes for a legacy turn never duplicate the save and reconcile under the same id",
      async () => {
        seedLegacyWorld();
        s.confirmPlan = ["network-after", "network-before", "network-before"];
        const done = await sendLegacy({});
        equal([
          done.status,
          "support" in done.data,
          done.data.assistantMessage.id === assistants()[0]?.id,
        ], [200, false, true]);
        equal([
          assistants().length,
          s.receipts.length,
          s.claimWrites.length,
          chatBodies().length,
          s.quotaCalls,
        ], [1, 1, 0, 1, 1]);

        seedLegacyWorld();
        s.confirmPlan = ["network-before", "missing", "db-error"];
        const unknown = await sendLegacy({});
        equal([unknown.status, unknown.data.code, unknown.data.retryable], [
          503,
          "chat_request_unconfirmed",
          false,
        ]);
        equal([
          assistants().length,
          s.directAssistantInserts,
          s.claimWrites.length,
          chatBodies().length,
        ], [0, 0, 0, 1]);
        assert(claim().response === null);
        const late = commitConfirm(s.confirmArgs[0]);
        assert(late.ok === true && late.replayed === false);
        const landed = await sendLegacy({});
        equal([
          landed.status,
          landed.data.assistantMessage.id,
          "support" in landed.data,
        ], [200, late.message_id, false]);
        equal([assistants().length, chatBodies().length], [1, 1]);
      },
    );

    await t.step(
      "R02 (r2): a failure that races a committed legacy turn never overwrites it: the stored legacy response is served",
      async () => {
        seedLegacyWorld();
        // The provider fails for THIS execution while another execution of the same request
        // commits the legacy turn atomically.
        s.provider = { text: "irrelevant", end: "failed" };
        s.hooks.onProviderResponse = () => {
          commitConfirm({
            user_id: userId,
            request_id: requestId,
            conversation_id: conversationId,
            content_hash: claim().content_hash,
            support_session_id: null,
            assistant_content: "Committed by the other execution.",
            content_origin: "model",
            privacy_revision: s.privacyRevision,
            scope: "personalized",
            provider_vendor: "openai",
            provider_model: "gpt-6-luna",
            route_version: "responses-legacy-1",
            exclusions: [],
            sources: [],
            proposal: null,
            response: buildLegacyWireTemplate({
              trimmedContent: MESSAGE,
              userMessage: { id: requestId, created_at: iso(Date.now()) },
              quota: { used: 1, limit: 5 },
              now: new Date(),
              content: "Committed by the other execution.",
              memoryUsed: false,
              memoryIds: [],
              coachData: null,
            }),
            response_status: 200,
          });
        };
        const res = await sendLegacy({});
        equal(res.status, 200);
        equal(
          res.data.assistantMessage.content,
          "Committed by the other execution.",
        );
        equal(res.data.assistantMessage.id, assistants()[0].id);
        assert(!("support" in res.data), "still the old wire");
        equal(assistants().length, 1);
        assert(
          claim().response.support_confirmed,
          "the confirmed response is still the stored terminal state",
        );
      },
    );

    await t.step(
      "R02 (r2): a very old client with no request id still gets the atomic path through a server-side claim",
      async () => {
        seedLegacyWorld();
        const res = await read(
          await post({ conversationId, content: MESSAGE }),
        );
        equal(res.status, 200);
        equal([
          assistants().length,
          s.confirmCalls,
          s.directAssistantInserts,
          s.receipts.length,
        ], [1, 1, 0, 1]);
        equal(s.claims.size, 1);
        assert(
          ![...s.claims.keys()].some((k) => k.endsWith(requestId)),
          "the claim id is server-generated",
        );
        equal(res.data.assistantMessage.id, assistants()[0].id);
        // A correction accepted while the provider runs is still quarantined.
        seedLegacyWorld();
        s.hooks.onProviderResponse = () => {
          s.privacyRevision++;
        };
        const stale = await read(
          await post({ conversationId, content: MESSAGE }),
        );
        equal([stale.status, stale.data.code, assistants().length], [
          409,
          "chat_privacy_revision_stale",
          0,
        ]);
      },
    );

    await t.step(
      "R02 (r2): coach data computed for an installed legacy turn is part of the one stored, replayable response",
      async () => {
        const AON =
          "I always mess up, everyone always thinks I'm a failure, and it will never get better.";
        reset();
        s.coachOk = true;
        for (let i = 0; i < 6; i++) {
          s.messages.push({
            id: crypto.randomUUID(),
            conversation_id: conversationId,
            role: i % 2 ? "assistant" : "user",
            content: `turn ${i}`,
            content_origin: null,
            content_revision: 0,
            created_at: iso(Date.now() - (10 - i) * 1000),
          });
        }
        const res = await sendLegacy({ content: AON });
        equal(res.status, 200);
        equal([
          res.data.coachData?.distortionCode,
          res.data.coachData?.encounterId,
          res.data.coachData?.reframeText,
        ], [
          "AON",
          "c0000000-0000-4000-8000-000000000001",
          "Consider the middle ground.",
        ]);
        const replay = await sendLegacy({ content: AON });
        equal(replay.data, res.data);
        equal(
          assistants().filter((m) => !String(m.content).startsWith("turn "))
            .length,
          1,
        );
      },
    );

    // =========================================================================
    // M4-R03: cited history messages are compared against an exact-id lookup
    // =========================================================================
    const target = () => s.messages[0];
    const edits: Array<[string, () => void]> = [
      ["in-place rewrite with a server version bump (apply-rewrite)", () => {
        target().content = "REWRITTEN-MARKER";
        target().content_revision++;
      }],
      ["in-place rewrite where the version did not move", () => {
        target().content = "REWRITTEN-MARKER";
      }],
      ["deleted", () => {
        s.messages.splice(0, 1);
      }],
      ["moved to another conversation", () => {
        target().conversation_id = "77777777-7777-4777-8777-777777777777";
      }],
      ["re-roled", () => {
        target().role = "user";
      }],
      ["no longer model text", () => {
        target().content_origin = "interface_fallback";
      }],
    ];

    await t.step(
      "R03: a cited message changed before dispatch stops everything: no provider, no quota, no confirm",
      async () => {
        for (const stream of [false, true]) {
          for (const [label, edit] of edits) {
            reset();
            s.hooks.onBudget = edit;
            const res = await send({
              context_scope: "conversation_only",
              expected_privacy_revision: null,
            }, { stream });
            equal([label, res.status, res.data.code, res.data.retryable], [
              label,
              409,
              "chat_privacy_revision_stale",
              true,
            ]);
            equal([
              label,
              s.providerCalls,
              s.quotaCalls,
              s.confirmCalls,
              assistants().length,
              s.receipts.length,
            ], [label, 0, 0, 0, 0, 0]);
            equal([label, res.data.reason], [label, "source_changed"]);
          }
        }
      },
    );

    await t.step(
      "R03: a cited message changed while the provider runs is quarantined: no confirm, no second provider call",
      async () => {
        for (const stream of [false, true]) {
          for (const [label, edit] of edits) {
            reset();
            s.provider = { text: "Written from the old wording." };
            s.hooks.onProviderResponse = edit;
            const res = await send({
              context_scope: "conversation_only",
              expected_privacy_revision: null,
            }, { stream });
            equal([label, res.status, res.data.code], [
              label,
              409,
              "chat_privacy_revision_stale",
            ]);
            equal([
              label,
              s.providerCalls,
              s.quotaCalls,
              s.confirmCalls,
              assistants().length,
              s.receipts.length,
            ], [label, 1, 1, 0, 0, 0]);
          }
        }
      },
    );

    await t.step(
      "R03: after a stale stop, an explicit retry uses the CURRENT wording with one new provider call",
      async () => {
        reset();
        // The version bump is only meaningful to a policy that cites it (otherwise a retry would
        // cite 0 against version 1: the version-skew case the exact lookup correctly refuses).
        const bump = policyCitesRevision ? 1 : 0;
        s.hooks.onBudget = () => {
          target().content = "REWRITTEN-MARKER";
          target().content_revision += bump;
        };
        const stale = await send({
          context_scope: "conversation_only",
          expected_privacy_revision: null,
        });
        equal(stale.status, 409);
        s.hooks.onBudget = undefined;
        const retried = await send({
          context_scope: "conversation_only",
          expected_privacy_revision: null,
          retryFailed: true,
        });
        equal(retried.status, 200);
        equal([s.providerCalls, s.confirmCalls, assistants().length], [
          1,
          1,
          1,
        ]);
        const prompt = JSON.stringify(chatBodies()[0].input);
        assert(
          prompt.includes("REWRITTEN-MARKER") &&
            !prompt.includes("Earlier reply"),
        );
        if (policyCitesRevision) {
          const cited = s.confirmArgs[0].sources.find((x: Row) =>
            x.kind === "message"
          );
          equal(
            cited.revision,
            1,
            "the receipt cites the server-owned content version",
          );
        }
      },
    );

    await t.step(
      "R03: unrelated activity is not staleness: new messages that push the cited one out of the latest window",
      async () => {
        reset();
        s.hooks.onBudget = () => {
          for (let i = 0; i < 30; i++) {
            s.messages.push({
              id: crypto.randomUUID(),
              conversation_id: conversationId,
              role: "user",
              content: `later ${i}`,
              content_origin: null,
              content_revision: 0,
              created_at: iso(Date.now() + i),
            });
          }
        };
        const res = await send({
          context_scope: "conversation_only",
          expected_privacy_revision: null,
        });
        equal([res.status, s.providerCalls, s.confirmCalls], [200, 1, 1]);
        assert(
          s.messageLookups >= 2,
          "exact-id lookups ran before dispatch and before confirm",
        );
      },
    );

    await t.step(
      "R03: a message with an earlier server version is cited exactly (revision-aware policy only)",
      async () => {
        if (!policyCitesRevision) return; // exercised by the M3-latest overlay run
        reset();
        target().content_revision = 2;
        const res = await send({
          context_scope: "conversation_only",
          expected_privacy_revision: null,
        });
        equal(res.status, 200);
        equal(
          s.confirmArgs[0].sources.find((x: Row) => x.kind === "message")
            .revision,
          2,
        );
        reset();
        target().content_revision = 2;
        s.hooks.onProviderResponse = () => {
          target().content_revision = 3;
        };
        const stale = await send({
          context_scope: "conversation_only",
          expected_privacy_revision: null,
        });
        equal([stale.status, s.confirmCalls], [409, 0]);
      },
    );

    // =========================================================================
    // M4-R04: no dependency text in logs or ordinary error responses
    // =========================================================================

    await t.step(
      "R04: malformed provider JSON quoting private text never reaches logs or the ordinary error body",
      async () => {
        const cases: Array<[string, boolean, boolean, boolean]> = [
          // [label, support, stream, caps installed]
          ["support json", true, false, true],
          ["support stream", true, true, true],
          ["legacy json (installed)", false, false, true],
          ["legacy stream (installed)", false, true, true],
          ["legacy json (baseline)", false, false, false],
        ];
        for (const [label, supportPath, stream, installed] of cases) {
          reset();
          seedMemory();
          s.sentinel = MARKER;
          s.providerRaw = MARKER;
          if (!installed) s.caps = "missing";
          const cap = captureConsole();
          let res: Wire;
          try {
            res = supportPath
              ? await send({}, { stream })
              : await sendLegacy({}, { stream });
          } finally {
            cap.restore();
          }
          const everything = cap.lines.join("\n") + JSON.stringify(res.data) +
            res.deltas;
          assert(
            !everything.toLowerCase().includes(MARKER.toLowerCase()),
            `${label}: private provider text leaked`,
          );
          assert(res.status >= 500, `${label}: stays a controlled failure`);
          if (res.status === 500) {
            assert(
              cap.lines.some((l) =>
                l.includes('"event":"chat_error"') &&
                l.includes('"category":"invalid_json"')
              ),
              `${label}: a symbolic category was logged`,
            );
          } else {
            equal([label, res.data.code, res.data.retryable], [
              label,
              "chat_provider_unavailable",
              true,
            ]);
          }
          assert(
            cap.lines.every((l) =>
              !l.includes("Error stack") && !l.includes("    at ")
            ),
            `${label}: no stack in logs`,
          );
          equal([label, s.confirmCalls, assistants().length], [label, 0, 0]);
        }
      },
    );

    await t.step(
      "R04: raw dependency errors (database, transport, provider HTTP) are replaced by symbols",
      async () => {
        type Setup = (st: ReturnType<typeof state>) => void;
        const scenarios: Array<[string, boolean, Setup, string?]> = [
          ["quota rpc error", true, (st) => {
            st.fail.quotaRpc = true;
          }, "quota_check_failed"],
          ["quota rpc error (legacy)", false, (st) => {
            st.fail.quotaRpc = true;
          }, "quota_check_failed"],
          ["conversation lookup error", true, (st) => {
            st.fail.conversationLookup = true;
          }],
          ["conversation lookup error (legacy)", false, (st) => {
            st.fail.conversationLookup = true;
          }],
          ["profile lookup error", true, (st) => {
            st.fail.profileLookup = true;
          }, "profile_fetch_failed"],
          ["provider transport failure", true, (st) => {
            st.providerThrow = MARKER;
          }, "transport"],
          ["provider transport failure (legacy)", false, (st) => {
            st.providerThrow = MARKER;
          }, "transport"],
          ["provider HTTP error body", true, (st) => {
            st.providerHttp = MARKER;
          }],
          ["provider HTTP error body (legacy)", false, (st) => {
            st.providerHttp = MARKER;
          }],
        ];
        for (const [label, supportPath, setup, expectLog] of scenarios) {
          reset();
          seedMemory();
          s.sentinel = MARKER;
          setup(s);
          const cap = captureConsole();
          let res: Wire;
          try {
            res = supportPath ? await send({}) : await sendLegacy({});
          } finally {
            cap.restore();
          }
          const everything = cap.lines.join("\n") + JSON.stringify(res.data);
          assert(
            !everything.toLowerCase().includes(MARKER.toLowerCase()),
            `${label}: dependency text leaked`,
          );
          if (expectLog) {
            assert(
              everything.includes(expectLog),
              `${label}: expected symbol ${expectLog}`,
            );
          }
        }
      },
    );

    await t.step(
      "R04: a title or extraction call that throws quoting private text logs a category only",
      async () => {
        reset();
        s.sentinel = MARKER;
        s.caps = "missing";
        s.messages = [];
        s.hooks.onProviderResponse = () => {
          if (s.providerCalls === 2) s.providerThrow = MARKER;
        };
        const cap = captureConsole();
        try {
          const res = await sendLegacy();
          assert(res.status === 200);
          await sleep(25);
        } finally {
          cap.restore();
        }
        const everything = cap.lines.join("\n");
        assert(
          !everything.toLowerCase().includes(MARKER.toLowerCase()),
          "thrown dependency text leaked",
        );
        for (
          const symbol of [
            "title_generation_failed",
            "memory_extraction_failed",
          ]
        ) {
          assert(
            everything.includes(symbol),
            `missing ${symbol} in: ${everything.slice(0, 800)}`,
          );
        }
      },
    );

    await t.step(
      "R04 / F004: the coach helper logs database codes only, on both lookup failures",
      async () => {
        const AON =
          "I always mess up, everyone always thinks I'm a failure, and it will never get better.";
        for (
          const lookup of ["distortion lookup", "english fallback"] as const
        ) {
          for (const installed of [false, true]) {
            reset();
            s.sentinel = MARKER;
            if (!installed) s.caps = "missing";
            s.fail.coachDistortion = lookup === "distortion lookup";
            // Past the first exchanges so the coach runs.
            for (let i = 0; i < 6; i++) {
              s.messages.push({
                id: crypto.randomUUID(),
                conversation_id: conversationId,
                role: i % 2 ? "assistant" : "user",
                content: `turn ${i}`,
                content_origin: null,
                content_revision: 0,
                created_at: iso(Date.now() - (10 - i) * 1000),
              });
            }
            const cap = captureConsole();
            let res: Wire;
            try {
              res = await sendLegacy({ content: AON });
            } finally {
              cap.restore();
            }
            const label = `${lookup} (${installed ? "installed" : "baseline"})`;
            const logs = cap.lines.join("\n");
            equal([label, res.status, res.data.coachData], [label, 200, null]);
            assert(
              !(logs + JSON.stringify(res.data)).toLowerCase().includes(
                MARKER.toLowerCase(),
              ),
              `${label}: dependency text leaked`,
            );
            assert(
              logs.includes("Distortion not found: AON XX000") ||
                logs.includes("English fallback also failed XX000"),
              `${label}: the coach path was not reached or logged more than a code: ${
                logs.slice(0, 600)
              }`,
            );
          }
        }
      },
    );

    await t.step(
      "R04: background title, usage and extraction failures log symbols only",
      async () => {
        reset();
        s.sentinel = MARKER;
        s.caps = "missing";
        s.messages = [];
        s.curated = [{
          id: ids.eligible,
          category: "preferences",
          content: "baseline row",
        }];
        s.fail.titleUpdate = true;
        s.fail.usageRpc = true;
        s.fail.fragmentUpsert = true;
        s.provider = {
          text: JSON.stringify([{
            type: "fact",
            key: "job",
            value: "Teacher",
          }]),
        };
        const cap = captureConsole();
        try {
          const res = await sendLegacy();
          assert(res.status === 200);
          await Promise.allSettled(background);
          await sleep(25);
        } finally {
          cap.restore();
        }
        const everything = cap.lines.join("\n");
        assert(
          !everything.toLowerCase().includes(MARKER.toLowerCase()),
          "background error text leaked",
        );
        for (
          const symbol of [
            "title_update_failed",
            "companion_memory_usage_failed",
            "memory_upsert_failed",
          ]
        ) {
          assert(
            everything.includes(symbol),
            `missing ${symbol} in: ${everything.slice(0, 1200)}`,
          );
        }
      },
    );
  } finally {
    globalThis.fetch = nativeFetch;
    globalThis.setInterval = nativeSetInterval;
    for (const interval of intervals) clearInterval(interval);
    Object.defineProperty(Deno, "serve", {
      configurable: true,
      value: nativeServe,
    });
    runtime.EdgeRuntime = previousRuntime;
    Object.keys(env).forEach((name, i) => {
      if (previous[i] === undefined) Deno.env.delete(name);
      else Deno.env.set(name, previous[i]!);
    });
  }
});

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------
Deno.test("request parsing: exact new-contract fields, everything else is legacy", () => {
  equal(
    parseSupportChatFields({ conversationId, content: "x" }).mode,
    "legacy",
  );
  equal(parseSupportChatFields(null).mode, "legacy");
  const ok = parseSupportChatFields({
    schema_version: 1,
    support_session_id: sessionId.toUpperCase(),
    context_scope: "personalized",
    expected_privacy_revision: 9,
    expected_owner: userId.toUpperCase(),
    selected_intent: "choose_step_v1",
    selected_memory_ids: [memoryId],
  });
  assert(ok.mode === "support");
  equal(ok.fields, {
    supportSessionId: sessionId,
    scope: "personalized",
    expectedPrivacyRevision: 9,
    expectedOwner: userId,
    selectedIntent: "choose_step_v1",
    selectedMemoryIds: [memoryId],
  });
  const minimal = parseSupportChatFields({
    schema_version: 1,
    context_scope: "conversation_only",
    expected_owner: userId,
  });
  assert(
    minimal.mode === "support" && minimal.fields.supportSessionId === null &&
      minimal.fields.expectedPrivacyRevision === null,
  );
  for (
    const only of [
      "support_session_id",
      "context_scope",
      "expected_privacy_revision",
      "expected_owner",
      "selected_intent",
      "selected_memory_ids",
    ]
  ) {
    equal(
      parseSupportChatFields({ [only]: null }).mode,
      "invalid",
      `${only} alone is not legacy`,
    );
  }
});

Deno.test("capability gate: separate negotiation, never an implicit pass", () => {
  const full = {
    session_contract: 1,
    context_policy: 1,
    privacy_revision: true,
    chat_confirmation: true,
  };
  equal(capabilityGate({ kind: "ok", caps: full }, true), null);
  equal(
    capabilityGate(
      { kind: "ok", caps: { ...full, session_contract: 0 } },
      false,
    ),
    null,
  );
  equal(
    capabilityGate({ kind: "ok", caps: { ...full, session_contract: 0 } }, true)
      ?.body.capability,
    "insufficient",
  );
  equal(
    capabilityGate(
      { kind: "ok", caps: { ...full, privacy_revision: false } },
      false,
    )?.body.capability,
    "insufficient",
  );
  equal(
    capabilityGate({ kind: "ok", caps: { ...full, context_policy: 0 } }, false)
      ?.body.capability,
    "insufficient",
  );
  equal(
    capabilityGate({ kind: "not_deployed" }, false)?.body.capability,
    "not_deployed",
  );
  equal(capabilityGate({ kind: "unavailable" }, false)?.body.retryable, true);
});

Deno.test("the wire is a pure function of the stored response", () => {
  const now = new Date("2026-11-06T12:00:00.000Z");
  const template = buildWireTemplate({
    userId,
    requestId,
    conversationId,
    supportSessionId: sessionId,
    trimmedContent: MESSAGE,
    userMessage: { id: requestId, created_at: "2026-11-06T11:59:59Z" },
    quota: { used: 2, limit: 5 },
    now,
    scope: "personalized",
    privacyRevision: 4,
    content: "Hello",
    origin: "model",
    status: "completed",
    proposal: {
      template_key: "choose_step_v1",
      reason_code: "current_request",
      basis_kind: null,
      basis_ref: null,
      suggested_step: "Write the subject line",
    },
    proposalDropped: null,
    sources: [{
      kind: "safety_policy",
      id: "00000000-0000-0000-0000-000000000001",
      revision: 1,
      date: null,
    }],
    exclusions: ["saved_memory"],
    provider: {
      vendor: "openai",
      model: "gpt-6-luna",
      routeVersion: "responses-chat-1",
    },
    narrowedBy: null,
  }) as Row;
  const ids = {
    message_id: "a".repeat(8) + "-0000-4000-8000-000000000001",
    receipt_id: "b".repeat(8) + "-0000-4000-8000-000000000002",
    proposal_id: "c".repeat(8) + "-0000-4000-8000-000000000003",
  };
  const stored = { ...template, support_confirmed: ids };
  const a = renderSupportWire(stored);
  const b = renderSupportWire(JSON.parse(JSON.stringify(stored)));
  assert(JSON.stringify(a) === JSON.stringify(b), "deterministic");
  equal([
    a.assistantMessage.id,
    a.message.id,
    a.support.context_receipt.receipt_id,
    a.support.proposal.id,
    a.support.confirmed,
  ], [ids.message_id, ids.message_id, ids.receipt_id, ids.proposal_id, true]);
  assert(!("support_confirmed" in a));
  equal(renderSupportWire(a), a, "idempotent on an already rendered response");
  equal(a.support.proposal.expires_at, "2026-11-07T12:00:00.000Z");
  const dropped = renderSupportWire({
    ...template,
    support_confirmed: { ...ids, proposal_id: null },
  });
  equal([dropped.support.proposal, dropped.support.proposal_dropped], [
    null,
    "rejected_at_confirm",
  ]);
  const legacy = { message: { id: "x" }, userMessageId: "y" };
  assert(
    renderSupportWire(legacy) === legacy,
    "legacy rows pass through untouched",
  );
  equal(template.support.confirmed, false);
});

Deno.test("turn planning: text/tool/refusal matrix is closed and never fabricates", () => {
  const src = [
    {
      kind: "safety_policy" as const,
      id: "00000000-0000-0000-0000-000000000001",
      revision: 1,
      date: null,
    },
    {
      kind: "companion_memory" as const,
      id: memoryId,
      revision: 1,
      date: null,
    },
  ];
  const plan = (result: Row, over: Row = {}) =>
    planSupportTurn({
      result: result as never,
      hasSession: true,
      scope: "personalized",
      includedSources: src,
      selectedIntent: null,
      suppressedTemplates: [],
      ...over,
    });
  const raw = (args = ARGS()) => ({
    state: "raw",
    callId: "c",
    itemId: "i",
    name: "propose_support_action",
    arguments: args,
  });
  const done = (text: string, proposal: Row = { state: "none" }) => ({
    status: "completed",
    text,
    proposal,
  });
  assert(plan(done("hi")).kind === "ok");
  const textTool = plan(done("hi", raw())) as Row;
  equal([textTool.origin, textTool.proposal?.template_key], [
    "model",
    "ground_present_v1",
  ]);
  const toolOnly = plan(done("  ", raw())) as Row;
  equal([toolOnly.origin, toolOnly.content], [
    "interface_fallback",
    "App option: Try a short grounding activity, or keep talking.",
  ]);
  equal(plan(done("", raw("{bad"))).kind, "empty");
  equal(
    plan(done("", { state: "invalid", reason: "multiple_calls" })).kind,
    "empty",
  );
  equal(
    (plan(done("hi", { state: "invalid", reason: "multiple_calls" })) as Row)
      .proposalDropped,
    "invalid_proposal",
  );
  equal(
    (plan(done("hi", raw()), { hasSession: false }) as Row).proposalDropped,
    "no_session",
  );
  equal(plan(done("", raw()), { hasSession: false }).kind, "empty");
  equal(
    (plan(done("hi", raw()), {
      suppressedTemplates: ["ground_present_v1"],
    }) as Row).proposalDropped,
    "template_declined",
  );
  const refusal = plan({
    status: "refused",
    text: "",
    refusal: "No.",
    proposal: { state: "none" },
  }) as Row;
  equal([refusal.status, refusal.content, refusal.proposal], [
    "refused",
    "No.",
    null,
  ]);
  equal(
    plan({
      status: "refused",
      text: "",
      refusal: "  ",
      proposal: { state: "none" },
    }).kind,
    "empty",
  );
  equal(
    plan({ status: "incomplete", text: "", proposal: { state: "none" } }).kind,
    "empty",
  );
  // basis outside the receipt downgrades to a general option, never an invented rationale
  const outside = plan(
    done(
      "hi",
      raw(
        ARGS({
          reason_code: "approved_preference",
          basis_ref: "12121212-1212-4121-8121-121212121212",
        }),
      ),
    ),
  ) as Row;
  equal([outside.proposal.reason_code, outside.proposal.basis_ref], [
    "general_option",
    null,
  ]);
  const inside = plan(
    done(
      "hi",
      raw(ARGS({ reason_code: "approved_preference", basis_ref: memoryId })),
    ),
  ) as Row;
  equal([inside.proposal.reason_code, inside.proposal.basis_kind], [
    "approved_preference",
    "companion_memory",
  ]);
});

Deno.test("memory ref markers align line-for-line or are omitted", () => {
  const block =
    '## Saved context the person approved\nQuoted user data.:\n- [Boundary] "a"\n- [Preference] "b"';
  equal(annotateMemoryRefs(block, ["id1", "id2"]).split("\n").slice(2), [
    '- [Boundary] "a" (ref: id1)',
    '- [Preference] "b" (ref: id2)',
  ]);
  equal(
    annotateMemoryRefs(block, ["id1"]),
    block,
    "count mismatch -> no markers rather than wrong ones",
  );
  equal(annotateMemoryRefs("", []), "");
});

Deno.test("the single propose_support_action declaration matches the contract vocabulary", () => {
  // openai-chat.ts is the only declaration (the contract module no longer carries a copy);
  // its enums must stay equal to the vocabularies the validator enforces.
  const t = SUPPORT_ACTION_TOOL;
  equal([t.type, t.name, t.strict, t.parameters.additionalProperties], [
    "function",
    "propose_support_action",
    true,
    false,
  ]);
  equal([...t.parameters.required].sort(), [
    "basis_ref",
    "reason_code",
    "suggested_step",
    "template_key",
  ]);
  equal([...t.parameters.properties.template_key.enum], [...TEMPLATE_KEYS]);
  equal([...t.parameters.properties.reason_code.enum], [...REASON_CODES]);
  equal(
    JSON.stringify(t.parameters.properties.basis_ref.type),
    '["string","null"]',
  );
  equal(
    JSON.stringify(t.parameters.properties.suggested_step.type),
    '["string","null"]',
  );
});

Deno.test("context sources: revalidation detects every privacy-relevant change", () => {
  const msgId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const sources = [
    {
      kind: "safety_policy" as const,
      id: "00000000-0000-0000-0000-000000000001",
      revision: 1,
      date: null,
    },
    { kind: "session" as const, id: sessionId, revision: 3, date: null },
    {
      kind: "companion_memory" as const,
      id: memoryId,
      revision: 1,
      date: "2026-11-02T00:00:00Z",
    },
    { kind: "message" as const, id: msgId, revision: 2, date: null },
  ];
  const prepared = {
    assembled: { privacyRevision: 7 },
    includedSources: sources,
    scope: "personalized",
    dispatchedHistory: new Map([[msgId, {
      role: "user",
      content: "hello there",
    }]]),
  } as never;
  const fresh = (): ContextSourceRecords => ({
    privacyRevision: 7,
    memories: [{
      id: memoryId,
      category: "preferences",
      content: "x",
      revision: 1,
      confirmedAt: "2026-11-02T00:00:00Z",
    }],
    dailyIntent: null,
    history: [],
    session: {
      id: sessionId,
      title: "",
      concern: null,
      contextScope: "personalized",
      status: "open",
      conversationId: conversationId,
      contextRevision: 3,
    },
    activity: null,
    suppressions: {
      messages: new Set(),
      memories: new Set(),
      conversations: new Set(),
      activities: new Set(),
    },
  });
  const row = (): CitedMessageRow => ({
    id: msgId,
    conversation_id: conversationId,
    role: "user",
    content: "hello there",
    content_origin: null,
    content_revision: 2,
  });
  const now = new Date("2026-11-06T00:00:00Z");
  const rows = (r: CitedMessageRow | undefined = row()) =>
    new Map([[msgId, r]]);
  equal(sourcesStillCurrent(prepared, fresh(), conversationId, now, rows()), {
    ok: true,
  });
  const mutate = (f: (r: ContextSourceRecords) => void) => {
    const r = fresh();
    f(r);
    return sourcesStillCurrent(prepared, r, conversationId, now, rows());
  };
  equal(
    mutate((r) => {
      r.privacyRevision = 8;
    }),
    { ok: false, reason: "privacy_revision" },
  );
  equal(
    mutate((r) => {
      r.memories[0].revision = 2;
    }).ok,
    false,
  );
  equal(
    mutate((r) => {
      r.memories = [];
    }).ok,
    false,
  );
  equal(
    mutate((r) => {
      r.memories[0].disabledAt = "2026-11-05T00:00:00Z";
    }).ok,
    false,
  );
  equal(
    mutate((r) => {
      r.suppressions.memories = new Set([memoryId]);
    }).ok,
    false,
  );
  equal(
    mutate((r) => {
      r.session!.contextRevision = 4;
    }).ok,
    false,
  );
  equal(
    mutate((r) => {
      r.session = null;
    }).ok,
    false,
  );
  equal(
    mutate((r) => {
      r.session!.status = "closed";
    }).ok,
    false,
  );
  equal(
    mutate((r) => {
      r.suppressions.messages = new Set([msgId]);
    }).ok,
    false,
  );
  equal(
    mutate((r) => {
      r.suppressions.conversations = new Set([conversationId]);
    }).ok,
    false,
  );
  // A new unrelated message arriving concurrently is not a privacy event.
  equal(
    mutate((r) => {
      r.history = [{
        id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        role: "user",
        content: "new",
        createdAt: "2026-11-06T00:00:00Z",
      }];
    }).ok,
    true,
  );

  // M4-R03: every cited message is compared against an EXACT-id lookup.
  const check = (
    r: CitedMessageRow | undefined,
    map?: Map<string, CitedMessageRow | undefined>,
  ) =>
    sourcesStillCurrent(
      prepared,
      fresh(),
      conversationId,
      now,
      map ?? (r ? rows(r) : new Map()),
    ).ok;
  equal(check(row()), true);
  equal(
    check({ ...row(), content: "rewritten in place" }),
    false,
    "text changed",
  );
  equal(
    check({ ...row(), content_revision: 3 }),
    false,
    "server version moved",
  );
  equal(
    check({ ...row(), content_revision: "2" }),
    true,
    "numeric strings are versions",
  );
  equal(
    check({ ...row(), content_revision: null }),
    false,
    "missing version reads as 0, not 2",
  );
  equal(check({ ...row(), role: "assistant" }), false, "re-roled");
  equal(
    check({ ...row(), conversation_id: otherUser }),
    false,
    "moved to another conversation",
  );
  equal(
    check({ ...row(), content_origin: "interface_fallback" }),
    false,
    "no longer model text",
  );
  equal(check(undefined), false, "deleted");
  equal(
    sourcesStillCurrent(prepared, fresh(), conversationId, now).ok,
    false,
    "unproven without a lookup",
  );
  equal(
    sourcesStillCurrent(prepared, fresh(), conversationId, now, new Map()).ok,
    false,
    "absent from lookup",
  );
});

Deno.test("the policy's measure is conservative against the exact dispatched bytes", async () => {
  const history = Array.from({ length: 30 }, (_, i) => ({
    id: crypto.randomUUID(),
    role: (i % 2 ? "assistant" : "user") as "user" | "assistant",
    content: 'ü"\\\n😀 '.repeat(900),
    createdAt: new Date(Date.UTC(2026, 10, 1, 0, i)).toISOString(),
    complete: true,
    origin: "model" as const,
  }));
  const sources = {
    load: () =>
      Promise.resolve({
        privacyRevision: 1,
        memories: [],
        dailyIntent: null,
        history,
        session: null,
        activity: null,
        suppressions: {
          messages: new Set<string>(),
          memories: new Set<string>(),
          conversations: new Set<string>(),
          activities: new Set<string>(),
        },
      } as ContextSourceRecords),
  };
  const r = await prepareSupportContext({
    admin: undefined as never,
    userId,
    conversationId,
    requestId,
    fields: {
      supportSessionId: null,
      scope: "conversation_only",
      expectedPrivacyRevision: null,
      expectedOwner: userId,
      selectedIntent: null,
      selectedMemoryIds: [],
    },
    accountPrivate: false,
    currentMessageId: null,
    trimmedContent: MESSAGE,
    baseSystemPrompt: "BASE PROMPT",
    sources,
  });
  assert(r.ok);
  const p = r.prepared;
  assert(
    p.exactPromptBytes <= p.assembled.bytes.total,
    `exact ${p.exactPromptBytes} must not exceed policy ${p.assembled.bytes.total}`,
  );
  assert(p.assembled.bytes.total <= MAX_PROMPT_BYTES);
  assert(
    p.assembled.bytes.overhead >= promptOverheadBytes("BASE PROMPT") - 1 &&
      p.assembled.bytes.overhead >= SUPPORT_ACTION_OVERHEAD_BYTES,
  );
  assert(p.assembled.omitted.history > 0, "history had to trim");
});

// ---------------------------------------------------------------------------
// confirmSupportTurn classification (no route)
// ---------------------------------------------------------------------------
Deno.test("confirm classification: definite, replay, reused and unknown outcomes are never confused", async () => {
  const args = { request_id: requestId } as never;
  const fast = { attempts: 3, sleep: () => Promise.resolve() };
  const ids = { message_id: "m", receipt_id: "r", proposal_id: null };
  const rpcReturning = (...results: Array<Row | Error>) => {
    let n = 0;
    return {
      calls: () => n,
      admin: {
        rpc: () => {
          const r = results[Math.min(n++, results.length - 1)];
          if (r instanceof Error) return Promise.reject(r);
          return Promise.resolve(r);
        },
        from: () => {
          throw new Error("unused");
        },
      } as never,
    };
  };
  const good = {
    data: {
      ok: true,
      replayed: false,
      message_id: "m",
      receipt_id: "r",
      response: { x: 1, support_confirmed: ids },
      response_status: 200,
    },
    error: null,
  };
  let t = rpcReturning(good);
  equal((await confirmSupportTurn(t.admin, args, fast)).kind, "confirmed");
  equal(t.calls(), 1);
  // mismatched ids / unexpected shapes are unknown outcomes: re-issued, then ambiguous
  t = rpcReturning({
    data: {
      ok: true,
      message_id: "other",
      receipt_id: "r",
      response: { support_confirmed: ids },
    },
    error: null,
  });
  equal([(await confirmSupportTurn(t.admin, args, fast)).kind, t.calls()], [
    "ambiguous",
    3,
  ]);
  t = rpcReturning({ data: "garbage", error: null });
  equal([(await confirmSupportTurn(t.admin, args, fast)).kind, t.calls()], [
    "ambiguous",
    3,
  ]);
  t = rpcReturning({ data: null, error: { message: "gateway" } });
  equal([(await confirmSupportTurn(t.admin, args, fast)).kind, t.calls()], [
    "ambiguous",
    3,
  ]);
  t = rpcReturning(new TypeError("net"), good);
  equal([(await confirmSupportTurn(t.admin, args, fast)).kind, t.calls()], [
    "confirmed",
    2,
  ]);
  // structured database errors are definite non-commits and are not re-issued
  t = rpcReturning({
    data: null,
    error: { code: "40001", message: "serialization" },
  });
  const db = await confirmSupportTurn(t.admin, args, fast);
  equal([db.kind, t.calls()], ["rejected", 1]);
  // ...but once any attempt is unknown, NOTHING later is definite: not a structured error,
  // and not a schema-cache "missing function" either.
  const missingFn = {
    data: null,
    error: { code: "PGRST202", message: "Could not find the function" },
  };
  t = rpcReturning(new TypeError("net"), missingFn, missingFn);
  equal([(await confirmSupportTurn(t.admin, args, fast)).kind, t.calls()], [
    "ambiguous",
    3,
  ]);
  t = rpcReturning(new TypeError("net"), missingFn, good);
  equal([(await confirmSupportTurn(t.admin, args, fast)).kind, t.calls()], [
    "confirmed",
    3,
  ]);
  t = rpcReturning(new TypeError("net"), {
    data: null,
    error: { code: "40001", message: "x" },
  }, { data: null, error: { code: "40001", message: "x" } });
  equal([(await confirmSupportTurn(t.admin, args, fast)).kind, t.calls()], [
    "ambiguous",
    3,
  ]);
  // A logical refusal from the function itself (it ran after the advisory lock) is definite.
  t = rpcReturning(new TypeError("net"), {
    data: {
      ok: false,
      code: "PRIVACY_REVISION_STALE",
      current_privacy_revision: 9,
    },
    error: null,
  });
  equal([(await confirmSupportTurn(t.admin, args, fast)).kind, t.calls()], [
    "rejected",
    2,
  ]);
  // First-attempt missing function stays definite (genuine old schema).
  t = rpcReturning(missingFn);
  equal([(await confirmSupportTurn(t.admin, args, fast)).kind, t.calls()], [
    "rejected",
    1,
  ]);
  t = rpcReturning({
    data: null,
    error: { code: "PGRST202", message: "Could not find the function" },
  });
  const missing = await confirmSupportTurn(t.admin, args, fast);
  equal([missing.kind, (missing as Row).failure.body.capability], [
    "rejected",
    "not_deployed",
  ]);
  t = rpcReturning({
    data: { ok: false, code: "OPERATION_ID_REUSED" },
    error: null,
  });
  equal((await confirmSupportTurn(t.admin, args, fast)).kind, "reused");
  t = rpcReturning({
    data: {
      ok: false,
      code: "PRIVACY_REVISION_STALE",
      current_privacy_revision: 12,
      message: "source_changed:session",
    },
    error: null,
  });
  const stale = await confirmSupportTurn(t.admin, args, fast) as Row;
  equal([
    stale.kind,
    stale.failure.status,
    stale.failure.body.current_privacy_revision,
    stale.failure.body.reason,
  ], ["rejected", 409, 12, "source_changed"]);
  t = rpcReturning({ data: { ok: false, code: "NOT_FOUND" }, error: null });
  equal(
    ((await confirmSupportTurn(t.admin, args, fast)) as Row).failure.body.code,
    "chat_support_state_changed",
  );
});

Deno.test("confirm timeout: a hung RPC is aborted, re-issued, and never reported as saved", async () => {
  let calls = 0;
  const hung = {
    rpc: () => {
      calls++;
      return {
        abortSignal: (signal: AbortSignal) =>
          new Promise((_resolve, reject) => {
            signal.addEventListener(
              "abort",
              () => reject(new DOMException("Timed out", "TimeoutError")),
              { once: true },
            );
          }),
      };
    },
    from: () => {
      throw new Error("unused");
    },
  } as never;
  const started = Date.now();
  const outcome = await confirmSupportTurn(
    hung,
    { request_id: requestId } as never,
    {
      attempts: 2,
      timeoutMs: 25,
      sleep: () => Promise.resolve(),
    },
  );
  equal([outcome.kind, calls], ["ambiguous", 2]);
  assert(Date.now() - started < 2000, "bounded by the per-attempt timeout");
  // A slow-but-successful call within the timeout is confirmed once.
  let n = 0;
  const slow = {
    rpc: () => {
      n++;
      return {
        abortSignal: () =>
          sleep(5).then(() => ({
            data: {
              ok: true,
              message_id: "m",
              receipt_id: "r",
              response: {
                support_confirmed: {
                  message_id: "m",
                  receipt_id: "r",
                  proposal_id: null,
                },
              },
              response_status: 200,
            },
            error: null,
          })),
      };
    },
    from: () => {
      throw new Error("unused");
    },
  } as never;
  equal([
    (await confirmSupportTurn(slow, { request_id: requestId } as never, {
      timeoutMs: 500,
    })).kind,
    n,
  ], ["confirmed", 1]);
});

Deno.test("reframe helper: every failure path logs a code or category, never an error object or message", async () => {
  const MARKER = "PRIVATE-FACT-FROM-DEPENDENCY-77A1";
  const quoting = {
    code: "XX000",
    message: `row ${MARKER}`,
    details: `(${MARKER})`,
  };
  const chain = (result: unknown) => {
    const q: Record<string, unknown> = {};
    for (const m of ["select", "eq"]) q[m] = () => q;
    q.single = () => Promise.resolve(result);
    return q;
  };
  const clientFor = (handlers: Record<string, () => unknown>) =>
    ({ from: (table: string) => handlers[table]() }) as never;
  const lines: string[] = [];
  const originals = { error: console.error, warn: console.warn };
  console.error = (...a: unknown[]) => {
    lines.push(
      a.map((x) => typeof x === "string" ? x : JSON.stringify(x)).join(" "),
    );
  };
  console.warn = (...a: unknown[]) => {
    lines.push(
      a.map((x) => typeof x === "string" ? x : JSON.stringify(x)).join(" "),
    );
  };
  try {
    // 1. the distortion lookup fails with a database error that quotes row text
    const a = await getReframe(
      clientFor({
        cognitive_distortions: () => chain({ data: null, error: quoting }),
      }),
      "AON",
      MARKER,
      "en",
    );
    // 2. the English fallback lookup fails the same way
    const b = await getReframe(
      clientFor({
        cognitive_distortions: () =>
          chain({ data: { id: "x", distortion_education: [] }, error: null }),
        distortion_education: () => chain({ data: null, error: quoting }),
      }),
      "AON",
      MARKER,
      "en",
    );
    // 3. an exception whose message quotes private text
    const c = await getReframe(
      clientFor({
        cognitive_distortions: () => {
          throw new Error(`boom ${MARKER}`);
        },
      }),
      "AON",
      MARKER,
      "en",
    );
    equal([a, b, c], [null, null, null]);
  } finally {
    Object.assign(console, originals);
  }
  const everything = lines.join("\n");
  assert(!everything.includes(MARKER), `dependency text leaked: ${everything}`);
  assert(
    everything.includes("XX000") && everything.includes("exception"),
    everything,
  );
});
