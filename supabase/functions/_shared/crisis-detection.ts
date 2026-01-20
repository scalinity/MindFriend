/**
 * Multi-Language Crisis Detection
 *
 * Detects crisis keywords in user messages across multiple languages
 * with safety redundancy (always checks English keywords as fallback).
 *
 * Created by dev-pipeline on 2026-01-19
 */

/**
 * Crisis keywords by language
 * Professional translations for Spanish and Portuguese
 * Always check English keywords in addition to user's language for safety
 */
export const CRISIS_KEYWORDS: Record<string, string[]> = {
  en: [
    "kill myself",
    "want to die",
    "suicide",
    "end it all",
    "better off dead",
    "cant go on",
    "can't go on",
    "self harm",
    "hurt myself",
    "end my life",
    "no reason to live",
  ],
  es: [
    "matarme",
    "quiero morir",
    "suicidio",
    "acabar con todo",
    "mejor muerto",
    "mejor muerta",
    "no puedo más",
    "no puedo mas",
    "autolesión",
    "autolesion",
    "hacerme daño",
    "hacerme dano",
    "terminar mi vida",
    "sin razón para vivir",
    "sin razon para vivir",
  ],
  "pt-BR": [
    "me matar",
    "quero morrer",
    "suicídio",
    "suicidio",
    "acabar com tudo",
    "melhor morto",
    "melhor morta",
    "não aguento mais",
    "nao aguento mais",
    "autolesão",
    "autolesao",
    "me machucar",
    "terminar minha vida",
    "sem razão para viver",
    "sem razao para viver",
  ],
};

/**
 * Detect crisis keywords in a message
 *
 * @param message - The user's message to check
 * @param userLanguage - User's preferred language code (e.g., 'es', 'pt-BR')
 * @returns true if crisis keywords detected, false otherwise
 *
 * Safety note: Always checks both user language AND English keywords
 * to ensure no false negatives if user switches languages mid-conversation
 */
export function detectCrisis(message: string, userLanguage: string): boolean {
  const normalizedMessage = message.toLowerCase();

  // Get keywords for user's language
  const userLanguageKeywords = CRISIS_KEYWORDS[userLanguage] || [];

  // ALWAYS also check English keywords (safety redundancy)
  const englishKeywords = CRISIS_KEYWORDS["en"];

  // Combine both keyword sets
  const allKeywords = [...userLanguageKeywords, ...englishKeywords];

  // Check if any keyword is present
  return allKeywords.some((keyword) =>
    normalizedMessage.includes(keyword.toLowerCase()),
  );
}

/**
 * Get the matched crisis keyword (for logging/debugging)
 *
 * @param message - The user's message
 * @param userLanguage - User's preferred language code
 * @returns The matched keyword, or null if no match
 */
export function getMatchedKeyword(
  message: string,
  userLanguage: string,
): string | null {
  const normalizedMessage = message.toLowerCase();

  // Check user language keywords first
  const userLanguageKeywords = CRISIS_KEYWORDS[userLanguage] || [];
  for (const keyword of userLanguageKeywords) {
    if (normalizedMessage.includes(keyword.toLowerCase())) {
      return keyword;
    }
  }

  // Then check English keywords
  const englishKeywords = CRISIS_KEYWORDS["en"];
  for (const keyword of englishKeywords) {
    if (normalizedMessage.includes(keyword.toLowerCase())) {
      return keyword;
    }
  }

  return null;
}
