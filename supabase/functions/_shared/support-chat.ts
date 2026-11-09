// Support-session text chat (docs/SUPPORT_SESSION_SPEC.md 8.2-8.6, 9.7, 10.1).
//
// Canonical M4 server integration for the `chat` Edge function. It composes the existing
// pieces; it adds no second policy:
//   * context   ... support-context-policy.ts (assembleContext / createSupabaseContextSources)
//   * provider  ... openai-chat.ts generateChatResult (ONE Responses invocation, strict
//                   propose_support_action, 500 output tokens, 128,000 serialized bytes)
//   * proposal  ... support-contract.ts validateSupportActionProposal
//   * atomic save ... SQL support_confirm_chat_turn (service role; final authority)
//
// Nothing here executes or starts an activity: a proposal is data the person must
// explicitly accept through `support-session` (accept_proposal).
//
// Logging is content-free: event names, status codes and counts only. Message text,
// memory text, model output and tool arguments are never logged or thrown in errors.

import {
  CHAT_MODEL,
  type ChatMessage,
  type ChatResult,
  generateChatResult,
  MAX_PROMPT_BYTES,
  SUPPORT_ACTION_OVERHEAD_BYTES,
} from "./openai-chat.ts";
import { sanitizeForPrompt } from "./sanitize.ts";
import {
  assembleContext,
  type AssembledContext,
  byteLength,
  CONTEXT_LIMITS,
  type ContextFailure,
  type ContextSourceRecords,
  type ContextSources,
  createSupabaseContextSources,
  defaultContextDeps,
  memoryExclusion,
  type MemorySourceRecord,
  renderTextContext,
} from "./support-context-policy.ts";
import {
  type ConfirmChatTurnArgs,
  type ContextScope,
  type ContextSourceRef,
  interfaceFallbackText,
  isUuid,
  SAFETY_POLICY_SOURCE_ID,
  SUPPORT_LIMITS,
  TEMPLATE_KEYS,
  type TemplateKey,
  type ValidatedProposal,
  validateSupportActionProposal,
} from "./support-contract.ts";

// ---------------------------------------------------------------------------
// Constants (wire-visible values are documented in docs/SUPPORT_CHAT_WIRE.md)
// ---------------------------------------------------------------------------
export const SUPPORT_CHAT_CONTRACT = 1 as const;
/** The route that ACTUALLY serves main chat. Independent of AI_PROVIDER (spec 2.3). */
export const SUPPORT_CHAT_ROUTE = {
  vendor: "openai",
  model: CHAT_MODEL,
  routeVersion: "responses-chat-1",
} as const;
export const SUPPORT_CHAT_MAX_OUTPUT_TOKENS = 500;
/**
 * The 4,000-character user limit is enforced by the handler on the RAW message. The policy
 * measures the SANITIZED message (escapes and redaction markers can expand it up to ~3.4x),
 * so its own character guard is widened to a safe upper bound instead of rejecting a legal
 * message. The 128,000-byte fit is still measured exactly on what is dispatched.
 */
export const SANITIZED_MESSAGE_CHAR_BOUND = 16_000;
export const MAX_SELECTED_MEMORIES = 5;
/** Bytes reserved for the "(ref: <uuid>)" markers appended to <= 20 saved-memory lines. */
const REF_ALLOWANCE_BYTES = SUPPORT_LIMITS.confirmedMemoryLimit * 48;
/** Conservative framing slack (array separators, braces) on top of measured overhead. */
const FRAMING_MARGIN_BYTES = 64;
export const CONFIRM_ATTEMPTS = 3;
export const CONFIRM_TIMEOUT_MS = 8_000;

export function supportLog(
  event: string,
  fields: Record<string, unknown> = {},
) {
  // Callers pass only enumerated, content-free values.
  console.log(
    JSON.stringify({ fn: "chat", contract: "support", event, ...fields }),
  );
}

// ---------------------------------------------------------------------------
// Content-free error vocabulary (M4-R04). Raw `error.message`, database error objects and
// stacks can carry provider/model/personal text (a JSON decode error quotes the invalid
// body; a database error can quote a row). Handlers log only these symbols.
// ---------------------------------------------------------------------------
const OWN_ERROR_CODES = new Set([
  "AI_DAILY_BUDGET_REACHED",
  "AI_EMPTY_RESPONSE",
  "AI_EMPTY_STREAM",
  "AI_INCOMPLETE_RESPONSE",
  "AI_INCOMPLETE_STREAM",
  "AI_STREAM_FAILED",
  "AI_TERMINAL_FAILED",
  "ASSISTANT_MESSAGE_NOT_SAVED",
  "CHAT_CONTEXT_TOO_LARGE",
  "INVALID_OUTPUT_LIMIT",
  "QUOTA_ADMISSION_UNCONFIRMED",
  "RECEIPT_NOT_SAVED",
  "RETRY_MESSAGE_UNCONFIRMED",
  "USER_MESSAGE_NOT_SAVED",
]);
const SAFE_ERROR_NAMES = new Set([
  "AbortError",
  "TimeoutError",
  "SyntaxError",
  "TypeError",
  "RangeError",
  "MonthlyAIBudgetExhaustedError",
  "MonthlyAIBudgetUnavailableError",
]);

/** One of a small fixed set of symbols; never any part of an error message or stack. */
export function errorCategory(error: unknown): string {
  if (error instanceof Response) return "http_response";
  if (!(error instanceof Error)) return "unexpected";
  if (error.name === "AbortError") return "aborted";
  if (error.name === "TimeoutError") return "timeout";
  if (error instanceof SyntaxError) return "invalid_json";
  // Only this codebase's own constant codes are passed through (never free text).
  if (/^AI_HTTP_\d{3}$/.test(error.message)) return error.message;
  if (OWN_ERROR_CODES.has(error.message)) return error.message;
  if (error instanceof TypeError) return "transport";
  return SAFE_ERROR_NAMES.has(error.name) ? error.name : "unexpected";
}

/** A PostgREST/PostgreSQL code (for example 23505, PGRST116), or "unknown". Never the message. */
export function dbCode(error: unknown): string {
  const code = typeof error === "object" && error !== null
    ? (error as { code?: unknown }).code
    : undefined;
  return typeof code === "string" && /^[A-Za-z0-9_]{1,16}$/.test(code)
    ? code
    : "unknown";
}

/** Content-free failure log: an event name plus symbols, numbers and booleans only. */
export function logFailure(
  event: string,
  fields: Record<string, string | number | boolean | null> = {},
) {
  console.error(JSON.stringify({ fn: "chat", event, ...fields }));
}

// ---------------------------------------------------------------------------
// Failures: content-free bodies shaped for the existing chat error contract.
// `code` keeps the chat_* vocabulary; `support_code` carries the M3 SupportErrorCode.
// ---------------------------------------------------------------------------
export interface SupportChatFailure {
  status: number;
  body: Record<string, unknown>;
}

function failure(
  status: number,
  code: string,
  supportCode: string,
  message: string,
  retryable: boolean,
  extra: Record<string, unknown> = {},
): SupportChatFailure {
  return {
    status,
    body: {
      error: message,
      message,
      code,
      support_code: supportCode,
      retryable,
      ...extra,
    },
  };
}

export const FAILURES = {
  invalid: (message: string) =>
    failure(
      400,
      "chat_support_invalid_request",
      "INVALID_PAYLOAD",
      message,
      false,
    ),
  schema: () =>
    failure(
      400,
      "chat_support_schema_unsupported",
      "INVALID_PAYLOAD",
      "Unsupported support-chat schema_version.",
      false,
    ),
  owner: () =>
    failure(
      409,
      "chat_owner_mismatch",
      "AUTH_REQUIRED",
      "This request was prepared for a different account.",
      false,
    ),
  sessionClosed: () =>
    failure(
      409,
      "chat_support_session_closed",
      "NOT_FOUND",
      "This session is closed. Start a new session to continue.",
      false,
    ),
  unavailable: (capability: "not_deployed" | "unavailable" | "insufficient") =>
    failure(
      503,
      "chat_support_unavailable",
      "TEMPORARY_FAILURE",
      "Private chat is not available right now. Your draft is kept.",
      capability === "unavailable",
      { capability },
    ),
  stale: (
    current?: number,
    reason: "privacy_revision" | "source_changed" = "privacy_revision",
  ) =>
    failure(
      409,
      "chat_privacy_revision_stale",
      "PRIVACY_REVISION_STALE",
      "Your privacy settings changed. Review the shared context, then send again.",
      true,
      {
        reason,
        ...(current !== undefined ? { current_privacy_revision: current } : {}),
      },
    ),
  contextUnavailable: () =>
    failure(
      503,
      "chat_context_unavailable",
      "TEMPORARY_FAILURE",
      "The conversation context could not be prepared. Nothing was sent.",
      true,
    ),
  tooLarge: (boundaries = false) =>
    failure(
      413,
      "chat_context_too_large",
      "INVALID_PAYLOAD",
      boundaries
        ? "Saved boundaries do not fit. Choose a narrower context scope."
        : "Use a shorter message or a narrower context selection.",
      false,
    ),
  confirmUnavailable: () =>
    failure(
      503,
      "chat_confirm_unavailable",
      "TEMPORARY_FAILURE",
      "The reply could not be saved. You can explicitly retry this message.",
      true,
    ),
  confirmRejected: (supportCode: string) =>
    failure(
      409,
      "chat_support_state_changed",
      supportCode,
      "The conversation changed before the reply could be saved.",
      false,
    ),
  unconfirmed: () =>
    failure(
      503,
      "chat_request_unconfirmed",
      "TEMPORARY_FAILURE",
      "Request outcome unconfirmed. Reload history before sending again.",
      false,
    ),
};

