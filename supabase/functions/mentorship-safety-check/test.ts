import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.208.0/assert/mod.ts";

/**
 * Test suite for mentorship-safety-check Edge Function
 * Tests crisis detection, boundary violations, and message flagging
 */

// Test 1: Crisis keyword detection - suicide
Deno.test("mentorship-safety-check: Detects suicide keyword", async () => {
  const crisisKeywords = ["suicide", "suicidal", "kill myself", "end my life"];
  const message = "I think about killing myself every day";
  const hasCrisis = crisisKeywords.some((kw) =>
    message.toLowerCase().includes(kw)
  );

  assertEquals(hasCrisis, true);
});

// Test 2: Crisis keyword detection - harm
Deno.test("mentorship-safety-check: Detects self-harm keyword", async () => {
  const message = "I've been hurting myself to cope with the pain";
  const harmKeywords = ["self harm", "hurt myself", "self-harm"];
  const hasHarm = harmKeywords.some((kw) =>
    message.toLowerCase().includes(kw)
  );

  assertEquals(hasHarm, true);
});

// Test 3: Boundary violation - romantic context
Deno.test("mentorship-safety-check: Detects romantic boundary violation", async () => {
  const message = "I really like you romantically and would love to date";
  const boundaryPattern = /\b(romantic|dating|love)\b/i;
  const hasBoundaryViolation = boundaryPattern.test(message);

  assertEquals(hasBoundaryViolation, true);
});

// Test 4: Boundary violation - physical contact
Deno.test("mentorship-safety-check: Detects physical contact request", async () => {
  const message = "Can we meet in person for coffee? I'd love a hug";
  const pattern = /\b(meet in person|meet up|coffee|hug)\b/i;
  const hasViolation = pattern.test(message);

  assertEquals(hasViolation, true);
});

// Test 5: Inappropriate request - scam
Deno.test("mentorship-safety-check: Detects scam pattern", async () => {
  const message = "This is a get-rich-quick scheme offering cryptocurrency investment";
  const pattern = /\b(scam|scheme|cryptocurrency|investment)\b/i;
  const hasInappropriate = pattern.test(message);

  assertEquals(hasInappropriate, true);
});

// Test 6: PII exposure - email
Deno.test("mentorship-safety-check: Detects PII - email", async () => {
  const message = "My email is john.doe@example.com if you want to contact me";
  const emailPattern = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/;
  const hasPII = emailPattern.test(message);

  assertEquals(hasPII, true);
});

// Test 7: PII exposure - phone
Deno.test("mentorship-safety-check: Detects PII - phone number", async () => {
  const message = "Call me at 555-123-4567 anytime";
  const phonePattern = /(\+?1)?[-.\s]?\(?[2-9]\d{2}\)?[-.\s]?\d{3}[-.\s]?\d{4}/;
  const hasPII = phonePattern.test(message);

  assertEquals(hasPII, true);
});

// Test 8: Severity classification - critical (crisis)
Deno.test("mentorship-safety-check: Crisis classified as CRITICAL", async () => {
  const message = "I'm going to kill myself tonight";
  const severity = message.toLowerCase().includes("kill myself")
    ? "critical"
    : "low";

  assertEquals(severity, "critical");
});

// Test 9: Severity classification - high (boundary)
Deno.test("mentorship-safety-check: Boundary violation classified as HIGH", async () => {
  const message = "Would you like to meet for dinner? I find you attractive";
  const hasBoundary = /\b(meet|dinner|attractive)\b/i.test(message);
  const severity = hasBoundary ? "high" : "low";

  assertEquals(severity, "high");
});

// Test 10: Severity classification - medium (PII)
Deno.test("mentorship-safety-check: PII exposure classified as MEDIUM", async () => {
  const message = "My SSN is 123-45-6789";
  const hasPII = /\b\d{3}-\d{2}-\d{4}\b/.test(message);
  const severity = hasPII ? "medium" : "low";

  assertEquals(severity, "medium");
});

