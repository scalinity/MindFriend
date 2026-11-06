import { Webhook } from "npm:svix@2.8.0";

const secret = `whsec_${btoa("local-webhook-validation-fixture")}`;
Deno.env.set("SUPABASE_URL", "https://fixture.invalid");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "local-fixture-key");
Deno.env.set("RESEND_WEBHOOK_SECRET", secret);

let capturedHandler: ((request: Request) => Promise<Response>) | undefined;
const originalServe = Object.getOwnPropertyDescriptor(Deno, "serve")!;
Object.defineProperty(Deno, "serve", {
  configurable: true,
  value: (handler: (request: Request) => Promise<Response>) => {
    capturedHandler = handler;
  },
});
try {
  await import("../functions/email-webhook/index.ts");
} finally {
  Object.defineProperty(Deno, "serve", originalServe);
}
if (!capturedHandler) throw new Error("Webhook handler was not registered");
const handle = capturedHandler;

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function signedRequest(value: unknown): Request {
  const body = JSON.stringify(value);
  const now = new Date();
  const id = "msg_local_fixture";
  return new Request("http://localhost/email-webhook", {
    method: "POST",
    body,
    headers: {
      "svix-id": id,
      "svix-timestamp": Math.floor(now.getTime() / 1000).toString(),
      "svix-signature": new Webhook(secret).sign(id, now, body),
    },
  });
}

Deno.test("signed malformed webhook payloads return 400 before database access", async () => {
  const originalFetch = globalThis.fetch;
  let databaseCalls = 0;
  globalThis.fetch = () => {
    databaseCalls++;
    throw new Error("Unexpected database access");
  };
  try {
    const malformed: unknown[] = [
      null, [], "payload", 12, true, {},
      { type: "email.opened" },
      { type: 3, data: { email_id: "fixture-id" } },
      { type: " ", data: { email_id: "fixture-id" } },
      { type: "email.opened", data: [] },
      { type: "email.opened", data: null },
      { type: "email.opened", data: {} },
      { type: "email.opened", data: { email_id: 3 } },
      { type: "email.opened", data: { email_id: " " } },
      ...[false, 3, "bounce", [], { type: 3 }, { message: [] }].map((bounce) => ({
        type: "email.bounced", data: { email_id: "fixture-id", bounce },
      })),
    ];
    for (const value of malformed) {
      const response = await handle(signedRequest(value));
      assert(response.status === 400, `Expected 400 for ${JSON.stringify(value)}, got ${response.status}`);
    }
    assert(databaseCalls === 0, `Malformed input made ${databaseCalls} database calls`);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("valid opened, bounce defaults, permanent suppression and unknown events retain behavior", async () => {
  const originalFetch = globalThis.fetch;
  const writes: Array<{ path: string; body: unknown }> = [];
  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init);
    const path = new URL(request.url).pathname;
    if (request.method === "GET") {
      if (path.endsWith("/email_logs")) {
        return Response.json({ id: "log-fixture", user_id: "user-fixture", email_type: "weekly_summary" });
      }
      if (path.endsWith("/profiles")) return Response.json({ email: "fixture@example.invalid" });
      throw new Error(`Unexpected GET ${path}`);
    }
    writes.push({ path, body: await request.json() });
    return new Response(null, { status: 204 });
  };
  try {
    const opened = await handle(signedRequest({ type: "email.opened", data: { email_id: "fixture-id" } }));
    assert(opened.status === 200, "Valid opened webhook rejected");
    assert(JSON.stringify(writes).includes("opened_at"), "Opened event did not update timestamp");
    writes.length = 0;

    for (const bounce of [undefined, null, {}, { type: "", message: "" }]) {
      const response = await handle(signedRequest({ type: "email.bounced", data: { email_id: "fixture-id", bounce } }));
      assert(response.status === 200, "Valid optional bounce data rejected");
      assert(JSON.stringify(writes).includes('"bounce_type":"unknown"'), "Missing bounce type default changed");
      assert(JSON.stringify(writes).includes("Unknown bounce reason"), "Missing bounce reason default changed");
      writes.length = 0;
    }

    const permanent = await handle(signedRequest({
      type: "email.bounced",
      data: { email_id: "fixture-id", bounce: { type: "permanent", message: "local fixture reason" } },
    }));
    assert(permanent.status === 200, "Valid permanent bounce rejected");
    assert(writes.some((write) => write.path.endsWith("/email_suppression_list")), "Permanent bounce did not suppress address");
    assert(JSON.stringify(writes).includes("Permanent bounce: local fixture reason"), "Suppression reason changed");
    writes.length = 0;

    const unknown = await handle(signedRequest({ type: "email.future-event", data: { email_id: "fixture-id" } }));
    assert(unknown.status === 200 && writes.length === 0, "Unknown event behavior changed");
    const otherEvent = await handle(signedRequest({ type: "domain.future-event", data: {} }));
    assert(otherEvent.status === 200 && writes.length === 0, "Signed non-email event must be acknowledged without email fields");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("invalid signatures remain unauthorized before database access", async () => {
  const response = await handle(new Request("http://localhost/email-webhook", {
    method: "POST", body: JSON.stringify({ type: "email.opened", data: { email_id: "fixture-id" } }),
  }));
  assert(response.status === 401, `Expected 401, got ${response.status}`);
});