// ---------------------------------------------------------------------------
// Request parsing (new-contract fields) and the capability handshake
// ---------------------------------------------------------------------------
export const SUPPORT_REQUEST_KEYS = [
  "schema_version",
  "support_session_id",
  "context_scope",
  "expected_privacy_revision",
  "expected_owner",
  "selected_intent",
  "selected_memory_ids",
] as const;

export interface SupportChatFields {
  supportSessionId: string | null;
  scope: ContextScope;
  expectedPrivacyRevision: number | null;
  expectedOwner: string;
  selectedIntent: TemplateKey | null;
  selectedMemoryIds: string[];
}
export type SupportChatMode =
  | { mode: "legacy" }
  | { mode: "support"; fields: SupportChatFields }
  | { mode: "invalid"; failure: SupportChatFailure };

const LAX_UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isObj = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);

/** `{op:"capabilities", schema_version:1}`: proves the DEPLOYED chat function enforces the contract. */
export function isCapabilityProbe(body: unknown): boolean {
  return isObj(body) && body.op === "capabilities";
}

/**
 * A request is new-contract when ANY new key is present. schema_version must then be 1, so a
 * privacy-bearing field can never be silently ignored by being mistaken for a legacy request.
 */
export function parseSupportChatFields(body: unknown): SupportChatMode {
  if (
    !isObj(body) || !SUPPORT_REQUEST_KEYS.some((k) => Object.hasOwn(body, k))
  ) {
    return { mode: "legacy" };
  }
  if (body.schema_version !== SUPPORT_CHAT_CONTRACT) {
    return { mode: "invalid", failure: FAILURES.schema() };
  }
  const bad = (m: string): SupportChatMode => ({
    mode: "invalid",
    failure: FAILURES.invalid(m),
  });

  const sid = body.support_session_id ?? null;
  if (sid !== null && !isUuid(sid)) {
    return bad("support_session_id must be a UUID or null.");
  }

  const scope = body.context_scope;
  if (scope !== "conversation_only" && scope !== "personalized") {
    return bad("context_scope must be conversation_only or personalized.");
  }
  if (
    typeof body.expected_owner !== "string" ||
    !LAX_UUID.test(body.expected_owner)
  ) {
    return bad("expected_owner must be the signed-in user's id.");
  }
  const rev = body.expected_privacy_revision ?? null;
  if (
    rev !== null &&
    !(typeof rev === "number" && Number.isInteger(rev) && rev >= 1 &&
      rev <= 999_999_999_999_999)
  ) return bad("expected_privacy_revision must be a positive integer or null.");
  if (scope === "personalized" && rev === null) {
    return bad(
      "expected_privacy_revision is required for personalized context.",
    );
  }
  const intent = body.selected_intent ?? null;
  if (
    intent !== null &&
    !(TEMPLATE_KEYS as readonly string[]).includes(intent as string)
  ) {
    return bad("selected_intent is not an allowed template.");
  }
  const ids = body.selected_memory_ids ?? [];
  if (
    !Array.isArray(ids) || ids.length > MAX_SELECTED_MEMORIES ||
    !ids.every((id) => isUuid(id))
  ) return bad("selected_memory_ids must list at most 5 UUIDs.");
  if (scope === "conversation_only" && ids.length > 0) {
    return bad("selected_memory_ids need personalized context.");
  }

  return {
    mode: "support",
    fields: {
      supportSessionId: sid === null ? null : (sid as string).toLowerCase(),
      scope,
      expectedPrivacyRevision: rev as number | null,
      expectedOwner: body.expected_owner.toLowerCase(),
      selectedIntent: intent as TemplateKey | null,
      selectedMemoryIds: (ids as string[]).map((id) => id.toLowerCase()),
    },
  };
}

export type AdminLike = {
  rpc: (
    fn: string,
    args: Record<string, unknown>,
    // deno-lint-ignore no-explicit-any
  ) =>
    & PromiseLike<
      { data: any; error: { code?: string; message: string } | null }
    >
    & {
      // deno-lint-ignore no-explicit-any
      abortSignal?: (
        signal: AbortSignal,
      ) => PromiseLike<{ data: any; error: any }>;
    };
  // deno-lint-ignore no-explicit-any
  from: (table: string) => any;
};

export type CapabilityRead =
  | { kind: "ok"; caps: Record<string, unknown> }
  | { kind: "not_deployed" }
  | { kind: "unavailable" };

function isMissingFunction(
  e: { code?: string; message?: string } | null,
): boolean {
  return !!e && (e.code === "PGRST202" || e.code === "42883" ||
    /could not find the function/i.test(e.message ?? ""));
}

export async function readSupportCapabilities(
  admin: AdminLike,
): Promise<CapabilityRead> {
  try {
    const { data, error } = await admin.rpc("support_capabilities", {});
    if (isMissingFunction(error)) return { kind: "not_deployed" };
    if (error || !isObj(data)) return { kind: "unavailable" };
    return { kind: "ok", caps: data };
  } catch {
    return { kind: "unavailable" };
  }
}

/**
 * The privacy-capable chat contract needs a context policy, an acknowledged privacy revision
 * and atomic confirmation; session persistence is needed only when a session is named
 * (section 10.1: separate negotiation, never a silent fall back to the old policy).
 */
export function capabilityGate(
  read: CapabilityRead,
  needsSession: boolean,
): SupportChatFailure | null {
  if (read.kind === "not_deployed") return FAILURES.unavailable("not_deployed");
  if (read.kind === "unavailable") return FAILURES.unavailable("unavailable");
  const c = read.caps;
  const n = (v: unknown) => (typeof v === "number" ? v : 0);
  if (
    n(c.context_policy) < 1 || c.privacy_revision !== true ||
    c.chat_confirmation !== true ||
    (needsSession && n(c.session_contract) < 1)
  ) return FAILURES.unavailable("insufficient");
  return null;
}

/** Body of the handshake response (HTTP 200); the client requires chat_contract >= 1. */
export function capabilityProbeBody(
  read: CapabilityRead,
): Record<string, unknown> {
  const base = {
    ok: true,
    op: "capabilities",
    chat_contract: SUPPORT_CHAT_CONTRACT,
  };
  if (read.kind === "ok") return { ...base, ...read.caps, status: "ok" };
  return {
    ...base,
    session_contract: 0,
    context_policy: 0,
    voice_context: 0,
    status: read.kind,
  };
}

// ---------------------------------------------------------------------------
// Context preparation (server-owned; client input never carries trusted text)
// ---------------------------------------------------------------------------
/** User-authored history is sanitized exactly as the legacy path did, BEFORE the policy measures it. */
export function sanitizingSources(inner: ContextSources): ContextSources {
  return {
    async load(args) {
      const records = await inner.load(args);
      return {
        ...records,
        history: records.history.map((h) =>
          h.role === "user"
            ? { ...h, content: sanitizeForPrompt(h.content) }
            : h
        ),
      };
    },
  };
}

const ACTIVITY_ADDENDUM = `

## Optional in-app activity
You may call propose_support_action at most once, only when a short in-app activity clearly fits what the person asked for, and always together with a brief caring reply written as text. It only shows an optional card; it starts nothing and the person decides. Do not call it for distress that needs human support, when they only want to talk, or for an activity they declined. basis_ref must be copied from a "(ref: ...)" marker in the saved context below, or be null. suggested_step is only for choose_step_v1.`;

const NO_SESSION_ADDENDUM = `

## In-app activities
Do not call propose_support_action in this conversation.`;

export function fixedSupportSystem(
  baseSystemPrompt: string,
  hasSession: boolean,
): string {
  return baseSystemPrompt +
    (hasSession ? ACTIVITY_ADDENDUM : NO_SESSION_ADDENDUM);
}

/**
 * Every serialized byte that is NOT history, current message or context blocks: the fixed
 * system text, message framing, the tool declaration, and room for the memory ref markers.
 */
export function promptOverheadBytes(fixedSystem: string): number {
  return byteLength(JSON.stringify([
    { role: "system", content: fixedSystem },
    { role: "user", content: "" },
  ])) + SUPPORT_ACTION_OVERHEAD_BYTES + REF_ALLOWANCE_BYTES +
    FRAMING_MARGIN_BYTES;
}

/** Append "(ref: <id>)" to each rendered saved-memory line so the model can cite a real source. */
export function annotateMemoryRefs(
  block: string,
  memoryIds: readonly string[],
): string {
  if (!block || memoryIds.length === 0) return block;
  const lines = block.split("\n");
  const body = lines.slice(2); // two header lines, then one line per memory
  if (
    body.length !== memoryIds.length || !body.every((l) => l.startsWith("- ["))
  ) return block;
  return [
    ...lines.slice(0, 2),
    ...body.map((l, i) => `${l} (ref: ${memoryIds[i]})`),
  ].join("\n");
}

export interface PreparedSupportTurn {
  assembled: AssembledContext;
  /** Effective scope after the account privacy mode (never wider than requested). */
  scope: ContextScope;
  narrowedBy: "account_privacy_mode" | null;
  messages: ChatMessage[];
  exclusions: string[];
  includedSources: ContextSourceRef[];
  /** Role and text of every history message exactly as dispatched (user text sanitized). */
  dispatchedHistory: ReadonlyMap<
    string,
    { role: "user" | "assistant"; content: string }
  >;
  /** Exact dispatched bytes: serialized messages + tool declaration (<= MAX_PROMPT_BYTES). */
  exactPromptBytes: number;
  fixedSystemBytes: number;
}

