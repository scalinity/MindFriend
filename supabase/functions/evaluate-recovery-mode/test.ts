// Exercises the actual handler and RPC adapter with synthetic credentials and intercepted HTTP.
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

Deno.test("recovery handler enforces caller scope and reads the SQL transition object", async () => {
  const env = {
    SUPABASE_URL: "http://127.0.0.1:55321",
    SUPABASE_ANON_KEY: "recovery-synthetic-anon",
    SUPABASE_SERVICE_ROLE_KEY: "recovery-synthetic-service",
    CRON_SECRET: "recovery-synthetic-cron",
  };
  const previousEnv = Object.keys(env).map((key) => Deno.env.get(key));
  const originalServe = Deno.serve;
  const originalFetch = globalThis.fetch;
  let handler: (request: Request) => Promise<Response> = () => {
    throw new Error("Handler was not registered");
  };
  const owner = "b1000000-0000-4000-8000-000000000001";
  const unchanged = "b1000000-0000-4000-8000-000000000002";
  const expired = "b1000000-0000-4000-8000-000000000003";
  const requests: Array<
    {
      path: string;
      authorization: string | null;
      body?: Record<string, unknown>;
    }
  > = [];
  let invalidRPC = false;
  try {
    for (const [key, value] of Object.entries(env)) Deno.env.set(key, value);
    Object.defineProperty(Deno, "serve", {
      configurable: true,
      value: (registered: typeof handler) => {
        handler = registered;
      },
    });
    globalThis.fetch =
      (async (input: RequestInfo | URL, init?: RequestInit) => {
        const request = new Request(input, init);
        const url = new URL(request.url);
        assert(url.origin === env.SUPABASE_URL, "Unexpected external request");
        const authorization = request.headers.get("Authorization");
        const body = request.method === "POST"
          ? await request.json()
          : undefined;
        requests.push({ path: url.pathname, authorization, body });
        if (url.pathname === "/auth/v1/user") {
          if (authorization !== "Bearer valid-user") {
            return Response.json({ message: "invalid token" }, { status: 401 });
          }
          return Response.json({
            id: owner,
            aud: "authenticated",
            role: "authenticated",
            email: "fixture@example.invalid",
          });
        }
        if (url.pathname === "/rest/v1/moods") {
          // A full page followed by another user's record proves candidates are not capped at 1,000 rows.
          return Response.json(
            url.searchParams.get("offset") === "1000"
              ? [{ user_id: unchanged }]
              : Array.from({ length: 1000 }, () => ({ user_id: owner })),
          );
        }
        if (url.pathname === "/rest/v1/user_settings") {
          assert(
            url.searchParams.get("recovery_mode_active") === "eq.true",
            "Active recovery candidate filter missing",
          );
          return Response.json([{ user_id: expired }]);
        }
        if (url.pathname === "/rest/v1/rpc/evaluate_recovery_mode_for_user") {
          if (invalidRPC) return Response.json([{ action: "entered" }]);
          const id = body?.p_user_id;
          assert(
            [owner, unchanged, expired].includes(String(id)),
            "Unknown user selected",
          );
          return Response.json(
            id === expired
              ? {
                action: "exit",
                reason: "max_duration_7_days",
                previous_state: true,
                new_state: false,
              }
              : id === owner
              ? {
                action: "enter",
                reason: "auto_consecutive_low_mood",
                previous_state: false,
                new_state: true,
              }
              : {
                action: "none",
                reason: "still_recovering",
                previous_state: true,
                new_state: true,
              },
          );
        }
        throw new Error(`Unexpected fixture request: ${url.pathname}`);
      }) as typeof fetch;
    const { parseRecoveryEvaluation } = await import("./index.ts");

    const anonymous = await handler(
      new Request("http://localhost/recovery", { method: "POST", body: "{}" }),
    );
    assert(
      anonymous.status === 401 && requests.length === 0,
      "Missing header reached service work",
    );
    await anonymous.text();
    const forged = await handler(
      new Request("http://localhost/recovery", {
        method: "POST",
        headers: { Authorization: "Bearer forged-service-token" },
        body: "{}",
      }),
    );
    assert(
      forged.status === 401 &&
        requests.every((r) => r.path === "/auth/v1/user"),
      "Invalid JWT reached a workload",
    );
    await forged.text();
    requests.length = 0;

    const manual = await handler(
      new Request("http://localhost/recovery", {
        method: "POST",
        headers: { Authorization: "Bearer valid-user" },
        body: JSON.stringify({ userId: expired }),
      }),
    );
    const manualBody = await manual.json();
    assert(
      manual.ok && manualBody.processedUsers === 1 && manualBody.entered === 1,
      "Manual own evaluation failed",
    );
    const calls = requests.filter((r) =>
      r.path.endsWith("evaluate_recovery_mode_for_user")
    );
    assert(
      calls.length === 1 && calls[0].body?.p_user_id === owner &&
        calls[0].authorization === "Bearer valid-user",
      "Manual path did not retain the caller's RLS context",
    );
    assert(
      !requests.some((r) =>
        r.path.endsWith("moods") || r.path.endsWith("user_settings")
      ),
      "Manual request enumerated other accounts",
    );

    const scheduledHeaders: Record<string, string>[] = [{
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
    }, { "x-cron-secret": env.CRON_SECRET }];
    for (const headers of scheduledHeaders) {
      requests.length = 0;
      const response = await handler(
        new Request("http://localhost/recovery", {
          method: "POST",
          headers,
          body: "{}",
        }),
      );
      const result = await response.json();
      assert(
        response.ok && result.processedUsers === 3 && result.entered === 1 &&
          result.exited === 1 && result.unchanged === 1 && result.errors === 0,
        "Scheduled evaluation did not count the SQL states correctly",
      );
      assert(
        result.results.some((r: { userId: string; action: string }) =>
          r.userId === expired && r.action === "exit"
        ),
        "Expired active account without recent mood was omitted",
      );
    }
    for (
      const invalid of [null, [], [{ action: "enter" }], {
        action: "entered",
        reason: "x",
        previous_state: false,
        new_state: true,
      }, {
        action: "none",
        reason: "x",
        previous_state: "false",
        new_state: false,
      }]
    ) {
      let rejected = false;
      try {
        parseRecoveryEvaluation(invalid, owner);
      } catch {
        rejected = true;
      }
      assert(rejected, "Malformed RPC contract was treated as a valid state");
    }
    invalidRPC = true;
    const invalid = await handler(
      new Request("http://localhost/recovery", {
        method: "POST",
        headers: { Authorization: "Bearer valid-user" },
        body: "{}",
      }),
    );
    assert(
      invalid.status === 500,
      "Invalid RPC data was reported as a successful unchanged evaluation",
    );
    await invalid.text();
  } finally {
    globalThis.fetch = originalFetch;
    Object.defineProperty(Deno, "serve", {
      configurable: true,
      value: originalServe,
    });
    Object.keys(env).forEach((key, i) =>
      previousEnv[i] === undefined
        ? Deno.env.delete(key)
        : Deno.env.set(key, previousEnv[i]!)
    );
  }
});
