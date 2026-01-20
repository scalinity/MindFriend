// Content Validation for AI-Generated Content
// Reuses crisis detection from existing crisis.ts and adds content-specific validation

import { detectCrisis, getMatchedCrisisKeyword } from "./crisis.ts";

export interface ContentValidationRequest {
  topic: string;
  contentType:
    | "sleep_story"
    | "meditation"
    | "breathing"
    | "grounding"
    | "mindfulness"
    | "cbt"
    | "journaling"
    | "affirmation";
  userInput?: string; // Optional user-provided prompt
  culturalContext?: string;
}

export interface ContentValidationResult {
  approved: boolean;
  reason?: string;
  flags: string[];
  safetyLevel: "safe" | "review_recommended" | "unsafe";
  suggestions?: string[];
}

// Inappropriate topics for mental health content generation
const INAPPROPRIATE_TOPICS = [
  // Violence
  "violence",
  "violent",
  "murder",
  "kill",
  "attack",
  "weapon",
  "gun",
  "knife",
  "blood",
  // Sexual content
  "sexual",
  "erotic",
  "porn",
  "explicit",
  "nude",
  // Substance abuse glorification
  "drug abuse",
  "get high",
  "substance abuse",
  "overdose",
  // Harmful behaviors
  "self-harm",
  "self harm",
  "cutting",
  "starve",
  "purge",
  "binge",
  // Discrimination
  "racist",
  "sexist",
  "homophobic",
  "transphobic",
  "discriminat",
  // Illegal activities
  "illegal",
  "crime",
  "steal",
  "fraud",
];

// Topics that require extra caution but are allowed with warnings
const SENSITIVE_TOPICS = [
  // Loss and grief
  "death",
  "dying",
  "grief",
  "funeral",
  "loss",
  "passed away",
  // Trauma
  "trauma",
  "abuse",
  "assault",
  // Mental health conditions
  "depression",
  "anxiety disorder",
  "ptsd",
  "bipolar",
  "schizophrenia",
  // Medical
  "hospital",
  "surgery",
  "illness",
  "cancer",
  "diagnosis",
  // Relationships
  "divorce",
  "breakup",
  "betrayal",
  "infidelity",
];

// Words to filter from generated content (stigmatizing language)
export const STIGMATIZING_TERMS = [
  "crazy",
  "insane",
  "psycho",
  "lunatic",
  "mental case",
  "nutcase",
  "retarded",
  "loony",
  "deranged",
  "maniac",
];

/**
 * Validate content request before generation
 */
export function validateContentRequest(
  request: ContentValidationRequest,
): ContentValidationResult {
  const flags: string[] = [];
  const suggestions: string[] = [];
  const combinedText =
    `${request.topic} ${request.userInput || ""}`.toLowerCase();

  // Check for crisis keywords first (highest priority)
  if (detectCrisis(combinedText)) {
    const matchedKeyword = getMatchedCrisisKeyword(combinedText);
    return {
      approved: false,
      reason: `Request contains crisis-related content. Please reach out for support.`,
      flags: ["crisis_keywords", matchedKeyword || "crisis"],
      safetyLevel: "unsafe",
      suggestions: [
        "If you're in crisis, please call 988 (Suicide & Crisis Lifeline)",
        "Text HOME to 741741 for Crisis Text Line",
      ],
    };
  }

  // Check for inappropriate topics
  for (const topic of INAPPROPRIATE_TOPICS) {
    if (combinedText.includes(topic)) {
      flags.push("inappropriate_topic");
      return {
        approved: false,
        reason: `Request contains inappropriate content that cannot be generated.`,
        flags: ["inappropriate_topic", topic],
        safetyLevel: "unsafe",
        suggestions: [
          "Try a different topic focused on wellbeing",
          "Consider topics like relaxation, gratitude, or mindfulness",
        ],
      };
    }
  }

  // Check for sensitive topics (allowed with warning)
  for (const topic of SENSITIVE_TOPICS) {
    if (combinedText.includes(topic)) {
      flags.push("sensitive_topic");
      suggestions.push(`Content may touch on sensitive topics (${topic})`);
    }
  }

  // Validate content type is appropriate
  if (!isContentTypeAppropriate(request.contentType, combinedText)) {
    flags.push("content_type_mismatch");
    suggestions.push(
      "Consider choosing a content type that better matches your needs",
    );
  }

  // Determine safety level based on flags
  let safetyLevel: "safe" | "review_recommended" | "unsafe" = "safe";
  if (flags.includes("sensitive_topic")) {
    safetyLevel = "review_recommended";
  }

  return {
    approved: true,
    flags,
    safetyLevel,
    suggestions: suggestions.length > 0 ? suggestions : undefined,
  };
}

