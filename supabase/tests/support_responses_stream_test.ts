import {
  type ChatMessage,
  generateChatResult,
  generateChatText,
  MAX_PROMPT_BYTES,
  MAX_TOOL_ARGUMENT_BYTES,
  SUPPORT_ACTION_OVERHEAD_BYTES,
  SUPPORT_ACTION_TOOL,
  SUPPORT_ACTION_TOOL_NAME,
  trimChatContext,
} from "../functions/_shared/openai-chat.ts";

// Synthetic fixtures only: no provider is contacted and no key is used.
function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
async function rejects(work: () => Promise<unknown>, message: string) {
  try { await work(); } catch (error) { assert(String(error).includes(message), String(error)); return; }
  throw new Error(`expected rejection containing ${message}`);
}
const messages: ChatMessage[] = [{ role: "user", content: "Synthetic fixture" }];
const ARGS = JSON.stringify({ template_key: "ground_present_v1", reason_code: "current_request", basis_ref: null, suggested_step: null });

function sse(events: unknown[], opts: { chunk?: number; omitCompleted?: boolean } = {}) {
  const bytes = new TextEncoder().encode(events.map((e) => `data: ${JSON.stringify(e)}\n\n`).join(""));
  return new Response(new ReadableStream({
    start(c) {
      const n = opts.chunk ?? bytes.length;
      for (let i = 0; i < bytes.length; i += n) c.enqueue(bytes.slice(i, i + n));
      c.close();
    },
  }));
}
const text = (delta: string, item = "msg_1", output = 0, content = 0) =>
  ({ type: "response.output_text.delta", item_id: item, output_index: output, content_index: content, delta });
const added = (item: Record<string, unknown>, output = 0) => ({ type: "response.output_item.added", output_index: output, item });
const fcItem = (over: Record<string, unknown> = {}) =>
  ({ type: "function_call", id: "fc_1", call_id: "call_1", name: SUPPORT_ACTION_TOOL_NAME, arguments: "", status: "in_progress", ...over });
const argDelta = (delta: string, item = "fc_1", output = 1) =>
  ({ type: "response.function_call_arguments.delta", item_id: item, output_index: output, delta });
const argDone = (args: string, item = "fc_1", output = 1) =>
  ({ type: "response.function_call_arguments.done", item_id: item, output_index: output, arguments: args });
const itemDone = (item: Record<string, unknown>, output = 1) => ({ type: "response.output_item.done", output_index: output, item });
const completed = (response: Record<string, unknown> = {}) => ({ type: "response.completed", response: { status: "completed", ...response } });

function run(events: unknown[], extra: { chunk?: number; onDelta?: (t: string) => void } = {}) {
  const deltas: string[] = [];
  let fetches = 0;
  let budget = 0;
  const promise = generateChatResult(messages, {
    apiKey: "synthetic-only",
    reserveBudget: async () => { budget++; return true; },
    onDelta: (t) => { deltas.push(t); extra.onDelta?.(t); },
    fetcher: (async () => { fetches++; return sse(events, { chunk: extra.chunk }); }) as typeof fetch,
  });
  return { promise, deltas, counts: () => ({ fetches, budget }) };
}

const toolCallEvents = (args = ARGS, over: Record<string, unknown> = {}) => [
  added(fcItem(over), 1),
  argDelta(args.slice(0, 20)),
  argDelta(args.slice(20)),
  argDone(args),
  itemDone(fcItem({ ...over, arguments: args, status: "completed" })),
];

Deno.test("request declares exactly one strict function, no parallel calls, same model caps", async () => {
  let body: Record<string, any> = {};
  await generateChatResult(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true,
    fetcher: (async (_u, init) => {
      body = JSON.parse(init!.body as string);
      return Response.json({ status: "completed", output: [{ type: "message", content: [{ type: "output_text", text: "Hi" }] }] });
    }) as typeof fetch,
  });
  assert(body.model === "gpt-6-luna" && body.max_output_tokens === 500 && body.store === false);
  assert(body.reasoning.effort === "none" && body.parallel_tool_calls === false && body.tool_choice === "auto");
  assert(body.tools.length === 1);
  const t = body.tools[0];
  assert(t.type === "function" && t.name === "propose_support_action" && t.strict === true);
  const p = t.parameters;
  assert(p.additionalProperties === false && p.type === "object");
  assert(JSON.stringify([...p.required].sort()) === JSON.stringify(Object.keys(p.properties).sort()), "all fields required");
  assert(JSON.stringify(p.properties.template_key.enum) === JSON.stringify(["ground_present_v1", "untangle_thought_v1", "choose_step_v1"]));
  assert(JSON.stringify(p.properties.reason_code.enum) === JSON.stringify(["current_request", "approved_preference", "selected_intent", "general_option"]));
  assert(JSON.stringify(p.properties.basis_ref.type) === '["string","null"]' && JSON.stringify(p.properties.suggested_step.type) === '["string","null"]');
  assert(JSON.stringify(t) === JSON.stringify(SUPPORT_ACTION_TOOL));
});

Deno.test("legacy wrapper keeps its request body: no tools", async () => {
  let body: Record<string, any> = {};
  await generateChatText(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true,
    fetcher: (async (_u, init) => {
      body = JSON.parse(init!.body as string);
      return Response.json({ status: "completed", output: [{ content: [{ type: "output_text", text: "Hi" }] }] });
    }) as typeof fetch,
  });
  assert(!("tools" in body) && !("tool_choice" in body) && !("parallel_tool_calls" in body));
});

