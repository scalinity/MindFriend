// Provider transport only. Authentication, ownership and quotas stay in the caller.
export const CHAT_MODEL = "gpt-6-luna";
export const MAX_PROMPT_BYTES = 128_000;

export interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

// ---------------------------------------------------------------------------
// Support-action declaration (Responses function tool, syntax checked against the
// official openai-node 7.43 Responses types: flat `{type:"function", name,
// description, parameters, strict}` tools; `parallel_tool_calls`; function_call
// output items with `id`/`call_id`/`name`/`arguments`; and the
// `response.function_call_arguments.{delta,done}` events keyed by `item_id`).
// This is a declaration of a suggested UI action. It is never executed here.
// ---------------------------------------------------------------------------
export const SUPPORT_ACTION_TOOL_NAME = "propose_support_action";
export const MAX_TOOL_ARGUMENT_BYTES = 8_192;
export const SUPPORT_TEMPLATE_KEYS = ["ground_present_v1", "untangle_thought_v1", "choose_step_v1"] as const;
export const SUPPORT_REASON_CODES = [
  "current_request",
  "approved_preference",
  "selected_intent",
  "general_option",
] as const;

export const SUPPORT_ACTION_TOOL = {
  type: "function",
  name: SUPPORT_ACTION_TOOL_NAME,
  description: "Optionally suggest one in-app support activity card. Omit unless it clearly fits.",
  strict: true,
  parameters: {
    type: "object",
    properties: {
      template_key: { type: "string", enum: [...SUPPORT_TEMPLATE_KEYS] },
      reason_code: { type: "string", enum: [...SUPPORT_REASON_CODES] },
      basis_ref: { type: ["string", "null"] },
      suggested_step: { type: ["string", "null"] },
    },
    required: ["template_key", "reason_code", "basis_ref", "suggested_step"],
    additionalProperties: false,
  },
} as const;

const SUPPORT_REQUEST_EXTRAS = {
  tools: [SUPPORT_ACTION_TOOL],
  tool_choice: "auto",
  parallel_tool_calls: false,
} as const;

const encoder = new TextEncoder();
const byteLength = (value: string) => encoder.encode(value).length;

/** Bytes the tool declaration adds to the provider request; reserve them when trimming history. */
export const SUPPORT_ACTION_OVERHEAD_BYTES = byteLength(JSON.stringify(SUPPORT_REQUEST_EXTRAS));

// Keep the system prompt and current message intact, dropping oldest history first.
// `reservedBytes` reserves room for request overhead (for example the tool declaration)
// so only history, never the current input or privacy boundaries, is dropped for it.
export function trimChatContext(messages: ChatMessage[], options: { reservedBytes?: number } = {}): ChatMessage[] {
  const reserved = options.reservedBytes ?? 0;
  const bounded = messages.slice();
  while (byteLength(JSON.stringify(bounded)) + reserved > MAX_PROMPT_BYTES) {
    if (bounded.length <= 2) throw new Error("CHAT_CONTEXT_TOO_LARGE");
    bounded.splice(1, 1);
  }
  return bounded;
}

// ---------------------------------------------------------------------------
// Typed result
// ---------------------------------------------------------------------------
export type ProposalInvalidReason =
  | "multiple_calls"
  | "duplicate_call"
  | "unknown_tool"
  | "unsupported_item"
  | "unknown_item"
  | "arguments_incomplete"
  | "arguments_too_large"
  | "arguments_malformed"
  | "call_not_completed"
  | "duplicate_item"
  | "envelope_mismatch";

/**
 * Raw model proposal. `arguments` is the completed argument STRING, untouched:
 * the support-contract policy owns every semantic check (template, basis,
 * ownership, privacy, step text). Nothing here is executable or actionable.
 */
export type ChatProposal =
  | { state: "none" }
  | { state: "raw"; callId: string; itemId: string | null; name: typeof SUPPORT_ACTION_TOOL_NAME; arguments: string }
  | { state: "invalid"; reason: ProposalInvalidReason };

export interface ChatUsage {
  inputTokens?: number;
  outputTokens?: number;
  totalTokens?: number;
  cachedInputTokens?: number;
  cacheWriteTokens?: number;
}

export interface ChatResult {
  /** completed: provider reported response.completed. refused: refusal, no proposal. incomplete/failed: provider terminal state. */
  status: "completed" | "refused" | "incomplete" | "failed";
  /** Completed conversational text in output order. Empty for tool-only, refused, incomplete and failed results. */
  text: string;
  refusal?: string;
  proposal: ChatProposal;
  usage?: ChatUsage;
  responseId?: string;
  /** Legacy error code the string wrapper throws for incomplete/failed results. */
  failureCode?: "AI_STREAM_FAILED" | "AI_TERMINAL_FAILED";
}

