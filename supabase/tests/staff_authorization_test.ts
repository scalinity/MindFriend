function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

Deno.test("staff endpoints trust Auth application roles and reject editable claims", async () => {
  const previousFetch = globalThis.fetch;
  const previousServe = Object.getOwnPropertyDescriptor(Deno, "serve")!;
  const environment = {
    SUPABASE_URL: "http://127.0.0.1:59999",
    SUPABASE_ANON_KEY: "synthetic-anon",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service",
    STRIPE_SECRET_KEY: "synthetic-unused",
  };
  const previousEnvironment = Object.keys(environment).map((key) => Deno.env.get(key));
  let handler: ((request: Request) => Promise<Response>) | undefined;
  let databaseCalls = 0;
  let applicationRole: unknown;
  try {
    for (const [key, value] of Object.entries(environment)) Deno.env.set(key, value);
    Object.defineProperty(Deno, "serve", {
      configurable: true,
      value: (registered: typeof handler) => { handler = registered; },
    });
    globalThis.fetch = (input, init) => {
      const request = new Request(input, init);
      const url = new URL(request.url);
      assert(url.origin === environment.SUPABASE_URL, "External request forbidden");
      if (url.pathname === "/auth/v1/user") {
        if (request.headers.get("Authorization") !== "Bearer synthetic-user") {
          return Promise.resolve(Response.json({ message: "Invalid JWT" }, { status: 401 }));
        }
        return Promise.resolve(Response.json({
          id: "f0200000-0000-4000-8000-000000000001",
          app_metadata: { role: applicationRole },
          user_metadata: { role: "admin", is_admin: true },
        }));
      }
      databaseCalls++;
      assert(!url.pathname.endsWith("/profiles"), "Staff authorization queried user profile fields");
      assert(request.method === "GET", "Authorization fixture must not mutate data");
      return Promise.resolve(Response.json(null));
    };

    for (const endpoint of ["approve-content", "approve-reject-application", "process-payouts", "calculate-earnings"]) {
      handler = undefined;
      await import(`../functions/${endpoint}/index.ts`);
      assert(handler, `Missing ${endpoint} handler`);
      const invoke = async (authorization?: string) => {
        const response = await handler!(new Request(`http://localhost/${endpoint}`, {
          method: "POST",
          headers: authorization ? { Authorization: authorization } : {},
          body: JSON.stringify({ periodMonth: "invalid" }),
        }));
        await response.text();
        return response.status;
      };

      applicationRole = "admin";
      assert(await invoke() === 401, `${endpoint} accepted no credential`);
      assert(await invoke("Basic synthetic-user") === 401, `${endpoint} accepted a non-Bearer credential`);
      assert(await invoke("Bearer invalid") === 401, `${endpoint} accepted an invalid token`);
      for (const role of [undefined, "user", ["admin"], true]) {
        applicationRole = role;
        const before = databaseCalls;
        assert(await invoke("Bearer synthetic-user") === 403, `${endpoint} accepted editable or malformed authority`);
        assert(databaseCalls === before, `${endpoint} performed privileged work for denied user`);
      }

      applicationRole = "reviewer";
      assert(await invoke("Bearer synthetic-user") === (endpoint === "approve-content" ? 400 : 403),
        `${endpoint} reviewer scope changed`);
      applicationRole = "admin";
      assert(await invoke("Bearer synthetic-user") === 400,
        `${endpoint} rejected server-managed admin authority`);
    }
  } finally {
    globalThis.fetch = previousFetch;
    Object.defineProperty(Deno, "serve", previousServe);
    Object.keys(environment).forEach((key, index) => {
      const value = previousEnvironment[index];
      if (value === undefined) Deno.env.delete(key); else Deno.env.set(key, value);
    });
  }
});
