import { assert, assertEquals } from "jsr:@std/assert@1.0.19";
import { analyzeMessageSafety, handler } from "./index.ts";

const secret = "synthetic-safety-secret";
Deno.env.set("SUPABASE_URL", "https://mentorship-fixture.invalid");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "synthetic-service-key");
Deno.env.set("MENTORSHIP_SAFETY_SECRET", secret);
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
const request = (
  body: unknown = {},
  authorization: string | null = `Bearer ${secret}`,
) =>
  new Request("https://edge-fixture.invalid", {
    method: "POST",
    headers: authorization ? { Authorization: authorization } : {},
    body: JSON.stringify(body),
  });
const messages = [
  {
    id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
    match_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    sender_id: "11111111-1111-4111-8111-111111111111",
    content: "I want to kill myself",
    created_at: "2026-11-06T12:00:00Z",
  },
  {
    id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2",
    match_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    sender_id: "11111111-1111-4111-8111-111111111111",
    content: "Please send cash",
    created_at: "2026-11-06T12:00:01Z",
  },
  {
    id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3",
    match_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    sender_id: "22222222-2222-4222-8222-222222222222",
    content: "The breathing exercises were helpful",
    created_at: "2026-11-06T12:00:02Z",
  },
];

Deno.test("safety checker rejects missing, incorrect and unconfigured secrets before privileged work", async () => {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = () => {
    calls++;
    throw new Error("No privileged request expected");
  };
  try {
    assertEquals((await handler(request({}, null))).status, 401);
    assertEquals((await handler(request({}, "Bearer wrong"))).status, 401);
    Deno.env.delete("MENTORSHIP_SAFETY_SECRET");
    assertEquals((await handler(request())).status, 503);
    assertEquals(calls, 0);
  } finally {
    globalThis.fetch = original;
    Deno.env.set("MENTORSHIP_SAFETY_SECRET", secret);
  }
});

Deno.test("safety checker validates bounded requests before accessing messages", async () => {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = () => {
    calls++;
    throw new Error("Invalid request reached database");
  };
  try {
    for (
      const body of [null, [], { batch_size: 0 }, { batch_size: 501 }, {
        batch_size: 1.5,
      }, { check_recent_only: "yes" }]
    ) {
      assertEquals((await handler(request(body))).status, 400);
    }
    assertEquals(
      (await handler(new Request("https://fixture.invalid", { method: "GET" })))
        .status,
      405,
    );
    assertEquals(calls, 0);
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("safety checker uses actual columns and persists crisis, boundary and safe checks", async () => {
  const original = globalThis.fetch;
  const saved: Record<string, unknown>[] = [];
  globalThis.fetch = async (input, init) => {
    const req = new Request(input, init);
    const url = new URL(req.url);
    assertEquals(
      req.headers.get("authorization"),
      "Bearer synthetic-service-key",
    );
    if (url.pathname === "/rest/v1/mentorship_messages") {
      assertEquals(req.method, "GET");
      assertEquals(url.searchParams.get("safety_checked_at"), "is.null");
      assertEquals(url.searchParams.get("order"), "created_at.asc,id.asc");
      assertEquals(url.searchParams.get("limit"), "3");
      assert(url.searchParams.get("created_at")?.startsWith("gte."));
      assert(
        !url.searchParams.has("flagged_at") &&
          !url.searchParams.has("is_flagged"),
      );
      return json(messages);
    }
    assertEquals(url.pathname, "/rest/v1/rpc/record_mentorship_safety_check");
    saved.push(await req.json());
    return json(true);
  };
  try {
    const response = await handler(request({ batch_size: 3 }));
    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.messages_checked, 3);
    assertEquals(body.messages_flagged, 2);
    assertEquals(body.critical_escalations, 1);
    assertEquals(saved.map((row) => row.p_severity), [
      "critical",
      "high",
      "low",
    ]);
    assertEquals(
      saved.map((row) => row.p_expected_content),
      messages.map((row) => row.content),
    );
    assertEquals(saved[2].p_reasons, []);
    assertEquals(body.flagged_details.length, 2);
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("failed database read or atomic persistence never returns successful safety results", async () => {
  const original = globalThis.fetch;
  try {
    for (const failure of ["read", "persist"]) {
      let writes = 0;
      globalThis.fetch = async (input, init) => {
        const url = new URL(new Request(input, init).url);
        if (url.pathname === "/rest/v1/mentorship_messages") {
          return failure === "read"
            ? json({ message: "Synthetic read failure" }, 400)
            : json([messages[0]]);
        }
        assertEquals(
          url.pathname,
          "/rest/v1/rpc/record_mentorship_safety_check",
        );
        writes++;
        return json({ message: "Synthetic persistence failure" }, 400);
      };
      const response = await handler(request());
      assertEquals(response.status, 500);
      assertEquals((await response.json()).success, undefined);
      assertEquals(writes, failure === "read" ? 0 : 1);
    }
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("stale or already checked messages are not counted and backlog mode omits the time filter", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    const url = new URL(new Request(input, init).url);
    if (url.pathname === "/rest/v1/mentorship_messages") {
      assert(!url.searchParams.has("created_at"));
      return json([messages[0]]);
    }
    assertEquals(url.pathname, "/rest/v1/rpc/record_mentorship_safety_check");
    return json(false);
  };
  try {
    const response = await handler(request({ check_recent_only: false }));
    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.messages_checked, 0);
    assertEquals(body.messages_flagged, 0);
    assertEquals(body.critical_escalations, 0);
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("production safety analysis detects the supported crisis, PII, boundary and spam patterns", () => {
  for (
    const message of [
      "I want to kill myself",
      "I think about killing myself",
      "I have been hurting myself",
      "I want to hurt myself",
    ]
  ) {
    assertEquals(analyzeMessageSafety(message).severity, "critical");
  }
  assertEquals(
    analyzeMessageSafety("Please send cash").boundary_violation,
    true,
  );
  assertEquals(
    analyzeMessageSafety("Verify your password").inappropriate_request,
    true,
  );
  assertEquals(
    analyzeMessageSafety("Email test@example.invalid").pii_exposure,
    true,
  );
  assertEquals(analyzeMessageSafety("a".repeat(30)).reasons.length, 1);
  assertEquals(analyzeMessageSafety(messages[2].content).reasons, []);
});
