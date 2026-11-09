// Support session wire contract (docs/SUPPORT_SESSION_SPEC.md sections 8.3, 8.6, 9.3, 9.4).
//
// Pure module: no I/O, no Deno APIs. It defines the request/response types the
// `support-session` Edge function exposes, request parsing that mirrors the SQL
// validation (defence in depth; the database remains authoritative), the error-code
// table, and validation of the model's `propose_support_action` arguments.
//
// Parent integration points exported from here:
//   * SupportCapabilities, SupportSessionSnapshot, SupportMutationResponse ... wire types
//   * parseSupportRequest()            ... Edge request parsing
//   * validateSupportActionProposal()  ... post-parse validation of tool arguments (M4)
//   * ContextReceiptWire / ConfirmChatTurnArgs ... shapes for support_confirm_chat_turn

export const SUPPORT_SCHEMA_VERSION = 1 as const;

export const SUPPORT_LIMITS = {
  titleChars: 80,
  concernChars: 4000,
  stepChars: 400,
  noteChars: 1000,
  /** Per-prompt typed answer; matches the app's local 4,000-character contract. */
  responseChars: 4000,
  // Unit for every character limit here: Unicode code points (JS [...s].length ==
  // PostgreSQL char_length). Clients must count unicodeScalars, not graphemes.
  checkpointBytes: 32 * 1024,
  envelopeBytes: 128 * 1024,
  requestBodyBytes: 160 * 1024,
  proposalArgumentBytes: 8192,
  memoryChars: 500,
  confirmedMemoryLimit: 20,
  listMaxLimit: 100,
  proposalTtlMs: 24 * 60 * 60 * 1000,
} as const;

// ---------------------------------------------------------------------------
// Error codes (section 9.4) plus additive codes the server may return.
// ---------------------------------------------------------------------------
export const SUPPORT_ERROR_STATUS = {
  AUTH_REQUIRED: 401,
  NOT_FOUND: 404,
  REVISION_CONFLICT: 409,
  OPERATION_ID_REUSED: 409,
  INVALID_PAYLOAD: 400,
  PRIVACY_REVISION_STALE: 409,
  PROPOSAL_EXPIRED: 409,
  CONTENT_UNAVAILABLE: 422,
  ENTITLEMENT_REQUIRED: 402,
  RATE_LIMITED: 429,
  TEMPORARY_FAILURE: 503,
  MEMORY_LIMIT_REACHED: 409,
} as const;
export type SupportErrorCode = keyof typeof SUPPORT_ERROR_STATUS;

/** Codes a client must not retry automatically. */
export const NON_RETRYABLE: ReadonlySet<SupportErrorCode> = new Set([
  "AUTH_REQUIRED",
  "NOT_FOUND",
  "INVALID_PAYLOAD",
  "PROPOSAL_EXPIRED",
  "OPERATION_ID_REUSED",
  "CONTENT_UNAVAILABLE",
  "ENTITLEMENT_REQUIRED",
  "MEMORY_LIMIT_REACHED",
]);

export function statusForCode(code: string): number {
  return (SUPPORT_ERROR_STATUS as Record<string, number>)[code] ?? 500;
}

// ---------------------------------------------------------------------------
// Domain vocabularies
// ---------------------------------------------------------------------------
export const TEMPLATE_KEYS = [
  "ground_present_v1",
  "untangle_thought_v1",
  "choose_step_v1",
] as const;
export type TemplateKey = (typeof TEMPLATE_KEYS)[number];
export type ActivityKind = "grounding" | "untangle" | "next_step";
export const TEMPLATE_KIND: Record<TemplateKey, ActivityKind> = {
  ground_present_v1: "grounding",
  untangle_thought_v1: "untangle",
  choose_step_v1: "next_step",
};
export const REASON_CODES = [
  "current_request",
  "approved_preference",
  "selected_intent",
  "general_option",
] as const;
export type ReasonCode = (typeof REASON_CODES)[number];
export type ContextScope = "conversation_only" | "personalized";
export type SessionStatus = "open" | "closed" | "deleted";
export type ActivityStatus =
  | "ready"
  | "in_progress"
  | "paused"
  | "completed"
  | "stopped";
export type ReflectionOutcome = "helpful" | "not_for_me" | "not_sure" | "skip";
export type StepState = "draft" | "saved" | "self_reported_done" | "dismissed";

export const MUTATION_KINDS = [
  "create",
  "update_session",
  "accept_proposal",
  "start_activity",
  "checkpoint_activity",
  "finish_activity",
  "discard_activity_answers",
  "record_reflection",
  "delete_session",
] as const;
export type MutationKind = (typeof MUTATION_KINDS)[number];

