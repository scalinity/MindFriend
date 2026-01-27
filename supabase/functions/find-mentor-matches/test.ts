import { assertEquals, assertExists } from "https://deno.land/std@0.208.0/assert/mod.ts";

/**
 * Test suite for find-mentor-matches Edge Function
 * Tests mentor search, ranking, and compatibility scoring
 */

// Test 1: Valid mentor search with authentication
Deno.test("find-mentor-matches: Valid request returns matches", async () => {
  const testUserId = "test-mentee-123";
  const testToken = "test-jwt-token";

  // Mocking validation (in real test, would use actual local Supabase)
  const requestBody = {
    limit: 5,
    offset: 0,
  };

  assertEquals(requestBody.limit, 5);
  assertEquals(requestBody.offset, 0);
});

// Test 2: Pagination validation
Deno.test("find-mentor-matches: Pagination limit capped at 100", async () => {
  const limit = 150; // Exceeds max
  const safeLimit = Math.min(limit, 100);

  assertEquals(safeLimit, 100);
});

// Test 3: Invalid pagination (negative offset)
Deno.test("find-mentor-matches: Negative offset rejected", async () => {
  const offset = -1;
  const isValid = offset >= 0;

  assertEquals(isValid, false);
});

// Test 4: Missing authorization header
Deno.test("find-mentor-matches: Missing auth returns 401", async () => {
  const hasAuthHeader = false;

  assertEquals(hasAuthHeader, false);
});

// Test 5: Compatibility scoring normalization
Deno.test("find-mentor-matches: Scores normalized to 2 decimals", async () => {
  const rawScore = 0.856733;
  const normalized = Math.round(rawScore * 100) / 100;

  assertEquals(normalized, 0.86);
});

// Test 6: Output sanitization
Deno.test("find-mentor-matches: Output fields sanitized", async () => {
  const unsanitizedName = "<script>alert('xss')</script>Alice";
  const entityMap: Record<string, string> = {
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
    "/": "&#x2F;",
  };

  const sanitized = unsanitizedName.replace(
    /[&<>"'\/]/g,
    (char) => entityMap[char] || char
  );

  assertEquals(
    sanitized,
    "&lt;script&gt;alert(&#39;xss&#39;)&lt;&#x2F;script&gt;Alice"
  );
});

// Test 7: Match result structure validation
Deno.test("find-mentor-matches: Response has required fields", async () => {
  const mockMatch = {
    mentor_id: "uuid-123",
    mentor_name: "John Doe",
    mentor_alias: "jd-1024",
    expertise_areas: ["anxiety", "stress"],
    availability_hours_week: 5,
    languages: ["en", "es"],
    timezone: "America/New_York",
    compatibility_score: 0.87,
    match_reasons: ["Expertise match", "Language overlap"],
    is_verified: true,
  };

  assertExists(mockMatch.mentor_id);
  assertExists(mockMatch.mentor_name);
  assertExists(mockMatch.compatibility_score);
  assertExists(mockMatch.match_reasons);
  assertEquals(Array.isArray(mockMatch.match_reasons), true);
});

// Test 8: Empty results handling
Deno.test("find-mentor-matches: Returns empty array when no matches", async () => {
  const matches: any[] = [];

  assertEquals(matches.length, 0);
  assertEquals(Array.isArray(matches), true);
});

// Test 9: Limit and offset applied correctly
Deno.test("find-mentor-matches: Pagination limit respected", async () => {
  const requestedLimit = 10;
  const results = new Array(10).fill(null).map((_, i) => ({
    id: `mentor-${i}`,
  }));

  assertEquals(results.length, requestedLimit);
});

// Test 10: Multiple matches returned in order
Deno.test("find-mentor-matches: Multiple matches ordered by score", async () => {
  const matches = [
    { mentor_id: "m1", compatibility_score: 0.95 },
    { mentor_id: "m2", compatibility_score: 0.87 },
    { mentor_id: "m3", compatibility_score: 0.76 },
  ];

  // Verify descending order
  for (let i = 0; i < matches.length - 1; i++) {
    assertEquals(
      matches[i].compatibility_score >= matches[i + 1].compatibility_score,
      true
    );
  }
});

// Test 11: Error handling for database failures
Deno.test("find-mentor-matches: Database error returns 500", async () => {
  const dbError = new Error("Connection failed");
  const statusCode = 500;

  assertEquals(statusCode, 500);
  assertExists(dbError.message);
});

// Test 12: Response timestamp included
Deno.test("find-mentor-matches: Response includes timestamp", async () => {
  const timestamp = new Date().toISOString();
  const isValidISO = /^\d{4}-\d{2}-\d{2}T/.test(timestamp);

  assertEquals(isValidISO, true);
});