Deno.test("stream: text only", async () => {
  const r = run([text("Hello "), text("there"), completed()], { chunk: 3 });
  const result = await r.promise;
  assert(result.status === "completed" && result.text === "Hello there" && result.proposal.state === "none");
  assert(r.deltas.join("") === "Hello there", "provisional deltas preserved");
  assert(r.counts().fetches === 1 && r.counts().budget === 1, "exactly one invocation");
});

Deno.test("stream: text plus tool call keeps raw argument string and ignores arg fragments for UI", async () => {
  const r = run([
    added({ type: "message", id: "msg_1", content: [] }, 0), text("Let's try something."),
    ...toolCallEvents(),
    completed({ id: "resp_1", usage: { input_tokens: 10, output_tokens: 20, total_tokens: 30, input_tokens_details: { cached_tokens: 4, cache_write_tokens: 6 } } }),
  ], { chunk: 5 });
  const result = await r.promise;
  assert(result.status === "completed" && result.text === "Let's try something.");
  assert(result.proposal.state === "raw" && result.proposal.arguments === ARGS && result.proposal.callId === "call_1" && result.proposal.itemId === "fc_1");
  assert(r.deltas.join("") === "Let's try something.", "argument fragments are never surfaced as deltas");
  assert(result.responseId === "resp_1" && result.usage?.outputTokens === 20 && result.usage?.cachedInputTokens === 4 && result.usage?.cacheWriteTokens === 6);
});

Deno.test("stream: tool-only result has empty text and one completed raw proposal", async () => {
  const result = await run([...toolCallEvents(), completed()]).promise;
  assert(result.status === "completed" && result.text === "" && result.proposal.state === "raw");
});

Deno.test("stream: refusal suppresses an ordinary proposal", async () => {
  const result = await run([
    { type: "response.refusal.delta", item_id: "msg_1", output_index: 0, content_index: 0, delta: "I can't " },
    { type: "response.refusal.done", item_id: "msg_1", output_index: 0, content_index: 0, refusal: "I can't help with that." },
    ...toolCallEvents(), completed(),
  ]).promise;
  assert(result.status === "refused" && result.refusal === "I can't help with that." && result.text === "" && result.proposal.state === "none");
});

Deno.test("stream: malformed, non-object and oversized UTF-8 arguments invalidate the proposal but keep text", async () => {
  for (const bad of ["{not json", "[1,2]", "null", '"string"']) {
    const result = await run([text("Kept."), ...toolCallEvents(bad), completed()]).promise;
    assert(result.text === "Kept." && result.proposal.state === "invalid" && result.proposal.reason === "arguments_malformed", bad);
  }
  // 4,097 two-byte characters: under 8,192 characters but over 8,192 UTF-8 bytes.
  const wide = JSON.stringify({ x: "é".repeat(4097) });
  assert(wide.length < MAX_TOOL_ARGUMENT_BYTES && new TextEncoder().encode(wide).length > MAX_TOOL_ARGUMENT_BYTES);
  const viaDone = await run([text("Kept."), added(fcItem(), 1), argDone(wide), completed()]).promise;
  assert(viaDone.text === "Kept." && viaDone.proposal.state === "invalid" && viaDone.proposal.reason === "arguments_too_large");
  // Accumulating deltas must trip the bound too, without an accepted done event.
  const viaDeltas = await run([
    text("Kept."), added(fcItem(), 1), ...Array.from({ length: 5 }, () => argDelta("é".repeat(1000))), completed(),
  ]).promise;
  assert(viaDeltas.proposal.state === "invalid" && viaDeltas.proposal.reason === "arguments_too_large");
  // Exactly at the bound is still a (structurally) raw proposal.
  const exact = JSON.stringify({ x: "a".repeat(MAX_TOOL_ARGUMENT_BYTES - 8) });
  assert(new TextEncoder().encode(exact).length === MAX_TOOL_ARGUMENT_BYTES);
  const ok = await run([text("Kept."), added(fcItem(), 1), argDone(exact), completed()]).promise;
  assert(ok.proposal.state === "raw");
});

Deno.test("stream: duplicate identity, multiple calls, unknown tool and unsupported items invalidate the proposal", async () => {
  const dupCallId = await run([text("T"), added(fcItem(), 1), added(fcItem({ id: "fc_2" }), 2), argDone(ARGS), completed()]).promise;
  assert(dupCallId.proposal.state === "invalid" && dupCallId.proposal.reason === "duplicate_call");
  const dupItemId = await run([text("T"), added(fcItem(), 1), added(fcItem({ call_id: "call_2" }), 2), completed()]).promise;
  assert(dupItemId.proposal.state === "invalid" && dupItemId.proposal.reason === "duplicate_call");
  const multiple = await run([
    text("T"), added(fcItem(), 1), argDone(ARGS, "fc_1", 1), added(fcItem({ id: "fc_2", call_id: "call_2" }), 2), argDone(ARGS, "fc_2", 2), completed(),
  ]).promise;
  assert(multiple.proposal.state === "invalid" && multiple.proposal.reason === "multiple_calls" && multiple.text === "T");
  const unknownTool = await run([text("T"), ...toolCallEvents(ARGS, { name: "delete_everything" }), completed()]).promise;
  assert(unknownTool.proposal.state === "invalid" && unknownTool.proposal.reason === "unknown_tool");
  const otherItem = await run([text("T"), added({ type: "web_search_call", id: "ws_1" }, 1), completed()]).promise;
  assert(otherItem.proposal.state === "invalid" && otherItem.proposal.reason === "unsupported_item");
  const orphan = await run([text("T"), argDelta("{}", "fc_unknown"), completed()]).promise;
  assert(orphan.proposal.state === "invalid" && orphan.proposal.reason === "unknown_item");
  const incompleteArgs = await run([text("T"), added(fcItem(), 1), argDelta(ARGS), completed()]).promise;
  assert(incompleteArgs.proposal.state === "invalid" && incompleteArgs.proposal.reason === "arguments_incomplete");
});

