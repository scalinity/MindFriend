// No network, env, credentials, provider calls, or external test imports.
import {
  MonthlyAIBudgetAdmin,
  MonthlyAIBudgetExhaustedError,
  MonthlyAIBudgetRequest,
  MonthlyAIBudgetUnavailableError,
  reserveMonthlyAIBudget,
} from "../functions/_shared/monthly-ai-budget.ts";

const input: MonthlyAIBudgetRequest = {
  requestId: "12345678-1234-4234-8234-123456789abc",
  userId: "23456789-2345-4345-8345-23456789abcd",
  feature: "chat.title",
  reserveMicrodollars: 250,
};

function receipt(overrides: Record<string, unknown> = {}) {
  return {
    allowed: true,
    reason: "reserved",
    request_id: input.requestId,
    user_id: input.userId,
    feature: input.feature,
    month_start: "2026-10-01",
    reserve_microdollars: 250,
    reserved_microdollars: 750,
    limit_microdollars: 10_000_000,
    remaining_microdollars: 9_999_250,
    ...overrides,
  };
}

function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}

function adminWith(data: unknown, error: unknown = null): MonthlyAIBudgetAdmin {
  return { rpc: () => Promise.resolve({ data, error }) };
}

async function unavailable(
  operation: () => Promise<unknown>,
  reason: MonthlyAIBudgetUnavailableError["reason"],
) {
  try {
    await operation();
  } catch (error) {
    assert(error instanceof MonthlyAIBudgetUnavailableError);
    assert(error.code === "monthly_ai_budget_unavailable");
    assert(error.reason === reason, `Expected ${reason}, got ${error.reason}`);
    return;
  }
  throw new Error("Expected unavailable error");
}

Deno.test("monthly budget: forwards only RPC arguments and maps a valid receipt", async () => {
  let calls = 0;
  const admin: MonthlyAIBudgetAdmin = {
    rpc(name, params) {
      calls++;
      assert(name === "reserve_monthly_ai_budget");
      assert(
        JSON.stringify(params) === JSON.stringify({
          p_request_id: input.requestId,
          p_user_id: input.userId,
          p_feature: input.feature,
          p_reserve_microdollars: 250,
        }),
      );
      return Promise.resolve({ data: receipt(), error: null });
    },
  };
  const result = await reserveMonthlyAIBudget(admin, {
    ...input,
    requestId: input.requestId.toUpperCase(),
    userId: input.userId.toUpperCase(),
  });
  assert(calls === 1);
  assert(
    result.requestId === input.requestId && result.userId === input.userId,
  );
  assert(
    result.monthStart === "2026-10-01" && result.reserveMicrodollars === 250,
  );
  assert(result.limitMicrodollars === 10_000_000);
  assert(
    result.reservedMicrodollars === 750 &&
      result.remainingMicrodollars === 9_999_250,
  );
});

Deno.test("monthly budget: accepts exact ceiling and a reduced limit", async () => {
  for (const limit of [250, 10_000_000]) {
    const result = await reserveMonthlyAIBudget(
      adminWith(receipt({
        reserved_microdollars: limit,
        limit_microdollars: limit,
        remaining_microdollars: 0,
      })),
      input,
    );
    assert(result.remainingMicrodollars === 0);
  }
});

Deno.test("monthly budget: retries preserve identity and accept an old month snapshot", async () => {
  let calls = 0;
  const admin: MonthlyAIBudgetAdmin = {
    rpc(_name, params) {
      calls++;
      assert(params.p_request_id === input.requestId);
      return Promise.resolve({
        data: receipt({ month_start: "2025-12-01" }),
        error: null,
      });
    },
  };
  const first = await reserveMonthlyAIBudget(admin, input);
  const retry = await reserveMonthlyAIBudget(admin, input);
  assert(calls === 2 && JSON.stringify(first) === JSON.stringify(retry));
});

Deno.test("monthly budget: valid exhaustion has a distinct typed error", async () => {
  for (const used of [9_999_999, 10_000_000]) {
    try {
      await reserveMonthlyAIBudget(
        adminWith(receipt({
          allowed: false,
          reason: "exhausted",
          reserved_microdollars: used,
          remaining_microdollars: 10_000_000 - used,
        })),
        input,
      );
      throw new Error("Expected exhaustion");
    } catch (error) {
      assert(error instanceof MonthlyAIBudgetExhaustedError);
      assert(error.code === "monthly_ai_budget_exhausted");
      assert(error.reservation.reservedMicrodollars === used);
    }
  }
});

Deno.test("monthly budget: disabled, rollback, and mismatched UUID results fail closed", async () => {
  await unavailable(() =>
    reserveMonthlyAIBudget(
      adminWith(receipt({
        allowed: false,
        reason: "disabled",
        limit_microdollars: 0,
        remaining_microdollars: 0,
      })),
      input,
    ), "disabled");
  for (const reason of ["request_mismatch", "unavailable"] as const) {
    await unavailable(
      () =>
        reserveMonthlyAIBudget(adminWith({ allowed: false, reason }), input),
      reason,
    );
  }
});

