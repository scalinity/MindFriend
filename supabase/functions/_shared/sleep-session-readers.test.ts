import { assertEquals } from "jsr:@std/assert@1.0.19";
Deno.env.set("SUPABASE_URL", "https://sleep-readers.invalid");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "synthetic-offline");
const handlers: Array<(request: Request) => Promise<Response>> = [];
const serve = Deno.serve;
Deno.serve = ((handler: typeof handlers[number]) => { handlers.push(handler); return {}; }) as typeof Deno.serve;
await import("../analyze-sleep-patterns/index.ts");
await import("../generate-wind-down/index.ts");
Deno.serve = serve;
const owner = "11111111-1111-4111-8111-111111111111";
const full = { id: "full", user_id: owner, date: "2026-10-25", source: "healthkit",
  bedtime: "2026-10-24T14:00:00Z", wake_time: "2026-10-25T09:00:00Z",
  time_in_bed_minutes: 1140, time_asleep_minutes: 1080, deep_sleep_minutes: 200,
  rem_sleep_minutes: 200, sleep_score: 90 };
const fragments = [full, { ...full, id: "early", wake_time: "2026-10-25T04:00:00Z", sleep_score: 10 },
  { ...full, id: "late", bedtime: "2026-10-25T04:00:00Z", sleep_score: 10 }];
function request() { return new Request("https://sleep-readers.invalid", { method: "POST",
  headers: { Authorization: "Bearer synthetic", "Content-Type": "application/json" },
  body: JSON.stringify({ availableMinutes: 10, preferences: ["breathing"] }) }); }
Deno.test("sleep readers reject anonymous requests without source reads", async () => {
  for (const handler of handlers) assertEquals((await handler(new Request("https://sleep-readers.invalid"))).status, 401);
});
Deno.test("analysis counts complete nights and wind-down ignores superseded poor fragments", async () => {
  const fetch = globalThis.fetch;
  let writes = 0;
  globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
    const req = new Request(input, init); const url = new URL(req.url);
    const json = (value: unknown) => new Response(JSON.stringify(value), { headers: { "Content-Type": "application/json" } });
    if (url.pathname.endsWith("/auth/v1/user")) return json({ id: owner, aud: "authenticated", role: "authenticated" });
    const table = url.pathname.split("/").at(-1);
    if (table === "sleep_entries") { assertEquals(url.searchParams.get("user_id"), `eq.${owner}`); return json(fragments); }
    if (table === "wind_down_sessions" && req.method === "POST") {
      const row = await req.json(); assertEquals(row.user_id, owner); writes++; return json({ id: "synthetic-session", ...row });
    }
    assertEquals(["exercise_sessions", "exercises"].includes(table!), true); return json([]);
  }) as typeof fetch;
  try {
    const analysis = await handlers[0](request()); assertEquals(analysis.status, 400);
    assertEquals((await analysis.json()).currentDays, 1);
    const windDown = await handlers[1](request()); assertEquals(windDown.status, 200);
    const body = await windDown.json(); assertEquals(writes, 1);
    assertEquals(body.tips.some((tip: string) => tip.includes("below optimal")), false);
  } finally { globalThis.fetch = fetch; }
});
