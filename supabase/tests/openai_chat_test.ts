import { CHAT_MODEL, type ChatMessage, generateChatText, MAX_PROMPT_BYTES, trimChatContext } from "../functions/_shared/openai-chat.ts";

function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
async function rejects(work: () => Promise<unknown>, message: string) {
  try { await work(); } catch (error) { assert(String(error).includes(message), String(error)); return; }
  throw new Error("expected rejection");
}
const messages = [{ role: "user" as const, content: "Synthetic fixture" }];

Deno.test("exact model, endpoint, output bound and no provider storage", async () => {
  let count = 0;
  const result = await generateChatText(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true,
    fetcher: (async (url, init) => {
      count++;
      assert(url === "https://api.openai.com/v1/responses");
      const body = JSON.parse(init!.body as string);
      assert(body.model === CHAT_MODEL && CHAT_MODEL === "gpt-6-luna");
      assert(body.store === false && body.max_output_tokens === 500 && body.reasoning.effort === "none");
      return Response.json({ status: "completed", output: [{ content: [{ type: "output_text", text: "Fixture response" }] }] });
    }) as typeof fetch,
  });
  assert(result === "Fixture response" && count === 1);
});

Deno.test("split UTF-8 SSE deltas assemble only after explicit completion", async () => {
  const encoded = new TextEncoder().encode('data: {"type":"response.output_text.delta","delta":"Olá 🌱"}\n\ndata: {"type":"response.completed"}\n\n');
  const chunks: string[] = [];
  const result = await generateChatText(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true, onDelta: (text) => chunks.push(text),
    fetcher: (async () => new Response(new ReadableStream({ start(c) {
      for (let i = 0; i < encoded.length; i += 2) c.enqueue(encoded.slice(i, i + 2));
      c.close();
    } }))) as typeof fetch,
  });
  assert(result === "Olá 🌱" && chunks.join("") === result);
});

Deno.test("interrupted stream is never reported as completed", async () => {
  await rejects(() => generateChatText(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true, onDelta: () => {},
    fetcher: (async () => new Response('data: {"type":"response.output_text.delta","delta":"partial"}\n\n')) as typeof fetch,
  }), "AI_INCOMPLETE_STREAM");
});

Deno.test("provider errors do not retry or leak response content", async () => {
  let calls = 0;
  await rejects(() => generateChatText(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true, fetcher: (async () => { calls++; return new Response("private provider detail", { status: 429 }); }) as typeof fetch,
  }), "AI_HTTP_429");
  assert(calls === 1);
});

Deno.test("oversized input and output limits fail before any provider call", async () => {
  const fetcher = (() => { throw new Error("provider must not be called"); }) as typeof fetch;
  await rejects(() => generateChatText([{ role: "user", content: "x".repeat(MAX_PROMPT_BYTES) }], { apiKey: "synthetic-only", reserveBudget: async () => true, fetcher }), "CHAT_CONTEXT_TOO_LARGE");
  await rejects(() => generateChatText(messages, { apiKey: "synthetic-only", reserveBudget: async () => true, fetcher, maxOutputTokens: 501 }), "INVALID_OUTPUT_LIMIT");
});

Deno.test("cancellation reaches provider without replay", async () => {
  const abort = new AbortController(); abort.abort();
  await rejects(() => generateChatText(messages, {
    apiKey: "synthetic-only", reserveBudget: async () => true, signal: abort.signal,
    fetcher: ((_, init) => { init!.signal!.throwIfAborted(); return Promise.reject(new Error("unexpected")); }) as typeof fetch,
  }), "AbortError");
});

Deno.test("a denied daily budget never contacts the provider", async () => {
  let providerCalls = 0;
  let quotaCalls = 0;
  let reserved = 0;
  await rejects(() => generateChatText(messages, {
    apiKey: "synthetic-only",
    reserveBudget: async (microdollars) => { reserved = microdollars; return false; },
    beforeProvider: async () => { quotaCalls++; },
    fetcher: (() => { providerCalls++; throw new Error("must not run"); }) as typeof fetch,
  }), "AI_DAILY_BUDGET_REACHED");
  assert(providerCalls === 0 && quotaCalls === 0 && reserved > 250);
});