Deno.test("monthly budget: invalid input never invokes RPC", async () => {
  const invalid = [
    { reserveMicrodollars: 0 },
    { reserveMicrodollars: -1 },
    { reserveMicrodollars: 0.5 },
    { reserveMicrodollars: NaN },
    { reserveMicrodollars: Infinity },
    { reserveMicrodollars: 10_000_001 },
    { reserveMicrodollars: "250" },
    { requestId: "bad" },
    { userId: "bad" },
    { requestId: input.requestId + "\n" },
    { feature: "" },
    { feature: "Chat" },
    { feature: "chat title" },
    { feature: "chat\n" },
    { feature: "x".repeat(65) },
  ];
  let calls = 0;
  const admin: MonthlyAIBudgetAdmin = {
    rpc() {
      calls++;
      return Promise.resolve({ data: receipt(), error: null });
    },
  };
  for (const patch of invalid) {
    await unavailable(() =>
      reserveMonthlyAIBudget(admin, {
        ...input,
        ...patch,
      } as MonthlyAIBudgetRequest), "invalid_request");
  }
  assert(calls === 0);
});

Deno.test("monthly budget: malformed, unbound, or contradictory receipts fail closed", async () => {
  const invalid = [
    null,
    [],
    {},
    true,
    receipt({ allowed: "true" }),
    receipt({ reason: "unknown" }),
    receipt({ request_id: input.userId }),
    receipt({ user_id: input.requestId }),
    receipt({ feature: "another" }),
    receipt({ reserve_microdollars: 251 }),
    receipt({ month_start: "2026-13-01" }),
    receipt({ month_start: "2026-10-02" }),
    receipt({ month_start: "2026-10-01\n" }),
    receipt({ limit_microdollars: 10_000_001 }),
    receipt({ limit_microdollars: -1 }),
    receipt({ limit_microdollars: 0.5 }),
    receipt({ limit_microdollars: "10000000" }),
    receipt({ reserved_microdollars: -1 }),
    receipt({ reserved_microdollars: 0.5 }),
    receipt({ reserved_microdollars: 10_000_001 }),
    receipt({ reserved_microdollars: 249, remaining_microdollars: 9_999_751 }),
    receipt({ remaining_microdollars: -1 }),
    receipt({ remaining_microdollars: 0.5 }),
    receipt({ remaining_microdollars: 10_000_001 }),
    receipt({ remaining_microdollars: 99 }),
    receipt({
      reserved_microdollars: 1000,
      limit_microdollars: 999,
      remaining_microdollars: 0,
    }),
    receipt({ allowed: false, reason: "reserved" }),
    receipt({ allowed: false, reason: "exhausted" }),
    receipt({ allowed: false, reason: "disabled" }),
    receipt({ allowed: true, reason: "request_mismatch" }),
    receipt({
      allowed: true,
      reason: "disabled",
      limit_microdollars: 0,
      remaining_microdollars: 0,
    }),
  ];
  for (const data of invalid) {
    await unavailable(
      () => reserveMonthlyAIBudget(adminWith(data), input),
      "invalid_response",
    );
  }
});

Deno.test("monthly budget: transport and permission errors never expose raw diagnostics", async () => {
  for (
    const error of [
      { code: "42501", message: "private diagnostic" },
      "failure",
      false,
    ]
  ) {
    await unavailable(
      () => reserveMonthlyAIBudget(adminWith(receipt(), error), input),
      "rpc_error",
    );
  }
  const throws: MonthlyAIBudgetAdmin = {
    rpc() {
      throw new Error("private diagnostic");
    },
  };
  await unavailable(() => reserveMonthlyAIBudget(throws, input), "rpc_error");
  const rejects: MonthlyAIBudgetAdmin = {
    rpc: () => Promise.reject(new Error("timeout")),
  };
  await unavailable(() => reserveMonthlyAIBudget(rejects, input), "rpc_error");
  const missing = {} as MonthlyAIBudgetAdmin;
  await unavailable(() => reserveMonthlyAIBudget(missing, input), "rpc_error");
  const incomplete: MonthlyAIBudgetAdmin = {
    rpc: () => Promise.resolve({ data: receipt(), error: undefined }),
  };
  await unavailable(
    () => reserveMonthlyAIBudget(incomplete, input),
    "rpc_error",
  );
});

Deno.test("monthly budget: forwards cancellation and keeps an aborted admission unavailable", async () => {
  const controller = new AbortController();
  let calls = 0;
  const admin: MonthlyAIBudgetAdmin = {
    rpc() {
      calls++;
      return Object.assign(Promise.resolve({ data: receipt(), error: null }), {
        abortSignal(signal: AbortSignal) {
          assert(signal === controller.signal);
          return Promise.resolve({ data: receipt(), error: null });
        },
      });
    },
  };
  await reserveMonthlyAIBudget(admin, input, controller.signal);
  controller.abort();
  await unavailable(
    () => reserveMonthlyAIBudget(admin, input, controller.signal),
    "aborted",
  );
  assert(calls === 1);
  const later = new AbortController();
  const aborts: MonthlyAIBudgetAdmin = {
    rpc() {
      return Object.assign(Promise.resolve({ data: receipt(), error: null }), {
        abortSignal() {
          later.abort();
          return Promise.resolve({ data: receipt(), error: null });
        },
      });
    },
  };
  await unavailable(
    () => reserveMonthlyAIBudget(aborts, input, later.signal),
    "aborted",
  );
  await unavailable(
    () =>
      reserveMonthlyAIBudget(
        adminWith(receipt()),
        input,
        new AbortController().signal,
      ),
    "unavailable",
  );
});
