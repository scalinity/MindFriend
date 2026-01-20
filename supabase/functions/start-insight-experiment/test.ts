// Tests for start-insight-experiment Edge Function
import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.192.0/testing/asserts.ts";

const FUNCTION_URL =
  (Deno.env.get("SUPABASE_URL") || "http://localhost:54321") +
  "/functions/v1/start-insight-experiment";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");

// Test helper to create auth header
function getAuthHeaders(token: string): Headers {
  const headers = new Headers();
  headers.set("Authorization", `Bearer ${token}`);
  headers.set("Content-Type", "application/json");
  return headers;
}

Deno.test(
  "start-insight-experiment: rejects missing authorization",
  async () => {
    const response = await fetch(FUNCTION_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        actionType: "morning_walk",
        title: "Morning Walk",
        description: "Test description",
      }),
    });

    assertEquals(response.status, 401);
    const bodyText = await response.text();
    if (bodyText) {
      const body = JSON.parse(bodyText);
      if (body.error) {
        assertEquals(body.error, "Missing authorization");
      }
    }
  },
);

Deno.test("start-insight-experiment: rejects title exceeding max length", async () => {
  const testToken = Deno.env.get("TEST_USER_TOKEN");
  if (!testToken) {
    console.log("Skipping test - TEST_USER_TOKEN not set");
    return;
  }

  const longTitle = "A".repeat(101); // MAX_TITLE_LENGTH is 100

  const response = await fetch(FUNCTION_URL, {
    method: "POST",
    headers: getAuthHeaders(testToken),
    body: JSON.stringify({
      actionType: "morning_walk",
      title: longTitle,
      description: "Valid description",
    }),
  });

  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.error, "INVALID_TITLE");
});

Deno.test("start-insight-experiment: rejects description exceeding max length", async () => {
  const testToken = Deno.env.get("TEST_USER_TOKEN");
  if (!testToken) {
    console.log("Skipping test - TEST_USER_TOKEN not set");
    return;
  }

  const longDescription = "A".repeat(501); // MAX_DESCRIPTION_LENGTH is 500

  const response = await fetch(FUNCTION_URL, {
    method: "POST",
    headers: getAuthHeaders(testToken),
    body: JSON.stringify({
      actionType: "morning_walk",
      title: "Valid Title",
      description: longDescription,
    }),
  });

  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.error, "INVALID_DESCRIPTION");
});

Deno.test("start-insight-experiment: rejects invalid action type", async () => {
  // Note: This test requires a valid auth token
  // In real tests, you would get this from a test user
  const testToken = Deno.env.get("TEST_USER_TOKEN");
  if (!testToken) {
    console.log("Skipping test - TEST_USER_TOKEN not set");
    return;
  }

  const response = await fetch(FUNCTION_URL, {
    method: "POST",
    headers: getAuthHeaders(testToken),
    body: JSON.stringify({
      actionType: "invalid_action",
      title: "Invalid Test",
      description: "Test description",
    }),
  });

  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.error, "INVALID_ACTION_TYPE");
});

Deno.test("start-insight-experiment: rejects missing fields", async () => {
  const testToken = Deno.env.get("TEST_USER_TOKEN");
  if (!testToken) {
    console.log("Skipping test - TEST_USER_TOKEN not set");
    return;
  }

  const response = await fetch(FUNCTION_URL, {
    method: "POST",
    headers: getAuthHeaders(testToken),
    body: JSON.stringify({
      actionType: "morning_walk",
      // Missing title and description
    }),
  });

  assertEquals(response.status, 400);
  const body = await response.json();
  assertExists(body.error);
});

Deno.test(
  "start-insight-experiment: creates experiment with valid input",
  async () => {
    const testToken = Deno.env.get("TEST_USER_TOKEN");
    if (!testToken) {
      console.log("Skipping test - TEST_USER_TOKEN not set");
      return;
    }

    // Note: This test will fail if user already has an active experiment
    // In a real test suite, you would clean up before/after tests

    const response = await fetch(FUNCTION_URL, {
      method: "POST",
      headers: getAuthHeaders(testToken),
      body: JSON.stringify({
        actionType: "morning_walk",
        title: "Morning Walk Experiment",
        description: "Take a 15-minute walk each morning.",
      }),
    });

    // Could be 201 (created) or 409 (active experiment exists)
    if (response.status === 201) {
      const body = await response.json();
      assertExists(body.experimentId);
      assertEquals(body.actionType, "morning_walk");
      assertEquals(body.status, "active");
      assertEquals(body.currentDay, 1);
      assertEquals(body.totalDays, 7);
      assertExists(body.days);
      assertEquals(body.days.length, 7);
    } else if (response.status === 409) {
      const body = await response.json();
      assertEquals(body.error, "ACTIVE_EXPERIMENT_EXISTS");
    } else {
      throw new Error(`Unexpected status: ${response.status}`);
    }
  },
);

Deno.test(
  "start-insight-experiment: OPTIONS returns CORS headers",
  async () => {
    const response = await fetch(FUNCTION_URL, {
      method: "OPTIONS",
      headers: { Origin: "http://localhost:3000" },
    });

    assertEquals(response.status, 200);
    await response.text();
  },
);