Deno.test("context validation precedes budget and quota; quota precedes a single provider attempt", async () => {
  const calls: string[] = [];
  const options = {
    apiKey: "synthetic-only",
    reserveBudget: async () => { calls.push("budget"); return true; },
    beforeProvider: async () => { calls.push("quota"); },
    fetcher: (async () => { calls.push("provider"); throw new Error("uncertain outcome"); }) as typeof fetch,
  };
  await rejects(() => generateChatText([{ role: "user", content: "漢".repeat(MAX_PROMPT_BYTES / 3) }], options), "CHAT_CONTEXT_TOO_LARGE");
  await rejects(() => generateChatText(messages, { ...options, maxOutputTokens: 501 }), "INVALID_OUTPUT_LIMIT");
  assert(calls.length === 0, "Invalid input consumed spending or quota");
  await rejects(() => generateChatText(messages, options), "uncertain outcome");
  assert(calls.join(",") === "budget,quota,provider", "Wrong ordering or uncertain provider request replayed");
});

Deno.test("a rejected quota stops the provider after one conservative budget reservation", async () => {
  let reservations = 0;
  let providerCalls = 0;
  await rejects(() => generateChatText(messages, {
    apiKey: "synthetic-only",
    reserveBudget: async () => { reservations++; return true; },
    beforeProvider: async () => { throw new Error("quota denied"); },
    fetcher: (() => { providerCalls++; throw new Error("must not run"); }) as typeof fetch,
  }), "quota denied");
  assert(reservations === 1 && providerCalls === 0);
});

Deno.test("cancellation during budget reservation does not consume quota", async () => {
  const abort = new AbortController();
  let quotaCalls = 0;
  await rejects(() => generateChatText(messages, {
    apiKey: "synthetic-only", signal: abort.signal,
    reserveBudget: async () => { abort.abort(); return true; },
    beforeProvider: async () => { quotaCalls++; },
    fetcher: (() => { throw new Error("provider must not be called"); }) as typeof fetch,
  }), "AbortError");
  assert(quotaCalls === 0);
});

Deno.test("UTF-8 history drops only oldest context and preserves system and current input", async () => {
  const system: ChatMessage = { role: "system", content: "Keep the complete system prompt 🌱" };
  const current: ChatMessage = { role: "user", content: "今".repeat(4000) };
  const history: ChatMessage[] = Array.from({ length: 20 }, (_, i) => ({ role: i % 2 ? "assistant" : "user", content: `${i}:` + "漢".repeat(3997) }));
  const original = [system, ...history, current];
  const bounded = trimChatContext(original);
  const size = (value: ChatMessage[]) => new TextEncoder().encode(JSON.stringify(value)).length;
  assert(size(original) > MAX_PROMPT_BYTES && size(bounded) <= MAX_PROMPT_BYTES);
  assert(original.length === 22 && bounded[0] === system && bounded.at(-1) === current);
  const retained = bounded.slice(1, -1);
  assert(retained.length > 0 && retained.length < history.length);
  assert(retained.every((message, i) => message === history[history.length - retained.length + i]));
  assert(size([system, history[history.length - retained.length - 1], ...retained, current]) > MAX_PROMPT_BYTES, "Discarded more history than necessary");
  await generateChatText(bounded, {
    apiKey: "synthetic-only", reserveBudget: async () => true,
    fetcher: (async (_, init) => {
      const input = JSON.parse(init!.body as string).input;
      assert(size(input) <= MAX_PROMPT_BYTES && input.at(-1).content === current.content);
      return Response.json({ status: "completed", output: [{ content: [{ type: "output_text", text: "Synthetic multilingual response" }] }] });
    }) as typeof fetch,
  });
});

Deno.test("context trimming counts JSON escaping and preserves mandatory UTF-8 content", async () => {
  const system: ChatMessage = { role: "system", content: "System" };
  const current: ChatMessage = { role: "user", content: "🌱\"\n".repeat(1000) };
  const oldest: ChatMessage = { role: "assistant", content: "\"".repeat(64_000) };
  const trimmed = trimChatContext([system, oldest, current]);
  assert(trimmed.length === 2 && trimmed[0] === system && trimmed[1] === current);
  const small = [system, { role: "assistant" as const, content: "Previous" }, current];
  assert(trimChatContext(small).length === small.length, "Small context was shortened");
  await rejects(async () => trimChatContext([system, { role: "user", content: "漢".repeat(MAX_PROMPT_BYTES) }]), "CHAT_CONTEXT_TOO_LARGE");
});