export const MEMORY_MUTATION_KINDS = [
  "memory_edit",
  "memory_stop_using",
  "memory_resume_using",
  "memory_forget",
  "candidate_approve",
  "candidate_dismiss",
  "suppress_source",
  "unsuppress_source",
] as const;
export type MemoryMutationKind = (typeof MEMORY_MUTATION_KINDS)[number];

// ---------------------------------------------------------------------------
// Wire types
// ---------------------------------------------------------------------------
export interface SupportCapabilities {
  /** 0 = not deployed. Negotiated separately (section 10.1). */
  session_contract: number;
  context_policy: number;
  voice_context: number;
  privacy_revision?: boolean;
  memory_lifecycle?: boolean;
  chat_confirmation?: boolean;
  status?: "ok" | "not_deployed";
}

export interface SupportSessionRecord {
  id: string;
  conversation_id: string | null;
  previous_session_id: string | null;
  selected_activity_id: string | null;
  title: string;
  concern: string | null;
  status: SessionStatus;
  context_scope: ContextScope;
  revision: number;
  suppressed_templates: TemplateKey[];
  created_at: string;
  updated_at: string;
  closed_at: string | null;
  deleted_at: string | null;
}

export interface SupportActivityRecord {
  id: string;
  template_key: TemplateKey;
  template_version: number;
  kind: ActivityKind;
  status: ActivityStatus;
  stop_reason: string | null;
  canonical_ref_type: "exercise_session" | "journal_entry" | null;
  canonical_ref_id: string | null;
  checkpoint: Record<string, unknown> | null;
  result: Record<string, unknown> | null;
  reflection: {
    outcome: ReflectionOutcome;
    note: string | null;
    share_note: boolean;
    shareable_text: string | null;
  } | null;
  active_ms: number;
  last_changed_revision: number;
  created_at: string;
  updated_at: string;
  finished_at: string | null;
}

export interface SupportProposalRecord {
  id: string;
  template_key: TemplateKey;
  reason_code: ReasonCode;
  basis_kind: "companion_memory" | "message" | "activity" | null;
  basis_ref: string | null;
  suggested_step: string | null;
  status: "offered";
  expires_at: string;
}

export interface SupportSessionSnapshot {
  session: SupportSessionRecord;
  activities: SupportActivityRecord[];
  /** Only currently actionable proposals (offered, unexpired, current privacy revision). */
  proposals: SupportProposalRecord[];
  privacy_revision: number;
}

export interface SupportMutationSuccess {
  ok: true;
  operation_id: string;
  kind: MutationKind;
  revision: number;
  no_op: boolean;
  replayed: boolean;
  event_id: string | null;
  activity_id: string | null;
  sync_status: "synced";
  server_time: string;
  snapshot: SupportSessionSnapshot | null;
  /** finish_activity(completed, grounding): canonical reward result. */
  xp?: { amount: number; new_xp: number; new_level: number; level_up: boolean };
  closed?: boolean;
  deleted?: boolean;
  /** Set on a no-op refused for a reason: activity_finished | activity_discarded. */
  reason?: string;
}
export interface SupportFailure {
  ok: false;
  code: SupportErrorCode;
  message?: string | null;
  /** REVISION_CONFLICT */
  current_revision?: number;
  snapshot?: SupportSessionSnapshot | null;
  current_privacy_revision?: number;
  /** REVISION_CONFLICT on a memory correction. */
  memory?: { id: string; category: string; content: string; revision: number };
}
export type SupportMutationResponse = SupportMutationSuccess | SupportFailure;

/** Source reference stored by a context receipt: identifiers and minimal labels only. */
export interface ContextSourceRef {
  kind:
    | "message"
    | "companion_memory"
    | "daily_intent"
    | "session"
    | "activity_result"
    | "safety_policy";
  id: string;
  revision: number;
  date: string | null;
}
export const SAFETY_POLICY_SOURCE_ID = "00000000-0000-0000-0000-000000000001";

/** Argument for the service-only support_confirm_chat_turn RPC. */
export interface ConfirmChatTurnArgs {
  user_id: string;
  request_id: string;
  conversation_id: string;
  support_session_id: string | null;
  assistant_content: string;
  content_origin: "model" | "interface_fallback" | "safety_response";
  privacy_revision: number;
  scope: ContextScope;
  /** The route that ACTUALLY served the request; never hard-coded by the policy. */
  provider_vendor: string;
  provider_model: string;
  route_version: string;
  exclusions: string[];
  sources: ContextSourceRef[];
  proposal: ValidatedProposal | null;
  /** SHA-256 hex of the trimmed user content, identical to the chat_requests claim. */
  content_hash: string;
  /** Terminal response stored with the request claim in the same transaction. */
  response: Record<string, unknown>;
  /** 2xx status stored with the response. */
  response_status: number;
}
export interface ConfirmChatTurnResult {
  ok: boolean;
  replayed?: boolean;
  message_id?: string;
  receipt_id?: string;
  proposal_id?: string | null;
  proposal_dropped?: string | null;
  code?: SupportErrorCode;
  current_privacy_revision?: number;
}

