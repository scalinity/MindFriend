// Unit tests for invite code validation
import {
  assertEquals,
  assert,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  validateInviteCode,
  validateFamilyInviteCode,
  validateBuddyInviteCode,
  validateCircleInviteCode,
  isValidInviteCode,
  INVITE_CODE_CHARSET,
} from "./validation.ts";

Deno.test("validateInviteCode: Empty and null inputs", () => {
  // Empty string
  let result = validateInviteCode("");
  assertEquals(result.valid, false);
  assertEquals(result.code, "EMPTY_CODE");
  assertEquals(result.normalized, null);

  // Null
  result = validateInviteCode(null);
  assertEquals(result.valid, false);
  assertEquals(result.code, "EMPTY_CODE");

  // Undefined
  result = validateInviteCode(undefined);
  assertEquals(result.valid, false);
  assertEquals(result.code, "EMPTY_CODE");

  // Whitespace only
  result = validateInviteCode("   ");
  assertEquals(result.valid, false);
  assertEquals(result.code, "INVALID_LENGTH");
});

Deno.test("validateInviteCode: Valid 8-character codes", () => {
  const validCodes = [
    "ABCDEFGH",
    "ZYXWVUTS",
    "ABCD1234",
    "12345678",
    "HELLOABC",
  ];

  for (const code of validCodes) {
    const result = validateInviteCode(code);
    assertEquals(result.valid, true, `Code ${code} should be valid`);
    assertEquals(
      result.normalized,
      code,
      `Code ${code} should normalize to itself`,
    );
  }
});

Deno.test("validateInviteCode: Valid 6-character codes", () => {
  const validCodes = ["ABCDEF", "123456", "ABC123"];

  for (const code of validCodes) {
    const result = validateInviteCode(code);
    assertEquals(result.valid, true, `Code ${code} should be valid`);
    assertEquals(result.normalized, code);
  }
});

Deno.test("validateInviteCode: Case normalization", () => {
  // Lowercase input
  let result = validateInviteCode("abcdefgh");
  assertEquals(result.valid, true);
  assertEquals(result.normalized, "ABCDEFGH");

  // Mixed case
  result = validateInviteCode("AbCdEfGh");
  assertEquals(result.valid, true);
  assertEquals(result.normalized, "ABCDEFGH");

  // With whitespace
  result = validateInviteCode("  abcdefgh  ");
  assertEquals(result.valid, true);
  assertEquals(result.normalized, "ABCDEFGH");
});

Deno.test("validateInviteCode: Too short codes", () => {
  const shortCodes = ["ABC", "12345", "A"];

  for (const code of shortCodes) {
    const result = validateInviteCode(code);
    assertEquals(result.valid, false, `Code '${code}' should be invalid`);
    assertEquals(result.code, "INVALID_LENGTH");
  }
});

Deno.test("validateInviteCode: Too long codes", () => {
  const longCodes = ["ABCDEFGHIJKLM", "123456789012345"];

  for (const code of longCodes) {
    const result = validateInviteCode(code);
    assertEquals(result.valid, false, `Code '${code}' should be invalid`);
    assertEquals(result.code, "INVALID_LENGTH");
  }
});

Deno.test("validateInviteCode: Invalid characters", () => {
  const invalidCodes = [
    "ABCDEF-H", // hyphen
    "ABCDEF_H", // underscore
    "ABCDEF!H", // special char
    "ABCDEF H", // space
    "ABC@EFG", // at symbol
    "ABC/EFG", // forward slash
  ];

  for (const code of invalidCodes) {
    const result = validateInviteCode(code);
    assertEquals(result.valid, false, `Code '${code}' should be invalid`);
    assertEquals(result.code, "INVALID_CHARACTERS");
  }
});

Deno.test("validateInviteCode: Custom length constraints", () => {
  // Strict 6-character validation
  let result = validateInviteCode("ABCDEFG", { minLength: 6, maxLength: 6 });
  assertEquals(result.valid, false);
  assertEquals(result.code, "INVALID_LENGTH");

  result = validateInviteCode("ABCDEF", { minLength: 6, maxLength: 6 });
  assertEquals(result.valid, true);

  // Flexible length (8-12)
  result = validateInviteCode("ABCDEFGH", { minLength: 8, maxLength: 12 });
  assertEquals(result.valid, true);

  result = validateInviteCode("ABCDEF", { minLength: 8, maxLength: 12 });
  assertEquals(result.valid, false);
  assertEquals(result.code, "INVALID_LENGTH");
});

