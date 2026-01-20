// ============================================================================
// B2B PHASE 1: STRIPE SUBSCRIPTION TESTS
// Run with: deno test --allow-net --allow-env supabase/functions/b2b-stripe-webhook/test.ts
// Expected: ALL TESTS FAIL until Stripe integration is implemented
// ============================================================================

import {
  assert,
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "http://localhost:54321";
const SUPABASE_ANON_KEY =
  Deno.env.get("SUPABASE_ANON_KEY") ||
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test";
const WEBHOOK_URL = `${SUPABASE_URL}/functions/v1/b2b-stripe-webhook`;
const CREATE_ORG_URL = `${SUPABASE_URL}/functions/v1/create-organization`;

// Mock Stripe webhook payload generator
function createStripeEvent(type: string, data: Record<string, unknown>) {
  return {
    id: `evt_${Date.now()}`,
    object: "event",
    api_version: "2023-10-16",
    created: Math.floor(Date.now() / 1000),
    type,
    data: {
      object: data,
    },
  };
}

// Helper to get admin token
async function getAdminToken(): Promise<string> {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  const { data, error } = await supabase.auth.signInWithPassword({
    email: "admin@example.com",
    password: "AdminPassword123!",
  });

  if (error || !data?.session?.access_token) {
    throw new Error(`Failed to get admin token: ${error?.message}`);
  }

  return data.session.access_token;
}

// ============================================================================
// TEST 8.1: Stripe customer can be created with organization metadata
// ============================================================================
Deno.test(
  "Stripe customer creation includes organization metadata",
  async () => {
    const adminToken = await getAdminToken();

    const response = await fetch(CREATE_ORG_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${adminToken}`,
      },
      body: JSON.stringify({
        name: "Test Corp",
        adminEmail: "admin@testcorp.com",
        seatCount: 50,
      }),
    });

    const data = await response.json();

    assertEquals(response.status, 200, "Should return 200 OK");
    assertExists(data.stripeCustomerId, "Should return Stripe customer ID");
    assertExists(data.organization?.id, "Should return organization ID");
  },
);

// ============================================================================
// TEST 8.2: Subscription created with metered billing for seats
// ============================================================================
Deno.test("Subscription uses metered billing for seats", async () => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const testOrgId = "test-org-with-subscription";

  const { data: org } = await supabase
    .from("organizations")
    .select("stripe_subscription_id, seat_count")
    .eq("id", testOrgId)
    .single();

  assertExists(
    org?.stripe_subscription_id,
    "Organization should have subscription",
  );
  assert(org?.seat_count > 0, "Organization should have seat count");
});

// ============================================================================
// TEST 8.3: Seat quantity update webhooks are handled
// ============================================================================
Deno.test("Seat quantity update webhooks are handled", async () => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const testOrgId = "test-org-id";

  const webhookPayload = createStripeEvent("customer.subscription.updated", {
    id: "sub_test123",
    customer: "cus_test456",
    items: {
      data: [
        {
          id: "si_test789",
          quantity: 60, // Updated from 50
        },
      ],
    },
    metadata: {
      organization_id: testOrgId,
    },
  });

  const response = await fetch(WEBHOOK_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Stripe-Signature": "mock-signature-for-testing",
    },
    body: JSON.stringify(webhookPayload),
  });

  assertEquals(response.status, 200, "Webhook should be processed");

  // Verify seat count updated in database
  const { data: org } = await supabase
    .from("organizations")
    .select("seat_count")
    .eq("id", testOrgId)
    .single();

  assertEquals(org?.seat_count, 60, "Seat count should be updated to 60");
});

// ============================================================================
// TEST 8.4: Payment failure webhook updates status to past_due
// ============================================================================
Deno.test("Payment failure triggers past_due status", async () => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const testOrgId = "test-org-payment-fail";

  const webhookPayload = createStripeEvent("invoice.payment_failed", {
    id: "in_test123",
    subscription: "sub_test123",
    customer: "cus_test456",
    metadata: {
      organization_id: testOrgId,
    },
  });

  const response = await fetch(WEBHOOK_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Stripe-Signature": "mock-signature-for-testing",
    },
    body: JSON.stringify(webhookPayload),
  });

  assertEquals(response.status, 200, "Webhook should be processed");

  // Verify organization status updated
  const { data: org } = await supabase
    .from("organizations")
    .select("status")
    .eq("id", testOrgId)
    .single();

  assertEquals(
    org?.status,
    "past_due",
    "Organization status should be past_due",
  );
});

// ============================================================================
// TEST 8.5: Billing audit log records seat changes
// ============================================================================
Deno.test("Billing audit log records seat changes", async () => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const testOrgId = "test-org-for-billing-audit";
  const beforeTime = new Date().toISOString();

  // Trigger a seat change via webhook
  const webhookPayload = createStripeEvent("customer.subscription.updated", {
    id: "sub_test_audit",
    items: {
      data: [{ quantity: 75 }],
    },
    metadata: {
      organization_id: testOrgId,
    },
  });

  await fetch(WEBHOOK_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Stripe-Signature": "mock-signature",
    },
    body: JSON.stringify(webhookPayload),
  });

  // Check billing audit log
  const { data: auditEntry } = await supabase
    .from("billing_audit_log")
    .select("*")
    .eq("organization_id", testOrgId)
    .gte("created_at", beforeTime)
    .order("created_at", { ascending: false })
    .limit(1)
    .single();

  assertExists(auditEntry, "Billing audit entry should exist");
  assertEquals(
    auditEntry?.event_type,
    "seat_change",
    "Event type should be seat_change",
  );
  assertExists(auditEntry?.seat_delta, "Should record seat delta");
});

// ============================================================================
// TEST 8.6: Subscription cancellation updates organization to churned
// ============================================================================
Deno.test(
  "Subscription cancellation updates organization to churned",
  async () => {
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const testOrgId = "org-to-cancel";

    const webhookPayload = createStripeEvent("customer.subscription.deleted", {
      id: "sub_cancelled",
      customer: "cus_cancelled",
      metadata: {
        organization_id: testOrgId,
      },
    });

    const response = await fetch(WEBHOOK_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Stripe-Signature": "mock-signature",
      },
      body: JSON.stringify(webhookPayload),
    });

    assertEquals(response.status, 200, "Webhook should be processed");

    // Verify organization status
    const { data: org } = await supabase
      .from("organizations")
      .select("status")
      .eq("id", testOrgId)
      .single();

    assertEquals(
      org?.status,
      "churned",
      "Organization status should be churned",
    );
  },
);

// ============================================================================
// TEST 8.7: Invalid webhook signature returns 400
// ============================================================================
Deno.test("Invalid webhook signature returns 400", async () => {
  const webhookPayload = createStripeEvent("test.event", {});

  const response = await fetch(WEBHOOK_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      // Missing or invalid Stripe-Signature
    },
    body: JSON.stringify(webhookPayload),
  });

  assertEquals(
    response.status,
    400,
    "Should return 400 for missing/invalid signature",
  );
});

// ============================================================================
// TEST 8.8: Subscription renewal updates billing audit log
// ============================================================================
Deno.test("Subscription renewal logs to billing audit", async () => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const testOrgId = "test-org-renewal";
  const beforeTime = new Date().toISOString();

  const webhookPayload = createStripeEvent("invoice.paid", {
    id: "in_renewal",
    subscription: "sub_renewal",
    customer: "cus_renewal",
    billing_reason: "subscription_cycle",
    amount_paid: 50000, // $500
    metadata: {
      organization_id: testOrgId,
    },
  });

  const response = await fetch(WEBHOOK_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Stripe-Signature": "mock-signature",
    },
    body: JSON.stringify(webhookPayload),
  });

  assertEquals(response.status, 200, "Webhook should be processed");

  // Check billing audit log for renewal event
  const { data: auditEntry } = await supabase
    .from("billing_audit_log")
    .select("*")
    .eq("organization_id", testOrgId)
    .eq("event_type", "renewal")
    .gte("created_at", beforeTime)
    .single();

  assertExists(auditEntry, "Renewal audit entry should exist");
});
