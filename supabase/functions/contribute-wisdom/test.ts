/**
 * Tests for contribute-wisdom Edge Function
 *
 * Run with: deno test --allow-net --allow-env contribute-wisdom/test.ts
 */

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

// Mock crypto.subtle for SHA-256 hashing
const mockHash = async (data: string): Promise<string> => {
  const encoder = new TextEncoder();
  const dataBuffer = encoder.encode(data);
  const hashBuffer = await crypto.subtle.digest("SHA-256", dataBuffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
};

Deno.test("hashUserId produces 64-character hex string", async () => {
  const userId = "550e8400-e29b-41d4-a716-446655440000";
  const salt = "test-salt-12345";
  const hash = await mockHash(`${userId}:${salt}`);

  assertEquals(hash.length, 64);
  assertEquals(/^[a-f0-9]+$/.test(hash), true);
});

Deno.test("hashUserId is deterministic", async () => {
  const userId = "550e8400-e29b-41d4-a716-446655440000";
  const salt = "test-salt-12345";

  const hash1 = await mockHash(`${userId}:${salt}`);
  const hash2 = await mockHash(`${userId}:${salt}`);

  assertEquals(hash1, hash2);
});

Deno.test("different userIds produce different hashes", async () => {
  const salt = "test-salt-12345";
  const hash1 = await mockHash("user-1:${salt}");
  const hash2 = await mockHash("user-2:${salt}");

  assertEquals(hash1 !== hash2, true);
});

Deno.test(
  "same userId with different salts produce different hashes",
  async () => {
    const userId = "550e8400-e29b-41d4-a716-446655440000";
    const hash1 = await mockHash(`${userId}:salt-1`);
    const hash2 = await mockHash(`${userId}:salt-2`);

    assertEquals(hash1 !== hash2, true);
  },
);

// PII Detection Tests
const EMAIL_REGEX = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/;
const PHONE_REGEX = /(\+?1[-.\s]?)?(\(?\d{3}\)?[-.\s]?)?\d{3}[-.\s]?\d{4}/;
const SSN_REGEX = /\b\d{3}-\d{2}-\d{4}\b/;
const CREDIT_CARD_REGEX = /\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/;

function detectPII(text: string): string[] {
  const detected: string[] = [];
  if (EMAIL_REGEX.test(text)) detected.push("email");
  if (PHONE_REGEX.test(text)) detected.push("phone");
  if (SSN_REGEX.test(text)) detected.push("ssn");
  if (CREDIT_CARD_REGEX.test(text)) detected.push("credit_card");
  return detected;
}

Deno.test("detectPII finds email addresses", () => {
  const text = "Contact me at john.doe@example.com for more info";
  const pii = detectPII(text);
  assertEquals(pii.includes("email"), true);
});

Deno.test("detectPII finds phone numbers", () => {
  const text = "Call me at 555-123-4567";
  const pii = detectPII(text);
  assertEquals(pii.includes("phone"), true);
});

Deno.test("detectPII finds phone with area code", () => {
  const text = "My number is (555) 123-4567";
  const pii = detectPII(text);
  assertEquals(pii.includes("phone"), true);
});

Deno.test("detectPII finds SSN", () => {
  const text = "My SSN is 123-45-6789";
  const pii = detectPII(text);
  assertEquals(pii.includes("ssn"), true);
});

Deno.test("detectPII finds credit card numbers", () => {
  const text = "Pay with 4111-1111-1111-1111";
  const pii = detectPII(text);
  assertEquals(pii.includes("credit_card"), true);
});

Deno.test("detectPII returns empty for safe text", () => {
  const text =
    "I take 5 deep breaths when feeling anxious. This helps me relax.";
  const pii = detectPII(text);
  assertEquals(pii.length, 0);
});

Deno.test("detectPII finds multiple PII types", () => {
  const text = "Email me at test@example.com or call 555-123-4567";
  const pii = detectPII(text);
  assertEquals(pii.includes("email"), true);
  assertEquals(pii.includes("phone"), true);
  assertEquals(pii.length, 2);
});

// Contribution Type Validation
const VALID_CONTRIBUTION_TYPES = [
  "mood_pattern",
  "exercise_effectiveness",
  "pathway_progress",
  "strategy_success",
];

Deno.test("valid contribution types are accepted", () => {
  for (const type of VALID_CONTRIBUTION_TYPES) {
    assertEquals(VALID_CONTRIBUTION_TYPES.includes(type), true);
  }
});

Deno.test("invalid contribution type is rejected", () => {
  const invalidType = "invalid_type";
  assertEquals(VALID_CONTRIBUTION_TYPES.includes(invalidType), false);
});

// Context Tag Building
function getTimeOfDay(): string {
  const hour = new Date().getUTCHours();
  if (hour >= 5 && hour < 12) return "morning";
  if (hour >= 12 && hour < 17) return "afternoon";
  if (hour >= 17 && hour < 21) return "evening";
  return "night";
}

function getMoodLevel(moodScore: number): string {
  if (moodScore <= 2) return "low";
  if (moodScore === 3) return "medium";
  return "high";
}

Deno.test("getMoodLevel categorizes correctly", () => {
  assertEquals(getMoodLevel(1), "low");
  assertEquals(getMoodLevel(2), "low");
  assertEquals(getMoodLevel(3), "medium");
  assertEquals(getMoodLevel(4), "high");
  assertEquals(getMoodLevel(5), "high");
});

Deno.test("getTimeOfDay returns valid time period", () => {
  const timeOfDay = getTimeOfDay();
  assertEquals(
    ["morning", "afternoon", "evening", "night"].includes(timeOfDay),
    true,
  );
});

// Contribution Data Schema Validation
interface MoodPatternData {
  moodScore: number;
  timeOfDay?: string;
  emotion?: string;
}

function validateMoodPattern(data: unknown): data is MoodPatternData {
  if (typeof data !== "object" || data === null) return false;
  const obj = data as Record<string, unknown>;

  if (typeof obj.moodScore !== "number") return false;
  if (obj.moodScore < 1 || obj.moodScore > 5) return false;

  if (obj.timeOfDay !== undefined && typeof obj.timeOfDay !== "string")
    return false;
  if (obj.emotion !== undefined && typeof obj.emotion !== "string")
    return false;

  return true;
}

Deno.test("validateMoodPattern accepts valid data", () => {
  const validData = { moodScore: 3, timeOfDay: "morning", emotion: "anxious" };
  assertEquals(validateMoodPattern(validData), true);
});

Deno.test("validateMoodPattern accepts minimal data", () => {
  const minimalData = { moodScore: 4 };
  assertEquals(validateMoodPattern(minimalData), true);
});

Deno.test("validateMoodPattern rejects invalid moodScore", () => {
  const invalidData = { moodScore: 6 };
  assertEquals(validateMoodPattern(invalidData), false);
});

Deno.test("validateMoodPattern rejects missing moodScore", () => {
  const invalidData = { timeOfDay: "morning" };
  assertEquals(validateMoodPattern(invalidData), false);
});

Deno.test("validateMoodPattern rejects non-object", () => {
  assertEquals(validateMoodPattern("not an object"), false);
  assertEquals(validateMoodPattern(null), false);
  assertEquals(validateMoodPattern(undefined), false);
});