type Options = {
  apiKey: string;
  reserveBudget: (microdollars: number) => Promise<boolean>;
  beforeProvider?: () => Promise<void>;
  maxOutputTokens?: number;
  onDelta?: (text: string) => void;
  signal?: AbortSignal;
  fetcher?: typeof fetch;
};

interface CallState {
  itemId: string | null;
  callId: string;
  name: string;
  args: string;
  argBytes: number;
  oversize: boolean;
  completedArgs: string | null;
  notCompleted: boolean;
}

class Collector {
  // Text is keyed by the actual item identity (output position when the provider omits it).
  texts = new Map<string, { output: number; content: number; text: string }>();
  refusal = "";
  calls: CallState[] = [];
  byItem = new Map<string, CallState>();
  seenIds = new Map<string, "call" | "other">();
  fault: ProposalInvalidReason | null = null;
  /** A message/reasoning item reported an explicit non-completed status. */
  turnIncomplete = false;

  noteFault(reason: ProposalInvalidReason) {
    this.fault ??= reason;
  }

  /** Output-item IDs are unique across messages, calls and every other item. */
  registerId(id: unknown, kind: "call" | "other") {
    if (typeof id !== "string") return;
    const prior = this.seenIds.get(id);
    if (prior !== undefined) this.noteFault(prior === "call" && kind === "call" ? "duplicate_call" : "duplicate_item");
    else this.seenIds.set(id, kind);
  }

  /** `strictStatus`: terminal data, where any supplied status must be exactly "completed". */
  addCall(item: { id?: string; call_id?: string; name?: string; status?: unknown }, strictStatus = false) {
    const callId = typeof item.call_id === "string" ? item.call_id : "";
    const itemId = typeof item.id === "string" ? item.id : null;
    if (!callId || this.calls.some((c) => c.callId === callId)) this.noteFault("duplicate_call");
    this.registerId(itemId, "call");
    const call: CallState = {
      itemId,
      callId,
      name: typeof item.name === "string" ? item.name : "",
      args: "",
      argBytes: 0,
      oversize: false,
      completedArgs: null,
      notCompleted: strictStatus && item.status !== undefined && item.status !== "completed",
    };
    this.calls.push(call);
    if (itemId !== null) this.byItem.set(itemId, call);
    return call;
  }

  setCompleted(call: CallState, value: unknown) {
    if (typeof value !== "string") return this.noteFault("arguments_malformed");
    if (byteLength(value) > MAX_TOOL_ARGUMENT_BYTES) {
      call.oversize = true;
      call.completedArgs = null;
    } else {
      call.oversize = false;
      call.completedArgs = value;
    }
    call.args = "";
  }

  appendDelta(call: CallState, delta: unknown) {
    if (typeof delta !== "string") return this.noteFault("arguments_malformed");
    if (call.oversize) return;
    call.argBytes += byteLength(delta);
    if (call.argBytes > MAX_TOOL_ARGUMENT_BYTES) {
      call.oversize = true;
      call.args = "";
    } else call.args += delta;
  }

  addText(itemId: unknown, output: number, content: number, text: string) {
    const key = `${typeof itemId === "string" ? itemId : `@${output}`}:${content}`;
    const entry = this.texts.get(key) ?? { output, content, text: "" };
    entry.text += text;
    this.texts.set(key, entry);
  }

  orderedText() {
    return [...this.texts.values()].sort((a, b) => a.output - b.output || a.content - b.content)
      .map((e) => e.text).join("");
  }
}

/** Fold a Responses `output` array (JSON body or response.completed envelope) into a collector. */
function collectOutput(output: unknown, into: Collector) {
  if (!Array.isArray(output)) return;
  output.forEach((item, outputIndex) => {
    if (!item || typeof item !== "object") return into.noteFault("unsupported_item");
    const it = item as Record<string, unknown>;
    // Items without a type but with content are accepted as messages (legacy fixtures/shape).
    if (it.type === "message" || (it.type === undefined && Array.isArray(it.content))) {
      into.registerId(it.id, "other");
      if (it.status !== undefined && it.status !== "completed") into.turnIncomplete = true;
      const content = Array.isArray(it.content) ? it.content : [];
      content.forEach((part: Record<string, unknown>, contentIndex: number) => {
        if (part?.type === "output_text" && typeof part.text === "string") {
          into.addText(it.id, outputIndex, contentIndex, part.text);
        } else if (part?.type === "refusal" && typeof part.refusal === "string") into.refusal += part.refusal;
      });
    } else if (it.type === "function_call") {
      const call = into.addCall(it as { id?: string; call_id?: string; name?: string; status?: unknown }, true);
      into.setCompleted(call, it.arguments);
    } else if (it.type === "reasoning") {
      into.registerId(it.id, "other");
      if (it.status !== undefined && it.status !== "completed") into.turnIncomplete = true;
    } else {
      into.noteFault("unsupported_item");
    }
  });
}

