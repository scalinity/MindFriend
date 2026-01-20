// Tests for delete-companion-memory Edge Function
import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.192.0/testing/asserts.ts";

const BASE_URL = Deno.env.get("SUPABASE_URL") || "http://localhost:54321";
const TEST_JWT = Deno.env.get("TEST_USER_JWT") || "";

Deno.test("delete-companion-memory - returns 401 without auth", async () => {
  const response = await fetch(
    `${BASE_URL}/functions/v1/delete-companion-memory`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        action: "memory",
        id: "00000000-0000-0000-0000-000000000000",
      }),
    },
  );

  assertEquals(response.status, 401);
  await response.text();
});

Deno.test("delete-companion-memory - returns 400 for missing id", async () => {
  if (!TEST_JWT) {
    console.log("Skipping test - no TEST_USER_JWT provided");
    return;
  }

  const response = await fetch(
    `${BASE_URL}/functions/v1/delete-companion-memory`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${TEST_JWT}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        action: "memory",
      }),
    },
  );

  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.error.includes("ID"), true);
});

Deno.test(
  "delete-companion-memory - returns 404 for non-existent memory",
  async () => {
    if (!TEST_JWT) {
      console.log("Skipping test - no TEST_USER_JWT provided");
      return;
    }

    const response = await fetch(
      `${BASE_URL}/functions/v1/delete-companion-memory`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${TEST_JWT}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          action: "memory",
          id: "00000000-0000-0000-0000-000000000000",
        }),
      },
    );

    assertEquals(response.status, 404);
  },
);

Deno.test("delete-companion-memory - clears intent successfully", async () => {
  if (!TEST_JWT) {
    console.log("Skipping test - no TEST_USER_JWT provided");
    return;
  }

  const response = await fetch(
    `${BASE_URL}/functions/v1/delete-companion-memory`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${TEST_JWT}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        action: "intent",
      }),
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.success, true);
});

Deno.test("delete-companion-memory - full CRUD cycle", async () => {
  if (!TEST_JWT) {
    console.log("Skipping test - no TEST_USER_JWT provided");
    return;
  }

  // 1. Create a memory
  const createResponse = await fetch(
    `${BASE_URL}/functions/v1/update-companion-memory`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${TEST_JWT}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        action: "memory",
        category: "life_context",
        content: "Test memory for delete test",
      }),
    },
  );

  // If limit reached, skip delete test
  if (createResponse.status === 409) {
    console.log("Skipping delete test - memory limit reached");
    return;
  }

  assertEquals(createResponse.status, 201);
  const createBody = await createResponse.json();
  const memoryId = createBody.memory.id;
  assertExists(memoryId);

  // 2. Delete the memory
  const deleteResponse = await fetch(
    `${BASE_URL}/functions/v1/delete-companion-memory`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${TEST_JWT}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        action: "memory",
        id: memoryId,
      }),
    },
  );

  assertEquals(deleteResponse.status, 200);
  const deleteBody = await deleteResponse.json();
  assertEquals(deleteBody.success, true);

  // 3. Verify it's gone (deleted)
  const verifyResponse = await fetch(
    `${BASE_URL}/functions/v1/delete-companion-memory`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${TEST_JWT}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        action: "memory",
        id: memoryId,
      }),
    },
  );

  // Should return 404 since it's already deleted
  assertEquals(verifyResponse.status, 404);
});
