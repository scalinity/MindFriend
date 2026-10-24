/**
 * Reserve a conservative cost bound before paid submission. The caller supplies
 * an admin client and a stable UUID; this module reads no credentials or env.
 * A matching retry reuses its receipt, not provider work. Keep a reservation on
 * abort/timeout/unknown outcomes; this helper never refunds or submits to providers.
 */
export const MONTHLY_AI_BUDGET_MAX_MICRODOLLARS = 10_000_000;

// Attribution for shared-library work authenticated with the exact service key.
// This is a stable workload identity, not an Auth user or an authorization grant.
// User-owned requests must continue to use the verified user's actual UUID.
export const BACKEND_WORKLOAD_BUDGET_PRINCIPAL =
  "16a71d85-ba11-59a9-a1e6-03301aa0bcde";

export interface MonthlyAIBudgetRequest {
  requestId: string;
  userId: string;
  feature: string;
  reserveMicrodollars: number;
}

interface RPCResult {
  data: unknown;
  error: unknown;
}

type RPCRequest = PromiseLike<RPCResult> & {
  abortSignal?: (signal: AbortSignal) => PromiseLike<RPCResult>;
};

/** Structural interface keeps the helper injectable without a runtime SDK import. */
export interface MonthlyAIBudgetAdmin {
  rpc(
    name: "reserve_monthly_ai_budget",
    params: {
      p_request_id: string;
      p_user_id: string;
      p_feature: string;
      p_reserve_microdollars: number;
    },
  ): RPCRequest;
}

export interface MonthlyAIBudgetReservation extends MonthlyAIBudgetRequest {
  monthStart: string;
  reservedMicrodollars: number;
  limitMicrodollars: number;
  remainingMicrodollars: number;
}

export class MonthlyAIBudgetUnavailableError extends Error {
  readonly code = "monthly_ai_budget_unavailable";
  constructor(
    readonly reason:
      | "invalid_request"
      | "invalid_response"
      | "rpc_error"
      | "aborted"
      | "disabled"
      | "request_mismatch"
      | "unavailable",
  ) {
    super("Monthly AI budget is unavailable.");
    this.name = "MonthlyAIBudgetUnavailableError";
  }
}

export class MonthlyAIBudgetExhaustedError extends Error {
  readonly code = "monthly_ai_budget_exhausted";
  constructor(readonly reservation: MonthlyAIBudgetReservation) {
    super("Monthly AI budget is exhausted.");
    this.name = "MonthlyAIBudgetExhaustedError";
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const FEATURE = /^[a-z][a-z0-9_.:-]{0,63}$/;

function boundedInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) &&
    value >= 0 && value <= MONTHLY_AI_BUDGET_MAX_MICRODOLLARS;
}

/** Throws on every denial, transport error, or malformed response; never retries. */
export async function reserveMonthlyAIBudget(
  admin: MonthlyAIBudgetAdmin,
  input: MonthlyAIBudgetRequest,
  signal?: AbortSignal,
): Promise<MonthlyAIBudgetReservation> {
  try {
    if (
      typeof input.requestId !== "string" || input.requestId.length !== 36 ||
      !UUID.test(input.requestId) || typeof input.userId !== "string" ||
      input.userId.length !== 36 || !UUID.test(input.userId) ||
      typeof input.feature !== "string" ||
      input.feature.trim() !== input.feature ||
      !FEATURE.test(input.feature) ||
      !boundedInteger(input.reserveMicrodollars) ||
      input.reserveMicrodollars === 0
    ) {
      throw new MonthlyAIBudgetUnavailableError("invalid_request");
    }
    if (signal?.aborted) throw new MonthlyAIBudgetUnavailableError("aborted");
    const request = admin.rpc("reserve_monthly_ai_budget", {
      p_request_id: input.requestId.toLowerCase(),
      p_user_id: input.userId.toLowerCase(),
      p_feature: input.feature,
      p_reserve_microdollars: input.reserveMicrodollars,
    });
    if (signal && typeof request.abortSignal !== "function") {
      throw new MonthlyAIBudgetUnavailableError("unavailable");
    }
    const result = await (signal ? request.abortSignal!(signal) : request);
    if (signal?.aborted) throw new MonthlyAIBudgetUnavailableError("aborted");
    if (!result || result.error !== null) {
      throw new MonthlyAIBudgetUnavailableError("rpc_error");
    }
    const data = result.data;
    if (typeof data !== "object" || data === null || Array.isArray(data)) {
      throw new MonthlyAIBudgetUnavailableError("invalid_response");
    }
    const row = data as Record<string, unknown>;
    if (
      row.allowed === false &&
      (row.reason === "request_mismatch" || row.reason === "unavailable")
    ) {
      throw new MonthlyAIBudgetUnavailableError(row.reason);
    }
    if (
      typeof row.allowed !== "boolean" ||
      row.request_id !== input.requestId.toLowerCase() ||
      row.user_id !== input.userId.toLowerCase() ||
      row.feature !== input.feature ||
      row.reserve_microdollars !== input.reserveMicrodollars ||
      typeof row.month_start !== "string" ||
      !/^\d{4}-(0[1-9]|1[0-2])-01$/.test(row.month_start) ||
      row.month_start.length !== 10 ||
      !boundedInteger(row.reserved_microdollars) ||
      !boundedInteger(row.limit_microdollars) ||
      !boundedInteger(row.remaining_microdollars) ||
      row.remaining_microdollars !==
        Math.max(row.limit_microdollars - row.reserved_microdollars, 0)
    ) {
      throw new MonthlyAIBudgetUnavailableError("invalid_response");
    }
    const reservation: MonthlyAIBudgetReservation = {
      requestId: row.request_id as string,
      userId: row.user_id as string,
      feature: row.feature as string,
      reserveMicrodollars: input.reserveMicrodollars,
      monthStart: row.month_start,
      reservedMicrodollars: row.reserved_microdollars,
      limitMicrodollars: row.limit_microdollars,
      remainingMicrodollars: row.remaining_microdollars,
    };
    if (
      row.allowed && row.reason === "reserved" &&
      row.limit_microdollars > 0 &&
      row.reserved_microdollars >= input.reserveMicrodollars &&
      row.reserved_microdollars <= row.limit_microdollars
    ) return reservation;
    if (
      !row.allowed && row.reason === "disabled" && row.limit_microdollars === 0
    ) {
      throw new MonthlyAIBudgetUnavailableError("disabled");
    }
    if (
      !row.allowed && row.reason === "exhausted" &&
      row.limit_microdollars > 0 &&
      input.reserveMicrodollars > row.remaining_microdollars
    ) throw new MonthlyAIBudgetExhaustedError(reservation);
    throw new MonthlyAIBudgetUnavailableError("invalid_response");
  } catch (error) {
    if (
      error instanceof MonthlyAIBudgetUnavailableError ||
      error instanceof MonthlyAIBudgetExhaustedError
    ) throw error;
    throw new MonthlyAIBudgetUnavailableError("rpc_error");
  }
}