/**
 * The completed envelope's output is authoritative. Streamed state is provisional
 * and may only agree with it: any disagreement about the calls invalidates the
 * proposal, and the streamed text/refusal never overrides the final output.
 */
function reconcile(streamed: Collector, final: Collector) {
  if (streamed.fault) final.noteFault(streamed.fault);
  if (streamed.turnIncomplete) final.turnIncomplete = true;
  if (streamed.calls.length === 0) return; // final-only calls are accepted from the envelope
  if (streamed.calls.length !== final.calls.length) return final.noteFault("envelope_mismatch");
  streamed.calls.forEach((s, i) => {
    const f = final.calls[i];
    const sArgs = s.completedArgs ?? s.args;
    const argsAgree = s.oversize === f.oversize && (f.oversize || sArgs === "" || sArgs === f.completedArgs);
    if (s.callId !== f.callId || s.itemId !== f.itemId || s.name !== f.name || !argsAgree) {
      final.noteFault("envelope_mismatch");
    }
    if (s.notCompleted) f.notCompleted = true;
  });
}

function readUsage(usage: unknown): ChatUsage | undefined {
  if (!usage || typeof usage !== "object") return undefined;
  const u = usage as Record<string, unknown> & {
    input_tokens_details?: { cached_tokens?: number; cache_write_tokens?: number };
  };
  const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : undefined);
  return {
    inputTokens: num(u.input_tokens),
    outputTokens: num(u.output_tokens),
    totalTokens: num(u.total_tokens),
    cachedInputTokens: num(u.input_tokens_details?.cached_tokens),
    cacheWriteTokens: num(u.input_tokens_details?.cache_write_tokens),
  };
}

function finalize(
  c: Collector,
  meta: { usage?: ChatUsage; responseId?: string },
  tools: boolean,
  failureCode: "AI_STREAM_FAILED" | "AI_TERMINAL_FAILED",
): ChatResult {
  // An item that itself says it is not completed can never be a completed assistant turn.
  if (c.turnIncomplete) return { status: "incomplete", text: "", proposal: { state: "none" }, failureCode };
  const text = c.orderedText();
  const base = { usage: meta.usage, responseId: meta.responseId };
  if (c.refusal.trim()) {
    // A refusal suppresses any ordinary proposal.
    return { status: "refused", text: "", refusal: c.refusal, proposal: { state: "none" }, ...base };
  }
  let proposal: ChatProposal = { state: "none" };
  if (!tools) {
    // Legacy text-only request: no tool was declared, so a call is not a proposal.
  } else if (c.fault) {
    proposal = { state: "invalid", reason: c.fault };
  } else if (c.calls.length > 1) {
    proposal = { state: "invalid", reason: "multiple_calls" };
  } else if (c.calls.length === 1) {
    const call = c.calls[0];
    if (call.name !== SUPPORT_ACTION_TOOL_NAME) proposal = { state: "invalid", reason: "unknown_tool" };
    else if (call.oversize) proposal = { state: "invalid", reason: "arguments_too_large" };
    else if (call.notCompleted) proposal = { state: "invalid", reason: "call_not_completed" };
    else if (call.completedArgs === null) proposal = { state: "invalid", reason: "arguments_incomplete" };
    else {
      let isObject = false;
      try {
        const parsed = JSON.parse(call.completedArgs);
        isObject = !!parsed && typeof parsed === "object" && !Array.isArray(parsed);
      } catch { /* malformed */ }
      proposal = isObject
        ? { state: "raw", callId: call.callId, itemId: call.itemId, name: SUPPORT_ACTION_TOOL_NAME, arguments: call.completedArgs }
        : { state: "invalid", reason: "arguments_malformed" };
    }
  }
  // Nothing usable to show or reconcile: no text and no raw proposal.
  if (!text.trim() && proposal.state !== "raw") throw new Error("AI_EMPTY_RESPONSE");
  return { status: "completed", text, proposal, ...base };
}

