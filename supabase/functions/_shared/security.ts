// Security utilities for constant-time comparisons and sensitive data protection

/**
 * Timing-safe string comparison to prevent timing attacks
 * Compares both strings in constant time regardless of length differences
 */
export function timingSafeEqual(a: string, b: string): boolean {
  const aBytes = new TextEncoder().encode(a);
  const bBytes = new TextEncoder().encode(b);

  // If lengths differ significantly, still compare in constant time
  const maxLen = Math.max(aBytes.length, bBytes.length);
  const minLen = Math.min(aBytes.length, bBytes.length);

  let result = aBytes.length ^ bBytes.length; // Will be 0 only if lengths equal

  // Compare all bytes (padding missing bytes with 0)
  for (let i = 0; i < maxLen; i++) {
    const aByte = i < aBytes.length ? aBytes[i] : 0;
    const bByte = i < bBytes.length ? bBytes[i] : 0;
    result |= aByte ^ bByte;
  }

  return result === 0;
}

/**
 * Sanitize error messages to prevent leaking sensitive data
 * Redacts UUIDs, email addresses, and API keys from logs
 */
export function sanitizeErrorMessage(error: unknown, maxLength: number = 500): string {
  let message = "";

  if (error instanceof Error) {
    message = error.message;
  } else if (typeof error === "string") {
    message = error;
  } else if (error && typeof error === "object" && "message" in error) {
    message = String((error as any).message);
  } else {
    message = String(error);
  }

  // Redact UUIDs (8-4-4-4-12 hex pattern)
  message = message.replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, "[REDACTED-UUID]");

  // Redact email addresses
  message = message.replace(/[\w.-]+@[\w.-]+\.\w+/g, "[REDACTED-EMAIL]");

  // Redact API keys and tokens (sequences that look like credentials)
  message = message.replace(/Bearer [^ ]+/g, "[REDACTED-TOKEN]");
  message = message.replace(/api[_-]?key[=:] *[^ ]+/gi, "[REDACTED-KEY]");

  // Truncate if too long
  return message.substring(0, maxLength);
}

/**
 * Validate and safely compare CRON secret
 */
export function validateCronSecret(
  authHeader: string | null,
  expectedSecret: string | null
): boolean {
  if (!expectedSecret || !authHeader) {
    return false;
  }

  return timingSafeEqual(authHeader, expectedSecret);
}
