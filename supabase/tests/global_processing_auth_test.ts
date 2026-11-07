// Actual scheduled handlers; synthetic credentials and empty HTTP fixtures only.
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
Deno.test("global processors reject ordinary users and preserve exact service/cron callers", async () => {
  const slugs = [
    "aggregate-weekly-stats",
    "aggregate-monthly-stats",
    "aggregate-yearly-stats",
    "detect-patterns",
    "calculate-wellness-score",
    "aggregate-interaction-metrics",
    "calculate-social-vitality",
    "detect-withdrawal",
    "generate-family-alerts",
    "lapsed-user-nudge",
    "send-monthly-report",
    "cleanup-deleted-capsule-media",
  ];
  const env = {
    SUPABASE_URL: "http://127.0.0.1:55321",
    SUPABASE_ANON_KEY: "synthetic-anon",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-global-service",
    CRON_SECRET: "synthetic-global-cron",
  };
  const savedEnv = Object.keys(env).map((key) => Deno.env.get(key));
  const savedServe = Deno.serve, savedFetch = globalThis.fetch;
  let handler: (request: Request) => Promise<Response> = () => {
    throw new Error("Handler missing");
  };
  let calls = 0;
  const forged = `${btoa('{"alg":"none"}')}.${
    btoa('{"role":"service_role"}')
  }.forged`;
  const denied: Record<string, string>[] = [
    {},
    { Authorization: "Bearer ordinary-user-jwt" },
    { Authorization: `Bearer ${forged}` },
    { "x-cron-secret": "wrong" },
  ];
  const allowed: Record<string, string>[] = [{
    Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
  }, { "x-cron-secret": env.CRON_SECRET }];
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
      assert(url.origin === env.SUPABASE_URL, "Unexpected external request");
      assert(
        url.pathname.startsWith("/rest/v1/"),
        "Unexpected privileged operation",
      );
      calls++;
      return Promise.resolve(Response.json([]));
    }) as typeof fetch;
    for (const slug of slugs) {
      handler = () => {
        throw new Error(`No handler for ${slug}`);
      };
      await import(`../functions/${slug}/index.ts`);
      for (const headers of denied) {
        const before = calls;
        const response = await handler(
          new Request(`http://localhost/${slug}`, {
            method: "POST",
            headers,
            body: "{}",
          }),
        );
        assert(
          response.status === 401,
          `${slug} admitted an unauthorized caller (${response.status})`,
        );
        await response.text();
        assert(calls === before, `${slug} performed work before authorization`);
      }
      for (const headers of allowed) {
        const before = calls;
        const response = await handler(
          new Request(`http://localhost/${slug}`, {
            method: "POST",
            headers,
            body: "{}",
          }),
        );
        assert(
          response.ok,
          `${slug} rejected the supported scheduler credential (${response.status})`,
        );
        await response.text();
        assert(calls > before, `${slug} did not reach its existing workflow`);
      }
    }
  } finally {
    globalThis.fetch = savedFetch;
    Object.defineProperty(Deno, "serve", {
      configurable: true,
      value: savedServe,
    });
    Object.keys(env).forEach((key, i) =>
      savedEnv[i] === undefined
        ? Deno.env.delete(key)
        : Deno.env.set(key, savedEnv[i]!)
    );
  }
});
