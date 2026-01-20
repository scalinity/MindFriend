// Tests for get-companion-memory Edge Function
import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.192.0/testing/asserts.ts";

const BASE_URL = Deno.env.get("SUPABASE_URL") || "http://localhost:54321";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";

// Mock JWT for testing (in real tests, get this from auth flow)
const TEST_JWT = Deno.env.get("TEST_USER_JWT") || "";

Deno.test("get-companion-memory - returns 401 without auth", async () => {
  const response = await fetch(
    `${BASE_URL}/functions/v1/get-companion-memory`,
    {
      method: "GET",
    },
  );

  assertEquals(response.status, 401);
  const bodyText = await response.text();
  if (bodyText) {
    const body = JSON.parse(bodyText);
    if (typeof body.code === "string") {
      assertEquals(body.code, "UNAUTHORIZED");
    }
  }
});

Deno.test(
  "get-companion-memory - returns memories for authenticated user",
  async () => {
    if (!TEST_JWT) {
      console.log("Skipping test - no TEST_USER_JWT provided");
      return;
    }

    const response = await fetch(
      `${BASE_URL}/functions/v1/get-companion-memory`,
      {
        method: "GET",
        headers: {
          Authorization: `Bearer ${TEST_JWT}`,
        },
      },
    );

    assertEquals(response.status, 200);
    const body = await response.json();

    // Verify response structure
    assertExists(body.memories);
    assertExists(body.totalCount);
    assertExists(body.maxLimit);
    assertEquals(body.maxLimit, 20);
    assertEquals(Array.isArray(body.memories), true);
  },
);

Deno.test(
  "get-companion-memory - memory object has correct shape",
  async () => {
    if (!TEST_JWT) {
      console.log("Skipping test - no TEST_USER_JWT provided");
      return;
    }

    const response = await fetch(
      `${BASE_URL}/functions/v1/get-companion-memory`,
      {
        method: "GET",
        headers: {
          Authorization: `Bearer ${TEST_JWT}`,
        },
      },
    );

    const body = await response.json();

    if (body.memories.length > 0) {
      const memory = body.memories[0];
      assertExists(memory.id);
      assertExists(memory.category);
      assertExists(memory.content);
      assertExists(memory.usageCount);
      assertExists(memory.createdAt);
      assertExists(memory.updatedAt);
      // lastUsedAt can be null
    }
  },
);

Deno.test(
  "get-companion-memory - dailyIntent is null or valid object",
  async () => {
    if (!TEST_JWT) {
      console.log("Skipping test - no TEST_USER_JWT provided");
      return;
    }

    const response = await fetch(
      `${BASE_URL}/functions/v1/get-companion-memory`,
      {
        method: "GET",
        headers: {
          Authorization: `Bearer ${TEST_JWT}`,
        },
      },
    );

    const body = await response.json();

    if (body.dailyIntent !== null) {
      assertExists(body.dailyIntent.id);
      assertExists(body.dailyIntent.intent);
      assertExists(body.dailyIntent.createdAt);
      assertExists(body.dailyIntent.expiresAt);
    }
  },
);
