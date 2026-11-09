// Actual handler and SDK, synthetic fetch only. No network permission or real account.
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

Deno.test("delete-account binds destructive work to the expected authenticated owner", async (t) => {
  const nativeFetch = globalThis.fetch;
  const nativeServe = Deno.serve;
  const nativeInterval = globalThis.setInterval;
  const intervals: ReturnType<typeof setInterval>[] = [];
  const keys = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"];
  const previous = keys.map((key) => Deno.env.get(key));
  const owner = "11111111-1111-4111-8111-111111111111";
  const other = "22222222-2222-4222-8222-222222222222";
  let handler!: (req: Request) => Promise<Response>;
  let mutations: string[] = [];
  const user = { id: owner, aud: "authenticated", created_at: "2026-11-06T12:00:00Z", app_metadata: {}, user_metadata: {} };
  try {
    Deno.env.set(keys[0], "http://localhost:55321");
    Deno.env.set(keys[1], "synthetic-service");
    globalThis.setInterval = ((...args: Parameters<typeof setInterval>) => {
      const id = nativeInterval(...args); intervals.push(id); return id;
    }) as typeof setInterval;
    globalThis.fetch = (input, options) => {
      const request = input instanceof Request ? input : new Request(input, options);
      const url = new URL(request.url);
      assert(url.host === "localhost:55321", "unexpected network target");
      if (url.pathname === "/auth/v1/user") return Promise.resolve(Response.json(user));
      if (request.method !== "GET") mutations.push(`${request.method} ${url.pathname}`);
      if (url.pathname.startsWith("/auth/v1/admin/users/")) return Promise.resolve(Response.json(user));
      if (request.method === "DELETE") return Promise.resolve(new Response(null, { status: 204 }));
      return Promise.resolve(Response.json([]));
    };
    Object.defineProperty(Deno, "serve", { configurable: true, value: (value: typeof handler) => { handler = value; } });
    await import("../functions/delete-account/index.ts");
    async function request(body: unknown) {
      mutations = [];
      return await handler(new Request("http://localhost:55321/functions/v1/delete-account", {
        method: "POST", headers: { Authorization: "Bearer synthetic-token", "Content-Type": "application/json" },
        body: JSON.stringify(body),
      }));
    }
    await t.step("changed account cannot run a single destructive call", async () => {
      const response = await request({ expected_owner: other });
      assert(response.status === 403, "owner mismatch must fail");
      assert(mutations.length === 0, "owner mismatch performed destructive work");
    });
    await t.step("malformed expected owner cannot become legacy omission", async () => {
      for (const expected_owner of [null, 42, [], {}]) {
        const response = await request({ expected_owner });
        assert(response.status === 403 && mutations.length === 0, "invalid identity must fail before writes");
      }
    });
    await t.step("matching owner reaches only the authenticated account deletion", async () => {
      const response = await request({ expected_owner: owner.toUpperCase() });
      assert(response.status === 200, "matching owner not accepted");
      assert(mutations.includes(`DELETE /auth/v1/admin/users/${owner}`), "canonical user not deleted");
      assert(!mutations.some((path) => path.includes(other)), "another owner was touched");
    });
    await t.step("legacy omitted field retains authenticated deletion", async () => {
      const response = await request({});
      assert(response.status === 200, "legacy request rejected");
      assert(mutations.includes(`DELETE /auth/v1/admin/users/${owner}`), "legacy deleted wrong owner");
    });
  } finally {
    globalThis.fetch = nativeFetch;
    Object.defineProperty(Deno, "serve", { configurable: true, value: nativeServe });
    globalThis.setInterval = nativeInterval;
    for (const id of intervals) clearInterval(id);
    keys.forEach((key, index) => previous[index] === undefined ? Deno.env.delete(key) : Deno.env.set(key, previous[index]!));
  }
});
