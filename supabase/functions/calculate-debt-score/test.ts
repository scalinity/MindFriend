import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1.0.19";
import {
  currentSourceTransactions,
  ledgerDate,
} from "./source-transactions.ts";
import type {
  Transaction,
  UserProfile,
} from "../_shared/wellbeing-debt-types.ts";
Deno.env.set("SUPABASE_URL", "https://synthetic.invalid");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "synthetic-test-key");
let handler: (req: Request) => Promise<Response>;
const originalServe = Deno.serve;
Deno.serve = ((callback: typeof handler) => {
  handler = callback;
  return {};
}) as typeof Deno.serve;
const {
  calculateUserDebtScore,
  calculateRollingDebt,
  calculateDailyBalance,
  calculateTrend,
  calculateThresholdStatus,
} = await import("./index.ts");
Deno.serve = originalServe;
const owner = "11111111-1111-4111-8111-111111111111";
const other = "22222222-2222-4222-8222-222222222222";
type Row = Record<string, any>;
const profile: UserProfile = {
  user_id: owner,
  personal_threshold: -75,
  crash_history: { crashes: [], last_updated: null },
  top_drains: { categories: [], last_updated: null },
  top_deposits: { categories: [], last_updated: null },
};
function transaction(
  date: string,
  type: Transaction["type"],
  amount: number,
): Transaction {
  return {
    id: crypto.randomUUID(),
    user_id: owner,
    date,
    type,
    amount,
    category: "work_stress",
    source: "user_logged",
  };
}
class Fixture {
  tables: Record<string, Row[]> = {
    profiles: [{ id: owner, created_at: "2025-01-01T00:00:00Z" }],
    wellbeing_debt_profiles: [profile],
  };
  failedTable: string | null = null;
  reads: {
    table: string;
    filters: [string, string, any][];
    columns: string;
  }[] = [];
  from(table: string) {
    const filters: [string, string, any][] = [];
    const read = { table, filters, columns: "" };
    this.reads.push(read);
    let one = false, start = 0, end = Infinity;
    const q: any = {
      select: (columns: string) => {
        read.columns = columns;
        return q;
      },
      eq: (key: string, value: any) => {
        filters.push(["eq", key, value]);
        return q;
      },
      gte: (key: string, value: any) => {
        filters.push(["gte", key, value]);
        return q;
      },
      lte: (key: string, value: any) => {
        filters.push(["lte", key, value]);
        return q;
      },
      lt: (key: string, value: any) => {
        filters.push(["lt", key, value]);
        return q;
      },
      order: () => q,
      range: (a: number, b: number) => {
        start = a;
        end = b;
        return q;
      },
      single: () => {
        one = true;
        return q;
      },
      maybeSingle: () => {
        one = true;
        return q;
      },
      then: (resolve: (r: unknown) => unknown) => {
        const rows = (this.tables[table] ?? []).filter((r) =>
          filters.every(([op, key, value]) =>
            op === "eq"
              ? r[key] === value
              : op === "gte"
              ? r[key] >= value
              : op === "lte"
              ? r[key] <= value
              : r[key] < value
          )
        ).slice(start, end + 1);
        return Promise.resolve({
          data: one ? rows[0] ?? null : rows,
          error: this.failedTable === table
            ? { message: "synthetic failure" }
            : null,
        }).then(resolve);
      },
    };
    return q;
  }
}
Deno.test("debt domain, exact N-day windows and decimal amounts", () => {
  const records = [
    transaction("2026-10-08", "withdrawal", 900),
    transaction("2026-10-09", "withdrawal", 200.25),
    transaction("2026-10-22", "deposit", 0.1),
    transaction("2026-10-22", "deposit", 0.2),
    transaction("2026-10-23", "withdrawal", 500),
  ];
  assertEquals(calculateRollingDebt(records, "2026-10-22", 14), 199.95);
  assertEquals(calculateRollingDebt(records, "2026-10-22", 7), 0);
  assertEquals(calculateDailyBalance(records, "2026-10-22"), 0.3);
  assertEquals(calculateDailyBalance(records, "2026-10-09"), -100);
  assertEquals(ledgerDate("2026-03-09", -1), "2026-03-08");
  assertThrows(() => ledgerDate("2026-02-30"));
});
Deno.test("trends use debt magnitude and actual date gaps, never negative projected debt", () => {
  const rising = [
    transaction("2026-10-17", "withdrawal", 10),
    transaction("2026-10-22", "withdrawal", 10),
  ];
  const up = calculateTrend(rising, "2026-10-22");
  assertEquals(up.velocity, 2);
  assertEquals(up.direction, "worsening");
  assertEquals(up.projection_7day, 34);
  const falling = [
    transaction("2026-10-17", "withdrawal", 30),
    transaction("2026-10-22", "deposit", 30),
  ];
  const down = calculateTrend(falling, "2026-10-22");
  assertEquals(down.direction, "improving");
  assertEquals(down.projection_7day, 0);
  assertEquals(
    calculateTrend([transaction("2026-10-22", "withdrawal", 5)], "2026-10-22")
      .available,
    false,
  );
});
Deno.test("current snapshot reconciles corrected/deleted sources, explicit events and ownership", async () => {
  const f = new Fixture();
  f.tables.wellbeing_transactions = [{
    ...transaction("2026-10-22", "withdrawal", 1.25),
  }, {
    ...transaction("2026-10-22", "withdrawal", 99),
    source: "inferred",
    category: "social_isolation",
  }, {
    ...transaction("2026-10-22", "deposit", 88),
    source: "exercise_sessions",
  }, { ...transaction("2026-10-22", "withdrawal", 50), user_id: other }];
  f.tables.exercise_sessions = [
    {
      id: "exercise",
      user_id: owner,
      completed_at: "2026-10-22T23:59:59.999Z",
    },
    { id: "other", user_id: other, completed_at: "2026-10-22T12:00:00Z" },
    { id: "next", user_id: owner, completed_at: "2026-10-23T00:00:00Z" },
  ];
  f.tables.quests = [{
    id: "quest",
    user_id: owner,
    local_date: "2026-10-22",
    status: "completed",
  }];
  f.tables.moods = [{
    id: "mood",
    user_id: owner,
    local_date: "2026-10-22",
    mood_score: 2,
  }];
  const score = await calculateUserDebtScore(f, owner, "2026-10-22");
  assertEquals(score?.rolling_debt_14day, 0);
  assertEquals(score?.daily_balance, 12.75);
  assertEquals(score?.source_transactions.length, 4);
  f.tables.exercise_sessions = [];
  f.tables.quests[0].status = "pending";
  const corrected = await calculateUserDebtScore(f, owner, "2026-10-22");
  assertEquals(corrected?.rolling_debt_14day, 3.25);
  assertEquals(corrected?.source_transactions.length, 2);
  assertEquals(
    f.tables.wellbeing_transactions.length,
    4,
    "Historical ledger remains untouched",
  );
  for (const read of f.reads.filter((r) => r.table !== "profiles")) {
    assertEquals(
      read.filters.some(([op, key, val]) =>
        op === "eq" && key === "user_id" && val === owner
      ),
      true,
    );
  }
});
Deno.test("sleep derives from actual owned measurements and UTC wake date, invalid stages excluded", async () => {
  const f = new Fixture();
  const base = {
    id: "sleep",
    user_id: owner,
    date: "2026-10-21",
    source: "healthkit",
    bedtime: "2026-10-21T23:00:00Z",
    wake_time: "2026-10-22T07:00:00Z",
    time_in_bed_minutes: 480,
    time_asleep_minutes: 420,
    deep_sleep_minutes: 70,
    rem_sleep_minutes: 70,
  };
  f.tables.sleep_entries = [base, { ...base, id: "other", user_id: other }, {
    ...base,
    id: "manual",
    source: "manual",
  }, {
    ...base,
    id: "bad",
    deep_sleep_minutes: 1000,
    wake_time: "2026-10-22T08:00:00Z",
  }];
  const records = await currentSourceTransactions(f, owner, "2026-10-22");
  assertEquals(records.length, 1);
  assertEquals(records[0].date, "2026-10-22");
  assertEquals(records[0].amount, 5);
  assertEquals(records[0].metadata?.source_ids, ["sleep"]);
});
Deno.test("pagination accounts for every owned source row without a silent cap", async () => {
  const f = new Fixture();
  f.tables.exercise_sessions = Array.from(
    { length: 501 },
    (_, i) => ({
      id: String(i),
      user_id: owner,
      completed_at: "2026-10-22T08:00:00Z",
    }),
  );
  const records = await currentSourceTransactions(f, owner, "2026-10-22");
  assertEquals(records[0].amount, 4008);
  assertEquals(records[0].metadata?.source_ids.length, 501);
  assertEquals(
    f.reads.filter((r) => r.table === "exercise_sessions").length,
    2,
  );
});
Deno.test("empty sources produce no score; source errors fail and retry recovers", async () => {
  const f = new Fixture();
  assertEquals(await calculateUserDebtScore(f, owner, "2026-10-22"), null);
  f.failedTable = "sleep_entries";
  await assertRejects(() => calculateUserDebtScore(f, owner, "2026-10-22"));
  f.failedTable = null;
  f.tables.wellbeing_transactions = [
    transaction("2026-10-22", "withdrawal", 2.5),
  ];
  assertEquals(
    (await calculateUserDebtScore(f, owner, "2026-10-22"))?.rolling_debt_14day,
    2.5,
  );
});
Deno.test("threshold uses positive debt velocity, unique history and no zero threshold reassurance", () => {
  const trend = calculateTrend([
    transaction("2026-10-17", "withdrawal", 10),
    transaction("2026-10-22", "withdrawal", 10),
  ], "2026-10-22");
  assertEquals(
    calculateThresholdStatus(20, trend, profile).days_until_crash,
    28,
  );
  const zero = calculateThresholdStatus(20, trend, {
    ...profile,
    personal_threshold: 0,
  });
  assertEquals(zero.threshold, null);
  assertEquals(zero.confidence, 0);
  const repeated = {
    ...profile,
    crash_history: {
      crashes: Array(5).fill({
        date: "2026-10-22",
        debt_at_crash: 20,
        mood_score: 2,
      }),
      last_updated: null,
    },
  };
  assertEquals(calculateThresholdStatus(20, trend, repeated).confidence, 0);
});
Deno.test("HTTP anonymous and cross-owner requests are rejected before any source read", async () => {
  assertEquals(
    (await handler(
      new Request("https://synthetic.invalid", { method: "POST" }),
    )).status,
    401,
  );
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = (() => {
    calls++;
    return Promise.resolve(
      new Response(
        JSON.stringify({
          id: owner,
          aud: "authenticated",
          role: "authenticated",
        }),
        { headers: { "Content-Type": "application/json" } },
      ),
    );
  }) as typeof fetch;
  try {
    const response = await handler(
      new Request("https://synthetic.invalid", {
        method: "POST",
        headers: {
          Authorization: "Bearer synthetic",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ user_id: other, date: "2026-10-22" }),
      }),
    );
    assertEquals(response.status, 403);
    assertEquals(calls, 1);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("HTTP owner response and persistence share one current snapshot; failed saves retry safely", async () => {
  const originalFetch = globalThis.fetch;
  let stored: Row | null = null;
  let failSave = false;
  let saves = 0;
  let scheduledInsertPreservedCurrent = false;
  let profileWrites = 0;
  const end = "2026-10-22";
  const tables: Record<string, Row[]> = {
    profiles: [{ id: owner, created_at: "2025-01-01T00:00:00Z" }],
    wellbeing_debt_profiles: [structuredClone(profile)],
    wellbeing_transactions: [
      transaction("2026-10-21", "withdrawal", 20),
      transaction(end, "deposit", 2),
    ],
  };
  globalThis.fetch =
    (async (input: Request | URL | string, init?: RequestInit) => {
      const req = new Request(input, init);
      const url = new URL(req.url);
      const json = (value: unknown, status = 200) =>
        new Response(JSON.stringify(value), {
          status,
          headers: { "Content-Type": "application/json" },
        });
      if (url.pathname.endsWith("/auth/v1/user")) {
        return json({ id: owner, aud: "authenticated", role: "authenticated" });
      }
      const table = url.pathname.split("/").at(-1)!;
      if (req.method === "POST" && table === "wellbeing_debt_scores") {
        saves++;
        if (failSave) return json({ message: "synthetic save failure" }, 500);
        const incoming = await req.json();
        if (
          req.headers.get("Prefer")?.includes("resolution=ignore-duplicates") &&
          stored
        ) {
          scheduledInsertPreservedCurrent = true;
        } else stored = incoming;
        return json(null, 201);
      }
      if (req.method === "PATCH" && table === "wellbeing_debt_profiles") {
        profileWrites++;
        Object.assign(tables.wellbeing_debt_profiles[0], await req.json());
        return json(null);
      }
      if (req.method === "PATCH" && table === "wellbeing_debt_scores") {
        if (failSave) {
          return json({ message: "synthetic invalidation failure" }, 500);
        }
        Object.assign(stored!, await req.json());
        return json(null);
      }
      assertEquals(req.method, "GET");
      const rows = (tables[table] ?? []).filter((row) =>
        [...url.searchParams.entries()].every(([key, filter]) => {
          if (["select", "order", "offset", "limit"].includes(key)) return true;
          const [op, ...parts] = filter.split(".");
          const value = parts.join(".");
          return op === "eq"
            ? row[key] === value
            : op === "gte"
            ? row[key] >= value
            : op === "lte"
            ? row[key] <= value
            : op === "lt"
            ? row[key] < value
            : true;
        })
      );
      return json(
        req.headers.get("Accept")?.includes("vnd.pgrst.object")
          ? rows[0] ?? null
          : rows,
      );
    }) as typeof fetch;
  const request = () =>
    new Request("https://synthetic.invalid", {
      method: "POST",
      headers: {
        Authorization: "Bearer synthetic",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ date: end }),
    });
  try {
    const response = await handler(request());
    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.score.rolling_debt_14day, 18);
    assertEquals(body.score.source_transactions.length, 2);
    assertEquals(stored!.rolling_debt_14day, 18);
    assertEquals("source_transactions" in stored!, false);
    assertEquals(stored!.trend.accounting_version, 2);
    assertEquals(stored!.trend.source_transactions.length, 2);
    const writesBeforeScheduled = profileWrites;
    Deno.env.set("CRON_SECRET", "synthetic-cron");
    const scheduled = await handler(
      new Request("https://synthetic.invalid", {
        headers: { "X-Cron-Secret": "synthetic-cron" },
      }),
    );
    assertEquals(scheduled.status, 200);
    assertEquals(scheduledInsertPreservedCurrent, true);
    assertEquals(profileWrites, writesBeforeScheduled);
    assertEquals(stored!.trend.accounting_version, 2);
    assertEquals(saves, 2);
    saves = 1; // Remaining assertions count owner-requested persistence attempts.
    Deno.env.delete("CRON_SECRET");
    assertEquals(
      stored!.trend.source_transactions.some((row: Row) =>
        "description" in row
      ),
      false,
    );
    failSave = true;
    assertEquals((await handler(request())).status, 500);
    failSave = false;
    assertEquals((await handler(request())).status, 200);
    assertEquals(saves, 3);
    assertEquals(tables.wellbeing_debt_profiles[0].crash_history.crashes, []);
    // Correct the triggering mood and preceding source, then remove it; threshold history must follow.
    tables.wellbeing_debt_profiles[0].crash_history.crashes = [
      { date: "2026-10-18", debt_at_crash: 30, mood_score: 2 },
      { date: "2026-10-19", debt_at_crash: 30, mood_score: 2 },
      { date: end, debt_at_crash: 100, mood_score: 2 },
    ];
    tables.moods = [{
      user_id: owner,
      created_at: `${end}T12:00:00Z`,
      local_date: end,
      mood_score: 2,
    }];
    tables.wellbeing_transactions[0].amount = 1;
    const corrected = await handler(request());
    assertEquals(corrected.status, 200);
    const correctedBody = await corrected.json();
    assertEquals(correctedBody.score.threshold_status.threshold, 6.8);
    assertEquals(
      tables.wellbeing_debt_profiles[0].crash_history.crashes.find((c: Row) =>
        c.date === end
      ).debt_at_crash,
      1,
    );
    tables.moods = [];
    assertEquals((await handler(request())).status, 200);
    assertEquals(
      tables.wellbeing_debt_profiles[0].crash_history.crashes.some((c: Row) =>
        c.date === end
      ),
      false,
    );
    // Deleting the final contributing source must durably invalidate the old saved calculation.
    tables.wellbeing_transactions = [];
    failSave = true;
    assertEquals((await handler(request())).status, 500);
    failSave = false;
    const empty = await handler(request());
    assertEquals(empty.status, 200);
    assertEquals((await empty.json()).score, null);
    assertEquals(stored!.trend.accounting_version, 0);
    assertEquals(stored!.trend.source_transactions, []);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
