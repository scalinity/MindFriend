// Tests for update-companion-memory Edge Function
import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.192.0/testing/asserts.ts";

const BASE_URL = Deno.env.get("SUPABASE_URL") || "http://localhost:54321";
const TEST_JWT = Deno.env.get("TEST_USER_JWT") || "";

const VALID_CATEGORIES = [
  "boundaries",
  "preferences",
  "triggers",
  "avoid_topics",
  "positive_reinforcement",
  "life_context",
];

Deno.test("update-companion-memory - returns 401 without auth", async () => {
  const response = await fetch(
    `${BASE_URL}/functions/v1/update-companion-memory`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        action: "memory",
        category: "preferences",
        content: "Test memory",
      }),
    },
  );

  assertEquals(response.status, 401);
});

Deno.test(
  "update-companion-memory - returns 400 for invalid category",
  async () => {
    if (!TEST_JWT) {
      console.log("Skipping test - no TEST_USER_JWT provided");
      return;
    }

    const response = await fetch(
      `${BASE_URL}/functions/v1/update-companion-memory`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${TEST_JWT}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          action: "memory",
          category: "invalid_category",
          content: "Test memory",
        }),
      },
    );

    assertEquals(response.status, 400);
    const body = await response.json();
    assertEquals(body.code, "BAD_REQUEST");
  },
);

Deno.test(
  "update-companion-memory - returns 400 for content too long",
  async () => {
    if (!TEST_JWT) {
      console.log("Skipping test - no TEST_USER_JWT provided");
      return;
    }

    const longContent = "a".repeat(501);

    const response = await fetch(
      `${BASE_URL}/functions/v1/update-companion-memory`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${TEST_JWT}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          action: "memory",
          category: "preferences",
          content: longContent,
        }),
      },
    );

    assertEquals(response.status, 400);
    const body = await response.json();
    assertEquals(body.error.includes("500 characters"), true);
  },
);

Deno.test(
  "update-companion-memory - returns 400 for empty content",
  async () => {
    if (!TEST_JWT) {
      console.log("Skipping test - no TEST_USER_JWT provided");
      return;
    }

    const response = await fetch(
      `${BASE_URL}/functions/v1/update-companion-memory`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${TEST_JWT}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          action: "memory",
          category: "preferences",
          content: "   ",
        }),
      },
    );

    assertEquals(response.status, 400);
  },
);

Deno.test("update-companion-memory - creates memory successfully", async () => {
  if (!TEST_JWT) {
    console.log("Skipping test - no TEST_USER_JWT provided");
    return;
  }

  const response = await fetch(
    `${BASE_URL}/functions/v1/update-companion-memory`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${TEST_JWT}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        action: "memory",
        category: "preferences",
        content: "Test memory for unit tests",
      }),
    },
  );

  // Could be 201 (created) or 409 (limit reached)
  if (response.status === 201) {
    const body = await response.json();
    assertEquals(body.success, true);
    assertExists(body.memory);
    assertExists(body.memory.id);
    assertEquals(body.memory.category, "preferences");
    assertEquals(body.memory.content, "Test memory for unit tests");
  } else if (response.status === 409) {
    // Limit reached - acceptable
    const body = await response.json();
    assertEquals(body.error.includes("limit"), true);
  }
});

Deno.test(
  "update-companion-memory - intent action validates length",
  async () => {
    if (!TEST_JWT) {
      console.log("Skipping test - no TEST_USER_JWT provided");
      return;
    }

    const longIntent = "a".repeat(141);

    const response = await fetch(
      `${BASE_URL}/functions/v1/update-companion-memory`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${TEST_JWT}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          action: "intent",
          intent: longIntent,
        }),
      },
    );

    assertEquals(response.status, 400);
    const body = await response.json();
    assertEquals(body.error.includes("140"), true);
  },
);

Deno.test("update-companion-memory - sets intent successfully", async () => {
  if (!TEST_JWT) {
    console.log("Skipping test - no TEST_USER_JWT provided");
    return;
  }

  const response = await fetch(
    `${BASE_URL}/functions/v1/update-companion-memory`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${TEST_JWT}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        action: "intent",
        intent: "Stay calm and focused today",
      }),
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.success, true);
  assertExists(body.dailyIntent);
  assertExists(body.dailyIntent.id);
  assertEquals(body.dailyIntent.intent, "Stay calm and focused today");
  assertExists(body.dailyIntent.expiresAt);
});