// ---------------------------------------------------------------------------
// Request parsing
// ---------------------------------------------------------------------------
export type Parsed<T> = { ok: true; value: T } | {
  ok: false;
  code: "INVALID_PAYLOAD";
  message: string;
};
const bad = (
  message: string,
): { ok: false; code: "INVALID_PAYLOAD"; message: string } => ({
  ok: false,
  code: "INVALID_PAYLOAD",
  message,
});

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export const isUuid = (v: unknown): v is string =>
  typeof v === "string" && UUID_RE.test(v);
const isObj = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);
/** Text of a value exactly as PostgreSQL `jsonb::text` renders it (", " and ": " separators). */
export function jsonbText(v: unknown): string {
  if (v === null || typeof v !== "object") return JSON.stringify(v) ?? "null";
  if (Array.isArray(v)) {
    return v.length ? `[${v.map(jsonbText).join(", ")}]` : "[]";
  }
  const e = Object.entries(v as Record<string, unknown>).filter(([, x]) =>
    x !== undefined
  );
  return e.length
    ? `{${
      e.map(([k, x]) => `${JSON.stringify(k)}: ${jsonbText(x)}`).join(", ")
    }}`
    : "{}";
}
/** Exact serialized size the database will measure with octet_length(jsonb::text). */
export const jsonbBytes = (v: unknown): number =>
  new TextEncoder().encode(jsonbText(v)).length;
const utf8 = (s: string) => new TextEncoder().encode(s).length;

export interface MutationEnvelope {
  schema_version: 1;
  operation_id: string;
  session_id: string;
  expected_revision: number | null;
  kind: MutationKind;
  payload: Record<string, unknown>;
  client_occurred_at?: string;
}

function checkString(
  o: Record<string, unknown>,
  key: string,
  max: number,
): string | null {
  const v = o[key];
  if (v === undefined || v === null) return null;
  if (typeof v !== "string") throw new Error(`${key} must be a string`);
  if ([...v].length > max) throw new Error(`${key} is too long`);
  return v;
}

/** Shape checks that mirror the SQL handlers; unknown fields are rejected. */
const PAYLOAD_FIELDS: Record<MutationKind, readonly string[]> = {
  create: [
    "title",
    "concern",
    "context_scope",
    "conversation_id",
    "previous_session_id",
  ],
  update_session: [
    "title",
    "concern",
    "context_scope",
    "conversation_id",
    "attach_conversation_id",
    "close",
    "decline_template",
  ],
  accept_proposal: ["proposal_id", "activity_id", "previous_disposition"],
  start_activity: [
    "activity_id",
    "template_key",
    "exercise_id",
    "previous_disposition",
  ],
  checkpoint_activity: ["activity_id", "checkpoint", "active_ms", "pause"],
  finish_activity: [
    "activity_id",
    "outcome",
    "reason",
    "result",
    "active_ms",
    "rating",
    "exercise_id",
    "discard_content",
    "checkpoint",
  ],
  discard_activity_answers: ["activity_id"],
  record_reflection: [
    "activity_id",
    "outcome",
    "note",
    "share_note",
    "shareable_text",
  ],
  delete_session: [],
};

