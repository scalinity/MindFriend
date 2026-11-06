import { assert, assertEquals } from "jsr:@std/assert@1.0.19";
import { handler } from "./index.ts";

const owner = "11111111-1111-4111-8111-111111111111";
const mentor = "22222222-2222-4222-8222-222222222222";
const match = "33333333-3333-4333-8333-333333333333";
Deno.env.set("SUPABASE_URL", "https://mentorship-fixture.invalid");
Deno.env.set("SUPABASE_ANON_KEY", "synthetic-anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "synthetic-service");
const json = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json" },
  });
const request = (
  body: unknown = {
    mentor_id: mentor,
    introduction_message: "I would appreciate support with managing stress.",
  },
) =>
  new Request("https://edge-fixture.invalid", {
    method: "POST",
    headers: { Authorization: "Bearer synthetic-user" },
    body: JSON.stringify(body),
  });

Deno.test("request persists through caller RPC and returns confirmed match even when notification fails", async () => {
  const original = globalThis.fetch;
  const paths: string[] = [];
  globalThis.fetch = async (input, init) => {
    const req = new Request(input, init);
    const url = new URL(req.url);
    paths.push(url.pathname);
    if (url.pathname === "/functions/v1/send-notification") {
      assertEquals(
        req.headers.get("Authorization"),
        "Bearer synthetic-service",
      );
      return json({ error: "Synthetic notification outage" }, 400);
    }
    assertEquals(req.headers.get("Authorization"), "Bearer synthetic-user");
    if (url.pathname === "/auth/v1/user") return json({ id: owner });
    if (url.pathname === "/rest/v1/rpc/create_mentorship_request") {
      assertEquals(await req.json(), {
        p_mentor_id: mentor,
        p_introduction_message:
          "I would appreciate support with managing stress.",
      });
      return json(match);
    }
    if (url.pathname === "/rest/v1/mentorship_matches") {
      assertEquals(req.method, "GET");
      assertEquals(url.searchParams.get("id"), `eq.${match}`);
      return json({
        id: match,
        status: "pending",
        created_at: "2026-11-06T12:00:00Z",
      });
    }
    throw new Error("Unexpected fixture request");
  };
  try {
    const response = await handler(request());
    assertEquals(response.status, 201);
    assertEquals((await response.json()).match_id, match);
    assertEquals(paths.filter((path) => path.includes("rpc/")).length, 1);
    assert(paths.includes("/functions/v1/send-notification"));
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("request rejects invalid/self requests and preserves failed RPC outcomes", async () => {
  const original = globalThis.fetch;
  for (
    const scenario of ["invalid", "self", "duplicate", "unavailable", "unknown"]
  ) {
    let rpcCalls = 0;
    let notificationCalls = 0;
    globalThis.fetch = async (input, init) => {
      const path = new URL(new Request(input, init).url).pathname;
      if (path === "/auth/v1/user") return json({ id: owner });
      if (path.includes("rpc/")) {
        rpcCalls++;
        return json({
          message: scenario === "duplicate"
            ? "Match already exists"
            : scenario === "unavailable"
            ? "Mentor not available"
            : "Synthetic failure",
        }, 400);
      }
      if (path.includes("send-notification")) notificationCalls++;
      throw new Error("No follow-on requests may run after a failed create");
    };
    try {
      const body = {
        mentor_id: scenario === "self" ? owner.toUpperCase() : mentor,
        introduction_message: scenario === "invalid"
          ? "short"
          : "I would appreciate support with managing stress.",
      };
      assertEquals(
        (await handler(request(body))).status,
        scenario === "duplicate" ? 409 : scenario === "unknown" ? 500 : 400,
      );
      assertEquals(rpcCalls, ["self", "invalid"].includes(scenario) ? 0 : 1);
      assertEquals(notificationCalls, 0);
    } finally {
      globalThis.fetch = original;
    }
  }
});
