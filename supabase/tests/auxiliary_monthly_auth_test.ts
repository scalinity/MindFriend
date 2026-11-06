// Actual handler auth checks with only synthetic environment and mocked fetch.
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

Deno.test("auxiliary paid batches: anonymous and forged service JWTs never select DB or submit providers", async () => {
  const savedFetch = globalThis.fetch;
  const savedServe = Deno.serve;
  const env = {
    SUPABASE_URL: "http://127.0.0.1:59999",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-only",
    SUPABASE_ANON_KEY: "synthetic-anon-only",
    CRON_SECRET: "synthetic-cron-only",
    XAI_API_KEY: "synthetic-only",
  };
  const previous = Object.keys(env).map((key) => Deno.env.get(key));
  let handler: (req: Request) => Promise<Response> = () => {
    throw new Error("Missing handler");
  };
  let databaseCalls = 0;
  let providerCalls = 0;
  try {
    for (const [key, value] of Object.entries(env)) Deno.env.set(key, value);
    Object.defineProperty(Deno, "serve", {
      configurable: true,
      value: (registered: typeof handler) => {
        handler = registered;
      },
    });
    globalThis.fetch = ((input: RequestInfo | URL) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      if (url.origin !== env.SUPABASE_URL) {
        providerCalls++;
        throw new Error("Provider forbidden");
      }
      databaseCalls++;
      return Promise.resolve(Response.json([]));
    }) as typeof fetch;
    const forged = `${btoa('{"alg":"none"}')}.${
      btoa('{"role":"service_role"}')
    }.forged`;
    for (const endpoint of ["generate-sleep-audio", "deliver-capsules"]) {
      if (endpoint === "generate-sleep-audio") {
        await import("../functions/generate-sleep-audio/index.ts");
      } else await import("../functions/deliver-capsules/index.ts");
      const deniedHeaders: Record<string, string>[] = [{}, {
        Authorization: `Bearer ${forged}`,
      }, { Authorization: "Bearer wrong", "x-cron-secret": "wrong" }];
      for (const headers of deniedHeaders) {
        const before = databaseCalls;
        const response = await handler(
          new Request(`http://localhost/${endpoint}`, {
            method: "POST",
            headers: { ...headers, "Content-Type": "application/json" },
            body: JSON.stringify({ action: "generate" }),
          }),
        );
        assert(
          [401, 403].includes(response.status),
          "Unverified service caller was admitted",
        );
        await response.text();
        assert(
          databaseCalls === before && providerCalls === 0,
          "Denied service caller reached DB/provider",
        );
      }
      if (endpoint === "generate-sleep-audio") {
        const response = await handler(
          new Request("http://localhost/generate-sleep-audio", {
            method: "POST",
            headers: {
              Authorization: "Bearer wrong",
              "x-cron-secret": env.CRON_SECRET,
            },
            body: JSON.stringify({ action: "generate" }),
          }),
        );
        assert(
          response.status === 403,
          "Sleep auth unexpectedly accepted Cron instead of exact service key",
        );
        await response.text();
      }
      const response = await handler(
        new Request(`http://localhost/${endpoint}`, {
          method: "POST",
          headers: { Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}` },
          body: JSON.stringify({ action: "status" }),
        }),
      );
      assert(response.ok, "Existing exact service credential no longer works");
      await response.text();
      if (endpoint === "deliver-capsules") {
        const cron = await handler(
          new Request("http://localhost/deliver-capsules", {
            headers: { "x-cron-secret": env.CRON_SECRET },
          }),
        );
        assert(cron.ok, "Existing capsule Cron credential no longer works");
        await cron.text();
      }
    }
    assert(
      databaseCalls === 3 && providerCalls === 0,
      "Unexpected actual handler dispatches",
    );
  } finally {
    globalThis.fetch = savedFetch;
    Object.defineProperty(Deno, "serve", {
      configurable: true,
      value: savedServe,
    });
    Object.keys(env).forEach((key, i) =>
      previous[i] === undefined
        ? Deno.env.delete(key)
        : Deno.env.set(key, previous[i]!)
    );
  }
});
