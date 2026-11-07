// Execute the real handler and SDK against synthetic HTTP responses; no network access.
import { deepStrictEqual, ok, strictEqual } from "node:assert";

type Handler = (request: Request) => Promise<Response>;
let handler: Handler;
const originalServe = Deno.serve;
Deno.serve = ((fn: Handler) => {
  handler = fn;
  return {};
}) as typeof Deno.serve;
try {
  await import("../functions/generate-daily-briefing/index.ts");
} finally {
  Deno.serve = originalServe;
}

const USER = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const MARKER = "SYNTHETIC_PRIVATE_BRIEFING_CONTENT";
const originalFetch = globalThis.fetch;
const originalEnvGet = Deno.env.get;
const originalConsole = {
  log: console.log,
  info: console.info,
  warn: console.warn,
  error: console.error,
  debug: console.debug,
};

async function runFixture(failInsert: boolean) {
  const logs: unknown[][] = [];
  const calls: string[] = [];
  const json = (value: unknown, status = 200) =>
    new Response(JSON.stringify(value), {
      status,
      headers: { "Content-Type": "application/json" },
    });
  for (const level of Object.keys(originalConsole) as Array<keyof typeof originalConsole>) {
    console[level] = (...values: unknown[]) => logs.push(values);
  }
  Deno.env.get = (key: string) => ({
    SUPABASE_URL: "https://briefing.invalid",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-key",
  }[key]);
  globalThis.fetch = async (input, init) => {
    const req = new Request(input, init);
    const url = new URL(req.url);
    strictEqual(url.origin, "https://briefing.invalid");
    calls.push(`${req.method} ${url.pathname}`);
    switch (url.pathname) {
      case "/auth/v1/user":
        return json({ id: USER });
      case "/rest/v1/briefing_preferences":
        return json({ enabled: true, include_calendar: true });
      case "/rest/v1/profiles":
        return json({ display_name: `${MARKER} Name`, timezone: "America/New_York" });
      case "/rest/v1/mood_predictions":
        return json({ predicted_mood: 2, confidence: 0.9, factors: { primary_factor: MARKER } });
      case "/rest/v1/quests":
        return json({ id: "synthetic-quest", quest_templates: { title: `${MARKER} Quest`, description: MARKER } });
      case "/rest/v1/biometric_daily_summaries":
        return json({ sleep_duration_hours: 4.125 });
      case "/rest/v1/daily_briefings":
        if (req.method === "GET") return json(null);
        strictEqual(req.method, "POST");
        const body = await req.json();
        // Verify the fixture exercises the private-data path rather than skipping it.
        strictEqual(body.user_id, USER);
        strictEqual(body.predicted_mood, 2);
        ok(body.greeting.includes(MARKER));
        ok(body.calendar_events[0].title.includes(MARKER));
        ok(body.suggestion.includes("4.1"));
        return failInsert
          ? json({ code: "23514", message: MARKER, details: `${MARKER} details` }, 400)
          : json({ id: "synthetic-briefing", ...body });
      default:
        throw new Error(`Unexpected fixture request: ${url.pathname}`);
    }
  };
  try {
    const start = new Date(Date.now() + 3_600_000);
    const response = await handler(new Request("https://briefing.invalid/function", {
      method: "POST",
      headers: { Authorization: "Bearer synthetic-user-token", "Content-Type": "application/json" },
      body: JSON.stringify({
        local_date: "2026-11-06",
        timezone: "America/New_York",
        calendar_events: [{
          id: MARKER,
          title: `${MARKER} Appointment`,
          start_time: start.toISOString(),
          end_time: new Date(start.getTime() + 3_600_000).toISOString(),
          location: `${MARKER} Location`,
        }],
      }),
    }));
    await response.text();
    strictEqual(response.status, failInsert ? 500 : 200);
    ok(calls.includes("POST /rest/v1/daily_briefings"));
    deepStrictEqual(logs, [[failInsert ? "Daily briefing generation failed" : "Daily briefing generated"]]);
    const serialized = JSON.stringify(logs);
    for (const privateValue of [MARKER, USER, "synthetic-user-token", "4.125"]) {
      ok(!serialized.includes(privateValue));
    }
  } finally {
    globalThis.fetch = originalFetch;
    Deno.env.get = originalEnvGet;
    Object.assign(console, originalConsole);
  }
}

Deno.test("briefing success logs only its outcome while returning personalized data", () => runFixture(false));
Deno.test("briefing database failure never logs private error details", () => runFixture(true));
