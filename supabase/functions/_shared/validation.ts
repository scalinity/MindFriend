// Invite code validation utilities for MindFriend
// Prevents database enumeration attacks and invalid queries

/**
 * Validation result for invite codes
 */
export interface InviteCodeValidation {
  /** Whether the code is valid */
  valid: boolean;
  /** Normalized code (uppercase, trimmed) - null if invalid */
  normalized: string | null;
  /** Error message for invalid codes */
  error?: string;
  /** Error code for programmatic handling */
  code?:
    | "INVALID_FORMAT"
    | "INVALID_LENGTH"
    | "INVALID_CHARACTERS"
    | "EMPTY_CODE";
}

/**
 * Valid characters for invite codes (matches generateInviteCode charset)
 * Excludes confusing characters: I, L, O, 0, 1
 * Excludes vowels: A, E, I, O, U (except when used in generated codes)
 */
export const INVITE_CODE_CHARSET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

/**
 * Regex pattern for validating invite codes
 * Matches: 6-12 characters from the valid charset (A-Z, no confusing chars, 2-9 only)
 * Note: Uses [A-Z0-9] for broader acceptance (includes I,O,0,1) for backward compatibility
 * with manually-entered codes, even though generation excludes those chars
 */
const INVITE_CODE_PATTERN = /^[A-Z0-9]{6,12}$/;

/**
 * Validate and normalize an invite code
 * Prevents injection attacks by validating format before any database operations
 *
 * @param code - The invite code to validate (can be null/undefined)
 * @param options - Validation options
 * @returns Validation result with normalized code or error details
 */
export function validateInviteCode(
  code: string | null | undefined,
  options?: {
    minLength?: number; // default: 6
    maxLength?: number; // default: 12
  },
): InviteCodeValidation {
  // Check for empty/null/undefined
  if (!code || typeof code !== "string") {
    return {
      valid: false,
      normalized: null,
      error: "Invite code is required",
      code: "EMPTY_CODE",
    };
  }

  // Normalize: trim whitespace and convert to uppercase
  const normalized = code.trim().toUpperCase();

  // Check length constraints
  const minLength = options?.minLength ?? 6;
  const maxLength = options?.maxLength ?? 12;

  if (normalized.length < minLength || normalized.length > maxLength) {
    return {
      valid: false,
      normalized: null,
      error: `Invite code must be ${minLength}-${maxLength} characters`,
      code: "INVALID_LENGTH",
    };
  }

  // Check character set: only alphanumeric, no special characters
  if (!INVITE_CODE_PATTERN.test(normalized)) {
    return {
      valid: false,
      normalized: null,
      error:
        "Invite code contains invalid characters (only letters and numbers allowed)",
      code: "INVALID_CHARACTERS",
    };
  }

  // All checks passed
  return {
    valid: true,
    normalized: normalized,
  };
}

/**
 * Validate a family/circle invite code (8 characters)
 * These are typically generated for family groups and circles
 */
export function validateFamilyInviteCode(
  code: string | null | undefined,
): InviteCodeValidation {
  return validateInviteCode(code, {
    minLength: 6, // Allow 6-8 for backward compatibility with buddy codes used in families
    maxLength: 12, // Allow up to 12 for future flexibility
  });
}

/**
 * Validate a buddy invite code (6 characters)
 * These are shorter codes generated for buddy/friend invitations
 */
export function validateBuddyInviteCode(
  code: string | null | undefined,
): InviteCodeValidation {
  return validateInviteCode(code, {
    minLength: 6,
    maxLength: 6, // Strict: exactly 6 characters
  });
}

/**
 * Validate a circle invite code (8 characters)
 * Same format as family codes
 */
export function validateCircleInviteCode(
  code: string | null | undefined,
): InviteCodeValidation {
  return validateFamilyInviteCode(code);
}

/**
 * Type guard to check if validation succeeded
 */
export function isValidInviteCode(
  result: InviteCodeValidation,
): result is InviteCodeValidation & { normalized: string } {
  return result.valid && result.normalized !== null;
}
