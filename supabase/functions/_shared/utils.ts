// Shared utility functions for Edge Functions

/**
 * Escape HTML entities to prevent XSS attacks
 * Use this when inserting user-provided content into HTML templates
 */
export function escapeHtml(unsafe: string): string {
  if (!unsafe) return "";
  return unsafe
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

/**
 * Validate email format
 * Returns true if the email appears to be valid
 */
export function isValidEmail(email: string): boolean {
  if (!email || typeof email !== "string") return false;
  // RFC 5322 compliant regex (simplified)
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email.trim()) && email.length <= 254;
}

/**
 * Sanitize email for storage
 * Lowercases and trims the email
 */
export function sanitizeEmail(email: string): string {
  if (!email || typeof email !== "string") return "";
  return email.trim().toLowerCase();
}

/**
 * Format a date for display
 */
export function formatDate(date: Date): string {
  return date.toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
  });
}

/**
 * Create a standardized error response object
 */
export function createErrorResponse(
  error: string,
  code: string,
  details?: Record<string, unknown>,
): { error: string; code: string; details?: Record<string, unknown> } {
  return {
    error,
    code,
    ...(details && { details }),
  };
}
