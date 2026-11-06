// Actual webhook handler, real local HMAC verification, mocked database HTTP.
// Run without network permissions; all configuration and rows are synthetic.
import { deepStrictEqual, ok, strictEqual } from "node:assert/strict";

type Row = Record<string, unknown>;
type Handler = (request: Request) => Response | Promise<Response>;
const organizationId = "10000000-0000-4000-8000-000000000001";
const stripeSubscriptionId = "sub_synthetic_current";
const webhookSecret = "whsec_synthetic_local_test";

Deno.test("billing cancellation through actual handler", async (t) => {
  const originalServe = Deno.serve;
  const originalFetch = globalThis.fetch;
  const originalEnvGet = Deno.env.get;
  const environment = new Map([
    ["SUPABASE_URL", "http://localhost:54321"],
    ["SUPABASE_SERVICE_ROLE_KEY", "synthetic-service-key"],
    ["STRIPE_SECRET_KEY", "sk_test_synthetic_local_test"],
    ["STRIPE_WEBHOOK_SECRET", webhookSecret],
  ]);
  let handler: Handler;
  let rows: Record<string, Row[]>;
  let calls: { table: string; body: Row; matched: number }[];
  let brokenTable: string;
  const reply = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json" },
    });
  const event = (subscriptionId = stripeSubscriptionId) => ({
    id: "evt_synthetic_cancellation",
    object: "event",
    type: "customer.subscription.deleted",
    created: Math.floor(Date.now() / 1000) - 30,
    data: {
      object: {
        id: subscriptionId,
        object: "subscription",
        status: "canceled",
        ended_at: Math.floor(Date.now() / 1000) - 60,
        canceled_at: Math.floor(Date.now() / 1000) - 120,
        metadata: { organization_id: organizationId },
      },
    },
  });
  const sponsored = (id: string, overrides: Row = {}): Row => ({
    id,
    user_id: id,
    plan_type: "organization",
    status: "active",
    access_source: "organization_sponsored",
    organization_id: organizationId,
    product_id: "org_sponsored_premium",
    original_transaction_id: `org_${organizationId}_${id}`,
    expires_at: null,
    ...overrides,
  });
  const reset = () => {
    calls = [];
    brokenTable = "";
    rows = {
      organizations: [{
        id: organizationId,
        stripe_subscription_id: stripeSubscriptionId,
        status: "active",
        subscription_status: "active",
      }],
      subscriptions: [sponsored("sponsored-active")],
      billing_audit_log: [],
    };
  };
  const invoke = async (
    payload: unknown,
    signature: string | null | undefined = undefined,
    signingSecret = webhookSecret,
  ) => {
    const body = JSON.stringify(payload);
    if (signature === undefined) {
      const timestamp = Math.floor(Date.now() / 1000);
      const key = await crypto.subtle.importKey(
        "raw",
        new TextEncoder().encode(signingSecret),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"],
      );
      const digest = await crypto.subtle.sign(
        "HMAC",
        key,
        new TextEncoder().encode(`${timestamp}.${body}`),
      );
      const hex = Array.from(
        new Uint8Array(digest),
        (byte) => byte.toString(16).padStart(2, "0"),
      ).join("");
      signature = `t=${timestamp},v1=${hex}`;
    }
    const response = await handler(
      new Request("http://localhost:54321/functions/v1/b2b-stripe-webhook", {
        method: "POST",
        headers: signature === null ? {} : { "stripe-signature": signature },
        body,
      }),
    );
    return { status: response.status, body: await response.json() };
  };

  Deno.env.get = (name) => environment.get(name);
  Deno.serve = ((captured: Handler) => {
    handler = captured;
  }) as typeof Deno.serve;
  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    strictEqual(url.origin, "http://localhost:54321");
    ok(url.pathname.startsWith("/rest/v1/"));
    const table = url.pathname.slice("/rest/v1/".length);
    ok(["organizations", "subscriptions", "billing_audit_log"].includes(table));
    ok(["PATCH", "POST"].includes(request.method));
    const body = await request.json() as Row;
    let matching = rows[table];
    for (const [column, filter] of url.searchParams) {
      if (column === "select") continue;
      ok(filter.startsWith("eq."), `Unexpected filter ${column}=${filter}`);
      matching = matching.filter((row) =>
        String(row[column]) === filter.slice(3)
      );
    }
    calls.push({ table, body, matched: matching.length });
    if (table === brokenTable) {
      return reply({ code: "XX000", message: "Synthetic query failure" }, 500);
    }
    if (table === "subscriptions") {
      // Match the current persisted schema: no tier/ended_at, no NULL source.
      for (const column of Object.keys(body)) {
        ok(["status", "expires_at", "updated_at"].includes(column));
      }
      strictEqual(body.status, "cancelled");
    }
    if (request.method === "POST") {
      rows[table].push(structuredClone(body));
      return new Response(null, { status: 201 });
    }
    for (const row of matching) Object.assign(row, body);
    return request.headers.get("Prefer")?.includes("return=representation")
      ? reply(matching)
      : new Response(null, { status: 204 });
  };

  try {
    await import("./index.ts");

    await t.step(
      "valid cancellation uses current schema and is safe to repeat",
      async () => {
        reset();
        const payload = event();
        strictEqual((await invoke(payload)).status, 200);
        strictEqual(rows.organizations[0].status, "churned");
        strictEqual(rows.organizations[0].subscription_status, "canceled");
        strictEqual(rows.subscriptions[0].status, "cancelled");
        strictEqual(
          rows.subscriptions[0].expires_at,
          new Date(payload.data.object.ended_at * 1000).toISOString(),
        );
        strictEqual(rows.subscriptions[0].organization_id, organizationId);
        strictEqual(
          rows.subscriptions[0].access_source,
          "organization_sponsored",
        );
        const once = structuredClone(rows.subscriptions);
        strictEqual((await invoke(payload)).status, 200);
        deepStrictEqual(rows.subscriptions, once);
        strictEqual(
          calls.filter((c) => c.table === "subscriptions")[1].matched,
          0,
        );
        // The existing schema has no unique Stripe event key: audit dedupe is not claimed.
      },
    );

    await t.step(
      "personal purchases and other sponsorships remain unchanged",
      async () => {
        reset();
        rows.subscriptions.push(
          sponsored("personal", {
            plan_type: "individual",
            product_id: "com.mindfriend.individual.monthly",
            access_source: "personal",
            organization_id: null,
          }),
          sponsored("personal-same-org", { access_source: "personal" }),
          // verify-purchase upserts the purchased plan/product without clearing source/org.
          sponsored("purchase-retaining-sponsor-markers", {
            plan_type: "family",
            product_id: "com.mindfriend.family.monthly",
            original_transaction_id: "synthetic-apple-purchase",
          }),
          sponsored("purchased-product", {
            product_id: "synthetic-purchased-product",
          }),
          sponsored("other-organization", {
            organization_id: "another-organization",
          }),
          sponsored("already-expired", { status: "expired" }),
          sponsored("already-cancelled", { status: "cancelled" }),
        );
        const preserved = structuredClone(rows.subscriptions.slice(1));
        strictEqual((await invoke(event())).status, 200);
        deepStrictEqual(rows.subscriptions.slice(1), preserved);
        strictEqual(rows.subscriptions[0].status, "cancelled");
      },
    );

    await t.step(
      "deletion for a replaced Stripe subscription is ignored",
      async () => {
        reset();
        const before = structuredClone(rows);
        strictEqual(
          (await invoke(event("sub_synthetic_replaced"))).status,
          200,
        );
        deepStrictEqual(rows, before);
        strictEqual(calls.length, 1);
      },
    );

    await t.step(
      "missing and invalid signatures perform no database calls",
      async () => {
        reset();
        strictEqual((await invoke(event(), null)).status, 400);
        strictEqual((await invoke(event(), "malformed-signature")).status, 400);
        strictEqual(
          (await invoke(event(), undefined, "whsec_wrong_secret")).status,
          400,
        );
        strictEqual(calls.length, 0);
        strictEqual(rows.subscriptions[0].status, "active");
      },
    );

    await t.step(
      "missing Stripe key rejects configuration before database calls",
      async () => {
        reset();
        environment.delete("STRIPE_SECRET_KEY");
        try {
          strictEqual((await invoke(event())).status, 503);
          strictEqual(calls.length, 0);
        } finally {
          environment.set("STRIPE_SECRET_KEY", "sk_test_synthetic_local_test");
        }
      },
    );

    await t.step(
      "organization failure returns 500 without revoking access",
      async () => {
        reset();
        brokenTable = "organizations";
        strictEqual((await invoke(event())).status, 500);
        strictEqual(rows.subscriptions[0].status, "active");
        strictEqual(calls.length, 1);
      },
    );

    await t.step(
      "revocation failure returns 500 and a retry completes it",
      async () => {
        reset();
        const payload = event();
        brokenTable = "subscriptions";
        strictEqual((await invoke(payload)).status, 500);
        strictEqual(rows.subscriptions[0].status, "active");
        strictEqual(rows.billing_audit_log.length, 0);
        brokenTable = "";
        strictEqual((await invoke(payload)).status, 200);
        strictEqual(rows.subscriptions[0].status, "cancelled");
        strictEqual(rows.billing_audit_log.length, 1);
      },
    );

    await t.step(
      "audit failure returns 500 and retry preserves the cancelled entitlement",
      async () => {
        reset();
        const payload = event();
        brokenTable = "billing_audit_log";
        strictEqual((await invoke(payload)).status, 500);
        const cancelled = structuredClone(rows.subscriptions);
        brokenTable = "";
        strictEqual((await invoke(payload)).status, 200);
        deepStrictEqual(rows.subscriptions, cancelled);
        strictEqual(rows.billing_audit_log.length, 1);
      },
    );
  } finally {
    Deno.serve = originalServe;
    globalThis.fetch = originalFetch;
    Deno.env.get = originalEnvGet;
  }
});