export function parseMutationEnvelope(raw: unknown): Parsed<MutationEnvelope> {
  if (!isObj(raw)) return bad("envelope must be an object");
  if (raw.schema_version !== SUPPORT_SCHEMA_VERSION) {
    return bad("schema_version 1 required");
  }
  if (!isUuid(raw.operation_id) || !isUuid(raw.session_id)) {
    return bad("operation_id and session_id must be UUIDs");
  }
  const kind = raw.kind;
  if (
    typeof kind !== "string" ||
    !(MUTATION_KINDS as readonly string[]).includes(kind)
  ) return bad("unknown kind");
  const k = kind as MutationKind;
  const exp = raw.expected_revision;
  if (k === "create") {
    if (exp !== null && exp !== undefined) {
      return bad("expected_revision must be null on create");
    }
  } else if (!(typeof exp === "number" && Number.isInteger(exp) && exp >= 1)) {
    return bad("expected_revision must be a positive integer");
  }
  const payload = raw.payload === undefined ? {} : raw.payload;
  if (!isObj(payload)) return bad("payload must be an object");
  for (const key of Object.keys(payload)) {
    if (!PAYLOAD_FIELDS[k].includes(key)) {
      return bad(`unknown payload field: ${key}`);
    }
  }
  try {
    switch (k) {
      case "create":
        checkString(payload, "title", SUPPORT_LIMITS.titleChars);
        checkString(payload, "concern", SUPPORT_LIMITS.concernChars);
        if (
          payload.context_scope !== undefined &&
          payload.context_scope !== "conversation_only" &&
          payload.context_scope !== "personalized"
        ) {
          return bad("unknown context_scope");
        }
        for (const f of ["conversation_id", "previous_session_id"]) {
          if (payload[f] != null && !isUuid(payload[f])) {
            return bad(`${f} must be a UUID`);
          }
        }
        break;
      case "update_session":
        checkString(payload, "title", SUPPORT_LIMITS.titleChars);
        checkString(payload, "concern", SUPPORT_LIMITS.concernChars);
        if (
          payload.context_scope != null &&
          payload.context_scope !== "conversation_only" &&
          payload.context_scope !== "personalized"
        ) {
          return bad("unknown context_scope");
        }
        if (
          payload.decline_template != null &&
          !(TEMPLATE_KEYS as readonly string[]).includes(
            payload.decline_template as string,
          )
        ) return bad("decline_template must be a catalog template key");
        for (const f of ["conversation_id", "attach_conversation_id"]) {
          if (payload[f] != null && !isUuid(payload[f])) {
            return bad(`${f} must be a UUID`);
          }
        }
        if (
          payload.conversation_id != null &&
          payload.attach_conversation_id != null &&
          payload.conversation_id !== payload.attach_conversation_id
        ) return bad("conversation_id and attach_conversation_id disagree");
        if (
          payload.close != null && payload.close !== "end_unfinished" &&
          payload.close !== "if_idle"
        ) return bad("close must be end_unfinished or if_idle");
        break;
      case "accept_proposal":
        if (!isUuid(payload.proposal_id) || !isUuid(payload.activity_id)) {
          return bad("proposal_id and activity_id must be UUIDs");
        }
        if (
          payload.previous_disposition != null &&
          payload.previous_disposition !== "save" &&
          payload.previous_disposition !== "end"
        ) return bad("previous_disposition must be save or end");
        break;
      case "start_activity":
        if (!isUuid(payload.activity_id)) {
          return bad("activity_id must be a UUID");
        }
        if (
          payload.template_key != null &&
          !(TEMPLATE_KEYS as readonly string[]).includes(
            payload.template_key as string,
          )
        ) return bad("unknown template_key");
        if (payload.exercise_id != null && !isUuid(payload.exercise_id)) {
          return bad("exercise_id must be a UUID");
        }
        if (
          payload.previous_disposition != null &&
          payload.previous_disposition !== "save" &&
          payload.previous_disposition !== "end"
        ) return bad("previous_disposition must be save or end");
        break;
      case "checkpoint_activity": {
        if (!isUuid(payload.activity_id)) {
          return bad("activity_id must be a UUID");
        }
        const cp = payload.checkpoint;
        if (!isObj(cp) || cp.version !== 1) {
          return bad("checkpoint version 1 object required");
        }
        if (jsonbBytes(cp) > SUPPORT_LIMITS.checkpointBytes) {
          return bad("checkpoint exceeds 32 KiB");
        }
        if (
          !(typeof payload.active_ms === "number" &&
            Number.isInteger(payload.active_ms) && payload.active_ms >= 0)
        ) return bad("active_ms must be a non-negative integer");
        if (payload.pause !== undefined && typeof payload.pause !== "boolean") {
          return bad("pause must be boolean");
        }
        promptCheck(cp);
        // Only a saved practical step needs step text; the database knows the template
        // and requires it for choose_step_v1. Grounding/untangle pauses carry no step.
        stepCheck(
          cp.step,
          payload.pause === true && cp.step != null,
          payload.pause === true ? "saved" : null,
        );
        break;
      }
      case "finish_activity": {
        if (!isUuid(payload.activity_id)) {
          return bad("activity_id must be a UUID");
        }
        if (payload.outcome !== "completed" && payload.outcome !== "stopped") {
          return bad("outcome must be completed or stopped");
        }
        checkString(payload, "reason", 40);
        if (payload.result != null) {
          if (!isObj(payload.result)) return bad("result must be an object");
          if (
            jsonbBytes(payload.result) >
              SUPPORT_LIMITS.checkpointBytes
          ) return bad("result exceeds 32 KiB");
        }
        if (
          payload.active_ms !== undefined &&
          !(typeof payload.active_ms === "number" &&
            Number.isInteger(payload.active_ms) && payload.active_ms >= 0)
        ) return bad("active_ms must be a non-negative integer");
        if (
          payload.rating != null &&
          !(typeof payload.rating === "number" &&
            Number.isInteger(payload.rating) && payload.rating >= 1 &&
            payload.rating <= 5)
        ) return bad("rating must be 1-5");
        if (payload.exercise_id != null && !isUuid(payload.exercise_id)) {
          return bad("exercise_id must be a UUID");
        }
        if (
          payload.discard_content !== undefined &&
          typeof payload.discard_content !== "boolean"
        ) return bad("discard_content must be boolean");
        if (payload.checkpoint != null) {
          const fc = payload.checkpoint;
          if (!isObj(fc) || fc.version !== 1) {
            return bad("final checkpoint must be a version 1 object");
          }
          if (jsonbBytes(fc) > SUPPORT_LIMITS.checkpointBytes) {
            return bad("checkpoint exceeds 32 KiB");
          }
          promptCheck(fc);
        }
        if (payload.outcome === "completed") {
          if (payload.reason === "skipped_all") {
            return bad("an all-skipped activity is stopped, not completed");
          }
          const res = payload.result as
            | Record<string, unknown>
            | null
            | undefined;
          // Next-step completion must carry the user's own non-empty, self-reported step.
          if (res && isObj(res.step)) {
            stepCheck(res.step, true, "self_reported_done");
          }
        }
        break;
      }
      case "discard_activity_answers":
        if (!isUuid(payload.activity_id)) {
          return bad("activity_id must be a UUID");
        }
        break;
      case "record_reflection":
        if (!isUuid(payload.activity_id)) {
          return bad("activity_id must be a UUID");
        }
        if (
          !["helpful", "not_for_me", "not_sure", "skip"].includes(
            payload.outcome as string,
          )
        ) return bad("outcome must be helpful, not_for_me, not_sure or skip");
        checkString(payload, "note", SUPPORT_LIMITS.noteChars);
        checkString(payload, "shareable_text", SUPPORT_LIMITS.noteChars);
        if (
          payload.share_note !== undefined &&
          typeof payload.share_note !== "boolean"
        ) return bad("share_note must be boolean");
        break;
      case "delete_session":
        break;
    }
  } catch (e) {
    return bad(e instanceof Error ? e.message : "invalid payload");
  }
  const envelope: MutationEnvelope = {
    schema_version: 1,
    operation_id: raw.operation_id,
    session_id: raw.session_id,
    expected_revision: k === "create" ? null : (exp as number),
    kind: k,
    payload,
  };
  if (typeof raw.client_occurred_at === "string") {
    envelope.client_occurred_at = raw.client_occurred_at;
  }
  if (jsonbBytes(envelope) > SUPPORT_LIMITS.envelopeBytes) {
    return bad("envelope too large");
  }
  return { ok: true, value: envelope };
}