export interface PrepareArgs {
  admin: AdminLike;
  userId: string;
  conversationId: string;
  requestId: string;
  fields: SupportChatFields;
  /** user_settings.privacy_mode !== "standard": the account opted out of personal context. */
  accountPrivate: boolean;
  /** Stored user message (explicit retry), excluded from history. */
  currentMessageId: string | null;
  trimmedContent: string;
  baseSystemPrompt: string;
  /** Test seam only. */
  sources?: ContextSources;
  now?: () => Date;
}

function mapContextFailure(f: ContextFailure): SupportChatFailure {
  switch (f.reason) {
    case "PRIVACY_REVISION_STALE":
      return FAILURES.stale(f.currentPrivacyRevision);
    case "SESSION_NOT_FOUND":
      return {
        status: 404,
        body: {
          ...FAILURES.invalid("Session not found.").body,
          code: "chat_support_session_not_found",
          support_code: "NOT_FOUND",
        },
      };
    case "SESSION_CONVERSATION_MISMATCH":
    case "SCOPE_MISMATCH":
      return {
        status: 409,
        body: {
          ...FAILURES.invalid(f.message).body,
          code: f.reason === "SCOPE_MISMATCH"
            ? "chat_support_scope_mismatch"
            : "chat_support_session_mismatch",
        },
      };
    case "BOUNDARIES_DO_NOT_FIT":
      return FAILURES.tooLarge(true);
    case "CONTEXT_TOO_LARGE":
      return FAILURES.tooLarge(false);
    case "MESSAGE_TOO_LONG":
      return FAILURES.invalid(f.message);
  }
}

export async function prepareSupportContext(
  a: PrepareArgs,
): Promise<
  { ok: true; prepared: PreparedSupportTurn } | {
    ok: false;
    failure: SupportChatFailure;
  }
> {
  const narrowedBy = a.fields.scope === "personalized" && a.accountPrivate
    ? "account_privacy_mode" as const
    : null;
  const scope: ContextScope = narrowedBy ? "conversation_only" : a.fields.scope;
  const hasSession = a.fields.supportSessionId !== null;
  const fixed = fixedSupportSystem(a.baseSystemPrompt, hasSession);
  const sanitizedCurrent = sanitizeForPrompt(a.trimmedContent);
  // Capture the session row the policy loaded so a closed session is refused BEFORE any
  // spending (the database would only reject it at confirm, after the provider ran).
  let loadedSession: ContextSourceRecords["session"] = null;
  const inner = a.sources ??
    sanitizingSources(createSupabaseContextSources(a.admin as never));
  const sources: ContextSources = {
    async load(args) {
      const records = await inner.load(args);
      loadedSession = records.session;
      return records;
    },
  };
  const deps = defaultContextDeps(sources);
  if (a.now) deps.now = a.now;

  let ctx;
  try {
    ctx = await assembleContext(deps, {
      userId: a.userId,
      conversationId: a.conversationId,
      supportSessionId: a.fields.supportSessionId,
      requestId: a.requestId,
      channel: "text",
      scope,
      currentMessage: sanitizedCurrent,
      currentMessageId: a.currentMessageId,
      selectedMemoryIds: scope === "personalized"
        ? a.fields.selectedMemoryIds
        : [],
      selectedIntent: a.fields.selectedIntent,
      expectedPrivacyRevision: a.fields.expectedPrivacyRevision,
      promptOverheadBytes: promptOverheadBytes(fixed),
      limits: { currentMessageChars: SANITIZED_MESSAGE_CHAR_BOUND },
    });
  } catch {
    // Loader/RPC failure: fail closed, never fall back to the old personal reads.
    return { ok: false, failure: FAILURES.contextUnavailable() };
  }
  if (!ctx.ok) return { ok: false, failure: mapContextFailure(ctx) };
  const session = loadedSession as ContextSourceRecords["session"];
  if (session && session.status !== "open") {
    return { ok: false, failure: FAILURES.sessionClosed() };
  }

  const memoryIds = ctx.receiptDraft.sources.filter((s) =>
    s.kind === "companion_memory"
  ).map((s) => s.id);
  const rendered = renderTextContext({
    ...ctx,
    memoryBlock: annotateMemoryRefs(ctx.memoryBlock, memoryIds),
  });
  const messages: ChatMessage[] = [
    { role: "system", content: fixed + rendered },
    ...ctx.history.map((h) => ({ role: h.role, content: h.content })),
    { role: "user", content: sanitizedCurrent },
  ];
  const exactPromptBytes = byteLength(JSON.stringify(messages)) +
    SUPPORT_ACTION_OVERHEAD_BYTES;
  if (exactPromptBytes > MAX_PROMPT_BYTES) {
    // Defensive: the policy measure is conservative, so this should be unreachable.
    return { ok: false, failure: FAILURES.tooLarge(false) };
  }
  const exclusions = narrowedBy
    ? [...new Set([...ctx.receiptDraft.exclusions, "account_privacy_mode"])]
      .sort()
    : ctx.receiptDraft.exclusions;
  return {
    ok: true,
    prepared: {
      assembled: ctx,
      scope,
      narrowedBy,
      messages,
      exclusions,
      includedSources: ctx.receiptDraft.sources,
      dispatchedHistory: new Map(
        ctx.history.map((h) => [h.id, { role: h.role, content: h.content }]),
      ),
      exactPromptBytes,
      fixedSystemBytes: byteLength(fixed),
    },
  };
}

// ---------------------------------------------------------------------------
// Revalidation (before dispatch and before confirm). The SQL confirm is still final.
// ---------------------------------------------------------------------------
/** A cited history message as it exists NOW (exact-id lookup, never a bounded latest-N window). */
export interface CitedMessageRow {
  id: string;
  conversation_id: string;
  role: string;
  content: string;
  content_origin?: string | null;
  /** Server-owned content version (messages.content_revision); absent means 0. */
  content_revision?: number | string | null;
}

/**
 * Every included source must still be what was assembled. For history messages that means
 * the cited id exists NOW, in this conversation, with the same role, the same dispatched
 * text, a model origin, the same server-owned content version, and is not suppressed. An
 * in-place rewrite (apply-rewrite), delete, move or re-role is therefore stale even though
 * no privacy revision moved. `messages` MUST come from an exact-id lookup; without it a
 * cited message cannot be proven current and the turn is treated as changed.
 */
export function sourcesStillCurrent(
  prepared: RevalidationTarget,
  fresh: ContextSourceRecords,
  conversationId: string,
  now: Date,
  messages?: ReadonlyMap<string, CitedMessageRow | undefined>,
): { ok: true } | { ok: false; reason: "privacy_revision" | "source_changed" } {
  if (fresh.privacyRevision !== prepared.assembled.privacyRevision) {
    return { ok: false, reason: "privacy_revision" };
  }
  const changed = { ok: false, reason: "source_changed" } as const;
  let hasMessage = false;
  for (const s of prepared.includedSources) {
    switch (s.kind) {
      case "companion_memory": {
        const m = fresh.memories.find((x) => x.id === s.id);
        if (
          !m || m.revision !== s.revision ||
          memoryExclusion(m, now, fresh.suppressions.memories)
        ) {
          return changed;
        }
        break;
      }
      case "daily_intent":
        if (
          !fresh.dailyIntent || fresh.dailyIntent.id !== s.id ||
          Date.parse(fresh.dailyIntent.expiresAt) <= now.getTime()
        ) return changed;
        break;
      case "session":
        if (
          !fresh.session || fresh.session.id !== s.id ||
          fresh.session.status !== "open" ||
          fresh.session.contextRevision !== s.revision
        ) return changed;
        break;
      case "activity_result":
        if (
          !fresh.activity || fresh.activity.id !== s.id ||
          fresh.activity.revision !== s.revision ||
          fresh.suppressions.activities?.has(s.id)
        ) return changed;
        break;
      case "message": {
        hasMessage = true;
        if (fresh.suppressions.messages.has(s.id)) return changed;
        const row = messages?.get(s.id);
        const sent = prepared.dispatchedHistory.get(s.id);
        if (!row || !sent) return changed;
        if (
          row.conversation_id !== conversationId || row.role !== sent.role ||
          (row.content_origin ?? "model") !== "model" ||
          Number(row.content_revision ?? 0) !== s.revision
        ) return changed;
        const text = typeof row.content === "string" ? row.content : "";
        if (
          (row.role === "user" ? sanitizeForPrompt(text) : text) !==
            sent.content
        ) {
          return changed;
        }
        break;
      }
      case "safety_policy":
        break;
    }
  }
  if (hasMessage && fresh.suppressions.conversations.has(conversationId)) {
    return changed;
  }
  return { ok: true };
}

/** Exact-id lookup of the cited history messages (owner-scoped via the verified conversation). */
export async function loadCitedMessages(
  admin: AdminLike,
  conversationId: string,
  ids: readonly string[],
): Promise<Map<string, CitedMessageRow>> {
  const rows = new Map<string, CitedMessageRow>();
  if (ids.length === 0) return rows;
  // `*` keeps this working across schema versions: a missing content_revision reads as 0.
  const { data, error } = await admin.from("messages").select("*").in("id", [
    ...ids,
  ]).eq("conversation_id", conversationId);
  if (error || !Array.isArray(data)) {
    throw new Error("cited messages unavailable");
  }
  for (const row of data as CitedMessageRow[]) rows.set(row.id, row);
  return rows;
}

/** What a turn actually sent: enough to prove, later, that none of it has changed. */
export type RevalidationTarget =
  & Pick<
    PreparedSupportTurn,
    "includedSources" | "scope" | "dispatchedHistory"
  >
  & { assembled: Pick<AssembledContext, "privacyRevision"> };

