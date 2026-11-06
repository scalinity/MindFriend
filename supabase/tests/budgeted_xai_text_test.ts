// Pure dispatcher tests: no credentials, env, network or external imports.
import {
  budgetedXAIText,
  XAI_TEXT_MODEL,
} from "../functions/_shared/budgeted-xai-text.ts";
import {
  type MonthlyAIBudgetAdmin,
  MonthlyAIBudgetExhaustedError,
  MonthlyAIBudgetUnavailableError,
} from "../functions/_shared/monthly-ai-budget.ts";

const userId = "23456789-2345-4345-8345-23456789abcd";
type Params = Parameters<MonthlyAIBudgetAdmin["rpc"]>[1];
const messages = [{
  role: "system" as const,
  content: "Synthetic final prompt",
}, { role: "user" as const, content: '漢\n"quoted"' }];

Deno.test("xAI monthly dispatcher: quota hook follows admission and never runs on denial or pre-abort", async () => {
  for (
    const mode of [
      "allowed",
      "exhausted",
      "unavailable",
      "pre-abort",
      "hook-abort",
    ] as const
  ) {
    const calls: Params[] = [];
    const cancellation = new AbortController();
    if (mode === "pre-abort") cancellation.abort();
    let quotaCalls = 0;
    let providerCalls = 0;
    const operation = () =>
      budgetedXAIText({
        admin: mockAdmin(
          calls,
          mode === "exhausted" || mode === "unavailable" ? mode : "allowed",
        ),
        userId,
        feature: "content.text",
        apiKey: "synthetic-only",
        messages,
        maxTokens: 300,
        signal: cancellation.signal,
        beforeProvider(signal) {
          assert(
            calls.length === 1 && !signal.aborted,
            "Quota hook preceded successful monthly admission",
          );
          quotaCalls++;
          if (mode === "hook-abort") cancellation.abort();
          return Promise.resolve();
        },
        fetcher() {
          providerCalls++;
          assert(quotaCalls === 1, "Provider preceded quota hook");
          return Promise.resolve(Response.json({ choices: [] }));
        },
      });
    if (mode === "allowed") {
      const response = await operation();
      await response.text();
    } else await rejects(operation);
    assert(
      quotaCalls === (mode === "allowed" || mode === "hook-abort" ? 1 : 0),
      "Denied admission debited quota",
    );
    assert(
      providerCalls === (mode === "allowed" ? 1 : 0),
      "Denied/aborted quota hook reached provider",
    );
    assert(
      calls.length === (mode === "pre-abort" ? 0 : 1),
      "Reservation count changed around quota hook",
    );
  }
});

function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}

function receipt(params: Params, allowed = true) {
  const reserved = allowed ? params.p_reserve_microdollars : 10_000_000;
  return {
    allowed,
    reason: allowed ? "reserved" : "exhausted",
    request_id: params.p_request_id,
    user_id: params.p_user_id,
    feature: params.p_feature,
    month_start: "2026-10-01",
    reserve_microdollars: params.p_reserve_microdollars,
    reserved_microdollars: reserved,
    limit_microdollars: 10_000_000,
    remaining_microdollars: 10_000_000 - reserved,
  };
}

function mockAdmin(
  calls: Params[],
  mode: "allowed" | "exhausted" | "unavailable" = "allowed",
): MonthlyAIBudgetAdmin {
  return {
    rpc(name, params) {
      assert(name === "reserve_monthly_ai_budget");
      calls.push(params);
      const result = Promise.resolve({
        data: receipt(params, mode === "allowed"),
        error: mode === "unavailable"
          ? { message: "Synthetic private error" }
          : null,
      });
      return Object.assign(result, {
        abortSignal(signal: AbortSignal) {
          assert(signal instanceof AbortSignal);
          return result;
        },
      });
    },
  };
}

async function rejects(
  operation: () => Promise<unknown>,
  kind?:
    | typeof MonthlyAIBudgetExhaustedError
    | typeof MonthlyAIBudgetUnavailableError,
) {
  try {
    await operation();
  } catch (error) {
    assert(error instanceof Error || error instanceof DOMException);
    if (kind) assert(error instanceof kind);
    return;
  }
  throw new Error("Expected failure");
}

Deno.test("xAI monthly dispatcher: final prompt admission precedes every distinct pinned-model HTTP attempt", async () => {
  const calls: Params[] = [];
  let providerCalls = 0;
  const admin = mockAdmin(calls);
  for (let attempt = 0; attempt < 2; attempt++) {
    const response = await budgetedXAIText({
      admin,
      userId,
      feature: "rehearsal.reply",
      apiKey: "synthetic-only",
      messages,
      maxTokens: 300,
      temperature: 0.7,
      responseFormat: { type: "json_object" },
      fetcher(input, init) {
        providerCalls++;
        assert(String(input) === "https://api.x.ai/v1/chat/completions");
        assert(
          calls.length === providerCalls && calls.length === attempt + 1,
          "Missing per-attempt admission",
        );
        assert(init?.signal instanceof AbortSignal);
        const body = JSON.parse(init!.body as string);
        assert(
          body.model === XAI_TEXT_MODEL && body.model === "grok-4.3" &&
            body.reasoning_effort === "none",
        );
        assert(
          body.max_tokens === 300 && body.temperature === 0.7 &&
            body.response_format.type === "json_object",
        );
        assert(
          JSON.stringify(body.messages) === JSON.stringify(messages),
          "Final messages changed after admission",
        );
        assert(!("tools" in body) && !("stream" in body));
        return Promise.resolve(
          attempt === 0
            ? new Response("Synthetic private provider failure", {
              status: 429,
            })
            : Response.json({
              choices: [{ message: { content: "Synthetic result" } }],
            }),
        );
      },
    });
    assert(response.status === (attempt === 0 ? 429 : 200));
    if (attempt === 0) {
      assert(
        await response.text() === "",
        "Provider diagnostic escaped dispatcher",
      );
    } else {assert(
        (await response.json()).choices[0].message.content ===
          "Synthetic result",
      );}
  }
  assert(
    providerCalls === 2 && calls.length === 2,
    "Dispatcher silently retried",
  );
  assert(
    calls[0].p_request_id !== calls[1].p_request_id,
    "Distinct paid attempts reused reservation",
  );
  assert(
    calls.every((call) =>
      call.p_user_id === userId && call.p_feature === "rehearsal.reply"
    ),
  );
  const cost = Math.ceil(
    (new TextEncoder().encode(JSON.stringify(messages)).length + 1024) * 1.25 +
      300 * 2.5,
  );
  assert(
    calls.every((call) => call.p_reserve_microdollars === cost),
    "Wrong conservative cost calculation",
  );
});

