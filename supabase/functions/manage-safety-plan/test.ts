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
const FUNCTION_URL = `${SUPABASE_URL}/functions/v1/manage-safety-plan`;

interface SafetyPlanResponse {
  success: boolean;
  data?: {
    id: string;
    version: number;
    payload: Record<string, unknown>;
    settings: {
      allow_ai_reference: boolean;
      pinned_to_quick_actions: boolean;
    };
  } | null;
  error?: { code: string; message: string } | null;
}

async function callManageSafetyPlan(
  token: string | null,
  body: Record<string, unknown>,
): Promise<{ status: number; data: SafetyPlanResponse }> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    apikey: SUPABASE_FUNCTIONS_KEY,
  };

  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  const response = await fetch(FUNCTION_URL, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });

  return {
    status: response.status,
    data: await response.json(),
  };
}

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
  });
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

async function resetSafetyPlan(
  supabase: ReturnType<typeof createClient<any>>,
  userId: string,
) {
  await supabase.from("safety_plans").delete().eq("user_id", userId);
  await supabase.from("safety_plan_cache").delete().eq("user_id", userId);
}

function buildPayload(overrides: Record<string, unknown> = {}) {
  return {
    warningSigns: [{ id: crypto.randomUUID(), text: "Overwhelmed" }],
    coping: [
      {
        id: crypto.randomUUID(),
        type: "custom",
        label: "Breathe slowly",
        category: "breathing",
      },
    ],
    contacts: [
      {
        id: crypto.randomUUID(),
        name: "Sam",
        phone: "+15555551234",
        relationship: "friend",
        preferredMethod: "text",
      },
    ],
    resources: [],
    environmentSteps: [{ id: crypto.randomUUID(), text: "Move to a safe room" }],
    anchors: [{ id: crypto.randomUUID(), text: "My family" }],
    ...overrides,
  };
}

Deno.test("manage-safety-plan returns 401 without auth", async () => {
  const response = await callManageSafetyPlan(null, { operation: "get" });
  assertEquals(response.status, 401);
  assertEquals(response.data.success, false);
  assertExists(response.data.error);
});

Deno.test("manage-safety-plan validates contact phone", async () => {
  const token = await getTestUserToken();
  const payload = buildPayload({
    contacts: [
      {
        id: crypto.randomUUID(),
        name: "Alex",
        phone: "5551234",
        relationship: "friend",
        preferredMethod: "call",
      },
    ],
  });

  const response = await callManageSafetyPlan(token, {
    operation: "create",
    payload,
  });

  assertEquals(response.status, 400);
  assertEquals(response.data.success, false);
  assertExists(response.data.error);
});

Deno.test("manage-safety-plan create/get/update/delete flow", async () => {
  const supabase = getServiceRoleClient();
  const token = await getTestUserToken();
  const userId = await getUserIdFromToken(supabase, token);

  await resetSafetyPlan(supabase, userId);

  const createResponse = await callManageSafetyPlan(token, {
    operation: "create",
    payload: buildPayload(),
  });

  assertEquals(createResponse.status, 200);
  assertEquals(createResponse.data.success, true);
  assertExists(createResponse.data.data);

  const getResponse = await callManageSafetyPlan(token, { operation: "get" });
  assertEquals(getResponse.status, 200);
  assertEquals(getResponse.data.success, true);
  assertExists(getResponse.data.data);

  const updateResponse = await callManageSafetyPlan(token, {
    operation: "update",
    payload: buildPayload({
      warningSigns: [{ id: crypto.randomUUID(), text: "Tense shoulders" }],
    }),
  });
  assertEquals(updateResponse.status, 200);
  assertEquals(updateResponse.data.success, true);
  assertExists(updateResponse.data.data);

  const settingsResponse = await callManageSafetyPlan(token, {
    operation: "update",
    settings: { allow_ai_reference: true },
  });
  assertEquals(settingsResponse.status, 200);
  assertEquals(settingsResponse.data.success, true);
  assertEquals(settingsResponse.data.data?.settings.allow_ai_reference, true);

  const deleteResponse = await callManageSafetyPlan(token, { operation: "delete" });
  assertEquals(deleteResponse.status, 200);
  assertEquals(deleteResponse.data.success, true);
});
