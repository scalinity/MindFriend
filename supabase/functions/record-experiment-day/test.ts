// Tests for record-experiment-day Edge Function
import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.192.0/testing/asserts.ts";

const FUNCTION_URL =
  Deno.env.get("SUPABASE_URL") + "/functions/v1/record-experiment-day";

// Test helper to create auth header
function getAuthHeaders(token: string): Headers {
  const headers = new Headers();
  headers.set("Authorization", `Bearer ${token}`);
  headers.set("Content-Type", "application/json");
  return headers;
}

Deno.test("record-experiment-day: rejects missing authorization", async () => {
  const response = await fetch(FUNCTION_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      experimentId: "00000000-0000-0000-0000-000000000000",
      dayIndex: 1,
      moodScore: 4,
      energyScore: 3,
    }),
  });

  assertEquals(response.status, 401);
  const body = await response.json();
  assertEquals(body.error, "Missing authorization");
});

Deno.test("record-experiment-day: rejects invalid UUID format", async () => {
  const testToken = Deno.env.get("TEST_USER_TOKEN");
  if (!testToken) {
    console.log("Skipping test - TEST_USER_TOKEN not set");
    return;
  }

  const response = await fetch(FUNCTION_URL, {
    method: "POST",
    headers: getAuthHeaders(testToken),
    body: JSON.stringify({
      experimentId: "not-a-valid-uuid",
      dayIndex: 1,
      moodScore: 4,
      energyScore: 3,
    }),
  });

  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.error, "INVALID_EXPERIMENT_ID");
});

Deno.test("record-experiment-day: rejects invalid day index", async () => {
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
      dayIndex: 8, // Invalid - max is 7
      moodScore: 4,
      energyScore: 3,
    }),
  });

  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.error, "INVALID_DAY_INDEX");
});

Deno.test("record-experiment-day: rejects invalid mood score", async () => {
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
      dayIndex: 1,
      moodScore: 6, // Invalid - max is 5
      energyScore: 3,
    }),
  });

  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.error, "INVALID_MOOD_SCORE");
});

Deno.test("record-experiment-day: rejects invalid energy score", async () => {
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
      dayIndex: 1,
      moodScore: 4,
      energyScore: 0, // Invalid - min is 1
    }),
  });

  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.error, "INVALID_ENERGY_SCORE");
});

Deno.test(
  "record-experiment-day: handles non-existent experiment",
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
        dayIndex: 1,
        moodScore: 4,
        energyScore: 3,
      }),
    });

    assertEquals(response.status, 404);
    const body = await response.json();
    assertEquals(body.error, "EXPERIMENT_NOT_FOUND");
  },
);

Deno.test("record-experiment-day: OPTIONS returns CORS headers", async () => {
  const response = await fetch(FUNCTION_URL, {
    method: "OPTIONS",
    headers: { Origin: "http://localhost:3000" },
  });

  assertEquals(response.status, 200);
});