/**
 * Validate generated content before delivery
 */
export function validateGeneratedContent(
  content: string,
): ContentValidationResult {
  const flags: string[] = [];
  const suggestions: string[] = [];
  const lowerContent = content.toLowerCase();

  // Check for crisis keywords in generated content
  if (detectCrisis(lowerContent)) {
    const matchedKeyword = getMatchedCrisisKeyword(lowerContent);
    return {
      approved: false,
      reason: "Generated content contains crisis-related language",
      flags: ["crisis_keywords", matchedKeyword || "crisis"],
      safetyLevel: "unsafe",
    };
  }

  // Check for stigmatizing language
  for (const term of STIGMATIZING_TERMS) {
    if (lowerContent.includes(term)) {
      flags.push("stigmatizing_language");
      suggestions.push(
        `Content contains potentially stigmatizing term: "${term}"`,
      );
    }
  }

  // Check for inappropriate content that may have slipped through
  for (const topic of INAPPROPRIATE_TOPICS) {
    if (lowerContent.includes(topic)) {
      return {
        approved: false,
        reason: "Generated content contains inappropriate material",
        flags: ["inappropriate_content", topic],
        safetyLevel: "unsafe",
      };
    }
  }

  // Check for therapeutic appropriateness
  const therapeuticIssues = checkTherapeuticAppropriateness(content);
  if (therapeuticIssues.length > 0) {
    flags.push(...therapeuticIssues);
    suggestions.push("Content may benefit from clinical review");
  }

  // Determine safety level
  let safetyLevel: "safe" | "review_recommended" | "unsafe" = "safe";
  if (flags.length > 0) {
    safetyLevel = "review_recommended";
  }

  return {
    approved: true,
    flags,
    safetyLevel,
    suggestions: suggestions.length > 0 ? suggestions : undefined,
  };
}

/**
 * Check if content type matches the request
 */
function isContentTypeAppropriate(
  contentType: ContentValidationRequest["contentType"],
  topic: string,
): boolean {
  // CBT exercises shouldn't be used for sleep
  if (contentType === "cbt" && topic.includes("sleep")) {
    return false;
  }

  // Sleep stories shouldn't be energizing
  if (
    contentType === "sleep_story" &&
    (topic.includes("energiz") || topic.includes("motivat"))
  ) {
    return false;
  }

  return true;
}

/**
 * Check for therapeutic appropriateness issues
 */
function checkTherapeuticAppropriateness(content: string): string[] {
  const issues: string[] = [];
  const lowerContent = content.toLowerCase();

  // Check for directive language instead of observing language
  const directivePhrases = [
    "you must",
    "you should",
    "you need to",
    "don't think",
  ];
  for (const phrase of directivePhrases) {
    if (lowerContent.includes(phrase)) {
      issues.push("directive_language");
      break;
    }
  }

  // Check for potentially harmful advice
  const harmfulAdvice = [
    "stop taking medication",
    "don't see your doctor",
    "ignore your therapist",
    "skip your treatment",
  ];
  for (const advice of harmfulAdvice) {
    if (lowerContent.includes(advice)) {
      issues.push("harmful_advice");
      break;
    }
  }

  // Check for overpromising
  const overpromises = [
    "will cure",
    "will fix",
    "guaranteed to",
    "100% effective",
    "instant relief",
    "permanent solution",
  ];
  for (const promise of overpromises) {
    if (lowerContent.includes(promise)) {
      issues.push("overpromising");
      break;
    }
  }

  return issues;
}

/**
 * Get trigger warnings for content
 */
export function detectTriggerWarnings(content: string): string[] {
  const warnings: string[] = [];
  const lowerContent = content.toLowerCase();

  const triggerCategories: Record<string, string[]> = {
    loss_grief: ["death", "dying", "funeral", "loss", "passed away", "grief"],
    medical: ["hospital", "surgery", "illness", "diagnosis", "treatment"],
    trauma: ["trauma", "abuse", "assault", "attack"],
    relationships: ["divorce", "breakup", "betrayal", "abandonment"],
    body_image: ["weight", "eating", "body", "appearance"],
  };

  for (const [category, keywords] of Object.entries(triggerCategories)) {
    for (const keyword of keywords) {
      if (lowerContent.includes(keyword)) {
        warnings.push(category);
        break; // Only add each category once
      }
    }
  }

  return warnings;
}

/**
 * Generate content disclaimer
 */
export function getContentDisclaimer(): string {
  return "This is AI-generated content designed for relaxation and wellness. It is not a substitute for professional mental health treatment. If you are in crisis, please call 988 or text HOME to 741741.";
}