/** Template v1 stable prompt identifiers (section 5.4). */
export const PROMPT_IDS: Record<TemplateKey, readonly string[]> = {
  ground_present_v1: ["see", "feel", "hear", "smell", "taste"],
  untangle_thought_v1: ["on_mind", "certain_unclear", "fairer_way"],
  choose_step_v1: ["action", "smaller"],
};
const ALL_PROMPT_IDS: readonly string[] = [
  ...new Set(Object.values(PROMPT_IDS).flat()),
];

/** Shape check for checkpoint prompt fields; the database narrows ids to the activity's template. */
function promptCheck(cp: Record<string, unknown>): void {
  for (const f of ["completed_steps", "skipped_steps"]) {
    const v = cp[f];
    if (v === undefined || v === null) continue;
    if (
      !Array.isArray(v) ||
      !v.every((x) => typeof x === "string" && ALL_PROMPT_IDS.includes(x))
    ) throw new Error(`${f} must list known prompt ids`);
  }
  if (
    cp.current_step != null &&
    !(typeof cp.current_step === "string" &&
      ALL_PROMPT_IDS.includes(cp.current_step))
  ) throw new Error("unknown current_step");
  if (cp.responses != null) {
    if (!isObj(cp.responses)) throw new Error("responses must be an object");
    for (const [k, v] of Object.entries(cp.responses)) {
      if (
        !ALL_PROMPT_IDS.includes(k) || typeof v !== "string" ||
        [...v].length > SUPPORT_LIMITS.responseChars
      ) {
        throw new Error(
          "responses need known prompt ids and strings up to 4000 characters",
        );
      }
    }
  }
}

