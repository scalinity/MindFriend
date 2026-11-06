// Actual Edge handler with SDK HTTP intercepted; no network access or live account.
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
Deno.test("family removal authenticates the actor and delegates one atomic mutation", async (t) => {
  const nativeFetch = globalThis.fetch;
  const nativeServe = Deno.serve;
  const names = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"];
  const previous = names.map((key) => Deno.env.get(key));
  Deno.env.set(names[0], "http://localhost:55321");
  Deno.env.set(names[1], "synthetic-service");
  const userId = "18100000-0000-4000-8000-000000000001";
  const memberId = "18100000-0000-4000-8000-000000000022";
  let handler!: (req: Request) => Promise<Response>;
  let authAllowed = true;
  let rpcError: string | null = null;
  let calls: { path: string; body: unknown }[] = [];
  Deno.serve = ((callback: typeof handler) => {
    handler = callback;
    return { finished: Promise.resolve(), shutdown: () => Promise.resolve() };
  }) as unknown as typeof Deno.serve;
  globalThis.fetch = async (input, init) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    assert(url.hostname === "localhost", "Unexpected external request");
    const body = init?.body ? JSON.parse(String(init.body)) : undefined;
    calls.push({ path: url.pathname, body });
    if (url.pathname === "/auth/v1/user") {
      return authAllowed
        ? Response.json({
          id: userId,
          email: "owner@example.invalid",
          app_metadata: {},
          user_metadata: {},
        })
        : Response.json({ message: "Invalid token" }, { status: 401 });
    }
    if (url.pathname === "/rest/v1/rpc/remove_family_member_atomic") {
      return rpcError
        ? Response.json({ code: rpcError, message: "Synthetic denial" }, {
          status: 400,
        })
        : Response.json({ success: true });
    }
    throw new Error(`Unexpected request ${url.pathname}`);
  };
  const request = (body: unknown, token = "synthetic-user") =>
    handler(
      new Request("http://localhost/remove-family-member", {
        method: "POST",
        headers: token
          ? {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          }
          : {},
        body: JSON.stringify(body),
      }),
    );
  try {
    await import("../functions/remove-family-member/index.ts");
    await t.step("missing authentication performs no mutation", async () => {
      calls = [];
      const response = await request({ member_id: memberId }, "");
      assert(
        response.status === 401 && calls.length === 0,
        "Missing auth accepted",
      );
      await response.text();
    });
    await t.step("invalid token performs no mutation", async () => {
      calls = [];
      authAllowed = false;
      const response = await request({ member_id: memberId });
      assert(
        response.status === 401 && calls.length === 1,
        "Invalid token accepted",
      );
      await response.text();
      authAllowed = true;
    });
    await t.step("invalid member never reaches RPC", async () => {
      calls = [];
      const response = await request({ member_id: "bad" });
      assert(
        response.status === 400 && calls.length === 1,
        "Invalid member accepted",
      );
      await response.text();
    });
    await t.step(
      "actor comes from verified user, ignoring body impersonation",
      async () => {
        calls = [];
        const response = await request({
          member_id: memberId,
          p_actor_id: "attacker",
          actor_id: "attacker",
        });
        assert(response.status === 200, "Valid removal rejected");
        await response.text();
        assert(
          calls.length === 2 &&
            JSON.stringify(calls[1].body) ===
              JSON.stringify({ p_actor_id: userId, p_member_id: memberId }),
          "Incorrect mutation or actor",
        );
      },
    );
    await t.step(
      "authorization and transaction failures cannot report success",
      async () => {
        for (
          const [code, status] of [["42501", 403], ["22023", 400], [
            "XX000",
            500,
          ]] as const
        ) {
          rpcError = code;
          const response = await request({ member_id: memberId });
          assert(response.status === status, "RPC error hidden");
          await response.text();
        }
      },
    );
  } finally {
    globalThis.fetch = nativeFetch;
    Deno.serve = nativeServe;
    names.forEach((name, index) =>
      previous[index] === undefined
        ? Deno.env.delete(name)
        : Deno.env.set(name, previous[index]!)
    );
  }
});
