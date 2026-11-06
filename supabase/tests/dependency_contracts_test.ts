import { create as createOld, verify as verifyOld } from "https://deno.land/x/djwt@v2.8/mod.ts";
import { create, verify } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import { jwtVerify } from "npm:jose@6.2.13";
import { Webhook } from "npm:svix@2.8.0";

function assert(value: unknown, label: string): asserts value {
  if (!value) throw new Error(label);
}
Deno.test("JWT updates preserve existing invitation signatures and reject tampering", async () => {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode("synthetic-fixture-key-with-32bytes"), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
  const payload = { purpose: "therapist_invitation", clientId: "fixture", exp: Math.floor(Date.now() / 1000) + 60 };
  const oldToken = await createOld({ alg: "HS256", typ: "JWT" }, payload, key);
  assert((await verify(oldToken, key)).clientId === "fixture", "Existing invitation invalidated");
  const token = await create({ alg: "HS256", typ: "JWT" }, payload, key);
  assert((await verifyOld(token, key)).clientId === "fixture", "Rolling release JWT incompatibility");
  assert((await jwtVerify(token, key, { algorithms: ["HS256"] })).payload.clientId === "fixture", "JOSE verification mismatch");
  let denied = false;
  try { await jwtVerify(token.slice(0, -4) + "AAAA", key, { algorithms: ["HS256"] }); } catch { denied = true; }
  assert(denied, "Tampered token accepted");
});

Deno.test("updated webhook handlers verify signatures before parsing or database work", async () => {
  const env = { SUPABASE_URL: "http://127.0.0.1:55321", SUPABASE_SERVICE_ROLE_KEY: "synthetic-only", RESEND_WEBHOOK_SECRET: "whsec_" + btoa("synthetic-webhook-fixture-secret"), STRIPE_SECRET_KEY: "synthetic-only", STRIPE_WEBHOOK_SECRET: "synthetic-stripe-webhook-secret", TEST_WEBHOOK_BYPASS_AUTH: "true" };
  const previous = Object.keys(env).map((name) => Deno.env.get(name));
  const originalServe = Deno.serve, originalFetch = globalThis.fetch;
  let handler: (request: Request) => Promise<Response> = () => { throw new Error("Handler not registered"); };
  let fetches = 0;
  try {
    for (const [name, value] of Object.entries(env)) Deno.env.set(name, value);
    Object.defineProperty(Deno, "serve", { configurable: true, value: (value: typeof handler) => { handler = value; } });
    globalThis.fetch = ((input) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      assert(url.origin === env.SUPABASE_URL, "External request denied");
      fetches++;
      return Promise.resolve(Response.json([]));
    }) as typeof fetch;
    await import("../functions/email-webhook/index.ts");
    const payload = JSON.stringify({ type: "synthetic.unknown", data: {} });
    const now = new Date(), id = "synthetic-fixture-message";
    const signature = new Webhook(env.RESEND_WEBHOOK_SECRET).sign(id, now, payload);
    const headers = { "svix-id": id, "svix-timestamp": String(Math.floor(now.getTime() / 1000)), "svix-signature": signature };
    let response = await handler(new Request("http://localhost/email-webhook", { method: "POST", headers, body: payload }));
    assert(response.status === 200, "Valid Svix signature or parsed payload failed"); await response.text();
    const beforeInvalidEmail = fetches;
    response = await handler(new Request("http://localhost/email-webhook", { method: "POST", headers, body: payload + " " }));
    assert(response.status === 401 && fetches === beforeInvalidEmail, "Tampered email webhook reached data access"); await response.text();
    await import("../functions/b2b-stripe-webhook/index.ts");
    const event = JSON.stringify({ id: "evt_synthetic_fixture", type: "synthetic.unknown", object: "event", data: { object: {} } });
    const timestamp = String(Math.floor(Date.now() / 1000));
    const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.STRIPE_WEBHOOK_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
    const signed = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(timestamp + "." + event));
    const hex = Array.from(new Uint8Array(signed), (byte) => byte.toString(16).padStart(2, "0")).join("");
    response = await handler(new Request("http://localhost/stripe", { method: "POST", headers: { "stripe-signature": `t=${timestamp},v1=${hex}` }, body: event }));
    assert(response.status === 200, "Deno async Stripe signature verification failed"); await response.text();
    const beforeInvalidStripe = fetches;
    response = await handler(new Request("http://localhost/stripe", { method: "POST", headers: { "stripe-signature": `t=${timestamp},v1=invalid` }, body: event }));
    assert(response.status === 400 && fetches === beforeInvalidStripe, "Stripe bypass reached data access"); await response.text();
    const { CrisisEventSchema } = await import("../functions/log-crisis-event/index.ts");
    assert(CrisisEventSchema.safeParse({ assessmentTemplateId: crypto.randomUUID(), eventType: "synthetic", severity: "low", context: { synthetic: true } }).success, "Valid crisis schema rejected");
    assert(!CrisisEventSchema.safeParse({ assessmentTemplateId: "bad", eventType: "", severity: "invalid" }).success, "Invalid crisis event accepted");

  } finally {
    globalThis.fetch = originalFetch;
    Object.defineProperty(Deno, "serve", { configurable: true, value: originalServe });
    Object.keys(env).forEach((name, i) => previous[i] === undefined ? Deno.env.delete(name) : Deno.env.set(name, previous[i]!));
  }
});
