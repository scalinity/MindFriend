import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

// IMPORTANT: When bumping this version, also ship a migration that updates the
// `policy_version <= N` predicate in the ai_consents_self_insert and
// ai_consents_self_update RLS policies. Otherwise client writes to the new version
// will be rejected.
export const CURRENT_POLICY_VERSION = 1;

export type AIFeature =
  | "chat"
  | "journal_ai"
  | "voice_journal_ai"
  | "image_gen"
  | "insights"
  | "tts_voice";

export const ALL_AI_FEATURES: readonly AIFeature[] = [
  "chat",
  "journal_ai",
  "voice_journal_ai",
  "image_gen",
  "insights",
  "tts_voice",
] as const;

export class ConsentRequiredError extends Error {
  constructor(public readonly feature: AIFeature) {
    super(`AI consent required for feature: ${feature}`);
    this.name = "ConsentRequiredError";
  }
}

export class ConsentCheckFailedError extends Error {
  constructor(public readonly feature: AIFeature, public override readonly cause: unknown) {
    super(`AI consent check failed for feature: ${feature}`);
    this.name = "ConsentCheckFailedError";
  }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type UntypedSupabaseClient = SupabaseClient<any, "public", any>;

/**
 * Throws ConsentRequiredError unless the user has an `ai_consents` row for
 * the given feature with state=granted and policy_version >= CURRENT.
 *
 * Caller responsibility: pass the *admin* (service-role) client so this
 * works regardless of the per-request RLS context.
 */
export async function requireAIConsent(
  supabase: UntypedSupabaseClient,
  userId: string,
  feature: AIFeature,
): Promise<void> {
  const { data, error } = await supabase
    .from("ai_consents")
    .select("state, policy_version")
    .eq("user_id", userId)
    .eq("feature", feature)
    .maybeSingle();

  if (error) {
    console.error(`[ai-consent] lookup error for feature "${feature}":`, error);
    throw new ConsentCheckFailedError(feature, error);
  }
  if (!data) throw new ConsentRequiredError(feature);
  if (data.state !== "granted") throw new ConsentRequiredError(feature);
  if (data.policy_version < CURRENT_POLICY_VERSION) {
    throw new ConsentRequiredError(feature);
  }
}

/**
 * Build the standard 403 response shape edge functions return when consent
 * is missing. iOS pattern-matches on `code === "ai_consent_required"`.
 */
export function aiConsentErrorResponse(
  err: ConsentRequiredError,
  corsHeaders: Record<string, string>,
): Response {
  return new Response(
    JSON.stringify({ code: "ai_consent_required", feature: err.feature }),
    {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
}
