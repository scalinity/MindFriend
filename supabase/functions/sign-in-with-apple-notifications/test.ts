import * as jose from "npm:jose@6.2.13";
import { verifyAppleNotification } from "./apple-notification.ts";
import { isAppleRelayEmailDisabled, shouldSendEmail } from "../_shared/email-utils.ts";

function assert(condition: unknown, message = "assertion failed"): asserts condition {
  if (!condition) throw new Error(message);
}
const subject = "000001.synthetic-apple-provider-subject.0001";
const now = Math.floor(Date.now() / 1000);
const keys = await jose.generateKeyPair("RS256", { extractable: true });
const jwk = { ...await jose.exportJWK(keys.publicKey), alg: "RS256", kid: "synthetic-apple-key" };
const localKeys = jose.createLocalJWKSet({ keys: [jwk] });
const event = (type = "email-disabled") => ({ type, sub: subject, event_time: now });
async function signed(overrides: jose.JWTPayload = {}) {
  return await new jose.SignJWT({ iss: "https://appleid.apple.com", aud: "com.mindfriend.app", iat: now,
    jti: "synthetic-event", events: event(), ...overrides })
    .setProtectedHeader({ alg: "RS256", kid: jwk.kid }).sign(keys.privateKey);
}

Deno.test("Apple notification verification accepts the documented no-exp contract and rejects invalid trust/claims", async () => {
  for (const type of ["email-disabled", "email-enabled", "consent-revoked", "account-deleted"]) {
    const result = await verifyAppleNotification(await signed({ events: event(type) }), "com.mindfriend.app", localKeys);
    assert(result.type === type && result.sub === subject);
  }
  const badTokens = await Promise.all([
    signed({ iss: "https://attacker.invalid" }), signed({ aud: "another.app" }),
    signed({ iat: now + 1000 }), signed({ jti: "" }), signed({ exp: now - 1 }),
    signed({ events: { ...event(), event_time: "123" } }), signed({ events: event("account-delete") }),
    signed({ events: { ...event(), event_time: now + 1000 } }),
    signed({ events: undefined, event_type: "email-disabled", sub: subject }),
    signed({ events: { ...event(), sub: "" } }),
  ]);
  badTokens.push(await new jose.SignJWT({ events: event() }).setProtectedHeader({ alg: "HS256" }).sign(new Uint8Array(32)));
  for (const token of badTokens) {
    let rejected = false;
    try { await verifyAppleNotification(token, "com.mindfriend.app", localKeys); } catch { rejected = true; }
    assert(rejected, "untrusted or malformed notification accepted");
  }
  const foreignKeys = await jose.generateKeyPair("RS256");
  const wrongSignature = await new jose.SignJWT({ iss: "https://appleid.apple.com", aud: "com.mindfriend.app", iat: now,
    jti: "synthetic-event", events: event() }).setProtectedHeader({ alg: "RS256", kid: jwk.kid }).sign(foreignKeys.privateKey);
  let rejected = false;
  try { await verifyAppleNotification(wrongSignature, "com.mindfriend.app", localKeys); } catch { rejected = true; }
  assert(rejected, "wrong RSA signature accepted");
});

Deno.test("Apple handler verifies the payload before service-only identity processing and retries failed effects", async () => {
  const originalServe = Deno.serve;
  const originalFetch = globalThis.fetch;
  const names = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "APPLE_CLIENT_ID"];
  const previous = names.map((name) => Deno.env.get(name));
  let handler!: (req: Request) => Promise<Response>;
  const calls: Record<string, unknown>[] = [];
  let failRPC = false;
  try {
    Deno.env.set("SUPABASE_URL", "http://localhost:55417");
    Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "synthetic-service-key");
    Deno.env.set("APPLE_CLIENT_ID", "com.mindfriend.app");
    Object.defineProperty(Deno, "serve", { configurable: true, value: (callback: typeof handler) => { handler = callback; } });
    globalThis.fetch = async (input, init) => {
      const url = String(input);
      if (url === "https://appleid.apple.com/auth/keys") return Response.json({ keys: [jwk] });
      assert(url === "http://localhost:55417/rest/v1/rpc/process_apple_account_event", "unexpected service request");
      calls.push(JSON.parse(String(init?.body)));
      return failRPC ? Response.json({ message: "synthetic failure", code: "synthetic" }, { status: 500 }) : Response.json(null);
    };
    await import("./index.ts");
    const send = (body: unknown) => handler(new Request("http://localhost/apple", { method: "POST", body: JSON.stringify(body) }));
    assert((await handler(new Request("http://localhost/apple"))).status === 405);
    assert((await send({ token: await signed() })).status === 400);
    assert((await send({ payload: "invalid" })).status === 401);
    assert((await send({ payload: await signed({ aud: "wrong.app" }) })).status === 401);
    assert((await send({ payload: await signed({ iss: "https://attacker.invalid" }) })).status === 401);
    assert(calls.length === 0, "invalid notifications reached database");
    assert((await send({ payload: await signed() })).status === 200);
    assert(Number(calls.length) === 1 && calls[0].p_subject === subject && calls[0].p_type === "email-disabled" && calls[0].p_event_time === now);
    assert(!("user_id" in calls[0]), "Apple subject used as local account UUID");
    failRPC = true;
    assert((await send({ payload: await signed() })).status === 500, "failed effects acknowledged");
  } finally {
    globalThis.fetch = originalFetch;
    Object.defineProperty(Deno, "serve", { configurable: true, value: originalServe });
    names.forEach((name, index) => previous[index] === undefined ? Deno.env.delete(name) : Deno.env.set(name, previous[index]!));
  }
});

Deno.test("Apple forwarding suppression applies only to the mapped relay address and fails closed on lookup error", async () => {
  const client = (metadata: Record<string, unknown>, error: unknown = null) => ({ auth: { admin: { getUserById: () =>
    Promise.resolve({ data: { user: { app_metadata: metadata, user_metadata: { apple_email_disabled: false } } }, error }) } } });
  const disabled = client({ apple_email_disabled: true, apple_relay_email: "relay@privaterelay.appleid.com" });
  assert(await isAppleRelayEmailDisabled(disabled, "owner", "RELAY@privaterelay.appleid.com"));
  assert(!await isAppleRelayEmailDisabled(disabled, "owner", "another@example.invalid"));
  assert(!await isAppleRelayEmailDisabled(client({ apple_email_disabled: false, apple_relay_email: "relay@privaterelay.appleid.com" }), "owner", "relay@privaterelay.appleid.com"));
  assert(!await isAppleRelayEmailDisabled(client({}), "owner", "relay@privaterelay.appleid.com"));
  let retryableFailure = false;
  try { await shouldSendEmail(client({}, new Error("synthetic unavailable")), "owner", "weekly_summary", "relay@privaterelay.appleid.com"); }
  catch { retryableFailure = true; }
  assert(retryableFailure, "lookup failure became delivery or a permanent skip");
});
