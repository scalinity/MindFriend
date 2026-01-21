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

// Spanish (ES) patterns with culturally appropriate keywords
const DISTORTION_PATTERNS_ES: DistortionKeywords[] = [
  {
    code: "AON",
    keywords: {
      siempre: 1.0,
      nunca: 1.0,
      todos: 0.9,
      nadie: 0.9,
      todo: 0.8,
      nada: 0.8,
      completamente: 0.7,
      totalmente: 0.7,
      jamás: 1.0,
    },
    phraseMultipliers: [
      { pattern: /\b(siempre|nunca|jamás)\b/i, multiplier: 1.5 },
      { pattern: /\b(todos|nadie)\b/i, multiplier: 1.4 },
    ],
  },
  {
    code: "CAT",
    keywords: {
      desastre: 1.0,
      terrible: 0.8,
      horrible: 0.8,
      espantoso: 0.8,
      peor: 1.0,
      "todo va a": 0.7,
      "se va a arruinar": 1.2,
      arruinado: 1.0,
      condenado: 1.0,
      "caer todo": 1.2,
    },
    phraseMultipliers: [
      { pattern: /\bpeor\s+(caso|escenario)\b/i, multiplier: 1.6 },
      { pattern: /\b(arruinar|destruir)\b/i, multiplier: 1.5 },
    ],
  },
  {
    code: "MIND",
    keywords: {
      "piensan que": 1.0,
      "deben pensar": 1.2,
      "probablemente piensan": 1.2,
      juzgando: 1.0,
      "deben saber": 1.0,
      "seguro piensan": 1.2,
    },
    phraseMultipliers: [
      { pattern: /\b(deben|probablemente)\s+pensar\b/i, multiplier: 1.5 },
    ],
  },
  {
    code: "FORT",
    keywords: {
      "nunca voy a": 1.2,
      "no va a funcionar": 1.0,
      "va a fracasar": 1.2,
      "sé que": 0.7,
      "va a salir mal": 1.0,
      "definitivamente va": 0.8,
    },
    phraseMultipliers: [
      { pattern: /\bnunca\s+(voy|vas|va)\s+a\b/i, multiplier: 1.5 },
      { pattern: /\bsé\s+que\s+(va|voy)\b/i, multiplier: 1.4 },
    ],
  },
  {
    code: "LAB",
    keywords: {
      "soy un": 0.9,
      "soy una": 0.9,
      perdedor: 1.0,
      idiota: 1.0,
      fracaso: 1.0,
      "no valgo": 1.2,
      estúpido: 0.9,
      inútil: 1.0,
    },
    phraseMultipliers: [
      { pattern: /\bsoy\s+(un|una)\s+\w+\b/i, multiplier: 1.4 },
      { pattern: /\bno\s+valgo\b/i, multiplier: 1.5 },
    ],
  },
  {
    code: "SHO",
    keywords: {
      debería: 1.0,
      debo: 1.0,
      debemos: 0.9,
      "tengo que": 0.8,
      "se supone": 0.8,
      obligado: 0.7,
    },
    phraseMultipliers: [
      { pattern: /\b(debería|debo|debemos)\b/i, multiplier: 1.3 },
    ],
  },
  {
    code: "EMF",
    keywords: {
      "me siento": 1.0,
      "se siente como": 0.9,
      "debe ser": 0.8,
      "tiene que ser": 0.8,
    },
    phraseMultipliers: [
      {
        pattern: /\bme\s+siento\s+\w+,?\s+entonces\s+(debe|tiene que)\b/i,
        multiplier: 1.6,
      },
    ],
  },
  {
    code: "MINS",
    keywords: {
      "no cuenta": 1.2,
      "no importa": 0.9,
      "solo suerte": 1.0,
      casualidad: 1.0,
      "fue suerte": 1.0,
    },
    phraseMultipliers: [
      { pattern: /\bno\s+cuenta\b/i, multiplier: 1.5 },
    ],
  },
  {
    code: "BLAME",
    keywords: {
      "culpa de ellos": 1.2,
      "toda mi culpa": 1.2,
      "por culpa de": 1.0,
      "si ellos": 0.8,
      "me hicieron": 1.0,
      "ellos me obligaron": 1.2,
    },
    phraseMultipliers: [
      { pattern: /\btoda\s+(mi|su)\s+culpa\b/i, multiplier: 1.5 },
    ],
  },
  {
    code: "COMP",
    keywords: {
      "todos los demás": 1.0,
      "mejor que": 0.8,
      "peor que": 0.8,
      "los demás": 0.9,
    },
    phraseMultipliers: [
      { pattern: /\btodos\s+los\s+demás\b/i, multiplier: 1.4 },
    ],
  },
  {
    code: "RG",
    keywords: {
      "no debería haber": 1.2,
      "si solo": 1.2,
      "debería haber": 1.0,
      lamento: 1.0,
      ojalá: 0.8,
      "me arrepiento": 1.2,
    },
    phraseMultipliers: [
      { pattern: /\bsi\s+solo\b/i, multiplier: 1.5 },
      { pattern: /\bdebería\s+haber\b/i, multiplier: 1.3 },
    ],
  },
  {
    code: "WHAT",
    keywords: {
      "qué tal si": 1.5,
      "qué pasa si": 1.5,
      "y si": 1.5,
      podría: 0.6,
      quizás: 0.5,
    },
    phraseMultipliers: [
      { pattern: /\b(qué|y)\s+(tal\s+)?si\b/i, multiplier: 1.7 },
    ],
  },
];