Deno.test("stream: an invalid proposal without any text is not a usable result", async () => {
  await rejects(() => run([...toolCallEvents("{bad"), completed()]).promise, "AI_EMPTY_RESPONSE");
  await rejects(() => run([completed()]).promise, "AI_EMPTY_RESPONSE");
});

Deno.test("stream: partial SSE and truncated tool calls never complete", async () => {
  await rejects(() => run([text("partial")]).promise, "AI_INCOMPLETE_STREAM");
  await rejects(() => run([text("partial"), ...toolCallEvents()]).promise, "AI_INCOMPLETE_STREAM");
  // A truncated line (no newline) is dropped, not parsed.
  const truncated = new Response('data: {"type":"response.output_text.delta","delta":"x"}\n\ndata: {"type":"response.compl');
  await rejects(() => generateChatResult(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true, onDelta: () => {}, fetcher: (async () => truncated) as typeof fetch,
  }), "AI_INCOMPLETE_STREAM");
  await rejects(() => generateChatResult(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true, onDelta: () => {},
    fetcher: (async () => new Response("data: {broken\n\n")) as typeof fetch,
  }), "AI_STREAM_FAILED");
});

Deno.test("stream: incomplete completed envelope, response.incomplete, failed and error-after-deltas are never completed", async () => {
  const envelope = await run([text("Hello"), ...toolCallEvents(), { type: "response.completed", response: { status: "incomplete" } }]).promise;
  assert(envelope.status === "incomplete" && envelope.text === "" && envelope.proposal.state === "none");
  const incomplete = await run([text("Hello"), ...toolCallEvents(), { type: "response.incomplete", response: { status: "incomplete" } }]).promise;
  assert(incomplete.status === "incomplete" && incomplete.text === "" && incomplete.proposal.state === "none");
  const failed = await run([text("Hello"), { type: "response.failed", response: { status: "failed" } }]).promise;
  assert(failed.status === "failed" && failed.text === "" && failed.proposal.state === "none");
  const errored = await run([text("Hello"), ...toolCallEvents(), { type: "error", code: "server_error", message: "x", param: null }, completed()]).promise;
  assert(errored.status === "failed" && errored.text === "" && errored.proposal.state === "none");
  // The legacy wrapper keeps its exact thrown codes for those states.
  await rejects(() => generateChatText(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true, onDelta: () => {},
    fetcher: (async () => sse([text("x"), { type: "error", message: "x" }])) as typeof fetch,
  }), "AI_STREAM_FAILED");
});

Deno.test("stream: completed envelope that disagrees with the stream invalidates the proposal", async () => {
  const mismatch = await run([
    text("T"), ...toolCallEvents(),
    completed({ output: [{ type: "message", content: [{ type: "output_text", text: "T" }] }, { type: "function_call", id: "fc_1", call_id: "call_1", name: SUPPORT_ACTION_TOOL_NAME, arguments: '{"template_key":"other"}' }] }),
  ]).promise;
  assert(mismatch.proposal.state === "invalid" && mismatch.proposal.reason === "envelope_mismatch" && mismatch.text === "T");
  const agree = await run([
    text("T"), ...toolCallEvents(),
    completed({ output: [{ type: "message", content: [{ type: "output_text", text: "T" }] }, { type: "function_call", id: "fc_1", call_id: "call_1", name: SUPPORT_ACTION_TOOL_NAME, arguments: ARGS }] }),
  ]).promise;
  assert(agree.proposal.state === "raw");
});

Deno.test("text is assembled in output order, not arrival order", async () => {
  const result = await run([text("B", "msg_2", 1, 0), text("C", "msg_1", 0, 1), text("A", "msg_1", 0, 0), completed()]).promise;
  assert(result.text === "ACB", result.text);
});

Deno.test("cancellation: pre-aborted and mid-stream aborts propagate and do not complete", async () => {
  const pre = new AbortController(); pre.abort();
  let fetches = 0;
  await rejects(() => generateChatResult(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true, signal: pre.signal,
    fetcher: (async () => { fetches++; return sse([completed()]); }) as typeof fetch,
  }), "AbortError");
  assert(fetches === 0);

  const abort = new AbortController();
  const deltas: string[] = [];
  await rejects(() => generateChatResult(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true, signal: abort.signal,
    onDelta: (t) => { deltas.push(t); abort.abort(); },
    fetcher: (async (_u, init) => new Response(new ReadableStream({
      start(c) {
        c.enqueue(new TextEncoder().encode(`data: ${JSON.stringify(text("first"))}\n\n`));
        init!.signal!.addEventListener("abort", () => c.error(init!.signal!.reason));
      },
    }))) as typeof fetch,
  }), "AbortError");
  assert(deltas.join("") === "first", "provisional text delivered before cancellation");
});

