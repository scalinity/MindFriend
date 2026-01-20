// UUID validation utilities for MindFriend Edge Functions
// Prevents database errors and potential information leakage from malformed UUIDs

/**
 * UUID validation result
 */
export interface UuidValidation {
  /** Whether the UUID is valid */
  valid: boolean;
  /** Normalized UUID (lowercase) - null if invalid */
  normalized: string | null;
  /** Error message for invalid UUIDs */
  error?: string;
}

/**
 * Regex pattern for validating UUIDs (RFC 4122 compliant)
 * Matches format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
 * where x is a hex digit (0-9, a-f, A-F)
 */
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Validate a UUID string
 * Prevents database errors from malformed UUIDs and potential SQL-injection-like attacks
 *
 * @param uuid - The UUID to validate (can be null/undefined)
 * @param fieldName - Name of the field for error messages (e.g., "arcId", "userArcId")
 * @returns Validation result with normalized UUID or error details
 */
export function validateUuid(
  uuid: string | null | undefined,
  fieldName: string = "id",
): UuidValidation {
  // Check for empty/null/undefined
  if (!uuid || typeof uuid !== "string") {
    return {
      valid: false,
      normalized: null,
      error: `${fieldName} is required`,
    };
  }

  // Normalize: trim whitespace and convert to lowercase
  const normalized = uuid.trim().toLowerCase();

  // Check UUID format
  if (!UUID_PATTERN.test(normalized)) {
    return {
      valid: false,
      normalized: null,
      error: `${fieldName} must be a valid UUID`,
    };
  }

  // All checks passed
  return {
    valid: true,
    normalized: normalized,
  };
}

/**
 * Type guard to check if validation succeeded
 */
export function isValidUuid(
  result: UuidValidation,
): result is UuidValidation & { normalized: string } {
  return result.valid && result.normalized !== null;
}

/**
 * Validate multiple UUIDs at once
 * Returns the first validation error encountered, or success if all valid
 *
 * @param uuids - Object mapping field names to UUID values
 * @returns Validation result for the first invalid UUID, or success with all normalized UUIDs
 */
export function validateUuids(
  uuids: Record<string, string | null | undefined>,
): { valid: true; normalized: Record<string, string> } | { valid: false; error: string } {
  const normalized: Record<string, string> = {};

  for (const [fieldName, uuid] of Object.entries(uuids)) {
    const validation = validateUuid(uuid, fieldName);
    if (!validation.valid) {
      return { valid: false, error: validation.error || "Invalid UUID" };
    }
    normalized[fieldName] = validation.normalized!;
  }

  return { valid: true, normalized };
}
