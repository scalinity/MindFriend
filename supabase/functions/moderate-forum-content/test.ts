import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.19";
import { handleModerateForumContent } from "./index.ts";

const AUTHOR = "11111111-1111-4111-8111-111111111111";
const CONTENT_ID = "22222222-2222-4222-8222-222222222222";
const OTHER = "33333333-3333-4333-8333-333333333333";

type Row = {
  id: string;
  author_id: string;
  title: string;
  content: string;
  updated_at: string;
  status: string;
  is_crisis?: boolean;
  moderation_confidence?: number;
};

type Scenario = {
  row?: Partial<Row>;
  request?: Record<string, unknown>;
  verdict?: unknown;
  providerStatus?: number;
  malformedProvider?: boolean;
  onModerate?: (row: Row) => void;
  token?: boolean;
};

// All requests use the real handler, auth helper, Supabase client, budget and
// provider adapter. Only the HTTP boundary is synthetic; no network is granted.
async function runScenario(scenario: Scenario = {}) {
  const originalFetch = globalThis.fetch;
  const environment = {
    SUPABASE_URL: "https://moderation.invalid",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-key",
    SUPABASE_ANON_KEY: "synthetic-anon-key",
    XAI_API_KEY: "synthetic-provider-key",
    AI_PROVIDER: "xai",
  };
  const previous = new Map(Object.keys(environment).map((key) => [key, Deno.env.get(key)]));
  for (const [key, value] of Object.entries(environment)) Deno.env.set(key, value);

  const row: Row = {
    id: CONTENT_ID, author_id: AUTHOR, title: "Stored title", content: "Stored body",
    updated_at: "2026-11-06T12:00:00.000001-05:00", status: "pending", ...scenario.row,
  };
  const prompts: string[] = [];
  const crisisEvents: Record<string, unknown>[] = [];
  const updates: URL[] = [];
  const unexpected: string[] = [];
  let budgetCalls = 0;
  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    if (url.hostname === "moderation.invalid" && url.pathname === "/auth/v1/user") {
      return Response.json({ id: AUTHOR });
    }
    if (url.hostname === "moderation.invalid" &&
        ["/rest/v1/forum_threads", "/rest/v1/forum_replies"].includes(url.pathname)) {
      const matches = () => [...url.searchParams].every(([field, filter]) =>
        field === "select" || filter === `eq.${row[field as keyof Row]}`
      );
      if (request.method === "GET") {
        return Response.json(matches() ? [{ ...row }] : []);
      }
      if (request.method === "PATCH") {
        updates.push(url);
        if (!matches()) return Response.json(null);
        Object.assign(row, await request.json());
        return Response.json({ id: CONTENT_ID });
      }
    }
    if (url.hostname === "moderation.invalid" && url.pathname === "/rest/v1/rpc/reserve_monthly_ai_budget") {
      budgetCalls++;
      const body = await request.json();
      return Response.json({
        allowed: true, reason: "reserved", request_id: body.p_request_id,
        user_id: body.p_user_id, feature: body.p_feature,
        reserve_microdollars: body.p_reserve_microdollars,
        month_start: "2026-11-01", reserved_microdollars: body.p_reserve_microdollars,
        limit_microdollars: 10_000_000, remaining_microdollars: 10_000_000 - body.p_reserve_microdollars,
      });
    }
    if (url.href === "https://api.x.ai/v1/chat/completions") {
      const body = await request.json();
      prompts.push(body.messages[1].content);
      scenario.onModerate?.(row);
      if (scenario.providerStatus) return new Response(null, { status: scenario.providerStatus });
      return Response.json({ choices: [{ message: { content: scenario.malformedProvider ? "not JSON" : JSON.stringify(
        scenario.verdict ?? { safe: true, confidence: 0.95, isCrisis: false },
      ) } }] });
    }
    if (url.hostname === "moderation.invalid" && url.pathname === "/rest/v1/crisis_events") {
      crisisEvents.push(await request.json());
      return new Response(null, { status: 201 });
    }
    unexpected.push(`${request.method} ${url.pathname}`);
    throw new Error("Unexpected request");
  };
  try {
    const response = await handleModerateForumContent(new Request("https://function.invalid", {
      method: "POST",
      headers: { "Content-Type": "application/json", ...(scenario.token === false ? {} : { Authorization: "Bearer synthetic-user-token" }) },
      body: JSON.stringify({ contentType: "thread", contentId: CONTENT_ID, ...scenario.request }),
    }));
    const body = await response.json();
    assertEquals(unexpected, []);
    return { response, body, row, prompts, updates, crisisEvents, budgetCalls };
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of previous) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}

Deno.test("moderation persists the safe verdict only when confidence is decisive", async () => {
  for (const [safe, confidence, status] of [
    [true, 0.95, "approved"], [false, 0.95, "rejected"],
    [true, 0.8, "approved"], [false, 0.8, "rejected"],
    [true, 0.5, "pending"], [false, 0.5, "pending"],
    [true, 0.2, "pending"], [false, 0.2, "pending"],
  ] as const) {
    const result = await runScenario({ verdict: { safe, confidence, isCrisis: false } });
    assertEquals(result.response.status, 200);
    assertEquals(result.row.status, status);
    assertEquals(result.body.status, status);
    assertEquals(result.row.moderation_confidence, confidence);
    assertEquals(result.budgetCalls, 1);
  }
});

