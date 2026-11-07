import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

Deno.test("daily intervention limits use the owner's complete local calendar day", async (t) => {
  const originalServe = Deno.serve;
  try {
    Object.defineProperty(Deno, "serve", { configurable: true, value: () => {} });
    const { evaluateTriggers } = await import("./index.ts");
    const owner = "b3000000-0000-4000-8000-000000000001";
    const cases = [
      { name: "just after Eastern midnight", now: "2026-11-06T05:05:00Z", start: "2026-11-06T05:00:00.000Z", end: "2026-11-07T05:00:00.000Z", hours: 24 },
      { name: "Eastern evening after UTC midnight", now: "2026-11-07T04:59:00Z", start: "2026-11-06T05:00:00.000Z", end: "2026-11-07T05:00:00.000Z", hours: 24 },
      { name: "spring forward day", now: "2026-03-08T07:15:00Z", start: "2026-03-08T05:00:00.000Z", end: "2026-03-09T04:00:00.000Z", hours: 23 },
      { name: "fall back first repeated hour", now: "2026-11-01T05:30:00Z", start: "2026-11-01T04:00:00.000Z", end: "2026-11-02T05:00:00.000Z", hours: 25 },
      { name: "fall back second repeated hour", now: "2026-11-01T06:30:00Z", start: "2026-11-01T04:00:00.000Z", end: "2026-11-02T05:00:00.000Z", hours: 25 },
    ];
    for (const item of cases) {
      await t.step(item.name, async () => {
        const start = Date.parse(item.start), end = Date.parse(item.end);
        const deliveries = [start - 1, start, start + 60000, end - 1, end];
        let countRequests = 0, cooldownRequests = 0;
        const client = createClient("http://127.0.0.1:55321", "synthetic-anon", {
          auth: { persistSession: false, autoRefreshToken: false },
          global: { fetch: (async (input: RequestInfo | URL, init?: RequestInit) => {
            const request = new Request(input, init), url = new URL(request.url);
            assert(url.origin === "http://127.0.0.1:55321", "Unexpected external request");
            assert(url.pathname === "/rest/v1/intervention_deliveries", "Unexpected table");
            assert(url.searchParams.get("user_id") === `eq.${owner}`, "Owner filter missing");
            if (request.method === "HEAD") {
              countRequests++;
              const bounds = url.searchParams.getAll("delivered_at");
              assert(bounds.length === 2 && bounds.includes(`gte.${item.start}`) && bounds.includes(`lt.${item.end}`),
                `Incorrect half-open day: ${bounds.join(",")}`);
              assert((end - start) / 3600000 === item.hours, "Unexpected fixture day length");
              const counted = deliveries.filter((instant) => instant >= start && instant < end).length;
              assert(counted === 3, "Neighboring days leaked into daily count");
              return new Response(null, { headers: { "Content-Range": `*/${counted}` } });
            }
            cooldownRequests++;
            return Response.json({ dismissed_at: item.now });
          }) as typeof fetch },
        });
        const limited = await evaluateTriggers(client, owner, { max_daily: 3 }, "America/New_York", "Bearer synthetic", undefined, new Date(item.now));
        assert(limited.shouldTrigger === false && limited.suppressionReason === "daily_limit", "Local daily limit not enforced");
        assert(countRequests === 1 && cooldownRequests === 0, "Daily limit did not stop later work");
        const belowLimit = await evaluateTriggers(client, owner, { max_daily: 4 }, "America/New_York", "Bearer synthetic", undefined, new Date(item.now));
        assert(belowLimit.suppressionReason === "cooldown", "Below-limit day was incorrectly suppressed");
        assert(Number(countRequests) === 2 && Number(cooldownRequests) === 1, "Below-limit flow did not continue");
      });
    }
  } finally {
    Object.defineProperty(Deno, "serve", { configurable: true, value: originalServe });
  }
});
