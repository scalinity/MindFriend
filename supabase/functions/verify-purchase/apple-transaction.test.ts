// Run from the repository root; OCSP traffic is restricted to the loopback fixture server.
// @deno-types="npm:@apple/app-store-server-library@3.1.0/dist/jws_verification.d.ts"
import { SignedDataVerifier } from "./apple-verifier.js";
import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import {
  Environment,
} from "npm:@apple/app-store-server-library@3.1.0";
import { callerId, database } from "./test-supabase.ts";
import { X509Certificate } from "./edge-crypto.ts";
import {
  ocspServer,
  expiredChain,
  missingOIDChain,
  nonCAChain,
  setOCSPRevoked,
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
  status: "active",
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

    for (const [name, chain] of [["expired signing certificate", expiredChain], ["missing Apple leaf OID", missingOIDChain], ["non-CA intermediate", nonCAChain]] as const) {
      await t.step(`rejects ${name}`, async () => {
        const verifier = new SignedDataVerifier([chain.root], true, Environment.PRODUCTION, "com.mindfriend.app", 6758198271);
        await assert.rejects(() => verifier.verifyAndDecodeTransaction(chain.sign(testTransaction())));
      });
    }
    await t.step("rejects a signed revoked OCSP response before writes", async () => {
      database.reset();
      setOCSPRevoked(true);
      try {
        const response = await request(trustedChain.sign(testTransaction()));
        assert.equal(response.status, 400);
        assert.equal((await response.json()).code, "JWS_VERIFICATION_FAILED");
        assert.deepEqual(database.writes, []);
      } finally { setOCSPRevoked(false); }
    });

    await t.step("rejection log records each verifier's status and cause without signed content", async () => {
      database.reset();
      const signed = untrustedChain.sign(testTransaction());
      const lines: string[] = [];
      const originalLog = console.log;
      console.log = (line: string) => lines.push(line);
      try {
        assert.equal((await request(signed)).status, 400);
      } finally { console.log = originalLog; }
      const entry = lines.map((line) => JSON.parse(line))
        .find((logged) => logged.message === "Transaction verification rejected");
      assert.deepEqual(
        entry.context.verifiers.map((v: { environment: string; status: number }) => [v.environment, v.status]),
        [["Production", 1], ["Sandbox", 1]],
      );
      assert.match(entry.context.verifiers[0].at, /apple-verifier\.js:\d+/);
      for (const part of signed.split(".")) assert.ok(!lines.join("\n").includes(part));
    });

    await t.step("a certificate checked against a root of another key type reads as unsigned", async () => {
      const production = await Deno.readTextFile(new URL("./apple-roots.ts", import.meta.url));
      const roots = [...production.matchAll(/"([A-Za-z0-9+/=]{200,})"/g)]
        .map((match) => new X509Certificate(Buffer.from(match[1], "base64")));
      const rsaRoot = roots.find((root) => root.publicKey.asymmetricKeyType === "rsa")!;
      const intermediate = new X509Certificate(Buffer.from(trustedChain.certificates[1], "base64"));
      const root = new X509Certificate(trustedChain.root);
      assert.equal(intermediate.verify(rsaRoot.publicKey), false);
      assert.equal(intermediate.verify(root.publicKey), true);
    });

    await t.step("a value that is not an Error is logged with the step that threw it and the chain", async () => {
      database.reset();
      // Some dependencies throw bare strings, which Apple's catch-all used to discard.
      // The expired chain has never verified, so no cached key skips the signature check.
      const signed = expiredChain.sign(testTransaction());
      const originalVerify = X509Certificate.prototype.verify;
      X509Certificate.prototype.verify = () => { throw "synthetic non-Error"; };
      const lines: string[] = [];
      const originalLog = console.log;
      console.log = (line: string) => lines.push(line);
      try {
        const response = await request(signed);
        assert.equal(response.status, 400);
        assert.equal((await response.json()).code, "JWS_VERIFICATION_FAILED");
      } finally {
        console.log = originalLog;
        X509Certificate.prototype.verify = originalVerify;
      }
      const entry = lines.map((line) => JSON.parse(line))
        .find((logged) => logged.message === "Transaction verification rejected");
      for (const verifier of entry.context.verifiers) {
        assert.equal(verifier.status, 1);
        assert.match(verifier.cause, /non-Error thrown at intermediate signature: synthetic non-Error/);
      }
      assert.equal(entry.context.chain.length, 3);
      assert.match(entry.context.chain.leafSerial, /^[0-9A-F]+$/);
      assert.equal(typeof entry.context.chain.leafValidTo, "string");
      for (const part of signed.split(".")) assert.ok(!lines.join("\n").includes(part));
      assert.deepEqual(database.writes, []);
    });

    await t.step("rejects tampered leaf and intermediate certificate signatures", async () => {
      const signed = trustedChain.sign(testTransaction());
      for (const index of [0, 1]) {
        const parts = signed.split(".");
        const header = JSON.parse(Buffer.from(parts[0], "base64url").toString());
        const cert = Buffer.from(header.x5c[index], "base64");
        cert[cert.length - 1] ^= 1;
        header.x5c[index] = cert.toString("base64");
        parts[0] = Buffer.from(JSON.stringify(header)).toString("base64url");
        database.reset();
        const response = await request(parts.join("."));
        assert.equal(response.status, 400);
        assert.deepEqual(database.writes, []);
      }
    });

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
        "missing signed purchase date",
        { purchaseDate: undefined },
        "INVALID_TRANSACTION_EXPIRY",
      ],
      [
        "unrepresentable expiry",
        { expiresDate: Number.MAX_SAFE_INTEGER },
        "INVALID_TRANSACTION_EXPIRY",
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
          assert.deepEqual(database.rpcCalls, []);
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

    for (const overrides of [{ revocationDate: Date.now() - 1, revocationReason: 0 }, { revocationReason: 1 }]) {
      await t.step("verified revocation reconciles only the matching stored transaction", async () => {
        database.reset();
        database.subscription = existingSubscription();
        const response = await request(trustedChain.sign(testTransaction(overrides)));
        assert.equal(response.status, 400);
        assert.equal((await response.json()).code, "TRANSACTION_REVOKED");
        assert.equal(database.subscription.status, "cancelled");
        assert.deepEqual(database.rpcCalls, [{ name: "revoke_verified_apple_transaction", args: {
          p_user_id: callerId, p_original_transaction_id: "100000000000001", p_transaction_id: "200000000000001",
        } }]);
      });
    }
    for (const subscription of [existingSubscription({ user_id: "22222222-2222-4222-8222-222222222222" }), existingSubscription({ last_transaction_id: "newer-renewal" })]) {
      await t.step("revoked older or other-owner receipt cannot cancel current access", async () => {
        database.reset();
        database.subscription = { ...subscription };
        const response = await request(trustedChain.sign(testTransaction({ revocationReason: 0 })));
        assert.equal(response.status, 400);
        assert.equal(database.subscription.status, "active");
        assert.deepEqual(database.writes, []);
      });
    }
    await t.step("revoked receipt with a mismatched account token never reaches reconciliation", async () => {
      database.reset();
      database.subscription = existingSubscription();
      const response = await request(trustedChain.sign(testTransaction({ revocationReason: 0, appAccountToken: "22222222-2222-4222-8222-222222222222" })));
      assert.equal(response.status, 403);
      assert.deepEqual(database.rpcCalls, []);
      assert.deepEqual(database.writes, []);
    });
    await t.step("revocation persistence failure returns a retryable server error", async () => {
      database.reset();
      database.subscription = existingSubscription();
      database.failOperation = "rpc";
      const response = await request(trustedChain.sign(testTransaction({ revocationReason: 0 })));
      assert.equal(response.status, 500);
      assert.equal(database.subscription.status, "active");
    });

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
      "crossgrade in the same group stores and returns the verified product",
      async () => {
        database.reset();
        database.subscription = existingSubscription();
        const payload = testTransaction({
          transactionId: "200000000000003",
          productId: "com.mindfriend.premium.yearly",
        });
        const response = await request(trustedChain.sign(payload));
        assert.equal(response.status, 200);
        const body = await response.json();
        assert.equal(body.productId, "com.mindfriend.premium.yearly");
        assert.equal(body.billingPeriod, "annual");
        const write = database.writes.find((w) => w.table === "subscriptions");
        assert.equal(write?.data.product_id, "com.mindfriend.premium.yearly");
        assert.equal(write?.data.plan_type, "individual");
        assert.equal(write?.data.billing_period, "annual");
        assert.equal(write?.data.seats_total, 1);
        assert.equal(write?.data.last_transaction_id, payload.transactionId);
        assert.equal(database.profile.premium_badge, "annual_achiever");
      },
    );

    await t.step(
      "upgrade into a couples plan creates its family group",
      async () => {
        database.reset();
        database.subscription = existingSubscription();
        const response = await request(trustedChain.sign(testTransaction({
          transactionId: "200000000000004",
          productId: "com.mindfriend.couples.monthly",
        })));
        assert.equal(response.status, 200);
        const body = await response.json();
        assert.equal(body.productId, "com.mindfriend.couples.monthly");
        assert.equal(body.planType, "couples");
        assert.ok(body.familyId);
        const write = database.writes.find((w) => w.table === "subscriptions");
        assert.equal(write?.data.plan_type, "couples");
        assert.equal(write?.data.seats_total, 2);
      },
    );

    await t.step(
      "a newer transaction records when Apple charged it",
      async () => {
        database.reset();
        database.subscription = existingSubscription({
          last_transaction_purchased_at: new Date(Date.now() - 30 * 86_400_000).toISOString(),
        });
        const payload = testTransaction({ transactionId: "200000000000005" });
        const response = await request(trustedChain.sign(payload));
        assert.equal(response.status, 200);
        const write = database.writes.find((w) => w.table === "subscriptions");
        assert.equal(
          write?.data.last_transaction_purchased_at,
          new Date(payload.purchaseDate).toISOString(),
        );
      },
    );

    await t.step(
      "an older transaction cannot replace the stored product",
      async () => {
        database.reset();
        const stored = existingSubscription({
          product_id: "com.mindfriend.family.monthly",
          plan_type: "family",
          family_id: "test-family",
          is_family_admin: true,
          seats_total: 6,
          last_transaction_purchased_at: new Date(Date.now() - 3_600_000).toISOString(),
        });
        database.subscription = stored;
        const response = await request(trustedChain.sign(testTransaction({
          transactionId: "200000000000000",
          productId: "com.mindfriend.premium.monthly",
          purchaseDate: Date.now() - 2 * 86_400_000,
        })));
        assert.equal(response.status, 200);
        const body = await response.json();
        assert.equal(body.productId, "com.mindfriend.family.monthly");
        assert.equal(body.planType, "family");
        assert.equal(body.familyId, "test-family");
        assert.deepEqual(database.writes.filter((w) => w.table === "subscriptions"), []);
      },
    );

    for (const [productId, planType, seatsTotal, kept] of [
      ["com.mindfriend.couples.monthly", "couples", 2, ["member-early"]],
      ["com.mindfriend.premium.monthly", "individual", 1, []],
    ] as const) {
      await t.step(
        `moving a shared family plan to ${planType} releases the newest members first`,
        async () => {
          database.reset();
          database.subscription = existingSubscription({
            product_id: "com.mindfriend.family.monthly",
            plan_type: "family",
            family_id: "test-family",
            is_family_admin: true,
            seats_used: 3,
            seats_total: 6,
            last_transaction_purchased_at: new Date(Date.now() - 30 * 86_400_000).toISOString(),
          });
          database.familyMembers = [
            { id: "member-late", user_id: "user-late", joined_at: "2026-10-02T00:00:00Z" },
            { id: "member-early", user_id: "user-early", joined_at: "2026-10-01T00:00:00Z" },
          ];
          const response = await request(trustedChain.sign(testTransaction({
            transactionId: "200000000000006",
            productId,
          })));
          assert.equal(response.status, 200);
          assert.equal((await response.json()).planType, planType);
          assert.deepEqual(
            database.familyMembers.map((member) => member.id),
            kept,
          );
          assert.deepEqual(
            database.rpcCalls.map((call) => call.args),
            [
              { p_actor_id: callerId, p_member_id: "member-late" },
              ...(kept.length ? [] : [{ p_actor_id: callerId, p_member_id: "member-early" }]),
            ],
          );
          const write = database.writes.find((w) => w.table === "subscriptions");
          assert.equal(write?.data.seats_total, seatsTotal);
          assert.equal(database.subscription?.seats_used, seatsTotal);
        },
      );
    }

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

    for (const operation of ["upsert", "update"]) {
      await t.step(`subscription ${operation} failure cannot report success`, async () => {
        database.reset();
        database.failTable = "subscriptions";
        database.failOperation = operation;
        if (operation === "update") database.subscription = existingSubscription();
        const response = await request(trustedChain.sign(testTransaction({transactionId: "200000000000099"})));
        assert.equal(response.status, 500);
        assert.equal((await response.json()).valid, false);
        assert.equal(database.writes.filter((write) => ["profiles", "user_stats", "user_badges"].includes(write.table)).length, 0);
      });
    }

    for (const table of ["profiles", "user_stats"]) {
      await t.step(`${table} failure returns failure and a duplicate repairs missing entitlements`, async () => {
        database.reset();
        database.profile = { subscription_tier: "free", daily_ai_quota: 3, premium_badge: null };
        database.stats = { streak_shields_max: 1, recovery_attempts_max: 1 };
        database.failTable = table;
        database.failOperation = "update";
        const signed = trustedChain.sign(testTransaction());
        let response = await request(signed);
        assert.equal(response.status, 500);
        assert.equal((await response.json()).valid, false);
        database.failTable = "";
        response = await request(signed);
        assert.equal(response.status, 200);
        assert.equal((await response.json()).idempotent, true);
        assert.equal(database.profile.subscription_tier, "premium");
        assert.equal(database.stats.streak_shields_max, 3);
      });
    }

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