Deno.test("JSON mode: item order, refusal, tool-only, incomplete and usage", async () => {
  const jsonResult = (body: Record<string, unknown>) => generateChatResult(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true,
    fetcher: (async () => Response.json(body)) as typeof fetch,
  });
  const fc = { type: "function_call", id: "fc_1", call_id: "call_1", name: SUPPORT_ACTION_TOOL_NAME, arguments: ARGS, status: "completed" };
  const msg = (t: string) => ({ type: "message", content: [{ type: "output_text", text: t }] });
  const textThenTool = await jsonResult({ status: "completed", id: "resp_9", usage: { input_tokens: 1, output_tokens: 2, total_tokens: 3 }, output: [msg("A"), fc] });
  assert(textThenTool.text === "A" && textThenTool.proposal.state === "raw" && textThenTool.usage?.totalTokens === 3 && textThenTool.responseId === "resp_9");
  const toolThenText = await jsonResult({ status: "completed", output: [fc, msg("A"), msg("B")] });
  assert(toolThenText.text === "AB" && toolThenText.proposal.state === "raw");
  const toolOnly = await jsonResult({ status: "completed", output: [{ type: "reasoning", id: "rs_1" }, fc] });
  assert(toolOnly.text === "" && toolOnly.proposal.state === "raw");
  const refusal = await jsonResult({ status: "completed", output: [{ type: "message", content: [{ type: "refusal", refusal: "No." }] }, fc] });
  assert(refusal.status === "refused" && refusal.proposal.state === "none");
  const two = await jsonResult({ status: "completed", output: [msg("A"), fc, { ...fc, id: "fc_2", call_id: "call_2" }] });
  assert(two.proposal.state === "invalid" && two.proposal.reason === "multiple_calls" && two.text === "A");
  const incomplete = await jsonResult({ status: "incomplete", output: [msg("A"), fc] });
  assert(incomplete.status === "incomplete" && incomplete.text === "" && incomplete.proposal.state === "none");
  await rejects(() => jsonResult({ status: "in_progress", output: [msg("A")] }), "AI_INCOMPLETE_RESPONSE");
});

Deno.test("prompt plus tool overhead must fit before any budget or provider contact; trimming reserves it", async () => {
  const fits = [{ role: "system" as const, content: "S" }, { role: "user" as const, content: "x".repeat(MAX_PROMPT_BYTES - 200) }];
  const size = new TextEncoder().encode(JSON.stringify(fits)).length;
  assert(size <= MAX_PROMPT_BYTES && size + SUPPORT_ACTION_OVERHEAD_BYTES > MAX_PROMPT_BYTES, "fixture must straddle the bound");
  let side = 0;
  const guarded = {
    apiKey: "synthetic-only", reserveBudget: async () => { side++; return true; }, beforeProvider: async () => { side++; },
    fetcher: (() => { side++; throw new Error("must not run"); }) as typeof fetch,
  };
  await rejects(() => generateChatResult(fits, guarded), "CHAT_CONTEXT_TOO_LARGE");
  assert(side === 0, "no budget, quota or provider contact");
  // The legacy text-only request (no tool) still accepts the same messages.
  let legacy = 0;
  await generateChatText(fits, {
    apiKey: "synthetic-only", reserveBudget: async () => true,
    fetcher: (async () => { legacy++; return Response.json({ status: "completed", output: [{ content: [{ type: "output_text", text: "ok" }] }] }); }) as typeof fetch,
  });
  assert(legacy === 1);

  // Trimming with the reservation drops history only; mandatory system/current input is never truncated.
  const system: ChatMessage = { role: "system", content: "Keep boundaries 🌱" };
  const current: ChatMessage = { role: "user", content: "今".repeat(4000) };
  const history: ChatMessage[] = Array.from({ length: 12 }, (_, i) => ({ role: i % 2 ? "assistant" : "user", content: `${i}:` + "漢".repeat(3997) }));
  const trimmed = trimChatContext([system, ...history, current], { reservedBytes: SUPPORT_ACTION_OVERHEAD_BYTES });
  assert(trimmed[0] === system && trimmed.at(-1) === current);
  assert(new TextEncoder().encode(JSON.stringify(trimmed)).length + SUPPORT_ACTION_OVERHEAD_BYTES <= MAX_PROMPT_BYTES);
  // Required content that cannot fit even alone fails instead of being cut.
  await rejects(async () => trimChatContext([system, { role: "user", content: "x".repeat(MAX_PROMPT_BYTES - 100) }], { reservedBytes: SUPPORT_ACTION_OVERHEAD_BYTES }), "CHAT_CONTEXT_TOO_LARGE");
});

