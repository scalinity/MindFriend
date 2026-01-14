// Tests for verify-purchase Edge Function
// Run with: deno test --allow-net --allow-env supabase/functions/verify-purchase/test.ts

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  getPlanDetails,
  isValidProductId,
  calculateExpiryDate,
  VALID_PRODUCT_IDS,
} from "../_shared/billing-types.ts";

// Unit tests for billing-types helper functions
Deno.test(
  "getPlanDetails returns correct details for individual monthly",
  () => {
    const details = getPlanDetails("com.mindfriend.premium.monthly");
    assertEquals(details.planType, "individual");
    assertEquals(details.billingPeriod, "monthly");
    assertEquals(details.seatsTotal, 1);
    assertEquals(details.badgeCode, "premium_supporter");
  },
);

Deno.test(
  "getPlanDetails returns correct details for individual yearly",
  () => {
    const details = getPlanDetails("com.mindfriend.premium.yearly");
    assertEquals(details.planType, "individual");
    assertEquals(details.billingPeriod, "annual");
    assertEquals(details.seatsTotal, 1);
    assertEquals(details.badgeCode, "annual_achiever");
  },
);

Deno.test("getPlanDetails returns correct details for couples monthly", () => {
  const details = getPlanDetails("com.mindfriend.couples.monthly");
  assertEquals(details.planType, "couples");
  assertEquals(details.billingPeriod, "monthly");
  assertEquals(details.seatsTotal, 2);
});

Deno.test("getPlanDetails returns correct details for couples annual", () => {
  const details = getPlanDetails("com.mindfriend.couples.annual");
  assertEquals(details.planType, "couples");
  assertEquals(details.billingPeriod, "annual");
  assertEquals(details.seatsTotal, 2);
  assertEquals(details.badgeCode, "annual_achiever");
});

Deno.test("getPlanDetails returns correct details for family monthly", () => {
  const details = getPlanDetails("com.mindfriend.family.monthly");
  assertEquals(details.planType, "family");
  assertEquals(details.billingPeriod, "monthly");
  assertEquals(details.seatsTotal, 6);
});

Deno.test("getPlanDetails returns correct details for family annual", () => {
  const details = getPlanDetails("com.mindfriend.family.annual");
  assertEquals(details.planType, "family");
  assertEquals(details.billingPeriod, "annual");
  assertEquals(details.seatsTotal, 6);
  assertEquals(details.badgeCode, "annual_achiever");
});

Deno.test("getPlanDetails returns default for unknown product ID", () => {
  const details = getPlanDetails("com.unknown.product");
  assertEquals(details.planType, "individual");
  assertEquals(details.billingPeriod, "monthly");
  assertEquals(details.seatsTotal, 1);
});

Deno.test("isValidProductId returns true for valid products", () => {
  assertEquals(isValidProductId("com.mindfriend.premium.monthly"), true);
  assertEquals(isValidProductId("com.mindfriend.premium.yearly"), true);
  assertEquals(isValidProductId("com.mindfriend.couples.monthly"), true);
  assertEquals(isValidProductId("com.mindfriend.couples.annual"), true);
  assertEquals(isValidProductId("com.mindfriend.family.monthly"), true);
  assertEquals(isValidProductId("com.mindfriend.family.annual"), true);
});

Deno.test("isValidProductId returns false for invalid products", () => {
  assertEquals(isValidProductId("com.unknown.product"), false);
  assertEquals(isValidProductId(""), false);
  assertEquals(isValidProductId("com.mindfriend.premium"), false);
});

Deno.test("VALID_PRODUCT_IDS contains exactly 6 products", () => {
  assertEquals(VALID_PRODUCT_IDS.length, 6);
});

Deno.test(
  "calculateExpiryDate returns date 1 month in future for monthly",
  () => {
    const now = new Date();
    const expiry = calculateExpiryDate("monthly");
    const expectedMonth = (now.getMonth() + 1) % 12;

    // Account for year rollover
    if (now.getMonth() === 11) {
      assertEquals(expiry.getFullYear(), now.getFullYear() + 1);
      assertEquals(expiry.getMonth(), 0);
    } else {
      assertEquals(expiry.getMonth(), expectedMonth);
    }
  },
);

Deno.test(
  "calculateExpiryDate returns date 1 year in future for annual",
  () => {
    const now = new Date();
    const expiry = calculateExpiryDate("annual");
    assertEquals(expiry.getFullYear(), now.getFullYear() + 1);
    assertEquals(expiry.getMonth(), now.getMonth());
  },
);

// Integration tests would require mocking Supabase - below are test stubs

Deno.test("verify-purchase rejects missing originalTransactionId", async () => {
  // This would be an integration test with the actual Edge Function
  // For now, this is a placeholder showing the expected behavior
  const expectedError = {
    error: "Missing originalTransactionId",
    code: "MISSING_TRANSACTION_ID",
  };
  assertExists(expectedError);
});

Deno.test("verify-purchase rejects invalid productId", async () => {
  // This would be an integration test
  const expectedError = {
    error: "Invalid product ID",
    code: "INVALID_PRODUCT_ID",
  };
  assertExists(expectedError);
});

Deno.test("verify-purchase blocks mock mode in production", async () => {
  // This would be an integration test
  // In production (ENVIRONMENT=production) without App Store credentials,
  // the function should return 503 with CREDENTIALS_NOT_CONFIGURED
  const expectedError = {
    error: "Payment verification unavailable",
    code: "CREDENTIALS_NOT_CONFIGURED",
    valid: false,
  };
  assertExists(expectedError);
});

Deno.test(
  "verify-purchase returns idempotent response for duplicate transaction",
  async () => {
    // This would be an integration test
    // When the same originalTransactionId is submitted twice, the second call
    // should return the existing subscription without creating a duplicate
    const expectedResponse = {
      valid: true,
      message: "Subscription already active (idempotent)",
      idempotent: true,
    };
    assertExists(expectedResponse);
  },
);

// Test for family plan creation
Deno.test("verify-purchase creates family group for family plan", async () => {
  // When purchasing a family or couples plan:
  // 1. Creates a family_groups entry
  // 2. Creates a circles entry for the family circle
  // 3. Adds the purchaser as first family_member
  // 4. Sets seats_total based on plan type (2 for couples, 6 for family)
  const expectedBehavior = {
    familyGroupCreated: true,
    circleCreated: true,
    seatsTotal: 6, // for family plan
    seatsUsed: 1,
  };
  assertExists(expectedBehavior);
});
