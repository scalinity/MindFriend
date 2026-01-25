/**
 * Shared validation and sanitization utilities for Mentorship Edge Functions
 * Provides PII detection, input sanitization, and data validation
 */

// PII Detection Patterns (per OWASP guidelines)
const PII_PATTERNS = {
  email: /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g,
  phone_us: /(\+?1)?[-.\s]?\(?[2-9]\d{2}\)?[-.\s]?\d{3}[-.\s]?\d{4}/g,
  phone_intl: /\+(?:[0-9] ?){6,14}[0-9]/g,
  ssn: /\b\d{3}-\d{2}-\d{4}\b/g,
  credit_card: /\b(?:\d{4}[-\s]?){3}\d{4}\b/g,
  zip_code: /\b\d{5}(?:-\d{4})?\b/g,
  ip_address: /\b(?:\d{1,3}\.){3}\d{1,3}\b/g,
};

// Allowed expertise/seeking areas (mental health topics)
const ALLOWED_TOPICS = [
  "anxiety",
  "depression",
  "stress",
  "sleep",
  "relationships",
  "work-life-balance",
  "self-esteem",
  "grief",
  "mindfulness",
  "coping-skills",
  "emotional-regulation",
  "career-guidance",
  "personal-growth",
  "trauma-recovery",
  "wellness",
];

/**
 * Detects PII in text
 * @param text Input text to scan
 * @returns Object with detected PII types and findings
 */
export function detectPII(text: string): {
  hasPII: boolean;
  types: string[];
  matches: Record<string, string[]>;
} {
  const matches: Record<string, string[]> = {};
  let detectedTypes: string[] = [];

  for (const [type, pattern] of Object.entries(PII_PATTERNS)) {
    const found = text.match(pattern);
    if (found && found.length > 0) {
      matches[type] = found;
      detectedTypes.push(type);
    }
  }

  return {
    hasPII: detectedTypes.length > 0,
    types: detectedTypes,
    matches,
  };
}

/**
 * Sanitizes input to prevent XSS
 * Uses HTML entity encoding (safer than regex filtering)
 * @param input Raw user input
 * @returns Sanitized string safe for storage and display
 */
