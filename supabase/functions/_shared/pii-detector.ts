/**
 * PII Detection utility for Community Wisdom Engine
 * Prevents personally identifiable information from being stored in contributions
 */

// PII Detection Patterns (OWASP guidelines)
const PII_PATTERNS: Record<string, RegExp> = {
  email: /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g,
  phone_us: /(\+?1)?[-.\s]?\(?[2-9]\d{2}\)?[-.\s]?\d{3}[-.\s]?\d{4}/g,
  phone_intl: /\+(?:[0-9] ?){6,14}[0-9]/g,
  ssn: /\b\d{3}-\d{2}-\d{4}\b/g,
  credit_card: /\b(?:\d{4}[-\s]?){3}\d{4}\b/g,
  ip_address: /\b(?:\d{1,3}\.){3}\d{1,3}\b/g,
};

// Suspicious content patterns (spam, scam, harmful)
const SUSPICIOUS_PATTERNS: RegExp[] = [
  /\b(click here|buy now|order now|limited offer|act fast)\b/i,
  /\b(crypto|bitcoin|investment|earn money|make \$\$)\b/i,
  /\b(hack|crack|cheat|exploit)\b/i,
];

export interface PIIDetectionResult {
  hasPII: boolean;
  types: string[];
  matches: Record<string, string[]>;
}

export interface ContentValidationResult {
  valid: boolean;
  errors: string[];
  hasPII: boolean;
  piiTypes: string[];
}

/**
 * Detects PII in text
 * @param text Input text to scan
 * @returns PIIDetectionResult with detected PII types and matches
 */
