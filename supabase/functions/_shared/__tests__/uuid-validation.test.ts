// Tests for UUID validation utilities
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { validateUuid, validateUuids, isValidUuid } from "../uuid-validation.ts";

Deno.test("validateUuid - valid UUID", () => {
  const result = validateUuid("550e8400-e29b-41d4-a716-446655440000");
  assertEquals(result.valid, true);
  assertEquals(result.normalized, "550e8400-e29b-41d4-a716-446655440000");
  assertEquals(result.error, undefined);
});

Deno.test("validateUuid - valid UUID with uppercase", () => {
  const result = validateUuid("550E8400-E29B-41D4-A716-446655440000");
  assertEquals(result.valid, true);
  assertEquals(result.normalized, "550e8400-e29b-41d4-a716-446655440000"); // normalized to lowercase
});

Deno.test("validateUuid - valid UUID with whitespace", () => {
  const result = validateUuid("  550e8400-e29b-41d4-a716-446655440000  ");
  assertEquals(result.valid, true);
  assertEquals(result.normalized, "550e8400-e29b-41d4-a716-446655440000");
});

Deno.test("validateUuid - null UUID", () => {
  const result = validateUuid(null);
  assertEquals(result.valid, false);
  assertEquals(result.normalized, null);
  assertEquals(result.error, "id is required");
});

Deno.test("validateUuid - undefined UUID", () => {
  const result = validateUuid(undefined);
  assertEquals(result.valid, false);
  assertEquals(result.normalized, null);
  assertEquals(result.error, "id is required");
});

Deno.test("validateUuid - empty string", () => {
  const result = validateUuid("");
  assertEquals(result.valid, false);
  assertEquals(result.normalized, null);
  assertEquals(result.error, "id is required");
});

Deno.test("validateUuid - invalid format (too short)", () => {
  const result = validateUuid("550e8400-e29b");
  assertEquals(result.valid, false);
  assertEquals(result.error, "id must be a valid UUID");
});

Deno.test("validateUuid - invalid format (missing hyphens)", () => {
  const result = validateUuid("550e8400e29b41d4a716446655440000");
  assertEquals(result.valid, false);
  assertEquals(result.error, "id must be a valid UUID");
});

Deno.test("validateUuid - SQL injection attempt", () => {
  const result = validateUuid("'; DROP TABLE users--");
  assertEquals(result.valid, false);
  assertEquals(result.error, "id must be a valid UUID");
});

Deno.test("validateUuid - XSS attempt", () => {
  const result = validateUuid("<script>alert('xss')</script>");
  assertEquals(result.valid, false);
  assertEquals(result.error, "id must be a valid UUID");
});

Deno.test("validateUuid - custom field name", () => {
  const result = validateUuid(null, "userArcId");
  assertEquals(result.valid, false);
  assertEquals(result.error, "userArcId is required");
});

Deno.test("isValidUuid - type guard works", () => {
  const result = validateUuid("550e8400-e29b-41d4-a716-446655440000");
  if (isValidUuid(result)) {
    // TypeScript should narrow result.normalized to string (not string | null)
    const normalized: string = result.normalized;
    assertEquals(normalized, "550e8400-e29b-41d4-a716-446655440000");
  }
});

Deno.test("validateUuids - all valid", () => {
  const result = validateUuids({
    arcId: "550e8400-e29b-41d4-a716-446655440000",
    userId: "660e8400-e29b-41d4-a716-446655440001",
  });
  assertEquals(result.valid, true);
  if (result.valid) {
    assertEquals(result.normalized.arcId, "550e8400-e29b-41d4-a716-446655440000");
    assertEquals(result.normalized.userId, "660e8400-e29b-41d4-a716-446655440001");
  }
});

Deno.test("validateUuids - one invalid", () => {
  const result = validateUuids({
    arcId: "550e8400-e29b-41d4-a716-446655440000",
    userId: "invalid-uuid",
  });
  assertEquals(result.valid, false);
  if (!result.valid) {
    assertEquals(result.error, "userId must be a valid UUID");
  }
});