export function sanitizeInput(input: string): string {
  if (!input || typeof input !== "string") return "";

  const entityMap: Record<string, string> = {
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
    "/": "&#x2F;",
  };

  return input.replace(/[&<>"'\/]/g, (char) => entityMap[char] || char);
}

/**
 * Validates expertise or seeking areas
 * @param topics Array of topics to validate
 * @returns { valid: boolean, invalidTopics: string[] }
 */
export function validateTopics(topics: unknown): {
  valid: boolean;
  invalidTopics: string[];
} {
  if (!Array.isArray(topics)) {
    return { valid: false, invalidTopics: [] };
  }

  const invalid = topics.filter(
    (t) => typeof t !== "string" || !ALLOWED_TOPICS.includes(t.toLowerCase())
  );

  return {
    valid: invalid.length === 0,
    invalidTopics: invalid as string[],
  };
}

/**
 * Validates introduction message
 * Checks for length, PII, and basic content quality
 * @param message Introduction message text
 * @returns { valid: boolean, errors: string[] }
 */
export function validateIntroductionMessage(message: unknown): {
  valid: boolean;
  errors: string[];
} {
  const errors: string[] = [];

  if (typeof message !== "string") {
    errors.push("Message must be a string");
    return { valid: false, errors };
  }

  const trimmed = message.trim();

  // Length validation
  if (trimmed.length < 10) {
    errors.push("Message must be at least 10 characters");
  }
  if (trimmed.length > 500) {
    errors.push("Message must be at most 500 characters");
  }

  // PII detection
  const piiCheck = detectPII(trimmed);
  if (piiCheck.hasPII) {
    errors.push(
      `Message contains sensitive information (${piiCheck.types.join(", ")})`
    );
  }

  // Block suspicious patterns
  const suspiciousPatterns = [
    /\b(click here|buy now|order now|limited offer|act fast)\b/i,
    /\b(crypto|bitcoin|investment|earn money|make $$)\b/i,
    /\b(hack|crack|cheat|exploit)\b/i,
  ];

  for (const pattern of suspiciousPatterns) {
    if (pattern.test(trimmed)) {
      errors.push("Message contains suspicious or promotional content");
      break;
    }
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

/**
 * Validates chat message content
 * Checks for length, rate limit compliance, and content quality
 * @param content Message content
 * @param isSystemRole Whether this is a system role message (different limits)
 * @returns { valid: boolean, errors: string[] }
 */
export function validateMessageContent(
  content: unknown,
  isSystemRole: boolean = false
): {
  valid: boolean;
  errors: string[];
} {
  const errors: string[] = [];

  if (typeof content !== "string") {
    errors.push("Message must be a string");
    return { valid: false, errors };
  }

  const trimmed = content.trim();

  // Length validation (system role messages can be longer)
  const minLength = 1;
  const maxLength = isSystemRole ? 5000 : 2000;

  if (trimmed.length < minLength) {
    errors.push("Message cannot be empty");
  }
  if (trimmed.length > maxLength) {
    errors.push(`Message must be at most ${maxLength} characters`);
  }

  // PII detection (stricter for non-system roles)
  const piiCheck = detectPII(trimmed);
  if (piiCheck.hasPII && !isSystemRole) {
    errors.push("Please don't share personal information in messages");
  }

  // Block excessive Unicode/emoji spam
  const emojiCount = (trimmed.match(/[\p{Emoji}]/gu) || []).length;
  if (emojiCount > 20) {
    errors.push("Message contains too many emojis");
  }

  // Block repeated characters (spam)
  if (/(.)\1{9,}/.test(trimmed)) {
    errors.push("Message contains excessive character repetition");
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

/**
 * Validates UUID format (RFC 4122 v4)
 * @param uuid UUID string to validate
 * @returns boolean True if valid UUID
 */
export function validateUUID(uuid: unknown): boolean {
  if (typeof uuid !== "string") return false;

  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  return uuidRegex.test(uuid);
}

/**
 * Validates pagination parameters
 * @param limit Items per page
 * @param offset Page offset
 * @returns { valid: boolean, errors: string[] }
 */
export function validatePagination(limit: unknown, offset: unknown): {
  valid: boolean;
  errors: string[];
  safeLimit: number;
  safeOffset: number;
} {
  const errors: string[] = [];
  let safeLimit = 20;
  let safeOffset = 0;

  // Validate limit
  if (typeof limit !== "number" || limit < 1 || limit > 100) {
    errors.push("Limit must be a number between 1 and 100");
  } else {
    safeLimit = Math.floor(limit);
  }

  // Validate offset
  if (typeof offset !== "number" || offset < 0 || offset > 10000) {
    errors.push("Offset must be a number between 0 and 10000");
  } else {
    safeOffset = Math.floor(offset);
  }

  return {
    valid: errors.length === 0,
    errors,
    safeLimit,
    safeOffset,
  };
}

/**
 * Validates language codes (ISO 639-1)
 * @param languages Array of language codes
 * @returns { valid: boolean, invalidLanguages: string[] }
 */
export function validateLanguages(languages: unknown): {
  valid: boolean;
  invalidLanguages: string[];
} {
  if (!Array.isArray(languages)) {
    return { valid: false, invalidLanguages: [] };
  }

  // ISO 639-1 language codes (common ones for MVP)
  const validLanguageCodes = [
    "en", // English
    "es", // Spanish
    "fr", // French
    "de", // German
    "it", // Italian
    "pt", // Portuguese
    "ja", // Japanese
    "ko", // Korean
    "zh", // Mandarin Chinese
    "ru", // Russian
    "ar", // Arabic
    "hi", // Hindi
  ];

  const invalid = languages.filter(
    (lang) =>
      typeof lang !== "string" || !validLanguageCodes.includes(lang.toLowerCase())
  );

  return {
    valid: invalid.length === 0,
    invalidLanguages: invalid as string[],
  };
}

/**
 * Validates availability hours per week
 * @param hours Number of hours available per week
 * @returns { valid: boolean, errors: string[] }
 */
export function validateAvailabilityHours(hours: unknown): {
  valid: boolean;
  errors: string[];
} {
  const errors: string[] = [];

  if (typeof hours !== "number") {
    errors.push("Hours must be a number");
    return { valid: false, errors };
  }

  if (hours < 0 || hours > 168) {
    // 168 = 24 * 7
    errors.push("Hours must be between 0 and 168 (24 hours per day)");
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

/**
 * Validates timezone offset string
 * @param timezone Timezone string (e.g., "America/New_York" or "+05:30")
 * @returns boolean True if valid timezone
 */
export function validateTimezone(timezone: unknown): boolean {
  if (typeof timezone !== "string") return false;

  // Check for IANA timezone format
  const ianatimezoneRegex = /^[A-Z][a-z]+\/[A-Z][a-z]+(?:\/[A-Za-z]+)?$/;
  if (ianatimezoneRegex.test(timezone)) return true;

  // Check for UTC offset format (+05:30, -08:00, etc)
  const utcOffsetRegex = /^[+-](?:[0-1][0-9]|2[0-3]):[0-5][0-9]$/;
  if (utcOffsetRegex.test(timezone)) return true;

  return false;
}
