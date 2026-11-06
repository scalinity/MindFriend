// The AI_PROVIDER switch: routing, budget reservation at the routed model's price,
// the response shape callers parse, output caps, the safety note and refusals.
import { budgetedXAIText } from "../functions/_shared/budgeted-xai-text.ts";
import { callStandardText, SAFETY_NOTE, textRoute } from "../functions/_shared/ai-provider.ts";
import { CRISIS_RESPONSE } from "../functions/_shared/crisis.ts";

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

const USER = "00000000-0000-4000-8000-000000000001";

function harness() {
  const reserved: number[] = [];
  const bodies: Record<string, unknown>[] = [];
  const admin = {
    rpc(_name: string, args: Record<string, unknown>) {
      reserved.push(Number(args.p_reserve_microdollars));
      const result = {
        data: {
          allowed: true, reason: "reserved", request_id: args.p_request_id, user_id: args.p_user_id,
          feature: args.p_feature, reserve_microdollars: args.p_reserve_microdollars, month_start: "2026-11-01",
          reserved_microdollars: args.p_reserve_microdollars, limit_microdollars: 10_000_000,
          remaining_microdollars: 10_000_000 - Number(args.p_reserve_microdollars),
        },
        error: null,
      };
      const promise = Promise.resolve(result);
      return Object.assign(promise, { abortSignal: () => promise });
    },
  };
  let reply: Record<string, unknown> = {
    status: "completed",
    output: [{ content: [{ type: "output_text", text: "{\"ok\":true}" }] }],
    usage: { input_tokens: 40, output_tokens: 6 },
  };
  const fetcher = ((input: RequestInfo | URL, init?: RequestInit) => {
    assert(String(input) === "https://api.openai.com/v1/responses", `Unexpected URL ${input}`);
    bodies.push(JSON.parse(String(init?.body)));
    return Promise.resolve(Response.json(reply));
  }) as typeof fetch;
  return { admin, reserved, bodies, fetcher, setReply: (r: Record<string, unknown>) => (reply = r) };
}

async function withEnv(values: Record<string, string | undefined>, fn: () => Promise<void>) {
  const previous = Object.fromEntries(Object.keys(values).map((k) => [k, Deno.env.get(k)]));
  for (const [k, v] of Object.entries(values)) v === undefined ? Deno.env.delete(k) : Deno.env.set(k, v);
  try {
    await fn();
  } finally {
    for (const [k, v] of Object.entries(previous)) v === undefined ? Deno.env.delete(k) : Deno.env.set(k, v);
  }
}

Deno.test("unset or unknown AI_PROVIDER keeps xAI", async () => {
  for (const value of [undefined, "", "openai", "xai"]) {
    await withEnv({ AI_PROVIDER: value }, () => {
      assert(textRoute("journal.analysis").vendor === "xai", `AI_PROVIDER=${value} left xAI`);
      return Promise.resolve();
    });
  }
});

Deno.test("standard reserves at gpt-6-luna prices and returns the chat-completions shape", async () => {
  await withEnv({ AI_PROVIDER: "standard", VOICE_AND_NONIMAGE_OPENAI_API_KEY: "synthetic" }, async () => {
    const h = harness();
    const messages = [{ role: "system" as const, content: "Reply in JSON." }, { role: "user" as const, content: "hi" }];
    const response = await budgetedXAIText({
      admin: h.admin, userId: USER, feature: "weekly.insight", apiKey: "unused-xai-key",
      messages, maxTokens: 400, temperature: 0.7, fetcher: h.fetcher,
    });
    const bytes = new TextEncoder().encode(JSON.stringify(messages)).length;
    assert(h.reserved[0] === Math.ceil((bytes + SAFETY_NOTE.length + 1024) * 0.1 + 400 * 0.5), "Wrong reservation");
    const body = h.bodies[0];
    assert(body.model === "gpt-6-luna" && body.max_output_tokens === 400, "Wrong model or cap");
    assert(!("temperature" in body), "Temperature sent");
    const data = await response.json();
    assert(data.choices[0].message.content === "{\"ok\":true}", "Callers' shape not kept");
    assert(data.usage.prompt_tokens === 40 && data.usage.completion_tokens === 6, "Usage not kept");
  });
});

