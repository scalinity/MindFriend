// Actual recovered handlers against synthetic local accounts only. External net denied.
const statusPath = Deno.env.get("MINDFRIEND_LOCAL_STATUS");
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
Deno.test({
  name:
    "recovered biofeedback handlers preserve ownership and nullable-pattern history",
  ignore: !statusPath,
  fn: async () => {
    const cfg = JSON.parse(await Deno.readTextFile(statusPath!));
    const base = cfg.API_URL;
    assert(base === "http://127.0.0.1:55321", "Owned local stack required");
    const originalFetch = globalThis.fetch, originalServe = Deno.serve;
    const env = {
      SUPABASE_URL: base,
      SUPABASE_ANON_KEY: cfg.ANON_KEY,
      SUPABASE_SERVICE_ROLE_KEY: cfg.SERVICE_ROLE_KEY,
    };
    const previous = Object.keys(env).map((name) => Deno.env.get(name));
    const handlers: Record<string, (req: Request) => Promise<Response>> = {};
    let importing = "";
    async function api(
      path: string,
      body?: unknown,
      token = cfg.SERVICE_ROLE_KEY,
    ) {
      const response = await originalFetch(base + path, {
        method: body ? "POST" : "GET",
        headers: {
          apikey: cfg.ANON_KEY,
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: body ? JSON.stringify(body) : undefined,
      });
      const text = await response.text();
      assert(response.ok, `Local setup/query failed: ${response.status}`);
      return text ? JSON.parse(text) : null;
    }
    try {
      for (const [key, value] of Object.entries(env)) Deno.env.set(key, value);
      Object.defineProperty(Deno, "serve", {
        configurable: true,
        value: (handler: (req: Request) => Promise<Response>) => {
          handlers[importing] = handler;
        },
      });
      globalThis.fetch =
        ((input: string | URL | Request, init?: RequestInit) => {
          assert(
            new URL(input instanceof Request ? input.url : String(input))
              .origin === base,
            "External traffic denied",
          );
          return originalFetch(input, init);
        }) as typeof fetch;
      for (
        const name of [
          "save-session",
          "get-session-history",
          "get-patterns",
          "get-ui-preferences",
          "update-ui-preferences",
        ]
      ) {
        importing = name;
        const loaders: Record<string, () => Promise<unknown>> = {
          "save-session": () => import("../functions/save-session/index.ts"),
          "get-session-history": () =>
            import("../functions/get-session-history/index.ts"),
          "get-patterns": () => import("../functions/get-patterns/index.ts"),
          "get-ui-preferences": () =>
            import("../functions/get-ui-preferences/index.ts"),
          "update-ui-preferences": () =>
            import("../functions/update-ui-preferences/index.ts"),
        };
        await loaders[name]();
        const response = await handlers[name](
          new Request(`http://localhost/${name}`, {
            method: name.startsWith("get-") ? "GET" : "POST",
            headers: { "Content-Type": "application/json" },
            body: name.startsWith("get-") ? undefined : "{}",
          }),
        );
        assert(response.status === 401, `Anonymous ${name} was allowed`);
        await response.text();
      }
      const users: { access_token: string; user: { id: string } }[] = [];
      const password = crypto.randomUUID();
      for (let i = 0; i < 2; i++) {
        const email =
          `restoration-recovered-${crypto.randomUUID()}@example.invalid`;
        await api("/auth/v1/admin/users", {
          email,
          password,
          email_confirm: true,
        });
        users.push(
          await api(
            "/auth/v1/token?grant_type=password",
            { email, password },
            cfg.ANON_KEY,
          ),
        );
      }
      const [a, b] = users;
      const body = {
        sessionType: "manual",
        startedAt: new Date().toISOString(),
        durationSeconds: 60,
        baselineRate: 16,
        endingRate: 12,
        lowestRate: 10,
        breathCount: 12,
        calmingDetected: true,
        qualityScore: 0.8,
        metrics: {},
      };
      async function save(token: string, extra = {}) {
        return handlers["save-session"](
          new Request("http://localhost/save-session", {
            method: "POST",
            headers: {
              Authorization: `Bearer ${token}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ ...body, ...extra }),
          }),
        );
      }
      let response = await save(a.access_token);
      const saved = await response.json();
      assert(response.ok && saved.sessionId, "Owner session save failed");
      response = await save(b.access_token, { sessionId: saved.sessionId });
      assert(!response.ok, "Cross-user upsert transferred an existing session");
      await response.text();
      const records = await api(
        `/rest/v1/biofeedback_sessions?id=eq.${saved.sessionId}&select=user_id`,
      );
      assert(
        records.length === 1 && records[0].user_id === a.user.id,
        "Session owner changed",
      );
      async function history(token: string, query = "?limit=1&offset=0") {
        return handlers["get-session-history"](
          new Request("http://localhost/get-session-history" + query, {
            headers: { Authorization: `Bearer ${token}` },
          }),
        );
      }
      response = await history(a.access_token);
      const own = await response.json();
      assert(
        response.ok && own.sessions.length === 1 &&
          own.sessions[0].id === saved.sessionId &&
          own.sessions[0].patternName === null && own.total === 1,
        "Nullable-pattern history contract failed",
      );
      response = await history(b.access_token);
      assert(
        response.ok && (await response.json()).sessions.length === 0,
        "Cross-user history leaked",
      );
      response = await history(a.access_token, "?limit=100000&offset=-1");
      assert(response.status === 400, "Unbounded pagination accepted");
      await response.text();
      response = await handlers["get-patterns"](
        new Request("http://localhost/get-patterns", {
          headers: { Authorization: `Bearer ${a.access_token}` },
        }),
      );
      assert(
        response.ok && Array.isArray((await response.json()).patterns),
        "Pattern catalog query failed",
      );
    } finally {
      globalThis.fetch = originalFetch;
      Object.defineProperty(Deno, "serve", {
        configurable: true,
        value: originalServe,
      });
      for (const [i, key] of Object.keys(env).entries()) {
        if (previous[i] === undefined) Deno.env.delete(key);
        else Deno.env.set(key, previous[i]!);
      }
    }
  },
});