function stepCheck(
  step: unknown,
  requireText: boolean,
  requiredState: StepState | null,
): void {
  if (step === undefined || step === null) {
    if (requireText) throw new Error("step is required");
    return;
  }
  if (!isObj(step)) throw new Error("step must be an object");
  const text = checkString(step, "action_text", SUPPORT_LIMITS.stepChars);
  if (requireText && (text === null || text.trim() === "")) {
    throw new Error("step text must not be empty");
  }
  if (
    step.state !== undefined &&
    !["draft", "saved", "self_reported_done", "dismissed"].includes(
      step.state as string,
    )
  ) {
    throw new Error("unknown step state");
  }
  if (requiredState && step.state !== requiredState) {
    throw new Error(`step state must be ${requiredState}`);
  }
}

export interface MemoryEnvelope {
  schema_version: 1;
  operation_id: string;
  kind: MemoryMutationKind;
  payload: Record<string, unknown>;
}
export function parseMemoryEnvelope(raw: unknown): Parsed<MemoryEnvelope> {
  if (!isObj(raw)) return bad("envelope must be an object");
  if (raw.schema_version !== SUPPORT_SCHEMA_VERSION) {
    return bad("schema_version 1 required");
  }
  if (!isUuid(raw.operation_id)) return bad("operation_id must be a UUID");
  if (
    typeof raw.kind !== "string" ||
    !(MEMORY_MUTATION_KINDS as readonly string[]).includes(raw.kind)
  ) return bad("unknown kind");
  const payload = raw.payload === undefined ? {} : raw.payload;
  if (!isObj(payload)) return bad("payload must be an object");
  const allowed = [
    "memory_id",
    "fragment_id",
    "id",
    "content",
    "category",
    "source_kind",
    "expected_revision",
  ];
  for (const key of Object.keys(payload)) {
    if (!allowed.includes(key)) return bad(`unknown payload field: ${key}`);
  }
  for (const f of ["memory_id", "fragment_id", "id"]) {
    if (payload[f] != null && !isUuid(payload[f])) {
      return bad(`${f} must be a UUID`);
    }
  }
  if (
    payload.content != null &&
    (typeof payload.content !== "string" ||
      [...payload.content].length > SUPPORT_LIMITS.memoryChars)
  ) return bad("content must be a string up to 500 characters");
  if (
    raw.kind === "memory_edit" &&
    (typeof payload.content !== "string" || payload.content.trim() === "")
  ) return bad("content required");
  if (
    payload.expected_revision != null &&
    !(typeof payload.expected_revision === "number" &&
      Number.isInteger(payload.expected_revision) &&
      payload.expected_revision >= 1)
  ) return bad("expected_revision must be a positive integer");
  if (raw.kind === "memory_edit" && payload.expected_revision == null) {
    return bad("expected_revision is required for a correction");
  }
  if (raw.kind === "suppress_source" || raw.kind === "unsuppress_source") {
    if (
      payload.source_kind !== "conversation" &&
      payload.source_kind !== "message"
    ) return bad("source_kind must be conversation or message");
    if (!isUuid(payload.id)) return bad("id required");
  } else if (!isUuid(payload.memory_id) && !isUuid(payload.fragment_id)) {
    return bad("memory_id or fragment_id required");
  }
  return {
    ok: true,
    value: {
      schema_version: 1,
      operation_id: raw.operation_id,
      kind: raw.kind as MemoryMutationKind,
      payload,
    },
  };
}

export type SupportRequest =
  | { op: "capabilities" }
  | { op: "get"; session_id: string; after_seq: number; limit: number }
  | {
    op: "list";
    limit: number;
    cursor: { updated_at: string; id: string } | null;
    status: SessionStatus | null;
    direction: "asc" | "desc";
    include_deleted: boolean;
  }
  | { op: "mutate"; envelope: MutationEnvelope }
  | { op: "memory_list" }
  | { op: "memory_mutate"; envelope: MemoryEnvelope }
  | { op: "receipt"; request_id: string };