async function invoke(messages: ChatMessage[], options: Options, tools: boolean): Promise<ChatResult> {
  options.signal?.throwIfAborted();
  const extras = tools ? SUPPORT_REQUEST_EXTRAS : {};
  // The prompt the provider sees is the messages plus any tool declaration; both must fit.
  const inputBytes = byteLength(JSON.stringify(messages)) + (tools ? SUPPORT_ACTION_OVERHEAD_BYTES : 0);
  if (inputBytes > MAX_PROMPT_BYTES) {
    throw new Error("CHAT_CONTEXT_TOO_LARGE");
  }
  const maxOutputTokens = options.maxOutputTokens ?? 500;
  if (!Number.isInteger(maxOutputTokens) || maxOutputTokens < 1 || maxOutputTokens > 500) {
    throw new Error("INVALID_OUTPUT_LIMIT");
  }
  // Standard GPT-6 Luna: reserve the worst 30-minute cache-write input rate
  // ($0.125/M) and $0.50/M output; ordinary/cached input costs less.
  // At most one token per input byte, plus framing allowance; no paid tools/Fast tier.
  const maxCostMicrodollars = Math.ceil((inputBytes + 1024) * 0.125 + maxOutputTokens * 0.5);
  if (!await options.reserveBudget(maxCostMicrodollars)) throw new Error("AI_DAILY_BUDGET_REACHED");
  options.signal?.throwIfAborted();
  // The caller debits user quota only after validated input and approved spending.
  await options.beforeProvider?.();
  options.signal?.throwIfAborted();
  const signal = options.signal
    ? AbortSignal.any([options.signal, AbortSignal.timeout(45_000)])
    : AbortSignal.timeout(45_000);
  // No SDK retries or provider fallback: an uncertain request must not be replayed.
  const response = await (options.fetcher ?? fetch)("https://api.openai.com/v1/responses", {
    method: "POST",
    signal,
    headers: {
      Authorization: `Bearer ${options.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: CHAT_MODEL,
      service_tier: "default",
      prompt_cache_options: { ttl: "30m" },
      input: messages,
      reasoning: { effort: "none" },
      max_output_tokens: maxOutputTokens,
      store: false,
      stream: !!options.onDelta,
      ...extras,
    }),
  });
  if (!response.ok) throw new Error(`AI_HTTP_${response.status}`);
  const c = new Collector();
  if (!options.onDelta) {
    const data = await response.json();
    if (data.status === "failed" || data.status === "incomplete") {
      return { status: data.status === "failed" ? "failed" : "incomplete", text: "", proposal: { state: "none" }, failureCode: "AI_TERMINAL_FAILED" };
    }
    if (data.status !== "completed") throw new Error("AI_INCOMPLETE_RESPONSE");
    // A present but malformed output cannot confirm anything (a missing one is simply empty).
    if (Object.hasOwn(data, "output") && !Array.isArray(data.output)) {
      return { status: "failed", text: "", proposal: { state: "none" }, failureCode: "AI_TERMINAL_FAILED" };
    }
    collectOutput(data.output, c);
    return finalize(c, { usage: readUsage(data.usage), responseId: typeof data.id === "string" ? data.id : undefined }, tools, "AI_TERMINAL_FAILED");
  }
  if (!response.body) throw new Error("AI_EMPTY_STREAM");
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let pending = "";
  // The first terminal event freezes the result. Nothing read afterwards (late output,
  // replacement arguments, a transport that never closes) can change or delay it.
  let outcome: ChatResult | null = null;
  const failure = (status: "incomplete" | "failed"): ChatResult =>
    ({ status, text: "", proposal: { state: "none" }, failureCode: "AI_STREAM_FAILED" });
  const callFor = (itemId: unknown) => (typeof itemId === "string" ? c.byItem.get(itemId) : undefined);
  try {
    while (!outcome) {
      const { value, done } = await reader.read();
      pending += decoder.decode(value, { stream: !done });
      if (pending.length > 1_048_576) throw new Error("AI_STREAM_FAILED");
      const lines = pending.split("\n");
      pending = lines.pop() ?? "";
      for (const line of lines) {
        if (!line.startsWith("data:")) continue;
        const raw = line.slice(5).trim();
        if (!raw || raw === "[DONE]") continue;
        let event: Record<string, any>;
        try {
          event = JSON.parse(raw);
        } catch {
          throw new Error("AI_STREAM_FAILED");
        }
        switch (event.type) {
          case "response.output_text.delta":
            if (typeof event.delta === "string") {
              c.addText(event.item_id, Number(event.output_index) || 0, Number(event.content_index) || 0, event.delta);
              options.onDelta(event.delta);
            }
            break;
          case "response.refusal.delta":
            if (typeof event.delta === "string") c.refusal += event.delta;
            break;
          case "response.refusal.done":
            if (typeof event.refusal === "string") c.refusal = event.refusal;
            break;
          case "response.output_item.added": {
            const item = event.item ?? {};
            if (item.type === "function_call") c.addCall(item);
            else if (item.type === "message" || item.type === "reasoning") c.registerId(item.id, "other");
            else c.noteFault("unsupported_item");
            break;
          }
          case "response.function_call_arguments.delta": {
            const call = callFor(event.item_id);
            if (call) c.appendDelta(call, event.delta);
            else c.noteFault("unknown_item");
            break;
          }
          case "response.function_call_arguments.done": {
            const call = callFor(event.item_id);
            if (call) c.setCompleted(call, event.arguments);
            else c.noteFault("unknown_item");
            break;
          }
          case "response.output_item.done": {
            const item = event.item ?? {};
            if (item.type === "function_call") {
              const call = callFor(item.id) ?? c.calls.find((x) => x.callId === item.call_id);
              if (!call) c.noteFault("unknown_item");
              else if ((item.call_id && item.call_id !== call.callId) || (item.name && item.name !== call.name)) {
                c.noteFault("envelope_mismatch");
              } else {
                c.setCompleted(call, item.arguments);
                if (item.status !== undefined && item.status !== "completed") call.notCompleted = true;
              }
            } else if ((item.type === "message" || item.type === "reasoning") &&
                       item.status !== undefined && item.status !== "completed") {
              c.turnIncomplete = true;
            }
            break;
          }
          case "response.completed": {
            // A present but malformed envelope or output cannot confirm provisional content.
            const hasResponse = Object.hasOwn(event, "response");
            const r = hasResponse ? event.response : {};
            if (r === null || typeof r !== "object" || Array.isArray(r)) {
              outcome = failure("failed");
              break;
            }
            if (r.status !== undefined && r.status !== "completed") {
              outcome = failure("incomplete");
              break;
            }
            const hasOutput = Object.hasOwn(r, "output");
            if (hasOutput && !Array.isArray(r.output)) {
              outcome = failure("failed");
              break;
            }
            const meta = { usage: readUsage(r.usage), responseId: typeof r.id === "string" ? r.id : undefined };
            if (hasOutput) {
              // The completed output is authoritative; streamed state must only agree.
              const final = new Collector();
              collectOutput(r.output, final);
              reconcile(c, final);
              outcome = finalize(final, meta, tools, "AI_STREAM_FAILED");
            } else {
              // Only a genuinely omitted output (legacy envelope) falls back to streamed state.
              outcome = finalize(c, meta, tools, "AI_STREAM_FAILED");
            }
            break;
          }
          case "response.incomplete":
            outcome = failure("incomplete");
            break;
          case "response.failed":
          case "error":
            outcome = failure("failed");
            break;
        }
        if (outcome) break; // later lines in this chunk are never examined
      }
      if (outcome) break;
      if (done) break;
    }
    if (!outcome) throw new Error("AI_INCOMPLETE_STREAM");
    return outcome;
  } finally {
    // Release the transport at the terminal event. Delivery never waits for the
    // source's cancel() to settle (it may never), and a cancel failure is ignored.
    void reader.cancel().catch(() => {});
    try {
      reader.releaseLock();
    } catch { /* already released */ }
  }
}

/**
 * Main-chat entrypoint: ONE model invocation (same budget, quota, abort and
 * 500-token ceiling) that declares exactly one strict `propose_support_action`
 * function with parallel tool calls off. Returns typed text + at most one RAW
 * proposal; the caller must validate the proposal through the support-contract
 * policy before any card is actionable. Nothing is executed and there is no
 * follow-up request.
 */
export function generateChatResult(messages: ChatMessage[], options: Options): Promise<ChatResult> {
  return invoke(messages, options, true);
}

// Legacy string-returning wrapper: unchanged request body and error codes.
export async function generateChatText(messages: ChatMessage[], options: Options): Promise<string> {
  const result = await invoke(messages, options, false);
  if (result.status === "failed" || result.status === "incomplete") {
    throw new Error(result.failureCode ?? "AI_STREAM_FAILED");
  }
  if (result.status === "refused" || !result.text.trim()) throw new Error("AI_EMPTY_RESPONSE");
  return result.text;
}
