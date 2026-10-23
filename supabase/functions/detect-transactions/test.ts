import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1.0.19";

Deno.env.set("SUPABASE_URL", "https://synthetic.invalid");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "synthetic-test-key");
let handler: (req: Request) => Promise<Response>;
const originalServe = Deno.serve;
Deno.serve = ((callback: typeof handler) => {
  handler = callback;
  return {};
}) as typeof Deno.serve;
const {
  detectUserTransactions,
  upsertTransactions,
  transactionDayBounds,
  lastCompleteTransactionDate,
} = await import("./index.ts");
Deno.serve = originalServe;

const owner = "11111111-1111-4111-8111-111111111111";
const other = "22222222-2222-4222-8222-222222222222";
type Row = Record<string, any>;

class Fixture {
  tables: Record<string, Row[]> = {
    profiles: [{
      id: owner,
      created_at: "2025-01-01T00:00:00Z",
      timezone: "America/New_York",
    }],
  };
  reads: string[] = [];
  written = new Map<string, Row>();
  from(table: string) {
    this.reads.push(table);
    const filters: ((row: Row) => boolean)[] = [];
    let single = false;
    const query: any = {
      select: () => query,
      eq: (key: string, value: unknown) => {
        filters.push((row) => row[key] === value);
        return query;
      },
      gte: (key: string, value: string) => {
        filters.push((row) => row[key] >= value);
        return query;
      },
      lt: (key: string, value: string) => {
        filters.push((row) => row[key] < value);
        return query;
      },
      order: () => query,
      single: () => {
        single = true;
        return query;
      },
      then: (resolve: (result: unknown) => unknown) => {
        const rows = (this.tables[table] ?? []).filter((row) =>
          filters.every((filter) => filter(row))
        );
        return Promise.resolve({
          data: single ? rows[0] ?? null : rows,
          error: null,
        }).then(resolve);
      },
      upsert: (rows: Row[], options: { onConflict: string }) => {
        assertEquals(options.onConflict, "user_id,date,source,category");
        const keys = rows.map((row) =>
          [row.user_id, row.date, row.source, row.category].join("|")
        );
        assertEquals(
          new Set(keys).size,
          keys.length,
          "A single upsert cannot contain duplicate conflict keys",
        );
        rows.forEach((row, i) => this.written.set(keys[i], row));
        return Promise.resolve({ error: null });
      },
    };
    return query;
  }
}

Deno.test("UTC ledger days retain boundaries across DST dates and fractional seconds", () => {
  assertEquals(transactionDayBounds("2026-03-08"), {
    start: "2026-03-08T00:00:00.000Z",
    end: "2026-03-09T00:00:00.000Z",
  });
  assertEquals(transactionDayBounds("2026-09-06"), {
    start: "2026-09-06T00:00:00.000Z",
    end: "2026-09-07T00:00:00.000Z",
  });
  assertThrows(() => transactionDayBounds("2026-02-30"));
});

Deno.test("absent circle activity never manufactures isolation", async () => {
  const fixture = new Fixture();
  const result = await detectUserTransactions(fixture, owner, "2026-10-22");
  assertEquals(result, []);
  assertEquals(fixture.reads.includes("circle_members"), false);
  assertEquals(fixture.reads.includes("wellbeing_transactions"), false);
});

Deno.test("source events retain the half-open UTC ledger day and exclude other accounts", async () => {
  const fixture = new Fixture();
  fixture.tables.exercise_sessions = [
    { id: "start", user_id: owner, completed_at: "2026-03-08T00:00:00.000Z" },
    { id: "last", user_id: owner, completed_at: "2026-03-08T23:59:59.999Z" },
    { id: "before", user_id: owner, completed_at: "2026-03-07T23:59:59.999Z" },
    { id: "next", user_id: owner, completed_at: "2026-03-09T00:00:00.000Z" },
    { id: "other", user_id: other, completed_at: "2026-03-08T00:00:00.000Z" },
  ];
  const result = await detectUserTransactions(fixture, owner, "2026-03-08");
  assertEquals(result.length, 1);
  assertEquals(result[0].amount, 16);
  assertEquals(result[0].metadata?.source_ids, ["start", "last"]);
});

Deno.test("moods aggregate to one conflict key and repeated detection is idempotent", async () => {
  const fixture = new Fixture();
  fixture.tables.moods = [1, 2, 3].map((n) => ({
    id: `mood-${n}`,
    user_id: owner,
    local_date: "2026-10-22",
    mood_score: n,
  }));
  for (let attempt = 0; attempt < 2; attempt++) {
    const result = await detectUserTransactions(fixture, owner, "2026-10-22");
    assertEquals(result.length, 1);
    assertEquals(result[0].amount, 4);
    assertEquals(result[0].metadata?.source_ids, ["mood-1", "mood-2"]);
    await upsertTransactions(fixture, result);
  }
  assertEquals(fixture.written.size, 1);
  assertEquals(
    [...fixture.written.values()].reduce((sum, row) => sum + row.amount, 0),
    4,
  );
});

Deno.test("unknown profile and invalid date fail without writing", async () => {
  const fixture = new Fixture();
  fixture.tables.profiles = [];
  await assertRejects(() =>
    detectUserTransactions(fixture, owner, "2026-10-22")
  );
  assertEquals(fixture.written.size, 0);
});

Deno.test("actual handler denies anonymous and cross-owner requests before transaction queries", async () => {
  const anonymous = await handler!(
    new Request("https://synthetic.invalid", { method: "POST" }),
  );
  assertEquals(anonymous.status, 401);
  const originalFetch = globalThis.fetch;
  let authCalls = 0;
  globalThis.fetch = (() => {
    authCalls++;
    return Promise.resolve(
      new Response(JSON.stringify({ id: owner, aud: "authenticated" }), {
        headers: { "Content-Type": "application/json" },
      }),
    );
  }) as typeof fetch;
  try {
    const response = await handler!(
      new Request("https://synthetic.invalid", {
        method: "POST",
        headers: {
          Authorization: "Bearer synthetic-test-token",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ user_id: other, date: "2026-10-22" }),
      }),
    );
    assertEquals(response.status, 403);
    assertEquals(authCalls, 1);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("default date and re-detection retain existing UTC aggregate identity", async () => {
  assertEquals(
    lastCompleteTransactionDate(new Date("2026-11-02T06:00:00Z")),
    "2026-11-01",
  );
  const fixture = new Fixture();
  const existing = {
    user_id: owner,
    date: "2026-10-22",
    source: "exercise_sessions",
    category: "exercise_completion",
    amount: 8,
  };
  fixture.written.set(
    [owner, existing.date, existing.source, existing.category].join("|"),
    existing,
  );
  fixture.tables.exercise_sessions = [{
    id: "event",
    user_id: owner,
    completed_at: "2026-10-22T01:00:00.000Z",
  }];
  for (const day of ["2026-10-22", "2026-10-21", "2026-10-22"]) {
    await upsertTransactions(
      fixture,
      await detectUserTransactions(fixture, owner, day),
    );
  }
  assertEquals(fixture.written.size, 1);
  assertEquals(
    [...fixture.written.values()].reduce((sum, row) => sum + row.amount, 0),
    8,
  );
});
