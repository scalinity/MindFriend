import { assert, assertEquals } from "jsr:@std/assert@1.0.19";
import { handler } from "./index.ts";

const owner = "11111111-1111-4111-8111-111111111111";
const mentor = "22222222-2222-4222-8222-222222222222";
Deno.env.set("SUPABASE_URL", "https://mentorship-fixture.invalid");
Deno.env.set("SUPABASE_ANON_KEY", "synthetic-anon");
const json = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json" },
  });
const request = (body: unknown = {}, authorization = "Bearer synthetic-user") =>
  new Request("https://edge-fixture.invalid", {
    method: "POST",
    headers: { Authorization: authorization },
    body: JSON.stringify(body),
  });

Deno.test("discovery uses authenticated RPC signature and maps actual result columns", async () => {
  const original = globalThis.fetch;
  let rpcCalls = 0;
  globalThis.fetch = async (input, init) => {
    const req = new Request(input, init);
    const url = new URL(req.url);
    assertEquals(req.headers.get("Authorization"), "Bearer synthetic-user");
    if (url.pathname === "/auth/v1/user") return json({ id: owner });
    if (
      url.pathname === "/rest/v1/mentorship_profiles" &&
      url.searchParams.get("select") === "seeking_areas"
    ) {
      assertEquals(url.searchParams.get("user_id"), `eq.${owner}`);
      return json({ seeking_areas: ["stress"] });
    }
    if (url.pathname === "/rest/v1/rpc/find_mentor_matches") {
      rpcCalls++;
      assertEquals(await req.json(), {
        p_user_id: owner,
        p_seeking_areas: ["stress"],
        p_limit: 5,
      });
      return json([{
        mentor_user_id: mentor,
        profile_id: "unused-profile-id",
        expertise_areas: ["stress"],
        languages: ["en"],
        availability_hours_week: 2,
        compatibility_score: 87.5,
        match_reason: "Shared expertise",
      }]);
    }
    if (url.pathname === "/rest/v1/mentorship_profiles") {
      assertEquals(url.searchParams.get("select"), "user_id,timezone,verified");
      return json([{
        user_id: mentor,
        timezone: "America/New_York",
        verified: true,
      }]);
    }
    throw new Error(`Unexpected fixture request: ${url.pathname}`);
  };
  try {
    const response = await handler(request());
    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.matches[0].mentor_id, mentor);
    assertEquals(body.matches[0].match_reasons, ["Shared expertise"]);
    assertEquals(body.matches[0].compatibility_score, 87.5);
    assertEquals(body.matches[0].timezone, "America/New_York");
    assertEquals(body.matches[0].is_verified, true);
    assertEquals(body.count, 1);
    assertEquals(rpcCalls, 1);
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("discovery fails closed on unauthenticated, invalid pagination, profile and RPC errors", async () => {
  const original = globalThis.fetch;
  for (const failure of ["auth", "profile", "rpc", "pagination"]) {
    let rpcCalls = 0;
    globalThis.fetch = async (input, init) => {
      const path = new URL(new Request(input, init).url).pathname;
      if (path === "/auth/v1/user") {
        return failure === "auth"
          ? json({ message: "Invalid JWT" }, 401)
          : json({ id: owner });
      }
      if (path === "/rest/v1/mentorship_profiles") {
        return failure === "profile"
          ? json({ message: "Synthetic failure" }, 400)
          : json({ seeking_areas: ["stress"] });
      }
      if (path === "/rest/v1/rpc/find_mentor_matches") {
        rpcCalls++;
        return json({ message: "Synthetic failure" }, 400);
      }
      throw new Error("Unexpected request");
    };
    try {
      const response = await handler(
        request(failure === "pagination" ? { limit: 1.5 } : {}),
      );
      assertEquals(
        response.status,
        failure === "auth" ? 401 : failure === "pagination" ? 400 : 500,
      );
      assertEquals(rpcCalls, failure === "rpc" ? 1 : 0);
    } finally {
      globalThis.fetch = original;
    }
  }
  assertEquals((await handler(request({}, ""))).status, 401);
});

Deno.test("discovery paginates the bounded ten-candidate RPC without unsupported offset argument", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    const req = new Request(input, init);
    const url = new URL(req.url);
    if (url.pathname === "/auth/v1/user") return json({ id: owner });
    if (url.pathname.endsWith("/rpc/find_mentor_matches")) {
      const body = await req.json();
      assertEquals(body.p_limit, 10);
      assert(!("p_offset" in body));
      return json(
        Array.from(
          { length: 10 },
          (_, i) => ({
            mentor_user_id: mentor,
            expertise_areas: [],
            languages: ["en"],
            compatibility_score: 100 - i,
          }),
        ),
      );
    }
    if (url.searchParams.get("select") === "seeking_areas") {
      return json({ seeking_areas: [] });
    }
    return json([{ user_id: mentor, timezone: "UTC", verified: true }]);
  };
  try {
    const response = await handler(request({ offset: 5, limit: 5 }));
    const body = await response.json();
    assertEquals(body.count, 5);
    assertEquals(body.matches[0].compatibility_score, 95);
  } finally {
    globalThis.fetch = original;
  }
});