export interface RevalidateArgs {
  admin: AdminLike;
  userId: string;
  conversationId: string;
  supportSessionId: string | null;
  prepared: RevalidationTarget;
  sources?: ContextSources;
  now?: () => Date;
}

export async function revalidatePreparedContext(
  a: RevalidateArgs,
): Promise<{ ok: true } | { ok: false; failure: SupportChatFailure }> {
  try {
    const sources = a.sources ?? createSupabaseContextSources(a.admin as never);
    const fresh = await sources.load({
      userId: a.userId,
      conversationId: a.conversationId,
      supportSessionId: a.supportSessionId,
      scope: a.prepared.scope,
    });
    const cited = await loadCitedMessages(
      a.admin,
      a.conversationId,
      a.prepared.includedSources.filter((x) => x.kind === "message").map((x) =>
        x.id
      ),
    );
    const verdict = sourcesStillCurrent(
      a.prepared,
      fresh,
      a.conversationId,
      a.now?.() ?? new Date(),
      cited,
    );
    if (!verdict.ok) {
      supportLog("stale", { reason: verdict.reason });
      return {
        ok: false,
        failure: FAILURES.stale(
          fresh.privacyRevision || undefined,
          verdict.reason,
        ),
      };
    }
    if (a.prepared.scope === "personalized") {
      // The account-level private mode is also a privacy control.
      const { data, error } = await a.admin.from("user_settings").select(
        "privacy_mode",
      )
        .eq("user_id", a.userId).maybeSingle();
      if (error || !data) {
        return { ok: false, failure: FAILURES.contextUnavailable() };
      }
      if (data.privacy_mode !== "standard") {
        supportLog("stale", { reason: "account_privacy_mode" });
        return {
          ok: false,
          failure: FAILURES.stale(fresh.privacyRevision, "source_changed"),
        };
      }
    }
    return { ok: true };
  } catch {
    return { ok: false, failure: FAILURES.contextUnavailable() };
  }
}

// ---------------------------------------------------------------------------
// Legacy-shaped requests (M4-R02). An installed client that predates the contract keeps its
// request and response shapes, quota, budget, claim and receipt semantics, but once the
// support schema is installed its personal context is no longer read directly: eligibility
// comes from the same server-owned loader and policy the new contract uses (Stop using,
// Forget, source/derived-message/conversation suppression, expiry, life-context review,
// review state). When the contract is genuinely absent the old baseline is unchanged. When
// its state cannot be proven, the request fails closed instead of reading unsuppressed rows.
// ---------------------------------------------------------------------------
export type LegacyEligibility =
  /** support_capabilities does not exist (or reports no context policy): old behavior. */
  | { kind: "baseline" }
  /** Installed but unreadable right now: nothing is read, sent or debited. */
  | { kind: "unavailable"; failure: SupportChatFailure }
  | {
    kind: "eligible";
    records: ContextSourceRecords;
    /** Confirmed, enabled, unexpired, not suppressed, not awaiting life-context review. */
    memories: MemorySourceRecord[];
    dailyIntent: { id: string; intent: string } | null;
    privacyRevision: number;
  };

export async function resolveLegacyEligibility(a: {
  admin: AdminLike;
  userId: string;
  conversationId: string;
  /** Account privacy mode is off (standard): personal context may be considered. */
  personal: boolean;
  now?: () => Date;
  /** Test seam only. */
  sources?: ContextSources;
}): Promise<LegacyEligibility> {
  const read = await readSupportCapabilities(a.admin);
  if (read.kind === "not_deployed") return { kind: "baseline" };
  if (read.kind === "unavailable") {
    return { kind: "unavailable", failure: FAILURES.contextUnavailable() };
  }
  const caps = read.caps;
  if (
    !(typeof caps.context_policy === "number" && caps.context_policy >= 1) ||
    caps.privacy_revision !== true
  ) return { kind: "baseline" };
  try {
    const inner = a.sources ??
      sanitizingSources(createSupabaseContextSources(a.admin as never));
    const records = await inner.load({
      userId: a.userId,
      conversationId: a.conversationId,
      supportSessionId: null,
      scope: a.personal ? "personalized" : "conversation_only",
    });
    const now = (a.now ?? (() => new Date()))();
    const memories = a.personal
      ? records.memories.filter((m) =>
        memoryExclusion(m, now, records.suppressions.memories) === null
      ).slice(0, CONTEXT_LIMITS.confirmedMemories)
      : [];
    const intent = a.personal && records.dailyIntent &&
        Date.parse(records.dailyIntent.expiresAt) > now.getTime()
      ? { id: records.dailyIntent.id, intent: records.dailyIntent.intent }
      : null;
    return {
      kind: "eligible",
      records,
      memories,
      dailyIntent: intent,
      privacyRevision: records.privacyRevision,
    };
  } catch {
    return { kind: "unavailable", failure: FAILURES.contextUnavailable() };
  }
}

/**
 * How the fixed crisis reply is saved directly (legacy-shaped requests, and a new-contract
 * request whose atomic confirmation is definitively unavailable):
 *   tagged ... the origin is recorded ATOMICALLY in the one insert (`content_origin` =
 *              safety_response). Used when the support schema is installed AND when its
 *              presence is merely unknown (probe unavailable): a best-effort UPDATE after an
 *              untagged insert cannot enforce provenance, so none is ever used.
 *   plain  ... the schema is known to be absent (the probe says the function does not exist):
 *              the old untagged insert, untouched (the column may not exist).
 */
export async function legacySafetyOriginMode(
  admin: AdminLike,
): Promise<"tagged" | "plain"> {
  const read = await readSupportCapabilities(admin);
  return read.kind === "not_deployed" ? "plain" : "tagged";
}

export type SafetyReplySave =
  | { kind: "saved"; message: { id: string; created_at: string | null } }
  /** Commit state unknown: nothing more is written; help is shown; the claim stays pending. */
  | { kind: "pending" };

/**
 * A usable acknowledgment of the inserted row: a canonical message id and the row we asked for
 * (assistant, this conversation). An empty object, an array, a numeric id or any other shape is
 * NOT an acknowledgment: the row may nonetheless have committed.
 */
function acknowledgedMessage(
  data: unknown,
  conversationId: string,
): { id: string; created_at: string | null } | null {
  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    return null;
  }
  const row = data as Record<string, unknown>;
  if (typeof row.id !== "string" || !LAX_UUID.test(row.id)) return null;
  if (row.role !== "assistant" || row.conversation_id !== conversationId) {
    return null;
  }
  return {
    id: row.id,
    created_at: typeof row.created_at === "string" ? row.created_at : null,
  };
}

/**
 * Save the fixed crisis reply with exactly ONE insert, never a second one under any outcome.
 *   tagged ... one insert that carries `content_origin: safety_response` (and the session for a
 *              new-contract request). It is saved ONLY on a valid acknowledgment. Every other
 *              outcome is pending: a database or schema-cache rejection (PGRST204 and 42703 say
 *              the cache or statement refused a column, NOT that the column is absent, so an
 *              untagged retry could write a NULL origin), transport loss, a lost response
 *              after commit, or an empty/malformed acknowledgment (the row may have committed).
 *   plain  ... the known-absent-schema legacy insert: a server-reported failure is the old
 *              hard error; a response that reports no error but carries no valid
 *              acknowledgment is unknown, hence pending.
 * The help text itself is always shown to the person.
 */
export async function saveSafetyReplyDirect(a: {
  admin: AdminLike;
  conversationId: string;
  content: string;
  mode: "tagged" | "plain";
  /** New-contract requests only: the session to record (undefined for legacy-shaped ones). */
  supportSessionId?: string | null;
}): Promise<SafetyReplySave> {
  const row: Record<string, unknown> = {
    conversation_id: a.conversationId,
    role: "assistant",
    content: a.content,
    ...(a.mode === "tagged"
      ? {
        content_origin: "safety_response",
        ...(a.supportSessionId !== undefined
          ? { support_session_id: a.supportSessionId }
          : {}),
      }
      : {}),
  };
  let result: { data: unknown; error: unknown };
  try {
    result = await a.admin.from("messages").insert(row).select().single();
  } catch {
    logFailure("safety_save_unknown", { code: "unknown" });
    return { kind: "pending" };
  }
  const message = result.error
    ? null
    : acknowledgedMessage(result.data, a.conversationId);
  if (message) return { kind: "saved", message };
  if (a.mode === "plain" && result.error) {
    // Known-absent schema: the old contract, unchanged.
    throw new Error("ASSISTANT_MESSAGE_NOT_SAVED");
  }
  logFailure("safety_save_unknown", {
    code: result.error ? dbCode(result.error) : "unacknowledged",
  });
  return { kind: "pending" };
}

/**
 * The response for a fixed crisis reply whose save is pending. The help text is returned
 * immediately; the assistant id is a stable NON-durable placeholder derived from the
 * request (or the saved user message), never a database row.
 */
export async function pendingSafetyReplyBody(a: {
  content: string;
  trimmedContent: string;
  userMessage: { id: string; created_at: string | null };
  requestId: string | null;
  now: Date;
  /** Present for new-contract requests (their wire carries the support block). */
  support?: {
    requestId: string;
    conversationId: string;
    supportSessionId: string | null;
    scope: ContextScope;
  };
}): Promise<Record<string, unknown>> {
  const assistant = {
    id: await pendingLocalMessageId(a.requestId ?? a.userMessage.id),
    role: "assistant",
    content: a.content,
    createdAt: a.now.getTime() / 1000,
    blocked: true,
    ...(a.support
      ? { contentOrigin: "safety_response", isInterfaceGuidance: false }
      : {}),
  };
  return {
    userMessage: {
      id: a.userMessage.id,
      role: "user",
      content: a.trimmedContent,
      createdAt: toUnix(a.userMessage.created_at, a.now),
      blocked: false,
    },
    assistantMessage: assistant,
    message: { ...assistant },
    isCrisisResponse: true,
    ...(a.support
      ? {
        support: {
          ...safetyFallbackSupport(a.support),
          persistence: "pending_reconcile",
        },
      }
      : {}),
  };
}