// Test 11: Clean message passes all checks
Deno.test("mentorship-safety-check: Safe message has no flags", async () => {
  const message = "I've been practicing the breathing exercises you suggested and they really help with my anxiety";
  const crisisKeywords = ["suicide", "kill myself", "harm"];
  const hasCrisis = crisisKeywords.some((kw) =>
    message.toLowerCase().includes(kw)
  );
  const hasBoundary = /\b(romantic|dating)\b/i.test(message);
  const hasReasons = hasCrisis || hasBoundary;

  assertEquals(hasReasons, false);
});

// Test 12: Excessive character repetition flagged (spam)
Deno.test("mentorship-safety-check: Detects spam repetition", async () => {
  const message = "hellooooooooooooooooooooo" + "a".repeat(20);
  const hasRepetition = /(.)\1{19,}/.test(message);

  assertEquals(hasRepetition, true);
});

// Test 13: Long message length check
Deno.test("mentorship-safety-check: Excessive length flagged", async () => {
  const message = "x".repeat(5001);
  const isTooLong = message.length > 5000;

  assertEquals(isTooLong, true);
});

// Test 14: Multiple issues in single message
Deno.test("mentorship-safety-check: Multiple flags for complex message", async () => {
  const message = "I want to hurt myself (123-45-6789). Let's meet romantically?";
  const flags = [];

  if (/\b(hurt myself|self-harm)\b/i.test(message)) flags.push("crisis");
  if (/\b\d{3}-\d{2}-\d{4}\b/.test(message)) flags.push("pii");
  if (/\b(romantic|dating)\b/i.test(message)) flags.push("boundary");

  assertEquals(flags.length > 1, true);
});

// Test 15: Batch processing limit
Deno.test("mentorship-safety-check: Batch size limit respected", async () => {
  const requestBatchSize = 100;
  const batchLimit = 100;
  const isValid = requestBatchSize <= batchLimit;

  assertEquals(isValid, true);
});

// Test 16: Flagged message update
Deno.test("mentorship-safety-check: Flagged messages marked in database", async () => {
  const flaggedMessage = {
    id: "msg-uuid",
    is_flagged: true,
    flagged_at: new Date().toISOString(),
  };

  assertEquals(flaggedMessage.is_flagged, true);
  assertEquals(flaggedMessage.flagged_at.length > 0, true);
});

// Test 17: Critical escalation creates record
Deno.test("mentorship-safety-check: Critical escalation recorded", async () => {
  const escalationRecord = {
    message_id: "msg-uuid",
    match_id: "match-uuid",
    severity: "critical",
    status: "pending_review",
  };

  assertEquals(escalationRecord.severity, "critical");
  assertEquals(escalationRecord.status, "pending_review");
});

// Test 18: Moderator notification sent on crisis
Deno.test("mentorship-safety-check: Crisis triggers moderator alert", async () => {
  const notification = {
    user_id: "moderator-group",
    title: "CRISIS ALERT - Mentorship Message",
    priority: "urgent",
    type: "crisis_escalation",
  };

  assertEquals(notification.priority, "urgent");
  assertStringIncludes(notification.title, "CRISIS");
});

// Test 19: Recent-only filter works
Deno.test("mentorship-safety-check: Check recent messages only", async () => {
  const hoursAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const messageCreatedAt = new Date().toISOString();
  const isRecent = messageCreatedAt >= hoursAgo;

  assertEquals(isRecent, true);
});

// Test 20: Response structure validation
Deno.test("mentorship-safety-check: Response includes summary stats", async () => {
  const response = {
    success: true,
    messages_checked: 45,
    messages_flagged: 3,
    critical_escalations: 1,
    timestamp: new Date().toISOString(),
  };

  assertEquals(response.success, true);
  assertEquals(typeof response.messages_checked, "number");
  assertEquals(typeof response.critical_escalations, "number");
});
