// Pure transport/adapter checks: no env, credentials, network or external imports.
import { openAIBudgetReservation } from "../functions/_shared/openai-budget.ts";
import { generateChatText } from "../functions/_shared/openai-chat.ts";
import {
  type MonthlyAIBudgetAdmin,
  MonthlyAIBudgetExhaustedError,
  MonthlyAIBudgetUnavailableError,
} from "../functions/_shared/monthly-ai-budget.ts";

const userId = "23456789-2345-4345-8345-23456789abcd";
const messages = [{ role: "user" as const, content: "Synthetic adapter test" }];
type Params = Parameters<MonthlyAIBudgetAdmin["rpc"]>[1];

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

async function expectedError(
  operation: () => Promise<unknown>,
  kind:
    | typeof MonthlyAIBudgetExhaustedError
    | typeof MonthlyAIBudgetUnavailableError,
) {
  try {
    await operation();
  } catch (error) {
    assert(error instanceof kind, "Wrong monthly admission error");
    return;
  }
  throw new Error("Expected monthly admission denial");
}

Deno.test("chat monthly adapter: owns each fixed feature and creates a UUID per submission", async () => {
  const calls: Params[] = [];
  const admin: MonthlyAIBudgetAdmin = {
    rpc(name, params) {
      assert(name === "reserve_monthly_ai_budget");
      calls.push(params);
      return Promise.resolve({ data: receipt(params), error: null });
    },
  };
  let providerCalls = 0;
  let quotaCalls = 0;
  const fetcher: typeof fetch = () => {
    providerCalls++;
    assert(calls.length === providerCalls, "Provider preceded its reservation");
    assert(quotaCalls === providerCalls, "Provider preceded quota debit");
    return Promise.resolve(Response.json({
      status: "completed",
      output: [{
        content: [{ type: "output_text", text: "Synthetic result" }],
      }],
    }));
  };
  const reserveResponse = openAIBudgetReservation(
    admin,
    userId,
    "chat.response",
  );
  for (
    const reserveBudget of [
      reserveResponse,
      reserveResponse,
      openAIBudgetReservation(admin, userId, "chat.title"),
      openAIBudgetReservation(admin, userId, "chat.memory"),
    ]
  ) {
    await generateChatText(messages, {
      apiKey: "synthetic-only",
      reserveBudget,
      beforeProvider: () => {
        quotaCalls++;
        return Promise.resolve();
      },
      fetcher,
    });
  }
  assert(providerCalls === 4 && quotaCalls === 4 && calls.length === 4);
  assert(
    calls.map((call) => call.p_feature).join() ===
      "chat.response,chat.response,chat.title,chat.memory",
  );
  assert(calls.every((call) => call.p_user_id === userId));
  assert(
    calls.every((call) =>
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
        .test(call.p_request_id)
    ),
  );
  assert(
    new Set(calls.map((call) => call.p_request_id)).size === 4,
    "Billable submissions shared a reservation UUID",
  );
  assert(
    calls.every((call) =>
      call.p_reserve_microdollars ===
        Math.ceil(
          (new TextEncoder().encode(JSON.stringify(messages)).length + 1024) *
              0.125 + 500 * 0.5,
        )
    ),
    "Adapter changed transport cost bound",
  );
});

Deno.test("chat monthly adapter: exhausted or unavailable ledger never debits quota or submits", async () => {
  for (const mode of ["exhausted", "unavailable", "invalid"] as const) {
    let rpcCalls = 0;
    let quotaCalls = 0;
    let providerCalls = 0;
    const admin: MonthlyAIBudgetAdmin = {
      rpc(_name, params) {
        rpcCalls++;
        return Promise.resolve({
          data: mode === "invalid" ? true : receipt(params, false),
          error: mode === "unavailable"
            ? { message: "Synthetic private failure" }
            : null,
        });
      },
    };
    await expectedError(
      () =>
        generateChatText(messages, {
          apiKey: "synthetic-only",
          reserveBudget: openAIBudgetReservation(
            admin,
            userId,
            "chat.response",
          ),
          beforeProvider: () => {
            quotaCalls++;
            return Promise.resolve();
          },
          fetcher: () => {
            providerCalls++;
            throw new Error("Unexpected provider submission");
          },
        }),
      mode === "exhausted"
        ? MonthlyAIBudgetExhaustedError
        : MonthlyAIBudgetUnavailableError,
    );
    assert(rpcCalls === 1 && quotaCalls === 0 && providerCalls === 0);
  }
});

Deno.test("chat monthly adapter: invalid owner cannot reach the ledger", async () => {
  let rpcCalls = 0;
  const admin: MonthlyAIBudgetAdmin = {
    rpc() {
      rpcCalls++;
      throw new Error("Unexpected ledger request");
    },
  };
  await expectedError(
    () => openAIBudgetReservation(admin, "", "chat.response")(100),
    MonthlyAIBudgetUnavailableError,
  );
  assert(rpcCalls === 0);
});

Deno.test("chat monthly adapter: forwards admission cancellation and never debits or submits", async () => {
  const cancellation = new AbortController();
  let rpcCalls = 0;
  let quotaCalls = 0;
  let providerCalls = 0;
  let forwarded: AbortSignal | undefined;
  const admin: MonthlyAIBudgetAdmin = {
    rpc(_name, params) {
      rpcCalls++;
      return Object.assign(
        Promise.resolve({ data: receipt(params), error: null }),
        {
          abortSignal(signal: AbortSignal) {
            forwarded = signal;
            cancellation.abort();
            return Promise.reject(
              new DOMException("Synthetic cancellation", "AbortError"),
            );
          },
        },
      );
    },
  };
  await expectedError(() =>
    generateChatText(messages, {
      apiKey: "synthetic-only",
      reserveBudget: openAIBudgetReservation(
        admin,
        userId,
        "chat.response",
        cancellation.signal,
      ),
      signal: cancellation.signal,
      beforeProvider: () => {
        quotaCalls++;
        return Promise.resolve();
      },
      fetcher: () => {
        providerCalls++;
        throw new Error("Unexpected provider submission");
      },
    }), MonthlyAIBudgetUnavailableError);
  assert(forwarded === cancellation.signal && rpcCalls === 1);
  assert(quotaCalls === 0 && providerCalls === 0);
  await expectedError(
    () =>
      openAIBudgetReservation(
        admin,
        userId,
        "chat.response",
        cancellation.signal,
      )(100),
    MonthlyAIBudgetUnavailableError,
  );
  assert(rpcCalls === 1, "Pre-aborted admission reached ledger again");
});