Deno.test("xAI monthly dispatcher: malformed/full UTF-8 prompts and unbounded output fail before admission", async () => {
  const calls: Params[] = [];
  let providerCalls = 0;
  const options = {
    admin: mockAdmin(calls),
    userId,
    feature: "content.text",
    apiKey: "synthetic-only",
    messages,
    maxTokens: 300,
    fetcher: () => {
      providerCalls++;
      throw new Error("Unexpected provider");
    },
  };
  const invalid = [
    { maxTokens: 0 },
    { maxTokens: 8001 },
    { maxTokens: Infinity },
    { maxTokens: NaN },
    { maxTokens: 1.5 },
    { messages: [] },
    { messages: Array.from({ length: 65 }, () => messages[0]) },
    { messages: [{ role: "user", content: "漢".repeat(43_000) }] },
    { messages: [{ role: "tool", content: "forbidden" }] },
    {
      messages: [{
        role: "user",
        content: [{
          type: "image_url",
          image_url: "https://invalid.example/image",
        }],
      }],
    },
    { messages: [{ role: "user", content: "text", tool_calls: [] }] },
    { temperature: NaN },
    { responseFormat: { type: "json_schema" } },
  ];
  for (const override of invalid) {
    await rejects(() =>
      budgetedXAIText(
        { ...options, ...override } as Parameters<typeof budgetedXAIText>[0],
      )
    );
  }
  assert(calls.length === 0 && providerCalls === 0);
});

Deno.test("xAI monthly dispatcher: exhausted/unavailable ledger makes zero HTTP attempts", async () => {
  for (const mode of ["exhausted", "unavailable"] as const) {
    const calls: Params[] = [];
    let providerCalls = 0;
    await rejects(
      () =>
        budgetedXAIText({
          admin: mockAdmin(calls, mode),
          userId,
          feature: "weekly.insight",
          apiKey: "synthetic-only",
          messages,
          maxTokens: 400,
          fetcher: () => {
            providerCalls++;
            throw new Error("Unexpected provider");
          },
        }),
      mode === "exhausted"
        ? MonthlyAIBudgetExhaustedError
        : MonthlyAIBudgetUnavailableError,
    );
    assert(calls.length === 1 && providerCalls === 0);
  }
});

Deno.test("xAI monthly dispatcher: pre-abort and admission cancellation prevent HTTP attempts", async () => {
  const cancellation = new AbortController();
  const calls: Params[] = [];
  let providerCalls = 0;
  let admissionSignal: AbortSignal | undefined;
  const admin: MonthlyAIBudgetAdmin = {
    rpc(_name, params) {
      calls.push(params);
      const result = Promise.resolve({ data: receipt(params), error: null });
      return Object.assign(result, {
        abortSignal(signal: AbortSignal) {
          admissionSignal = signal;
          cancellation.abort();
          return result;
        },
      });
    },
  };
  const options = {
    admin,
    userId,
    feature: "journal.analysis",
    apiKey: "synthetic-only",
    messages,
    maxTokens: 2000,
    signal: cancellation.signal,
    fetcher: () => {
      providerCalls++;
      throw new Error("Unexpected provider");
    },
  };
  await rejects(() => budgetedXAIText(options));
  assert(admissionSignal?.aborted && calls.length === 1 && providerCalls === 0);
  await rejects(() => budgetedXAIText(options));
  assert(calls.length === 1 && providerCalls === 0);
});

Deno.test("xAI monthly dispatcher: body cancellation and oversized responses retain one reservation", async () => {
  const calls: Params[] = [];
  const cancellation = new AbortController();
  let bodyCancelled = false;
  await rejects(() =>
    budgetedXAIText({
      admin: mockAdmin(calls),
      userId,
      feature: "sleep.story",
      apiKey: "synthetic-only",
      messages,
      maxTokens: 8000,
      signal: cancellation.signal,
      fetcher: () =>
        Promise.resolve(
          new Response(
            new ReadableStream({
              pull() {
                cancellation.abort();
                return new Promise(() => {});
              },
              cancel() {
                bodyCancelled = true;
              },
            }, { highWaterMark: 0 }),
          ),
        ),
    })
  );
  assert(
    calls.length === 1 && bodyCancelled,
    "Uncertain attempt lost reservation or body remained open",
  );
  await rejects(() =>
    budgetedXAIText({
      admin: mockAdmin(calls),
      userId,
      feature: "sleep.story",
      apiKey: "synthetic-only",
      messages,
      maxTokens: 8000,
      fetcher: () => Promise.resolve(new Response(new Uint8Array(1_048_577))),
    })
  );
  assert(Number(calls.length) === 2);
});