export function parseSupportRequest(body: unknown): Parsed<SupportRequest> {
  if (!isObj(body)) return bad("body must be an object");
  switch (body.op) {
    case "capabilities":
      return { ok: true, value: { op: "capabilities" } };
    case "get": {
      if (body.schema_version !== SUPPORT_SCHEMA_VERSION) {
        return bad("schema_version 1 required");
      }
      if (!isUuid(body.session_id)) return bad("session_id must be a UUID");
      const after = body.after_seq ?? 0;
      const limit = body.limit ?? 100;
      if (
        !(Number.isInteger(after) && (after as number) >= 0) ||
        !(Number.isInteger(limit) && (limit as number) >= 1 &&
          (limit as number) <= 200)
      ) return bad("bad after_seq or limit");
      return {
        ok: true,
        value: {
          op: "get",
          session_id: body.session_id,
          after_seq: after as number,
          limit: limit as number,
        },
      };
    }
    case "list": {
      if (body.schema_version !== SUPPORT_SCHEMA_VERSION) {
        return bad("schema_version 1 required");
      }
      const limit = body.limit ?? 50;
      if (
        !(Number.isInteger(limit) && (limit as number) >= 1 &&
          (limit as number) <= SUPPORT_LIMITS.listMaxLimit)
      ) return bad("limit must be 1-100");
      let cursor: { updated_at: string; id: string } | null = null;
      if (body.cursor != null) {
        const c = body.cursor;
        if (
          !isObj(c) || typeof c.updated_at !== "string" ||
          Number.isNaN(Date.parse(c.updated_at)) || !isUuid(c.id)
        ) return bad("cursor needs updated_at and id");
        cursor = { updated_at: c.updated_at, id: c.id };
      }
      const status = body.status ?? null;
      if (
        status !== null &&
        !["open", "closed", "deleted"].includes(status as string)
      ) return bad("unknown status filter");
      const direction = body.direction ?? "desc";
      if (direction !== "asc" && direction !== "desc") {
        return bad("direction must be asc or desc");
      }
      return {
        ok: true,
        value: {
          op: "list",
          limit: limit as number,
          cursor,
          status: status as SessionStatus | null,
          direction,
          include_deleted: body.include_deleted === true,
        },
      };
    }
    case "mutate": {
      const { op: _op, ...envelope } = body;
      const parsed = parseMutationEnvelope(envelope);
      return parsed.ok
        ? { ok: true, value: { op: "mutate", envelope: parsed.value } }
        : parsed;
    }
    case "memory_list":
      return { ok: true, value: { op: "memory_list" } };
    case "memory_mutate": {
      const { op: _op, ...envelope } = body;
      const parsed = parseMemoryEnvelope(envelope);
      return parsed.ok
        ? { ok: true, value: { op: "memory_mutate", envelope: parsed.value } }
        : parsed;
    }
    case "receipt":
      if (!isUuid(body.request_id)) return bad("request_id must be a UUID");
      return {
        ok: true,
        value: { op: "receipt", request_id: body.request_id },
      };
    default:
      return bad("unknown op");
  }
}

// ---------------------------------------------------------------------------
// propose_support_action (section 8.6): post-parse validation
// ---------------------------------------------------------------------------
export interface ValidatedProposal {
  template_key: TemplateKey;
  reason_code: ReasonCode;
  basis_kind: "companion_memory" | "message" | "activity" | null;
  basis_ref: string | null;
  suggested_step: string | null;
}

// The Responses `function` tool declaration is owned by _shared/openai-chat.ts
// (SUPPORT_ACTION_TOOL): strict, all four fields required, additionalProperties:false,
// template_key / reason_code enums, one function, parallel calls off. A second copy here had
// no callers and drifted (description, maxLength), so it was removed. The 400-character
// suggested_step bound is enforced after parsing by validateSupportActionProposal().

/** Names of top-level keys that appear more than once in raw JSON text. */
export function duplicateTopLevelKeys(json: string): string[] {
  const seen = new Set<string>();
  const dups = new Set<string>();
  let depth = 0;
  for (let i = 0; i < json.length; i++) {
    const ch = json[i];
    if (ch === '"') {
      let j = i + 1;
      let s = "";
      while (j < json.length && json[j] !== '"') {
        if (json[j] === "\\") {
          s += json[j] + (json[j + 1] ?? "");
          j += 2;
          continue;
        }
        s += json[j++];
      }
      let k = j + 1;
      while (k < json.length && /\s/.test(json[k])) k++;
      if (depth === 1 && json[k] === ":") {
        let key = s;
        try {
          key = JSON.parse(`"${s}"`) as string;
        } catch { /* keep raw spelling */ }
        if (seen.has(key)) dups.add(key);
        seen.add(key);
      }
      i = j;
    } else if (ch === "{" || ch === "[") depth++;
    else if (ch === "}" || ch === "]") depth--;
  }
  return [...dups];
}

export interface ProposalValidationContext {
  scope: ContextScope;
  /** Sources actually included in THIS request's context (from the draft receipt). */
  includedSources: ReadonlyArray<Pick<ContextSourceRef, "kind" | "id">>;
  /** Intent the person selected for this session, if any (template key). */
  selectedIntent?: TemplateKey | null;
  /** Templates the person declined this session (not_for_me / Not now). */
  suppressedTemplates?: ReadonlyArray<string>;
}
export type ProposalValidation =
  | { ok: true; proposal: ValidatedProposal; downgraded: boolean }
  | { ok: false; reason: string };

