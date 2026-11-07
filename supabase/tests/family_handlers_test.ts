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

Deno.test("family invite routes use one recipient-bound transaction", async (t) => {
  const nativeFetch = globalThis.fetch;
  const nativeServe = Deno.serve;
  const names = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"];
  const previous = names.map((key) => Deno.env.get(key));
  Deno.env.set(names[0], "http://localhost:55321");
  Deno.env.set(names[1], "synthetic-service");
  const userId = "18200000-0000-4000-8000-000000000002";
  let handler!: (req: Request) => Promise<Response>;
  let rpcError: string | null = null;
  let rpcCalls: unknown[] = [];
  Deno.serve = ((callback: typeof handler) => {
    handler = callback;
    return { finished: Promise.resolve(), shutdown: () => Promise.resolve() };
  }) as unknown as typeof Deno.serve;
  globalThis.fetch = async (input, init) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    assert(url.hostname === "localhost", "Unexpected external request");
    if (url.pathname === "/auth/v1/user") {
      return Response.json({
        id: userId,
        email: "recipient@example.invalid",
        app_metadata: {},
        user_metadata: {},
      });
    }
    if (url.pathname === "/rest/v1/rpc/check_rate_limit") {
      return Response.json([{
        allowed: true,
        remaining: 9,
        reset_at: new Date(Date.now() + 60_000).toISOString(),
      }]);
    }
    if (url.pathname === "/rest/v1/rpc/join_family_atomic") {
      rpcCalls.push(JSON.parse(String(init?.body)));
      return rpcError
        ? Response.json({ code: rpcError, message: "Synthetic denial" }, {
          status: 400,
        })
        : Response.json({
          success: true,
          family_id: "family-id",
          family_name: "Family",
          member_id: "member-id",
          role: "child",
          circle_id: null,
        });
    }
    if (
      url.pathname === "/rest/v1/family_members" &&
      (!init?.method || init.method === "GET")
    ) return Response.json([]);
    throw new Error(`Unexpected split mutation ${url.pathname}`);
  };
  const request = (body: unknown) =>
    handler(
      new Request("http://localhost/family", {
        method: "POST",
        headers: {
          Authorization: "Bearer synthetic-user",
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      }),
    );
  try {
    await import("../functions/accept-family-invite/index.ts");
    await t.step(
      "paid invitation requires exact invitation and verified actor",
      async () => {
        rpcCalls = [];
        const response = await request({
          invite_code: "abcd5678",
          user_id: "attacker",
          role: "admin",
        });
        assert(response.status === 200, "Acceptance failed");
        const body = await response.json();
        assert(
          body.familyId === "family-id" && body.success === true,
          "Client response contract changed",
        );
        assert(
          JSON.stringify(rpcCalls) ===
            JSON.stringify([{
              p_user_id: userId,
              p_invite_code: "ABCD5678",
              p_require_invitation: true,
            }]),
          "Incorrect invitation transaction",
        );
      },
    );
    await t.step(
      "recipient denial returns forbidden without partial writes",
      async () => {
        rpcError = "42501";
        const response = await request({ invite_code: "ABCD5678" });
        assert(response.status === 403, "Recipient denial hidden");
        await response.text();
        rpcError = null;
      },
    );
    await import("../functions/join-family/index.ts");
    await t.step(
      "group route preserves date-only payload and never sends claimed role",
      async () => {
        rpcCalls = [];
        const response = await request({
          inviteCode: "abcd5678",
          nickname: " Name ",
          birthDate: "1990-01-01",
          role: "parent",
        });
        assert(response.status === 200, "Group join failed");
        const body = await response.json();
        assert(body.member.role === "child", "Authoritative role lost");
        assert(
          JSON.stringify(rpcCalls) ===
            JSON.stringify([{
              p_user_id: userId,
              p_invite_code: "ABCD5678",
              p_nickname: "Name",
              p_birth_date: "1990-01-01",
            }]),
          "Untrusted role or incorrect request",
        );
      },
    );
    await t.step("impossible date cannot reach transaction", async () => {
      rpcCalls = [];
      const response = await request({
        inviteCode: "ABCD5678",
        birthDate: "2015-02-30",
      });
      assert(
        response.status === 400 && rpcCalls.length === 0,
        "Impossible birth date accepted",
      );
      await response.text();
    });
    await t.step(
      "transaction failure does not become a successful join",
      async () => {
        rpcError = "XX000";
        const response = await request({ inviteCode: "ABCD5678" });
        assert(response.status === 500, "Transaction failure hidden");
        await response.text();
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