Deno.test("token cap, budget denial and quota ordering are unchanged for the typed entrypoint", async () => {
  const fetcher = (() => { throw new Error("provider must not be called"); }) as typeof fetch;
  await rejects(() => generateChatResult(messages, { apiKey: "synthetic-only", reserveBudget: async () => true, fetcher, maxOutputTokens: 501 }), "INVALID_OUTPUT_LIMIT");
  let quota = 0;
  await rejects(() => generateChatResult(messages, { apiKey: "synthetic-only", reserveBudget: async () => false, beforeProvider: async () => { quota++; }, fetcher }), "AI_DAILY_BUDGET_REACHED");
  assert(quota === 0);
  const calls: string[] = [];
  await generateChatResult(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => { calls.push("budget"); return true; }, beforeProvider: async () => { calls.push("quota"); },
    fetcher: (async () => { calls.push("provider"); return Response.json({ status: "completed", output: [{ type: "message", content: [{ type: "output_text", text: "ok" }] }] }); }) as typeof fetch,
  });
  assert(calls.join(",") === "budget,quota,provider");
  await rejects(() => generateChatResult(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true,
    fetcher: (async () => new Response("secret provider text", { status: 500 })) as typeof fetch,
  }), "AI_HTTP_500");
});

// ---------------------------------------------------------------------------
// Terminal freeze, final-envelope authority (review R01-R03)
// ---------------------------------------------------------------------------
const FINAL_MSG = (t: string, id?: string) => ({ type: "message", ...(id ? { id } : {}), content: [{ type: "output_text", text: t }] });
const FINAL_CALL = (over: Record<string, unknown> = {}) =>
  ({ type: "function_call", id: "fc_1", call_id: "call_1", name: SUPPORT_ACTION_TOOL_NAME, arguments: ARGS, status: "completed", ...over });

/** A transport that delivers its events and then NEVER closes; records release. */
function openTransport(chunks: unknown[][]) {
  let cancelled = false;
  let controller!: ReadableStreamDefaultController<Uint8Array>;
  const enc = (events: unknown[]) => new TextEncoder().encode(events.map((e) => `data: ${JSON.stringify(e)}\n\n`).join(""));
  const response = new Response(new ReadableStream<Uint8Array>({
    start(c) { controller = c; c.enqueue(enc(chunks[0])); },
    cancel() { cancelled = true; },
  }));
  return { response, push: (events: unknown[]) => { try { controller.enqueue(enc(events)); } catch { /* released */ } }, cancelled: () => cancelled };
}
async function withDeadline<T>(work: Promise<T>, label: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([work, new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error(`hung: ${label}`)), 2000); })]);
  } finally { clearTimeout(timer); }
}

Deno.test("R01: a never-ending transport after response.completed does not delay and is released", async () => {
  const t = openTransport([[text("Hello"), completed({ output: [FINAL_MSG("Hello")] })]]);
  const result = await withDeadline(generateChatResult(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true, onDelta: () => {}, fetcher: (async () => t.response) as typeof fetch,
  }), "waited for EOF");
  assert(result.status === "completed" && result.text === "Hello" && result.proposal.state === "none");
  assert(t.cancelled(), "the transport was not released at the terminal event");
  // Terminal failures release the transport immediately too.
  const f = openTransport([[text("x"), { type: "error", message: "x" }]]);
  const failed = await withDeadline(generateChatResult(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true, onDelta: () => {}, fetcher: (async () => f.response) as typeof fetch,
  }), "failure waited for EOF");
  assert(failed.status === "failed" && f.cancelled());
});

Deno.test("R01: output after response.completed cannot create or change the result", async () => {
  const late = [added(fcItem({ id: "fc_late", call_id: "call_late" }), 1), argDone(ARGS, "fc_late"), text(" LATE"), completed({ output: [FINAL_MSG("replaced")] })];
  // Same chunk as the terminal event, and as later chunks of a transport that stays open.
  const same = await run([text("T"), completed({ output: [FINAL_MSG("T")] }), ...late]).promise;
  assert(same.status === "completed" && same.text === "T" && same.proposal.state === "none", JSON.stringify(same));
  const t = openTransport([[text("T"), completed({ output: [FINAL_MSG("T")] })]]);
  const promise = generateChatResult(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true, onDelta: () => {}, fetcher: (async () => t.response) as typeof fetch,
  });
  const result = await withDeadline(promise, "post-terminal");
  t.push(late); // arrives after the result was delivered
  assert(result.text === "T" && result.proposal.state === "none");
  // Replacement arguments after a completed raw proposal do not replace it.
  const replaced = await run([
    text("T"), ...toolCallEvents(),
    completed({ output: [FINAL_MSG("T"), FINAL_CALL()] }),
    argDone('{"template_key":"choose_step_v1"}'),
  ]).promise;
  assert(replaced.proposal.state === "raw" && replaced.proposal.arguments === ARGS);
});