// Portuguese (PT-BR) patterns with culturally appropriate keywords
const DISTORTION_PATTERNS_PT_BR: DistortionKeywords[] = [
  {
    code: "AON",
    keywords: {
      sempre: 1.0,
      nunca: 1.0,
      todos: 0.9,
      ninguém: 0.9,
      tudo: 0.8,
      nada: 0.8,
      completamente: 0.7,
      totalmente: 0.7,
      jamais: 1.0,
    },
    phraseMultipliers: [
      { pattern: /\b(sempre|nunca|jamais)\b/i, multiplier: 1.5 },
      { pattern: /\b(todos|ninguém)\b/i, multiplier: 1.4 },
    ],
  },
  {
    code: "CAT",
    keywords: {
      desastre: 1.0,
      terrível: 0.8,
      horrível: 0.8,
      péssimo: 0.8,
      pior: 1.0,
      "tudo vai": 0.7,
      "vai arruinar": 1.2,
      arruinado: 1.0,
      condenado: 1.0,
      "vai dar errado": 1.2,
    },
    phraseMultipliers: [
      { pattern: /\bpior\s+(caso|cenário)\b/i, multiplier: 1.6 },
      { pattern: /\b(arruinar|destruir)\b/i, multiplier: 1.5 },
    ],
  },
  {
    code: "MIND",
    keywords: {
      "pensam que": 1.0,
      "devem pensar": 1.2,
      "provavelmente pensam": 1.2,
      julgando: 1.0,
      "devem saber": 1.0,
      "com certeza pensam": 1.2,
    },
    phraseMultipliers: [
      { pattern: /\b(devem|provavelmente)\s+pensar\b/i, multiplier: 1.5 },
    ],
  },
  {
    code: "FORT",
    keywords: {
      "nunca vou": 1.2,
      "não vai funcionar": 1.0,
      "vai fracassar": 1.2,
      "sei que": 0.7,
      "vai dar errado": 1.0,
      "definitivamente vai": 0.8,
    },
    phraseMultipliers: [
      { pattern: /\bnunca\s+(vou|vai)\b/i, multiplier: 1.5 },
      { pattern: /\bsei\s+que\s+(vai|vou)\b/i, multiplier: 1.4 },
    ],
  },
  {
    code: "LAB",
    keywords: {
      "sou um": 0.9,
      "sou uma": 0.9,
      perdedor: 1.0,
      idiota: 1.0,
      fracasso: 1.0,
      "não valho": 1.2,
      estúpido: 0.9,
      inútil: 1.0,
    },
    phraseMultipliers: [
      { pattern: /\bsou\s+(um|uma)\s+\w+\b/i, multiplier: 1.4 },
      { pattern: /\bnão\s+valho\b/i, multiplier: 1.5 },
    ],
  },
  {
    code: "SHO",
    keywords: {
      deveria: 1.0,
      devo: 1.0,
      devemos: 0.9,
      "tenho que": 0.8,
      "é suposto": 0.8,
      obrigado: 0.7,
    },
    phraseMultipliers: [
      { pattern: /\b(deveria|devo|devemos)\b/i, multiplier: 1.3 },
    ],
  },
  {
    code: "EMF",
    keywords: {
      "me sinto": 1.0,
      "sente como": 0.9,
      "deve ser": 0.8,
      "tem que ser": 0.8,
    },
    phraseMultipliers: [
      {
        pattern: /\bme\s+sinto\s+\w+,?\s+então\s+(deve|tem que)\b/i,
        multiplier: 1.6,
      },
    ],
  },
  {
    code: "MINS",
    keywords: {
      "não conta": 1.2,
      "não importa": 0.9,
      "só sorte": 1.0,
      acaso: 1.0,
      "foi sorte": 1.0,
    },
    phraseMultipliers: [
      { pattern: /\bnão\s+conta\b/i, multiplier: 1.5 },
    ],
  },
  {
    code: "BLAME",
    keywords: {
      "culpa deles": 1.2,
      "toda minha culpa": 1.2,
      "por culpa de": 1.0,
      "se eles": 0.8,
      "me fizeram": 1.0,
      "eles me obrigaram": 1.2,
    },
    phraseMultipliers: [
      { pattern: /\btoda\s+(minha|sua)\s+culpa\b/i, multiplier: 1.5 },
    ],
  },
  {
    code: "COMP",
    keywords: {
      "todos os outros": 1.0,
      "melhor que": 0.8,
      "pior que": 0.8,
      "os outros": 0.9,
    },
    phraseMultipliers: [
      { pattern: /\btodos\s+os\s+outros\b/i, multiplier: 1.4 },
    ],
  },
  {
    code: "RG",
    keywords: {
      "não deveria ter": 1.2,
      "se apenas": 1.2,
      "deveria ter": 1.0,
      lamento: 1.0,
      queria: 0.8,
      "me arrependo": 1.2,
    },
    phraseMultipliers: [
      { pattern: /\bse\s+apenas\b/i, multiplier: 1.5 },
      { pattern: /\bdeveria\s+ter\b/i, multiplier: 1.3 },
    ],
  },
  {
    code: "WHAT",
    keywords: {
      "e se": 1.5,
      "o que se": 1.5,
      poderia: 0.6,
      talvez: 0.5,
    },
    phraseMultipliers: [
      { pattern: /\be\s+se\b/i, multiplier: 1.7 },
    ],
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

  // Select pattern set based on language
  const patterns =
    language === "es" ? DISTORTION_PATTERNS_ES :
    language === "pt-BR" ? DISTORTION_PATTERNS_PT_BR :
    DISTORTION_PATTERNS_EN;

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
