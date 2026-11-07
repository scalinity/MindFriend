function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

Deno.test("partner invite handlers keep service authority and bind creation and acceptance to Auth", async () => {
  const previousFetch = globalThis.fetch;
  const previousServe = Object.getOwnPropertyDescriptor(Deno, "serve")!;
  const environment = {
    SUPABASE_URL: "http://127.0.0.1:59999",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service",
  };
  const previousEnvironment = Object.keys(environment).map((key) => Deno.env.get(key));
  const first = "f0200000-0000-4000-8000-000000000001";
  const second = "f0200000-0000-4000-8000-000000000002";
  const linkId = "f0230000-0000-4000-8000-000000000001";
  let currentUser = first;
  let handler: ((request: Request) => Promise<Response>) | undefined;
  let dataCalls = 0;
  let created = 0;
  let accepted = 0;
  let rpcFailure: string | undefined;
  let lookupFailure = false;
  const code = "aB2cD3eF";
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(code));
  const expectedHash = Array.from(new Uint8Array(digest), (n) => n.toString(16).padStart(2,"0")).join("");
  try {
    for (const [key, value] of Object.entries(environment)) Deno.env.set(key, value);
    Object.defineProperty(Deno, "serve", {
      configurable: true,
      value: (registered: typeof handler) => { handler = registered; },
    });
    globalThis.fetch = async (input, init) => {
      const request = new Request(input, init);
      const url = new URL(request.url);
      assert(url.origin === environment.SUPABASE_URL, "External request forbidden");
      if (url.pathname === "/auth/v1/user") {
        if (request.headers.get("Authorization") !== "Bearer synthetic-user") {
          return Response.json({ message: "Invalid JWT" }, { status: 401 });
        }
        return Response.json({ id: currentUser });
      }
      dataCalls++;
      assert(request.headers.get("Authorization") === "Bearer synthetic-service",
        "User JWT replaced service authority");
      if (url.pathname === "/rest/v1/rate_limit_tracker") {
        assert(url.searchParams.get("user_id") === `eq.${currentUser}` || request.method === "POST",
          "Rate lookup is not current account scoped");
        return Response.json([]);
      }
      if (url.pathname === "/rest/v1/partner_links") {
        if (request.method === "GET") {
          assert(url.searchParams.get("status") === "eq.active", "Unexpected direct invite-code lookup");
          return lookupFailure
            ? Response.json({ message: "Synthetic query failure" }, { status: 500 })
            : Response.json(null);
        }
        assert(request.method === "POST", "Acceptance bypassed atomic RPC");
        const body = await request.json();
        assert(body.user_id_1 === currentUser && body.created_by === currentUser && body.user_id_2 === null,
          "Creation trusted a supplied participant");
        assert(body.status === "pending" && /^[a-f0-9]{64}$/.test(body.invite_code_hash),
          "Creation omitted pending state or hashed code");
        created++;
        return Response.json({ id: linkId, ...body });
      }
      if (url.pathname === "/rest/v1/rpc/accept_partner_invite") {
        const body = await request.json();
        assert(Object.keys(body).sort().join(",") === "p_invite_code_hash,p_user_id", "Unexpected acceptance input");
        assert(body.p_user_id === currentUser && body.p_invite_code_hash === expectedHash,
          "Acceptance lost verified owner or case-sensitive code");
        accepted++;
        if (rpcFailure) return Response.json({ success: false, code: rpcFailure });
        return Response.json({ success: true, partner_id: currentUser === first ? second : first,
          partner_link: { id: linkId, user_id_1: first, user_id_2: second, activated_at: "2026-11-06T12:00:00Z" } });
      }
      assert(url.pathname === "/rest/v1/profiles" && request.method === "GET", "Unexpected data access");
      assert(url.searchParams.get("id") === `eq.${currentUser === first ? second : first}`,
        "Profile lookup used sorted position instead of the inviter");
      return Response.json({ display_name: "Synthetic partner" });
    };

    for (const endpoint of ["couples-partner-links", "couples-partner-links-accept"]) {
      handler = undefined;
      await import(`../functions/${endpoint}/index.ts`);
      assert(handler, "Missing handler");
      const accepting = endpoint.endsWith("accept");
      const invoke = async (authorization?: string, inviteCode = code) => {
        const response = await handler!(new Request(`http://localhost/${endpoint}`, {
          method: "POST", headers: authorization ? { Authorization: authorization } : {},
          body: JSON.stringify({ inviteCode, userId: currentUser === first ? second : first, status: "active" }),
        }));
        return { status: response.status, body: await response.json() };
      };
      for (const credential of [undefined, "Basic synthetic-user", "Bearer invalid"]) {
        const before = dataCalls;
        assert((await invoke(credential)).status === 401, "Invalid credential admitted");
        assert(dataCalls === before, "Unauthenticated data access");
      }
      for (const participant of [first,second]) {
        currentUser = participant;
        const response = await invoke("Bearer synthetic-user");
        assert(response.status === 200, "Legitimate operation failed");
        if (accepting) {
          assert(response.body.partnerId === (currentUser === first ? second : first),
            "Client response changed partner identity after sorting");
        } else {
          assert(/^[1-9A-HJ-NP-Za-km-z]{8}$/.test(response.body.inviteCode), "Generated code format changed");
        }
      }
      if (!accepting) {
        lookupFailure = true;
        const before = created;
        assert((await invoke("Bearer synthetic-user")).status === 500 && created === before,
          "Creation proceeded after active-partnership query failed");
        lookupFailure = false;
      } else {
        const before = accepted;
        assert((await invoke("Bearer synthetic-user","invalid")).status === 400 && accepted === before,
          "Malformed code reached RPC");
        for (const [failure,status] of Object.entries({ NOT_FOUND: 404, EXPIRED: 409,
          ALREADY_ACCEPTED: 409, ACTIVE_PARTNERSHIP: 409, SELF_INVITE: 400 })) {
          rpcFailure = failure;
          assert((await invoke("Bearer synthetic-user")).status === status, "Transaction denial lost its client contract");
        }
      }
    }
  } finally {
    globalThis.fetch = previousFetch;
    Object.defineProperty(Deno, "serve", previousServe);
    Object.keys(environment).forEach((key,index) => {
      const value = previousEnvironment[index];
      if (value === undefined) Deno.env.delete(key); else Deno.env.set(key,value);
    });
  }
});