Deno.test("R02: final item identity, status and shared IDs are validated", async () => {
  const base = [text("T"), ...toolCallEvents()];
  const differentItem = await run([...base, completed({ output: [FINAL_MSG("T"), FINAL_CALL({ id: "fc_DIFFERENT" })] })]).promise;
  assert(differentItem.proposal.state === "invalid" && differentItem.proposal.reason === "envelope_mismatch" && differentItem.text === "T");
  const differentCall = await run([...base, completed({ output: [FINAL_MSG("T"), FINAL_CALL({ call_id: "call_other" })] })]).promise;
  assert(differentCall.proposal.state === "invalid" && differentCall.proposal.reason === "envelope_mismatch");
  const finalIncomplete = await run([...base, completed({ output: [FINAL_MSG("T"), FINAL_CALL({ status: "incomplete" })] })]).promise;
  assert(finalIncomplete.proposal.state === "invalid" && finalIncomplete.proposal.reason === "call_not_completed" && finalIncomplete.text === "T");
  const streamIncomplete = await run([
    text("T"), added(fcItem(), 1), argDone(ARGS), itemDone(fcItem({ arguments: ARGS, status: "incomplete" })), completed(),
  ]).promise;
  assert(streamIncomplete.proposal.state === "invalid" && streamIncomplete.proposal.reason === "call_not_completed");
  const finalMismatchedName = await run([...base, completed({ output: [FINAL_MSG("T"), FINAL_CALL({ name: "other_tool" })] })]).promise;
  assert(finalMismatchedName.proposal.state === "invalid");
  // A message and a function call may not share an item ID (final output and stream).
  const sharedFinal = await run([text("T"), completed({ output: [FINAL_MSG("T", "item_1"), FINAL_CALL({ id: "item_1" })] })]).promise;
  assert(sharedFinal.proposal.state === "invalid" && sharedFinal.proposal.reason === "duplicate_item" && sharedFinal.text === "T");
  const sharedStream = await run([
    added({ type: "message", id: "fc_1", content: [] }, 0), text("T", "fc_1"), ...toolCallEvents(), completed(),
  ]).promise;
  assert(sharedStream.proposal.state === "invalid" && sharedStream.proposal.reason === "duplicate_item");
  // Two messages with the same ID are also ambiguous output identity.
  const dupMessages = await run([text("T"), completed({ output: [FINAL_MSG("T", "m"), FINAL_MSG("U", "m"), FINAL_CALL()] })]).promise;
  assert(dupMessages.proposal.state === "invalid");
});

Deno.test("R02: oversized terminal arguments override earlier small streamed arguments", async () => {
  const huge = JSON.stringify({ x: "é".repeat(4097) });
  assert(new TextEncoder().encode(huge).length > MAX_TOOL_ARGUMENT_BYTES);
  const result = await run([
    text("Kept."), ...toolCallEvents(),
    completed({ output: [FINAL_MSG("Kept."), FINAL_CALL({ arguments: huge })] }),
  ]).promise;
  assert(result.text === "Kept." && result.proposal.state === "invalid", JSON.stringify(result.proposal));
  // Oversized in the terminal output only, with no streamed call events at all.
  const finalOnly = await run([text("Kept."), completed({ output: [FINAL_MSG("Kept."), FINAL_CALL({ arguments: huge })] })]).promise;
  assert(finalOnly.proposal.state === "invalid" && finalOnly.proposal.reason === "arguments_too_large" && finalOnly.text === "Kept.");
  // A final-only call with valid arguments is accepted from the authoritative envelope.
  const finalOnlyOk = await run([text("Kept."), completed({ output: [FINAL_MSG("Kept."), FINAL_CALL()] })]).promise;
  assert(finalOnlyOk.proposal.state === "raw" && finalOnlyOk.proposal.arguments === ARGS);
  // Streamed call absent from the terminal output is a disagreement, not a proposal.
  const droppedByFinal = await run([text("Kept."), ...toolCallEvents(), completed({ output: [FINAL_MSG("Kept.")] })]).promise;
  assert(droppedByFinal.proposal.state === "invalid" && droppedByFinal.proposal.reason === "envelope_mismatch" && droppedByFinal.text === "Kept.");
});

Deno.test("R03: the completed output supplies the final text; provisional deltas never override it", async () => {
  const deltas: string[] = [];
  const replaced = await run([text("STREAMED"), completed({ output: [FINAL_MSG("FINAL")] })], { onDelta: (t) => deltas.push(t) }).promise;
  assert(replaced.text === "FINAL" && replaced.proposal.state === "none");
  assert(deltas.join("") === "STREAMED", "the provisional stream is still delivered as provisional");
  // Final-only text (no deltas at all).
  const finalOnly = await run([completed({ output: [FINAL_MSG("Only in the envelope")] })]).promise;
  assert(finalOnly.text === "Only in the envelope");
  // Duplicated or missing deltas cannot alter the confirmed message.
  const duplicated = await run([text("Hel"), text("Hel"), text("lo"), completed({ output: [FINAL_MSG("Hello")] })]).promise;
  assert(duplicated.text === "Hello");
  // The envelope's output order governs multi-part text.
  const ordered = await run([text("B", "m2", 1, 0), text("A", "m1", 0, 0), completed({ output: [FINAL_MSG("A", "m1"), FINAL_MSG("B", "m2")] })]).promise;
  assert(ordered.text === "AB");
  // A final output without any message does not promote streamed text; a valid call survives as tool-only.
  const toolOnlyFinal = await run([text("STREAMED"), ...toolCallEvents(), completed({ output: [FINAL_CALL()] })]).promise;
  assert(toolOnlyFinal.text === "" && toolOnlyFinal.proposal.state === "raw");
  await rejects(() => run([text("STREAMED"), completed({ output: [] })]).promise, "AI_EMPTY_RESPONSE");
  // Legitimate omission of output: the streamed state is the only source (legacy envelope).
  const omitted = await run([text("Streamed only"), completed()]).promise;
  assert(omitted.text === "Streamed only");
  // Valid confirmed text is preserved when only the proposal is invalid.
  const invalidProposal = await run([text("STREAMED"), ...toolCallEvents("{bad"), completed({ output: [FINAL_MSG("FINAL"), FINAL_CALL({ arguments: "{bad" })] })]).promise;
  assert(invalidProposal.text === "FINAL" && invalidProposal.proposal.state === "invalid");
  // Refusal in the final output wins over streamed text and suppresses the proposal.
  const refusal = await run([text("STREAMED"), ...toolCallEvents(), completed({ output: [{ type: "message", content: [{ type: "refusal", refusal: "No." }] }, FINAL_CALL()] })]).promise;
  assert(refusal.status === "refused" && refusal.proposal.state === "none");
});

