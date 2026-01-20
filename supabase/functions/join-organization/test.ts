// ============================================================================
// B2B PHASE 1: JOIN ORGANIZATION TESTS
// Run with: deno test --allow-net --allow-env supabase/functions/join-organization/test.ts
// Expected: ALL TESTS FAIL until Edge Function is implemented
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
const FUNCTION_URL = `${SUPABASE_URL}/functions/v1/join-organization`;

interface JoinOrganizationResponse {
  success: boolean;
  member?: {
    id: string;
    organization_id: string;
    user_id: string;
    joined_at: string;
  };
  subscription?: {
    tier: string;
    access_source: string;
  };
  error?: string;
  errorCode?: string;
}

async function callJoinOrganization(
  inviteCode: string,
  token: string,
): Promise<{ status: number; data: JoinOrganizationResponse }> {
  const response = await fetch(FUNCTION_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ inviteCode }),
  });

  return {
    status: response.status,
    data: await response.json(),
  };
}

// Helper to get test user token
async function getTestUserToken(): Promise<string> {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  const { data, error } = await supabase.auth.signInWithPassword({
    email: "test@example.com",
    password: "TestPassword123!",
  });

  if (error || !data?.session?.access_token) {
    throw new Error(`Failed to get test token: ${error?.message}`);
  }

  return data.session.access_token;
}

// ============================================================================
// TEST 4.1: Join organization creates organization_members record
// ============================================================================
Deno.test("join-organization creates organization_members record", async () => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const testToken = await getTestUserToken();
  const testInviteCode = "JOINTEST123";

  const response = await callJoinOrganization(testInviteCode, testToken);

  assertEquals(response.status, 200, "Should return 200 OK");
  assertEquals(response.data.success, true, "Should indicate success");
  assertExists(response.data.member, "Should return member data");
  assertExists(response.data.member?.id, "Member should have ID");
  assertExists(response.data.member?.joined_at, "Member should have joined_at");

  // Verify record exists in database
  if (response.data.member?.id) {
    const { data: member } = await supabase
      .from("organization_members")
      .select("*")
      .eq("id", response.data.member.id)
      .single();

    assertExists(member, "Member record should exist in database");
  }
});

// ============================================================================
// TEST 4.2: Join organization grants premium subscription
// ============================================================================
Deno.test(
  "join-organization grants premium subscription with organization_sponsored source",
  async () => {
    const testToken = await getTestUserToken();
    const testInviteCode = "PREMIUMTEST";

    const response = await callJoinOrganization(testInviteCode, testToken);

    assertEquals(response.status, 200, "Should return 200 OK");
    assertExists(response.data.subscription, "Should return subscription data");
    assertEquals(
      response.data.subscription?.tier,
      "premium",
      "Subscription tier should be premium",
    );
    assertEquals(
      response.data.subscription?.access_source,
      "organization_sponsored",
      "Access source should be organization_sponsored",
    );
  },
);

// ============================================================================
// TEST 4.3: Join organization prevents duplicate membership
// ============================================================================
Deno.test("join-organization prevents duplicate membership", async () => {
  const testToken = await getTestUserToken();
  const testInviteCode = "DUPLICATETEST";

  // First join should succeed
  const response1 = await callJoinOrganization(testInviteCode, testToken);
  assertEquals(response1.status, 200, "First join should succeed");

  // Second join should fail
  const response2 = await callJoinOrganization(testInviteCode, testToken);
  assertEquals(response2.status, 400, "Second join should fail");
  assertEquals(
    response2.data.errorCode,
    "ALREADY_MEMBER",
    "Should return ALREADY_MEMBER error code",
  );
});

// ============================================================================
// TEST 4.4: Join organization links user to correct organization
// ============================================================================
Deno.test("join-organization links user to correct organization", async () => {
  const testToken = await getTestUserToken();
  const testInviteCode = "LINKTEST123";
  // This would need to be set up in test data
  const expectedOrgId = "expected-organization-uuid";

  const response = await callJoinOrganization(testInviteCode, testToken);

  assertEquals(response.status, 200, "Should return 200 OK");
  assertEquals(
    response.data.member?.organization_id,
    expectedOrgId,
    "Member should be linked to correct organization",
  );
});

// ============================================================================
// TEST 4.5: Join organization logs audit event
// ============================================================================
Deno.test(
  "join-organization logs audit event with event_type member_joined",
  async () => {
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const testToken = await getTestUserToken();
    const testInviteCode = "AUDITLOGTEST";

    const beforeTime = new Date().toISOString();

    const response = await callJoinOrganization(testInviteCode, testToken);
    assertEquals(response.status, 200, "Should return 200 OK");

    // Check audit log entry was created
    const { data: auditEntry } = await supabase
      .from("audit_log")
      .select("*")
      .eq("event_type", "member_joined")
      .gte("created_at", beforeTime)
      .order("created_at", { ascending: false })
      .limit(1)
      .single();

    assertExists(auditEntry, "Audit log entry should exist");
    assertEquals(
      auditEntry?.event_type,
      "member_joined",
      "Event type should be member_joined",
    );
    assertExists(auditEntry?.metadata, "Audit entry should have metadata");
  },
);

// ============================================================================
// TEST 4.6: Join organization fails when org is at seat capacity
// ============================================================================
Deno.test(
  "join-organization fails when organization is at seat capacity",
  async () => {
    const testToken = await getTestUserToken();
    const testInviteCode = "FULLORGCODE";

    const response = await callJoinOrganization(testInviteCode, testToken);

    assertEquals(response.status, 400, "Should return 400 Bad Request");
    assertEquals(
      response.data.errorCode,
      "SEAT_LIMIT_REACHED",
      "Should return SEAT_LIMIT_REACHED error code",
    );
  },
);

// ============================================================================
// TEST 4.7: Join organization increments seats_used counter
// ============================================================================
Deno.test(
  "join-organization increments organization.seats_used counter",
  async () => {
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const testToken = await getTestUserToken();
    const testInviteCode = "SEATCOUNTTEST";
    const testOrgId = "test-org-for-seat-count";

    // Get initial seats_used
    const { data: beforeOrg } = await supabase
      .from("organizations")
      .select("seats_used")
      .eq("id", testOrgId)
      .single();

    const initialSeats = beforeOrg?.seats_used ?? 0;

    // Join organization
    await callJoinOrganization(testInviteCode, testToken);

    // Check seats_used incremented
    const { data: afterOrg } = await supabase
      .from("organizations")
      .select("seats_used")
      .eq("id", testOrgId)
      .single();

    assertEquals(
      afterOrg?.seats_used,
      initialSeats + 1,
      "seats_used should increment by 1",
    );
  },
);

// ============================================================================
// TEST 4.8: Missing authorization returns 401
// ============================================================================
Deno.test("join-organization returns 401 without auth", async () => {
  const response = await fetch(FUNCTION_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ inviteCode: "ANYCODE" }),
  });

  assertEquals(response.status, 401, "Should return 401 Unauthorized");
  await response.json(); // Consume response body to avoid resource leak
});

// ============================================================================
// TEST 4.9: Invalid HTTP method returns 405
// ============================================================================
Deno.test("join-organization returns 405 for GET request", async () => {
  const testToken = await getTestUserToken();

  const response = await fetch(FUNCTION_URL, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${testToken}`,
    },
  });

  assertEquals(response.status, 405, "Should return 405 Method Not Allowed");
  await response.json(); // Consume response body to avoid resource leak
});
