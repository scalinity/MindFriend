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
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "http://localhost:54321";
const SUPABASE_ANON_KEY =
  Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ||
  Deno.env.get("SUPABASE_ANON_KEY_REMOTE") ||
  Deno.env.get("SUPABASE_ANON_KEY") ||
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const SUPABASE_AUTH_KEY = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") || SUPABASE_ANON_KEY;
const SUPABASE_FUNCTIONS_KEY =
  Deno.env.get("SUPABASE_FUNCTIONS_KEY") ||
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ||
  Deno.env.get("SUPABASE_ANON_KEY_REMOTE") ||
  Deno.env.get("SUPABASE_ANON_KEY") ||
  SUPABASE_AUTH_KEY;
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
      apikey: SUPABASE_FUNCTIONS_KEY,
    },
    body: JSON.stringify({ inviteCode }),
  });

  const data = await response.json();
  if (response.status >= 400) {
    console.log(`Request failed (${response.status}):`, JSON.stringify(data));
  }
  return { status: response.status, data };
}

// Helper to get test user token
async function getTestUserToken(): Promise<string> {
  const email = Deno.env.get("SUPABASE_TEST_EMAIL") ?? "test@example.com";
  const password = Deno.env.get("SUPABASE_TEST_PASSWORD") ?? "TestPassword123!";

  const response = await fetch(
    `${SUPABASE_URL}/auth/v1/token?grant_type=password`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: SUPABASE_AUTH_KEY,
      },
      body: JSON.stringify({ email, password }),
    },
  );

  const data = await response.json();
  if (!response.ok || !data?.access_token) {
    throw new Error(`Failed to get test token: ${data?.message || response.status}`);
  }

  return data.access_token;
}

function getServiceRoleClient() {
  if (!SUPABASE_SERVICE_ROLE_KEY) {
    throw new Error("Missing SUPABASE_SERVICE_ROLE_KEY for test setup");
  }
  return createClient<any>(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  }) as ReturnType<typeof createClient<any>>;
}

async function getUserIdFromToken(
  supabase: ReturnType<typeof createClient<any>>,
  token: string,
): Promise<string> {
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data?.user?.id) {
    throw new Error(`Failed to fetch user: ${error?.message || "unknown error"}`);
  }
  return data.user.id;
}

async function resetOrganizationState(
  supabase: ReturnType<typeof createClient<any>>,
  token: string,
  inviteCode: string,
  options: { seatsUsed?: number } = {},
): Promise<{ organizationId: string; seatCount: number }> {
  const userId = await getUserIdFromToken(supabase, token);
  const { data: invite, error: inviteError } = await supabase
    .from("organization_invites")
    .select("organization_id")
    .eq("invite_code", inviteCode)
    .single();

  if (inviteError || !invite) {
    throw new Error(`Failed to fetch invite ${inviteCode}: ${inviteError?.message}`);
  }

  await supabase
    .from("organization_members")
    .delete()
    .eq("organization_id", invite.organization_id)
    .eq("user_id", userId);

  await supabase
    .from("subscriptions")
    .delete()
    .eq("user_id", userId)
    .eq("organization_id", invite.organization_id);

  await supabase
    .from("organization_invites")
    .update({ uses_count: 0 })
    .eq("invite_code", inviteCode);

  if (options.seatsUsed !== undefined) {
    await supabase
      .from("organizations")
      .update({ seats_used: options.seatsUsed })
      .eq("id", invite.organization_id);
  }

  const { data: organization } = await supabase
    .from("organizations")
    .select("seat_count")
    .eq("id", invite.organization_id)
    .single();

  return {
    organizationId: invite.organization_id,
    seatCount: organization?.seat_count ?? 0,
  };
}

// ============================================================================
// TEST 4.1: Join organization creates organization_members record
// ============================================================================
Deno.test("join-organization creates organization_members record", async () => {
  const supabase = getServiceRoleClient();
  const testToken = await getTestUserToken();
  const testInviteCode = "JOINTEST123";

  await resetOrganizationState(supabase, testToken, testInviteCode, { seatsUsed: 0 });

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
    const supabase = getServiceRoleClient();

    await resetOrganizationState(supabase, testToken, testInviteCode, { seatsUsed: 0 });

    const response = await callJoinOrganization(testInviteCode, testToken);

    assertEquals(response.status, 200, "Should return 200 OK");
    assertExists(response.data.subscription, "Should return subscription data");
    assertEquals(
      response.data.subscription?.tier,
      "organization",
      "Subscription tier should be organization",
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
  const supabase = getServiceRoleClient();

  await resetOrganizationState(supabase, testToken, testInviteCode, { seatsUsed: 0 });

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
  const expectedOrgId = "00000000-0000-0000-0000-000000000002";
  const supabase = getServiceRoleClient();

  await resetOrganizationState(supabase, testToken, testInviteCode, { seatsUsed: 0 });

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
    const supabase = getServiceRoleClient();
    const testToken = await getTestUserToken();
    const testInviteCode = "AUDITLOGTEST";

    await resetOrganizationState(supabase, testToken, testInviteCode, { seatsUsed: 0 });

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
    const supabase = getServiceRoleClient();

    const { organizationId, seatCount } = await resetOrganizationState(
      supabase,
      testToken,
      testInviteCode,
    );

    await supabase
      .from("organizations")
      .update({ seats_used: seatCount })
      .eq("id", organizationId);

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
    const supabase = getServiceRoleClient();
    const testToken = await getTestUserToken();
    const testInviteCode = "SEATCOUNTTEST";
    const testOrgId = "00000000-0000-0000-0000-000000000004";

    await resetOrganizationState(supabase, testToken, testInviteCode, { seatsUsed: 0 });

    await supabase
      .from("organizations")
      .update({ seats_used: 2 })
      .eq("id", testOrgId);

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

    const afterSeats = afterOrg?.seats_used ?? 0;
    assertEquals(afterSeats, initialSeats + 1, "seats_used should increment by 1");
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
      apikey: SUPABASE_FUNCTIONS_KEY,
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
      apikey: SUPABASE_FUNCTIONS_KEY,
    },
  });

  assertEquals(response.status, 405, "Should return 405 Method Not Allowed");
  await response.json(); // Consume response body to avoid resource leak
});