Deno.test("still one provider call and the legacy wrapper is unchanged after the terminal freeze", async () => {
  let calls = 0;
  const t = openTransport([[text("Hi"), completed({ output: [FINAL_MSG("Hi")] })]]);
  const legacy = await withDeadline(generateChatText(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true, onDelta: () => {},
    fetcher: (async (_u, init) => { calls++; assert(!("tools" in JSON.parse(init!.body as string))); return t.response; }) as typeof fetch,
  }), "legacy waited for EOF");
  assert(legacy === "Hi" && calls === 1 && t.cancelled());
});

// ---------------------------------------------------------------------------
// Residuals R01-R1 / R02-R1 / R03-R1
// ---------------------------------------------------------------------------
const jsonRun = (body: Record<string, unknown>) => generateChatResult(messages, {
  apiKey: "synthetic-only", reserveBudget: async () => true,
  fetcher: (async () => Response.json(body)) as typeof fetch,
});
const BAD_STATUSES: unknown[] = ["in_progress", "incomplete", "failed", "cancelled", "COMPLETED", "", null, 1, true, {}, []];

/** A transport whose source cancel() returns a promise that never settles. */
function stuckCancelTransport(events: unknown[], rawTail = "") {
  let cancelCalled = false;
  const bytes = new TextEncoder().encode(events.map((e) => `data: ${JSON.stringify(e)}\n\n`).join("") + rawTail);
  const response = new Response(new ReadableStream<Uint8Array>({
    start(c) { c.enqueue(bytes); },
    cancel() { cancelCalled = true; return new Promise<void>(() => {}); },
  }));
  return { response, cancelCalled: () => cancelCalled };
}
const viaStuck = (t: { response: Response }) => generateChatResult(messages, {
  apiKey: "synthetic-only", reserveBudget: async () => true, onDelta: () => {}, fetcher: (async () => t.response) as typeof fetch,
});

Deno.test("R01-R1: terminal delivery never waits for a source cancel() that never settles", async () => {
  const ok = stuckCancelTransport([text("Hello"), completed({ output: [FINAL_MSG("Hello")] })]);
  const success = await withDeadline(viaStuck(ok), "success waited for cancel");
  assert(success.status === "completed" && success.text === "Hello" && ok.cancelCalled(), "cleanup was still initiated");
  const err = stuckCancelTransport([text("x"), { type: "error", message: "x" }]);
  const failed = await withDeadline(viaStuck(err), "failure waited for cancel");
  assert(failed.status === "failed" && err.cancelCalled());
  const inc = stuckCancelTransport([text("x"), { type: "response.incomplete", response: { status: "incomplete" } }]);
  const incomplete = await withDeadline(viaStuck(inc), "incomplete waited for cancel");
  assert(incomplete.status === "incomplete" && inc.cancelCalled());
  // Rejection paths must not be held hostage either.
  const broken = stuckCancelTransport([text("x")], "data: {broken\n\n");
  await withDeadline(rejects(() => viaStuck(broken), "AI_STREAM_FAILED"), "throw waited for cancel");
  // A source whose cancel() rejects is ignored.
  const rejecting = new Response(new ReadableStream<Uint8Array>({
    start(c) { c.enqueue(new TextEncoder().encode(`data: ${JSON.stringify(text("Hi"))}\n\ndata: ${JSON.stringify(completed({ output: [FINAL_MSG("Hi")] }))}\n\n`)); },
    cancel() { return Promise.reject(new Error("cancel failed")); },
  }));
  assert((await withDeadline(viaStuck({ response: rejecting }), "rejecting cancel")).text === "Hi");
  // No later data can mutate the frozen result (the chunk's trailing events are ignored).
  const frozen = stuckCancelTransport([text("T"), completed({ output: [FINAL_MSG("T")] }), added(fcItem(), 1), argDone(ARGS), text(" late")]);
  const result = await withDeadline(viaStuck(frozen), "frozen");
  assert(result.text === "T" && result.proposal.state === "none");
});

