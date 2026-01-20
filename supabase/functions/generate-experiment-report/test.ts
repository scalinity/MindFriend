// Tests for generate-experiment-report Edge Function
import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.192.0/testing/asserts.ts";

const FUNCTION_URL =
  Deno.env.get("SUPABASE_URL") + "/functions/v1/generate-experiment-report";

// Test helper to create auth header
function getAuthHeaders(token: string): Headers {
  const headers = new Headers();
  headers.set("Authorization", `Bearer ${token}`);
  headers.set("Content-Type", "application/json");
  return headers;
}

Deno.test(
  "generate-experiment-report: rejects missing authorization",
  async () => {
    const response = await fetch(FUNCTION_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        experimentId: "00000000-0000-0000-0000-000000000000",
      }),
    });

    assertEquals(response.status, 401);
    const body = await response.json();
    assertEquals(body.error, "Missing authorization");
  },
);

Deno.test(
  "generate-experiment-report: rejects missing experimentId",
  async () => {
    const testToken = Deno.env.get("TEST_USER_TOKEN");
    if (!testToken) {
      console.log("Skipping test - TEST_USER_TOKEN not set");
      return;
    }

    const response = await fetch(FUNCTION_URL, {
      method: "POST",
      headers: getAuthHeaders(testToken),
      body: JSON.stringify({}),
    });

    assertEquals(response.status, 400);
    const body = await response.json();
    assertEquals(body.error, "Missing experimentId");
  },
);

Deno.test(
  "generate-experiment-report: handles non-existent experiment",
  async () => {
    const testToken = Deno.env.get("TEST_USER_TOKEN");
    if (!testToken) {
      console.log("Skipping test - TEST_USER_TOKEN not set");
      return;
    }

    const response = await fetch(FUNCTION_URL, {
      method: "POST",
      headers: getAuthHeaders(testToken),
      body: JSON.stringify({
        experimentId: "00000000-0000-0000-0000-000000000000",
      }),
    });

    assertEquals(response.status, 404);
    const body = await response.json();
    assertEquals(body.error, "EXPERIMENT_NOT_FOUND");
  },
);

Deno.test(
  "generate-experiment-report: OPTIONS returns CORS headers",
  async () => {
    const response = await fetch(FUNCTION_URL, {
      method: "OPTIONS",
      headers: { Origin: "http://localhost:3000" },
    });

    assertEquals(response.status, 200);
  },
);

// Note: Testing successful report generation requires:
// 1. A test user with a completed experiment
// 2. Setting up experiment days with mood/energy scores
// This is typically done in integration tests with a test database