/**
 * Conversation history for a legacy-shaped request, selected by the shared policy (suppressed
 * messages, derived assistant turns and a suppressed conversation are already excluded; 20
 * messages, 64,000 history bytes, whole prompt <= 128,000 bytes) from the SAME loaded records.
 */
export async function legacyEligibleHistory(a: {
  records: ContextSourceRecords;
  userId: string;
  conversationId: string;
  requestId: string | null;
  currentMessageId: string | null;
  trimmedContent: string;
  /** The complete legacy system prompt, memory and tone included. */
  systemPrompt: string;
}): Promise<
  | {
    ok: true;
    history: { id: string; role: "user" | "assistant"; content: string }[];
    /** Receipt references for the history actually sent (plus the safety policy). */
    sources: ContextSourceRef[];
    /** History-related exclusions the policy recorded (trimmed / suppressed turns). */
    exclusions: string[];
  }
  | { ok: false; failure: SupportChatFailure }
> {
  const cached: ContextSources = { load: () => Promise.resolve(a.records) };
  const overhead = byteLength(JSON.stringify([
    { role: "system", content: a.systemPrompt },
    { role: "user", content: "" },
  ])) + FRAMING_MARGIN_BYTES;
  const ctx = await assembleContext(defaultContextDeps(cached), {
    userId: a.userId,
    conversationId: a.conversationId,
    supportSessionId: null,
    requestId: a.requestId ?? "",
    channel: "text",
    // Memory was already filtered above; the history rules are scope-independent.
    scope: "conversation_only",
    currentMessage: sanitizeForPrompt(a.trimmedContent),
    currentMessageId: a.currentMessageId,
    promptOverheadBytes: overhead,
    limits: { currentMessageChars: SANITIZED_MESSAGE_CHAR_BOUND },
  });
  if (!ctx.ok) return { ok: false, failure: mapContextFailure(ctx) };
  return {
    ok: true,
    history: ctx.history,
    sources: ctx.receiptDraft.sources,
    exclusions: ctx.receiptDraft.exclusions.filter((e) =>
      e === "trimmed_history" || e === "suppressed_or_incomplete_turns"
    ),
  };
}

// ---------------------------------------------------------------------------
// Installed-schema legacy turn: the same privacy/source authority as the new contract.
// The old request and response shapes are kept; the final save is the atomic
// support_confirm_chat_turn with a NULL support session (no session or history is invented
// for an old client; context receipts allow NULL support_session_id).
// ---------------------------------------------------------------------------
export const LEGACY_CHAT_ROUTE = {
  vendor: "openai",
  model: CHAT_MODEL,
  routeVersion: "responses-legacy-1",
} as const;

export interface LegacyTurnContext {
  prepared: RevalidationTarget;
  exclusions: string[];
  scope: ContextScope;
  privacyRevision: number;
}

/** Everything the legacy turn sent, as cited sources, from what was actually dispatched. */
export function buildLegacyTurnContext(a: {
  eligible: Extract<LegacyEligibility, { kind: "eligible" }>;
  personal: boolean;
  history: { id: string; role: "user" | "assistant"; content: string }[];
  historySources: ContextSourceRef[];
  historyExclusions: string[];
}): LegacyTurnContext {
  const scope: ContextScope = a.personal ? "personalized" : "conversation_only";
  const sources: ContextSourceRef[] = [...a.historySources];
  for (const m of a.eligible.memories) {
    sources.push({
      kind: "companion_memory",
      id: m.id,
      revision: m.revision,
      date: m.confirmedAt,
    });
  }
  if (a.personal && a.eligible.dailyIntent && a.eligible.records.dailyIntent) {
    sources.push({
      kind: "daily_intent",
      id: a.eligible.dailyIntent.id,
      revision: 0,
      date: a.eligible.records.dailyIntent.createdAt,
    });
  }
  const exclusions = new Set<string>([
    ...a.historyExclusions,
    "generated_fragments",
    "health_data",
    "inferred_affect",
    "other_conversations",
    "private_vault",
  ]);
  if (!a.personal) {
    exclusions.add("saved_memory");
    exclusions.add("daily_intent");
    exclusions.add("absence_metadata");
  }
  return {
    prepared: {
      assembled: { privacyRevision: a.eligible.privacyRevision },
      includedSources: sources,
      scope,
      dispatchedHistory: new Map(
        a.history.map((h) => [h.id, { role: h.role, content: h.content }]),
      ),
    },
    exclusions: [...exclusions].sort(),
    scope,
    privacyRevision: a.eligible.privacyRevision,
  };
}

/** The legacy response body minus server ids; stored as the request's terminal response. */
export function buildLegacyWireTemplate(a: {
  trimmedContent: string;
  userMessage: { id: string; created_at: string | null } | null;
  quota: { used: number; limit: number };
  now: Date;
  content: string;
  memoryUsed: boolean;
  memoryIds: string[];
  coachData: unknown;
}): Record<string, unknown> {
  return {
    userMessage: {
      id: a.userMessage?.id,
      role: "user",
      content: a.trimmedContent,
      createdAt: toUnix(a.userMessage?.created_at, a.now),
      blocked: false,
    },
    assistantMessage: {
      id: null as string | null,
      role: "assistant",
      content: a.content,
      createdAt: a.now.getTime() / 1000,
      blocked: false,
    },
    userMessageId: a.userMessage?.id,
    quotaUsed: a.quota.used,
    quotaLimit: a.quota.limit,
    conversationTitle: null,
    memoryUsed: a.memoryUsed,
    memoryIdsUsed: a.memoryIds,
    coachData: a.coachData ?? null,
  };
}

/**
 * Atomic final save of an installed-schema legacy turn, against the exact privacy revision
 * and cited sources of what was sent. The SQL confirmation is the authority (it re-validates
 * every cited source under lock); a client that sent no requestId gets a server-side claim so
 * the same atomic path applies.
 */
export async function confirmLegacyTurn(a: {
  admin: AdminLike;
  userId: string;
  conversationId: string;
  requestId: string | null;
  contentHash: string;
  ctx: LegacyTurnContext;
  template: Record<string, unknown>;
  content: string;
  confirm?: ConfirmOptions;
}): Promise<SupportTurnOutcome> {
  let claimId = a.requestId;
  if (!claimId) {
    claimId = crypto.randomUUID();
    try {
      const { error } = await a.admin.from("chat_requests").insert({
        user_id: a.userId,
        request_id: claimId,
        conversation_id: a.conversationId,
        content_hash: a.contentHash,
      });
      if (error) return fromFailure(FAILURES.confirmUnavailable());
    } catch {
      return fromFailure(FAILURES.confirmUnavailable());
    }
  }
  const args: ConfirmChatTurnArgs = {
    user_id: a.userId,
    request_id: claimId,
    conversation_id: a.conversationId,
    support_session_id: null,
    assistant_content: a.content,
    content_origin: "model",
    privacy_revision: a.ctx.privacyRevision,
    scope: a.ctx.scope,
    provider_vendor: LEGACY_CHAT_ROUTE.vendor,
    provider_model: LEGACY_CHAT_ROUTE.model,
    route_version: LEGACY_CHAT_ROUTE.routeVersion,
    exclusions: a.ctx.exclusions,
    sources: a.ctx.prepared.includedSources,
    proposal: null,
    content_hash: a.contentHash,
    response: a.template,
    response_status: 200,
  };
  return await finishConfirmed(a.admin, a.userId, claimId, args, a.confirm);
}

/**
 * Background extraction must recheck the privacy revision and the suppression set before it
 * sends text to the provider and again before it persists a candidate (spec 8.4/8.5).
 * Any doubt means no extraction.
 */