Deno.test("R02-R1: any supplied non-completed item status is never confirmed (SSE and JSON)", async () => {
  for (const status of BAD_STATUSES) {
    const label = JSON.stringify(status);
    // Function call: proposal invalid, confirmed text preserved.
    const sseCall = await run([text("T"), ...toolCallEvents(), completed({ output: [FINAL_MSG("T"), FINAL_CALL({ status })] })]).promise;
    assert(sseCall.status === "completed" && sseCall.text === "T" && sseCall.proposal.state === "invalid" &&
      sseCall.proposal.reason === "call_not_completed", `sse final call ${label}: ${JSON.stringify(sseCall)}`);
    const jsonCall = await jsonRun({ status: "completed", output: [FINAL_MSG("T"), FINAL_CALL({ status })] });
    assert(jsonCall.text === "T" && jsonCall.proposal.state === "invalid" && jsonCall.proposal.reason === "call_not_completed", `json call ${label}`);
    // Streamed item.done carrying the bad status (no final output to correct it).
    const doneCall = await run([text("T"), added(fcItem(), 1), argDone(ARGS), itemDone(fcItem({ arguments: ARGS, status })), completed()]).promise;
    assert(doneCall.proposal.state === "invalid" && doneCall.proposal.reason === "call_not_completed", `sse done call ${label}`);
    // Message: the turn is incomplete, not a completed assistant message.
    const msg = { type: "message", id: "m1", status, content: [{ type: "output_text", text: "T" }] };
    const sseMsg = await run([text("T", "m1"), completed({ output: [msg, FINAL_CALL()] })]).promise;
    assert(sseMsg.status === "incomplete" && sseMsg.text === "" && sseMsg.proposal.state === "none" && sseMsg.failureCode === "AI_STREAM_FAILED", `sse message ${label}`);
    const jsonMsg = await jsonRun({ status: "completed", output: [msg, FINAL_CALL()] });
    assert(jsonMsg.status === "incomplete" && jsonMsg.text === "" && jsonMsg.proposal.state === "none" && jsonMsg.failureCode === "AI_TERMINAL_FAILED", `json message ${label}`);
    const doneMsg = await run([text("T", "m1"), itemDone(msg, 0), completed()]).promise;
    assert(doneMsg.status === "incomplete" && doneMsg.text === "", `sse message done ${label}`);
    // Reasoning items with a bad status also prevent a completed turn.
    const reasoning = await jsonRun({ status: "completed", output: [{ type: "reasoning", id: "rs", status }, FINAL_MSG("T")] });
    assert(reasoning.status === "incomplete", `reasoning ${label}`);
    // Top-level completed envelope contradicting completion.
    const top = await run([text("T"), { type: "response.completed", response: { status, output: [FINAL_MSG("T")] } }]).promise;
    assert(top.status === "incomplete" && top.text === "" && top.proposal.state === "none", `sse top ${label}`);
  }
  // JSON top-level contradiction: typed for failed/incomplete, never completed otherwise.
  assert((await jsonRun({ status: "incomplete", output: [FINAL_MSG("T")] })).status === "incomplete");
  assert((await jsonRun({ status: "failed", output: [FINAL_MSG("T")] })).status === "failed");
  for (const status of ["in_progress", "cancelled", null, 1, undefined]) {
    await rejects(() => jsonRun({ status, output: [FINAL_MSG("T")] }), "AI_INCOMPLETE_RESPONSE");
  }
  // Omitted optional statuses stay compatible when completion is otherwise proven.
  const omitted = await run([text("T"), ...toolCallEvents(), completed({ output: [FINAL_MSG("T"), { type: "function_call", id: "fc_1", call_id: "call_1", name: SUPPORT_ACTION_TOOL_NAME, arguments: ARGS }] })]).promise;
  assert(omitted.status === "completed" && omitted.proposal.state === "raw");
  const explicitOk = await jsonRun({ status: "completed", output: [{ ...FINAL_MSG("T"), status: "completed" }, FINAL_CALL()] });
  assert(explicitOk.text === "T" && explicitOk.proposal.state === "raw");
});

Deno.test("R03-R1: a present but malformed output never falls back to provisional content (SSE and JSON)", async () => {
  for (const output of [null, {}, "x", 5, true, false]) {
    const label = JSON.stringify(output);
    const sse = await run([text("PROVISIONAL"), ...toolCallEvents(), { type: "response.completed", response: { status: "completed", output } }]).promise;
    assert(sse.status === "failed" && sse.text === "" && sse.proposal.state === "none" && sse.failureCode === "AI_STREAM_FAILED", `sse ${label}: ${JSON.stringify(sse)}`);
    const json = await jsonRun({ status: "completed", output });
    assert(json.status === "failed" && json.text === "" && json.proposal.state === "none" && json.failureCode === "AI_TERMINAL_FAILED", `json ${label}`);
  }
  // A malformed response object itself cannot confirm anything either.
  for (const response of [null, "x", 5, [], true]) {
    const sse = await run([text("PROVISIONAL"), { type: "response.completed", response }]).promise;
    assert(sse.status === "failed" && sse.text === "", `response ${JSON.stringify(response)}`);
  }
  // Legacy wrapper maps these to its existing error code.
  await rejects(() => generateChatText(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true, onDelta: () => {},
    fetcher: (async () => sse([text("x"), { type: "response.completed", response: { status: "completed", output: null } }])) as typeof fetch,
  }), "AI_STREAM_FAILED");
  // A valid empty array is a present, well-formed (empty) output: nothing to confirm.
  await rejects(() => run([text("PROVISIONAL"), completed({ output: [] })]).promise, "AI_EMPTY_RESPONSE");
  await rejects(() => jsonRun({ status: "completed", output: [] }), "AI_EMPTY_RESPONSE");
  // A genuinely omitted output keeps the documented legacy compatibility.
  const omittedSse = await run([text("Streamed"), { type: "response.completed", response: { status: "completed" } }]).promise;
  assert(omittedSse.status === "completed" && omittedSse.text === "Streamed");
  const bareCompleted = await run([text("Streamed"), { type: "response.completed" }]).promise;
  assert(bareCompleted.text === "Streamed");
  await rejects(() => jsonRun({ status: "completed" }), "AI_EMPTY_RESPONSE");
});
