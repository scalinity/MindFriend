/**
 * Reframe Template Engine
 *
 * Selects and populates reframe templates with context from user messages
 */

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";

/**
 * Logging only: a database error object or message can quote row text, and a thrown error's
 * message can quote a response body. Log a PostgREST/PostgreSQL code or a fixed category, never
 * the object, message or stack.
 */
function failureCode(error: unknown): string {
  const code = typeof error === "object" && error !== null
    ? (error as { code?: unknown }).code
    : undefined;
  return typeof code === "string" && /^[A-Za-z0-9_]{1,16}$/.test(code)
    ? code
    : error instanceof Error
    ? "exception"
    : "unknown";
}

export interface ReframeResult {
  reframeText: string;
  educationalContent: string;
  socraticQuestions: string[];
  distortionName: string;
  shortDescription: string;
}

/**
 * Get reframe suggestion for a detected distortion
 *
 * @param supabase Supabase client (service role for database access)
 * @param distortionCode Distortion code (e.g., 'AON', 'CAT')
 * @param originalMessage User's original message
 * @param language User's language preference ('en', 'es', 'pt-BR')
 * @returns Reframe result with populated templates
 */
export async function getReframe(
  supabase: SupabaseClient,
  distortionCode: string,
  originalMessage: string,
  language: string = "en",
): Promise<ReframeResult | null> {
  try {
    // Fetch distortion with education in a single query using JOIN
    const { data: distortionData, error: distortionError } = await supabase
      .from("cognitive_distortions")
      .select(`
        id,
        name,
        short_description,
        full_description,
        distortion_education!inner (
          locale,
          name_translated,
          short_description_translated,
          full_description_translated,
          reframe_templates_translated,
          questions_translated
        )
      `)
      .eq("code", distortionCode)
      .eq("distortion_education.locale", language)
      .single();

    if (distortionError || !distortionData) {
      console.error(`Distortion not found: ${distortionCode}`, failureCode(distortionError));
      return null;
    }

    // Extract education data (will be array due to JOIN)
    const educationData = Array.isArray(distortionData.distortion_education)
      ? distortionData.distortion_education[0]
      : distortionData.distortion_education;

    let reframeTemplates: string[];
    let questions: string[];
    let name: string;
    let shortDesc: string;
    let fullDesc: string;

    if (!educationData) {
      // Fallback to English if translation not found
      console.warn(
        `Translation not found for ${distortionCode} in ${language}, falling back to English`,
      );

      const { data: englishData, error: englishError } = await supabase
        .from("distortion_education")
        .select(
          "name_translated, short_description_translated, full_description_translated, reframe_templates_translated, questions_translated",
        )
        .eq("distortion_id", distortionData.id)
        .eq("locale", "en")
        .single();

      if (englishError || !englishData) {
        console.error("English fallback also failed", failureCode(englishError));
        return null;
      }

      reframeTemplates = englishData.reframe_templates_translated || [];
      questions = englishData.questions_translated || [];
      name = englishData.name_translated;
      shortDesc = englishData.short_description_translated;
      fullDesc = englishData.full_description_translated;
    } else {
      reframeTemplates = educationData.reframe_templates_translated || [];
      questions = educationData.questions_translated || [];
      name = educationData.name_translated;
      shortDesc = educationData.short_description_translated;
      fullDesc = educationData.full_description_translated;
    }

    // Select a reframe template (use first one for now; could randomize in future)
    if (reframeTemplates.length === 0) {
      console.error(`No reframe templates found for ${distortionCode}`);
      return null;
    }

    const selectedTemplate = reframeTemplates[0];

    // Perform variable substitution
    // Templates support: {original}, {alternative}, {question}
    // For MVP, we use the template as-is (no complex substitution)
    // Future: Could extract distorted phrase and suggest alternative
    const reframeText = selectedTemplate;

    return {
      reframeText,
      educationalContent: fullDesc,
      socraticQuestions: questions.slice(0, 3), // Return top 3 questions
      distortionName: name,
      shortDescription: shortDesc,
    };
  } catch (error) {
    console.error("Error fetching reframe:", failureCode(error));
    return null;
  }
}

/**
 * Extract distorted phrase from message (helper for future enhancements)
 *
 * @param message User message
 * @param distortionCode Detected distortion
 * @returns Extracted phrase or null
 */
export function extractDistortedPhrase(
  message: string,
  distortionCode: string,
): string | null {
  // TODO: Implement phrase extraction logic
  // For now, return first sentence
  const sentences = message.split(/[.!?]/).filter((s) => s.trim().length > 0);
  return sentences[0]?.trim() || null;
}