export async function legacyExtractionAllowed(a: {
  admin: AdminLike;
  userId: string;
  conversationId: string;
  userMessageId: string | null;
  privacyRevision: number;
}): Promise<boolean> {
  try {
    const state = await a.admin.from("support_privacy_state").select(
      "privacy_revision",
    ).eq("user_id", a.userId).maybeSingle();
    if (state.error) return false;
    const current = Number(state.data?.privacy_revision ?? 1);
    if (current !== a.privacyRevision) return false;
    const sup = await a.admin.from("support_suppressions").select(
      "kind, ref_id",
    )
      .eq("user_id", a.userId);
    if (sup.error || !Array.isArray(sup.data)) return false;
    return !(sup.data as { kind: string; ref_id: string }[]).some((r) =>
      (r.kind === "conversation" && r.ref_id === a.conversationId) ||
      (r.kind === "message" && a.userMessageId !== null &&
        r.ref_id === a.userMessageId)
    );
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Turn planning: what is persisted, with what origin, and whether a card exists
// ---------------------------------------------------------------------------
export type ProposalDropReason =
  | "invalid_proposal"
  | "template_declined"
  | "refusal"
  | "no_session"
  | "rejected_at_confirm";

export type TurnPlan =
  | {
    kind: "ok";
    status: "completed" | "refused";
    content: string;
    origin: "model" | "interface_fallback";
    proposal: ValidatedProposal | null;
    proposalDropped: ProposalDropReason | null;
  }
  | { kind: "empty" };

export function planSupportTurn(a: {
  result: ChatResult;
  hasSession: boolean;
  scope: ContextScope;
  includedSources: readonly ContextSourceRef[];
  selectedIntent: TemplateKey | null;
  suppressedTemplates: readonly string[];
}): TurnPlan {
  const { result } = a;
  if (result.status === "refused") {
    const refusal = (result.refusal ?? "").trim();
    // A refusal never carries an ordinary proposal (section 8.6).
    return refusal
      ? {
        kind: "ok",
        status: "refused",
        content: result.refusal!,
        origin: "model",
        proposal: null,
        proposalDropped: result.proposal.state === "none" ? null : "refusal",
      }
      : { kind: "empty" };
  }
  if (result.status !== "completed") return { kind: "empty" };

  const hasText = result.text.trim() !== "";
  let proposal: ValidatedProposal | null = null;
  let dropped: ProposalDropReason | null = null;
  if (result.proposal.state === "invalid") dropped = "invalid_proposal";
  else if (result.proposal.state === "raw") {
    if (!a.hasSession) dropped = "no_session";
    else {
      const v = validateSupportActionProposal(result.proposal.arguments, {
        scope: a.scope,
        includedSources: a.includedSources,
        selectedIntent: a.selectedIntent,
        suppressedTemplates: a.suppressedTemplates,
      });
      if (v.ok) proposal = v.proposal;
      else {dropped = v.reason === "template declined this session"
          ? "template_declined"
          : "invalid_proposal";}
    }
  }
  if (hasText) {
    return {
      kind: "ok",
      status: "completed",
      content: result.text,
      origin: "model",
      proposal,
      proposalDropped: dropped,
    };
  }
  // Tool-only: only a VALID proposal yields persistable, self-contained interface guidance.
  if (proposal) {
    return {
      kind: "ok",
      status: "completed",
      content: interfaceFallbackText(proposal.template_key),
      origin: "interface_fallback",
      proposal,
      proposalDropped: null,
    };
  }
  return { kind: "empty" };
}

// ---------------------------------------------------------------------------
// Client wire: one stored template + server ids => identical initial and replayed bytes
// ---------------------------------------------------------------------------
const toUnix = (value: string | null | undefined, fallback: Date) =>
  (value ? new Date(value) : fallback).getTime() / 1000;

export interface WireTemplateArgs {
  userId: string;
  requestId: string;
  conversationId: string;
  supportSessionId: string | null;
  trimmedContent: string;
  userMessage: { id: string; created_at: string | null } | null;
  /** null for a safety response: no quota was debited. */
  quota: { used: number; limit: number } | null;
  now: Date;
  scope: ContextScope;
  privacyRevision: number;
  content: string;
  origin: "model" | "interface_fallback" | "safety_response";
  status: "completed" | "refused" | "safety";
  proposal: ValidatedProposal | null;
  proposalDropped: ProposalDropReason | null;
  sources: readonly ContextSourceRef[];
  exclusions: readonly string[];
  provider: { vendor: string; model: string; routeVersion: string };
  narrowedBy: "account_privacy_mode" | null;
}

/**
 * Everything the client sees EXCEPT the server-generated ids (assistant message, receipt,
 * proposal), which only exist after support_confirm_chat_turn commits. The same object is
 * stored as the request's terminal response; renderSupportWire() fills the ids from the
 * `support_confirmed` block the RPC adds. Times are handler times stored once, so a replay
 * is byte-identical. proposal.expires_at is a conservative display hint (the database
 * enforces expiry at accept time and sets it a few ms later).
 */
export function buildWireTemplate(
  a: WireTemplateArgs,
): Record<string, unknown> {
  const createdIso = a.now.toISOString();
  const memoryIds = a.sources.filter((s) => s.kind === "companion_memory").map((
    s,
  ) => s.id);
  const personalIncluded = a.sources.some((s) =>
    s.kind === "companion_memory" || s.kind === "daily_intent"
  );
  const safety = a.origin === "safety_response";
  const assistant = {
    id: null as string | null,
    role: "assistant",
    content: a.content,
    createdAt: a.now.getTime() / 1000,
    blocked: safety,
    contentOrigin: a.origin,
    isInterfaceGuidance: a.origin === "interface_fallback",
  };
  return {
    userMessage: {
      id: a.userMessage?.id,
      role: "user",
      content: a.trimmedContent,
      createdAt: toUnix(a.userMessage?.created_at, a.now),
      blocked: false,
    },
    assistantMessage: assistant,
    userMessageId: a.userMessage?.id,
    ...(safety ? { isCrisisResponse: true } : {}),
    ...(a.quota ? { quotaUsed: a.quota.used, quotaLimit: a.quota.limit } : {}),
    conversationTitle: null,
    memoryUsed: personalIncluded,
    memoryIdsUsed: memoryIds,
    coachData: null,
    support: {
      schema_version: SUPPORT_CHAT_CONTRACT,
      request_id: a.requestId,
      support_session_id: a.supportSessionId,
      conversation_id: a.conversationId,
      scope: a.scope,
      scope_narrowed_by: a.narrowedBy,
      privacy_revision: a.privacyRevision,
      content_origin: a.origin,
      status: a.status,
      suppress_ordinary_cards: a.status !== "completed",
      confirmed: false,
      persistence: "unconfirmed",
      context_receipt: {
        schema_version: 1,
        receipt_id: null as string | null,
        request_id: a.requestId,
        support_session_id: a.supportSessionId,
        conversation_id: a.conversationId,
        assistant_message_id: null as string | null,
        privacy_revision: a.privacyRevision,
        scope: a.scope,
        provider: {
          vendor: a.provider.vendor,
          model: a.provider.model,
          route_version: a.provider.routeVersion,
        },
        sources: a.sources,
        exclusions: a.exclusions,
        created_at: createdIso,
      },
      proposal: a.proposal
        ? {
          id: null as string | null,
          template_key: a.proposal.template_key,
          reason_code: a.proposal.reason_code,
          basis_kind: a.proposal.basis_kind,
          basis_ref: a.proposal.basis_ref,
          suggested_step: a.proposal.suggested_step,
          status: "offered",
          expires_at: new Date(a.now.getTime() + SUPPORT_LIMITS.proposalTtlMs)
            .toISOString(),
        }
        : null,
      proposal_dropped: a.proposalDropped,
    },
  };
}

// deno-lint-ignore no-explicit-any
type Json = Record<string, any>;

/**
 * Pure function of the stored response. Rows without `support_confirmed` (legacy contract,
 * failures) are returned unchanged, so every replay path can call it unconditionally.
 */
export function renderSupportWire(stored: Json): Json {
  const c = stored?.support_confirmed;
  if (!isObj(c)) return stored;
  const { support_confirmed: _ids, ...rest } = stored;
  const out: Json = structuredClone(rest);
  out.assistantMessage = { ...out.assistantMessage, id: c.message_id };
  out.message = { ...out.assistantMessage };
  if (!isObj(out.support)) {
    // A legacy-shaped response (installed client that sends none of the new fields): only the
    // server-generated message id is filled; the old wire gains no new block.
    return out;
  }
  const support: Json = {
    ...out.support,
    confirmed: true,
    persistence: "confirmed",
  };
  if (isObj(support.context_receipt)) {
    support.context_receipt = {
      ...support.context_receipt,
      receipt_id: c.receipt_id,
      assistant_message_id: c.message_id,
    };
  }
  if (isObj(support.proposal)) {
    if (typeof c.proposal_id === "string") {
      support.proposal = { ...support.proposal, id: c.proposal_id };
    } else {
      // The database dropped it at confirm (for example a just-declined template).
      support.proposal = null;
      support.proposal_dropped = "rejected_at_confirm";
    }
  }
  out.support = support;
  return out;
}

// ---------------------------------------------------------------------------
// Atomic confirmation with ambiguity-safe reconciliation
// ---------------------------------------------------------------------------
export type ConfirmOutcome =
  | { kind: "confirmed"; stored: Json; status: number; replayed: boolean }
  /** Definite non-commit: the RPC returned ok:false or a structured database error. */
  | {
    kind: "rejected";
    failure: SupportChatFailure;
    code: string;
    currentPrivacyRevision?: number;
  }
  /** The request is already finalized (or never claimed); read the claim to learn the result. */
  | { kind: "reused" }
  /** Outcome unknown after bounded idempotent re-issues. The claim must stay pending. */
  | { kind: "ambiguous" };

export interface ConfirmOptions {
  attempts?: number;
  timeoutMs?: number;
  sleep?: (ms: number) => Promise<void>;
}

function rejection(code: string, data: Json): ConfirmOutcome {
  const current = typeof data.current_privacy_revision === "number"
    ? data.current_privacy_revision
    : undefined;
  switch (code) {
    case "PRIVACY_REVISION_STALE":
      return {
        kind: "rejected",
        code,
        currentPrivacyRevision: current,
        failure: FAILURES.stale(
          current,
          typeof data.message === "string" &&
            data.message.startsWith("source_changed")
            ? "source_changed"
            : "privacy_revision",
        ),
      };
    case "OPERATION_ID_REUSED":
      return { kind: "reused" };
    case "TEMPORARY_FAILURE":
      return { kind: "rejected", code, failure: FAILURES.confirmUnavailable() };
    default:
      return {
        kind: "rejected",
        code,
        failure: FAILURES.confirmRejected(code),
      };
  }
}

/**
 * support_confirm_chat_turn is idempotent per (user, request): it serializes on an advisory
 * lock and returns the stored response if a receipt exists. An unknown outcome (network
 * failure, timeout, unstructured error) is therefore reconciled by re-issuing the SAME call,
 * which either observes the earlier commit or commits exactly once. No second model turn.
 */
export async function confirmSupportTurn(
  admin: AdminLike,
  args: ConfirmChatTurnArgs,
  opts: ConfirmOptions = {},
): Promise<ConfirmOutcome> {
  const attempts = opts.attempts ?? CONFIRM_ATTEMPTS;
  const sleep = opts.sleep ??
    ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  // Once any attempt had an unknown outcome, a later STRUCTURED database error (for example
  // a lock or statement timeout while queued behind that attempt) proves nothing about the
  // earlier one, which may still commit. Only a logical ok:false returned by the function
  // itself is definitive then: it runs after the per-request advisory lock, so no earlier
  // attempt can have committed.
  let unknown = false;
  for (let attempt = 0; attempt < attempts; attempt++) {
    if (attempt > 0) await sleep(100 * attempt);
    let data: unknown;
    let error: { code?: string; message: string } | null = null;
    try {
      const call = admin.rpc("support_confirm_chat_turn", { p_args: args });
      // The request's own abort signal is deliberately NOT used: a client cancel must not
      // leave the commit state unknown. Only a bounded timeout applies.
      const timed = typeof call.abortSignal === "function"
        ? call.abortSignal(
          AbortSignal.timeout(opts.timeoutMs ?? CONFIRM_TIMEOUT_MS),
        )
        : call;
      const r = await timed;
      data = r.data;
      error = r.error;
    } catch {
      unknown = true;
      supportLog("confirm_ambiguous", { attempt: attempt + 1 });
      continue;
    }
    if (error) {
      // An error from THIS attempt (a schema-cache "missing function" included) proves only
      // that this attempt did not run. It is a definite non-commit for the REQUEST only when
      // no earlier attempt is unknown; otherwise the earlier one may still have committed.
      if (!unknown) {
        if (isMissingFunction(error)) {
          return {
            kind: "rejected",
            code: "NOT_DEPLOYED",
            failure: FAILURES.unavailable("not_deployed"),
          };
        }
        if (typeof error.code === "string" && error.code !== "") {
          return {
            kind: "rejected",
            code: "TEMPORARY_FAILURE",
            failure: FAILURES.confirmUnavailable(),
          };
        }
      }
      unknown = true;
      supportLog("confirm_ambiguous", { attempt: attempt + 1 });
      continue;
    }
    if (!isObj(data) || typeof data.ok !== "boolean") {
      unknown = true;
      supportLog("confirm_ambiguous", { attempt: attempt + 1 });
      continue;
    }
    if (data.ok === false) {
      return rejection(String(data.code ?? "TEMPORARY_FAILURE"), data);
    }
    const stored = data.response;
    const ids = isObj(stored) ? stored.support_confirmed : null;
    if (
      !isObj(stored) || !isObj(ids) || typeof ids.message_id !== "string" ||
      typeof ids.receipt_id !== "string" || ids.message_id !== data.message_id
    ) {
      unknown = true;
      supportLog("confirm_ambiguous", {
        attempt: attempt + 1,
        shape: "unexpected",
      });
      continue;
    }
    return {
      kind: "confirmed",
      stored,
      status: typeof data.response_status === "number"
        ? data.response_status
        : 200,
      replayed: data.replayed === true,
    };
  }
  return { kind: "ambiguous" };
}

/** Read the request's terminal state after OPERATION_ID_REUSED or a lost guarded write. */
export async function readTerminalClaim(
  admin: AdminLike,
  userId: string,
  requestId: string,
): Promise<{ response: Json; status: number } | null> {
  try {
    const { data, error } = await admin.from("chat_requests")
      .select("response, response_status")
      .eq("user_id", userId).eq("request_id", requestId).maybeSingle();
    if (error || !data?.response || typeof data.response_status !== "number") {
      return null;
    }
    return { response: data.response as Json, status: data.response_status };
  } catch {
    return null;
  }
}

async function loadSuppressedTemplates(
  admin: AdminLike,
  userId: string,
  sessionId: string,
): Promise<string[] | null> {
  try {
    const { data, error } = await admin.from("support_work_sessions").select(
      "suppressed_templates",
    )
      .eq("id", sessionId).eq("user_id", userId).maybeSingle();
    if (error || !data) return null;
    return Array.isArray(data.suppressed_templates)
      ? data.suppressed_templates
      : [];
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// The model turn
// ---------------------------------------------------------------------------
export class SupportChatAbort extends Error {
  constructor(readonly failure: SupportChatFailure) {
    super("SUPPORT_CHAT_ABORT");
  }
}

export interface SupportTurnDeps {
  admin: AdminLike;
  userId: string;
  conversationId: string;
  requestId: string;
  trimmedContent: string;
  contentHash: string;
  fields: SupportChatFields;
  accountPrivate: boolean;
  baseSystemPrompt: string;
  apiKey: string;
  signal: AbortSignal;
  onDelta?: (text: string) => void;
  reserveBudget: (microdollars: number) => Promise<boolean>;
  /** Atomic user quota debit, then the user message save. Owned by the handler. */
  beforeProvider: () => Promise<void>;
  getUserMessage: () => { id: string; created_at: string | null } | null;
  getQuota: () => { used: number; limit: number };
  /** Lets the handler classify provider errors for its existing 503 mapping. */
  markProviderFailure: (error: unknown) => void;
  now?: () => Date;
  confirm?: ConfirmOptions;
}

export interface SupportTurnOutcome {
  status: number;
  body: Json;
  /** The database already stored this terminal response; the caller must not overwrite it. */
  final?: boolean;
  /** Commit state unknown: store nothing so a late commit cannot be contradicted. */
  leavePending?: boolean;
}

function fromFailure(f: SupportChatFailure): SupportTurnOutcome {
  return { status: f.status, body: f.body };
}

export async function runSupportTurn(
  d: SupportTurnDeps,
): Promise<SupportTurnOutcome> {
  const now = d.now ?? (() => new Date());
  const prep = await prepareSupportContext({
    admin: d.admin,
    userId: d.userId,
    conversationId: d.conversationId,
    requestId: d.requestId,
    fields: d.fields,
    accountPrivate: d.accountPrivate,
    currentMessageId: d.getUserMessage()?.id ?? null,
    trimmedContent: d.trimmedContent,
    baseSystemPrompt: d.baseSystemPrompt,
    now,
  });
  if (!prep.ok) return fromFailure(prep.failure);
  const prepared = prep.prepared;
  supportLog("context_prepared", {
    scope: prepared.scope,
    sources: prepared.includedSources.length,
    bytes: prepared.exactPromptBytes,
    omitted_history: prepared.assembled.omitted.history,
  });
  d.signal.throwIfAborted();

  let result: ChatResult;
  try {
    result = await generateChatResult(prepared.messages, {
      apiKey: d.apiKey,
      reserveBudget: d.reserveBudget,
      maxOutputTokens: SUPPORT_CHAT_MAX_OUTPUT_TOKENS,
      onDelta: d.onDelta,
      signal: d.signal,
      beforeProvider: async () => {
        // Latest privacy and sources, immediately before quota is debited and the provider is
        // contacted, so a just-accepted correction never reaches the provider.
        const fresh = await revalidatePreparedContext({
          admin: d.admin,
          userId: d.userId,
          conversationId: d.conversationId,
          supportSessionId: d.fields.supportSessionId,
          prepared,
          now,
        });
        if (!fresh.ok) throw new SupportChatAbort(fresh.failure);
        await d.beforeProvider();
      },
    });
  } catch (error) {
    if (error instanceof SupportChatAbort) return fromFailure(error.failure);
    if (error instanceof Error && error.message === "CHAT_CONTEXT_TOO_LARGE") {
      return fromFailure(FAILURES.tooLarge(false));
    }
    d.markProviderFailure(error);
    throw error;
  }
  d.signal.throwIfAborted();
  if (result.status === "incomplete" || result.status === "failed") {
    // Never a final card or saved reply for an incomplete/errored response.
    const error = new Error(result.failureCode ?? "AI_STREAM_FAILED");
    d.markProviderFailure(error);
    throw error;
  }

  const sid = d.fields.supportSessionId;
  let suppressed: string[] = [];
  if (result.proposal.state === "raw" && sid) {
    const loaded = await loadSuppressedTemplates(d.admin, d.userId, sid);
    // Cannot prove the template was not declined: drop the card, keep the text.
    if (loaded === null) {
      result = {
        ...result,
        proposal: { state: "invalid", reason: "arguments_incomplete" },
      };
    } else suppressed = loaded;
  }
  const plan = planSupportTurn({
    result,
    hasSession: sid !== null,
    scope: prepared.scope,
    includedSources: prepared.includedSources,
    selectedIntent: d.fields.selectedIntent,
    suppressedTemplates: suppressed,
  });
  if (plan.kind === "empty") {
    const error = new Error("AI_EMPTY_RESPONSE");
    d.markProviderFailure(error);
    throw error;
  }
  supportLog("turn_planned", {
    status: plan.status,
    origin: plan.origin,
    proposal: plan.proposal ? plan.proposal.template_key : null,
    dropped: plan.proposalDropped,
  });

  // Latest privacy and sources again, before anything is published or saved.
  const latest = await revalidatePreparedContext({
    admin: d.admin,
    userId: d.userId,
    conversationId: d.conversationId,
    supportSessionId: sid,
    prepared,
    now,
  });
  if (!latest.ok) return fromFailure(latest.failure);
  d.signal.throwIfAborted();

  const completedAt = now();
  const template = buildWireTemplate({
    userId: d.userId,
    requestId: d.requestId,
    conversationId: d.conversationId,
    supportSessionId: sid,
    trimmedContent: d.trimmedContent,
    userMessage: d.getUserMessage(),
    quota: d.getQuota(),
    now: completedAt,
    scope: prepared.scope,
    privacyRevision: prepared.assembled.privacyRevision,
    content: plan.content,
    origin: plan.origin,
    status: plan.status,
    proposal: plan.proposal,
    proposalDropped: plan.proposalDropped,
    sources: prepared.includedSources,
    exclusions: prepared.exclusions,
    provider: SUPPORT_CHAT_ROUTE,
    narrowedBy: prepared.narrowedBy,
  });
  const args: ConfirmChatTurnArgs = {
    user_id: d.userId,
    request_id: d.requestId,
    conversation_id: d.conversationId,
    support_session_id: sid,
    assistant_content: plan.content,
    content_origin: plan.origin,
    privacy_revision: prepared.assembled.privacyRevision,
    scope: prepared.scope,
    provider_vendor: SUPPORT_CHAT_ROUTE.vendor,
    provider_model: SUPPORT_CHAT_ROUTE.model,
    route_version: SUPPORT_CHAT_ROUTE.routeVersion,
    exclusions: prepared.exclusions,
    sources: prepared.includedSources as ContextSourceRef[],
    proposal: plan.proposal,
    content_hash: d.contentHash,
    response: template,
    response_status: 200,
  };
  return await finishConfirmed(d.admin, d.userId, d.requestId, args, d.confirm);
}

/** Turn a ConfirmOutcome into the single terminal client result. */
export async function finishConfirmed(
  admin: AdminLike,
  userId: string,
  requestId: string,
  args: ConfirmChatTurnArgs,
  opts?: ConfirmOptions,
): Promise<SupportTurnOutcome> {
  const outcome = await confirmSupportTurn(admin, args, opts);
  switch (outcome.kind) {
    case "confirmed":
      supportLog("confirmed", {
        replayed: outcome.replayed,
        proposal: !!outcome.stored.support_confirmed?.proposal_id,
      });
      return {
        status: outcome.status,
        body: renderSupportWire(outcome.stored),
        final: true,
      };
    case "rejected":
      supportLog("confirm_rejected", { code: outcome.code });
      return fromFailure(outcome.failure);
    case "reused": {
      const terminal = await readTerminalClaim(admin, userId, requestId);
      if (terminal) {
        return {
          status: terminal.status,
          body: renderSupportWire(terminal.response),
          final: true,
        };
      }
      return { ...fromFailure(FAILURES.unconfirmed()), leavePending: true };
    }
    case "ambiguous": {
      // Unknown commit state after bounded idempotent re-issues: read the canonical claim. A
      // commit whose responses were all lost is observed here and returned verbatim (same
      // ids); otherwise nothing is written and the request stays pending.
      const terminal = await readTerminalClaim(admin, userId, requestId);
      if (terminal) {
        supportLog("confirm_reconciled", { status: terminal.status });
        return {
          status: terminal.status,
          body: renderSupportWire(terminal.response),
          final: true,
        };
      }
      supportLog("confirm_unconfirmed");
      return { ...fromFailure(FAILURES.unconfirmed()), leavePending: true };
    }
  }
}

// ---------------------------------------------------------------------------
// Safety (crisis) turn: the existing detector already decided; this only records it
// truthfully (origin safety_response, no model, no card) in the same atomic receipt.
// ---------------------------------------------------------------------------
export const SAFETY_ROUTE = {
  vendor: "none",
  model: "safety_response",
  routeVersion: "1",
} as const;
const SAFETY_EXCLUSIONS = [
  "absence_metadata",
  "ai_model_not_used",
  "daily_intent",
  "health_data",
  "history",
  "inferred_affect",
  "other_conversations",
  "private_vault",
  "saved_memory",
];

export type SafetyTurnResult =
  /** The database holds this turn (confirmed now, or found stored): body is final. */
  | { kind: "served"; outcome: SupportTurnOutcome }
  /**
   * Commit state unknown. The fixed local help is returned so the person is never left
   * without it, but NOTHING further is saved and the claim stays pending under the same id:
   * a late commit is later returned verbatim by a replay. Never confirmed.
   */
  | { kind: "pending"; outcome: SupportTurnOutcome }
  /** Definitely nothing was committed (contract absent or the database refused). */
  | { kind: "fallback" };

/** A stable, NON-durable placeholder id for an unsaved reply (derived from the request id). */
export async function pendingLocalMessageId(
  requestId: string,
): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(`mindfriend:pending-safety:${requestId}`),
    ),
  );
  const h = Array.from(digest.slice(0, 16)).map((b) =>
    b.toString(16).padStart(2, "0")
  ).join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-8${
    h.slice(17, 20)
  }-${h.slice(20, 32)}`;
}

export async function confirmSafetyTurn(d: {
  admin: AdminLike;
  userId: string;
  conversationId: string;
  requestId: string;
  trimmedContent: string;
  contentHash: string;
  fields: SupportChatFields;
  accountPrivate: boolean;
  safetyText: string;
  userMessage: { id: string; created_at: string | null } | null;
  quota: { used: number; limit: number } | null;
  now?: () => Date;
  confirm?: ConfirmOptions;
}): Promise<SafetyTurnResult> {
  const now = (d.now ?? (() => new Date()))();
  const scope: ContextScope =
    d.fields.scope === "personalized" && !d.accountPrivate
      ? "personalized"
      : "conversation_only";
  const sources: ContextSourceRef[] = [{
    kind: "safety_policy",
    id: SAFETY_POLICY_SOURCE_ID,
    revision: 1,
    date: null,
  }];
  const served = (terminal: { response: Json; status: number }) => ({
    kind: "served" as const,
    outcome: {
      status: terminal.status,
      body: renderSupportWire(terminal.response),
      final: true,
    },
  });
  // No personal context is used, so a stale expected revision is harmless here: learn the
  // current one from a stale answer and retry once. The crisis response must never fail on it.
  let revision = d.fields.expectedPrivacyRevision ?? 1;
  let template: Json = {};
  for (let round = 0; round < 2; round++) {
    template = buildWireTemplate({
      userId: d.userId,
      requestId: d.requestId,
      conversationId: d.conversationId,
      supportSessionId: d.fields.supportSessionId,
      trimmedContent: d.trimmedContent,
      userMessage: d.userMessage,
      quota: d.quota,
      now,
      scope,
      privacyRevision: revision,
      content: d.safetyText,
      origin: "safety_response",
      status: "safety",
      proposal: null,
      proposalDropped: null,
      sources,
      exclusions: SAFETY_EXCLUSIONS,
      provider: SAFETY_ROUTE,
      narrowedBy: null,
    });
    const args: ConfirmChatTurnArgs = {
      user_id: d.userId,
      request_id: d.requestId,
      conversation_id: d.conversationId,
      support_session_id: d.fields.supportSessionId,
      assistant_content: d.safetyText,
      content_origin: "safety_response",
      privacy_revision: revision,
      scope,
      provider_vendor: SAFETY_ROUTE.vendor,
      provider_model: SAFETY_ROUTE.model,
      route_version: SAFETY_ROUTE.routeVersion,
      exclusions: SAFETY_EXCLUSIONS,
      sources,
      proposal: null,
      content_hash: d.contentHash,
      response: template,
      response_status: 200,
    };
    const outcome = await confirmSupportTurn(d.admin, args, d.confirm);
    if (outcome.kind === "confirmed") {
      return {
        kind: "served",
        outcome: {
          status: outcome.status,
          body: renderSupportWire(outcome.stored),
          final: true,
        },
      };
    }
    if (
      outcome.kind === "rejected" &&
      outcome.code === "PRIVACY_REVISION_STALE" &&
      outcome.currentPrivacyRevision !== undefined && round === 0
    ) {
      revision = outcome.currentPrivacyRevision;
      continue;
    }
    if (outcome.kind === "rejected") {
      // Definite non-commit (contract absent, or the database refused): the existing direct
      // save still delivers help, once, under its own receipt-less wire.
      supportLog("safety_confirm_fallback", { code: outcome.code });
      return { kind: "fallback" };
    }
    // `reused` or `ambiguous`: the canonical claim is the only authority. Read it BEFORE any
    // other durable write; a stored confirmed turn (even one whose every response was lost)
    // is returned verbatim with its original ids.
    const terminal = await readTerminalClaim(d.admin, d.userId, d.requestId);
    if (terminal && isObj(terminal.response?.support_confirmed)) {
      supportLog("safety_reconciled", { status: terminal.status });
      return served(terminal);
    }
    break;
  }
  // Unknown (or finalized elsewhere without a receipt): fixed local help, no new durable
  // message, claim untouched. Safety availability does not authorize another append.
  supportLog("safety_pending");
  const body: Json = structuredClone(template);
  body.assistantMessage = {
    ...body.assistantMessage,
    id: await pendingLocalMessageId(d.requestId),
  };
  body.message = { ...body.assistantMessage };
  body.support = {
    ...body.support,
    confirmed: false,
    persistence: "pending_reconcile",
    context_receipt: null,
  };
  return {
    kind: "pending",
    outcome: { status: 200, body, leavePending: true },
  };
}

/** Wire for a safety response saved without an atomic receipt (database fallback). */
export function safetyFallbackSupport(a: {
  requestId: string;
  conversationId: string;
  supportSessionId: string | null;
  scope: ContextScope;
}): Json {
  return {
    schema_version: SUPPORT_CHAT_CONTRACT,
    request_id: a.requestId,
    support_session_id: a.supportSessionId,
    conversation_id: a.conversationId,
    scope: a.scope,
    scope_narrowed_by: null,
    privacy_revision: null,
    content_origin: "safety_response",
    status: "safety",
    suppress_ordinary_cards: true,
    confirmed: false,
    persistence: "saved_without_receipt",
    context_receipt: null,
    proposal: null,
    proposal_dropped: null,
  };
}
