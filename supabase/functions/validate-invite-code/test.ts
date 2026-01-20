// ============================================================================
// B2B PHASE 1: INVITE CODE VALIDATION TESTS
// Run with: deno test --allow-net --allow-env supabase/functions/validate-invite-code/test.ts
// Expected: ALL TESTS FAIL until Edge Function is implemented
// ============================================================================

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
const FUNCTION_URL = `${SUPABASE_URL}/functions/v1/validate-invite-code`;

interface InviteValidationResponse {
  valid: boolean;
  organizationId?: string;
  organizationName?: string;
  error?: string;
  errorCode?: string;
}

async function callValidateInvite(
  code: string,
  token: string,
): Promise<{ status: number; data: InviteValidationResponse }> {
  const response = await fetch(FUNCTION_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
      apikey: SUPABASE_FUNCTIONS_KEY,
    },
    body: JSON.stringify({ inviteCode: code }),
  });

  return {
    status: response.status,
    data: await response.json(),
  };
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
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

// ============================================================================
// TEST 3.1: Valid invite code returns organizationId
// ============================================================================
Deno.test(
  "validate-invite-code returns organizationId for valid code",
  async () => {
    const testToken = await getTestUserToken();
    const testCode = "VALIDCODE123";

    const response = await callValidateInvite(testCode, testToken);

    assertEquals(response.status, 200, "Should return 200 OK");
    assertEquals(response.data.valid, true, "Should indicate valid");
    assertExists(response.data.organizationId, "Should return organizationId");
    assertExists(
      response.data.organizationName,
      "Should return organizationName",
    );
  },
);

// ============================================================================
// TEST 3.2: Expired invite code returns error
// ============================================================================
Deno.test("validate-invite-code returns error for expired code", async () => {
  const testToken = await getTestUserToken();
  const expiredCode = "EXPIREDCODE";

  const response = await callValidateInvite(expiredCode, testToken);

  assertEquals(response.status, 400, "Should return 400 Bad Request");
  assertEquals(response.data.valid, false, "Should indicate invalid");
  assertEquals(
    response.data.errorCode,
    "INVITE_EXPIRED",
    "Should return INVITE_EXPIRED error code",
  );
});

// ============================================================================
// TEST 3.3: Max uses exceeded returns error
// ============================================================================
Deno.test(
  "validate-invite-code returns error when max_uses exceeded",
  async () => {
    const testToken = await getTestUserToken();
    const maxedOutCode = "MAXEDOUTCODE";

    const response = await callValidateInvite(maxedOutCode, testToken);

    assertEquals(response.status, 400, "Should return 400 Bad Request");
    assertEquals(response.data.valid, false, "Should indicate invalid");
    assertEquals(
      response.data.errorCode,
      "MAX_USES_EXCEEDED",
      "Should return MAX_USES_EXCEEDED error code",
    );
  },
);

// ============================================================================
// TEST 3.4: Validation increments uses counter
// ============================================================================
Deno.test("validate-invite-code increments uses_count on success", async () => {
  const supabase = getServiceRoleClient();
  const testToken = await getTestUserToken();
  const testCode = "COUNTERCODE";

  // Get initial uses count
  const { data: beforeData } = await supabase
    .from("organization_invites")
    .select("uses_count")
    .eq("invite_code", testCode)
    .single();

  const initialCount = beforeData?.uses_count ?? 0;

  // Validate the code
  await callValidateInvite(testCode, testToken);

  // Check uses count incremented
  const { data: afterData } = await supabase
    .from("organization_invites")
    .select("uses_count")
    .eq("invite_code", testCode)
    .single();

  assertEquals(
    afterData?.uses_count,
    initialCount + 1,
    "uses_count should increment by 1",
  );
});

// ============================================================================
// TEST 3.5: Duplicate invite codes are rejected (UNIQUE constraint)
// ============================================================================
Deno.test("organization_invites rejects duplicate invite_code", async () => {
  const supabase = getServiceRoleClient();
  const uniqueCode = `UNIQUE${Date.now()}`;
  const organizationId = "00000000-0000-0000-0000-000000000001";
  const adminId = "00000000-0000-0000-0000-000000000011";

  // First insert should succeed
  const { error: firstError } = await supabase
    .from("organization_invites")
    .insert({
      organization_id: organizationId,
      invite_code: uniqueCode,
      max_uses: 100,
      expires_at: new Date(Date.now() + 86400000).toISOString(),
      created_by_admin_id: adminId,
    });

  // Second insert with same code should fail
  const { error: secondError } = await supabase
    .from("organization_invites")
    .insert({
      organization_id: organizationId,
      invite_code: uniqueCode, // Same code
      max_uses: 100,
      expires_at: new Date(Date.now() + 86400000).toISOString(),
      created_by_admin_id: adminId,
    });

  assertExists(secondError, "Should have error on duplicate code");
  assertEquals(
    secondError?.code,
    "23505", // PostgreSQL unique violation
    "Should be unique constraint violation",
  );

  // Cleanup
  await supabase
    .from("organization_invites")
    .delete()
    .eq("invite_code", uniqueCode);
});

// ============================================================================
// TEST 3.6: Non-existent invite code returns error
// ============================================================================
Deno.test(
  "validate-invite-code returns error for non-existent code",
  async () => {
    const testToken = await getTestUserToken();
    const fakeCode = "DOESNOTEXIST" + Date.now();

    const response = await callValidateInvite(fakeCode, testToken);

    assertEquals(response.status, 404, "Should return 404 Not Found");
    assertEquals(response.data.valid, false, "Should indicate invalid");
    assertEquals(
      response.data.errorCode,
      "INVITE_NOT_FOUND",
      "Should return INVITE_NOT_FOUND error code",
    );
  },
);

// ============================================================================
// TEST 3.7: Deactivated invite code returns error
// ============================================================================
Deno.test(
  "validate-invite-code returns error for deactivated code",
  async () => {
    const testToken = await getTestUserToken();
    const deactivatedCode = "DEACTIVATED";

    const response = await callValidateInvite(deactivatedCode, testToken);

    assertEquals(response.status, 400, "Should return 400 Bad Request");
    assertEquals(response.data.valid, false, "Should indicate invalid");
    assertEquals(
      response.data.errorCode,
      "INVITE_DEACTIVATED",
      "Should return INVITE_DEACTIVATED error code",
    );
  },
);

// ============================================================================
// TEST 3.8: Missing authorization returns 401
// ============================================================================
Deno.test("validate-invite-code returns 401 without auth", async () => {
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
