// Run from the repository root; OCSP traffic is restricted to the loopback fixture server.
import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import {
  Environment,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library@3.1.0";
import { callerId, database } from "./test-supabase.ts";
import {
  ocspServer,
  setOCSPAvailable,
  testTransaction,
  trustedChain,
  untrustedChain,
} from "./test-fixtures.ts";
import { getPlanDetails, VALID_PRODUCT_IDS } from "../_shared/billing-types.ts";

let handleRequest: (request: Request) => Promise<Response>;
const originalServe = Deno.serve;
const originalGetEnv = Deno.env.get;
const mockEnv = (name: string) =>
  name === "SUPABASE_URL"
    ? "https://supabase.synthetic.invalid"
    : name === "SUPABASE_SERVICE_ROLE_KEY"
    ? "synthetic-test-value"
    : undefined;
Object.defineProperty(Deno.env, "get", { value: mockEnv, configurable: true });
Object.defineProperty(Deno, "serve", {
  value: (handler: typeof handleRequest) => {
    handleRequest = handler;
    return {};
  },
  configurable: true,
});
try {
  await import("./index.ts");
} finally {
  Object.defineProperty(Deno, "serve", {
    value: originalServe,
    configurable: true,
  });
}

async function request(
  signedTransaction: unknown,
  extra: Record<string, unknown> = {},
  authenticated = true,
) {
  return await handleRequest(
    new Request("http://localhost:8000", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(authenticated ? { Authorization: "Bearer synthetic-token" } : {}),
      },
      body: JSON.stringify({ signedTransaction, ...extra }),
    }),
  );
}

const existingSubscription = (overrides: Record<string, unknown> = {}) => ({
  id: "test-subscription",
  user_id: callerId,
  product_id: "com.mindfriend.premium.monthly",
  original_transaction_id: "100000000000001",
  last_transaction_id: "200000000000001",
  plan_type: "individual",
  billing_period: "monthly",
  expires_at: new Date(Date.now() + 86_400_000).toISOString(),
  family_id: null,
  ...overrides,
});

