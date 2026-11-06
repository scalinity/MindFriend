function assert(condition: unknown, message = "assertion failed"): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("gift endpoints never issue, redeem, charge, or mutate existing records while unavailable", async () => {
  const originalServe = Deno.serve;
  const originalFetch = globalThis.fetch;
  const handlers: Array<(req: Request) => Response | Promise<Response>> = [];
  let requests = 0;
  try {
    // Every auth/database/payment request is blocked, so the real handlers cannot
    // mutate either a historical gift or its recipient's existing entitlement.
    globalThis.fetch = () => { requests++; throw new Error("Unexpected outbound request"); };
    Object.defineProperty(Deno, "serve", { configurable: true, value: (handler: (req: Request) => Response) => { handlers.push(handler); } });
    await import("../functions/create-gift/index.ts");
    await import("../functions/redeem-gift/index.ts");
    assert(handlers.length === 2);
    for (const handler of handlers) {
      for (const body of [
        { plan_id: "synthetic-plan", payment_method_id: "synthetic-payment", recipient_email: "recipient@example.invalid" },
        { redemption_code: "synthetic-gift" }, { redemptionCode: "synthetic-gift" },
      ]) {
        const response = await handler(new Request("http://localhost/gift", {
          method: "POST", headers: { Authorization: "Bearer synthetic-user" }, body: JSON.stringify(body),
        }));
        assert(response.status === 503);
        const data = await response.json();
        assert(data.code === "GIFTING_UNAVAILABLE" && data.success === false);
        assert(!data.gift && !data.subscription && !data.redemptionCode);
      }
      assert((await handler(new Request("http://localhost/gift", { method: "OPTIONS" }))).status === 200);
      assert((await handler(new Request("http://localhost/gift"))).status === 405);
    }
    assert(requests === 0, "unavailable gifting contacted external services");
  } finally {
    globalThis.fetch = originalFetch;
    Object.defineProperty(Deno, "serve", { configurable: true, value: originalServe });
  }
});