/**
 * Validate the model's tool arguments. Anything invalid yields `ok:false` so the caller
 * keeps the completed text, drops the card and offers the manual chooser; it must NOT
 * make a second paid generation to repair it (section 8.6).
 */
export function validateSupportActionProposal(
  rawArguments: string,
  ctx: ProposalValidationContext,
): ProposalValidation {
  if (utf8(rawArguments) > SUPPORT_LIMITS.proposalArgumentBytes) {
    return { ok: false, reason: "arguments too large" };
  }
  if (duplicateTopLevelKeys(rawArguments).length > 0) {
    return { ok: false, reason: "duplicate keys" };
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawArguments);
  } catch {
    return { ok: false, reason: "malformed JSON" };
  }
  if (!isObj(parsed)) {
    return { ok: false, reason: "arguments must be an object" };
  }
  const allowed = new Set([
    "template_key",
    "reason_code",
    "basis_ref",
    "suggested_step",
  ]);
  for (const key of Object.keys(parsed)) {
    if (!allowed.has(key)) return { ok: false, reason: `unknown key ${key}` };
  }
  for (const key of allowed) {
    if (!(key in parsed)) return { ok: false, reason: `missing key ${key}` };
  }
  const { template_key, reason_code, basis_ref, suggested_step } =
    parsed as Record<string, unknown>;
  if (
    typeof template_key !== "string" ||
    !(TEMPLATE_KEYS as readonly string[]).includes(template_key)
  ) return { ok: false, reason: "unknown template" };
  if (
    typeof reason_code !== "string" ||
    !(REASON_CODES as readonly string[]).includes(reason_code)
  ) return { ok: false, reason: "unknown reason" };
  if (basis_ref !== null && typeof basis_ref !== "string") {
    return { ok: false, reason: "basis_ref type" };
  }
  if (suggested_step !== null && typeof suggested_step !== "string") {
    return { ok: false, reason: "suggested_step type" };
  }
  const tk = template_key as TemplateKey;
  if (ctx.suppressedTemplates?.includes(tk)) {
    return { ok: false, reason: "template declined this session" };
  }
  let step: string | null = null;
  if (suggested_step !== null) {
    if (tk !== "choose_step_v1") {
      return { ok: false, reason: "suggested_step only for choose_step_v1" };
    }
    const trimmed = suggested_step.trim();
    if ([...trimmed].length > SUPPORT_LIMITS.stepChars) {
      return { ok: false, reason: "suggested_step too long" };
    }
    step = trimmed === "" ? null : trimmed;
  }

  // Basis and reason must be provable from this request's real context; otherwise
  // downgrade to a general option rather than fabricating a rationale.
  let reason = reason_code as ReasonCode;
  let basisKind: ValidatedProposal["basis_kind"] = null;
  let basisRef: string | null = null;
  let downgraded = false;
  if (basis_ref !== null) {
    const hit = isUuid(basis_ref)
      ? ctx.includedSources.find((s) =>
        s.id === basis_ref.toLowerCase() || s.id === basis_ref
      )
      : undefined;
    const kindMap: Record<string, ValidatedProposal["basis_kind"]> = {
      companion_memory: "companion_memory",
      message: "message",
      activity_result: "activity",
    };
    if (
      hit && kindMap[hit.kind] &&
      !(hit.kind === "companion_memory" && ctx.scope !== "personalized")
    ) {
      basisKind = kindMap[hit.kind];
      basisRef = hit.id;
    } else {
      downgraded = true;
    }
  }
  if (
    reason === "approved_preference" &&
    (basisKind !== "companion_memory" || ctx.scope !== "personalized")
  ) {
    reason = "general_option";
    downgraded = true;
  }
  if (reason === "selected_intent" && ctx.selectedIntent !== tk) {
    reason = "general_option";
    downgraded = true;
  }
  if (reason === "general_option") {
    basisKind = null;
    basisRef = null;
  }
  return {
    ok: true,
    downgraded,
    proposal: {
      template_key: tk,
      reason_code: reason,
      basis_kind: basisKind,
      basis_ref: basisRef,
      suggested_step: step,
    },
  };
}

/** Deterministic interface text for a valid proposal with no model prose (section 8.6). */
export function interfaceFallbackText(template: TemplateKey): string {
  switch (template) {
    case "ground_present_v1":
      return "App option: Try a short grounding activity, or keep talking.";
    case "untangle_thought_v1":
      return "App option: Untangle a thought step by step, or keep talking.";
    case "choose_step_v1":
      return "App option: Choose one small next step, or keep talking.";
  }
}