Deno.test("validateFamilyInviteCode: Valid codes", () => {
  // 6-12 character family codes
  const validCodes = ["ABCDEF", "ABCDEFGH", "ABC123XYZ", "123456789ABC"];

  for (const code of validCodes) {
    const result = validateFamilyInviteCode(code);
    assertEquals(result.valid, true, `Family code '${code}' should be valid`);
  }
});

Deno.test("validateFamilyInviteCode: Invalid codes", () => {
  const invalidCodes = ["ABCDE", "1234567890123", "ABC-DEF", "ABC DEF"];

  for (const code of invalidCodes) {
    const result = validateFamilyInviteCode(code);
    assertEquals(
      result.valid,
      false,
      `Family code '${code}' should be invalid`,
    );
  }
});

Deno.test("validateBuddyInviteCode: Exactly 6 characters", () => {
  // Valid: exactly 6 characters
  let result = validateBuddyInviteCode("ABCDEF");
  assertEquals(result.valid, true);

  result = validateBuddyInviteCode("123456");
  assertEquals(result.valid, true);

  // Invalid: not exactly 6
  result = validateBuddyInviteCode("ABCDE"); // 5 chars
  assertEquals(result.valid, false);

  result = validateBuddyInviteCode("ABCDEFG"); // 7 chars
  assertEquals(result.valid, false);
});

Deno.test("validateCircleInviteCode: Same as family codes", () => {
  // Should use same validation as family codes
  const code = "ABC12345";
  const familyResult = validateFamilyInviteCode(code);
  const circleResult = validateCircleInviteCode(code);

  assertEquals(familyResult.valid, circleResult.valid);
  assertEquals(familyResult.normalized, circleResult.normalized);
});

Deno.test("isValidInviteCode: Type guard", () => {
  const validResult = validateInviteCode("ABCDEF");
  assert(isValidInviteCode(validResult));
  if (isValidInviteCode(validResult)) {
    // TypeScript should narrow to string here
    const normalized: string = validResult.normalized;
    assertEquals(typeof normalized, "string");
  }

  const invalidResult = validateInviteCode("ABC");
  assertEquals(isValidInviteCode(invalidResult), false);
});

Deno.test("INVITE_CODE_CHARSET: Contains expected characters", () => {
  assertEquals(INVITE_CODE_CHARSET, "ABCDEFGHJKLMNPQRSTUVWXYZ23456789");

  // Should NOT contain confusing characters: I, O, 0, 1
  // (L is included for backward compatibility, despite visual similarity to 1)
  assertEquals(INVITE_CODE_CHARSET.includes("I"), false);
  assertEquals(INVITE_CODE_CHARSET.includes("O"), false);
  assertEquals(INVITE_CODE_CHARSET.includes("0"), false);
  assertEquals(INVITE_CODE_CHARSET.includes("1"), false);
  // L IS included (not excluded)
  assertEquals(INVITE_CODE_CHARSET.includes("L"), true);
});

Deno.test("validateInviteCode: SQL injection attempts", () => {
  const sqlInjectionAttempts = [
    "'; DROP TABLE--",
    "1' OR '1'='1",
    "UNION SELECT *",
    "'; DELETE FROM--",
  ];

  for (const code of sqlInjectionAttempts) {
    const result = validateInviteCode(code);
    assertEquals(
      result.valid,
      false,
      `SQL injection attempt '${code}' should be invalid`,
    );
  }
});

Deno.test("validateInviteCode: Enumeration attack prevention", () => {
  // These would be used in enumeration attempts - should all fail validation
  const enumerationAttempts = [
    "", // empty
    " ", // space
    "A", // too short
    "00000", // 5 zeros
    "000000000000000", // too many zeros
    "-1", // negative
    "1e10", // exponential
  ];

  for (const code of enumerationAttempts) {
    const result = validateInviteCode(code);
    assertEquals(
      result.valid,
      false,
      `Enumeration attempt '${code}' should be invalid`,
    );
  }
});

Deno.test("validateInviteCode: Maximum string length safety", () => {
  // Very long string (potential DoS)
  const longString = "A".repeat(10000);
  const result = validateInviteCode(longString);
  assertEquals(result.valid, false);
  assertEquals(result.code, "INVALID_LENGTH");
});
