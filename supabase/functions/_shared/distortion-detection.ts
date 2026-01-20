/**
 * Cognitive Distortion Detection Engine
 *
 * Keyword-based detection with weighted confidence scoring
 * Supports EN/ES/PT-BR languages
 */

export interface DistortionDetectionResult {
  distortionCode: string;
  confidence: number;
  matchedKeywords: string[];
  evidence: string;
}

export interface DistortionKeywords {
  code: string;
  keywords: {
    [key: string]: number; // keyword -> weight
  };
  phraseMultipliers: {
    pattern: RegExp;
    multiplier: number;
  }[];
}

// Distortion keyword patterns with weights
const DISTORTION_PATTERNS_EN: DistortionKeywords[] = [
  {
    code: "AON",
    keywords: {
      always: 1.0,
      never: 1.0,
      everyone: 0.9,
      "no one": 0.9,
      everything: 0.8,
      nothing: 0.8,
      completely: 0.7,
      totally: 0.7,
    },
    phraseMultipliers: [
      { pattern: /\b(always|never)\b/i, multiplier: 1.5 },
      { pattern: /\b(everyone|no one)\b/i, multiplier: 1.4 },
    ],
  },
  {
    code: "CAT",
    keywords: {
      disaster: 1.0,
      terrible: 0.8,
      awful: 0.8,
      horrible: 0.8,
      worst: 1.0,
      "everything will": 0.7,
      "fall apart": 1.2,
      ruined: 1.0,
      doomed: 1.0,
    },
    phraseMultipliers: [
      { pattern: /\bworst\s+(case|scenario)\b/i, multiplier: 1.6 },
      { pattern: /\bfall\s+apart\b/i, multiplier: 1.5 },
    ],
  },
  {
    code: "MIND",
    keywords: {
      "they think": 1.0,
      "must think": 1.2,
      "probably think": 1.2,
      judging: 1.0,
      "they know": 0.8,
      "must know": 1.0,
    },
    phraseMultipliers: [
      { pattern: /\bthey\s+(must|probably)\s+think\b/i, multiplier: 1.5 },
    ],
  },
  {
    code: "FORT",
    keywords: {
      "will never": 1.2,
      "won't work": 1.0,
      "going to fail": 1.2,
      "i know": 0.7,
      "will definitely": 0.8,
    },
    phraseMultipliers: [
      { pattern: /\bwill\s+never\b/i, multiplier: 1.5 },
      { pattern: /\bi\s+know\s+(i|it)\s+will\b/i, multiplier: 1.4 },
    ],
  },
  {
    code: "LAB",
    keywords: {
      "i'm a": 0.9,
      "i'm such a": 1.2,
      loser: 1.0,
      idiot: 1.0,
      failure: 1.0,
      worthless: 1.2,
      stupid: 0.9,
    },
    phraseMultipliers: [
      { pattern: /\bi'm\s+(a|an|such\s+a)\s+\w+\b/i, multiplier: 1.4 },
    ],
  },
  {
    code: "SHO",
    keywords: {
      should: 1.0,
      must: 1.0,
      ought: 0.9,
      "have to": 0.8,
      supposed: 0.8,
    },
    phraseMultipliers: [
      { pattern: /\b(should|must|ought)\b/i, multiplier: 1.3 },
    ],
  },
  {
    code: "EMF",
    keywords: {
      "i feel": 1.0,
      "feels like": 0.9,
      "must be": 0.8,
    },
    phraseMultipliers: [
      {
        pattern: /\bi\s+feel\s+\w+,?\s+so\s+(i|it)\s+must\b/i,
        multiplier: 1.6,
      },
    ],
  },
  {
    code: "MINS",
    keywords: {
      "doesn't count": 1.2,
      "doesn't matter": 0.9,
      "just luck": 1.0,
      fluke: 1.0,
    },
    phraseMultipliers: [
      { pattern: /\b(doesn't|don't)\s+count\b/i, multiplier: 1.5 },
    ],
  },
  {
    code: "BLAME",
    keywords: {
      "their fault": 1.2,
      "all my fault": 1.2,
      "because of them": 1.0,
      "if they": 0.8,
      "they made me": 1.0,
    },
    phraseMultipliers: [
      { pattern: /\ball\s+(my|their)\s+fault\b/i, multiplier: 1.5 },
    ],
  },
  {
    code: "COMP",
    keywords: {
      "everyone else": 1.0,
      "better than": 0.8,
      "worse than": 0.8,
    },
    phraseMultipliers: [{ pattern: /\beveryone\s+else\b/i, multiplier: 1.4 }],
  },
  {
    code: "RG",
    keywords: {
      "shouldn't have": 1.2,
      "if only": 1.2,
      "should have": 1.0,
      regret: 1.0,
      "wish i": 0.8,
    },
    phraseMultipliers: [
      { pattern: /\bif\s+only\b/i, multiplier: 1.5 },
      { pattern: /\bshould(n\'t)?\s+have\b/i, multiplier: 1.3 },
    ],
  },
  {
    code: "WHAT",
    keywords: {
      "what if": 1.5,
      might: 0.6,
      could: 0.5,
    },
    phraseMultipliers: [{ pattern: /\bwhat\s+if\b/i, multiplier: 1.7 }],
  },
];

/**
 * Detects cognitive distortions in a message
 *
 * @param message User message text
 * @param language Language code ('en', 'es', 'pt-BR')
 * @param sensitivityThreshold Minimum confidence to return result (0.0-1.0)
 * @returns Detection result or null if no distortion detected above threshold
 */
export function detectDistortion(
  message: string,
  language: string = "en",
  sensitivityThreshold: number = 0.7,
): DistortionDetectionResult | null {
  // Normalize message
  const normalized = message.toLowerCase().trim();

  // Skip very short messages (< 5 words)
  if (normalized.split(/\s+/).length < 5) {
    return null;
  }

  // TODO: Support ES/PT patterns (for now, fallback to EN)
  const patterns =
    language === "en" ? DISTORTION_PATTERNS_EN : DISTORTION_PATTERNS_EN;

  // Calculate confidence for each distortion type
  const scores: { code: string; confidence: number; keywords: string[] }[] = [];

  for (const pattern of patterns) {
    const matchedKeywords: string[] = [];
    let totalWeight = 0;
    let matchedWeight = 0;

    // Check keyword matches
    for (const [keyword, weight] of Object.entries(pattern.keywords)) {
      totalWeight += weight;
      if (normalized.includes(keyword.toLowerCase())) {
        matchedKeywords.push(keyword);
        matchedWeight += weight;
      }
    }

    if (matchedWeight === 0) {
      continue; // No matches for this distortion
    }

    // Calculate base confidence: matched weight / total weight
    let confidence = matchedWeight / totalWeight;

    // Apply phrase multipliers
    for (const { pattern: regex, multiplier } of pattern.phraseMultipliers) {
      if (regex.test(normalized)) {
        confidence *= multiplier;
      }
    }

    // Cap confidence at 1.0
    confidence = Math.min(confidence, 1.0);

    scores.push({
      code: pattern.code,
      confidence,
      keywords: matchedKeywords,
    });
  }

  // No detections
  if (scores.length === 0) {
    return null;
  }

  // Sort by confidence descending
  scores.sort((a, b) => b.confidence - a.confidence);

  const top = scores[0];

  // Filter by sensitivity threshold
  if (top.confidence < sensitivityThreshold) {
    return null;
  }

  return {
    distortionCode: top.code,
    confidence: top.confidence,
    matchedKeywords: top.keywords,
    evidence: `Matched keywords: ${top.keywords.join(", ")}`,
  };
}

/**
 * Get sensitivity threshold based on user's sensitivity level setting
 *
 * @param level Sensitivity level ('minimal', 'balanced', 'frequent')
 * @returns Confidence threshold
 */
export function getSensitivityThreshold(level: string): number {
  switch (level) {
    case "minimal":
      return 0.85; // Show intervention for top 20% of detections
    case "balanced":
      return 0.7; // Show intervention for top 50% of detections (default)
    case "frequent":
      return 0.55; // Show intervention for top 80% of detections
    default:
      return 0.7;
  }
}
