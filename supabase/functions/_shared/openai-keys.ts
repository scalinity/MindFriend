// OpenAI keys are split by purpose so each has its own usage limits and billing.
// Image generation (generate-art, generate-profile-picture) keeps OPENAI_API_KEY;
// every other OpenAI call (chat, text, realtime voice, transcription, moderation)
// reads VOICE_AND_NONIMAGE_OPENAI_API_KEY. tests/openai_key_split_test.ts pins this.
export const OPENAI_IMAGE_KEY_ENV = "OPENAI_API_KEY";
export const OPENAI_NONIMAGE_KEY_ENV = "VOICE_AND_NONIMAGE_OPENAI_API_KEY";

export function openAINonImageKey(): string | undefined {
  return Deno.env.get(OPENAI_NONIMAGE_KEY_ENV)?.trim() || undefined;
}