Deno.test("crisis tagging and events never override an unsafe verdict", async () => {
  const result = await runScenario({
    row: { content: "I want to die. Synthetic harassment follows." },
    verdict: { safe: false, confidence: 0.95, isCrisis: false, reason: "Harassment" },
  });
  assertEquals(result.response.status, 200);
  assertEquals(result.row.status, "rejected");
  assertEquals(result.row.is_crisis, true);
  assertEquals(result.body.isCrisis, true);
  assertEquals(result.crisisEvents, [{ user_id: AUTHOR, notes: `Forum thread ${CONTENT_ID}: crisis language detected` }]);
});

Deno.test("safe crisis support remains publishable and title keywords are screened", async () => {
  const result = await runScenario({ row: { title: "Having suicidal thoughts" } });
  assertEquals(result.row.status, "approved");
  assertEquals(result.body.isCrisis, true);
  assertStringIncludes(result.prompts[0], "Having suicidal thoughts");
});

Deno.test("caller text cannot substitute for the authoritative stored title or body", async () => {
  const result = await runScenario({
    row: { title: "Stored title violation", content: "Stored body violation" },
    request: { title: "Forged harmless title", content: "Forged harmless text" },
    verdict: { safe: false, confidence: 0.99, isCrisis: false },
  });
  assertEquals(result.row.status, "rejected");
  assertStringIncludes(result.prompts[0], "Stored title violation");
  assertStringIncludes(result.prompts[0], "Stored body violation");
  assertEquals(result.prompts[0].includes("Forged harmless"), false);
});

Deno.test("another author's content is neither screened nor changed", async () => {
  const result = await runScenario({ row: { author_id: OTHER }, request: { content: "harmless" } });
  assertEquals(result.response.status, 404);
  assertEquals(result.row.status, "pending");
  assertEquals(result.prompts, []);
  assertEquals(result.updates, []);
  assertEquals(result.crisisEvents, []);
});

Deno.test("unsupported type, missing auth and already reviewed content cause no paid work", async () => {
  for (const [scenario, status] of [
    [{ request: { contentType: "arbitrary" } }, 400],
    [{ request: { contentId: 123 } }, 400],
    [{ token: false }, 401],
    [{ row: { status: "rejected" } }, 409],
    [{ row: { status: "flagged" } }, 409],
  ] as [Scenario, number][]) {
    const result = await runScenario(scenario);
    assertEquals(result.response.status, status);
    assertEquals(result.prompts, []);
    assertEquals(result.budgetCalls, 0);
    assertEquals(result.updates, []);
  }
});

Deno.test("the complete accepted body reaches moderation including the last character", async () => {
  for (const content of ["a".repeat(9979) + " PROHIBITED_END_TEXT!", "🙂".repeat(9979) + " PROHIBITED_END_TEXT!"]) {
    const result = await runScenario({ row: { content }, verdict: { safe: false, confidence: 0.99, isCrisis: false } });
    assertEquals([...content].length, 10000);
    assertEquals(result.response.status, 200);
    assertStringIncludes(result.prompts[0], content);
    assertEquals(result.row.status, "rejected");
  }
});

Deno.test("oversized stored content stays pending without partial screening", async () => {
  const result = await runScenario({ row: { content: "a".repeat(10001) } });
  assertEquals(result.response.status, 422);
  assertEquals(result.prompts, []);
  assertEquals(result.row.status, "pending");
});

Deno.test("edits during moderation invalidate the decision and suppress crisis side effects", async () => {
  const result = await runScenario({
    row: { content: "I want to die" },
    onModerate: (row) => { row.content = "New unscreened body"; row.updated_at = "2026-11-06T12:00:01.000001-05:00"; },
  });
  assertEquals(result.response.status, 409);
  assertEquals(result.row.status, "pending");
  assertEquals(result.crisisEvents, []);
  assertEquals(result.updates[0].searchParams.get("author_id"), `eq.${AUTHOR}`);
  assertEquals(result.updates[0].searchParams.get("updated_at"), "eq.2026-11-06T12:00:00.000001-05:00");
  assertEquals(result.updates[0].searchParams.get("status"), "eq.pending");
});

Deno.test("reply moderation uses the reply row and never a caller title", async () => {
  const result = await runScenario({ request: { contentType: "reply", title: "Forged title" } });
  assertEquals(result.response.status, 200);
  assertEquals(result.updates[0].pathname, "/rest/v1/forum_replies");
  assertEquals(result.prompts[0].includes("Stored title"), false);
  assertEquals(result.prompts[0].includes("Forged title"), false);
});

Deno.test("provider failures and malformed verdicts leave the full row pending", async () => {
  for (const scenario of [
    { providerStatus: 429 }, { providerStatus: 500 }, { malformedProvider: true },
    { verdict: { safe: true, confidence: 1.5, isCrisis: false } },
    { verdict: { safe: true, confidence: 0.95 } },
  ]) {
    const result = await runScenario(scenario);
    assertEquals(result.response.status, 200);
    assertEquals(result.row.status, "pending");
  }
});