Deno.test("Apple verifier and verify-purchase handler with synthetic signatures and mocked services", async (t) => {
  try {
    await t.step(
      "official library accepts a trusted synthetic x5c chain with online checks",
      async () => {
        const verifier = new SignedDataVerifier(
          [trustedChain.root],
          true,
          Environment.PRODUCTION,
          "com.mindfriend.app",
          6758198271,
        );
        const decoded = await verifier.verifyAndDecodeTransaction(
          trustedChain.sign(testTransaction()),
        );
        assert.equal(decoded.transactionId, "200000000000001");
        assert.equal(decoded.environment, "Production");
      },
    );

    await t.step(
      "OCSP network failure is retryable and performs no writes",
      async () => {
        database.reset();
        setOCSPAvailable(false);
        try {
          const response = await request(trustedChain.sign(testTransaction()));
          assert.equal(response.status, 503);
          assert.equal(
            (await response.json()).code,
            "VERIFICATION_UNAVAILABLE",
          );
          assert.deepEqual(database.writes, []);
        } finally {
          setOCSPAvailable(true);
        }
      },
    );

    for (const productId of VALID_PRODUCT_IDS) {
      await t.step(
        `activates ${productId} using Apple's signed expiry`,
        async () => {
          database.reset();
          const payload = testTransaction({
            productId,
            appAccountToken: callerId.toUpperCase(),
          });
          const response = await request(trustedChain.sign(payload));
          assert.equal(response.status, 200);
          const body = await response.json();
          const plan = getPlanDetails(productId);
          assert.equal(body.valid, true);
          assert.equal(body.productId, productId);
          assert.equal(body.planType, plan.planType);
          assert.equal(body.billingPeriod, plan.billingPeriod);
          assert.equal(
            body.expiresAt,
            new Date(payload.expiresDate).toISOString(),
          );
          const subscription = database.writes.find((write) =>
            write.table === "subscriptions"
          );
          assert.equal(subscription?.data.seats_total, plan.seatsTotal);
          assert.equal(subscription?.data.expires_at, body.expiresAt);
        },
      );
    }

    for (const environment of ["Production", "Sandbox"]) {
      await t.step(
        `derives ${environment} from the verified JWS despite a conflicting client hint`,
        async () => {
          database.reset();
          const response = await request(
            trustedChain.sign(testTransaction({ environment })),
            {
              environment: environment === "Sandbox" ? "production" : "sandbox",
              originalTransactionId: "untrusted-original",
              productId: "untrusted-product",
            },
          );
          assert.equal(response.status, 200);
          const subscription = database.writes.find((write) =>
            write.table === "subscriptions"
          );
          assert.equal(
            subscription?.data.original_transaction_id,
            "100000000000001",
          );
        },
      );
    }

    const invalidClaims: [string, Record<string, unknown>, string][] = [
      [
        "wrong bundle",
        { bundleId: "com.other.app" },
        "JWS_VERIFICATION_FAILED",
      ],
      [
        "Xcode environment",
        { environment: "Xcode" },
        "JWS_VERIFICATION_FAILED",
      ],
      [
        "local testing environment",
        { environment: "LocalTesting" },
        "JWS_VERIFICATION_FAILED",
      ],
      [
        "unknown environment",
        { environment: "Unknown" },
        "JWS_VERIFICATION_FAILED",
      ],
      [
        "expired subscription",
        { expiresDate: Date.now() - 1 },
        "TRANSACTION_EXPIRED",
      ],
      [
        "missing signed expiry",
        { expiresDate: undefined },
        "INVALID_TRANSACTION_EXPIRY",
      ],
      [
        "unrepresentable expiry",
        { expiresDate: Number.MAX_SAFE_INTEGER },
        "INVALID_TRANSACTION_EXPIRY",
      ],
      ["revoked transaction", {
        revocationDate: Date.now() - 1,
        revocationReason: 0,
      }, "TRANSACTION_REVOKED"],
      [
        "revocation reason without date",
        { revocationReason: 1 },
        "TRANSACTION_REVOKED",
      ],
      [
        "unknown product",
        { productId: "com.other.subscription" },
        "INVALID_PRODUCT_ID",
      ],
      [
        "inherited object product key",
        { productId: "constructor" },
        "INVALID_PRODUCT_ID",
      ],
      [
        "missing original transaction",
        { originalTransactionId: undefined },
        "INVALID_TRANSACTION_ID",
      ],
      ["empty transaction", { transactionId: "" }, "INVALID_TRANSACTION_ID"],
      ["owner token mismatch", {
        appAccountToken: "22222222-2222-4222-8222-222222222222",
      }, "APP_ACCOUNT_TOKEN_MISMATCH"],
      [
        "empty owner token",
        { appAccountToken: "" },
        "APP_ACCOUNT_TOKEN_MISMATCH",
      ],
    ];
    for (const [name, overrides, code] of invalidClaims) {
      await t.step(
        `rejects ${name} before subscription lookup or writes`,
        async () => {
          database.reset();
          // A duplicate must not bypass revalidation of expiry/revocation/owner.
          database.subscription = existingSubscription();
          const response = await request(
            trustedChain.sign(testTransaction(overrides)),
          );
          assert.equal(
            response.status,
            code === "APP_ACCOUNT_TOKEN_MISMATCH" ? 403 : 400,
          );
          assert.equal((await response.json()).code, code);
          assert.deepEqual(database.reads, []);
          assert.deepEqual(database.writes, []);
        },
      );
    }

    await t.step(
      "rejects a tampered signature and an untrusted root",
      async () => {
        const signed = trustedChain.sign(testTransaction());
        const parts = signed.split(".");
        parts[1] = Buffer.from(
          JSON.stringify(
            testTransaction({ productId: "com.mindfriend.family.annual" }),
          ),
        ).toString("base64url");
        for (
          const invalid of [
            parts.join("."),
            untrustedChain.sign(testTransaction()),
            "invalid",
            123,
          ]
        ) {
          database.reset();
          const response = await request(invalid);
          assert.equal(response.status, 400);
          assert.equal((await response.json()).code, "JWS_VERIFICATION_FAILED");
          assert.deepEqual(database.writes, []);
        }
      },
    );

    await t.step(
      "restores a legacy signed purchase without an account token",
      async () => {
        database.reset();
        const response = await request(
          trustedChain.sign(
            testTransaction({ purchaseDate: Date.now() - 100 * 86_400_000 }),
          ),
        );
        assert.equal(response.status, 200);
        assert.equal((await response.json()).valid, true);
      },
    );

    await t.step(
      "rejects legacy cross-account claims by original transaction ID",
      async () => {
        database.reset();
        database.subscription = existingSubscription({
          user_id: "22222222-2222-4222-8222-222222222222",
        });
        const response = await request(trustedChain.sign(testTransaction()));
        assert.equal(response.status, 409);
        assert.equal(
          (await response.json()).code,
          "TRANSACTION_ALREADY_CLAIMED",
        );
        assert.deepEqual(database.writes, []);
      },
    );

    await t.step(
      "same transaction is idempotent with no database writes",
      async () => {
        database.reset();
        database.subscription = existingSubscription();
        const response = await request(trustedChain.sign(testTransaction()));
        assert.equal(response.status, 200);
        assert.equal((await response.json()).idempotent, true);
        assert.deepEqual(database.writes, []);
      },
    );

    await t.step(
      "same owner's new transaction renews using the signed expiry",
      async () => {
        database.reset();
        database.subscription = existingSubscription();
        const payload = testTransaction({ transactionId: "200000000000002" });
        const response = await request(trustedChain.sign(payload));
        assert.equal(response.status, 200);
        assert.equal((await response.json()).renewed, true);
        assert.equal(database.writes.length, 1);
        assert.equal(
          database.writes[0].data.last_transaction_id,
          payload.transactionId,
        );
        assert.equal(
          database.writes[0].data.expires_at,
          new Date(payload.expiresDate).toISOString(),
        );
      },
    );

    await t.step(
      "lookup errors and missing/invalid auth cannot grant access",
      async () => {
        database.reset();
        database.lookupError = { code: "synthetic-lookup-error" };
        assert.equal(
          (await request(trustedChain.sign(testTransaction()))).status,
          500,
        );
        assert.deepEqual(database.writes, []);
        database.reset();
        assert.equal(
          (await request(trustedChain.sign(testTransaction()), {}, false))
            .status,
          401,
        );
        database.authenticated = false;
        assert.equal(
          (await request(trustedChain.sign(testTransaction()))).status,
          401,
        );
        assert.deepEqual(database.reads, []);
        assert.deepEqual(database.writes, []);
      },
    );

    await t.step("unsigned legacy request remains rejected", async () => {
      database.reset();
      const response = await request(undefined, {
        originalTransactionId: "100000000000001",
        productId: VALID_PRODUCT_IDS[0],
      });
      assert.equal(response.status, 400);
      assert.equal((await response.json()).code, "MISSING_SIGNED_TRANSACTION");
      assert.deepEqual(database.writes, []);
    });
  } finally {
    await ocspServer.shutdown();
    Object.defineProperty(Deno.env, "get", {
      value: originalGetEnv,
      configurable: true,
    });
  }
});
