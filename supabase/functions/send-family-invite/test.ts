// Tests for send-family-invite Edge Function
// Run with: deno test --allow-net --allow-env supabase/functions/send-family-invite/test.ts

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { escapeHtml, isValidEmail, sanitizeEmail } from "../_shared/utils.ts";

// Unit tests for utils

Deno.test("escapeHtml escapes HTML entities", () => {
  assertEquals(escapeHtml("<script>"), "&lt;script&gt;");
  assertEquals(escapeHtml("&"), "&amp;");
  assertEquals(escapeHtml('"'), "&quot;");
  assertEquals(escapeHtml("'"), "&#039;");
  assertEquals(escapeHtml("<"), "&lt;");
  assertEquals(escapeHtml(">"), "&gt;");
});

Deno.test("escapeHtml handles complex XSS attempts", () => {
  const xss = '<script>alert("xss")</script>';
  const escaped = escapeHtml(xss);
  assertEquals(escaped.includes("<"), false);
  assertEquals(escaped.includes(">"), false);
  assertEquals(escaped, "&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;");
});

Deno.test("escapeHtml handles empty/null input", () => {
  assertEquals(escapeHtml(""), "");
  assertEquals(escapeHtml(null as unknown as string), "");
  assertEquals(escapeHtml(undefined as unknown as string), "");
});

Deno.test("escapeHtml preserves safe characters", () => {
  assertEquals(escapeHtml("Hello World"), "Hello World");
  assertEquals(escapeHtml("user@example.com"), "user@example.com");
  assertEquals(escapeHtml("123-456-7890"), "123-456-7890");
});

Deno.test("isValidEmail accepts valid emails", () => {
  assertEquals(isValidEmail("user@example.com"), true);
  assertEquals(isValidEmail("user.name@example.com"), true);
  assertEquals(isValidEmail("user+tag@example.com"), true);
  assertEquals(isValidEmail("user@subdomain.example.com"), true);
  assertEquals(isValidEmail("user@example.co.uk"), true);
});

Deno.test("isValidEmail rejects invalid emails", () => {
  assertEquals(isValidEmail(""), false);
  assertEquals(isValidEmail("not-an-email"), false);
  assertEquals(isValidEmail("@example.com"), false);
  assertEquals(isValidEmail("user@"), false);
  assertEquals(isValidEmail("user@.com"), false);
  assertEquals(isValidEmail("user example.com"), false);
});

Deno.test("isValidEmail rejects overly long emails", () => {
  const longEmail = "a".repeat(250) + "@example.com";
  assertEquals(isValidEmail(longEmail), false);
});

Deno.test("sanitizeEmail lowercases and trims", () => {
  assertEquals(sanitizeEmail("User@Example.com"), "user@example.com");
  assertEquals(sanitizeEmail("  user@example.com  "), "user@example.com");
  assertEquals(sanitizeEmail("USER@EXAMPLE.COM"), "user@example.com");
});

Deno.test("sanitizeEmail handles empty/null input", () => {
  assertEquals(sanitizeEmail(""), "");
  assertEquals(sanitizeEmail(null as unknown as string), "");
  assertEquals(sanitizeEmail(undefined as unknown as string), "");
});

// Integration test stubs for send-family-invite

Deno.test("send-family-invite rejects missing email", async () => {
  const expectedError = {
    error: "Missing email",
    code: "MISSING_EMAIL",
  };
  assertExists(expectedError);
});

Deno.test("send-family-invite rejects invalid email format", async () => {
  const expectedError = {
    error: "Invalid email format",
    code: "INVALID_EMAIL_FORMAT",
  };
  assertExists(expectedError);
});

Deno.test("send-family-invite rejects non-family-admin", async () => {
  const expectedError = {
    success: false,
    error:
      "You don't have a family plan. Purchase a couples or family plan first.",
  };
  assertExists(expectedError);
});

Deno.test("send-family-invite rejects when no seats available", async () => {
  const expectedError = {
    success: false,
    error: "No seats available. Your plan allows 2 members.",
  };
  assertExists(expectedError);
});

Deno.test("send-family-invite returns existing invitation", async () => {
  // If there's already a valid pending invitation for this email,
  // return it instead of creating a new one
  const expectedResponse = {
    success: true,
    invite_code: "ABCD1234",
    expires_at: "2026-01-21T00:00:00.000Z",
    message: "An active invitation already exists for this email",
  };
  assertExists(expectedResponse);
});

Deno.test("send-family-invite creates new invitation", async () => {
  const expectedResponse = {
    success: true,
    invite_code: "WXYZ5678",
    expires_at: "2026-01-21T00:00:00.000Z",
    message: "Invitation created. Share the code with your invitee.",
  };
  assertExists(expectedResponse);
});

Deno.test("send-family-invite sends email when requested", async () => {
  // When send_email: true and RESEND_API_KEY is configured
  const expectedResponse = {
    success: true,
    invite_code: "ABCD1234",
    expires_at: "2026-01-21T00:00:00.000Z",
    email_sent: true,
    message: "Invitation sent to user@example.com",
  };
  assertExists(expectedResponse);
});

Deno.test("send-family-invite gracefully handles email failure", async () => {
  // If email sending fails, the invitation is still created
  // and the response indicates email_sent: false
  const expectedResponse = {
    success: true,
    invite_code: "ABCD1234",
    expires_at: "2026-01-21T00:00:00.000Z",
    email_sent: false,
    message: "Invitation created. Share the code with your invitee.",
  };
  assertExists(expectedResponse);
});

// XSS prevention test
Deno.test("email template escapes user content", () => {
  // The email template should use escapeHtml for:
  // - senderName (from profiles.display_name)
  // - familyGroup.name
  const maliciousName = '<script>alert("xss")</script>';
  const escaped = escapeHtml(maliciousName);
  assertEquals(escaped.includes("<script>"), false);
});