export function detectPII(text: string): PIIDetectionResult {
  const matches: Record<string, string[]> = {};
  const detectedTypes: string[] = [];

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
 * Validates contribution data for PII and suspicious content
 * @param data JSONB data to validate
 * @returns ContentValidationResult with validation status and errors
 */
export function validateContributionData(
  data: Record<string, unknown>,
): ContentValidationResult {
  const errors: string[] = [];
  let hasPII = false;
  let piiTypes: string[] = [];

  // Convert data to string for PII scanning
  const dataString = JSON.stringify(data);

  // Check for PII
  const piiResult = detectPII(dataString);
  if (piiResult.hasPII) {
    hasPII = true;
    piiTypes = piiResult.types;
    errors.push(
      `Contribution contains personal information: ${piiResult.types.join(", ")}`,
    );
  }

  // Check for suspicious patterns in string values
  for (const [key, value] of Object.entries(data)) {
    if (typeof value === "string") {
      for (const pattern of SUSPICIOUS_PATTERNS) {
        if (pattern.test(value)) {
          errors.push(`Field '${key}' contains suspicious content`);
          break;
        }
      }
    }
  }

  return {
    valid: errors.length === 0,
    errors,
    hasPII,
    piiTypes,
  };
}

/**
 * Validates strategy text for PII, length, and content quality
 * @param strategyText Strategy text to validate
 * @returns ContentValidationResult
 */
export function validateStrategyText(
  strategyText: string,
): ContentValidationResult {
  const errors: string[] = [];
  let hasPII = false;
  let piiTypes: string[] = [];

  // Length validation
  if (strategyText.length < 10) {
    errors.push("Strategy must be at least 10 characters");
  }
  if (strategyText.length > 500) {
    errors.push("Strategy must be 500 characters or less");
  }

  // PII detection
  const piiResult = detectPII(strategyText);
  if (piiResult.hasPII) {
    hasPII = true;
    piiTypes = piiResult.types;
    errors.push(
      `Please remove personal information: ${piiResult.types.join(", ")}`,
    );
  }

  // Suspicious content check
  for (const pattern of SUSPICIOUS_PATTERNS) {
    if (pattern.test(strategyText)) {
      errors.push("Strategy contains suspicious or promotional content");
      break;
    }
  }

  // Block excessive character repetition (spam)
  if (/(.)\1{9,}/.test(strategyText)) {
    errors.push("Strategy contains excessive character repetition");
  }

  // Block excessive emoji spam
  const emojiCount = (strategyText.match(/[\p{Emoji}]/gu) || []).length;
  if (emojiCount > 10) {
    errors.push("Strategy contains too many emojis");
  }

  return {
    valid: errors.length === 0,
    errors,
    hasPII,
    piiTypes,
  };
}

/**
 * Valid contribution types for data_json schema validation
 */
export const VALID_CONTRIBUTION_TYPES = [
  "mood_pattern",
  "exercise_effectiveness",
  "pathway_progress",
  "strategy_success",
] as const;

export type ContributionType = (typeof VALID_CONTRIBUTION_TYPES)[number];

/**
 * Schema definitions for each contribution type
 */
export const CONTRIBUTION_SCHEMAS: Record<
  ContributionType,
  { required: string[]; optional: string[] }
> = {
  mood_pattern: {
    required: ["moodScore"],
    optional: ["timeOfDay", "emotion"],
  },
  exercise_effectiveness: {
    required: ["exerciseType", "effectivenessRating"],
    optional: [],
  },
  pathway_progress: {
    required: ["pathwayType", "phaseNumber"],
    optional: [],
  },
  strategy_success: {
    required: ["category"],
    optional: ["strategyId"],
  },
};

/**
 * Validates contribution data against schema for its type
 * @param type Contribution type
 * @param data Data to validate
 * @returns ContentValidationResult
 */
export function validateContributionSchema(
  type: string,
  data: Record<string, unknown>,
): ContentValidationResult {
  const errors: string[] = [];

  if (!VALID_CONTRIBUTION_TYPES.includes(type as ContributionType)) {
    return {
      valid: false,
      errors: [`Invalid contribution type: ${type}`],
      hasPII: false,
      piiTypes: [],
    };
  }

  const schema = CONTRIBUTION_SCHEMAS[type as ContributionType];

  // Check required fields
  for (const field of schema.required) {
    if (!(field in data) || data[field] === null || data[field] === undefined) {
      errors.push(`Missing required field: ${field}`);
    }
  }

  // Validate specific field constraints
  if (type === "mood_pattern") {
    const moodScore = data.moodScore as number;
    if (typeof moodScore !== "number" || moodScore < 1 || moodScore > 5) {
      errors.push("moodScore must be between 1 and 5");
    }

    const timeOfDay = data.timeOfDay as string;
    if (
      timeOfDay &&
      !["morning", "afternoon", "evening", "night"].includes(timeOfDay)
    ) {
      errors.push("timeOfDay must be morning, afternoon, evening, or night");
    }
  }

  if (type === "exercise_effectiveness") {
    const rating = data.effectivenessRating as number;
    if (typeof rating !== "number" || rating < 1 || rating > 5) {
      errors.push("effectivenessRating must be between 1 and 5");
    }
  }

  if (type === "pathway_progress") {
    const phaseNumber = data.phaseNumber as number;
    if (
      typeof phaseNumber !== "number" ||
      phaseNumber < 1 ||
      phaseNumber > 10
    ) {
      errors.push("phaseNumber must be between 1 and 10");
    }
  }

  // Run PII validation on the data
  const piiResult = validateContributionData(data);
  if (!piiResult.valid) {
    errors.push(...piiResult.errors);
  }

  return {
    valid: errors.length === 0,
    errors,
    hasPII: piiResult.hasPII,
    piiTypes: piiResult.piiTypes,
  };
}

/**
 * Valid strategy categories
 */
export const VALID_CATEGORIES = [
  "anxiety",
  "depression",
  "stress",
  "grief",
  "anger",
  "loneliness",
  "overwhelm",
  "sleep",
  "motivation",
  "general",
] as const;

export type StrategyCategory = (typeof VALID_CATEGORIES)[number];

/**
 * Validates strategy category
 * @param category Category to validate
 * @returns boolean True if valid category
 */
export function isValidCategory(
  category: string,
): category is StrategyCategory {
  return VALID_CATEGORIES.includes(category as StrategyCategory);
}
