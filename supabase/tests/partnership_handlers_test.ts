function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

Deno.test("partnership handlers preserve each participant's consent and service authority", async () => {
  const previousFetch = globalThis.fetch;
  const previousServe = Object.getOwnPropertyDescriptor(Deno, "serve")!;
  const environment = {
    SUPABASE_URL: "http://127.0.0.1:59999",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service",
  };
  const previousEnvironment = Object.keys(environment).map((key) => Deno.env.get(key));
  const first = "f0200000-0000-4000-8000-000000000001";
  const second = "f0200000-0000-4000-8000-000000000002";
  const outsider = "f0200000-0000-4000-8000-000000000003";
  const linkId = "f0210000-0000-4000-8000-000000000001";
  let currentUser = first;
  let handler: ((request: Request) => Promise<Response>) | undefined;
  let writes: Record<string, unknown>[] = [];
  let reads = 0;
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
      assert(url.pathname === "/rest/v1/partner_links", "Unexpected data access");
      assert(request.headers.get("Authorization") === "Bearer synthetic-service",
        "User JWT replaced service authorization");
      assert(url.searchParams.get("id") === `eq.${linkId}`, "Missing exact link filter");
      const link = {
        id: linkId, user_id_1: first, user_id_2: second, status: "active",
        user_1_share_mood: false, user_1_share_exercises: false,
        user_2_share_mood: false, user_2_share_exercises: false,
      };
      if (request.method === "GET") {
        reads++;
        return Response.json(link);
      }
      assert(request.method === "PATCH", "Unexpected mutation");
      assert(url.searchParams.get(currentUser === first ? "user_id_1" : "user_id_2") === `eq.${currentUser}`,
        "Missing mutation-time participant filter");
      const values = await request.json();
      writes.push(values);
      return Response.json({ ...link, ...values });
    };

    for (const endpoint of ["couples-partner-links-settings", "couples-partner-links-delete"]) {
      handler = undefined;
      await import(`../functions/${endpoint}/index.ts`);
      assert(handler, "Handler not registered");
      const settings = endpoint.endsWith("settings");
      const invoke = async (authorization?: string) => {
        const response = await handler!(new Request(
          `http://localhost/${endpoint}/${linkId}${settings ? "/settings" : ""}`, {
            method: settings ? "PATCH" : "DELETE",
            headers: authorization ? { Authorization: authorization } : {},
            body: settings ? JSON.stringify({
              shareMood: true, shareExercises: true,
              user_2_share_mood: true, user_id_2: outsider, status: "ended",
            }) : undefined,
          },
        ));
        await response.text();
        return response.status;
      };
      for (const credential of [undefined, "Basic synthetic-user", "Bearer invalid"]) {
        const beforeReads = reads;
        assert(await invoke(credential) === 401, "Unauthenticated mutation admitted");
        assert(reads === beforeReads, "Unauthenticated database access");
      }
      writes = [];
      currentUser = outsider;
      assert(await invoke("Bearer synthetic-user") === 403, "Outsider mutation admitted");
      assert(writes.length === 0, "Outsider wrote partnership");
      for (const participant of [first, second]) {
        currentUser = participant;
        writes = [];
        assert(await invoke("Bearer synthetic-user") === (settings ? 200 : 204),
          "Legitimate participant operation failed");
        assert(writes.length === 1, "Expected exactly one mutation");
        const keys = Object.keys(writes[0]).sort().join(",");
        const position = participant === first ? "1" : "2";
        assert(keys === (settings
          ? `user_${position}_share_exercises,user_${position}_share_mood`
          : "ended_at,status"), "Request modified another participant or protected fields");
      }
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