Deno.test("decision analysis gets its larger cap; the safety note goes only where listed", async () => {
  await withEnv({ AI_PROVIDER: "standard", VOICE_AND_NONIMAGE_OPENAI_API_KEY: "synthetic" }, async () => {
    const h = harness();
    const base = { admin: h.admin, userId: USER, apiKey: "x", maxTokens: 300, fetcher: h.fetcher };
    const messages = [{ role: "system" as const, content: "SYSTEM" }, { role: "user" as const, content: "u" }];
    await budgetedXAIText({ ...base, feature: "decision.analysis", messages });
    await budgetedXAIText({ ...base, feature: "conversation.title", messages });
    assert(h.bodies[0].max_output_tokens === 800, "Decision cap not raised");
    const system = (i: number) => (h.bodies[i].input as Array<{ content: string }>)[0].content;
    assert(system(0) === `SYSTEM\n\n${SAFETY_NOTE}`, "Safety note missing for decision analysis");
    assert(system(1) === "SYSTEM", "Safety note added to a title");
    assert(h.bodies[1].max_output_tokens === 300, "Caller cap not kept");
  });
});

Deno.test("a refusal becomes the crisis response in rehearsal and empty content in analysis", async () => {
  await withEnv({ AI_PROVIDER: "standard", VOICE_AND_NONIMAGE_OPENAI_API_KEY: "synthetic" }, async () => {
    const h = harness();
    h.setReply({ status: "completed", output: [{ content: [{ type: "refusal", refusal: "no" }] }], usage: {} });
    const base = { admin: h.admin, userId: USER, apiKey: "x", maxTokens: 300, fetcher: h.fetcher };
    const messages = [{ role: "user" as const, content: "u" }];
    const reply = await (await budgetedXAIText({ ...base, feature: "rehearsal.reply", messages })).json();
    const analysis = await (await budgetedXAIText({ ...base, feature: "journal.analysis", messages })).json();
    assert(reply.choices[0].message.content === CRISIS_RESPONSE, "Rehearsal refusal was not the crisis response");
    assert(reply.choices[0].finish_reason === "refusal", "Refusal not marked");
    assert(analysis.choices[0].message.content === "", "Analysis refusal returned content");
  });
});

Deno.test("missing OpenAI key fails before any budget is reserved", async () => {
  await withEnv({ AI_PROVIDER: "standard", VOICE_AND_NONIMAGE_OPENAI_API_KEY: undefined }, async () => {
    const h = harness();
    let message = "";
    try {
      await budgetedXAIText({
        admin: h.admin, userId: USER, feature: "journal.analysis", apiKey: "x", maxTokens: 10,
        messages: [{ role: "user", content: "u" }], fetcher: h.fetcher,
      });
    } catch (error) {
      message = (error as Error).message;
    }
    assert(message === "AI_PROVIDER_CONFIG_ERROR", "Missing key not reported");
    assert(h.reserved.length === 0 && h.bodies.length === 0, "Budget or provider touched");
  });
});

const LUNA_ROUTE = { vendor: "openai" as const, model: "gpt-6-luna", inputUsdPerM: 0.1, outputUsdPerM: 0.5 };

Deno.test("an OpenAI body over 1 MiB is rejected", async () => {
  await withEnv({ VOICE_AND_NONIMAGE_OPENAI_API_KEY: "synthetic" }, async () => {
    const big = JSON.stringify({
      status: "completed",
      output: [{ content: [{ type: "output_text", text: "x".repeat(1_048_577) }] }],
    });
    let message = "";
    try {
      await callStandardText({
        route: LUNA_ROUTE, feature: "weekly.insight", messages: [{ role: "user", content: "u" }],
        maxTokens: 10, json: false, signal: AbortSignal.timeout(5000),
        fetcher: () => Promise.resolve(new Response(big)),
      });
    } catch (error) {
      message = (error as Error).message;
    }
    assert(message === "AI_TEXT_RESPONSE_TOO_LARGE", `Oversized body accepted (${message})`);
  });
});

Deno.test("an abort while reading cancels and releases a stalled OpenAI body", async () => {
  await withEnv({ VOICE_AND_NONIMAGE_OPENAI_API_KEY: "synthetic" }, async () => {
    let cancelled = false;
    // A stream that never ends and ignores the request signal.
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new TextEncoder().encode("{\"status\":"));
      },
      cancel() {
        cancelled = true;
      },
    });
    const controller = new AbortController();
    const pending = callStandardText({
      route: LUNA_ROUTE, feature: "weekly.insight", messages: [{ role: "user", content: "u" }],
      maxTokens: 10, json: false, signal: controller.signal,
      fetcher: () => Promise.resolve(new Response(body)),
    });
    await new Promise((r) => setTimeout(r, 10));
    controller.abort();
    let rejected = false;
    try {
      await pending;
    } catch {
      rejected = true;
    }
    assert(rejected, "Abort did not reject");
    assert(cancelled, "Stalled body was not cancelled");
    assert(!body.locked, "Body reader lock was not released");
  });
});
