// Tests for request validation utilities
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { extractAuthToken, safeParseJson } from "../request-validation.ts";

Deno.test("extractAuthToken - valid Bearer token", () => {
  const req = new Request("https://example.com", {
    headers: { Authorization: "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" },
  });
  const token = extractAuthToken(req);
  assertEquals(token, "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9");
});

Deno.test("extractAuthToken - missing Authorization header", () => {
  const req = new Request("https://example.com");
  const token = extractAuthToken(req);
  assertEquals(token, null);
});

Deno.test("extractAuthToken - missing Bearer prefix", () => {
  const req = new Request("https://example.com", {
    headers: { Authorization: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" },
  });
  const token = extractAuthToken(req);
  assertEquals(token, null);
});

Deno.test("extractAuthToken - empty token after Bearer", () => {
  const req = new Request("https://example.com", {
    headers: { Authorization: "Bearer " },
  });
  const token = extractAuthToken(req);
  assertEquals(token, null);
});

Deno.test("extractAuthToken - token with whitespace", () => {
  const req = new Request("https://example.com", {
    headers: { Authorization: "Bearer  eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9  " },
  });
  const token = extractAuthToken(req);
  assertEquals(token, "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9");
});

Deno.test("safeParseJson - valid JSON", async () => {
  const req = new Request("https://example.com", {
    method: "POST",
    body: JSON.stringify({ arcId: "test-123" }),
  });
  const result = await safeParseJson(req);
  assertEquals(result, { arcId: "test-123" });
});

Deno.test("safeParseJson - invalid JSON", async () => {
  const req = new Request("https://example.com", {
    method: "POST",
    body: "invalid{json",
  });
  const result = await safeParseJson(req);
  assertEquals(result, null);
});

Deno.test("safeParseJson - empty body", async () => {
  const req = new Request("https://example.com", {
    method: "POST",
    body: "",
  });
  const result = await safeParseJson(req);
  assertEquals(result, null);
});

Deno.test("safeParseJson - array JSON", async () => {
  const req = new Request("https://example.com", {
    method: "POST",
    body: JSON.stringify([1, 2, 3]),
  });
  const result = await safeParseJson<number[]>(req);
  const expected: number[] = [1, 2, 3];
  assertEquals(result, expected);
});
